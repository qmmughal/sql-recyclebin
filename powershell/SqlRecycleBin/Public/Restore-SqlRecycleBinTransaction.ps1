function Restore-SqlRecycleBinTransaction {
    <#
    .SYNOPSIS
        Undoes a specific captured transaction on a table (rb.UndoTransaction).
    .DESCRIPTION
        Use the TxId from Get-SqlRecycleBinDeletedRow / Get-SqlRecycleBinUpdatedRow output
        to target a specific transaction rather than just "the most recent one".
    .PARAMETER Table
        Two-part table name, e.g. 'dbo.Orders'.
    .PARAMETER TxId
        The transaction id to undo (see the TxId column via rb.ChangeLog / retrieval cmdlets).
    .EXAMPLE
        Restore-SqlRecycleBinTransaction -ServerInstance 'localhost' -Database 'Sales' -Table 'dbo.Orders' -TxId 48291
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
        [long]$TxId,

        [pscredential]$Credential,

        [switch]$TrustServerCertificate
    )

    $query = "EXEC rb.UndoTransaction @Table = $(ConvertTo-SqlLiteral $Table), @TxId = $TxId;"

    if ($PSCmdlet.ShouldProcess("$Table (TxId $TxId)", 'Undo this captured transaction')) {
        Invoke-SqlRecycleBinCommand -ServerInstance $ServerInstance -Database $Database `
            -Query $query -Credential $Credential -TrustServerCertificate:$TrustServerCertificate
    }
}
