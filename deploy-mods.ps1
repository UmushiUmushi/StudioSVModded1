# ============================================================
# Stardew Valley Mod Deployer
# Double-click setup.bat to run this script
# ============================================================

# Auto-elevate to admin if not already running as admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

$ErrorActionPreference = "Stop"

$RepoUrl = "https://github.com/UmushiUmushi/StudioSVModded1.git"

# ---- Functions ----

function Find-StardewValley {
    $candidates = @()

    # Steam default
    $steamDefault = "C:\Program Files (x86)\Steam\steamapps\common\Stardew Valley"
    if (Test-Path $steamDefault) { $candidates += $steamDefault }

    # Parse Steam library folders
    $libraryFile = "C:\Program Files (x86)\Steam\steamapps\libraryfolders.vdf"
    if (Test-Path $libraryFile) {
        $content = Get-Content $libraryFile -Raw
        $paths = [regex]::Matches($content, '"path"\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value -replace '\\\\', '\' }
        foreach ($libPath in $paths) {
            $candidate = Join-Path $libPath "steamapps\common\Stardew Valley"
            if ((Test-Path $candidate) -and ($candidates -notcontains $candidate)) {
                $candidates += $candidate
            }
        }
    }

    # GOG default
    $gogDefault = "C:\Program Files (x86)\GOG Galaxy\Games\Stardew Valley"
    if (Test-Path $gogDefault) { $candidates += $gogDefault }

    # Xbox / MS Store
    $xboxPaths = @(
        "C:\Program Files\ModifiableWindowsApps\Stardew Valley",
        "C:\XboxGames\Stardew Valley\Content"
    )
    foreach ($xp in $xboxPaths) {
        if (Test-Path $xp) { $candidates += $xp }
    }

    return $candidates
}

function Show-FolderPicker {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Select your Stardew Valley installation folder (the one containing Stardew Valley.exe)"
    $dialog.ShowNewFolderButton = $false
    $result = $dialog.ShowDialog()
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    }
    return $null
}

function Test-GitInstalled {
    try {
        $null = git --version 2>&1
        return $true
    } catch {
        return $false
    }
}

function Install-GitPortable {
    param([string]$TempDir)

    $gitZipUrl = "https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.2/MinGit-2.47.1.2-64-bit.zip"
    $gitZip = Join-Path $TempDir "mingit.zip"
    $gitDir = Join-Path $TempDir "mingit"

    Write-Host "Downloading portable Git..." -ForegroundColor Yellow
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $gitZipUrl -OutFile $gitZip -UseBasicParsing

    Write-Host "Extracting Git..." -ForegroundColor Yellow
    Expand-Archive -Path $gitZip -DestinationPath $gitDir -Force
    Remove-Item $gitZip -Force

    $env:PATH = (Join-Path $gitDir "cmd") + ";" + $env:PATH
    return $gitDir
}

# ---- Main ----

try {

Clear-Host
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Stardew Valley Mod Deployer" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check for Git
$gitPortableDir = $null
if (-not (Test-GitInstalled)) {
    Write-Host "Git is not installed. Downloading a portable copy..." -ForegroundColor Yellow
    $tempDir = Join-Path $env:TEMP "sv-mod-deploy"
    if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }
    try {
        $gitPortableDir = Install-GitPortable -TempDir $tempDir
    } catch {
        Write-Host "ERROR: Failed to download Git. Please install Git manually from https://git-scm.com" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }
}

# Find Stardew Valley
Write-Host "Looking for Stardew Valley..." -ForegroundColor Yellow
$found = @(Find-StardewValley)

if ($found.Count -eq 0) {
    Write-Host "Could not auto-detect Stardew Valley. Please select the folder manually." -ForegroundColor Yellow
    $svPath = Show-FolderPicker
    if (-not $svPath) {
        Write-Host "No folder selected. Exiting." -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }
} elseif ($found.Count -eq 1) {
    $svPath = $found[0]
    Write-Host "Found Stardew Valley at: $svPath" -ForegroundColor Green
} else {
    Write-Host "Found multiple installations:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $found.Count; $i++) {
        Write-Host "  [$($i + 1)] $($found[$i])"
    }
    Write-Host "  [$($found.Count + 1)] Choose a different folder"
    $choice = Read-Host "Select installation (1-$($found.Count + 1))"
    $idx = [int]$choice - 1
    if ($idx -ge 0 -and $idx -lt $found.Count) {
        $svPath = $found[$idx]
    } else {
        $svPath = Show-FolderPicker
        if (-not $svPath) {
            Write-Host "No folder selected. Exiting." -ForegroundColor Red
            Read-Host "Press Enter to exit"
            exit 1
        }
    }
}

# Validate
$exePath = Join-Path $svPath "Stardew Valley.dll"
$exePath2 = Join-Path $svPath "StardewValley.exe"
if (-not (Test-Path $exePath) -and -not (Test-Path $exePath2)) {
    Write-Host "WARNING: This doesn't look like a Stardew Valley folder (no game executable found)." -ForegroundColor Yellow
    $confirm = Read-Host "Continue anyway? (y/n)"
    if ($confirm -ne 'y') {
        Read-Host "Press Enter to exit"
        exit 1
    }
}

$modsPath = Join-Path $svPath "Mods"

# Choose mod pack
Write-Host ""
Write-Host "Which mod pack do you want to install?" -ForegroundColor Cyan
Write-Host "  [1] Full mod pack (all mods)"
Write-Host "  [2] Server host (no auto-unfocus, adjusted money config)"
Write-Host "  [3] No Earthy recolour (removes DaisyNiko visual mods)"
Write-Host ""
$packChoice = Read-Host "Select (1-3)"

switch ($packChoice) {
    "1" { $branch = "main" }
    "2" { $branch = "server" }
    "3" { $branch = "main_no_earthy" }
    default {
        Write-Host "Invalid choice. Defaulting to full mod pack." -ForegroundColor Yellow
        $branch = "main"
    }
}

Write-Host ""
Write-Host "Installing '$branch' mod pack to: $modsPath" -ForegroundColor Cyan

# Backup existing Mods folder
$backupPath = $null
if (Test-Path $modsPath) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupPath = Join-Path $svPath "Mods_backup_$timestamp.zip"
    Write-Host "Backing up existing Mods folder to zip..." -ForegroundColor Yellow
    $zipJob = Start-Job -ScriptBlock {
        param($src, $dst)
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($src, $dst)
    } -ArgumentList $modsPath, $backupPath
    $spinCharsBackup = @('|','/','-','\')
    $spinIdxBackup = 0
    while ($zipJob.State -eq 'Running') {
        Write-Host "`r  $($spinCharsBackup[$spinIdxBackup % 4]) Zipping..." -NoNewline -ForegroundColor DarkGray
        $spinIdxBackup++
        Start-Sleep -Milliseconds 300
    }
    Receive-Job $zipJob -ErrorAction Stop
    Remove-Job $zipJob
    Write-Host "`r  Backup saved: $backupPath                    " -ForegroundColor DarkGray

    Write-Host "Clearing existing Mods folder..." -ForegroundColor Yellow
    $clearItems = @(Get-ChildItem -Path $modsPath -Force)
    $clearTotal = $clearItems.Count
    $clearCurrent = 0
    foreach ($item in $clearItems) {
        $clearCurrent++
        $pct = [math]::Floor(($clearCurrent / $clearTotal) * 100)
        $barLen = [math]::Floor($pct / 2)
        $bar = ('#' * $barLen).PadRight(50)
        Write-Host "`r  [$bar] $pct% - Removing: $($item.Name)                    " -NoNewline -ForegroundColor DarkGray
        Remove-Item -Path $item.FullName -Recurse -Force
    }
    Write-Host ""
}

# Clone the repo (shallow, single branch for speed)
$tempClone = Join-Path $env:TEMP "sv-mod-deploy-clone"
if (Test-Path $tempClone) { Remove-Item -Recurse -Force $tempClone }

Write-Host "Downloading mods (this may take a few minutes)..." -ForegroundColor Yellow
Write-Host ""

# Run git clone and show a spinner
$spinChars = @('|','/','-','\')
$spinIdx = 0
$cloneJob = Start-Job -ScriptBlock {
    param($url, $br, $dest)
    & git clone --depth 1 --branch $br --single-branch $url $dest 2>&1
    $LASTEXITCODE
} -ArgumentList $RepoUrl, $branch, $tempClone

while ($cloneJob.State -eq 'Running') {
    Write-Host "`r  $($spinChars[$spinIdx % 4]) Downloading..." -NoNewline -ForegroundColor DarkGray
    $spinIdx++
    Start-Sleep -Milliseconds 300
}
Write-Host "`r                                                                    " -NoNewline
Write-Host "`r" -NoNewline

$cloneOutput = Receive-Job $cloneJob
Remove-Job $cloneJob

# Check if clone actually produced files
if (-not (Test-Path (Join-Path $tempClone ".git"))) {
    Write-Host "ERROR: Failed to download mods." -ForegroundColor Red
    Write-Host ($cloneOutput | Out-String) -ForegroundColor Red
    # Restore backup if we have one
    if ($backupPath -and (Test-Path $backupPath)) {
        Get-ChildItem -Path $modsPath -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        [System.IO.Compression.ZipFile]::ExtractToDirectory($backupPath, $modsPath)
        Write-Host "Restored your original Mods folder from backup." -ForegroundColor Yellow
    }
    Read-Host "Press Enter to exit"
    exit 1
}
Write-Host "  Download complete!" -ForegroundColor Green

# Copy mods to Stardew Valley
New-Item -ItemType Directory -Path $modsPath -Force | Out-Null

# Copy all mod folders (skip git metadata and deploy scripts)
$skipItems = @(".git", ".gitignore", ".gitattributes", "deploy-mods.ps1", "deploy-mods.sh", "setup.bat", "setup.command")
$modFolders = @(Get-ChildItem -Path $tempClone -Force | Where-Object { $skipItems -notcontains $_.Name })
$total = $modFolders.Count
$current = 0
foreach ($mod in $modFolders) {
    $current++
    $pct = [math]::Floor(($current / $total) * 100)
    $barLen = [math]::Floor($pct / 2)
    $bar = ('#' * $barLen).PadRight(50)
    Write-Host "`r  [$bar] $pct% - $($mod.Name)" -NoNewline -ForegroundColor Cyan
    Copy-Item -Path $mod.FullName -Destination $modsPath -Recurse -Force
}
Write-Host ""

# Clean up temp clone
Remove-Item -Recurse -Force $tempClone -ErrorAction SilentlyContinue

# Clean up portable git if we downloaded it
if ($gitPortableDir -and (Test-Path $gitPortableDir)) {
    Remove-Item -Recurse -Force $gitPortableDir -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Mods installed successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Mod pack: $branch" -ForegroundColor White
Write-Host "Location: $modsPath" -ForegroundColor White
if ($backupPath -and (Test-Path $backupPath)) {
    Write-Host "Backup:   $backupPath" -ForegroundColor White
}
Write-Host ""
Write-Host "You can now launch Stardew Valley with SMAPI!" -ForegroundColor Cyan
Write-Host ""
Read-Host "Press Enter to exit"

} catch {
    Write-Host "" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "  AN ERROR OCCURRED" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Location: $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor DarkGray
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}
