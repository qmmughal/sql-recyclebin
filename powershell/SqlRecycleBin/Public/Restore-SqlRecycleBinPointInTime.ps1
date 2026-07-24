function Restore-SqlRecycleBinPointInTime {
    <#
    .SYNOPSIS
        Rolls a table's captured changes back to a point in time (rb.Restore).
    .DESCRIPTION
        Undoes every captured transaction on the table since -Since, newest first.
        Equivalent to calling Restore-SqlRecycleBinLast repeatedly until nothing
        newer than -Since remains.
    .PARAMETER Table
        Two-part table name, e.g. 'dbo.Orders'.
    .PARAMETER Since
        Undo every captured change at or after this time.
    .EXAMPLE
        Restore-SqlRecycleBinPointInTime -ServerInstance 'localhost' -Database 'Sales' -Table 'dbo.Orders' -Since (Get-Date).AddMinutes(-30)
    .LINK
        https://github.com/qmmughal/sql-recyclebin
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [string]$ServerInstance,

        [Parameter(Mandatory)]
        [string]$Database,

        [Parameter(Mandatory)]
        [string]$Table,

        [Parameter(Mandatory)]
        [datetime]$Since,

        [pscredential]$Credential,

        [switch]$TrustServerCertificate
    )

    $sinceLiteral = "'{0}'" -f $Since.ToString('yyyy-MM-ddTHH:mm:ss.fff')
    $query = "EXEC rb.Restore @Table = $(ConvertTo-SqlLiteral $Table), @Since = $sinceLiteral;"

    if ($PSCmdlet.ShouldProcess($Table, "Undo all captured changes since $Since")) {
        Invoke-SqlRecycleBinCommand -ServerInstance $ServerInstance -Database $Database `
            -Query $query -Credential $Credential -TrustServerCertificate:$TrustServerCertificate
    }
}
