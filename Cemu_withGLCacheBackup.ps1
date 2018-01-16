<#

This PowerShell script is designed to intelligently backup and 
restore the NVIDIA GL shader cache for Cemu on a PER-GAME basis.

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
    
    [decimal]$glCacheSizeTolerance = 0.01,

    [switch]$showPrompts = $false,
    [switch]$testMode = $false
)

#region Helper functions
function Write-Log {
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Message,
        [string]$Level = "trace"
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
            "info" { Write-Host $Message -ForegroundColor Cyan }
            "success" { Write-Host $Message -ForegroundColor Green }
            "warn" { Write-Host $Message -ForegroundColor Yellow }
            "error" { Write-Host $Message -ForegroundColor Red }
            "fatal" { Write-Host $Message -ForegroundColor Red }
            default { Write-Host $Message }
        }
    }
}

function Set-CemuHookIgnorePrecompiled {
    if (Test-Path $cemuHookIniFile) {
        $ini = Get-IniContent $cemuHookIniFile
    }
    else {
        if (!(Test-Path "$cemuDir\dbghelp.dll")) {
            Write-Log "Cemu hook not detected - delete files from 'shaderCache/precompiled' to ensure clean backup!" -Level "warn"
            return $false
        }
        $ini = @{}
    }
    
    if (!$ini.ContainsKey("Graphics")) {
        $ini.Graphics = @{}
    }
    elseif ($ini.Graphics.ignorePrecompiledShaderCache -eq "true") {
        Write-Log "You should change the 'Ignore precompiled shader cache' setting to 'Enabled'" -Level "warn"
        return $false
    }

    $ini.Graphics.ignorePrecompiledShaderCache = "true"
    
    if (Test-Path $cemuHookIniFile) {
        Copy-Item $cemuHookIniFile $cemuHookIniBackupFile -Force
    }
    
    Out-IniFile $ini -FilePath $cemuHookIniFile
    Write-Log "Forced ignorePrecompiledShaderCache = true in cemuhook.ini" -Level "info"

    return $true
}

function Get-IniContent ($FilePath) {
    $ini = @{}
    switch -regex -file $FilePath
    {
        "^\[(.+)\]" # Section
        {
            $section = $matches[1]
            $ini[$section] = @{}
            $CommentCount = 0
        }
        "^(;.*)$" # Comment
        {
            $value = $matches[1]
            $CommentCount = $CommentCount + 1
            $name = "Comment" + $CommentCount
            $ini[$section][$name] = $value
        } 
        "(.+?)\s*=\s*(.*)" # Key
        {
            $name,$value = $matches[1..2]
            $ini[$section][$name] = $value
        }
    }
    return $ini
}

function Out-IniFile($InputObject, $FilePath) {
    $outFile = New-Item -ItemType file -Path $FilePath -Force
    foreach ($i in $InputObject.keys)
    {
        if (!($($InputObject[$i].GetType().Name) -eq "Hashtable"))
        {
            #No Sections
            Add-Content -Path $outFile -Value "$i = $($InputObject[$i])"
        } else {
            #Sections
            Add-Content -Path $outFile -Value "[$i]"
            foreach ($j in ($InputObject[$i].keys | Sort-Object))
            {
                if ($j -match "^Comment[\d]+") {
                    Add-Content -Path $outFile -Value "$($InputObject[$i][$j])"
                } else {
                    Add-Content -Path $outFile -Value "$j = $($InputObject[$i][$j])" 
                }

            }
            Add-Content -Path $outFile -Value ""
        }
    }
}
#endregion

# Determine the current script path
if ($MyInvocation.MyCommand.CommandType -eq "ExternalScript") { 
    $scriptPath = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition 
}
else { 
    $scriptPath = Split-Path -Parent -Path ([Environment]::GetCommandLineArgs()[0]) 
}

# Default to current script path for Cemu and backup directories
if (!$cemuDir) { 
    $cemuDir = "$scriptPath" 
}
if (!$backupDir) { 
    $backupDir = "$scriptPath\GLCacheBackup"
    if (!(Test-Path $backupDir)) {
        Write-Log "Creating default backup directory"
        New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    }
}

# In case we need to make changes to cemuhook settings
$cemuHookIniFile = "$cemuDir\cemuhook.ini"
$cemuHookIniBackupFile = "$cemuDir\cemuhook.ini.glcachebackup"
$cemuHookIniModified = $false

# Cemu args need to be prefixed with '+' instead of '-' otherwise powershell gets confused
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
Write-Log "glCacheSizeTolerance = $glCacheSizeTolerance" -Level "debug"

$errors = @()

if (!(Test-Path "$cemuDir/$cemuExe")) {
    $errors += "Cemu executable was not found - is this script in the CEMU install directory?"
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
$forceRecompile = $false

$backupExists = Test-Path "$backupDir\$gameId.bin"
$backupSize = 0

if ($backupExists) {
    $backupSize = ((Get-ChildItem $backupDir -Recurse -Filter "$gameId.*" | Measure-Object -Property Length -Sum -ErrorAction Stop).Sum / 1MB)
    Write-Log ("GLCache backup size for $gameId is {0:N2} MB" -f $backupSize)
}
else {
    Write-Log "GLCache backup doesn't exist for $gameId"
    $copyCache = $false

    if (!$showPrompts -or (Read-Host "Force re-compile shader cache? ( [y] / n ) ") -ne "n") {
        if (!$testMode) {    
            $forceRecompile = $true
            $cemuHookIniModified = Set-CemuHookIgnorePrecompiled
        }
    }
}

$glCacheExists = Test-Path "$glCacheDir\$glCacheId.bin"
$glCacheSize = 0

if ($glCacheExists) {
    $glCacheSize = ((Get-ChildItem $glCacheDir -Recurse -Filter "$glCacheId.*" | Measure-Object -Property Length -Sum -ErrorAction Stop).Sum / 1MB)
    Write-Log ("Existing GLCache size is {0:N2} MB" -f $glCacheSize)
    
    if ($backupExists -and !$forceRecompile) {
        if ([Math]::Abs($glCacheSize - $backupSize) -lt $glCacheSizeTolerance) {
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
        if ($forceRecompile) {
            Write-Log "Deleting existing GLCache because shader cache will be re-compiled"
            if (!$testMode) {
                Remove-Item "$glCacheDir\$glCacheId.bin" -Force
                Remove-Item "$glCacheDir\$glCacheId.toc" -Force
            }
        }
        elseif (!$showPrompts -or (Read-Host "Delete existing GLCache before starting? ( [y] / n ) ") -ne "n") {
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

If ($copyCache) {
    Write-Log "Backup GLCache will be used" -Level "success"
    if (!$testMode) {
        Copy-Item "$backupDir\$gameId.bin" "$glCacheDir\$glCacheId.bin" -Force
        Copy-Item "$backupDir\$gameId.toc" "$glCacheDir\$glCacheId.toc" -Force
    }
}

Write-Log "Starting Cemu... "

Set-Location -Path $cemuDir
Start-Process -FilePath "$cemuDir/$cemuExe" -ArgumentList "$cemuArgs -g ""$gamePath""" -Wait

Write-Log "Cemu stopped."

if ($cemuHookIniModified) {
    if (Test-Path $cemuHookIniBackupFile) {
        Copy-Item $cemuHookIniBackupFile $cemuHookIniFile -Force
        Write-Log "Restored cemuhook.ini" -Level "info"
    }
    else {
        Remove-Item $cemuHookIniFile -Force
        Write-Log "Removed temporary cemuhook.ini"
    }
}

$glCacheExists = Test-Path "$glCacheDir\$glCacheId.bin"

if ($glCacheExists) {
    $newGlCacheSize = ((Get-ChildItem "$glCacheDir\$glCacheId.*" -Recurse | Measure-Object -Property Length -Sum -ErrorAction Stop).Sum / 1MB)
    Write-Log ("New GLCache size is {0:N2} MB" -f $newGlCacheSize)

    if ([Math]::Abs($newGlCacheSize - $backupSize) -gt $glCacheSizeTolerance) {
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

if ($showPrompts) {
    Read-Host "Press enter to exit"
}