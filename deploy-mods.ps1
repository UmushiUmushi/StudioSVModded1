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

$RepoOwner = "UmushiUmushi"
$RepoName = "StudioSVModded1"

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

# ---- Main ----

try {

Clear-Host
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Stardew Valley Mod Deployer" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

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

$modsVersionFile = Join-Path $modsPath ".mod-version"
$isFirstInstall = -not (Test-Path $modsVersionFile)

# Get latest commit hash from GitHub API
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$remoteCommit = ""
try {
    $apiUrl = "https://api.github.com/repos/$RepoOwner/$RepoName/commits/$branch"
    $response = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -ErrorAction Stop
    $remoteCommit = $response.sha
} catch {
    $remoteCommit = ""
}

# Check if already up to date
if (-not $isFirstInstall) {
    $versionContent = Get-Content $modsVersionFile -Raw
    $installedBranch = if ($versionContent -match 'branch=(.+)') { $Matches[1].Trim() } else { "" }
    $installedCommit = if ($versionContent -match 'commit=(.+)') { $Matches[1].Trim() } else { "" }

    if ($installedBranch -eq $branch -and $remoteCommit -and $remoteCommit -eq $installedCommit) {
        Write-Host "Checking for updates..." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "  Already up to date!" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "Mod pack: $branch" -ForegroundColor White
        Write-Host "Location: $modsPath" -ForegroundColor White
        Write-Host ""
        Read-Host "Press Enter to exit"
        exit 0
    }
}

Write-Host "Installing '$branch' mod pack to: $modsPath" -ForegroundColor Cyan

# Backup on first install (no .mod-version = user had manually installed mods)
$backupPath = $null
if ($isFirstInstall -and (Test-Path $modsPath)) {
    $hasExistingMods = @(Get-ChildItem -Path $modsPath -Force -ErrorAction SilentlyContinue).Count -gt 0
    if ($hasExistingMods) {
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
    }
}

# Download the branch as a zip from GitHub
$tempDir = Join-Path $env:TEMP "sv-mod-deploy"
if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }
$tempZip = Join-Path $tempDir "mods.zip"
$tempClone = Join-Path $tempDir "extract"
if (Test-Path $tempClone) { Remove-Item -Recurse -Force $tempClone }

$zipUrl = "https://github.com/$RepoOwner/$RepoName/archive/refs/heads/$branch.zip"
Write-Host "Downloading mods (this may take a few minutes)..." -ForegroundColor Yellow
Write-Host ""

$downloadJob = Start-Job -ScriptBlock {
    param($url, $outFile)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $outFile -UseBasicParsing
} -ArgumentList $zipUrl, $tempZip

$spinChars = @('|','/','-','\')
$spinIdx = 0
while ($downloadJob.State -eq 'Running') {
    Write-Host "`r  $($spinChars[$spinIdx % 4]) Downloading..." -NoNewline -ForegroundColor DarkGray
    $spinIdx++
    Start-Sleep -Milliseconds 300
}
Write-Host "`r                                                                    " -NoNewline
Write-Host "`r" -NoNewline

try {
    Receive-Job $downloadJob -ErrorAction Stop
} catch {
    Remove-Job $downloadJob
    Write-Host "ERROR: Failed to download mods." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}
Remove-Job $downloadJob

# Extract the zip
Write-Host "  Extracting..." -ForegroundColor DarkGray
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($tempZip, $tempClone)
Remove-Item $tempZip -Force

# GitHub zips extract to a subfolder like "RepoName-branch/"
$extractedFolder = @(Get-ChildItem -Path $tempClone -Directory)[0].FullName
Write-Host "  Download complete!" -ForegroundColor Green

# Sync mods using robocopy (only copies changed files, removes deleted ones)
New-Item -ItemType Directory -Path $modsPath -Force | Out-Null

Write-Host "Syncing mods..." -ForegroundColor Yellow
$robocopyExcludes = @(".gitignore", ".gitattributes", "deploy-mods.ps1", "deploy-mods.sh", "setup.bat", "setup.command", ".mod-version")
$roboArgs = @($extractedFolder, $modsPath, "/MIR", "/NFL", "/NDL", "/NJH", "/NJS", "/NP")
$roboArgs += "/XF"
$roboArgs += $robocopyExcludes
$roboResult = & robocopy @roboArgs
# Robocopy exit codes: 0 = no changes, 1 = files copied, 2 = extras deleted, 3 = both. 8+ = error
if ($LASTEXITCODE -ge 8) {
    Write-Host "WARNING: Some files may not have synced correctly." -ForegroundColor Yellow
}
Write-Host "  Sync complete!" -ForegroundColor Green

# Write version marker (commit hash from API, or "unknown" if API failed)
$commitHash = if ($remoteCommit) { $remoteCommit } else { "unknown" }
Set-Content -Path $modsVersionFile -Value "branch=$branch`ncommit=$commitHash" -Force

# Clean up temp files
Remove-Item -Recurse -Force $tempClone -ErrorAction SilentlyContinue

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
