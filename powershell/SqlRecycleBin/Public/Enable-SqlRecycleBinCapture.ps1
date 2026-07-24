function Enable-SqlRecycleBinCapture {
    <#
    .SYNOPSIS
        Enables SQL RecycleBin capture (rb.Enable) on a table.
    .DESCRIPTION
        Generates the AFTER UPDATE, DELETE capture trigger for the given table.
        The table must have a primary key.
    .PARAMETER Table
        Two-part table name, e.g. 'dbo.Orders'.
    .EXAMPLE
        Enable-SqlRecycleBinCapture -ServerInstance 'localhost' -Database 'Sales' -Table 'dbo.Orders'
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

    $query = "EXEC rb.Enable @Table = $(ConvertTo-SqlLiteral $Table);"

    if ($PSCmdlet.ShouldProcess($Table, 'Enable SQL RecycleBin capture')) {
        Invoke-SqlRecycleBinCommand -ServerInstance $ServerInstance -Database $Database `
            -Query $query -Credential $Credential -TrustServerCertificate:$TrustServerCertificate
    }
}
