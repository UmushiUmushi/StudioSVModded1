# ============================================================
# Stardew Valley Mod Deployer
# Double-click setup.bat to run this script
# ============================================================

$ErrorActionPreference = "Stop"

$RepoUrl = "https://github.com/UmushiUmushi/StudioSVModded1.git"
$PAT = "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"
$AuthRepoUrl = "https://${PAT}@github.com/UmushiUmushi/StudioSVModded1.git"

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
$found = Find-StardewValley

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
if (Test-Path $modsPath) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupPath = Join-Path $svPath "Mods_backup_$timestamp"
    Write-Host "Backing up existing Mods folder to: $backupPath" -ForegroundColor Yellow
    Rename-Item -Path $modsPath -NewName "Mods_backup_$timestamp"
}

# Clone the repo (shallow, single branch for speed)
$tempClone = Join-Path $env:TEMP "sv-mod-deploy-clone"
if (Test-Path $tempClone) { Remove-Item -Recurse -Force $tempClone }

Write-Host "Downloading mods (this may take a few minutes)..." -ForegroundColor Yellow
try {
    git clone --depth 1 --branch $branch --single-branch $AuthRepoUrl $tempClone 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    if ($LASTEXITCODE -ne 0) { throw "Git clone failed" }
} catch {
    Write-Host "ERROR: Failed to download mods." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    # Restore backup if we renamed
    if ($backupPath -and (Test-Path $backupPath)) {
        Rename-Item -Path $backupPath -NewName "Mods"
        Write-Host "Restored your original Mods folder." -ForegroundColor Yellow
    }
    Read-Host "Press Enter to exit"
    exit 1
}

# Copy mods to Stardew Valley
Write-Host "Copying mods to Stardew Valley..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path $modsPath -Force | Out-Null

# Copy all mod folders (skip git metadata and deploy scripts)
$skipItems = @(".git", ".gitignore", ".gitattributes", "deploy-mods.ps1", "setup.bat")
Get-ChildItem -Path $tempClone -Force | Where-Object { $skipItems -notcontains $_.Name } | ForEach-Object {
    Copy-Item -Path $_.FullName -Destination $modsPath -Recurse -Force
}

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
