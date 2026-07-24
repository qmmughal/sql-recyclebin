function Disable-SqlRecycleBinCapture {
    <#
    .SYNOPSIS
        Disables SQL RecycleBin capture (rb.Disable) on a table.
    .DESCRIPTION
        Drops the capture trigger for the given table. Previously captured history in
        rb.ChangeLog is left in place.
    .PARAMETER Table
        Two-part table name, e.g. 'dbo.Orders'.
    .EXAMPLE
        Disable-SqlRecycleBinCapture -ServerInstance 'localhost' -Database 'Sales' -Table 'dbo.Orders'
    .LINK
        https://github.com/qmmughal/sql-recyclebin
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$ServerInstance,

        [Parameter(Mandatory)]
        [string]$Database,

        [Parameter(Mandatory)]
        [string]$Table,

        [pscredential]$Credential,

        [switch]$TrustServerCertificate
    )

    $query = "EXEC rb.Disable @Table = $(ConvertTo-SqlLiteral $Table);"

    if ($PSCmdlet.ShouldProcess($Table, 'Disable SQL RecycleBin capture')) {
        Invoke-SqlRecycleBinCommand -ServerInstance $ServerInstance -Database $Database `
            -Query $query -Credential $Credential -TrustServerCertificate:$TrustServerCertificate
    }
}
