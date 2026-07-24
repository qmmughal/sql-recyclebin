function ConvertTo-SqlLiteral {
    <#
    .SYNOPSIS
        Escapes a string for safe use as a single-quoted T-SQL literal.
    .DESCRIPTION
        Doubles embedded single quotes and wraps the value in quotes. Used internally
        to build EXEC rb.* calls for values that come from PowerShell parameters
        (table names, dates) since Invoke-Sqlcmd has no native parameter binding.
        This is basic literal-escaping, not full injection protection — values still
        run with the caller's own SQL Server permissions.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyString()]
        [string]$Value
    )
    process {
        "'{0}'" -f ($Value -replace "'", "''")
    }
}
