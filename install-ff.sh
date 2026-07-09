#!/usr/bin/env bash
# My god, what are you doing!?
# Stop messing with the code!
# ...or don't, I'm a script, not a cop.
set -euo pipefail

VERSION="V1.6.4"
BIN_DIR="${HOME}/.local/bin"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fastfetch"
LOGOS_DIR="$CONFIG_DIR/logos"

# ── Installer UI Colors ──────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
BOLD='\033[1m'

info()  { echo -e "${CYAN}::${NC} $1"; }
warn()  { echo -e "${YELLOW}::${NC} $1"; }
ok()    { echo -e "${GREEN}::${NC} $1"; }
die()   { echo -e "${RED}::${NC} $1" >&2; exit 1; }
need_cmd() { command -v "$1" &>/dev/null || die "Missing: $1"; }

# ── Distro detection ────────────────────────────────────────
detect_distro() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO="$ID"
  elif command -v lsb_release &>/dev/null; then
    DISTRO=$(lsb_release -si 2>/dev/null | tr '[:upper:]' '[:lower:]')
  else
    DISTRO="unknown"
  fi
  echo -e "  ${CYAN}Detected:${NC} ${DISTRO}"
}

# ── Install deps ────────────────────────────────────────────
install_deps() {
  echo -e "${CYAN}::${NC} Checking dependencies..."
  local pkgs=""
  command -v jq &>/dev/null || pkgs="$pkgs jq"
  command -v chafa &>/dev/null || pkgs="$pkgs chafa"
  command -v convert &>/dev/null || {
    case "${DISTRO:-}" in
      fedora|centos|rhel) pkgs="$pkgs ImageMagick" ;;
      *) pkgs="$pkgs imagemagick" ;;
    esac
  }
  [ -z "$pkgs" ] && { ok "Dependencies ready"; return; }

  case "${DISTRO:-}" in
    arch|cachyos|endeavouros|garuda|manjaro)
      sudo pacman -S --noconfirm $pkgs ;;
    ubuntu|debian|pop|linuxmint|elementary)
      sudo apt update && sudo apt install -y $pkgs ;;
    fedora|centos|rhel)
      sudo dnf install -y $pkgs ;;
    opensuse*|suse)
      sudo zypper install -y $pkgs ;;
    alpine)
      sudo apk add $pkgs ;;
    void)
      sudo xbps-install -S $pkgs ;;
    gentoo)
      pkgs=""; command -v jq &>/dev/null || pkgs="$pkgs app-misc/jq"
      command -v chafa &>/dev/null || pkgs="$pkgs media-gfx/chafa"
      [ -n "$pkgs" ] && sudo emerge $pkgs ;;
    *)
      warn "Unknown distro '${DISTRO}' - install jq, chafa, and imagemagick manually" ;;
  esac
  need_cmd jq
  ok "Dependencies ready"
}

# ── Default config JSON ─────────────────────────────────────
gen_default_config() {
  cat << 'JSONCFG'
{
  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/master/doc/json_schema.json",
  "logo": {
    "type": "auto",
    "source": "",
    "padding": { "right": 4 }
  },
  "modules": [
    "title",
    "separator",
    { "type": "os", "keyIcon": "\uf17c" },
    "host", "kernel", "uptime", "packages", "shell", "de", "wm",
    "cpu", "memory", "swap", "gpu",
    { "type": "disk", "folders": "/" },
    "locale", "break", "colors"
  ]
}
JSONCFG
}

# ── Embed fastfetch-config script ────────────────────────────
install_scripts() {
  mkdir -p "$BIN_DIR"

  cat > "$BIN_DIR/fastfetch-config" << 'FFSCRIPT'
#!/usr/bin/env bash
set -euo pipefail

VERSION="V1.6.4"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fastfetch"
CONFIG_FILE="$CONFIG_DIR/config.jsonc"
LOGOS_DIR="$CONFIG_DIR/logos"
BACKUP_DIR="$CONFIG_DIR/backups"

# ── Color Map (120+ named colors) ───────────────────────────
# Feel free to add your own!
declare -gA C=(
  [red]="#FF0000"          [darkred]="#8B0000"        [firebrick]="#B22222"
  [indianred]="#CD5C5C"    [lightcoral]="#F08080"    [salmon]="#FA8072"
  [darksalmon]="#E9967A"   [tomato]="#FF6347"        [coral]="#FF7F50"
  [maroon]="#800000"       [brown]="#A52A2A"         [crimson]="#DC143C"
  [lightsalmon]="#FFA07A"  [rosybrown]="#BC8F8F"     [mistyrose]="#FFE4E1"
  [lavenderblush]="#FFF0F5"

  [darkorange]="#FF8C00"   [orange]="#FF8000"        [goldenrod]="#DAA520"
  [darkgoldenrod]="#B8860B" [gold]="#FFD700"         [peachpuff]="#FFDAB9"
  [navajowhite]="#FFDEAD"  [khaki]="#F0E68C"         [darkkhaki]="#BDB76B"
  [bisque]="#FFE4C4"       [blanchedalmond]="#FFEBCD" [papayawhip]="#FFEFD5"
  [moccasin]="#FFE4B5"     [palegoldenrod]="#EEE8AA"  [amber]="#FFBF00"
  [yellow]="#FFFF00"

  [lime]="#32CD32"         [darkgreen]="#006400"     [forestgreen]="#228B22"
  [seagreen]="#2E8B57"     [darkseagreen]="#8FBC8F"  [mediumseagreen]="#3CB371"
  [springgreen]="#00FF7F"  [mediumspringgreen]="#00FA9A" [lawngreen]="#7CFC00"
  [chartreuse]="#7FFF00"   [greenyellow]="#ADFF2F"   [yellowgreen]="#9ACD32"
  [olivedrab]="#6B8E23"    [olive]="#808000"         [darkolivegreen]="#556B2F"
  [lightgreen]="#90EE90"   [palegreen]="#98FB98"     [emerald]="#50C878"
  [mint]="#98FF98"          [mediumaquamarine]="#66CDAA" [aquamarine]="#7FFFD4"
  [paleturquoise]="#AFEEEE" [jade]="#00A86B"

  [teal]="#008080"         [darkcyan]="#008B8B"      [lightseagreen]="#20B2AA"
  [turquoise]="#40E0D0"    [mediumturquoise]="#48D1CC" [darkturquoise]="#00CED1"
  [cyan]="#00FFFF"         [lightcyan]="#E0FFFF"     [azure]="#F0FFFF"
  [skobeloff]="#007474"    [cadetblue]="#5F9EA0"      [cerulean]="#007BA7"

  [powderblue]="#B0E0E6"   [lightblue]="#ADD8E6"     [skyblue]="#87CEEB"
  [lightskyblue]="#87CEFA" [deepskyblue]="#00BFFF"   [dodgerblue]="#1E90FF"
  [cornflowerblue]="#6495ED" [royalblue]="#4169E1"   [blue]="#0000FF"
  [mediumblue]="#0000CD"   [darkblue]="#00008B"      [navy]="#000080"
  [midnightblue]="#191970" [steelblue]="#4682B4"     [diamond]="#B9F2FF"
  [lightsteelblue]="#B0C4DE" [mediumslateblue]="#7B68EE" [denim]="#1560BD"
  [sapphire]="#0F52BA"

  [indigo]="#4B0082"       [lavender]="#E6E6FA"      [thistle]="#D8BFD8"
  [plum]="#DDA0DD"         [violet]="#EE82EE"        [orchid]="#DA70D6"
  [mediumorchid]="#BA55D3" [darkorchid]="#9932CC"    [darkviolet]="#9400D3"
  [blueviolet]="#8A2BE2"   [mediumpurple]="#9370DB"  [purple]="#BF40BF"
  [rebeccapurple]="#663399" [slateblue]="#6A5ACD"    [darkslateblue]="#483D8B"
  [lilac]="#C8A2C8"        [mauve]="#E0B0FF"

  [pink]="#FFC0CB"         [hotpink]="#FF69B4"       [deeppink]="#FF1493"
  [palevioletred]="#DB7093" [mediumvioletred]="#C71585"
  [ruby]="#E0115F"          [scarlet]="#FF2400"       [wine]="#722F37"

  [sienna]="#A0522D"       [saddlebrown]="#8B4513"   [chocolate]="#D2691E"
  [sandybrown]="#F4A460"   [peru]="#CD853F"          [tan]="#D2B48C"
  [burlywood]="#DEB887"    [wheat]="#F5DEB3"         [pearl]="#EAE0C8"
  [copper]="#B87333"       [taupe]="#483C32"

  [beige]="#F5F5DC"        [ivory]="#FFFFF0"         [antiquewhite]="#FAEBD7"
  [linen]="#FAF0E6"        [seashell]="#FFF5EE"      [honeydew]="#F0FFF0"
  [oldlace]="#FDF5E6"      [floralwhite]="#FFFAF0"   [cornsilk]="#FFF8DC"
  [lemonchiffon]="#FFFACD" [lightgoldenrodyellow]="#FAFAD2" [silver]="#C0C0C0"

  [white]="#FFFFFF"        [snow]="#FFFAFA"          [whitesmoke]="#F5F5F5"
  [ghostwhite]="#F8F8FF"   [aliceblue]="#F0F8FF"     [gainsboro]="#DCDCDC"
  [lightgray]="#D3D3D3"    [darkgray]="#A9A9A9"      [gray]="#808080"
  [dimgray]="#696969"      [darkslategray]="#2F4F4F" [lightslategray]="#778899"
  [charcoal]="#36454F"
  [slategray]="#708090"    [black]="#000000"

  [magenta]="#FF00FF"      [darkmagenta]="#8B008B"
)

# ── Utility functions ────────────────────────────────────────
CLEANUP_FILES=()
_cleanup() { rm -f "${CLEANUP_FILES[@]}"; }
trap _cleanup EXIT

die() { echo "$1" >&2; exit 1; }
need_jq() { command -v jq &>/dev/null || die "jq is required (pacman -S jq)"; }

jq_apply() {
  local tmp; tmp=$(mktemp)
  CLEANUP_FILES+=("$tmp")
  jq "$@" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
}

# ── Version comparison ───────────────────────────────────────
version_lt() {
  local v1="$1" v2="$2"
  v1="${v1#[Vv]}"; v2="${v2#[Vv]}"
  v1="${v1%%-*}";  v2="${v2%%-*}"
  [ "$(printf '%s\n' "$v1" "$v2" | sort -V | head -1)" = "$v1" ] && [ "$v1" != "$v2" ]
}

# ── Default config ───────────────────────────────────────────
gen_default_config() {
  cat << 'ENDJSON'
{
  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/master/doc/json_schema.json",
  "logo": {
    "type": "auto",
    "source": "",
    "padding": { "right": 4 }
  },
  "modules": [
    "title",
    "separator",
    { "type": "os", "keyIcon": "\uf17c" },
    "host", "kernel", "uptime", "packages", "shell", "de", "wm",
    "cpu", "memory", "swap", "gpu",
    { "type": "disk", "folders": "/" },
    "locale", "break", "colors"
  ]
}
ENDJSON
}

reset_config() {
  backup_config "pre-reset-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
  gen_default_config > "$CONFIG_FILE"
  echo "Config reset to default (backup saved)"
}

# ── Color resolution ─────────────────────────────────────────
resolve_color() {
  local key; key=$(echo "$1" | tr '[:upper:]' '[:lower:]')
  echo "${C[$key]:-$1}"
}

# ── Logo ─────────────────────────────────────────────────────
get_logo() { jq -r '.logo.source // "auto"' "$CONFIG_FILE"; }

set_logo_type_by_ext() {
  local path="$1" label="$2" current_type="${3:-}" ext=""
  case "$path" in
    *.*) ext=$(echo "$path" | sed 's/.*\.//' | tr '[:upper:]' '[:lower:]') ;;
  esac
  case "$ext" in
    png|jpg|jpeg|gif|bmp|webp|tiff|tif)
      jq_apply --arg s "$path" '.logo.type = "chafa" | .logo.source = $s'
      echo "Logo set to image (chafa): $label" ;;
    *)
      jq_apply --arg s "$path" '.logo.type = "file" | .logo.source = $s | del(.logo.width) | del(.logo.chafa)'
      echo "Logo set to custom file: $label" ;;
  esac
}

set_logo() {
  local name="$1"
  local current_type
  current_type=$(jq -r '.logo.type // "auto"' "$CONFIG_FILE")

  if [ "$name" = "auto" ]; then
    jq_apply '.logo.type = "auto" | .logo.source = ""'
    echo "Logo set to auto-detection"
  elif [ -f "$name" ]; then
    local logo_path="$LOGOS_DIR/$(basename "$name")"
    cp "$name" "$logo_path"
    set_logo_type_by_ext "$logo_path" "$name" "$current_type"
  elif [ -f "$LOGOS_DIR/$name" ]; then
    set_logo_type_by_ext "$LOGOS_DIR/$name" "$name" "$current_type"
  else
    jq_apply --arg s "$name" '.logo.type = "builtin" | .logo.source = $s | del(.logo.width) | del(.logo.chafa)'
    echo "Logo set to built-in: $name"
  fi
  set_logo_fit
}

set_logo_fit() {
  local lines cols t cw ch lh
  lines=$(tput lines 2>/dev/null || echo 40)
  cols=$(tput cols 2>/dev/null || echo 80)
  t=$(jq -r '.logo.type // "auto"' "$CONFIG_FILE")

  case "$t" in
    chafa|chafaRaw)
      local info_width
      info_width=$(fastfetch --logo-type none --pipe 2>/dev/null \
        | sed 's/\x1b\[[0-9;]*m//g' \
        | awk 'length > max { max = length } END { print max+0 }')
      if [ -z "$info_width" ] || [ "$info_width" -lt 10 ]; then
        cw=$(( cols > 80 ? cols * 45 / 100 : cols * 5 / 10 ))
      else
        local min_info=$(( cols * 35 / 100 ))
        cw=$info_width
        [ "$cw" -gt $(( cols - min_info - 4 )) ] && cw=$(( cols - min_info - 4 ))
      fi
      ch=$(( lines - 12 ))
      [ "$cw" -lt 20 ] && cw=20; [ "$cw" -gt 80 ] && cw=80
      [ "$ch" -lt 5 ]  && ch=5;  [ "$ch" -gt 40 ] && ch=40
      jq_apply --argjson w "$cw" --argjson h "$ch" \
        '.logo.width = $w | .logo.height = $h'
      echo "  Fit: chafa ${cw}x${ch} @ ${cols}x${lines} term" ;;
    file|builtin)
      lh=$(( lines - 15 ))
      [ "$lh" -lt 5 ] && lh=5; [ "$lh" -gt 50 ] && lh=50
      jq_apply --argjson h "$lh" 'del(.logo.width) | del(.logo.chafa) | .logo.height = $h'
      echo "  Fit: height ${lh} @ ${cols}x${lines} term" ;;
  esac
}

# ── Chafa ────────────────────────────────────────────────────
get_chafa() {
  local t; t=$(jq -r '.logo.type // "auto"' "$CONFIG_FILE")
  case "$t" in chafa|chafaRaw) echo "enabled ($t)";; *) echo "disabled";; esac
}

set_chafa() {
  local mode="$1" name="${2:-}"
  case "$mode" in
    on|enable|chafa)
      if [ -n "$name" ]; then
        local logo_path="$LOGOS_DIR/$(basename "$name")"
        cp "$name" "$logo_path"
        jq_apply --arg s "$logo_path" '.logo.type = "chafa" | .logo.source = $s'
        echo "Chafa enabled with image: $name"
      else
        jq_apply '.logo.type = "chafa"'
        echo "Chafa logo rendering enabled"
      fi ;;
    raw|chafaRaw)
      if [ -n "$name" ]; then
        local logo_path="$LOGOS_DIR/$(basename "$name")"
        cp "$name" "$logo_path"
        jq_apply --arg s "$logo_path" '.logo.type = "chafaRaw" | .logo.source = $s'
        echo "Chafa raw enabled with image: $name"
      else
        jq_apply '.logo.type = "chafaRaw"'
        echo "Chafa raw rendering enabled"
      fi ;;
    off|disable|auto)
      jq_apply '.logo.type = "auto" | .logo.source = "" | del(.logo.width) | del(.logo.chafa) | del(.logo.height)'
      echo "Chafa logo rendering disabled" ;;
  esac
  set_logo_fit
}

FF_IS_CHAFA=0
is_image_ext() {
  local f="$1" ext=""
  case "$f" in *.*) ext=$(echo "$f" | sed 's/.*\.//' | tr '[:upper:]' '[:lower:]') ;; esac
  case "$ext" in png|jpg|jpeg|gif|bmp|webp|tiff|tif) return 0 ;; *) return 1 ;; esac
}

auto_chafa() {
  local t src
  t=$(jq -r '[.logo.type // "auto", .logo.source // ""] | join("|")' "$CONFIG_FILE")
  src="${t#*|}"; t="${t%%|*}"
  FF_IS_CHAFA=0
  { [ "$t" = "chafa" ] || [ "$t" = "chafaRaw" ]; } && { FF_IS_CHAFA=1; return 0; }
  [ "$t" != "auto" ] && return 0
  command -v chafa &>/dev/null || return 0
  [ -z "$src" ] && return 0
  is_image_ext "$src" || return 0
  set_chafa on; FF_IS_CHAFA=1
}

# ── OS Name ──────────────────────────────────────────────────
get_osname() {
  local val
  val=$(jq -r '.modules[] | select(type == "object") | select(.type == "custom" and .key == "OS") | .format // ""' "$CONFIG_FILE")
  [ -z "$val" ] && echo "auto" || echo "$val"
}

set_osname() {
  local name="$1"
  if [ "$name" = "auto" ]; then
    jq_apply '
      ([.modules | to_entries[] | select(.value | type == "object") | select(.value.type == "custom" and .value.key == "OS") | .key] | first) as $idx |
      if $idx then .modules[$idx] = {type: "os", keyIcon: "\uf17c"} else . end
    '
    echo "OS name set to auto-detection"
  else
    local has_custom
    has_custom=$(jq '[.modules[] | select(type == "object") | select(.type == "custom" and .key == "OS")] | length' "$CONFIG_FILE")
    if [ "$has_custom" -gt 0 ]; then
      jq_apply --arg n "$name" '(.modules[] | select(type == "object") | select(.type == "custom" and .key == "OS") | .format) = $n'
    else
      jq_apply --arg n "$name" '
        ([.modules | to_entries[] | select(.value | type == "object") | select(.value.type == "os") | .key] | first) as $idx |
        if $idx then .modules[$idx] = {type: "custom", key: "OS", format: $n}
        else .modules += [{type: "custom", key: "OS", format: $n}] end
      '
    fi
    echo "OS name set to: $name"
  fi
}

# ── Logo Colors ──────────────────────────────────────────────
get_colors() {
  jq -r '(.logo.color // {}) | to_entries[] | select(.value != "") | "\(.key): \(.value)"' "$CONFIG_FILE" 2>/dev/null || true
}

set_color() {
  local slot="$1" color_val; color_val=$(resolve_color "$2")
  case "$slot" in
    ''|*[!0-9]*) echo "Warning: slot '$slot' is not a number" >&2 ;;
    *) if [ "$slot" -lt 1 ] || [ "$slot" -gt 9 ] 2>/dev/null; then
         echo "Warning: slot '$slot' is outside the typical 1-9 range" >&2
       fi ;;
  esac
  jq_apply --arg c "$color_val" --arg s "$slot" \
    '.logo.color = ((.logo.color // {}) + {($s): $c})'
  echo "Logo color $slot set to: $color_val"
}

reset_colors() { jq_apply '.logo.color = {}'; echo "All logo color overrides cleared"; }

list_color_names() {
  for key in "${!C[@]}"; do echo "$key"; done | sort
}

search_colors() {
  local term="$1" key found=0
  for key in "${!C[@]}"; do
    if echo "$key" | grep -qi "$term"; then
      echo "$key"; found=1
    fi
  done
  [ "$found" -eq 0 ] && echo "No colors matching '$term'"
}

# ── Modules ──────────────────────────────────────────────────
get_default_pos() {
  case "$1" in
    title) echo 0 ;; separator) echo 1 ;; os) echo 2 ;; host) echo 3 ;;
    kernel) echo 4 ;; uptime) echo 5 ;; packages) echo 6 ;; shell) echo 7 ;;
    de) echo 8 ;; wm) echo 9 ;; cpu) echo 10 ;; memory) echo 11 ;;
    swap) echo 12 ;; gpu) echo 13 ;; disk) echo 14 ;; locale) echo 15 ;;
    break) echo 16 ;; colors) echo 17 ;;
    *) echo -1 ;;
  esac
}

list_modules() { jq -r '.modules[] | if type == "object" then .type else . end' "$CONFIG_FILE"; }
show_module()  { jq --arg n "$1" '.modules[] | select(if type == "string" then . == $n else .type == $n end)' "$CONFIG_FILE"; }
module_exists() { jq -r --arg n "$1" '[.modules[] | select(if type == "string" then . == $n else .type == $n end)] | length' "$CONFIG_FILE"; }

add_module() {
  local name="$1"
  [ "$(module_exists "$name")" -gt 0 ] && { echo "Module '$name' already exists"; return; }
  local pos; pos=$(get_default_pos "$name")
  if [ "$pos" -ge 0 ]; then
    if [ "$name" = "disk" ]; then
      jq_apply --arg n "$name" --argjson p "$pos" '.modules = (.modules[:$p] + [{type: $n, folders: "/"}] + .modules[$p:])'
    else
      jq_apply --arg n "$name" --argjson p "$pos" '.modules = (.modules[:$p] + [$n] + .modules[$p:])'
    fi
  else
    [ "$name" = "disk" ] && jq_apply --arg n "$name" '.modules += [{type: $n, folders: "/"}]' \
      || jq_apply --arg n "$name" '.modules += [$n]'
  fi
  echo "Added module: $name"
}

remove_module() {
  local name="$1"
  [ "$(module_exists "$name")" -eq 0 ] && { echo "Module '$name' not found"; return; }
  jq_apply --arg n "$name" '.modules = [.modules[] | select(if type == "string" then . != $n else .type != $n end)]'
  echo "Removed module: $name"
}

set_module() {
  local name="$1" key="$2" value="$3"
  local is_string
  is_string=$(jq -r --arg n "$name" '[.modules[] | select(type == "string" and . == $n)] | length' "$CONFIG_FILE")
  if [ "$is_string" -gt 0 ]; then
    jq_apply --arg n "$name" --arg k "$key" --arg v "$value" '
      (.modules | to_entries[] | select(.value == $n)) as $e |
      .modules[$e.key] = {type: $n, ($k): $v}
    '
  else
    local is_obj
    is_obj=$(jq -r --arg n "$name" '[.modules[] | select(type == "object") | select(.type == $n)] | length' "$CONFIG_FILE")
    [ "$is_obj" -eq 0 ] && { echo "Module '$name' not found"; return; }
    jq_apply --arg n "$name" --arg k "$key" --arg v "$value" \
      '(.modules[] | select(type == "object") | select(.type == $n))[$k] = $v'
  fi
  echo "Set $name.$key = $value"
}

reset_module() {
  local name="$1"
  [ "$(module_exists "$name")" -eq 0 ] && { echo "Module '$name' not found"; return; }
  jq_apply --arg n "$name" '
    (.modules | to_entries[] | select(.value | if type == "string" then . == $n else .type == $n end)) as $e |
    .modules[$e.key] = (
      if $n == "os" then {type: "os", keyIcon: "\uf17c"}
      elif $n == "disk" then {type: "disk", folders: "/"}
      else $n
      end
    )
  '
  echo "Reset '$name' to default"
}

move_module() {
  local name="$1" new_pos="$2"
  [ "$(module_exists "$name")" -eq 0 ] && { echo "Module '$name' not found"; return; }
  local total; total=$(jq '.modules | length' "$CONFIG_FILE")
  [ "$new_pos" -lt 1 ] || [ "$new_pos" -gt "$total" ] && { echo "Position must be between 1 and $total"; return; }
  local idx=$((new_pos - 1))
  jq_apply --arg n "$name" --argjson p "$idx" '
    (.modules | to_entries[] | select(.value | if type == "string" then . == $n else .type == $n end)) as $e |
    .modules = (.modules[:$e.key] + .modules[$e.key+1:]) |
    .modules = (.modules[:$p] + [$e.value] + .modules[$p:])
  '
  echo "Moved '$name' to position $new_pos"
}

# ── Backup / Restore ─────────────────────────────────────────
backup_config() {
  local name="${1:-}"
  mkdir -p "$BACKUP_DIR"
  [ -z "$name" ] && name="backup-$(date +%Y%m%d-%H%M%S)"
  local dest="$BACKUP_DIR/$name.jsonc"
  if [ -f "$dest" ]; then
    echo "Backup '$name' already exists. Overwrite? (y/N): "
    read -r ans </dev/tty 2>/dev/null || { echo "Non-interactive shell — aborting"; return; }
    [ "$ans" != "y" ] && [ "$ans" != "Y" ] && { echo "Canceled"; return; }
  fi
  cp "$CONFIG_FILE" "$dest"
  echo "Backup saved: $dest"
}

list_backups() {
  mkdir -p "$BACKUP_DIR"
  shopt -s nullglob; local files=("$BACKUP_DIR"/*.jsonc); shopt -u nullglob
  [ ${#files[@]} -eq 0 ] && { echo "No backups found in $BACKUP_DIR"; return; }
  echo "Available backups:"
  for f in "${files[@]}"; do
    local bname; bname=$(basename "$f" .jsonc)
    local bdate; bdate=$(stat -c "%y" "$f" 2>/dev/null | cut -d. -f1)
    echo "  $bname  ($bdate)"
  done
}

restore_config() {
  local name="$1"
  local src="$BACKUP_DIR/$name.jsonc"
  [ ! -f "$src" ] && { echo "Backup '$name' not found"; echo "Use 'ff backup list' to see available backups"; return; }
  cp "$src" "$CONFIG_FILE"
  echo "Restored backup: $name"
}

remove_backup() {
  local file="$BACKUP_DIR/$1.jsonc"
  [ ! -f "$file" ] && { echo "Backup '$1' not found"; return; }
  rm "$file"
  echo "Removed backup: $1"
}

# ── Self-update ──────────────────────────────────────────────
self_update() {
  local mode="${1:-}" allow_prerelease="${2:-}"
  echo "Checking for updates..."
  local release_data
  release_data=$(curl -sL --connect-timeout 5 --max-time 10 \
    "https://api.github.com/repos/AaronYTDev/fastfetch-config/releases/latest" 2>/dev/null || true)
  [ -z "$release_data" ] && { echo "Failed to reach GitHub. Check your internet connection."; return; }
  local remote_version; remote_version=$(echo "$release_data" | jq -r '.tag_name' 2>/dev/null || true)
  local release_name; release_name=$(echo "$release_data" | jq -r '.name' 2>/dev/null || true)
  local display="${release_name:-$remote_version}"
  [ -z "$remote_version" ] && { echo "Failed to parse release info from GitHub."; return; }
  echo "Current: $VERSION"
  echo "Remote:  $display"

  if ! version_lt "$VERSION" "$remote_version"; then
    echo "You're up to date! Hip, Hip, Hooray!"
    return
  fi

  local is_prerelease;  is_prerelease=$(echo "$display" | grep -c '\-prerelease' || true)
  local is_local_prerelease; is_local_prerelease=$(echo "$VERSION" | grep -c '\-prerelease' || true)

  if [ "$is_local_prerelease" -eq 0 ] && [ "$is_prerelease" -eq 1 ] && [ "$allow_prerelease" != "prerelease" ]; then
    if [ "$mode" = "check" ]; then echo "Prerelease available ($display). Use 'ff update -prerelease' to install the prerelease build."
    else echo "Skipping prerelease build. Use 'ff update -prerelease' to install prereleases."; fi
    return
  fi

  [ "$mode" = "check" ] && { echo "Update available ($display)! Run 'ff update' to install."; return; }

  local asset_url body
  asset_url=$(echo "$release_data" | jq -r '.assets[] | select(.name == "install-ff.sh") | .browser_download_url' 2>/dev/null || true)
  body=$(echo "$release_data" | jq -r '.body // "No changelog provided"' 2>/dev/null || true)
  [ -z "$asset_url" ] && { echo "Could not find the installer in the latest release."; return; }
  echo; echo "Changelog for $display:"
  echo "$body" | head -30
  echo; read -p "Continue with update? (Y/n): " ans </dev/tty 2>/dev/null || ans="y"
  case "$ans" in n|N|no) echo "Update canceled."; return ;; esac
  echo; echo "Downloading update..."
  local tmp; tmp=$(mktemp); CLEANUP_FILES+=("$tmp")
  if curl -sL --connect-timeout 5 --max-time 60 -o "$tmp" "$asset_url"; then
    chmod +x "$tmp"; echo "Running installer..."; bash "$tmp"
  else
    echo "Downloading the installer failed. Try again later."
  fi
}

check_update_quiet() {
  local cache_file="$BACKUP_DIR/.update_check" remote_version
  if [ -f "$cache_file" ]; then
    local age=$(( $(date +%s) - $(stat -c %Y "$cache_file") ))
    [ "$age" -lt 86400 ] && return
  fi
  remote_version=$(curl -sL --connect-timeout 3 --max-time 4 \
    "https://api.github.com/repos/AaronYTDev/fastfetch-config/releases/latest" 2>/dev/null \
    | jq -r '.tag_name' 2>/dev/null || true)
  [ -z "$remote_version" ] && { rm -f "$cache_file"; return; }
  echo "$remote_version" > "$cache_file"
  if version_lt "$VERSION" "$remote_version"; then
    local is_prerelease; is_prerelease=$(echo "$remote_version" | grep -c '\-prerelease' || true)
    local is_local_prerelease; is_local_prerelease=$(echo "$VERSION" | grep -c '\-prerelease' || true)
    [ "$is_local_prerelease" -eq 0 ] && [ "$is_prerelease" -eq 1 ] && return
    echo "[update] Version $remote_version available! Run 'ff update' to install the latest build."
  fi
}

# ── Logo preview / export / import ──────────────────────────
preview_logo() {
  local t; t=$(jq -r '.logo.type // "auto"' "$CONFIG_FILE")
  echo "Logo type: $t"
  echo "Source: $(get_logo)"
  echo "Logo dir: $LOGOS_DIR"
  case "$t" in
    chafa|chafaRaw)
      local w h
      w=$(jq -r '.logo.width // "auto"' "$CONFIG_FILE")
      h=$(jq -r '.logo.height // "auto"' "$CONFIG_FILE")
      echo "Dimensions: ${w}x${h}" ;;
  esac
}

export_config() {
  local file="${1:-fastfetch-config-export-$(date +%Y%m%d).jsonc}"
  cp "$CONFIG_FILE" "$file"
  echo "Config exported to $file"
}

import_config() {
  local file="$1"
  [ ! -f "$file" ] && { echo "File not found: $file"; return; }
  backup_config "pre-import-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
  cp "$file" "$CONFIG_FILE"
  echo "Config imported from $file (backup saved)"
}

# ── Doctor ──────────────────────────────────────────────────
doctor() {
  echo "Checking fastfetch-config setup..."
  local issues=0
  command -v jq &>/dev/null || { echo "  [FAIL] jq not found"; issues=$((issues+1)); }
  command -v fastfetch &>/dev/null || { echo "  [FAIL] fastfetch not found"; issues=$((issues+1)); }
  if [ -f "$CONFIG_FILE" ]; then
    jq . "$CONFIG_FILE" &>/dev/null && echo "  [OK] Config file is valid JSON" \
      || { echo "  [FAIL] Config file is not valid JSON"; issues=$((issues+1)); }
  else echo "  [FAIL] Config file not found at $CONFIG_FILE"; issues=$((issues+1)); fi
  [ -d "$LOGOS_DIR" ] && echo "  [OK] Logos directory exists" || echo "  [WARN] Logos directory missing"
  [ -d "$BACKUP_DIR" ] && echo "  [OK] Backup directory exists" || echo "  [WARN] Backup directory missing"
  [ "$issues" -eq 0 ] && echo "All good!" || echo "$issues issue(s) found"
}

# ── Usage ────────────────────────────────────────────────────
usage() {
  cat <<EOF
Usage: fastfetch-config <command> [args]

Configuration:
  status                Show current settings
  config-path           Show config file path
  reset [name]          Reset config or individual module to default
  export [file]         Export config to a file
  import <file>         Import config from a file

Logo:
  logo [name|fit]       Show/set logo, "fit" to resize, "auto" for detection
  logo preview          Show logo details
  logo width|height <n>  Manually set logo dimensions
  color <slot> <c>      Set logo color slot (1-9), e.g. ff color 1 blue
  color list            Show logo color overrides
  color names           List all available color names
  color search <term>   Search for a color name
  color reset           Clear all logo color overrides
  list-logos            List available built-in logos
  chafa [on|off|raw|fit] [file]  Show/set chafa image rendering mode

OS:
  os|osname [name]      Show/set OS name, or "auto" to restore detection
  osname-logo <n> [l]   Set OS name and logo (one arg sets both)

Modules:
  module                List all modules
  module add <name>     Add a module (inserted at default pos)
  module remove <name>  Remove a module from the config
  module move <name> <pos> Move a module to position (1-based)
  module set <n> <k> <v> Set a property on a module
  module eset <n> <f>   Set key+format in one go ("Kernel" "MyOS")
  module reset all      Reset all modules to defaults

Other:
  backup [name]         Save a backup of current config
  backup list           List available backups
  backup remove <name>  Remove a backup
  restore <name>        Restore a backup
  doctor|check          Check for common setup issues
  update [check]        Check for / install updates from GitHub
  version               Show version
  tui|interactive|menu   Open interactive TUI menu
  help                  Show this help

Modules: host, kernel, uptime, packages, shell, de, wm, cpu, memory,
            swap, gpu, disk, locale

Colors: over 150 named colors including orange, purple, skobeloff, gold,
         emerald, silver, diamond, lime, pink, crimson, coral, indigo,
         mint, pearl, red, blue, green, cyan, magenta, and many more.
         Also accepts ANSI codes (32, 93) and raw hex codes (#FF8000).

Examples:
  fastfetch-config export my-config.jsonc
  fastfetch-config import my-config.jsonc
  fastfetch-config backup
  fastfetch-config logo arch
  fastfetch-config logo preview
  fastfetch-config osname "MyOS 1.0"
  fastfetch-config color 1 cyan
  fastfetch-config color names
  fastfetch-config color search purple
  fastfetch-config module reset all
  fastfetch-config module list
  fastfetch-config doctor
  ff                    Run fastfetch directly
  fastfetch-config update
  fastfetch-config update check
EOF
}

# ── TUI ──────────────────────────────────────────────────────
tui_backup() {
  while true; do
    clear; echo "═══ Backup / Restore / Remove ═══"; echo
    echo "1) Create backup"; echo "2) List backups"; echo "3) Restore backup"
    echo "4) Remove backup"; echo "5) Back"; echo
    read -n 1 -p "Select option: " choice; echo
    case "$choice" in
      1) read -p "Backup name (enter for timestamp): " name; backup_config "$name"; read -p "Press enter..." _ ;;
      2) list_backups; echo; read -p "Press enter..." _ ;;
      3) list_backups; echo; read -p "Backup name to restore: " name; restore_config "$name"; read -p "Press enter..." _ ;;
      4) list_backups; echo; read -p "Backup name to remove: " name; remove_backup "$name"; read -p "Press enter..." _ ;;
      5|q|back) break ;;
      *) echo "Invalid option"; read -p "Press enter..." _ ;;
    esac
  done
}

tui_modules() {
  while true; do
    clear; echo "═══ Modules ═══"
    echo "Current: $(list_modules | tr '\n' ' ')"; echo
    echo "1) Add"; echo "2) Remove"; echo "3) Move"; echo "4) Set property"
    echo "5) Easy set (key+format)"; echo "6) Back"; echo
    read -n 1 -p "Select option: " choice; echo
    case "$choice" in
      1) read -p "Module name to add: " name; add_module "$name"; read -p "Press enter..." _ ;;
      2) read -p "Module name to remove: " name; remove_module "$name"; read -p "Press enter..." _ ;;
      3) read -p "Module name: " name; read -p "New position (1-based): " pos; move_module "$name" "$pos"; read -p "Press enter..." _ ;;
      4) read -p "Module name: " name; read -p "Property key: " key; read -p "Property value: " val; set_module "$name" "$key" "$val"; read -p "Press enter..." _ ;;
      5) read -p "Module name: " name; read -p "Display label (key): " key; read -p "Display value (format): " fmt
         local nlow; nlow=$(echo "$name" | tr '[:upper:]' '[:lower:]')
         if [ "$(module_exists "$nlow")" -eq 0 ]; then echo "Module '$name' not found"
         else set_module "$nlow" "key" "$key"; set_module "$nlow" "format" "$fmt"; echo "Easy-set complete: $name -> $fmt"
         fi; read -p "Press enter..." _ ;;
      6|q|back) break ;;
      *) echo "Invalid option"; read -p "Press enter..." _ ;;
    esac
  done
}

tui_logo() {
  clear; echo "═══ Logo ═══"
  echo "Modules: $(list_modules | tr '\n' ' ')"
  echo "Current: $(get_logo)"; echo
  read -p "Logo name (or 'auto'): " name; set_logo "$name"
}

tui_chafa() {
  while true; do
    clear; echo "═══ Chafa ═══"
    echo "Current: $(get_chafa)"; echo
    echo "1) Enable chafa"; echo "2) Enable chafa (raw mode)"
    echo "3) Enable with image (normal)"; echo "4) Enable with image (raw)"
    echo "5) Disable chafa"; echo "6) Re-fit"; echo "7) Back"; echo
    read -n 1 -p "Select option: " choice; echo
    case "$choice" in
      1) set_chafa on; read -p "Press enter..." _ ;;
      2) set_chafa raw; read -p "Press enter..." _ ;;
      3) read -p "Image file path: " img; [ -f "$img" ] && set_chafa on "$img" || echo "File not found: $img"; read -p "Press enter..." _ ;;
      4) read -p "Image file path: " img; [ -f "$img" ] && set_chafa raw "$img" || echo "File not found: $img"; read -p "Press enter..." _ ;;
      5) set_chafa off; read -p "Press enter..." _ ;;
      6) set_logo_fit; read -p "Press enter..." _ ;;
      7|q|back|b) break ;;
      *) echo "Invalid option"; sleep 1 ;;
    esac
  done
}

tui_osname() {
  clear; echo "═══ OS Name ═══"
  echo "Modules: $(list_modules | tr '\n' ' ')"
  echo "Current: $(get_osname)"; echo
  read -p "OS name (or 'auto'): " name; set_osname "$name"
}

tui_colors() {
  clear; echo "═══ Colors ═══"
  local cols; cols=$(get_colors)
  if [ -n "$cols" ]; then echo "Current overrides:"; echo "$cols" | sed 's/^/  /'
  else echo "No color overrides set"; fi
  echo
  read -p "Color slot (1-9, or q to quit): " slot
  [ "$slot" = "q" ] || [ "$slot" = "quit" ] || [ "$slot" = "back" ] && return
  read -p "Color (name, hex, or ANSI code): " color
  set_color "$slot" "$color"
}

tui_status() {
  clear; echo "═══ Status ═══"
  echo "Config: $CONFIG_FILE"
  echo "Logo: $(get_logo)"
  echo "OS name: $(get_osname)"
  echo "Logos dir: $LOGOS_DIR"
  local cols; cols=$(get_colors)
  [ -n "$cols" ] && { echo "Logo colors:"; echo "$cols" | sed 's/^/  /'; }
  echo "Modules: $(list_modules | tr '\n' ' ')"; echo
  read -p "Press enter..." _
}

tui_reset() {
  while true; do
    clear; echo "═══ Reset ═══"
    echo "Modules: $(list_modules | tr '\n' ' ')"
    echo "1) Reset entire config"; echo "2) Reset a single module"; echo "3) Back"; echo
    read -n 1 -p "Select option: " choice; echo
    case "$choice" in
      1) reset_config; read -p "Press enter..." _ ;;
      2) read -p "Module name to reset: " name; reset_module "$name"; read -p "Press enter..." _ ;;
      3|q|back) break ;;
    esac
  done
}

tui_menu() {
  auto_chafa; check_update_quiet
  while true; do
    clear
    echo "╔══════════════════════════╗"
    echo "║  fastfetch-config TUI    ║"
    echo "╚══════════════════════════╝"
    echo "1) Modules"; echo "2) Logo"; echo "3) OS Name"; echo "4) Colors"
    echo "5) Status"; echo "6) Chafa"; echo "7) Reset"; echo "8) Update"
    echo "9) Backup / Restore"; echo "A) Help"; echo "0) Exit"; echo "F) Pay Respects"; echo
    read -n 1 -p "Select option: " choice; echo
    case "$choice" in
      1) tui_modules ;; 2) tui_logo ;; 3) tui_osname ;; 4) tui_colors ;;
      5) tui_status ;; 6|c|chafa) tui_chafa ;; 7) tui_reset ;;
      8|u|update) clear; self_update; read -p "Press enter..." _ ;;
      9|b|backup) tui_backup ;;
      a|h|help) clear; usage; echo; read -p "Press enter..." _ ;;
      0|q|exit) clear; echo "Goodbye!"; echo; ff config 2>/dev/null || true; break ;;
      f|F) echo "F's in chat. Press enter..."; read -r _ ;;
      *) echo "Invalid option"; sleep 1 ;;
    esac
  done
}

# ── Main dispatch ────────────────────────────────────────────
need_jq
mkdir -p "$LOGOS_DIR" "$BACKUP_DIR"

case "${1:-}" in
  logo)
    case "${2:-}" in
      fit) set_logo_fit ;;
      preview|show|info) preview_logo ;;
      width)
        [ -z "${3:-}" ] && { echo "Current logo width: $(jq -r '.logo.width // "auto"' "$CONFIG_FILE")"; exit 0; }
        jq_apply --argjson w "${3}" '.logo.width = $w'
        echo "Logo width set to ${3}" ;;
      height)
        [ -z "${3:-}" ] && { echo "Current logo height: $(jq -r '.logo.height // "auto"' "$CONFIG_FILE")"; exit 0; }
        jq_apply --argjson h "${3}" '.logo.height = $h'
        echo "Logo height set to ${3}" ;;
      "")  echo "Current logo: $(get_logo)" ;;
      *)   set_logo "$2" ;;
    esac ;;
  osname)
    [ -z "${2:-}" ] && echo "Current OS name: $(get_osname)" || set_osname "$2" ;;
  osname-logo)
    [ -z "${2:-}" ] && { echo "Usage: fastfetch-config osname-logo <name> [logoname]"; exit 1; }
    [ -z "${3:-}" ] && { set_osname "$2"; set_logo "$2"; } || { set_osname "$2"; set_logo "$3"; } ;;
  list-logos|list|ls)
    fastfetch --print-logos 2>&1 | head -100; echo
    if ls -A "$LOGOS_DIR" &>/dev/null; then
      echo "Custom logos in $LOGOS_DIR:"; ls "$LOGOS_DIR"
    fi ;;
  color)
    case "${2:-}" in
      list)
        cols=$(get_colors)
        echo "Current logo color overrides:"
        [ -z "$cols" ] && echo "  (none set)" || echo "$cols" ;;
      names|list-names) list_color_names ;;
      search) [ -z "${3:-}" ] && { echo "Usage: fastfetch-config color search <term>"; exit 1; }
              search_colors "$3" ;;
      reset) reset_colors ;;
      *)
        [ -z "${2:-}" ] || [ -z "${3:-}" ] && { echo "Usage: fastfetch-config color <slot(1-9)> <color>"; echo "       fastfetch-config color list"; echo "       fastfetch-config color reset"; exit 1; }
        set_color "$2" "$3" ;;
    esac ;;
  chafa)
    case "${2:-}" in
      on|enable)        set_chafa on "${3:-}" ;;
      raw|chafaRaw)     set_chafa raw "${3:-}" ;;
      fit|refit)        set_logo_fit ;;
      off|disable|auto) set_chafa off ;;
      "")
        echo "Chafa: $(get_chafa)"
        echo "Usage: fastfetch-config chafa [on|off|raw|fit] [image-file]"
        echo "  on [file]   Enable chafa (optionally with an image)"
        echo "  raw [file]  Enable chafa raw mode (optionally with an image)"
        echo "  fit         Re-fit chafa to terminal size"
        echo "  off         Disable chafa, revert to auto" ;;
      *) echo "Unknown option: $2"; echo "Usage: fastfetch-config chafa [on|off|raw|fit] [image-file]" ;;
    esac ;;
  status)
    echo "Fastfetch config: $CONFIG_FILE"
    echo "Logo: $(get_logo)"
    echo "Chafa: $(get_chafa)"
    echo "OS name: $(get_osname)"
    echo "Custom logos dir: $LOGOS_DIR"
    cols=$(get_colors)
    [ -n "$cols" ] && { echo "Logo colors:"; echo "$cols" | sed 's/^/  /'; }
    echo "Modules: $(list_modules | tr '\n' ' ')" ;;
  module|var)
    case "${2:-}" in
      list|"") echo "Current modules:"; list_modules ;;
      add)     [ -z "${3:-}" ] && { echo "Usage: fastfetch-config module add <name>"; exit 1; }
               add_module "$3" ;;
      remove|rm) [ -z "${3:-}" ] && { echo "Usage: fastfetch-config module remove <name>"; exit 1; }
                 remove_module "$3" ;;
      move|mv|reorder) [ -z "${3:-}" ] || [ -z "${4:-}" ] && { echo "Usage: fastfetch-config module move <name> <position>"; exit 1; }
                       move_module "$3" "$4" ;;
      set)   [ -z "${3:-}" ] || [ -z "${4:-}" ] || [ -z "${5:-}" ] && { echo "Usage: fastfetch-config module set <name> <key> <value>"; exit 1; }
             set_module "$3" "$4" "$5" ;;
      eset)  [ -z "${3:-}" ] || [ -z "${4:-}" ] && { echo "Usage: fastfetch-config module eset <keyname> <formatname>"; exit 1; }
             local nlow; nlow=$(echo "$3" | tr '[:upper:]' '[:lower:]')
             [ "$(module_exists "$nlow")" -eq 0 ] && { echo "Module '$3' not found"; exit 1; }
             set_module "$nlow" "key" "$3"
             set_module "$nlow" "format" "$4"
             echo "Easy-set complete: $3 -> $4" ;;
      reset)
        if [ "${3:-}" = "all" ]; then
          for m in title separator os host kernel uptime packages shell de wm cpu memory swap gpu disk locale break colors; do
            [ "$(module_exists "$m")" -gt 0 ] && reset_module "$m"
          done; echo "All modules reset to default"
        else echo "Usage: fastfetch-config module reset all"; fi ;;
      show|get) [ -z "${3:-}" ] && { echo "Usage: fastfetch-config module show <name>"; exit 1; }
                show_module "$3" ;;
      *) echo "Unknown subcommand: ${2:-}"; echo "Usage: fastfetch-config module [list|add|remove|set|show|reset]"; exit 1 ;;
    esac ;;
  reset)
    if [ -n "${2:-}" ]; then reset_module "$2"; else reset_config; fi ;;  
  backup)
    case "${2:-}" in
      list) list_backups ;;
      "")  backup_config ;;
      remove|rm) remove_backup "${3:-}" ;;
      *) backup_config "$2" ;;
    esac ;;
  restore)
    [ -z "${2:-}" ] && { echo "Usage: fastfetch-config restore <name>"; echo "       fastfetch-config restore list"; exit 1; }
    case "${2:-}" in list) list_backups ;; *) restore_config "$2" ;; esac ;;
  export|export-config) export_config "${2:-}" ;;
  import|import-config)
    [ -z "${2:-}" ] && { echo "Usage: fastfetch-config import <file>"; exit 1; }
    import_config "$2" ;;
  config-path|configpath) echo "$CONFIG_FILE" ;;
  doctor|check) doctor ;;
  os)
    [ -z "${2:-}" ] && echo "Current OS name: $(get_osname)" || set_osname "$2" ;;
  version|--version)
    echo "fastfetch-config $VERSION" ;;
  update)
    case "${2:-}" in
      check) case "${3:-}" in -prerelease|--prerelease) self_update check prerelease ;; *) self_update check ;; esac ;;
      -prerelease|--prerelease) self_update "" prerelease ;;
      --help|-h|help) echo "Usage: ff update [check] [-prerelease]"; echo "  update              Download and install latest stable"; echo "  update check        Check for stable updates"; echo "  update -prerelease  Download and install latest (including prereleases)"; echo "  update check -prerelease  Check all updates including prereleases" ;;
      "") self_update ;;
      *) echo "Unknown option: ${2:-}"; echo "Usage: ff update [check] [-prerelease]" ;;
    esac ;;
  tui|interactive|menu) tui_menu ;;
  help|--help|-h) usage ;;
  *)
    auto_chafa
    check_update_quiet
    [ "$FF_IS_CHAFA" -eq 1 ] && set -- --pipe false "$@"
    exec fastfetch "$@" ;;
esac
FFSCRIPT

  chmod +x "$BIN_DIR/fastfetch-config"
  ok "Installed fastfetch-config -> $BIN_DIR/fastfetch-config"

  cat > "$BIN_DIR/ff" << 'FFALIAS'
#!/usr/bin/env bash
exec fastfetch-config "$@"
FFALIAS
  chmod +x "$BIN_DIR/ff"
  ok "Installed ff alias -> $BIN_DIR/ff"
}

# ── Config setup ────────────────────────────────────────────
setup_config() {
  mkdir -p "$CONFIG_DIR" "$LOGOS_DIR"

  if [ -f "$CONFIG_DIR/config.jsonc" ] && [[ " $* " == *" -nodelete "* ]]; then
    info "Config already exists at $CONFIG_DIR/config.jsonc - Preserving it as -nodelete was used"
  else
    if [ -f "$CONFIG_DIR/config.jsonc" ]; then
      warn "Removing old config..."
      rm -f "$CONFIG_DIR/config.jsonc"
    fi
    gen_default_config > "$CONFIG_DIR/config.jsonc"
    ok "Created default config -> $CONFIG_DIR/config.jsonc"
  fi
  ok "Logos directory ready -> $LOGOS_DIR"
}

# ── PATH setup ─────────────────────────────────────────────
setup_path() {
  local shell_rc=""
  case "${SHELL##*/}" in
    bash) shell_rc=".bashrc" ;;
    zsh)  shell_rc=".zshrc" ;;
    fish) shell_rc=".config/fish/config.fish" ;;
  esac
  [ -z "$shell_rc" ] && return

  local rc_file="$HOME/$shell_rc"
  [ ! -f "$rc_file" ] && touch "$rc_file"
  if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' "$rc_file" 2>/dev/null; then
    echo "" >> "$rc_file"
    echo '# Added by fastfetch-config installer' >> "$rc_file"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc_file"
    ok "Added ~/.local/bin to PATH in $shell_rc"
  else
    ok "PATH entry already in $shell_rc"
  fi
}

# ── Main ────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   fastfetch-config $VERSION             ║${NC}"
echo -e "${CYAN}║   by aaronYTDev                       ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
echo ""

detect_distro
install_deps
install_scripts
setup_config "$@"

if command -v chafa &>/dev/null && [ -f "$CONFIG_DIR/config.jsonc" ]; then
  "$BIN_DIR/fastfetch-config" chafa on 2>/dev/null || true
  ok "Chafa auto-enabled"
fi

setup_path

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Installation complete!              ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}Commands:${NC}"
echo -e "    ff                      Run fastfetch with your config"
echo -e "    ff chafa [on|off|raw]   Toggle chafa image rendering"
echo -e "    ff update               Update to latest stable"
echo -e "    ff update -prerelease   Update to latest (including prereleases)"
echo -e "    ff update check         Check for stable updates"
echo -e "    ff update check -prerelease  Check all updates"
echo -e "    ff version              Show version"
echo -e "    ff logo [fit|name]      Set or fit logo to terminal size"
echo -e "    ff backup               Backup current config"
echo -e "    ff backup list          List backups"
echo -e "    ff backup remove <name> Remove a backup"
echo -e "    ff restore <name>       Restore a backup"
echo -e "    ff osname <str>         Set custom OS name"
echo -e "    ff color <n> <c>        Set logo color"
echo -e "    ff variable <cmd>       Manage config variables"
echo -e "    ff tui                  Open interactive TUI menu"
echo -e "    ff reset [name]         Reset config or single variable"
echo -e "    ff status               Show current settings"
echo ""
echo -e "  ${YELLOW}To get started:${NC}"
echo -e "    source ~/.\${shell_rc:-bashrc}     # reload PATH"
echo -e "    ff logo arch         # set a built-in logo"
echo -e "    ff logo fit          # fit logo to terminal"
echo ""
echo "Press enter to exit..."
read
echo ""
