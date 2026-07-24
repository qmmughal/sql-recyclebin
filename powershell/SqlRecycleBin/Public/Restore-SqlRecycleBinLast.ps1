function Restore-SqlRecycleBinLast {
    <#
    .SYNOPSIS
        Undoes the most recent captured transaction on a table (rb.UndoLast).
    .DESCRIPTION
        Re-inserts the most recently deleted rows, or reverts the most recent update,
        whichever was captured last for this table. Call it repeatedly to walk further
        back in time, newest first.
    .PARAMETER Table
        Two-part table name, e.g. 'dbo.Orders'.
    .EXAMPLE
        Restore-SqlRecycleBinLast -ServerInstance 'localhost' -Database 'Sales' -Table 'dbo.Orders'
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

        [pscredential]$Credential,

        [switch]$TrustServerCertificate
    )

    $query = "EXEC rb.UndoLast @Table = $(ConvertTo-SqlLiteral $Table);"

    if ($PSCmdlet.ShouldProcess($Table, 'Undo the most recent captured transaction')) {
        Invoke-SqlRecycleBinCommand -ServerInstance $ServerInstance -Database $Database `
            -Query $query -Credential $Credential -TrustServerCertificate:$TrustServerCertificate
    }
}
