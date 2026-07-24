function Get-SqlRecycleBinDeletedRow {
    <#
    .SYNOPSIS
        Returns recently deleted rows for a table (rb.Deleted), as typed PowerShell objects.
    .DESCRIPTION
        Wraps rb.Deleted. Rows are projected from JSON back into the table's current
        column types, so the objects you get back have real properties matching the
        table's schema (plus ChangeId, ChangedAt, ChangedBy, AppName).
    .PARAMETER Table
        Two-part table name, e.g. 'dbo.Orders'.
    .PARAMETER Top
        Max rows to return. Default 10.
    .PARAMETER Since
        Only include rows deleted at or after this time.
    .EXAMPLE
        Get-SqlRecycleBinDeletedRow -ServerInstance 'localhost' -Database 'Sales' -Table 'dbo.Orders'
    .EXAMPLE
        Get-SqlRecycleBinDeletedRow -ServerInstance 'localhost' -Database 'Sales' -Table 'dbo.Orders' -Top 50 -Since (Get-Date).AddHours(-1) |
            Export-Csv .\recovered-orders.csv -NoTypeInformation
    .LINK
        https://github.com/qmmughal/sql-recyclebin
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerInstance,

        [Parameter(Mandatory)]
        [string]$Database,

        [Parameter(Mandatory)]
        [string]$Table,

        [int]$Top = 10,

        [Nullable[datetime]]$Since,

        [pscredential]$Credential,

        [switch]$TrustServerCertificate
    )

    $sinceLiteral = if ($Since) { "'{0}'" -f $Since.ToString('yyyy-MM-ddTHH:mm:ss.fff') } else { 'NULL' }
    $query = "EXEC rb.Deleted @Table = $(ConvertTo-SqlLiteral $Table), @Top = $Top, @Since = $sinceLiteral;"

    Invoke-SqlRecycleBinCommand -ServerInstance $ServerInstance -Database $Database `
        -Query $query -Credential $Credential -TrustServerCertificate:$TrustServerCertificate
}
