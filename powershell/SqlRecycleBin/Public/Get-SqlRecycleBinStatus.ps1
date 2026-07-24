function Get-SqlRecycleBinStatus {
    <#
    .SYNOPSIS
        Returns enabled tables, captured/pending counts, and change-log store size.
    .DESCRIPTION
        Runs the same two queries as rb.Status, as two separate calls rather than one
        EXEC — Invoke-Sqlcmd's handling of a single stored procedure returning multiple
        differently-shaped result sets is inconsistent across versions, so this cmdlet
        sidesteps that entirely. Each returned row includes StoreSizeMB (the overall
        rb.ChangeLog store size) alongside that table's own capture stats.
    .EXAMPLE
        Get-SqlRecycleBinStatus -ServerInstance 'localhost' -Database 'Sales' | Format-Table
    .LINK
        https://github.com/qmmughal/sql-recyclebin
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerInstance,

        [Parameter(Mandatory)]
        [string]$Database,

        [pscredential]$Credential,

        [switch]$TrustServerCertificate
    )

    $tableQuery = @'
SELECT e.SchemaName, e.TableName, e.EnabledAt,
       Captured = (SELECT COUNT_BIG(*) FROM rb.ChangeLog l
                   WHERE l.SchemaName = e.SchemaName AND l.TableName = e.TableName),
       PendingRestore = (SELECT COUNT_BIG(*) FROM rb.ChangeLog l
                         WHERE l.SchemaName = e.SchemaName AND l.TableName = e.TableName
                           AND l.Restored = 0)
FROM rb.EnabledTables e
ORDER BY e.SchemaName, e.TableName;
'@

    $sizeQuery = @'
SELECT StoreSizeMB = CAST(SUM(a.total_pages) * 8 / 1024.0 AS DECIMAL(18,1))
FROM sys.partitions p
JOIN sys.allocation_units a ON a.container_id = p.partition_id
WHERE p.object_id = OBJECT_ID(N'rb.ChangeLog');
'@

    $commonParams = @{
        ServerInstance         = $ServerInstance
        Database               = $Database
        Credential             = $Credential
        TrustServerCertificate = $TrustServerCertificate
    }

    $tables = Invoke-SqlRecycleBinCommand @commonParams -Query $tableQuery
    $size = Invoke-SqlRecycleBinCommand @commonParams -Query $sizeQuery
    $storeSizeMB = if ($size) { $size.StoreSizeMB } else { 0 }

    if (-not $tables) {
        return
    }

    foreach ($row in $tables) {
        [PSCustomObject]@{
            SchemaName     = $row.SchemaName
            TableName      = $row.TableName
            EnabledAt      = $row.EnabledAt
            Captured       = $row.Captured
            PendingRestore = $row.PendingRestore
            StoreSizeMB    = $storeSizeMB
        }
    }
}
