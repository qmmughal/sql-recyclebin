function Invoke-SqlRecycleBinBypass {
    <#
    .SYNOPSIS
        Runs a query or script with SQL RecycleBin capture bypassed (rb.BypassOn/BypassOff).
    .DESCRIPTION
        rb.BypassOn/rb.BypassOff toggle a SESSION_CONTEXT flag that only affects the
        connection it's set on. Because Invoke-Sqlcmd opens a new connection per call,
        calling an "Enable bypass" cmdlet and then a separate "run my bulk job" cmdlet
        would NOT share a session — the bypass would have no effect. This cmdlet wraps
        BypassOn, your query (or script file), and BypassOff into a single batch on a
        single connection so the bypass actually applies.
    .PARAMETER Query
        A T-SQL statement (e.g. a bulk DELETE/UPDATE) to run with capture bypassed.
    .PARAMETER InputFile
        Path to a .sql script to run with capture bypassed, instead of -Query.
    .EXAMPLE
        Invoke-SqlRecycleBinBypass -ServerInstance 'localhost' -Database 'Sales' -Query "DELETE dbo.Orders WHERE Status = 'Archived';"
    .EXAMPLE
        Invoke-SqlRecycleBinBypass -ServerInstance 'localhost' -Database 'Sales' -InputFile .\nightly-etl.sql
    .LINK
        https://github.com/qmmughal/sql-recyclebin
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Query')]
    param(
        [Parameter(Mandatory)]
        [string]$ServerInstance,

        [Parameter(Mandatory)]
        [string]$Database,

        [Parameter(Mandatory, ParameterSetName = 'Query')]
        [string]$Query,

        [Parameter(Mandatory, ParameterSetName = 'File')]
        [string]$InputFile,

        [pscredential]$Credential,

        [switch]$TrustServerCertificate
    )

    $innerSql = if ($PSCmdlet.ParameterSetName -eq 'File') {
        if (-not (Test-Path -Path $InputFile)) {
            throw "InputFile '$InputFile' not found."
        }
        Get-Content -Raw -Path $InputFile
    }
    else {
        $Query
    }

    $wrapped = @"
EXEC rb.BypassOn;
GO
$innerSql
GO
EXEC rb.BypassOff;
"@

    if ($PSCmdlet.ShouldProcess($Database, 'Run query/script with SQL RecycleBin capture bypassed')) {
        Invoke-SqlRecycleBinCommand -ServerInstance $ServerInstance -Database $Database `
            -Query $wrapped -Credential $Credential -TrustServerCertificate:$TrustServerCertificate
    }
}
