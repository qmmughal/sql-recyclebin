/* =============================================================================
   SQL RecycleBin — v0.1.0
   A recycle bin for SQL Server: capture every DELETE and UPDATE, query it back,
   undo it with one command.

   Requirements : SQL Server 2017+ (any edition, including Express)
   Install      : run this whole script in the target database
   Quick start  :
        EXEC rb.Enable  @Table = 'dbo.Orders';
        -- ...someone runs a bad DELETE/UPDATE...
        EXEC rb.Deleted @Table = 'dbo.Orders';          -- see what was lost
        EXEC rb.UndoLast @Table = 'dbo.Orders';         -- put it back

   License      : PolyForm Noncommercial 1.0.0 — free for personal and
                  noncommercial use. Commercial use requires a license:
                  qaiser@92logics.com
   ============================================================================= */

SET NOCOUNT ON;
GO

IF SCHEMA_ID(N'rb') IS NULL
    EXEC (N'CREATE SCHEMA rb AUTHORIZATION dbo;');
GO

/* ---------------------------------------------------------------------------
   1. Storage
   --------------------------------------------------------------------------- */
IF OBJECT_ID(N'rb.ChangeLog') IS NULL
BEGIN
    CREATE TABLE rb.ChangeLog
    (
        ChangeId    BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_rb_ChangeLog PRIMARY KEY,
        SchemaName  SYSNAME        NOT NULL,
        TableName   SYSNAME        NOT NULL,
        Operation   CHAR(1)        NOT NULL,             -- 'D' = delete, 'U' = update
        TxId        BIGINT         NOT NULL,             -- groups rows of one statement/transaction
        KeyValues   NVARCHAR(1000) NULL,                 -- primary key as JSON
        RowBefore   NVARCHAR(MAX)  NOT NULL,             -- full row as JSON (before change)
        RowAfter    NVARCHAR(MAX)  NULL,                 -- full row as JSON (after update)
        ChangedBy   SYSNAME        NOT NULL,
        AppName     NVARCHAR(128)  NULL,
        HostName    NVARCHAR(128)  NULL,
        ChangedAt   DATETIME2(3)   NOT NULL CONSTRAINT DF_rb_ChangeLog_At DEFAULT SYSUTCDATETIME(),
        Restored    BIT            NOT NULL CONSTRAINT DF_rb_ChangeLog_Restored DEFAULT (0)
    );

    CREATE INDEX IX_rb_ChangeLog_Table
        ON rb.ChangeLog (SchemaName, TableName, Operation, ChangeId DESC)
        INCLUDE (ChangedAt, Restored);

    CREATE INDEX IX_rb_ChangeLog_Tx
        ON rb.ChangeLog (TxId) INCLUDE (SchemaName, TableName);

    CREATE INDEX IX_rb_ChangeLog_At
        ON rb.ChangeLog (ChangedAt);

    -- Page compression is supported in all editions since 2016 SP1; ignore failure on older builds.
    BEGIN TRY
        ALTER TABLE rb.ChangeLog REBUILD WITH (DATA_COMPRESSION = PAGE);
    END TRY
    BEGIN CATCH
    END CATCH
END
GO

IF OBJECT_ID(N'rb.EnabledTables') IS NULL
BEGIN
    CREATE TABLE rb.EnabledTables
    (
        SchemaName  SYSNAME  NOT NULL,
        TableName   SYSNAME  NOT NULL,
        TriggerName SYSNAME  NOT NULL,
        EnabledAt   DATETIME2(0) NOT NULL CONSTRAINT DF_rb_Enabled_At DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_rb_EnabledTables PRIMARY KEY (SchemaName, TableName)
    );
END
GO

IF OBJECT_ID(N'rb.Config') IS NULL
BEGIN
    CREATE TABLE rb.Config (ConfigKey SYSNAME PRIMARY KEY, ConfigValue NVARCHAR(200) NOT NULL);
    INSERT rb.Config VALUES (N'KeepDays', N'14');
END
GO

/* ---------------------------------------------------------------------------
   2. Internal helper: OPENJSON WITH-clause + column metadata for a table
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE rb.internal_GetTableMeta
    @ObjectId     INT,
    @WithCols     NVARCHAR(MAX) OUTPUT,   -- OPENJSON WITH (...) column definitions
    @InsertCols   NVARCHAR(MAX) OUTPUT,   -- insertable column list (no computed/rowversion)
    @UpdateSet    NVARCHAR(MAX) OUTPUT,   -- SET t.[c]=src.[c] list (no PK/identity/computed/rowversion)
    @PkJoin       NVARCHAR(MAX) OUTPUT,   -- t.[pk]=src.[pk] AND ...
    @HasIdentity  BIT           OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pk TABLE (col SYSNAME PRIMARY KEY);
    INSERT @pk (col)
    SELECT c.name
    FROM sys.indexes ix
    JOIN sys.index_columns ic ON ic.object_id = ix.object_id AND ic.index_id = ix.index_id
    JOIN sys.columns c        ON c.object_id  = ic.object_id AND c.column_id = ic.column_id
    WHERE ix.object_id = @ObjectId AND ix.is_primary_key = 1;

    SELECT
        @WithCols = STRING_AGG(CAST(
            QUOTENAME(c.name) + N' ' +
            CASE
                WHEN t.name IN (N'nvarchar', N'nchar')
                    THEN t.name + N'(' + CASE WHEN c.max_length = -1 THEN N'max' ELSE CAST(c.max_length / 2 AS NVARCHAR(10)) END + N')'
                WHEN t.name IN (N'varchar', N'char', N'varbinary', N'binary')
                    THEN t.name + N'(' + CASE WHEN c.max_length = -1 THEN N'max' ELSE CAST(c.max_length AS NVARCHAR(10)) END + N')'
                WHEN t.name IN (N'decimal', N'numeric')
                    THEN t.name + N'(' + CAST(c.precision AS NVARCHAR(10)) + N',' + CAST(c.scale AS NVARCHAR(10)) + N')'
                WHEN t.name IN (N'datetime2', N'time', N'datetimeoffset')
                    THEN t.name + N'(' + CAST(c.scale AS NVARCHAR(10)) + N')'
                WHEN t.name IN (N'geography', N'geometry', N'hierarchyid', N'xml', N'sql_variant')
                    THEN N'nvarchar(max)'   -- captured as text; restored as text-castable
                ELSE t.name
            END
            + N' ''$."' + REPLACE(c.name, N'''', N'''''') + N'"'''
            AS NVARCHAR(MAX)), N', ')
    FROM sys.columns c
    JOIN sys.types t ON t.user_type_id = c.user_type_id
    WHERE c.object_id = @ObjectId
      AND c.is_computed = 0
      AND t.name NOT IN (N'timestamp', N'rowversion');

    SELECT @InsertCols = STRING_AGG(CAST(QUOTENAME(c.name) AS NVARCHAR(MAX)), N', ')
    FROM sys.columns c
    JOIN sys.types t ON t.user_type_id = c.user_type_id
    WHERE c.object_id = @ObjectId
      AND c.is_computed = 0
      AND t.name NOT IN (N'timestamp', N'rowversion');

    SELECT @UpdateSet = STRING_AGG(CAST(N't.' + QUOTENAME(c.name) + N' = src.' + QUOTENAME(c.name) AS NVARCHAR(MAX)), N', ')
    FROM sys.columns c
    JOIN sys.types t ON t.user_type_id = c.user_type_id
    WHERE c.object_id = @ObjectId
      AND c.is_computed = 0
      AND c.is_identity = 0
      AND t.name NOT IN (N'timestamp', N'rowversion')
      AND c.name NOT IN (SELECT col FROM @pk);

    SELECT @PkJoin = STRING_AGG(CAST(N't.' + QUOTENAME(col) + N' = src.' + QUOTENAME(col) AS NVARCHAR(MAX)), N' AND ')
    FROM @pk;

    SELECT @HasIdentity = CASE WHEN EXISTS
        (SELECT 1 FROM sys.columns WHERE object_id = @ObjectId AND is_identity = 1) THEN 1 ELSE 0 END;
END
GO

/* ---------------------------------------------------------------------------
   3. rb.Enable / rb.Disable — turn capture on/off per table
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE rb.Enable
    @Table SYSNAME          -- two-part name, e.g. 'dbo.Orders'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @objId INT = OBJECT_ID(@Table, N'U');
    IF @objId IS NULL
    BEGIN
        RAISERROR(N'rb.Enable: table %s not found (use a two-part name like dbo.Orders).', 16, 1, @Table);
        RETURN;
    END

    DECLARE @schema SYSNAME = OBJECT_SCHEMA_NAME(@objId),
            @name   SYSNAME = OBJECT_NAME(@objId);

    IF @schema = N'rb'
    BEGIN
        RAISERROR(N'rb.Enable: cannot enable capture on rb internal tables.', 16, 1);
        RETURN;
    END

    /* Primary key is required — it is how updates pair before/after and how undo targets rows. */
    DECLARE @pk TABLE (col SYSNAME, ord INT);
    INSERT @pk (col, ord)
    SELECT c.name, ic.key_ordinal
    FROM sys.indexes ix
    JOIN sys.index_columns ic ON ic.object_id = ix.object_id AND ic.index_id = ix.index_id
    JOIN sys.columns c        ON c.object_id  = ic.object_id AND c.column_id = ic.column_id
    WHERE ix.object_id = @objId AND ix.is_primary_key = 1;

    IF NOT EXISTS (SELECT 1 FROM @pk)
    BEGIN
        RAISERROR(N'rb.Enable: %s has no primary key. A primary key is required in v1.', 16, 1, @Table);
        RETURN;
    END

    DECLARE @pkJson NVARCHAR(MAX) =
        (SELECT STRING_AGG(CAST(N'd.' + QUOTENAME(col) + N' AS ' + QUOTENAME(col) AS NVARCHAR(MAX)), N', ')
                WITHIN GROUP (ORDER BY ord) FROM @pk);
    DECLARE @joinCond NVARCHAR(MAX) =
        (SELECT STRING_AGG(CAST(N'd.' + QUOTENAME(col) + N' = i.' + QUOTENAME(col) AS NVARCHAR(MAX)), N' AND ')
                WITHIN GROUP (ORDER BY ord) FROM @pk);

    DECLARE @trg SYSNAME = N'rb_trg_' + @name;

    DECLARE @sql NVARCHAR(MAX) = N'
CREATE OR ALTER TRIGGER ' + QUOTENAME(@schema) + N'.' + QUOTENAME(@trg) + N'
ON ' + QUOTENAME(@schema) + N'.' + QUOTENAME(@name) + N'
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    IF ISNULL(TRY_CAST(SESSION_CONTEXT(N''rb_bypass'') AS INT), 0) = 1 RETURN;

    DECLARE @op CHAR(1) = CASE WHEN EXISTS (SELECT 1 FROM inserted) THEN ''U'' ELSE ''D'' END;

    INSERT rb.ChangeLog
        (SchemaName, TableName, Operation, TxId, KeyValues, RowBefore, RowAfter, ChangedBy, AppName, HostName)
    SELECT
        N''' + REPLACE(@schema, N'''', N'''''') + N''',
        N''' + REPLACE(@name,   N'''', N'''''') + N''',
        @op,
        CURRENT_TRANSACTION_ID(),
        (SELECT ' + @pkJson + N' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES),
        CASE WHEN @op = ''U''
             THEN (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES) END,
        ORIGINAL_LOGIN(), APP_NAME(), HOST_NAME()
    FROM deleted d
    LEFT JOIN inserted i ON ' + @joinCond + N';
END';

    EXEC sys.sp_executesql @sql;

    IF NOT EXISTS (SELECT 1 FROM rb.EnabledTables WHERE SchemaName = @schema AND TableName = @name)
        INSERT rb.EnabledTables (SchemaName, TableName, TriggerName) VALUES (@schema, @name, @trg);
    ELSE
        UPDATE rb.EnabledTables SET TriggerName = @trg WHERE SchemaName = @schema AND TableName = @name;

    PRINT N'rb: capture enabled on ' + QUOTENAME(@schema) + N'.' + QUOTENAME(@name) + N'.';
END
GO

CREATE OR ALTER PROCEDURE rb.Disable
    @Table SYSNAME
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @objId INT = OBJECT_ID(@Table, N'U');
    IF @objId IS NULL BEGIN RAISERROR(N'rb.Disable: table %s not found.', 16, 1, @Table); RETURN; END

    DECLARE @schema SYSNAME = OBJECT_SCHEMA_NAME(@objId),
            @name   SYSNAME = OBJECT_NAME(@objId),
            @trg    SYSNAME;

    SELECT @trg = TriggerName FROM rb.EnabledTables WHERE SchemaName = @schema AND TableName = @name;
    IF @trg IS NULL BEGIN PRINT N'rb: capture was not enabled on this table.'; RETURN; END

    DECLARE @sql NVARCHAR(MAX) =
        N'DROP TRIGGER IF EXISTS ' + QUOTENAME(@schema) + N'.' + QUOTENAME(@trg) + N';';
    EXEC sys.sp_executesql @sql;

    DELETE rb.EnabledTables WHERE SchemaName = @schema AND TableName = @name;
    PRINT N'rb: capture disabled on ' + QUOTENAME(@schema) + N'.' + QUOTENAME(@name) + N'.';
END
GO

/* ---------------------------------------------------------------------------
   4. Bypass switch — let ETL / bulk maintenance skip capture for this session
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE rb.BypassOn  AS EXEC sys.sp_set_session_context @key = N'rb_bypass', @value = 1;
GO
CREATE OR ALTER PROCEDURE rb.BypassOff AS EXEC sys.sp_set_session_context @key = N'rb_bypass', @value = 0;
GO

/* ---------------------------------------------------------------------------
   5. Retrieval — see what was deleted / updated
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE rb.Deleted
    @Table SYSNAME,
    @Top   INT     = 10,
    @Since DATETIME2(3) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @objId INT = OBJECT_ID(@Table, N'U');
    IF @objId IS NULL BEGIN RAISERROR(N'rb.Deleted: table %s not found.', 16, 1, @Table); RETURN; END

    DECLARE @schema SYSNAME = OBJECT_SCHEMA_NAME(@objId),
            @name   SYSNAME = OBJECT_NAME(@objId);

    DECLARE @withCols NVARCHAR(MAX), @ic NVARCHAR(MAX), @us NVARCHAR(MAX), @pj NVARCHAR(MAX);
    DECLARE @hasId BIT;
    EXEC rb.internal_GetTableMeta @objId, @withCols OUTPUT, @ic OUTPUT, @us OUTPUT, @pj OUTPUT, @hasId OUTPUT;

    DECLARE @sql NVARCHAR(MAX) = N'
SELECT TOP (@Top)
    l.ChangeId, l.ChangedAt, l.ChangedBy, l.AppName, j.*
FROM rb.ChangeLog l
CROSS APPLY OPENJSON(l.RowBefore) WITH (' + @withCols + N') j
WHERE l.SchemaName = @s AND l.TableName = @t
  AND l.Operation = ''D'' AND l.Restored = 0
  AND (@Since IS NULL OR l.ChangedAt >= @Since)
ORDER BY l.ChangeId DESC;';

    EXEC sys.sp_executesql @sql,
        N'@Top INT, @s SYSNAME, @t SYSNAME, @Since DATETIME2(3)',
        @Top = @Top, @s = @schema, @t = @name, @Since = @Since;
END
GO

CREATE OR ALTER PROCEDURE rb.Updated
    @Table SYSNAME,
    @Top   INT     = 10,
    @Since DATETIME2(3) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @objId INT = OBJECT_ID(@Table, N'U');
    IF @objId IS NULL BEGIN RAISERROR(N'rb.Updated: table %s not found.', 16, 1, @Table); RETURN; END

    SELECT TOP (@Top)
        l.ChangeId, l.ChangedAt, l.ChangedBy, l.AppName,
        l.KeyValues, l.RowBefore, l.RowAfter
    FROM rb.ChangeLog l
    WHERE l.SchemaName = OBJECT_SCHEMA_NAME(@objId)
      AND l.TableName  = OBJECT_NAME(@objId)
      AND l.Operation  = 'U' AND l.Restored = 0
      AND (@Since IS NULL OR l.ChangedAt >= @Since)
    ORDER BY l.ChangeId DESC;
END
GO

/* ---------------------------------------------------------------------------
   6. Undo — restore deleted rows / revert updates
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE rb.UndoTransaction
    @Table SYSNAME,
    @TxId  BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @objId INT = OBJECT_ID(@Table, N'U');
    IF @objId IS NULL BEGIN RAISERROR(N'rb.UndoTransaction: table %s not found.', 16, 1, @Table); RETURN; END

    DECLARE @schema SYSNAME = OBJECT_SCHEMA_NAME(@objId),
            @name   SYSNAME = OBJECT_NAME(@objId),
            @full   NVARCHAR(300);
    SET @full = QUOTENAME(@schema) + N'.' + QUOTENAME(@name);

    DECLARE @withCols NVARCHAR(MAX), @insertCols NVARCHAR(MAX),
            @updateSet NVARCHAR(MAX), @pkJoin NVARCHAR(MAX);
    DECLARE @hasIdentity BIT;
    EXEC rb.internal_GetTableMeta @objId,
        @withCols OUTPUT, @insertCols OUTPUT, @updateSet OUTPUT, @pkJoin OUTPUT, @hasIdentity OUTPUT;

    IF @pkJoin IS NULL
    BEGIN
        RAISERROR(N'rb.UndoTransaction: %s has no primary key; cannot undo safely.', 16, 1, @Table);
        RETURN;
    END

    DECLARE @delRows NVARCHAR(MAX), @updRows NVARCHAR(MAX);
    DECLARE @delIds  NVARCHAR(MAX), @updIds  NVARCHAR(MAX);

    SELECT
        @delRows = N'[' + STRING_AGG(CAST(RowBefore AS NVARCHAR(MAX)), N',') + N']',
        @delIds  = STRING_AGG(CAST(ChangeId AS NVARCHAR(MAX)), N',')
    FROM rb.ChangeLog
    WHERE TxId = @TxId AND SchemaName = @schema AND TableName = @name
      AND Operation = 'D' AND Restored = 0;

    SELECT
        @updRows = N'[' + STRING_AGG(CAST(RowBefore AS NVARCHAR(MAX)), N',') + N']',
        @updIds  = STRING_AGG(CAST(ChangeId AS NVARCHAR(MAX)), N',')
    FROM rb.ChangeLog
    WHERE TxId = @TxId AND SchemaName = @schema AND TableName = @name
      AND Operation = 'U' AND Restored = 0;

    IF @delRows IS NULL AND @updRows IS NULL
    BEGIN
        PRINT N'rb: nothing to undo for this transaction (already restored, or wrong TxId).';
        RETURN;
    END

    DECLARE @sql NVARCHAR(MAX);
    DECLARE @restoredDeletes INT = 0, @revertedUpdates INT = 0;

    BEGIN TRAN;
        /* Do not let the rb trigger log the undo itself */
        EXEC rb.BypassOn;

        /* 6a. Re-insert deleted rows (skip PK collisions instead of failing) */
        IF @delRows IS NOT NULL
        BEGIN
            SET @sql =
                CASE WHEN @hasIdentity = 1
                     THEN N'SET IDENTITY_INSERT ' + @full + N' ON; ' ELSE N'' END + N'
INSERT ' + @full + N' (' + @insertCols + N')
SELECT ' + @insertCols + N'
FROM OPENJSON(@rows) WITH (' + @withCols + N') AS src
WHERE NOT EXISTS (SELECT 1 FROM ' + @full + N' AS t WHERE ' + @pkJoin + N');
SET @cnt = @@ROWCOUNT;' +
                CASE WHEN @hasIdentity = 1
                     THEN N' SET IDENTITY_INSERT ' + @full + N' OFF;' ELSE N'' END;

            EXEC sys.sp_executesql @sql,
                N'@rows NVARCHAR(MAX), @cnt INT OUTPUT',
                @rows = @delRows, @cnt = @restoredDeletes OUTPUT;

            SET @sql = N'UPDATE rb.ChangeLog SET Restored = 1 WHERE ChangeId IN (' + @delIds + N');';
            EXEC sys.sp_executesql @sql;
        END

        /* 6b. Revert updated rows to their before-values */
        IF @updRows IS NOT NULL AND @updateSet IS NOT NULL
        BEGIN
            SET @sql = N'
UPDATE t SET ' + @updateSet + N'
FROM ' + @full + N' AS t
JOIN OPENJSON(@rows) WITH (' + @withCols + N') AS src ON ' + @pkJoin + N';
SET @cnt = @@ROWCOUNT;';

            EXEC sys.sp_executesql @sql,
                N'@rows NVARCHAR(MAX), @cnt INT OUTPUT',
                @rows = @updRows, @cnt = @revertedUpdates OUTPUT;

            SET @sql = N'UPDATE rb.ChangeLog SET Restored = 1 WHERE ChangeId IN (' + @updIds + N');';
            EXEC sys.sp_executesql @sql;
        END

        EXEC rb.BypassOff;
    COMMIT;

    PRINT N'rb: restored ' + CAST(@restoredDeletes AS NVARCHAR(20)) + N' deleted row(s), reverted '
        + CAST(@revertedUpdates AS NVARCHAR(20)) + N' update(s) on ' + @full + N'.';
END
GO

CREATE OR ALTER PROCEDURE rb.UndoLast
    @Table SYSNAME
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @objId INT = OBJECT_ID(@Table, N'U');
    IF @objId IS NULL BEGIN RAISERROR(N'rb.UndoLast: table %s not found.', 16, 1, @Table); RETURN; END

    DECLARE @TxId BIGINT;
    SELECT TOP (1) @TxId = TxId
    FROM rb.ChangeLog
    WHERE SchemaName = OBJECT_SCHEMA_NAME(@objId)
      AND TableName  = OBJECT_NAME(@objId)
      AND Restored = 0
    ORDER BY ChangeId DESC;

    IF @TxId IS NULL BEGIN PRINT N'rb: nothing to undo for this table.'; RETURN; END

    EXEC rb.UndoTransaction @Table = @Table, @TxId = @TxId;
END
GO

CREATE OR ALTER PROCEDURE rb.Restore
    @Table SYSNAME,
    @Since DATETIME2(3)
AS
BEGIN
    /* Undo every captured transaction on @Table since @Since, newest first. */
    SET NOCOUNT ON;

    DECLARE @objId INT = OBJECT_ID(@Table, N'U');
    IF @objId IS NULL BEGIN RAISERROR(N'rb.Restore: table %s not found.', 16, 1, @Table); RETURN; END

    DECLARE @tx TABLE (TxId BIGINT PRIMARY KEY, LastChange BIGINT);
    INSERT @tx (TxId, LastChange)
    SELECT TxId, MAX(ChangeId)
    FROM rb.ChangeLog
    WHERE SchemaName = OBJECT_SCHEMA_NAME(@objId)
      AND TableName  = OBJECT_NAME(@objId)
      AND Restored = 0
      AND ChangedAt >= @Since
    GROUP BY TxId;

    DECLARE @TxId BIGINT;
    WHILE EXISTS (SELECT 1 FROM @tx)
    BEGIN
        SELECT TOP (1) @TxId = TxId FROM @tx ORDER BY LastChange DESC;
        EXEC rb.UndoTransaction @Table = @Table, @TxId = @TxId;
        DELETE @tx WHERE TxId = @TxId;
    END
END
GO

/* ---------------------------------------------------------------------------
   7. Housekeeping
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE rb.Cleanup
    @KeepDays INT = NULL          -- default from rb.Config
AS
BEGIN
    SET NOCOUNT ON;

    IF @KeepDays IS NULL
        SELECT @KeepDays = TRY_CAST(ConfigValue AS INT) FROM rb.Config WHERE ConfigKey = N'KeepDays';
    SET @KeepDays = ISNULL(@KeepDays, 14);

    DECLARE @cutoff DATETIME2(3) = DATEADD(DAY, -@KeepDays, SYSUTCDATETIME());
    DECLARE @batch INT = 50000, @rows INT = 1, @total BIGINT = 0;

    WHILE @rows > 0
    BEGIN
        DELETE TOP (@batch) FROM rb.ChangeLog WHERE ChangedAt < @cutoff;
        SET @rows = @@ROWCOUNT;
        SET @total += @rows;
    END

    PRINT N'rb: cleanup removed ' + CAST(@total AS NVARCHAR(20)) + N' row(s) older than '
        + CAST(@KeepDays AS NVARCHAR(10)) + N' day(s).';
END
GO

CREATE OR ALTER PROCEDURE rb.Status
AS
BEGIN
    SET NOCOUNT ON;

    SELECT e.SchemaName, e.TableName, e.EnabledAt,
           Captured = (SELECT COUNT_BIG(*) FROM rb.ChangeLog l
                       WHERE l.SchemaName = e.SchemaName AND l.TableName = e.TableName),
           PendingRestore = (SELECT COUNT_BIG(*) FROM rb.ChangeLog l
                             WHERE l.SchemaName = e.SchemaName AND l.TableName = e.TableName
                               AND l.Restored = 0)
    FROM rb.EnabledTables e
    ORDER BY e.SchemaName, e.TableName;

    SELECT StoreSizeMB = CAST(SUM(a.total_pages) * 8 / 1024.0 AS DECIMAL(18,1))
    FROM sys.partitions p
    JOIN sys.allocation_units a ON a.container_id = p.partition_id
    WHERE p.object_id = OBJECT_ID(N'rb.ChangeLog');
END
GO

PRINT N'SQL RecycleBin v0.1.0 installed. Try: EXEC rb.Enable @Table = ''dbo.YourTable'';';
GO
