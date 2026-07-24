$ModuleRoot = $PSScriptRoot

$private = Get-ChildItem -Path (Join-Path $ModuleRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue
$public = Get-ChildItem -Path (Join-Path $ModuleRoot 'Public') -Filter '*.ps1' -ErrorAction SilentlyContinue

foreach ($file in @($private) + @($public)) {
    try {
        . $file.FullName
    }
    catch {
        Write-Error -Message "Failed to import function $($file.FullName): $_"
    }
}

Export-ModuleMember -Function $public.BaseName
