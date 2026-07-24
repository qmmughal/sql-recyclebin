function Uninstall-SqlRecycleBin {
    <#
    .SYNOPSIS
        Removes SQL RecycleBin from a database — triggers, procedures, tables, and the
        rb schema.
    .DESCRIPTION
        Runs the bundled uninstall.sql. WARNING: this permanently deletes the captured
        change history (rb.ChangeLog) — there is no undo for undoing SQL RecycleBin itself.
        Requires -Confirm acknowledgment unless -Force is passed.
    .PARAMETER ServerInstance
        SQL Server instance name.
    .PARAMETER Database
        Target database to remove SQL RecycleBin from.
    .PARAMETER Force
        Skip the confirmation prompt.
    .EXAMPLE
        Uninstall-SqlRecycleBin -ServerInstance 'localhost' -Database 'ScratchDb' -Force
    .LINK
        https://github.com/qmmughal/sql-recyclebin
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [string]$ServerInstance,

        [Parameter(Mandatory)]
        [string]$Database,

        [pscredential]$Credential,

        [switch]$TrustServerCertificate,

        [switch]$Force
    )

    $scriptPath = Join-Path -Path $ModuleRoot -ChildPath 'Scripts/uninstall.sql'
    if (-not (Test-Path -Path $scriptPath)) {
        throw "Could not find uninstall.sql at '$scriptPath'. The module installation may be corrupt."
    }

    $target = "$ServerInstance / $Database"
    $action = 'Remove SQL RecycleBin AND permanently delete its captured change history'

    if ($Force) {
        $ConfirmPreference = 'None'
    }

    if ($PSCmdlet.ShouldProcess($target, $action)) {
        Invoke-SqlRecycleBinCommand -ServerInstance $ServerInstance -Database $Database `
            -InputFile $scriptPath -Credential $Credential -TrustServerCertificate:$TrustServerCertificate
        Write-Verbose "SQL RecycleBin removed from $ServerInstance/$Database."
    }
}
