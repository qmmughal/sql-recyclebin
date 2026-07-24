function Get-SqlRecycleBinUpdatedRow {
    <#
    .SYNOPSIS
        Returns recently updated rows for a table (rb.Updated), with before/after JSON.
    .DESCRIPTION
        Wraps rb.Updated. Unlike Get-SqlRecycleBinDeletedRow, before/after values come
        back as raw JSON columns (RowBefore/RowAfter) rather than typed columns — mirroring
        rb.Updated's own output, since an update can touch a different set of columns each time.
    .PARAMETER Table
        Two-part table name, e.g. 'dbo.Orders'.
    .PARAMETER Top
        Max rows to return. Default 10.
    .PARAMETER Since
        Only include rows updated at or after this time.
    .EXAMPLE
        Get-SqlRecycleBinUpdatedRow -ServerInstance 'localhost' -Database 'Sales' -Table 'dbo.Orders' |
            Select-Object ChangeId, ChangedAt, RowBefore, RowAfter
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
    $query = "EXEC rb.Updated @Table = $(ConvertTo-SqlLiteral $Table), @Top = $Top, @Since = $sinceLiteral;"

    Invoke-SqlRecycleBinCommand -ServerInstance $ServerInstance -Database $Database `
        -Query $query -Credential $Credential -TrustServerCertificate:$TrustServerCertificate
}
