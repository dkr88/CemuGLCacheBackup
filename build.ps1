Set-Location (Split-Path -Parent -Path $MyInvocation.MyCommand.Definition)

# Build the regular version

.\build\ps2exe.ps1 -inputFile .\Cemu_withGLCacheBackup.ps1 -outputFile .\dist\Cemu_withGLCacheBackup.exe

# Build the noConsole version

$scriptContent = Get-Content -Path .\Cemu_withGLCacheBackup.ps1
$scriptContent = $scriptContent.Replace('$noConsole = $false', '$noConsole = $true')
Set-Content -Path .\Cemu_withGLCacheBackup_noConsole.temp.ps1 -Value $scriptContent

.\build\ps2exe.ps1 -inputFile Cemu_withGLCacheBackup_noConsole.temp.ps1 -outputFile .\dist\Cemu_withGLCacheBackup_noConsole.exe -noConsole

Remove-Item .\Cemu_withGLCacheBackup_noConsole.temp.ps1

# Clean up

Remove-Item .\dist\*.exe.config

# Support files

Copy-Item .\Cemu_withGLCacheBackup.ps1 .\dist\
Copy-Item .\Cemu_withGLCacheBackup.xml .\dist\
Copy-Item .\README.md .\dist\