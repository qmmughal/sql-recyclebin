/* =============================================================================
   SQL RecycleBin — uninstall
   Removes all rb triggers, procedures, tables, and the rb schema.
   WARNING: this permanently deletes the captured change history.
   ============================================================================= */

SET NOCOUNT ON;

/* 1. Drop capture triggers on every enabled table */
DECLARE @sql NVARCHAR(MAX) = N'';
SELECT @sql += N'DROP TRIGGER IF EXISTS ' + QUOTENAME(SchemaName) + N'.' + QUOTENAME(TriggerName) + N';' + CHAR(10)
FROM rb.EnabledTables;
EXEC sys.sp_executesql @sql;

/* 2. Drop procedures */
DROP PROCEDURE IF EXISTS rb.Enable, rb.Disable, rb.Deleted, rb.Updated,
    rb.UndoLast, rb.UndoTransaction, rb.Restore, rb.Cleanup, rb.Status,
    rb.BypassOn, rb.BypassOff, rb.internal_GetTableMeta;

/* 3. Drop tables */
DROP TABLE IF EXISTS rb.ChangeLog, rb.EnabledTables, rb.Config;

/* 4. Drop schema */
DROP SCHEMA IF EXISTS rb;

PRINT N'SQL RecycleBin removed.';
