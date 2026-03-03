# UTF-8 for correct display
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Load package lists from files (one package per line, # for comments)
function Edit-PackageList {
    param([string]$FileName, [string]$CategoryName)
    $path = Join-Path $PSScriptRoot $FileName
    if (-not (Test-Path $path)) {
        Write-Host ""
        Write-Host ('  File not found: ' + $path) -ForegroundColor Red
        return
    }
    Write-Host ""
    Write-Host ('  Opening ' + $CategoryName + '...') -ForegroundColor Cyan
    Write-Host '  Close the editor when done.' -ForegroundColor Gray
    Write-Host ""
    try {
        Start-Process notepad.exe -ArgumentList $path -Wait
    } catch {
        Start-Process $path
    }
}

function Get-PackagesFromFile {
    param([string]$FileName)
    $path = Join-Path $PSScriptRoot $FileName
    if (-not (Test-Path $path)) { return @() }
    Get-Content $path -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith('#')) {
            $pkg = ($line -split '#')[0].Trim()
            if ($pkg) { $pkg }
        }
    }
}

$script:categoriesPath = Join-Path $PSScriptRoot 'categories.json'
$script:categoryColors = @('Yellow', 'Magenta', 'Blue', 'Cyan', 'Green', 'DarkCyan')

function Load-Categories {
    if (-not (Test-Path $script:categoriesPath)) {
        $defaults = @(
            @{ id = 'dev'; name = 'Development'; file = 'packages_dev.txt'; desc = 'IDE, dev tools, databases, containers' },
            @{ id = 'local'; name = 'Local'; file = 'packages_local.txt'; desc = 'Games, media, utilities, drivers' },
            @{ id = 'vm'; name = 'VM'; file = 'packages_vm.txt'; desc = 'Drivers and utilities for virtualization' }
        )
        $defaults | ConvertTo-Json | Set-Content $script:categoriesPath -Encoding UTF8
    }
    $raw = Get-Content $script:categoriesPath -Raw -Encoding UTF8
    $list = $raw | ConvertFrom-Json
    $result = @()
    foreach ($c in $list) {
        $pkgs = @(Get-PackagesFromFile $c.file)
        $result += [PSCustomObject]@{ id = $c.id; name = $c.name; file = $c.file; desc = $c.desc; packages = $pkgs }
    }
    return $result
}

function Save-Categories {
    $toSave = $script:categories | ForEach-Object {
        @{ id = $_.id; name = $_.name; file = $_.file; desc = $_.desc }
    }
    $toSave | ConvertTo-Json | Set-Content $script:categoriesPath -Encoding UTF8
}

$script:categories = Load-Categories

# Settings - load from config if exists
$script:settingsConfigPath = Join-Path $env:APPDATA 'chocopad\settings.json'
$useProxy = $false
$script:proxyUrl = "http://192.168.1.212:9119"
$script:logsEnabled = $false
try {
    $configPath = $script:settingsConfigPath
    if (-not (Test-Path $configPath)) { $configPath = Join-Path $env:APPDATA 'chocopad\proxy.json' }
    if (Test-Path $configPath) {
        $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
        $script:proxyUrl = $cfg.proxyUrl
        $useProxy = $cfg.useProxy -eq $true
        if ($null -ne $cfg.logsEnabled) { $script:logsEnabled = $cfg.logsEnabled -eq $true }
    }
} catch { }

# Statistics tracking
$script:installedCount = 0
$script:updatedCount = 0
$script:failedCount = 0
$script:totalPackages = 0

# Execution Policy check and fix
function Test-ExecutionPolicy {
    $currentPolicy = Get-ExecutionPolicy
    Write-Host "Current execution policy: $currentPolicy" -ForegroundColor Cyan
    
    if ($currentPolicy -eq "Restricted") {
        Write-Host "Execution policy is restricted. Fixing..." -ForegroundColor Yellow
        try {
            Set-ExecutionPolicy Bypass -Scope Process -Force
            Write-Host "Execution policy set to Bypass for current process" -ForegroundColor DarkCyan
            return $true
        }
        catch {
            Write-Host "Failed to change execution policy: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host ""
            Write-Host "Try running PowerShell as Administrator and execute:" -ForegroundColor Yellow
            Write-Host "Set-ExecutionPolicy Bypass -Scope Process -Force" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "Or for permanent change (requires admin rights):" -ForegroundColor Yellow
            Write-Host "Set-ExecutionPolicy Bypass -Scope LocalMachine -Force" -ForegroundColor Cyan
            return $false
        }
    } else {
        Write-Host "Execution policy allows script execution" -ForegroundColor DarkCyan
        return $true
    }
}

# Admin check
function Test-Admin {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Chocolatey check
function Test-Chocolatey {
    try {
        choco --version 2>$null | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Get-ChocolateyVersion {
    try {
        $ver = choco --version 2>$null
        if ($ver) { return $ver.Trim() }
    }
    catch { }
    return $null
}

# Install Chocolatey function
function Install-Chocolatey {
    Write-Host "Chocolatey is not installed. Starting installation..." -ForegroundColor Yellow
    
    # Check execution policy
    $executionPolicy = Get-ExecutionPolicy
    Write-Host "Current execution policy: $executionPolicy" -ForegroundColor Cyan
    
    if ($executionPolicy -eq "Restricted") {
        Write-Host "Execution policy is restricted. Setting Bypass for current process..." -ForegroundColor Yellow
        Set-ExecutionPolicy Bypass -Scope Process -Force
    }
    
    Write-Host "Installing Chocolatey..." -ForegroundColor DarkCyan
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        
        # Refresh environment variables
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        
        Write-Host "Chocolatey installed successfully!" -ForegroundColor DarkCyan
        return $true
    }
    catch {
        Write-Host "Error installing Chocolatey: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Try installing Chocolatey manually:" -ForegroundColor Yellow
        Write-Host "Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))" -ForegroundColor Cyan
        return $false
    }
}

# UI Functions
function Show-ColorMenu {
    Clear-Host
    Write-Host ""
    Write-Host ""
    $chocoVer = Get-ChocolateyVersion
    $userFolderPath = Join-Path $env:USERPROFILE 'chocopad'
    $userFolderInstalled = (Test-Path (Join-Path $userFolderPath 'chocopad.bat')) -and (Test-Path (Join-Path $userFolderPath 'choco_software.ps1'))
    $chocoStat = if ($chocoVer) { "v$chocoVer" } else { 'no' }
    $proxyVal = if ($useProxy) { 'ON' } else { 'OFF' }
    $userVal = if ($userFolderInstalled) { 'Yes' } else { 'No' }
    $pkgCount = 0
    if ($chocoVer) { try { $pkgCount = (Get-InstalledPackages).Count } catch { } }
    Write-Host '  ' -NoNewline
    Write-Host 'Choco: ' -NoNewline -ForegroundColor DarkCyan
    Write-Host $chocoStat -NoNewline -ForegroundColor White
    Write-Host '  |  ' -NoNewline -ForegroundColor DarkGray
    Write-Host 'Chocopad: ' -NoNewline -ForegroundColor DarkCyan
    Write-Host 'v.0.1' -NoNewline -ForegroundColor White
    Write-Host '  |  ' -NoNewline -ForegroundColor DarkGray
    Write-Host 'Packages: ' -NoNewline -ForegroundColor DarkCyan
    Write-Host $pkgCount -NoNewline -ForegroundColor White
    Write-Host '  |  ' -NoNewline -ForegroundColor DarkGray
    Write-Host 'Proxy: ' -NoNewline -ForegroundColor DarkCyan
    if ($useProxy) { Write-Host 'ON' -NoNewline -ForegroundColor Green } else { Write-Host 'OFF' -NoNewline -ForegroundColor DarkGray }
    Write-Host '  |  ' -NoNewline -ForegroundColor DarkGray
    Write-Host 'Logs: ' -NoNewline -ForegroundColor DarkCyan
    if ($script:logsEnabled) { Write-Host 'ON' -NoNewline -ForegroundColor Green } else { Write-Host 'OFF' -NoNewline -ForegroundColor DarkGray }
    Write-Host '  |  ' -NoNewline -ForegroundColor DarkGray
    Write-Host 'User folder: ' -NoNewline -ForegroundColor DarkCyan
    if ($userFolderInstalled) { Write-Host 'Yes' -ForegroundColor Green } else { Write-Host 'No' -ForegroundColor Yellow }
    Write-Host ""
    $menuW = 58
    $asciiArt = @(
        '_____ _____ _____ _____ _____ _____ _____ ____ ',
        '|     |  |  |     |     |     |  _  |  _  |    \',
        '|   --|     |  |  |   --|  |  |   __|     |  |  |',
        '|_____|__|__|_____|_____|_____|__|  |__|__|____/'
    )
    $pad = { param($n) ' ' * [Math]::Max(0, $n) }
    $right = { param($i) if ($i -lt $asciiArt.Length) { $asciiArt[$i] } else { '' } }
    $lineIdx = 0
    Write-Host ('  Choose an action:' + (& $pad ($menuW - 18)) + (& $right $lineIdx)) -ForegroundColor White
    $lineIdx++
    Write-Host (' ' + (& $pad $menuW) + (& $right $lineIdx)) -ForegroundColor Cyan
    $lineIdx++
    if ($chocoVer) {
        $t = '  [C] Upgrade Chocolatey'
        Write-Host '  ' -NoNewline
        Write-Host '[C] ' -NoNewline -ForegroundColor Magenta
        Write-Host ('Upgrade Chocolatey' + (& $pad ($menuW - $t.Length)) + (& $right $lineIdx)) -ForegroundColor White
    } else {
        $t = '  [C] Install Chocolatey'
        Write-Host '  ' -NoNewline
        Write-Host '[C] ' -NoNewline -ForegroundColor Magenta
        Write-Host ('Install Chocolatey' + (& $pad ($menuW - $t.Length)) + (& $right $lineIdx)) -ForegroundColor White
    }
    $lineIdx++
    $desc = if ($chocoVer) { '      |-- Install or update Chocolatey package manager' } else { '      |-- Install Chocolatey (required for other options)' }
    Write-Host ($desc + (& $pad ($menuW - $desc.Length)) + (& $right $lineIdx)) -ForegroundColor DarkGray
    $lineIdx++
    Write-Host ""
    $t = '  [U] Upgrade all installed packages'
    Write-Host '  ' -NoNewline
    Write-Host '[U] ' -NoNewline -ForegroundColor DarkCyan
    Write-Host ($t.Substring(6) + (& $pad ($menuW - $t.Length))) -ForegroundColor White
    Write-Host ('      |-- Upgrades all packages installed via Chocolatey') -ForegroundColor DarkGray
    Write-Host ""
    Write-Host '  [I] ' -NoNewline -ForegroundColor Yellow
    Write-Host "Install packages by category" -ForegroundColor White
    Write-Host '      |-- Development, Local, VM' -ForegroundColor DarkGray
    Write-Host ""
    Write-Host '  [S] ' -NoNewline -ForegroundColor Cyan
    Write-Host "Show installed packages list" -ForegroundColor White
    Write-Host '      |-- Displays all locally installed packages' -ForegroundColor DarkGray
    Write-Host ""
    Write-Host '  [M] ' -NoNewline -ForegroundColor Yellow
    Write-Host "Interactive package selection" -ForegroundColor White
    Write-Host '      |-- Choose which to install / uninstall (checkbox menu)' -ForegroundColor DarkGray
    Write-Host ""
    Write-Host '  [O] ' -NoNewline -ForegroundColor DarkCyan
    Write-Host "Settings" -ForegroundColor White
    Write-Host '      |-- Proxy, install to PATH, logs' -ForegroundColor DarkGray
    Write-Host ""
    Write-Host '  [Q] ' -NoNewline -ForegroundColor Red
    Write-Host "Exit" -ForegroundColor White
    Write-Host ""
    Write-Host '------------------------------------------------------------------' -ForegroundColor Cyan
}

function Show-Statistics {
    if ($script:totalPackages -le 0) { return }
    Write-Host ""
    Write-Host '+======================================================================+' -ForegroundColor DarkCyan
    Write-Host '|                            STATISTICS                                 |' -ForegroundColor DarkCyan
    Write-Host '+======================================================================+' -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  Total processed:         " -NoNewline -ForegroundColor White
    Write-Host "$($script:totalPackages)" -ForegroundColor Cyan
    Write-Host "  Successfully installed:  " -NoNewline -ForegroundColor White
    Write-Host "$($script:installedCount)" -ForegroundColor DarkCyan
    Write-Host "  Updated:                " -NoNewline -ForegroundColor White
    Write-Host "$($script:updatedCount)" -ForegroundColor Yellow
    Write-Host "  Failed:                 " -NoNewline -ForegroundColor White
    Write-Host "$($script:failedCount)" -ForegroundColor Red
    Write-Host ""
}

function Install-ChocopadToUserFolder {
    $targetDir = Join-Path $env:USERPROFILE 'chocopad'
    $scriptDir = $PSScriptRoot
    $batFile = Join-Path $scriptDir 'chocopad.bat'
    $ps1File = Join-Path $scriptDir 'choco_software.ps1'
    
    if (-not (Test-Path $batFile)) {
        Write-Host ""
        Write-Host "chocopad.bat not found in script folder." -ForegroundColor Red
        Write-Host ('  Script folder: ' + $scriptDir) -ForegroundColor Gray
        return $false
    }
    if (-not (Test-Path $ps1File)) {
        Write-Host ""
        Write-Host "choco_software.ps1 not found in script folder." -ForegroundColor Red
        return $false
    }
    
    Write-Host ""
    Write-Host ('  Target folder: ' + $targetDir) -ForegroundColor Cyan
    Write-Host ""
    
    try {
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            Write-Host "  Created folder." -ForegroundColor DarkCyan
        }
        Copy-Item $batFile (Join-Path $targetDir 'chocopad.bat') -Force
        Copy-Item $ps1File (Join-Path $targetDir 'choco_software.ps1') -Force
        $catPath = Join-Path $scriptDir 'categories.json'
        if (Test-Path $catPath) { Copy-Item $catPath (Join-Path $targetDir 'categories.json') -Force }
        foreach ($cat in $script:categories) {
            $src = Join-Path $scriptDir $cat.file
            if (Test-Path $src) { Copy-Item $src (Join-Path $targetDir $cat.file) -Force }
        }
        Write-Host "  Copied chocopad.bat, choco_software.ps1, categories and package lists" -ForegroundColor DarkCyan
        
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if (-not $userPath) { $userPath = '' }
        $pathDirs = $userPath -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        $alreadyInPath = ($pathDirs | Where-Object { $_ -eq $targetDir }).Count -gt 0
        if (-not $alreadyInPath) {
            $newPath = $userPath.TrimEnd(';') + ';' + $targetDir
            [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
            $env:Path = $env:Path + ';' + $targetDir
            Write-Host "  Added to user PATH." -ForegroundColor DarkCyan
        } else {
            Write-Host "  Already in PATH." -ForegroundColor Gray
        }
        
        Write-Host ""
        Write-Host "  Done! Open a new CMD or PowerShell window and run: chocopad" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host ('  Error: ' + $_.Exception.Message) -ForegroundColor Red
        return $false
    }
}

function Save-Settings {
    try {
        $configDir = Split-Path $script:settingsConfigPath -Parent
        if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }
        @{ proxyUrl = $script:proxyUrl; useProxy = $useProxy; logsEnabled = $script:logsEnabled } | ConvertTo-Json | Set-Content $script:settingsConfigPath -Encoding UTF8
    } catch { }
}

function Write-ChocopadLog {
    param([string]$Message, [string]$Level = 'INFO')
    if (-not $script:logsEnabled) { return }
    $logsDir = Join-Path $PSScriptRoot 'logs'
    if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null }
    $dateStr = Get-Date -Format 'yyyy-MM-dd'
    $logFile = Join-Path $logsDir "chocopad_$dateStr.log"
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp] [$Level] $Message"
    Add-Content -Path $logFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
}

function Reset-Statistics {
    $script:installedCount = 0
    $script:updatedCount = 0
    $script:failedCount = 0
    $script:totalPackages = 0
}

function Confirm-MassOperation {
    param(
        [string]$OperationName,
        [int]$PackageCount
    )
    
    Write-Host ""
    Write-Host "  WARNING: Batch operation" -ForegroundColor Yellow
    Write-Host "  Operation: $OperationName" -ForegroundColor White
    Write-Host "  Package count: $PackageCount" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Continue? (y/n): " -NoNewline -ForegroundColor Gray
    $confirm = Read-Host
    return ($confirm -eq "y" -or $confirm -eq "Y")
}

function Get-OutdatedPackages {
    param([switch]$ShowSpinner)
    if ($ShowSpinner) {
        $job = Start-Job -ScriptBlock { choco outdated --limit-output 2>$null }
        $chars = @('|', '/', '-', '\')
        $i = 0
        while ($job.State -eq 'Running') {
            Write-Host "`r  Checking for updates... $($chars[$i % 4])    " -NoNewline -ForegroundColor Gray
            Start-Sleep -Milliseconds 120
            $i++
        }
        Write-Host "`r  Checking for updates... done.    " -ForegroundColor Gray
        Write-Host ""
        $output = Receive-Job $job
        Remove-Job $job -Force
    } else {
        $output = choco outdated --limit-output 2>$null
    }
    $packages = @()
    foreach ($line in $output) {
        if ($line -match '\|' -and $line -notmatch '^Chocolatey') {
            $parts = $line -split '\|'
            if ($parts.Count -ge 3) {
                $packages += [PSCustomObject]@{
                    Name = $parts[0]
                    CurrentVersion = $parts[1]
                    AvailableVersion = $parts[2]
                }
            }
        }
    }
    return $packages
}

function Show-OutdatedPackagesList {
    param($packages)
    $colNum = 5
    $colPkg = 35
    $colCur = 18
    $colAvail = 18
    $totalWidth = 2 + 1 + $colNum + 1 + $colPkg + 1 + $colCur + 1 + $colAvail + 1
    
    Clear-Host
    Write-Host ""
    Write-Host "  +$('-' * ($totalWidth - 4))+"
    Write-Host '  |' -NoNewline
    $title = ' Packages to upgrade '
    Write-Host $title.PadRight($totalWidth - 5) -ForegroundColor White -BackgroundColor DarkGray -NoNewline
    Write-Host '|'
    Write-Host "  +$('-' * ($totalWidth - 4))+"
    Write-Host '  |' -NoNewline -ForegroundColor Cyan
    Write-Host (' # ').PadRight($colNum) -ForegroundColor White -NoNewline
    Write-Host '|' -NoNewline -ForegroundColor Cyan
    Write-Host (' Package ').PadRight($colPkg) -ForegroundColor White -NoNewline
    Write-Host '|' -NoNewline -ForegroundColor Cyan
    Write-Host (' Current ').PadRight($colCur) -ForegroundColor White -NoNewline
    Write-Host '|' -NoNewline -ForegroundColor Cyan
    Write-Host (' Available ').PadRight($colAvail) -ForegroundColor White -NoNewline
    Write-Host '|' -ForegroundColor Cyan
    Write-Host "  +$('-' * ($totalWidth - 4))+"
    
    for ($i = 0; $i -lt $packages.Count; $i++) {
        $p = $packages[$i]
        $num = ($i + 1).ToString().PadRight($colNum - 2)
        $pkg = $p.Name.PadRight($colPkg - 2)
        $cur = $p.CurrentVersion.PadRight($colCur - 2)
        $avail = $p.AvailableVersion.PadRight($colAvail - 2)
        Write-Host '  |' -NoNewline -ForegroundColor Cyan
        Write-Host " $num " -NoNewline -ForegroundColor Gray
        Write-Host '|' -NoNewline -ForegroundColor Cyan
        Write-Host " $pkg " -NoNewline -ForegroundColor White
        Write-Host '|' -NoNewline -ForegroundColor Cyan
        Write-Host " $cur " -NoNewline -ForegroundColor Gray
        Write-Host '|' -NoNewline -ForegroundColor Cyan
        Write-Host " $avail " -NoNewline -ForegroundColor DarkCyan
        Write-Host '|' -ForegroundColor Cyan
    }
    
    Write-Host "  +$('-' * ($totalWidth - 4))+"
    Write-Host ('  ' + $packages.Count + ' packages will be upgraded.') -ForegroundColor Gray
    Write-Host ""
}

function Get-InstalledPackages {
    $output = choco list 2>$null
    $packages = @()
    foreach ($line in $output) {
        if ($line -match '^\s*(\S+)\s+(.+)') {
            $name = $Matches[1]
            $ver = $Matches[2]
            if ($name -eq 'Chocolatey') { continue }
            if ($ver -match 'packages?\s+installed') { continue }
            if ($ver -imatch 'validation|warning|error|success|reboot|recommended|convenience|ignored|detected') { continue }
            if ($name -imatch 'validation|warning|error|^\-$|^\[|\]') { continue }
            if ($ver -notmatch '^\d') { continue }
            if ($name -notmatch '^[a-zA-Z0-9\.\-]+$') { continue }
            $packages += [PSCustomObject]@{ Name = $name; Version = $ver }
        }
    }
    return $packages
}

function Get-AvailablePackagesForInstall {
    $all = @()
    foreach ($cat in $script:categories) { $all += $cat.packages }
    $all = $all | Select-Object -Unique
    $installed = (Get-InstalledPackages).Name
    $available = $all | Where-Object { $_ -notin $installed }
    return $available | ForEach-Object {
        $pkg = $_
        $catName = ($script:categories | Where-Object { $pkg -in $_.packages } | Select-Object -First 1).name
        if (-not $catName) { $catName = 'Other' }
        [PSCustomObject]@{ Package = $pkg; Category = $catName }
    }
}

function Show-InstallCategoryMenu {
    Clear-Host
    Write-Host '+======================================================================+' -ForegroundColor Cyan
    Write-Host '|                 INSTALL PACKAGES BY CATEGORY                         |' -ForegroundColor Cyan
    Write-Host '+======================================================================+' -ForegroundColor Cyan
    Write-Host ""
    $i = 1
    foreach ($cat in $script:categories) {
        $color = $script:categoryColors[($i - 1) % $script:categoryColors.Count]
        Write-Host ('  [' + $i + '] ') -NoNewline -ForegroundColor $color
        Write-Host ($cat.name + ' ({0} pkgs)' -f $cat.packages.Count) -ForegroundColor White
        Write-Host ('      |-- ' + $cat.desc) -ForegroundColor Gray
        Write-Host ""
        $i++
    }
    Write-Host '  [E] ' -NoNewline -ForegroundColor Green
    Write-Host 'Edit package lists' -ForegroundColor White
    Write-Host '      |-- Edit, add or delete categories' -ForegroundColor Gray
    Write-Host ""
    Write-Host '  [0] ' -NoNewline -ForegroundColor Gray
    Write-Host "Back to main menu" -ForegroundColor White
    Write-Host ""
    Write-Host '=======================================================================' -ForegroundColor Cyan
}

function Show-InstalledPackagesList {
    $packages = Get-InstalledPackages
    $colNum = 5
    $colPkg = 40
    $colVer = 20
    $totalWidth = 2 + 1 + $colNum + 1 + $colPkg + 1 + $colVer + 1
    
    Clear-Host
    Write-Host ""
    Write-Host "  +$('-' * ($totalWidth - 4))+"
    Write-Host '  |' -NoNewline
    $instTitle = ' Installed Packages '
    Write-Host $instTitle.PadRight($totalWidth - 5) -ForegroundColor White -BackgroundColor DarkGray -NoNewline
    Write-Host '|'
    Write-Host "  +$('-' * ($totalWidth - 4))+"
    Write-Host '  |' -NoNewline -ForegroundColor Cyan
    Write-Host (' # ').PadRight($colNum) -ForegroundColor White -NoNewline
    Write-Host '|' -NoNewline -ForegroundColor Cyan
    Write-Host (' Package ').PadRight($colPkg) -ForegroundColor White -NoNewline
    Write-Host '|' -NoNewline -ForegroundColor Cyan
    Write-Host (' Version ').PadRight($colVer) -ForegroundColor White -NoNewline
    Write-Host '|' -ForegroundColor Cyan
    Write-Host "  +$('-' * ($totalWidth - 4))+"
    
    for ($i = 0; $i -lt $packages.Count; $i++) {
        $p = $packages[$i]
        $num = ($i + 1).ToString().PadRight($colNum - 2)
        $pkg = $p.Name.PadRight($colPkg - 2)
        $ver = $p.Version.PadRight($colVer - 2)
        Write-Host '  |' -NoNewline -ForegroundColor Cyan
        Write-Host " $num " -NoNewline -ForegroundColor Gray
        Write-Host '|' -NoNewline -ForegroundColor Cyan
        Write-Host " $pkg " -NoNewline -ForegroundColor White
        Write-Host '|' -NoNewline -ForegroundColor Cyan
        Write-Host " $ver " -NoNewline -ForegroundColor Gray
        Write-Host '|' -ForegroundColor Cyan
    }
    
    Write-Host "  +$('-' * ($totalWidth - 4))+"
    Write-Host ('  ' + $packages.Count + ' packages installed.') -ForegroundColor Gray
    Write-Host ""
}

function Show-PackagesToInstallList {
    param(
        [string]$Title,
        [array]$Packages
    )
    $colNum = 5
    $colPkg = 50
    $totalWidth = 2 + 1 + $colNum + 1 + $colPkg + 1
    
    Clear-Host
    Write-Host ""
    Write-Host "  +$('-' * ($totalWidth - 4))+"
    Write-Host '  |' -NoNewline
    $titlePadded = (' ' + $Title + ' ').PadRight($totalWidth - 5)
    Write-Host $titlePadded -ForegroundColor White -BackgroundColor DarkGray -NoNewline
    Write-Host '|'
    Write-Host "  +$('-' * ($totalWidth - 4))+"
    Write-Host '  |' -NoNewline -ForegroundColor Cyan
    Write-Host (' # ').PadRight($colNum) -ForegroundColor White -NoNewline
    Write-Host '|' -NoNewline -ForegroundColor Cyan
    Write-Host (' Package ').PadRight($colPkg) -ForegroundColor White -NoNewline
    Write-Host '|' -ForegroundColor Cyan
    Write-Host "  +$('-' * ($totalWidth - 4))+"
    
    for ($j = 0; $j -lt $Packages.Count; $j++) {
        $num = ($j + 1).ToString().PadRight($colNum - 2)
        $pkg = $Packages[$j].PadRight($colPkg - 2)
        Write-Host '  |' -NoNewline -ForegroundColor Cyan
        Write-Host " $num " -NoNewline -ForegroundColor Gray
        Write-Host '|' -NoNewline -ForegroundColor Cyan
        Write-Host " $pkg " -NoNewline -ForegroundColor White
        Write-Host '|' -ForegroundColor Cyan
    }
    
    Write-Host "  +$('-' * ($totalWidth - 4))+"
    Write-Host ('  ' + $Packages.Count + ' packages will be installed.') -ForegroundColor Gray
    Write-Host ""
    Write-Host '  Press Enter to continue...' -ForegroundColor Gray
    Read-Host
}

function Show-InteractivePackageMenu {
    Clear-Host
    Write-Host '+======================================================================+' -ForegroundColor Cyan
    Write-Host '|              INTERACTIVE PACKAGE SELECTION                          |' -ForegroundColor Cyan
    Write-Host '+======================================================================+' -ForegroundColor Cyan
    Write-Host ""
    Write-Host '  [1] ' -NoNewline -ForegroundColor DarkCyan
    Write-Host "Install packages (select from list)" -ForegroundColor White
    Write-Host '      |-- Opens checkbox menu to select packages' -ForegroundColor Gray
    Write-Host ""
    Write-Host '  [2] ' -NoNewline -ForegroundColor Red
    Write-Host "Uninstall packages (select from installed)" -ForegroundColor White
    Write-Host '      |-- Opens checkbox menu to select packages for removal' -ForegroundColor Gray
    Write-Host ""
    Write-Host '  [3] ' -NoNewline -ForegroundColor Yellow
    Write-Host "Install single package (enter name)" -ForegroundColor White
    Write-Host '      |-- Enter package name to install from Chocolatey' -ForegroundColor Gray
    Write-Host ""
    Write-Host '  [0] ' -NoNewline -ForegroundColor Gray
    Write-Host "Back to main menu" -ForegroundColor White
    Write-Host ""
    Write-Host '=======================================================================' -ForegroundColor Cyan
}

function Show-TUISelectMenu {
    param(
        [string]$Title,
        [string]$Prompt,
        [array]$Items,
        [string]$ValueProperty,
        [string]$DisplayProperty,
        [string]$CategoryProperty = $null
    )
    $selected = @{}
    foreach ($i in 0..($Items.Count - 1)) { $selected[$i] = $false }
    $cursor = 0
    $scrollOffset = 0
    
    try { $menuWidth = [Console]::WindowWidth - 2 } catch { $menuWidth = 78 }
    try { $visibleRows = [Console]::WindowHeight - 8 } catch { $visibleRows = 20 }
    if ($visibleRows -lt 5) { $visibleRows = 5 }
    
    function Get-ItemLine {
        param($item, $sel, $valProp, $dispProp, $catProp)
        $disp = $item.$dispProp
        $cat = if ($catProp -and $item.$catProp) { "  $($item.$catProp)" } else { "" }
        $check = if ($sel) { '[*]' } else { '[ ]' }
        return "  $check $disp$cat"
    }
    
    function Draw-MenuFull {
        param($title, $prompt, $items, $sel, $cur, $scroll, $visible, $valProp, $dispProp, $catProp, $width)
        Clear-Host
        Write-Host ""
        Write-Host "  $title"
        Write-Host "  $prompt"
        Write-Host "  $('-' * $width)"
        $endIdx = [Math]::Min($scroll + $visible, $items.Count)
        for ($i = $scroll; $i -lt $endIdx; $i++) {
            $item = $items[$i]
            $line = (Get-ItemLine -item $item -sel $sel[$i] -valProp $valProp -dispProp $dispProp -catProp $catProp).PadRight($width)
            if ($i -eq $cur) {
                Write-Host $line -ForegroundColor Black -BackgroundColor DarkCyan
            } else {
                $catVal = if ($catProp) { $item.$catProp } else { $null }
                $fg = switch ($catVal) { "Development" { "Red" } "VM" { "Blue" } default { "White" } }
                Write-Host $line -ForegroundColor $fg
            }
        }
        Write-Host "  $('-' * $width)"
        $scrollInfo = if ($items.Count -gt $visible) { "  [$($scroll+1)-$endIdx / $($items.Count)]" } else { "" }
        Write-Host ('  < Enter - confirm >  < Esc >  < Space >  < PgUp/PgDn - page >' + $scrollInfo)
    }
    
    do {
        Draw-MenuFull -title $Title -prompt $Prompt -items $Items -sel $selected -cur $cursor -scroll $scrollOffset -visible $visibleRows -valProp $ValueProperty -dispProp $DisplayProperty -catProp $CategoryProperty -width $menuWidth
        
        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        switch ($key.VirtualKeyCode) {
            33 {
                $cursor = [Math]::Max(0, $cursor - $visibleRows)
                $scrollOffset = [Math]::Max(0, $scrollOffset - $visibleRows)
            }
            34 {
                $cursor = [Math]::Min($Items.Count - 1, $cursor + $visibleRows)
                $maxScroll = [Math]::Max(0, $Items.Count - $visibleRows)
                $scrollOffset = [Math]::Min($maxScroll, [Math]::Max(0, $cursor - $visibleRows + 1))
            }
            38 {
                if ($cursor -gt 0) {
                    $cursor--
                    if ($cursor -lt $scrollOffset) { $scrollOffset = [Math]::Max(0, $cursor) }
                }
            }
            40 {
                if ($cursor -lt $Items.Count - 1) {
                    $cursor++
                    if ($cursor -ge $scrollOffset + $visibleRows) { $scrollOffset = $cursor - $visibleRows + 1 }
                }
            }
            32 { $selected[$cursor] = -not $selected[$cursor] }
            27 { return $null }
            13 { break }
        }
    } while ($key.VirtualKeyCode -ne 13)
    
    $result = @()
    foreach ($i in 0..($Items.Count - 1)) {
        if ($selected[$i]) { $result += $Items[$i].$ValueProperty }
    }
    return $result
}

function Invoke-InteractiveInstall {
    $available = Get-AvailablePackagesForInstall
    if ($available.Count -eq 0) {
        Write-Host ""
        Write-Host "All packages from the list are already installed!" -ForegroundColor DarkCyan
        return
    }
    $toInstall = Show-TUISelectMenu -Title "Select packages to install" -Prompt "Space - select, Enter - install selected, Esc - cancel" -Items $available -ValueProperty "Package" -DisplayProperty "Package" -CategoryProperty "Category"
    if ($null -eq $toInstall -or $toInstall.Count -eq 0) {
        Write-Host "Selection cancelled." -ForegroundColor Yellow
        return
    }
    Write-Host ""
    Write-Host "  Install $($toInstall.Count) package(s)? (y/n): " -NoNewline -ForegroundColor Gray
    $confirm = Read-Host
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Host "  Cancelled." -ForegroundColor Yellow
        return
    }
    Write-Host ""
    Write-Host "Installing $($toInstall.Count) package(s)..." -ForegroundColor DarkCyan
    Reset-Statistics
    foreach ($pkg in $toInstall) {
        Install-PackageWithStats $pkg
    }
    Show-Statistics
    Write-Host ""
    Write-Host "  Press Enter to continue..." -ForegroundColor Gray
    Read-Host
}

function Invoke-InstallSinglePackage {
    Write-Host ""
    Write-Host "  Package name (e.g. notepadplusplus, vlc): " -NoNewline -ForegroundColor Gray
    $pkgName = Read-Host
    $pkgName = $pkgName.Trim()
    if (-not $pkgName) {
        Write-Host "  Cancelled." -ForegroundColor Yellow
        return
    }
    Write-Host ""
    Reset-Statistics
    Install-PackageWithStats $pkgName
    Show-Statistics
    Write-Host ""
    Write-Host "  Press Enter to continue..." -ForegroundColor Gray
    Read-Host
}

function Invoke-InteractiveUninstall {
    $installed = Get-InstalledPackages
    if ($installed.Count -eq 0) {
        Write-Host ""
        Write-Host "No Chocolatey packages installed." -ForegroundColor Yellow
        return
    }
    $toRemove = Show-TUISelectMenu -Title "Select packages to uninstall" -Prompt "Space - select, Enter - uninstall selected, Esc - cancel" -Items $installed -ValueProperty "Name" -DisplayProperty "Name" -CategoryProperty "Version"
    if ($null -eq $toRemove -or $toRemove.Count -eq 0) {
        Write-Host "Selection cancelled." -ForegroundColor Yellow
        return
    }
    Write-Host ""
    Write-Host "  Uninstall $($toRemove.Count) package(s)? (y/n): " -NoNewline -ForegroundColor Gray
    $confirm = Read-Host
    if ($confirm -ne "y" -and $confirm -ne "Y") { return }
    foreach ($pkg in $toRemove) {
        Write-Host "  Uninstalling: $pkg" -ForegroundColor Cyan
        & choco uninstall $pkg -y
        if ($LASTEXITCODE -eq 0) {
            Write-Host '    [OK] Uninstalled' -ForegroundColor DarkCyan
            Write-ChocopadLog "Uninstalled: $pkg" 'OK'
        } else {
            Write-Host '    [X] Error' -ForegroundColor Red
            Write-ChocopadLog "Uninstall failed: $pkg" 'ERROR'
        }
    }
}

function Install-PackageWithStats {
    param(
        [string]$PackageName
    )
    
    $script:totalPackages++
    Write-Host ('  [' + $script:totalPackages + '] Installing: ') -NoNewline -ForegroundColor Cyan
    Write-Host "$PackageName" -ForegroundColor White
    
    try {
        & choco install $PackageName -y
        if ($LASTEXITCODE -eq 0) {
            $script:installedCount++
            Write-Host '    [OK] Success' -ForegroundColor DarkCyan
            Write-ChocopadLog "Installed: $PackageName" 'OK'
        } else {
            $script:failedCount++
            Write-Host '    [X] Install failed' -ForegroundColor Red
            Write-ChocopadLog "Install failed: $PackageName" 'ERROR'
        }
    }
    catch {
        $script:failedCount++
        Write-Host ('    [X] Error: ' + $_.Exception.Message) -ForegroundColor Red
        Write-ChocopadLog "Install error: $PackageName - $($_.Exception.Message)" 'ERROR'
    }
}


# Check and fix execution policy first
if (-not (Test-ExecutionPolicy)) {
    Write-Host "Failed to fix execution policy. Exiting." -ForegroundColor Red
    Write-Host "  Press Enter to exit" -ForegroundColor Gray
    Read-Host
    exit 1
}

if (-not (Test-Admin)) {
    Write-Host "Script is not running as Administrator. Restarting with elevated privileges..." -ForegroundColor Yellow
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}


Write-Host "Running with Administrator privileges..." -ForegroundColor DarkCyan

# Check if Chocolatey is installed (menu will show status and [C] option)
if (Test-Chocolatey) {
    Write-Host "Chocolatey found in the system." -ForegroundColor DarkCyan
} else {
    Write-Host "Chocolatey not found. Use [C] in menu to install." -ForegroundColor Yellow
}

# Set proxy if enabled
if ($useProxy) {
    $env:http_proxy = $script:proxyUrl
    $env:https_proxy = $script:proxyUrl
    Write-Host "Proxy enabled: $script:proxyUrl" -ForegroundColor Cyan
} else {
    Write-Host "Proxy disabled" -ForegroundColor Cyan
}

# Main menu loop
do {
    Show-ColorMenu
    Write-Host "  Enter command: " -NoNewline -ForegroundColor Gray
    $action = Read-Host
    
    switch ($action.ToLower()) {
        'c' {
            if (Test-Chocolatey) {
                Write-Host ""
                Write-Host "Upgrading Chocolatey..." -ForegroundColor DarkCyan
                choco upgrade chocolatey -y
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "Chocolatey upgraded successfully." -ForegroundColor DarkCyan
                    Write-ChocopadLog "Chocolatey upgraded" 'OK'
                } else {
                    Write-Host "Upgrade failed or already up to date." -ForegroundColor Yellow
                    Write-ChocopadLog "Chocolatey upgrade failed or already up to date" 'WARN'
                }
                Write-Host ""
                Write-Host "Press Enter to continue..." -ForegroundColor Gray
                Read-Host
            } else {
                Write-Host ""
                if (Install-Chocolatey) {
                    Write-Host ""
                    Write-Host "Chocolatey installed successfully. You can now use other menu options." -ForegroundColor DarkCyan
                    Write-ChocopadLog "Chocolatey installed" 'OK'
                } else {
                    Write-Host ""
                    Write-Host "Failed to install Chocolatey." -ForegroundColor Red
                    Write-ChocopadLog "Chocolatey install failed" 'ERROR'
                }
                Write-Host ""
                Write-Host "Press Enter to continue..." -ForegroundColor Gray
                Read-Host
            }
            break
        }
        'u' {
            if (-not (Test-Chocolatey)) {
                Write-Host ""
                Write-Host "Chocolatey not installed. Use [C] to install." -ForegroundColor Yellow
                Write-Host ""
                break
            }
            Write-Host ""
            $outdated = Get-OutdatedPackages -ShowSpinner
            if ($outdated.Count -eq 0) {
                Write-Host ""
                Write-Host "  All packages are up to date." -ForegroundColor Gray
            } else {
                Show-OutdatedPackagesList -packages $outdated
                if (Confirm-MassOperation "Upgrade all packages" $outdated.Count) {
                    Write-Host ""
                    Write-Host "  Upgrading packages..." -ForegroundColor DarkCyan
                    Reset-Statistics
                    choco upgrade all -y
                    Write-Host ""
                    Write-Host "  Upgrade completed." -ForegroundColor DarkCyan
                    Write-ChocopadLog "Upgrade all packages completed (exit: $LASTEXITCODE)" $(if ($LASTEXITCODE -eq 0) { 'OK' } else { 'WARN' })
                }
            }
            break
        }
        'i' {
            if (-not (Test-Chocolatey)) {
                Write-Host ""
                Write-Host "Chocolatey not installed. Use [C] to install." -ForegroundColor Yellow
                Write-Host ""
                break
            }
            do {
                Show-InstallCategoryMenu
                Write-Host "  Enter command: " -NoNewline -ForegroundColor Gray
                $catAction = Read-Host
                switch ($catAction.ToLower()) {
                    'e' {
                        do {
                            Clear-Host
                            Write-Host ""
                            Write-Host "  Manage categories" -ForegroundColor Cyan
                            Write-Host ""
                            $ei = 1
                            foreach ($cat in $script:categories) {
                                $ec = $script:categoryColors[($ei - 1) % $script:categoryColors.Count]
                                Write-Host ('  [' + $ei + '] ') -NoNewline -ForegroundColor $ec
                                Write-Host ($cat.name + ' (' + $cat.file + ', ' + $cat.packages.Count + ' pkgs)') -ForegroundColor White
                                $ei++
                            }
                            Write-Host ""
                            Write-Host '  [N] ' -NoNewline -ForegroundColor Green
                            Write-Host 'New category' -ForegroundColor White
                            Write-Host '  [D] ' -NoNewline -ForegroundColor Red
                            Write-Host 'Delete category' -ForegroundColor White
                            Write-Host '  [0] ' -NoNewline -ForegroundColor Gray
                            Write-Host 'Back' -ForegroundColor White
                            Write-Host ""
                            Write-Host "  Enter command: " -NoNewline -ForegroundColor Gray
                            $editAction = Read-Host
                            $editNum = 0
                            if ([int]::TryParse($editAction, [ref]$editNum) -and $editNum -ge 1 -and $editNum -le $script:categories.Count) {
                                $cat = $script:categories[$editNum - 1]
                                Edit-PackageList -FileName $cat.file -CategoryName $cat.name
                                $cat.packages = @(Get-PackagesFromFile $cat.file)
                                Write-Host ('  Reloaded: ' + $cat.packages.Count + ' packages') -ForegroundColor DarkCyan
                                Write-Host ""
                                Write-Host "  Press Enter to continue..." -ForegroundColor Gray
                                Read-Host
                            } elseif ($editAction -eq 'n' -or $editAction -eq 'N') {
                                Write-Host ""
                                Write-Host "  Category name: " -NoNewline -ForegroundColor Gray
                                $newName = Read-Host
                                if ($newName -and $newName.Trim()) {
                                    $newId = ($newName.Trim() -replace '[^a-zA-Z0-9]', '').ToLower()
                                    if (-not $newId) { $newId = 'cat' + ($script:categories.Count + 1) }
                                    $newFile = 'packages_' + $newId + '.txt'
                                    $newPath = Join-Path $PSScriptRoot $newFile
                                    if (Test-Path $newPath) {
                                        Write-Host "  File already exists. Use different name." -ForegroundColor Red
                                    } else {
                                        '' | Set-Content $newPath -Encoding UTF8
                                        Write-Host "  Description: " -NoNewline -ForegroundColor Gray
                                        $newDesc = Read-Host
                                        if (-not $newDesc) { $newDesc = $newName }
                                        $newCat = [PSCustomObject]@{ id = $newId; name = $newName.Trim(); file = $newFile; desc = $newDesc; packages = @() }
                                        $script:categories += $newCat
                                        Save-Categories
                                        Write-Host ('  Created category: ' + $newName) -ForegroundColor Green
                                    }
                                }
                                Write-Host ""
                                Write-Host "  Press Enter to continue..." -ForegroundColor Gray
                                Read-Host
                            } elseif ($editAction -eq 'd' -or $editAction -eq 'D') {
                                if ($script:categories.Count -eq 0) {
                                    Write-Host "  No categories to delete." -ForegroundColor Yellow
                                    Start-Sleep -Seconds 2
                                } else {
                                    Write-Host ""
                                    Write-Host "  Select category to delete (number, 0 to cancel): " -NoNewline -ForegroundColor Gray
                                    $delNum = 0
                                    $delInput = Read-Host
                                    if ([int]::TryParse($delInput, [ref]$delNum) -and $delNum -ge 1 -and $delNum -le $script:categories.Count) {
                                        $delCat = $script:categories[$delNum - 1]
                                        Write-Host ""
                                        Write-Host ('  Delete "' + $delCat.name + '" and ' + $delCat.file + '? (y/n): ') -NoNewline -ForegroundColor Yellow
                                        $confirm = Read-Host
                                        if ($confirm -eq 'y' -or $confirm -eq 'Y') {
                                            $script:categories = @($script:categories | Where-Object { $_.id -ne $delCat.id })
                                            Save-Categories
                                            $delPath = Join-Path $PSScriptRoot $delCat.file
                                            if (Test-Path $delPath) { Remove-Item $delPath -Force }
                                            Write-Host "  Category deleted." -ForegroundColor Green
                                        }
                                    }
                                    Write-Host ""
                                    Write-Host "  Press Enter to continue..." -ForegroundColor Gray
                                    Read-Host
                                }
                            } elseif ($editAction -ne '0') {
                                Write-Host '  Unknown command' -ForegroundColor Red
                                Start-Sleep -Seconds 1
                            }
                        } while ($editAction -ne '0')
                        break
                    }
                    '0' { break }
                    default {
                        $idx = 0
                        if ([int]::TryParse($catAction, [ref]$idx) -and $idx -ge 1 -and $idx -le $script:categories.Count) {
                            $cat = $script:categories[$idx - 1]
                            Show-PackagesToInstallList -Title ('Packages to install (' + $cat.name + ')') -Packages $cat.packages
                            if (Confirm-MassOperation ('Install ' + $cat.name + ' packages') $cat.packages.Count) {
                                Write-Host ""
                                Write-Host ('Installing ' + $cat.name + ' packages...') -ForegroundColor Cyan
                                Reset-Statistics
                                foreach ($package in $cat.packages) {
                                    Install-PackageWithStats $package
                                }
                                Show-Statistics
                                Write-Host ""
                                Write-Host "  Press Enter to continue..." -ForegroundColor Gray
                                Read-Host
                            }
                        } else {
                            Write-Host 'Unknown command' -ForegroundColor Red
                        }
                        break
                    }
                }
            } while ($catAction.ToLower() -ne '0')
            break
        }
        's' {
            if (-not (Test-Chocolatey)) {
                Write-Host ""
                Write-Host "Chocolatey not installed. Use [C] to install." -ForegroundColor Yellow
                Write-Host ""
                break
            }
            Show-InstalledPackagesList
            Write-Host "  Press Enter to return to menu" -ForegroundColor Gray
            Read-Host
            break
        }
        'm' {
            if (-not (Test-Chocolatey)) {
                Write-Host ""
                Write-Host "Chocolatey not installed. Use [C] to install." -ForegroundColor Yellow
                Write-Host ""
                break
            }
            do {
                Show-InteractivePackageMenu
                Write-Host "  Enter command: " -NoNewline -ForegroundColor Gray
                $subAction = Read-Host
                switch ($subAction) {
                    '1' { Invoke-InteractiveInstall; break }
                    '2' { Invoke-InteractiveUninstall; break }
                    '3' { Invoke-InstallSinglePackage; break }
                    '0' { break }
                    default {
                        Write-Host 'Unknown command' -ForegroundColor Red
                    }
                }
            } while ($subAction -ne '0')
            break
        }
        'o' {
            do {
                Clear-Host
                Write-Host ""
                Write-Host "  Settings" -ForegroundColor Cyan
                Write-Host ""
                Write-Host '  [1] ' -NoNewline -ForegroundColor Yellow
                Write-Host "Proxy configure" -ForegroundColor White
                Write-Host ('      |-- Configure proxy URL and toggle usage (' + $script:proxyUrl + ')') -ForegroundColor DarkGray
                Write-Host ""
                Write-Host '  [2] ' -NoNewline -ForegroundColor Green
                Write-Host 'Install to user folder and add to PATH' -ForegroundColor White
                $chocopadPath = (Join-Path $env:USERPROFILE 'chocopad')
                Write-Host ('      |-- Copy to ' + $chocopadPath + ', add to PATH for chocopad command') -ForegroundColor DarkGray
                Write-Host ""
                Write-Host '  [3] ' -NoNewline -ForegroundColor Magenta
                Write-Host 'Logs' -ForegroundColor White
                $logsStatus = if ($script:logsEnabled) { 'ON' } else { 'OFF' }
                $logsStatusColor = if ($script:logsEnabled) { 'Green' } else { 'Gray' }
                Write-Host ('      |-- Save operation logs to logs folder (current: ' + $logsStatus + ')') -ForegroundColor DarkGray
                Write-Host ""
                Write-Host '  [0] ' -NoNewline -ForegroundColor Gray
                Write-Host 'Back to menu' -ForegroundColor White
                Write-Host ""
                Write-Host "  Enter command: " -NoNewline -ForegroundColor Gray
                $oAction = Read-Host
                switch ($oAction) {
                    '1' {
                        Clear-Host
                        Write-Host ""
                        Write-Host "  Proxy settings" -ForegroundColor Cyan
                        Write-Host ""
                        Write-Host ('  Current URL: ' + $script:proxyUrl) -ForegroundColor White
                        $status = if ($useProxy) { 'ON' } else { 'OFF' }
                        $statusColor = if ($useProxy) { 'Green' } else { 'Gray' }
                        Write-Host ('  Status: ' + $status) -ForegroundColor $statusColor
                        Write-Host ""
                        Write-Host '  [1] ' -NoNewline -ForegroundColor Yellow
                        Write-Host 'Toggle proxy on/off' -ForegroundColor White
                        Write-Host '  [2] ' -NoNewline -ForegroundColor Yellow
                        Write-Host 'Change proxy URL' -ForegroundColor White
                        Write-Host '  [0] ' -NoNewline -ForegroundColor Gray
                        Write-Host 'Back' -ForegroundColor White
                        Write-Host ""
                        Write-Host "  Enter command: " -NoNewline -ForegroundColor Gray
                        $pAction = Read-Host
                        switch ($pAction) {
                            '1' {
                                $useProxy = -not $useProxy
                                if ($useProxy) {
                                    $env:http_proxy = $script:proxyUrl
                                    $env:https_proxy = $script:proxyUrl
                                    Write-Host ""
                                    Write-Host "  Proxy enabled." -ForegroundColor DarkCyan
                                } else {
                                    Remove-Item Env:http_proxy -ErrorAction SilentlyContinue
                                    Remove-Item Env:https_proxy -ErrorAction SilentlyContinue
                                    Write-Host ""
                                    Write-Host "  Proxy disabled." -ForegroundColor DarkCyan
                                }
                                Save-Settings
                                Write-Host ""
                                Write-Host "  Press Enter to continue..." -ForegroundColor Gray
                                Read-Host
                            }
                            '2' {
                                Write-Host ""
                                Write-Host ('  Current: ' + $script:proxyUrl) -ForegroundColor Gray
                                Write-Host "  New proxy URL (Enter to cancel): " -NoNewline -ForegroundColor Gray
                                $newUrl = Read-Host
                                if ($newUrl -and $newUrl.Trim()) {
                                    $script:proxyUrl = $newUrl.Trim()
                                    if ($useProxy) {
                                        $env:http_proxy = $script:proxyUrl
                                        $env:https_proxy = $script:proxyUrl
                                    }
                                    Save-Settings
                                    Write-Host ""
                                    Write-Host ('  Proxy URL updated to: ' + $script:proxyUrl) -ForegroundColor DarkCyan
                                }
                                Write-Host ""
                                Write-Host "  Press Enter to continue..." -ForegroundColor Gray
                                Read-Host
                            }
                            '0' { }
                            default { Write-Host '  Unknown command' -ForegroundColor Red; Start-Sleep -Seconds 1 }
                        }
                    }
                    '2' {
                        Write-Host ""
                        Write-Host "  Install chocopad to user folder?" -ForegroundColor White
                        Write-Host ('  Target: ' + (Join-Path $env:USERPROFILE 'chocopad')) -ForegroundColor Gray
                        Write-Host "  This will add the folder to PATH so you can run 'chocopad' from any terminal." -ForegroundColor Gray
                        Write-Host ""
                        Write-Host "  Continue? (y/n): " -NoNewline -ForegroundColor Gray
                        $confirm = Read-Host
                        if ($confirm -eq 'y' -or $confirm -eq 'Y') {
                            Install-ChocopadToUserFolder
                        }
                        Write-Host ""
                        Write-Host "  Press Enter to continue..." -ForegroundColor Gray
                        Read-Host
                    }
                    '3' {
                        $script:logsEnabled = -not $script:logsEnabled
                        Save-Settings
                        $logsStatus = if ($script:logsEnabled) { 'enabled' } else { 'disabled' }
                        $logsPath = Join-Path $PSScriptRoot 'logs'
                        Write-Host ""
                        Write-Host ("  Logs " + $logsStatus + ".") -ForegroundColor DarkCyan
                        if ($script:logsEnabled) {
                            Write-Host ("  Logs will be saved to: " + $logsPath) -ForegroundColor Gray
                        }
                        Write-Host ""
                        Write-Host "  Press Enter to continue..." -ForegroundColor Gray
                        Read-Host
                    }
                    '0' { break }
                    default { Write-Host '  Unknown command' -ForegroundColor Red; Start-Sleep -Seconds 1 }
                }
            } while ($oAction -ne '0')
            break
        }
        'q' {
            Write-Host ""
            Write-Host 'Goodbye!' -ForegroundColor DarkCyan
            break
        }
        default {
            Write-Host ""
            Write-Host ('Unknown command: ' + $action) -ForegroundColor Red
        }
    }
    
} while ($action.ToLower() -ne 'q')

# Clean up proxy environment variables
if ($useProxy) {
    Remove-Item Env:http_proxy -ErrorAction SilentlyContinue
    Remove-Item Env:https_proxy -ErrorAction SilentlyContinue
    Write-Host 'Proxy environment variables cleared' -ForegroundColor DarkCyan
}