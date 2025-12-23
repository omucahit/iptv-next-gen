$source = "build\windows\x64\runner\Release"
$destination = "iptv_next_release.zip"

if (Test-Path $destination) {
    Remove-Item $destination
}

Write-Host "Zipping release..."
Compress-Archive -Path "$source\*" -DestinationPath $destination -Force
Write-Host "Done! Created $destination"
