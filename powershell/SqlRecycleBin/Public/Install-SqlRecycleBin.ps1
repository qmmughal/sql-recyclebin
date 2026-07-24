function Install-SqlRecycleBin {
    <#
    .SYNOPSIS
        Installs SQL RecycleBin (the rb schema, tables, and procedures) on a database.
    .DESCRIPTION
        Runs the bundled install.sql against the target database. Safe to re-run —
        install.sql is fully idempotent (CREATE OR ALTER / IF-exists checks).
    .PARAMETER ServerInstance
        SQL Server instance name, e.g. 'localhost', 'MYSERVER\SQLEXPRESS', 'tcp:myserver,1433'.
    .PARAMETER Database
        Target database. SQL RecycleBin installs into an 'rb' schema inside this database.
    .PARAMETER Credential
        Optional SQL authentication credential. Omit to use Windows/Integrated auth.
    .PARAMETER TrustServerCertificate
        Passed through to Invoke-Sqlcmd for encrypted connections with a self-signed cert
        (common for local dev instances since SQL Server 2022 defaults to Encrypt=Mandatory).
    .EXAMPLE
        Install-SqlRecycleBin -ServerInstance 'localhost' -Database 'AdventureWorks'
    .EXAMPLE
        Install-SqlRecycleBin -ServerInstance 'myserver.database.windows.net' -Database 'Sales' -Credential (Get-Credential)
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

    $scriptPath = Join-Path -Path $ModuleRoot -ChildPath 'Scripts/install.sql'
    if (-not (Test-Path -Path $scriptPath)) {
        throw "Could not find install.sql at '$scriptPath'. The module installation may be corrupt."
    }

    if ($PSCmdlet.ShouldProcess("$ServerInstance / $Database", 'Install SQL RecycleBin (rb schema)')) {
        Invoke-SqlRecycleBinCommand -ServerInstance $ServerInstance -Database $Database `
            -InputFile $scriptPath -Credential $Credential -TrustServerCertificate:$TrustServerCertificate
        Write-Verbose "SQL RecycleBin installed on $ServerInstance/$Database."
    }
}
