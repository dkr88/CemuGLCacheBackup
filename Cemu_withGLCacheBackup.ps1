<#

This PowerShell script is designed to intelligently backup and 
restore the NVIDIA GL shader cache for CEMU on a PER-GAME basis.

Please see https://github.com/dkr88/CemuGLCacheBackup/blob/master/README.md

#>

param (
    [Parameter(Mandatory=$true)][string]$gamePath,
    [Parameter(Mandatory=$true)][string]$gameId,
    
    [string]$cemuDir = $null,
    [string]$cemuExe = "Cemu.exe",
    [string]$cemuArgs = "",

    [string]$backupDir = $null,

    [string]$logFile = "Cemu_withGLCacheBackup.log.txt",
    
    [switch]$showPrompts = $false,
    [switch]$testMode = $false
)

function Write-Log {
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Message,
        [string]$Level = "info"
    )

    if ($noConsole) {
        $Message | Tee-Object -FilePath $logFile -Append | Out-Null

        if ($Level -eq "fatal") {
            Write-Host $Message -ForegroundColor Red
        }
    }
    else {
        switch ($Level) {
            "debug" { Write-Host $Message -ForegroundColor DarkGray }
            "success" { Write-Host $Message -ForegroundColor Green }
            "warn" { Write-Host $Message -ForegroundColor Yellow }
            "error" { Write-Host $Message -ForegroundColor Red }
            "fatal" { Write-Host $Message -ForegroundColor Red }
            default { Write-Host $Message }
        }
    }
}

# Determine the current script path
if ($MyInvocation.MyCommand.CommandType -eq "ExternalScript") { 
    $scriptPath = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition 
}
else { 
    $scriptPath = Split-Path -Parent -Path ([Environment]::GetCommandLineArgs()[0]) 
}

# Default to current script path for CEMU and backup directories
if (!$cemuDir) { $cemuDir = "$scriptPath" }
if (!$backupDir) { 
    $backupDir = "$scriptPath\GLCacheBackup"
    if (!(Test-Path $backupDir)) {
        Write-Log "Creating default backup directory"
        New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    }
}

# CEMU args need to be prefixed with '+' instead of '-' otherwise powershell gets confused
$cemuArgs = $cemuArgs.Replace("+", "-")

# This will be modified at build time to reflect the exe version being built
$noConsole = $false

# Read the config XML
$configXml = Get-Content "Cemu_withGLCacheBackup.xml" -Raw
if (!$configXml) {
    Write-Host "Configuration file 'Cemu_withGLCacheBackup.xml' is missing or invalid" -ForegroundColor Red
    exit
}

$glCacheDir = ($configXml | Select-Xml -XPath "//config/glCacheDir").Node.InnerText.TrimEnd("\")
$glCacheId = ($configXml | Select-Xml -XPath "//config/glCacheCemuId").Node.InnerText.Replace(".bin", "")

if ($noConsole) {
    "Starting session @ {0}" -f (Get-Date) | Tee-Object -FilePath $logFile | Out-Null
}
else {
    Start-Transcript $logFile -Force | Out-Null
}

Write-Log "gamePath   = $gamePath" -Level "debug"
Write-Log "gameId     = $gameId" -Level "debug"
Write-Log "cemuDir    = $cemuDir" -Level "debug"
Write-Log "cemuExe    = $cemuExe" -Level "debug"
Write-Log "cemuArgs   = $cemuArgs" -Level "debug"
Write-Log "backupDir  = $backupDir" -Level "debug"
Write-Log "glCacheDir = $glCacheDir" -Level "debug"
Write-Log "glCacheId  = $glCacheId" -Level "debug"

$errors = @()

if (!(Test-Path "$cemuDir/$cemuExe")) {
    $errors += "CEMU executable was not found - is this script in the CEMU install directory?"
}

if (!(Test-Path $backupDir)) {
    $errors += "Backup directory '$backupDir' doesn't exist - please create it now"
}

if (!(Test-Path $glCacheDir)) {
    $errors += "GLCache directory '$glCacheDir' doesn't exist - check your XML config"
}

if ($errors.Length) {
    foreach ($err in $errors) {
        Write-Log $err -Level "fatal"
    }

    if ($noConsole) {
        Write-Log "Session complete"
    }
    else {
        Stop-Transcript | Out-Null
        Read-Host "Press enter to exit"
    }
    exit
}

if ($testMode) {
    Write-Log "Running in TEST mode - no files will actually be copied"
}

$copyCache = $true

$backupExists = Test-Path "$backupDir\$gameId.bin"
$backupSize = 0

if ($backupExists -eq $true) {
    $backupSize = ((Get-ChildItem $backupDir -Recurse -Filter "$gameId.*" | Measure-Object -Property Length -Sum -ErrorAction Stop).Sum / 1MB)
    Write-Log ("GLCache backup size for $gameId is {0:N2} MB" -f $backupSize)
}
else {
    Write-Log "GLCache backup doesn't exist for $gameId"
    $copyCache = $false
}

$glCacheExists = Test-Path "$glCacheDir\$glCacheId.bin"
$glCacheSize = 0

if ($glCacheExists -eq $true) {
    $glCacheSize = ((Get-ChildItem $glCacheDir -Recurse -Filter "$glCacheId.*" | Measure-Object -Property Length -Sum -ErrorAction Stop).Sum / 1MB)
    Write-Log ("Existing GLCache size is {0:N2} MB" -f $glCacheSize)
    
    if ($backupExists -eq $true) {
        if ($glCacheSize -eq $backupSize) {
            Write-Log "Existing GLCache will be re-used - it is the same size as backup"
            $copyCache = $false
        }
        elseif ($glCacheSize -gt $backupSize) {
            Write-Log ("Existing GLCache is {0:N8} MB larger than backup for $gameId" -f ($glCacheSize - $backupSize))
            if ($showPrompts -and (Read-Host "Use smaller backup instead? ( [y] / n ) ") -eq "n") {
                $copyCache = $false
            }
        }
    }
    else {
        if (!$showPrompts -or (Read-Host "Delete existing GLCache before starting? ( [y] / n ) ") -ne "n") {
            Write-Log "Deleting existing GLCache and starting fresh"
            if (!$testMode) {    
                Remove-Item "$glCacheDir\$glCacheId.bin" -Force
                Remove-Item "$glCacheDir\$glCacheId.toc" -Force
            }
        }
    }
}
else {
    Write-Log "GLCache doesn't exist at the specified location yet" -Level "warn"
}

If ($copyCache -eq $true) {
    Write-Log "Backup GLCache will be used" -Level "success"
    if (!$testMode) {
        Copy-Item "$backupDir\$gameId.bin" "$glCacheDir\$glCacheId.bin" -Force
        Copy-Item "$backupDir\$gameId.toc" "$glCacheDir\$glCacheId.toc" -Force
    }
}

Write-Log "Starting CEMU... "

Set-Location -Path $cemuDir
Start-Process -FilePath "$cemuDir/$cemuExe" -ArgumentList "$cemuArgs -g ""$gamePath""" -Wait

Write-Log "CEMU stopped."

$glCacheExists = Test-Path "$glCacheDir\$glCacheId.bin"

if ($glCacheExists) {
    $newGlCacheSize = ((Get-ChildItem "$glCacheDir\$glCacheId.*" -Recurse | Measure-Object -Property Length -Sum -ErrorAction Stop).Sum / 1MB)
    Write-Log ("New GLCache size is {0:N2} MB" -f $newGlCacheSize)

    if ($newGlCacheSize -gt $backupSize) {
        if ($backupSize -gt 0) {
            Write-Log ("New GLCache is {0:N8} MB larger than current backup" -f ($newGlCacheSize - $backupSize))
        }
        if (!$showPrompts -or (Read-Host "Backup now? ( [y] / n ) ") -ne "n") {
            Write-Log "Backing up GLCache for $gameId" -Level "success"
            if (!$testMode) {
                Copy-Item "$glCacheDir\$glCacheId.bin" "$backupDir\$gameId.bin" -Force
                Copy-Item "$glCacheDir\$glCacheId.toc" "$backupDir\$gameId.toc" -Force
            }
        }
    }
    else {
        Write-Log "New GLCache is the same size or smaller - it will not be backed up"
    }
}
else {
    Write-Log "GLCache doesn't exist at the expected location - did you configure the correct glCacheCemuId in the XML?" -Level "error"
}

if ($noConsole) {
    Write-Log "Session complete"
}
else {
    Stop-Transcript | Out-Null
    Start-Sleep -Seconds 3
}