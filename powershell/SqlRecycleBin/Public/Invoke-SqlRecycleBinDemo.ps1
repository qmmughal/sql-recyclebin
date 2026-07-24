function Invoke-SqlRecycleBinDemo {
    <#
    .SYNOPSIS
        Runs the bundled demo.sql — the accident -> recovery smoke test — against a scratch database.
    .DESCRIPTION
        Creates dbo.rbDemo_Orders, enables capture, simulates an accidental DELETE + UPDATE,
        then undoes both. Requires SQL RecycleBin to already be installed on the target
        database (see Install-SqlRecycleBin). Safe to run repeatedly — it drops and
        recreates its own demo table each time.
    .EXAMPLE
        Invoke-SqlRecycleBinDemo -ServerInstance 'localhost' -Database 'ScratchDb'
    .LINK
        https://github.com/qmmughal/sql-recyclebin
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$ServerInstance,

        [Parameter(Mandatory)]
        [string]$Database,

        [pscredential]$Credential,

        [switch]$TrustServerCertificate
    )

    $scriptPath = Join-Path -Path $ModuleRoot -ChildPath 'Scripts/demo.sql'
    if (-not (Test-Path -Path $scriptPath)) {
        throw "Could not find demo.sql at '$scriptPath'. The module installation may be corrupt."
    }

    if ($PSCmdlet.ShouldProcess("$ServerInstance / $Database", 'Run the SQL RecycleBin demo (creates/drops dbo.rbDemo_Orders)')) {
        Invoke-SqlRecycleBinCommand -ServerInstance $ServerInstance -Database $Database `
            -InputFile $scriptPath -Credential $Credential -TrustServerCertificate:$TrustServerCertificate
    }
}
