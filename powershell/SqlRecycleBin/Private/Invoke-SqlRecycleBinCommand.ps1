function Invoke-SqlRecycleBinCommand {
    <#
    .SYNOPSIS
        Internal wrapper around Invoke-Sqlcmd shared by every SqlRecycleBin cmdlet.
    .DESCRIPTION
        Centralizes connection parameter handling (ServerInstance, Database, Credential,
        trust/encrypt options, timeout) so each public cmdlet only has to build a query
        or point at a script file. Requires the 'SqlServer' module (Invoke-Sqlcmd) —
        see this module's manifest RequiredModules.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Query')]
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

        [int]$QueryTimeout = 30,

        [switch]$TrustServerCertificate
    )

    $sqlcmdParams = @{
        ServerInstance = $ServerInstance
        Database       = $Database
        QueryTimeout   = $QueryTimeout
        ErrorAction    = 'Stop'
    }

    if ($PSCmdlet.ParameterSetName -eq 'File') {
        $sqlcmdParams['InputFile'] = $InputFile
    }
    else {
        $sqlcmdParams['Query'] = $Query
    }

    if ($Credential) {
        $sqlcmdParams['Username'] = $Credential.UserName
        $sqlcmdParams['Password'] = $Credential.GetNetworkCredential().Password
    }

    # Invoke-Sqlcmd (SqlServer module, recent versions) supports -TrustServerCertificate;
    # older versions don't, so only pass it through when asked for and available.
    if ($TrustServerCertificate) {
        $cmd = Get-Command -Name Invoke-Sqlcmd -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Parameters.ContainsKey('TrustServerCertificate')) {
            $sqlcmdParams['TrustServerCertificate'] = $true
        }
    }

    Invoke-Sqlcmd @sqlcmdParams
}
