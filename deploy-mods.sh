#!/bin/bash
# ============================================================
# Stardew Valley Mod Deployer (macOS / Linux)
# Make executable: chmod +x deploy-mods.sh
# Then double-click or run: ./deploy-mods.sh
# ============================================================

set -e

REPO_OWNER="UmushiUmushi"
REPO_NAME="StudioSVModded1"

# ---- Colors ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# ---- Detect OS ----
OS="$(uname -s)"

# ---- Functions ----

find_stardew() {
    local candidates=()

    if [ "$OS" = "Darwin" ]; then
        # macOS Steam default
        local steam_default="$HOME/Library/Application Support/Steam/steamapps/common/Stardew Valley/Contents/MacOS"
        if [ -d "$steam_default" ]; then
            candidates+=("$steam_default")
        fi

        # macOS Steam library folders
        local library_file="$HOME/Library/Application Support/Steam/steamapps/libraryfolders.vdf"
        if [ -f "$library_file" ]; then
            while IFS= read -r lib_path; do
                local candidate="$lib_path/steamapps/common/Stardew Valley/Contents/MacOS"
                if [ -d "$candidate" ]; then
                    local already_found=false
                    for c in "${candidates[@]}"; do
                        if [ "$c" = "$candidate" ]; then already_found=true; break; fi
                    done
                    if [ "$already_found" = false ]; then candidates+=("$candidate"); fi
                fi
            done < <(grep '"path"' "$library_file" 2>/dev/null | sed 's/.*"path"[[:space:]]*"\([^"]*\)".*/\1/' | sed 's|\\\\|/|g')
        fi

        # GOG (macOS app bundle)
        local gog_default="/Applications/Stardew Valley.app/Contents/MacOS"
        if [ -d "$gog_default" ]; then
            candidates+=("$gog_default")
        fi

        # Non-app-bundle Steam path
        local steam_alt="$HOME/Library/Application Support/Steam/steamapps/common/Stardew Valley"
        if [ -d "$steam_alt" ] && [ ! -d "$steam_default" ]; then
            candidates+=("$steam_alt")
        fi
    else
        # Linux Steam default
        local steam_default="$HOME/.steam/steam/steamapps/common/Stardew Valley"
        if [ -d "$steam_default" ]; then
            candidates+=("$steam_default")
        fi

        # Linux Steam alternate location
        local steam_alt="$HOME/.local/share/Steam/steamapps/common/Stardew Valley"
        if [ -d "$steam_alt" ]; then
            local already_found=false
            for c in "${candidates[@]}"; do
                if [ "$c" = "$steam_alt" ]; then already_found=true; break; fi
            done
            if [ "$already_found" = false ]; then candidates+=("$steam_alt"); fi
        fi

        # Flatpak Steam
        local flatpak_steam="$HOME/.var/app/com.valvesoftware.Steam/.steam/steam/steamapps/common/Stardew Valley"
        if [ -d "$flatpak_steam" ]; then
            candidates+=("$flatpak_steam")
        fi

        # Linux Steam library folders
        local library_file="$HOME/.steam/steam/steamapps/libraryfolders.vdf"
        [ ! -f "$library_file" ] && library_file="$HOME/.local/share/Steam/steamapps/libraryfolders.vdf"
        if [ -f "$library_file" ]; then
            while IFS= read -r lib_path; do
                local candidate="$lib_path/steamapps/common/Stardew Valley"
                if [ -d "$candidate" ]; then
                    local already_found=false
                    for c in "${candidates[@]}"; do
                        if [ "$c" = "$candidate" ]; then already_found=true; break; fi
                    done
                    if [ "$already_found" = false ]; then candidates+=("$candidate"); fi
                fi
            done < <(grep '"path"' "$library_file" 2>/dev/null | sed 's/.*"path"[[:space:]]*"\([^"]*\)".*/\1/' | sed 's|\\\\|/|g')
        fi

        # GOG default (Linux)
        local gog_default="$HOME/GOG Games/Stardew Valley/game"
        if [ -d "$gog_default" ]; then
            candidates+=("$gog_default")
        fi
    fi

    printf '%s\n' "${candidates[@]}"
}

folder_picker() {
    local result=""
    if [ "$OS" = "Darwin" ]; then
        # macOS: native AppleScript folder picker
        result=$(osascript -e 'tell application "Finder"
            activate
            set folderPath to POSIX path of (choose folder with prompt "Select your Stardew Valley folder (the one containing the Mods folder)")
            return folderPath
        end tell' 2>/dev/null) || true
    else
        # Linux: try zenity (GNOME), then kdialog (KDE), then manual input
        if command -v zenity &>/dev/null; then
            result=$(zenity --file-selection --directory --title="Select your Stardew Valley folder" 2>/dev/null) || true
        elif command -v kdialog &>/dev/null; then
            result=$(kdialog --getexistingdirectory "$HOME" --title "Select your Stardew Valley folder" 2>/dev/null) || true
        else
            echo -e "${YELLOW}No GUI file picker available. Please type the full path:${NC}"
            read -p "Stardew Valley path: " result
        fi
    fi
    echo "$result"
}

# ---- Main ----

clear
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Stardew Valley Mod Deployer${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# Check for curl (needed for update check)
if ! command -v curl &>/dev/null; then
    echo -e "${RED}ERROR: curl is not installed.${NC}"
    echo -e "${YELLOW}Please install it using your package manager:${NC}"
    echo -e "  Ubuntu/Debian: ${CYAN}sudo apt install curl${NC}"
    echo -e "  Fedora:        ${CYAN}sudo dnf install curl${NC}"
    echo -e "  Arch:          ${CYAN}sudo pacman -S curl${NC}"
    echo ""
    read -p "Press Enter to exit..."
    exit 1
fi

# Find Stardew Valley
echo -e "${YELLOW}Looking for Stardew Valley...${NC}"
IFS=$'\n' read -r -d '' -a found < <(find_stardew && printf '\0') || true

if [ ${#found[@]} -eq 0 ]; then
    echo -e "${YELLOW}Could not auto-detect Stardew Valley. Please select the folder manually.${NC}"
    sv_path=$(folder_picker)
    if [ -z "$sv_path" ]; then
        echo -e "${RED}No folder selected. Exiting.${NC}"
        read -p "Press Enter to exit..."
        exit 1
    fi
elif [ ${#found[@]} -eq 1 ]; then
    sv_path="${found[0]}"
    echo -e "${GREEN}Found Stardew Valley at: $sv_path${NC}"
else
    echo -e "${YELLOW}Found multiple installations:${NC}"
    for i in "${!found[@]}"; do
        echo "  [$((i + 1))] ${found[$i]}"
    done
    echo "  [$((${#found[@]} + 1))] Choose a different folder"
    read -p "Select installation (1-$((${#found[@]} + 1))): " choice
    idx=$((choice - 1))
    if [ "$idx" -ge 0 ] && [ "$idx" -lt ${#found[@]} ]; then
        sv_path="${found[$idx]}"
    else
        sv_path=$(folder_picker)
        if [ -z "$sv_path" ]; then
            echo -e "${RED}No folder selected. Exiting.${NC}"
            read -p "Press Enter to exit..."
            exit 1
        fi
    fi
fi

# Remove trailing slash
sv_path="${sv_path%/}"

# Validate - look for Stardew Valley binary or Mods folder
if [ ! -f "$sv_path/StardewValley" ] && [ ! -f "$sv_path/Stardew Valley.dll" ] && [ ! -d "$sv_path/Mods" ]; then
    echo -e "${YELLOW}WARNING: This doesn't look like a Stardew Valley folder.${NC}"
    read -p "Continue anyway? (y/n): " confirm
    if [ "$confirm" != "y" ]; then
        read -p "Press Enter to exit..."
        exit 1
    fi
fi

mods_path="$sv_path/Mods"

# Choose mod pack
echo ""
echo -e "${CYAN}Which mod pack do you want to install?${NC}"
echo "  [1] Full mod pack (all mods)"
echo "  [2] Server host (no auto-unfocus, adjusted money config)"
echo "  [3] No Earthy recolour (removes DaisyNiko visual mods)"
echo ""
read -p "Select (1-3): " pack_choice

case $pack_choice in
    1) branch="main" ;;
    2) branch="server" ;;
    3) branch="main_no_earthy" ;;
    *)
        echo -e "${YELLOW}Invalid choice. Defaulting to full mod pack.${NC}"
        branch="main"
        ;;
esac

echo ""

mods_version_file="$mods_path/.mod-version"
is_first_install=true
if [ -f "$mods_version_file" ]; then
    is_first_install=false
fi

# Get latest commit hash from GitHub API
remote_commit=$(curl -s "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/commits/$branch" 2>/dev/null | grep '"sha"' | head -1 | sed 's/.*"sha": *"\([^"]*\)".*/\1/')

# Check if already up to date
if [ "$is_first_install" = false ]; then
    installed_branch=$(grep '^branch=' "$mods_version_file" 2>/dev/null | cut -d= -f2)
    installed_commit=$(grep '^commit=' "$mods_version_file" 2>/dev/null | cut -d= -f2)

    if [ "$installed_branch" = "$branch" ] && [ -n "$remote_commit" ] && [ "$remote_commit" = "$installed_commit" ]; then
        echo -e "${YELLOW}Checking for updates...${NC}"
        echo ""
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}  Already up to date!${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo ""
        echo -e "Mod pack: $branch"
        echo -e "Location: $mods_path"
        echo ""
        read -p "Press Enter to exit..."
        exit 0
    fi
fi

echo -e "${CYAN}Installing '$branch' mod pack to: $mods_path${NC}"

# Check dependencies (only needed if we're actually installing)
missing_deps=()
if ! command -v unzip &>/dev/null; then missing_deps+=("unzip"); fi
if ! command -v rsync &>/dev/null; then missing_deps+=("rsync"); fi
if ! command -v zip &>/dev/null; then missing_deps+=("zip"); fi

if [ ${#missing_deps[@]} -gt 0 ]; then
    echo -e "${RED}ERROR: Missing required tools: ${missing_deps[*]}${NC}"
    echo ""
    if [ "$OS" = "Darwin" ]; then
        echo -e "${YELLOW}Install Homebrew (https://brew.sh) then run:${NC}"
        echo -e "  ${CYAN}brew install ${missing_deps[*]}${NC}"
    else
        echo -e "${YELLOW}Please install using your package manager:${NC}"
        echo -e "  Ubuntu/Debian: ${CYAN}sudo apt install ${missing_deps[*]}${NC}"
        echo -e "  Fedora:        ${CYAN}sudo dnf install ${missing_deps[*]}${NC}"
        echo -e "  Arch:          ${CYAN}sudo pacman -S ${missing_deps[*]}${NC}"
    fi
    echo ""
    echo -e "${YELLOW}Then run this script again.${NC}"
    echo ""
    read -p "Press Enter to exit..."
    exit 1
fi

# Backup on first install (no .mod-version = user had manually installed mods)
backup_path=""
if [ "$is_first_install" = true ] && [ -d "$mods_path" ]; then
    has_existing=$(ls -A "$mods_path" 2>/dev/null | head -1)
    if [ -n "$has_existing" ]; then
        timestamp=$(date +"%Y%m%d_%H%M%S")
        backup_path="$sv_path/Mods_backup_$timestamp.zip"
        echo -e "${YELLOW}Backing up existing Mods folder to zip...${NC}"
        (cd "$mods_path" && zip -r -q "$backup_path" .)
        echo -e "  ${GRAY}Backup saved: $backup_path${NC}"
    fi
fi

# Download the branch as a zip from GitHub
temp_dir="/tmp/sv-mod-deploy"
mkdir -p "$temp_dir"
temp_zip="$temp_dir/mods.zip"
temp_extract="$temp_dir/extract"
rm -rf "$temp_extract"

zip_url="https://github.com/$REPO_OWNER/$REPO_NAME/archive/refs/heads/$branch.zip"
echo -e "${YELLOW}Downloading mods (this may take a few minutes)...${NC}"
echo ""
curl -L -# -o "$temp_zip" "$zip_url" 2>&1 | while IFS= read -r line; do
    printf "\r  ${GRAY}%s${NC}" "$line"
done
echo ""

if [ ! -f "$temp_zip" ] || [ ! -s "$temp_zip" ]; then
    echo -e "${RED}ERROR: Failed to download mods.${NC}"
    read -p "Press Enter to exit..."
    exit 1
fi

# Extract the zip
echo -e "  ${GRAY}Extracting...${NC}"
mkdir -p "$temp_extract"
unzip -q -o "$temp_zip" -d "$temp_extract"
rm -f "$temp_zip"

# GitHub zips extract to a subfolder like "RepoName-branch/"
extracted_folder=$(find "$temp_extract" -mindepth 1 -maxdepth 1 -type d | head -1)
echo -e "  ${GREEN}Download complete!${NC}"

# Sync mods using rsync (only copies changed files, removes deleted ones)
mkdir -p "$mods_path"

echo -e "${YELLOW}Syncing mods...${NC}"
rsync -a --delete \
    --exclude='.gitignore' \
    --exclude='.gitattributes' \
    --exclude='deploy-mods.ps1' \
    --exclude='deploy-mods.sh' \
    --exclude='setup.bat' \
    --exclude='setup.command' \
    --exclude='.mod-version' \
    "$extracted_folder/" "$mods_path/"
echo -e "  ${GREEN}Sync complete!${NC}"

# Write version marker (commit hash from API, or "unknown" if API failed)
commit_hash="${remote_commit:-unknown}"
printf "branch=%s\ncommit=%s\n" "$branch" "$commit_hash" > "$mods_version_file"

# Clean up temp files
rm -rf "$temp_extract"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Mods installed successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Mod pack: $branch"
echo -e "Location: $mods_path"
if [ -n "$backup_path" ] && [ -f "$backup_path" ]; then
    echo -e "Backup:   $backup_path"
fi
echo ""
echo -e "${CYAN}You can now launch Stardew Valley with SMAPI!${NC}"
echo ""
read -p "Press Enter to exit..."
