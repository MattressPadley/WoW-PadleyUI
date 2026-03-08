param(
    [string]$SourceDir,
    [string]$AddonName,
    [string]$ZipPath
)

Add-Type -Assembly System.IO.Compression.FileSystem

if (Test-Path $ZipPath) { Remove-Item $ZipPath }

$zip = [System.IO.Compression.ZipFile]::Open($ZipPath, 'Create')
$addonDir = Join-Path $SourceDir $AddonName

Get-ChildItem -Path $addonDir -Recurse -File | ForEach-Object {
    $relativePath = $_.FullName.Substring($addonDir.Length).TrimStart('\', '/')
    $entryName = "$AddonName/$relativePath".Replace('\', '/')
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $entryName) | Out-Null
}

$zip.Dispose()
Write-Host "Created $ZipPath"
