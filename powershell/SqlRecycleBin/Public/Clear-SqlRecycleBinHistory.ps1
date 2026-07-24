function Clear-SqlRecycleBinHistory {
    <#
    .SYNOPSIS
        Purges captured history beyond a retention window (rb.Cleanup).
    .DESCRIPTION
        Deletes rb.ChangeLog rows older than -KeepDays, in batches. This is permanent —
        rows removed here can no longer be recovered with Restore-SqlRecycleBin*.
    .PARAMETER KeepDays
        Retention window in days. Omit to use the database's configured default (rb.Config, 14 by default).
    .EXAMPLE
        Clear-SqlRecycleBinHistory -ServerInstance 'localhost' -Database 'Sales' -KeepDays 30
    .LINK
        https://github.com/qmmughal/sql-recyclebin
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [string]$ServerInstance,

        [Parameter(Mandatory)]
        [string]$Database,

        [Nullable[int]]$KeepDays,

        [pscredential]$Credential,

        [switch]$TrustServerCertificate
    )

    $keepDaysArg = if ($null -ne $KeepDays) { $KeepDays } else { 'NULL' }
    $query = "EXEC rb.Cleanup @KeepDays = $keepDaysArg;"

    if ($PSCmdlet.ShouldProcess($Database, 'Permanently purge captured history beyond the retention window')) {
        Invoke-SqlRecycleBinCommand -ServerInstance $ServerInstance -Database $Database `
            -Query $query -Credential $Credential -TrustServerCertificate:$TrustServerCertificate
    }
}
