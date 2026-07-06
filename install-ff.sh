#!/usr/bin/env bash
# My god, what are you doing!?
# Stop editing the code!
set -euo pipefail

BIN_DIR="${HOME}/.local/bin"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fastfetch"
LOGOS_DIR="$CONFIG_DIR/logos"
FF_BIN="/usr/local/bin"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[✓]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; }

detect_distro() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO_ID="$ID"
    DISTRO_LIKE="${ID_LIKE:-}"
  else
    DISTRO_ID="unknown"
    DISTRO_LIKE=""
  fi
  DISTRO_ID="${DISTRO_ID,,}"
  DISTRO_LIKE="${DISTRO_LIKE,,}"
}

detect_pm() {
  if command -v pacman &>/dev/null; then
    PM="pacman"
    PM_INSTALL="pacman -S --noconfirm"
    PM_QUERY="pacman -Q"
  elif command -v dnf &>/dev/null; then
    PM="dnf"
    PM_INSTALL="dnf install -y"
    PM_QUERY="dnf list installed"
  elif command -v apt &>/dev/null; then
    PM="apt"
    PM_INSTALL="apt install -y"
    PM_QUERY="dpkg -l"
  elif command -v zypper &>/dev/null; then
    PM="zypper"
    PM_INSTALL="zypper install -y"
    PM_QUERY="rpm -q"
  elif command -v apk &>/dev/null; then
    PM="apk"
    PM_INSTALL="apk add"
    PM_QUERY="apk info"
  elif command -v xbps-install &>/dev/null; then
    PM="xbps"
    PM_INSTALL="xbps-install -y"
    PM_QUERY="xbps-query"
  elif command -v emerge &>/dev/null; then
    PM="emerge"
    PM_INSTALL="emerge"
    PM_QUERY="qlist -I"
  else
    PM="unknown"
  fi
}

ensure_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
  elif command -v sudo &>/dev/null; then
    SUDO="sudo"
  else
    err "sudo not available — install as root or install dependencies manually"
    exit 1
  fi
}

install_deps() {
  detect_pm
  ensure_sudo

  info "Detected distro: ${DISTRO_ID}${DISTRO_LIKE:+ (like: $DISTRO_LIKE)}"
  info "Package manager: ${PM}"

  # Install jq (available everywhere)
  if command -v jq &>/dev/null; then
    ok "jq already installed"
  else
    info "Installing jq..."
    case "$PM" in
      pacman) $SUDO pacman -S --noconfirm jq ;;
      dnf)    $SUDO dnf install -y jq ;;
      apt)    $SUDO apt install -y jq ;;
      zypper) $SUDO zypper install -y jq ;;
      apk)    $SUDO apk add jq ;;
      xbps)   $SUDO xbps-install -y jq ;;
      emerge) $SUDO emerge jq ;;
      *)
        err "Unknown package manager — install jq manually, then re-run"
        exit 1
        ;;
    esac
    ok "jq installed"
  fi

  # Install fastfetch
  if command -v fastfetch &>/dev/null; then
    ok "fastfetch already installed ($(fastfetch --version-raw 2>/dev/null || echo "unknown version"))"
    return
  fi

  info "fastfetch not found — trying package manager..."
  local ff_ok=false
  case "$PM" in
    pacman)
      $SUDO pacman -S --noconfirm fastfetch && ff_ok=true ;;
    dnf)
      $SUDO dnf install -y fastfetch 2>/dev/null && ff_ok=true || true ;;
    apt)
      $SUDO apt install -y fastfetch 2>/dev/null && ff_ok=true || true ;;
    zypper)
      $SUDO zypper install -y fastfetch 2>/dev/null && ff_ok=true || true ;;
    *) ;;
  esac

  if $ff_ok && command -v fastfetch &>/dev/null; then
    ok "fastfetch installed via $PM"
    return
  fi

  # Download static binary from GitHub
  warn "fastfetch not in repos — downloading static binary..."
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64)  arch="amd64" ;;
    aarch64|arm64) arch="aarch64" ;;
    *) err "Unsupported architecture: $arch"; exit 1 ;;
  esac

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local latest_url
  latest_url="$(curl -sL https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest | grep '"browser_download_url"' | grep "linux-$arch" | grep '\.tar\.gz$' | head -1 | cut -d'"' -f4)"

  if [ -z "$latest_url" ]; then
    err "Could not find fastfetch binary for $arch"
    err "Install fastfetch manually, then re-run this installer"
    exit 1
  fi

  info "Downloading fastfetch from GitHub..."
  curl -sL "$latest_url" | tar xz -C "$tmp_dir"
  $SUDO cp "$tmp_dir"/fastfetch-linux-*/usr/bin/fastfetch "$FF_BIN/fastfetch"
  $SUDO chmod +x "$FF_BIN/fastfetch"
  rm -rf "$tmp_dir"
  ok "fastfetch installed to $FF_BIN/fastfetch"
}

install_scripts() {
  mkdir -p "$BIN_DIR"

  cat > "$BIN_DIR/fastfetch-config" << 'FFCONFIG'
VERSION="V1.2"
REPO_URL="https://raw.githubusercontent.com/AaronYTDev/fastfetch-config/main"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fastfetch"
CONFIG_FILE="$CONFIG_DIR/config.jsonc"
LOGOS_DIR="$CONFIG_DIR/logos"
BACKUP_DIR="$CONFIG_DIR/backups"

usage() {
  cat <<EOF
Usage: fastfetch-config <command> [args]

Configuration:
  status                Show current settings
  reset [name]          Reset config or individual variable to default

Logo:
  logo [name]           Show/set logo, or "auto" to restore detection
  color <slot> <c>      Set logo color slot (1-9), e.g. ff color 1 blue
  color list            Show logo color overrides
  color reset           Clear all logo color overrides
  ff --list-logos       List available built-in logos

OS:
  osname [name]         Show/set OS name, or "auto" to restore detection
  osname-logo <n> [l]   Set OS name and logo (one arg sets both)

Variables:
  variable              List all variables (modules)
  variable add <name>   Add a variable (inserted at default pos)
  variable remove <name> Remove a variable from the config
  variable move <name> <pos> Move a variable to position (1-based)
  variable set <n> <k> <v> Set a property on a variable
  variable eset <n> <f> Set key+format in one go ("Kernel" "MyOS")

Other:
  backup [name]         Save a backup of current config
  backup list           List available backups
  backup remove <name>  Remove a backup
  restore <name>        Restore a backup
  update [check]        Check for / install updates from GitHub
  version               Show version
  tui|interactive|menu   Open interactive TUI menu
  help                  Show this help

Variables: host, kernel, uptime, packages, shell, de, wm, cpu, memory,
           swap, gpu, disk, locale

Colors: black, red, green, yellow, blue, magenta, cyan, white, orange,
        bright-black, bright-red, etc., or ANSI codes (32, 93)

Examples:
  fastfetch-config backup
  fastfetch-config backup my-config
  fastfetch-config backup list
  fastfetch-config restore my-config
  fastfetch-config logo arch
  fastfetch-config logo ~/my-logo.txt
  fastfetch-config osname "MyOS 1.0"
  fastfetch-config color 1 cyan
  fastfetch-config color 2 93
  fastfetch-config variable list
  fastfetch-config variable add gpu
  fastfetch-config variable remove locale
  fastfetch-config variable set disk folders /
  ff                    Run fastfetch directly
  fastfetch-config update
  fastfetch-config update check
EOF
}

die() { echo "$1" >&2; exit 1; }
need_jq() { command -v jq &>/dev/null || die "jq is required (pacman -S jq)"; }

get_logo() {
  jq -r '.logo.source // "auto"' "$CONFIG_FILE"
}

set_logo() {
  local name="$1"
  local tmp
  tmp=$(mktemp)

  local logo_path="$LOGOS_DIR/$name"
  if [ "$name" = "auto" ]; then
    jq '.logo.type = "auto" | .logo.source = ""' "$CONFIG_FILE" > "$tmp"
    echo "Logo set to auto-detection"
  elif [ -f "$name" ]; then
    cp "$name" "$logo_path"
    jq --arg s "$logo_path" '.logo.type = "file" | .logo.source = $s' "$CONFIG_FILE" > "$tmp"
    echo "Logo set to custom file: $name"
  elif [ -f "$logo_path" ]; then
    jq --arg s "$logo_path" '.logo.type = "file" | .logo.source = $s' "$CONFIG_FILE" > "$tmp"
    echo "Logo set to custom file: $name"
  else
    jq --arg s "$name" '.logo.type = "builtin" | .logo.source = $s' "$CONFIG_FILE" > "$tmp"
    echo "Logo set to built-in: $name"
  fi
  mv "$tmp" "$CONFIG_FILE"
}

get_osname() {
  local val
  val=$(jq -r '.modules[] | select(type == "object") | select(.type == "custom" and .key == "OS") | .format // ""' "$CONFIG_FILE")
  if [ -z "$val" ]; then
    echo "auto"
  else
    echo "$val"
  fi
}

set_osname() {
  local name="$1"
  local tmp
  tmp=$(mktemp)

  if [ "$name" = "auto" ]; then
    jq '
      ([.modules | to_entries[] | select(.value | type == "object") | select(.value.type == "custom" and .value.key == "OS") | .key] | first) as $idx |
      if $idx then .modules[$idx] = {type: "os", keyIcon: "\uf17c"} else . end
    ' "$CONFIG_FILE" > "$tmp"
    echo "OS name set to auto-detection"
  else
    local has_custom
    has_custom=$(jq '[.modules[] | select(type == "object") | select(.type == "custom" and .key == "OS")] | length' "$CONFIG_FILE")
    if [ "$has_custom" -gt 0 ]; then
      jq --arg n "$name" '(.modules[] | select(type == "object") | select(.type == "custom" and .key == "OS") | .format) = $n' \
        "$CONFIG_FILE" > "$tmp"
    else
      jq --arg n "$name" '
        ([.modules | to_entries[] | select(.value | type == "object") | select(.value.type == "os") | .key] | first) as $idx |
        if $idx then .modules[$idx] = {type: "custom", key: "OS", format: $n}
        else .modules += [{type: "custom", key: "OS", format: $n}] end
      ' "$CONFIG_FILE" > "$tmp"
    fi
    echo "OS name set to: $name"
  fi
  mv "$tmp" "$CONFIG_FILE"
}

get_colors() {
  jq -r '.logo.color | to_entries[] | select(.value != "") | "\(.key): \(.value)"' "$CONFIG_FILE" 2>/dev/null || true
}

resolve_color() {
  case "${1,,}" in
    orange)  echo "#FF8000" ;;
    *)       echo "$1" ;;
  esac
}

set_color() {
  local slot="$1"
  local color_val
  color_val=$(resolve_color "$2")
  local tmp
  tmp=$(mktemp)
  jq --arg c "$color_val" ".logo.color[\"$slot\"] = \$c" "$CONFIG_FILE" > "$tmp"
  mv "$tmp" "$CONFIG_FILE"
  echo "Logo color $slot set to: $color_val"
}

reset_colors() {
  local tmp
  tmp=$(mktemp)
  jq '.logo.color = {}' "$CONFIG_FILE" > "$tmp"
  mv "$tmp" "$CONFIG_FILE"
  echo "All logo color overrides cleared"
}

get_default_pos() {
  local name="$1"
  case "$name" in
    title)     echo 0 ;;
    separator) echo 1 ;;
    os)        echo 2 ;;
    host)      echo 3 ;;
    kernel)    echo 4 ;;
    uptime)    echo 5 ;;
    packages)  echo 6 ;;
    shell)     echo 7 ;;
    de)        echo 8 ;;
    wm)        echo 9 ;;
    cpu)       echo 10 ;;
    memory)    echo 11 ;;
    swap)      echo 12 ;;
    gpu)       echo 13 ;;
    disk)      echo 14 ;;
    locale)    echo 15 ;;
    break)     echo 16 ;;
    colors)    echo 17 ;;
    *)         echo -1 ;;
  esac
}

list_modules() {
  jq -r '.modules[] | if type == "object" then .type else . end' "$CONFIG_FILE"
}

show_module() {
  local name="$1"
  jq --arg n "$name" '.modules[] | select(if type == "string" then . == $n else .type == $n end)' "$CONFIG_FILE"
}

add_module() {
  local name="$1"
  local tmp
  tmp=$(mktemp)
  local exists
  exists=$(jq -r --arg n "$name" '[.modules[] | select(if type == "string" then . == $n else .type == $n end)] | length' "$CONFIG_FILE")
  if [ "$exists" -gt 0 ]; then
    echo "Variable '$name' already exists in config"
    rm "$tmp"
    return
  fi
  local pos
  pos=$(get_default_pos "$name")
  if [ "$pos" -ge 0 ]; then
    if [ "$name" = "disk" ]; then
      jq --arg n "$name" --argjson p "$pos" '.modules = (.modules[:$p] + [{type: $n, folders: "/"}] + .modules[$p:])' "$CONFIG_FILE" > "$tmp"
    else
      jq --arg n "$name" --argjson p "$pos" '.modules = (.modules[:$p] + [$n] + .modules[$p:])' "$CONFIG_FILE" > "$tmp"
    fi
  else
    if [ "$name" = "disk" ]; then
      jq --arg n "$name" '.modules += [{type: $n, folders: "/"}]' "$CONFIG_FILE" > "$tmp"
    else
      jq --arg n "$name" '.modules += [$n]' "$CONFIG_FILE" > "$tmp"
    fi
  fi
  mv "$tmp" "$CONFIG_FILE"
  echo "Added variable: $name"
}

remove_module() {
  local name="$1"
  local tmp
  tmp=$(mktemp)
  local exists
  exists=$(jq -r --arg n "$name" '[.modules[] | select(if type == "string" then . == $n else .type == $n end)] | length' "$CONFIG_FILE")
  if [ "$exists" -eq 0 ]; then
    echo "Variable '$name' not found in config"
    rm "$tmp"
    return
  fi
  jq --arg n "$name" '.modules = [.modules[] | select(if type == "string" then . != $n else .type != $n end)]' "$CONFIG_FILE" > "$tmp"
  mv "$tmp" "$CONFIG_FILE"
  echo "Removed variable: $name"
}

set_module() {
  local name="$1"
  local key="$2"
  local value="$3"
  local tmp
  tmp=$(mktemp)
  local is_string
  is_string=$(jq -r --arg n "$name" '[.modules[] | select(type == "string" and . == $n)] | length' "$CONFIG_FILE")
  if [ "$is_string" -gt 0 ]; then
    jq --arg n "$name" --arg k "$key" --arg v "$value" '
      (.modules | to_entries[] | select(.value == $n)) as $e |
      .modules[$e.key] = {type: $n, ($k): $v}
    ' "$CONFIG_FILE" > "$tmp"
  else
    local is_obj
    is_obj=$(jq -r --arg n "$name" '[.modules[] | select(type == "object") | select(.type == $n)] | length' "$CONFIG_FILE")
    if [ "$is_obj" -eq 0 ]; then
      echo "Variable '$name' not found in config"
      rm "$tmp"
      return
    fi
    jq --arg n "$name" --arg k "$key" --arg v "$value" '
      (.modules[] | select(type == "object") | select(.type == $n))[$k] = $v
    ' "$CONFIG_FILE" > "$tmp"
  fi
  mv "$tmp" "$CONFIG_FILE"
  echo "Set $name.$key = $value"
}

reset_module() {
  local name="$1"
  local tmp
  tmp=$(mktemp)
  local exists
  exists=$(jq -r --arg n "$name" '[.modules[] | select(if type == "string" then . == $n else .type == $n end)] | length' "$CONFIG_FILE")
  if [ "$exists" -eq 0 ]; then
    echo "Variable '$name' not found in config"
    rm "$tmp"
    return
  fi
  jq --arg n "$name" '
    (.modules | to_entries[] | select(.value | if type == "string" then . == $n else .type == $n end)) as $e |
    .modules[$e.key] = (
      if $n == "os" then {type: "os", keyIcon: "\uf17c"}
      elif $n == "disk" then {type: "disk", folders: "/"}
      else $n
      end
    )
  ' "$CONFIG_FILE" > "$tmp"
  mv "$tmp" "$CONFIG_FILE"
  echo "Reset '$name' to default"
}

move_module() {
  local name="$1"
  local new_pos="$2"
  local tmp
  tmp=$(mktemp)
  local idx=$((new_pos - 1))
  local exists
  exists=$(jq -r --arg n "$name" '[.modules[] | select(if type == "string" then . == $n else .type == $n end)] | length' "$CONFIG_FILE")
  if [ "$exists" -eq 0 ]; then
    echo "Variable '$name' not found in config"
    rm "$tmp"
    return
  fi
  jq --arg n "$name" --argjson p "$idx" '
    (.modules | to_entries[] | select(.value | if type == "string" then . == $n else .type == $n end)) as $e |
    if $p > $e.key then
      .modules = (.modules[:$e.key] + .modules[$e.key+1:]) |
      .modules = (.modules[:$p-1] + [$e.value] + .modules[$p-1:])
    else
      .modules = (.modules[:$e.key] + .modules[$e.key+1:]) |
      .modules = (.modules[:$p] + [$e.value] + .modules[$p:])
    end
  ' "$CONFIG_FILE" > "$tmp"
  mv "$tmp" "$CONFIG_FILE"
  echo "Moved '$name' to position $new_pos"
}

backup_config() {
  local name="${1:-}"
  mkdir -p "$BACKUP_DIR"
  if [ -z "$name" ]; then
    name="backup-$(date +%Y%m%d-%H%M%S)"
  fi
  local dest="$BACKUP_DIR/$name.jsonc"
  if [ -f "$dest" ]; then
    echo "Backup '$name' already exists. Overwrite? (y/N): "
    read -r ans
    [ "$ans" != "y" ] && [ "$ans" != "Y" ] && { echo "Canceled"; return; }
  fi
  cp "$CONFIG_FILE" "$dest"
  echo "Backup saved: $dest"
}

list_backups() {
  mkdir -p "$BACKUP_DIR"
  local files
  files=$(ls -1t "$BACKUP_DIR"/*.jsonc 2>/dev/null)
  if [ -z "$files" ]; then
    echo "No backups found in $BACKUP_DIR"
    return
  fi
  echo "Available backups:"
  for f in $files; do
    local bname
    bname=$(basename "$f" .jsonc)
    local bdate
    bdate=$(stat -c "%y" "$f" 2>/dev/null | cut -d. -f1)
    echo "  $bname  ($bdate)"
  done
}

restore_config() {
  local name="$1"
  local src="$BACKUP_DIR/$name.jsonc"
  if [ ! -f "$src" ]; then
    echo "Backup '$name' not found in $BACKUP_DIR"
    echo "Use 'ff backup list' to see available backups"
    return
  fi
  cp "$src" "$CONFIG_FILE"
  echo "Restored backup: $name"
}

remove_backup() {
  local name="$1"
  local file="$BACKUP_DIR/$name.jsonc"
  if [ ! -f "$file" ]; then
    echo "Backup '$name' not found"
    return
  fi
  rm "$file"
  echo "Removed backup: $name"
}

self_update() {
  local mode="${1:-}"
  local allow_prerelease="${2:-}"
  echo "Checking for updates..."
  local api_url="https://api.github.com/repos/AaronYTDev/fastfetch-config/releases/latest"
  local release_data
  release_data=$(curl -sL --connect-timeout 5 --max-time 10 "$api_url" 2>/dev/null || true)
  if [ -z "$release_data" ]; then
    echo "Failed to reach GitHub. Check your internet connection."
    return
  fi
  local remote_version
  remote_version=$(echo "$release_data" | jq -r '.tag_name' 2>/dev/null || true)
  local release_name
  release_name=$(echo "$release_data" | jq -r '.name' 2>/dev/null || true)
  if [ -z "$remote_version" ]; then
    echo "Failed to parse release info from GitHub."
    return
  fi
  echo "Current: $VERSION"
  echo "Remote:  ${release_name:-$remote_version}"
  local local_norm
  local_norm=$(echo "$VERSION" | tr -d '.-' | tr '[:upper:]' '[:lower:]')
  local remote_norm
  remote_norm=$(echo "${release_name:-$remote_version}" | tr -d '.-' | tr '[:upper:]' '[:lower:]')
  if [ "$local_norm" = "$remote_norm" ]; then
    echo "You're up to date!"
    return
  fi
  local is_local_prerelease
  is_local_prerelease=$(echo "$VERSION" | grep -c '\-prerelease' || true)
  local is_remote_prerelease
  is_remote_prerelease=$(echo "${release_name:-$remote_version}" | grep -c '\-prerelease' || true)
  if [ "$is_local_prerelease" -eq 0 ] && [ "$is_remote_prerelease" -eq 1 ] && [ "$allow_prerelease" != "prerelease" ]; then
    if [ "$mode" = "check" ]; then
      echo "Prerelease available (${release_name:-$remote_version}). Use 'ff update -prerelease' to install."
    else
      echo "Skipping prerelease. Use 'ff update -prerelease' to install prereleases."
    fi
    return
  fi
  if [ "$mode" = "check" ]; then
    echo "Update available (${release_name:-$remote_version})! Run 'ff update' to install."
    return
  fi
  local asset_url
  asset_url=$(echo "$release_data" | jq -r '.assets[] | select(.name == "install-ff.sh") | .browser_download_url' 2>/dev/null || true)
  if [ -z "$asset_url" ]; then
    echo "Could not find 'install-ff.sh' in the latest release."
    return
  fi
  echo
  echo "Downloading update..."
  local tmp
  tmp=$(mktemp)
  if curl -sL --connect-timeout 5 --max-time 60 -o "$tmp" "$asset_url"; then
    chmod +x "$tmp"
    echo "Running installer..."
    bash "$tmp"
    rm "$tmp"
  else
    rm "$tmp"
    echo "Download failed. Try again later."
  fi
}

check_update_quiet() {
  local release_data remote_version
  release_data=$(curl -sL --connect-timeout 5 --max-time 5 "https://api.github.com/repos/AaronYTDev/fastfetch-config/releases/latest" 2>/dev/null || true)
  [ -z "$release_data" ] && return
  remote_version=$(echo "$release_data" | jq -r '.tag_name' 2>/dev/null || true)
  [ -z "$remote_version" ] && return
  local local_norm remote_norm
  local_norm=$(echo "$VERSION" | tr -d '.-' | tr '[:upper:]' '[:lower:]')
  remote_norm=$(echo "$remote_version" | tr -d '.-' | tr '[:upper:]' '[:lower:]')
  [ "$local_norm" = "$remote_norm" ] && return
  local is_local_prerelease
  is_local_prerelease=$(echo "$VERSION" | grep -c '\-prerelease' || true)
  local is_remote_prerelease
  is_remote_prerelease=$(echo "$remote_version" | grep -c '\-prerelease' || true)
  [ "$is_local_prerelease" -eq 0 ] && [ "$is_remote_prerelease" -eq 1 ] && return
  echo "[update] Version $remote_version available! Run 'ff update' to install."
}

tui_backup() {
  while true; do
    clear
    echo "═══ Backup / Restore / Remove ═══"
    echo
    echo "1) Create backup"
    echo "2) List backups"
    echo "3) Restore backup"
    echo "4) Remove backup"
    echo "5) Back"
    echo
    read -n 1 -p "Select option: " choice
    echo
    case "$choice" in
      1)
        read -p "Backup name (leave empty for timestamp): " name
        backup_config "$name"
        read -p "Press enter to continue..." _
        ;;
      2)
        list_backups
        echo
        read -p "Press enter to continue..." _
        ;;
      3)
        list_backups
        echo
        read -p "Backup name to restore: " name
        restore_config "$name"
        read -p "Press enter to continue..." _
        ;;
      4)
        list_backups
        echo
        read -p "Backup name to remove: " name
        remove_backup "$name"
        read -p "Press enter to continue..." _
        ;;
      5|q|back) break ;;
      *) echo "Invalid option"; read -p "Press enter to continue..." _ ;;
    esac
  done
}

tui_menu() {
  check_update_quiet
  while true; do
    clear
    echo "╔══════════════════════════╗"
    echo "║  fastfetch-config TUI    ║"
    echo "╚══════════════════════════╝"
    echo "1) Variables"
    echo "2) Logo"
    echo "3) OS Name"
    echo "4) Colors"
    echo "5) Status"
    echo "6) Reset"
    echo "7) Update"
    echo "8) Backup / Restore"
    echo "9) Help"
    echo "0) Exit"
    echo
    read -n 1 -p "Select option: " choice
    echo
    case "$choice" in
      1) tui_variables ;;
      2) tui_logo ;;
      3) tui_osname ;;
      4) tui_colors ;;
      5) tui_status ;;
      6) tui_reset ;;
      7|u|update) clear; self_update; read -p "Press enter to continue..." _ ;;
      8|b|backup) tui_backup ;;
      9) clear; usage; echo; read -p "Press enter to exit..." _ ;;
      0|q|exit) clear; echo "Goodbye!"; echo; ff; break ;;
      *) echo "Invalid option"; sleep 1 ;;
    esac
  done
}

tui_variables() {
  while true; do
    clear
    echo "═══ Variables ═══"
    echo "Current: $(list_modules | tr '\n' ' ')"
    echo
    echo "1) Add"
    echo "2) Remove"
    echo "3) Move"
    echo "4) Set property"
    echo "5) Easy set (key+format)"
    echo "6) Back"
    echo
    read -n 1 -p "Select option: " choice
    echo
    case "$choice" in
      1)
        read -p "Variable name to add: " name
        add_module "$name"
        read -p "Press enter to continue..." _
        ;;
      2)
        read -p "Variable name to remove: " name
        remove_module "$name"
        read -p "Press enter to continue..." _
        ;;
      3)
        read -p "Variable name: " name
        read -p "New position (1-based): " pos
        move_module "$name" "$pos"
        read -p "Press enter to continue..." _
        ;;
      4)
        read -p "Variable name: " name
        read -p "Property key: " key
        read -p "Property value: " val
        set_module "$name" "$key" "$val"
        read -p "Press enter to continue..." _
        ;;
      5)
        read -p "Variable name: " name
        read -p "Display label (key): " key
        read -p "Display value (format): " fmt
        varname=$(echo "$name" | tr '[:upper:]' '[:lower:]')
        set_module "$varname" "key" "$key"
        set_module "$varname" "format" "$fmt"
        echo "Easy-set complete: $name → $fmt"
        read -p "Press enter to continue..." _
        ;;
      6|q|back) break ;;
      *) echo "Invalid option"; read -p "Press enter to continue..." _ ;;
    esac
  done
}

tui_logo() {
  clear
  echo "═══ Logo ═══"
  echo "Variables: $(list_modules | tr '\n' ' ')"
  echo "Current: $(get_logo)"
  echo
  read -p "Logo name (or 'auto'): " name
  set_logo "$name"
}

tui_osname() {
  clear
  echo "═══ OS Name ═══"
  echo "Variables: $(list_modules | tr '\n' ' ')"
  echo "Current: $(get_osname)"
  echo
  read -p "OS name (or 'auto'): " name
  set_osname "$name"
}

tui_colors() {
  clear
  echo "═══ Colors ═══"
  echo "Variables: $(list_modules | tr '\n' ' ')"
  cols=$(get_colors)
  if [ -n "$cols" ]; then
    echo "Current overrides:"
    echo "$cols" | sed 's/^/  /'
  else
    echo "No color overrides set"
  fi
  echo
  read -p "Color slot (1-9): " slot
  read -p "Color (name or ANSI code): " color
  set_color "$slot" "$color"
}

tui_status() {
  clear
  echo "═══ Status ═══"
  echo "Config: $CONFIG_FILE"
  echo "Logo: $(get_logo)"
  echo "OS name: $(get_osname)"
  echo "Logos dir: $LOGOS_DIR"
  cols=$(get_colors)
  if [ -n "$cols" ]; then
    echo "Logo colors:"
    echo "$cols" | sed 's/^/  /'
  fi
  echo "Variables: $(list_modules | tr '\n' ' ')"
  echo
  read -p "Press enter to continue..." _
}

tui_reset() {
  while true; do
    clear
    echo "═══ Reset ═══"
    echo "Variables: $(list_modules | tr '\n' ' ')"
    echo "1) Reset entire config"
    echo "2) Reset a single variable"
    echo "3) Back"
    echo
    read -n 1 -p "Select option: " choice
    echo
    case "$choice" in
      1)
        cat > "$CONFIG_FILE" << 'RESETCFG'
{
  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/master/doc/json_schema.json",
  "logo": {
    "type": "auto",
    "source": "",
    "padding": {
      "right": 4
    }
  },
  "modules": [
    "title",
    "separator",
    { "type": "os", "keyIcon": "\uf17c" },
    "host",
    "kernel",
    "uptime",
    "packages",
    "shell",
    "de",
    "wm",
    "cpu",
    "memory",
    "swap",
    "gpu",
    { "type": "disk", "folders": "/" },
    "locale",
    "break",
    "colors"
  ]
}
RESETCFG
        echo "Config reset to default"
        read -p "Press enter to continue..." _
        ;;
      2)
        read -p "Variable name to reset: " name
        reset_module "$name"
        ;;
      3|q|back) break ;;
    esac
  done
}

need_jq
mkdir -p "$LOGOS_DIR"

case "${1:-}" in
  logo)
    if [ -z "${2:-}" ]; then
      echo "Current logo: $(get_logo)"
    else
      set_logo "$2"
    fi
    ;;
  osname)
    if [ -z "${2:-}" ]; then
      echo "Current OS name: $(get_osname)"
    else
      set_osname "$2"
    fi
    ;;
  osname-logo)
    if [ -z "${2:-}" ]; then
      echo "Usage: ff osname-logo <name> [logoname]"
      exit 1
    fi
    if [ -z "${3:-}" ]; then
      set_osname "$2"
      set_logo "$2"
    else
      set_osname "$2"
      set_logo "$3"
    fi
    ;;
  list-logos|list|ls)
    fastfetch --print-logos 2>&1 | head -100
    echo ""
    if [ -n "$(ls -A "$LOGOS_DIR" 2>/dev/null)" ]; then
      echo "Custom logos in $LOGOS_DIR:"
      ls "$LOGOS_DIR"
    fi
    ;;
  color)
    case "${2:-}" in
      list)
        echo "Current logo color overrides:"
        cols=$(get_colors)
        if [ -z "$cols" ]; then
          echo "  (none set)"
        else
          echo "$cols"
        fi
        ;;
      reset)
        reset_colors
        ;;
      *)
        if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
          echo "Usage: ff color <slot(1-9)> <color>"
          echo "       ff color list"
          echo "       ff color reset"
          exit 1
        fi
        set_color "$2" "$3"
        ;;
    esac
    ;;
  status)
    echo "Fastfetch config: $CONFIG_FILE"
    echo "Logo: $(get_logo)"
    echo "OS name: $(get_osname)"
    echo "Custom logos dir: $LOGOS_DIR"
    cols=$(get_colors)
    if [ -n "$cols" ]; then
      echo "Logo colors:"
      echo "$cols" | sed 's/^/  /'
    fi
    echo "Variables: $(list_modules | tr '\n' ' ')"
    ;;
  variable|var)
    case "${2:-}" in
      list|"")
        echo "Current variables (modules):"
        list_modules
        ;;
      add)
        if [ -z "${3:-}" ]; then
          echo "Usage: ff variable add <name>"
          exit 1
        fi
        add_module "$3"
        ;;
      remove|rm)
        if [ -z "${3:-}" ]; then
          echo "Usage: ff variable remove <name>"
          exit 1
        fi
        remove_module "$3"
        ;;
      move|mv|reorder)
        if [ -z "${3:-}" ] || [ -z "${4:-}" ]; then
          echo "Usage: ff variable move <name> <position>"
          exit 1
        fi
        move_module "$3" "$4"
        ;;
      set)
        if [ -z "${3:-}" ] || [ -z "${4:-}" ] || [ -z "${5:-}" ]; then
          echo "Usage: ff variable set <name> <key> <value>"
          exit 1
        fi
        set_module "$3" "$4" "$5"
        ;;
      eset)
        if [ -z "${3:-}" ] || [ -z "${4:-}" ]; then
          echo "Usage: ff variable eset <keyname> <formatname>"
          exit 1
        fi
        varname=$(echo "$3" | tr '[:upper:]' '[:lower:]')
        set_module "$varname" "key" "$3"
        set_module "$varname" "format" "$4"
        echo "Easy-set complete: $3 → $4"
        ;;
      show|get)
        if [ -z "${3:-}" ]; then
          echo "Usage: ff variable show <name>"
          exit 1
        fi
        show_module "$3"
        ;;
      *)
        echo "Unknown variable subcommand: ${2:-}"
        echo "Usage: ff variable [list|add|remove|set|show]"
        exit 1
        ;;
    esac
    ;;
  reset)
    if [ -n "${2:-}" ]; then
      reset_module "$2"
    else
      cat > "$CONFIG_FILE" << 'RESETCFG'
{
  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/master/doc/json_schema.json",
  "logo": {
    "type": "auto",
    "source": "",
    "padding": {
      "right": 4
    }
  },
  "modules": [
    "title",
    "separator",
    { "type": "os", "keyIcon": "\uf17c" },
    "host",
    "kernel",
    "uptime",
    "packages",
    "shell",
    "de",
    "wm",
    "cpu",
    "memory",
    "swap",
    "gpu",
    { "type": "disk", "folders": "/" },
    "locale",
    "break",
    "colors"
  ]
}
RESETCFG
      echo "Config reset to default"
    fi
    ;;
  backup)
    if [ -z "${2:-}" ]; then
      backup_config ""
    else
      case "${2:-}" in
        list) list_backups ;;
        remove|rm) remove_backup "${3:-}" ;;
        *) backup_config "$2" ;;
      esac
    fi
    ;;
  restore)
    if [ -z "${2:-}" ]; then
      echo "Usage: ff restore <name>"
      echo "       ff restore list"
    else
      case "${2:-}" in
        list) list_backups ;;
        *) restore_config "$2" ;;
      esac
    fi
    ;;
  version|--version)
    echo "fastfetch-config $VERSION"
    ;;
  update)
    case "${2:-}" in
      check)
        case "${3:-}" in
          -prerelease|--prerelease) self_update check prerelease ;;
          *) self_update check ;;
        esac
        ;;
      -prerelease|--prerelease) self_update "" prerelease ;;
      --help|-h|help) echo "Usage: ff update [check] [-prerelease]"; echo "  update              Download and install latest stable"; echo "  update check        Check for stable updates"; echo "  update -prerelease  Download and install latest (including prereleases)"; echo "  update check -prerelease  Check all updates including prereleases" ;;
      "") self_update ;;
      *) echo "Unknown option: ${2:-}"; echo "Usage: ff update [check] [-prerelease]" ;;
    esac
    ;;
  tui|interactive|menu)
    tui_menu
    ;;
  help|--help|-h)
    usage
    ;;
  *)
    check_update_quiet
    exec fastfetch "$@"
    ;;
esac




FFCONFIG

  chmod +x "$BIN_DIR/fastfetch-config"
  ok "Installed fastfetch-config → $BIN_DIR/fastfetch-config"

  cat > "$BIN_DIR/ff" << 'FFALIAS'
#!/usr/bin/env bash
exec fastfetch-config "$@"
FFALIAS
  chmod +x "$BIN_DIR/ff"
  ok "Installed ff alias → $BIN_DIR/ff"
}

setup_config() {
  mkdir -p "$CONFIG_DIR" "$LOGOS_DIR"

  if [ -f "$CONFIG_DIR/config.jsonc" ] && [[ " $* " == *" -nodelete "* ]]; then
    info "Config already exists at $CONFIG_DIR/config.jsonc - Preserving it as -nodelete was used"
  else
    if [ -f "$CONFIG_DIR/config.jsonc" ]; then
      warn "Removing old config..."
      rm -f "$CONFIG_DIR/config.jsonc"
    fi
    cat > "$CONFIG_DIR/config.jsonc" << JSONCFG
{
  "\$schema": "https://github.com/fastfetch-cli/fastfetch/raw/master/doc/json_schema.json",
  "logo": {
    "type": "auto",
    "source": "",
    "padding": {
      "right": 4
    }
  },
  "modules": [
    "title",
    "separator",
    { "type": "os", "keyIcon": "\\uf17c" },
    "host",
    "kernel",
    "uptime",
    "packages",
    "shell",
    "de",
    "wm",
    "cpu",
    "memory",
    "swap",
    "gpu",
    { "type": "disk", "folders": "/" },
    "locale",
    "break",
    "colors"
  ]
}
JSONCFG
    ok "Created default config → $CONFIG_DIR/config.jsonc"
  fi

  ok "Logos directory ready → $LOGOS_DIR"
}

setup_path() {
  local rc_file=""
  local rc_dirs=("$HOME" "$HOME/.config/bash")
  local shell_rc=""

  case "${SHELL##*/}" in
    bash) shell_rc=".bashrc" ;;
    zsh)  shell_rc=".zshrc" ;;
    fish) shell_rc=".config/fish/config.fish" ;;
  esac

  if [ -n "$shell_rc" ]; then
    rc_file="$HOME/$shell_rc"
    if [ ! -f "$rc_file" ]; then
      touch "$rc_file"
    fi
    if ! grep -q 'export PATH="\$HOME/.local/bin:\$PATH"' "$rc_file" 2>/dev/null; then
      echo "" >> "$rc_file"
      echo '# Added by fastfetch-config installer' >> "$rc_file"
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc_file"
      ok "Added ~/.local/bin to PATH in $shell_rc"
    else
      ok "PATH entry already in $shell_rc"
    fi
  fi
}

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   fastfetch-config V1.2               ║${NC}"
echo -e "${CYAN}║   by aaronYTDev                       ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
echo ""

detect_distro
install_deps
install_scripts
setup_config "$@"
setup_path

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Installation complete!              ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}Commands:${NC}"
echo -e "    ff                      Run fastfetch with your config"
echo -e "    ff update               Update to latest stable"
echo -e "    ff update -prerelease   Update to latest (including prereleases)"
echo -e "    ff update check         Check for stable updates"
echo -e "    ff update check -prerelease  Check all updates"
echo -e "    ff version              Show version"
echo -e "    ff backup [name]        Backup current config (timestamp if no name)"
echo -e "    ff backup list          List available backups"
echo -e "    ff backup rm <name>     Remove a backup"
echo -e "    ff restore <name>       Restore a backup"
echo -e "    ff logo <name>          Set logo (built-in or custom)"
echo -e "    ff osname <str>         Set custom OS name"
echo -e "    ff osname-logo <n> [l]  Set OS name and logo"
echo -e "    ff color <n> <c>        Set logo color"
echo -e "    ff variable list        List config variables"
echo -e "    ff variable add <n>     Add a variable (default position)"
echo -e "    ff variable rm <n>      Remove a variable"
echo -e "    ff variable mv <n> <p>  Move variable to position"
echo -e "    ff variable eset <n> <f> Quick set key+format"
echo -e "    ff variable set <n> <k> <v> Set variable property"
echo -e "    ff variable show <n>    Show variable JSON"
echo -e "    ff tui                  Open interactive TUI menu"
echo -e "    ff reset [name]         Reset config or single variable"
echo -e "    ff status               Show current settings"
echo ""
echo -e "  ${YELLOW}To get started:${NC}"
echo -e "    source ~/\${shell_rc:-.bashrc}     # reload PATH"
echo -e "    ff backup            # backup current config"
echo -e "    ff logo arch         # set a built-in logo"
echo -e "    ff osname \"MyOS 1.0\" # custom OS name"
echo ""
echo "Press enter to exit..."
read
echo ""
