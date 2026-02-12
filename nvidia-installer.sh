#!/bin/bash
#
# NVIDIA Driver Installer TUI
# A beautiful terminal interface for installing NVIDIA drivers
# Supports: Fedora/RPM-based and Ubuntu-based systems
#

# Colors and styling (using $'...' for proper escape interpretation)
readonly RED=$'\033[0;31m'
readonly GREEN=$'\033[0;32m'
readonly YELLOW=$'\033[1;33m'
readonly BLUE=$'\033[0;34m'
readonly MAGENTA=$'\033[0;35m'
readonly CYAN=$'\033[0;36m'
readonly WHITE=$'\033[1;37m'
readonly BOLD=$'\033[1m'
readonly DIM=$'\033[2m'
readonly NC=$'\033[0m' # No Color

# Box drawing characters
readonly BOX_TL='╭'
readonly BOX_TR='╮'
readonly BOX_BL='╰'
readonly BOX_BR='╯'
readonly BOX_H='─'
readonly BOX_V='│'
readonly BOX_TITLE_L='┤'
readonly BOX_TITLE_R='├'

# Global state
DISTRO=""
DISTRO_VERSION=""
PACKAGE_MANAGER=""
GPU_DETECTED=""
GPU_NAME=""
GPU_IS_LEGACY=false
SECURE_BOOT_ENABLED=false
LUKS_DETECTED=false
DRIVER_INSTALLED=false
DRIVER_VERSION=""
DRIVER_PACKAGE=""
TERM_WIDTH=80
TERM_HEIGHT=24

# Command-line options
AUTO_MODE=false
FORCE_REINSTALL=false
NO_REBOOT=false
AUTO_REBOOT=false
EXIT_CLEAN=false

# ─────────────────────────────────────────────────────────────────────────────
# Argument Parsing
# ─────────────────────────────────────────────────────────────────────────────

show_usage() {
    cat << 'EOF'
NVIDIA Driver Installer TUI

Usage: nvidia-installer.sh [OPTIONS]

Options:
  -y, --auto          Run in automatic mode, accepting all defaults
                      (still prompts for reboot confirmation)
  -f, --force         Force reinstall even if drivers are already installed
  --reboot            Automatically reboot without confirmation after install
                      (use with -y for fully unattended installation)
  --no-reboot         Do not reboot after installation
  -h, --help          Show this help message and exit

Examples:
  sudo ./nvidia-installer.sh              # Interactive mode
  sudo ./nvidia-installer.sh -y           # Auto install, prompts for reboot
  sudo ./nvidia-installer.sh -y --reboot  # Fully unattended with auto reboot
  sudo ./nvidia-installer.sh -y -f        # Force reinstall automatically
  sudo ./nvidia-installer.sh -y --no-reboot  # Auto install, no reboot

EOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--auto|--yes)
                AUTO_MODE=true
                shift
                ;;
            -f|--force)
                FORCE_REINSTALL=true
                shift
                ;;
            --reboot)
                AUTO_REBOOT=true
                shift
                ;;
            --no-reboot)
                NO_REBOOT=true
                shift
                ;;
            -h|--help)
                show_usage
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# TUI Helper Functions
# ─────────────────────────────────────────────────────────────────────────────

get_terminal_size() {
    if command -v tput &>/dev/null; then
        TERM_WIDTH=$(tput cols 2>/dev/null || echo 80)
        TERM_HEIGHT=$(tput lines 2>/dev/null || echo 24)
    fi
    # Ensure minimum width
    [[ $TERM_WIDTH -lt 60 ]] && TERM_WIDTH=60
}

clear_screen() {
    printf $'\033[2J\033[H'
}

hide_cursor() {
    printf $'\033[?25l'
}

show_cursor() {
    printf $'\033[?25h'
}

move_cursor() {
    printf $'\033[%d;%dH' "$1" "$2"
}

# Draw a box with optional title
draw_box() {
    local row=$1
    local col=$2
    local width=$3
    local height=$4
    local title=${5:-}
    local color=${6:-$CYAN}

    # Build horizontal line of correct length
    local hline=""
    local i
    for ((i=0; i<width-2; i++)); do
        hline+="$BOX_H"
    done

    # Top border
    move_cursor "$row" "$col"
    if [[ -n "$title" ]]; then
        local title_len=${#title}
        local total_padding=$((width - title_len - 6))  # 2 corners + 2 title brackets + 2 spaces
        local padding_left=$((total_padding / 2))
        local padding_right=$((total_padding - padding_left))

        # Build left padding
        local left_hline=""
        for ((i=0; i<padding_left; i++)); do
            left_hline+="$BOX_H"
        done

        # Build right padding
        local right_hline=""
        for ((i=0; i<padding_right; i++)); do
            right_hline+="$BOX_H"
        done

        printf "%s%s%s%s %s %s%s%s%s" \
            "$color" "$BOX_TL" "$left_hline" "$BOX_TITLE_L" \
            "$WHITE$BOLD$title$NC$color" \
            "$BOX_TITLE_R" "$right_hline" "$BOX_TR" "$NC"
    else
        printf "%s%s%s%s%s" "$color" "$BOX_TL" "$hline" "$BOX_TR" "$NC"
    fi

    # Sides
    for ((i=1; i<height-1; i++)); do
        move_cursor "$((row+i))" "$col"
        printf "%s%s%s" "$color" "$BOX_V" "$NC"
        move_cursor "$((row+i))" "$((col+width-1))"
        printf "%s%s%s" "$color" "$BOX_V" "$NC"
    done

    # Bottom border
    move_cursor "$((row+height-1))" "$col"
    printf "%s%s%s%s%s" "$color" "$BOX_BL" "$hline" "$BOX_BR" "$NC"
}

# Print centered text
print_centered() {
    local row=$1
    local text=$2
    local color=${3:-$NC}
    local col=$(( (TERM_WIDTH - ${#text}) / 2 ))
    [[ $col -lt 1 ]] && col=1
    move_cursor "$row" "$col"
    printf "${color}%s${NC}" "$text"
}

# Print text at position
print_at() {
    local row=$1
    local col=$2
    local text=$3
    local color=${4:-$NC}
    move_cursor "$row" "$col"
    printf "${color}%s${NC}" "$text"
}

# Animated spinner
spinner() {
    local pid=$1
    local message=$2
    local row=$3
    local col=$4
    local spinchars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0

    while kill -0 "$pid" 2>/dev/null; do
        local char="${spinchars:$i:1}"
        print_at "$row" "$col" "${CYAN}${char}${NC} ${message}"
        i=$(( (i + 1) % ${#spinchars} ))
        sleep 0.1
    done
    wait "$pid"
    return $?
}

# Progress bar
progress_bar() {
    local current=$1
    local total=$2
    local width=${3:-40}
    local row=$4
    local col=$5

    local percent=$(( current * 100 / total ))
    local filled=$(( current * width / total ))
    local empty=$(( width - filled ))

    move_cursor "$row" "$col"
    printf "${CYAN}["
    printf '%*s' "$filled" | tr ' ' '█'
    printf '%*s' "$empty" | tr ' ' '░'
    printf "] ${WHITE}%3d%%${NC}" "$percent"
}

# Show a message box
message_box() {
    local title=$1
    local message=$2
    local type=${3:-info}  # info, success, warning, error
    local hint_text=${4:-"Press any key..."}  # optional custom hint
    local color
    local icon

    case $type in
        success) color=$GREEN; icon="✓" ;;
        warning) color=$YELLOW; icon="⚠" ;;
        error)   color=$RED; icon="✗" ;;
        *)       color=$CYAN; icon="ℹ" ;;
    esac

    # In auto mode, just print to console
    if [[ "$AUTO_MODE" == true ]]; then
        echo -e "${color}${icon}${NC} [${title}] ${message}"
        return 0
    fi

    local box_width=60
    local box_height=7
    local start_row=$(( (TERM_HEIGHT - box_height) / 2 ))
    local start_col=$(( (TERM_WIDTH - box_width) / 2 ))

    draw_box "$start_row" "$start_col" "$box_width" "$box_height" "$title" "$color"

    # Clear inside
    for ((i=1; i<box_height-1; i++)); do
        move_cursor "$((start_row+i))" "$((start_col+1))"
        printf '%*s' "$((box_width-2))" ""
    done

    # Icon and message (centered)
    local full_message="${icon}  ${message}"
    local msg_col=$((start_col + (box_width - ${#full_message}) / 2))
    print_at "$((start_row+2))" "$msg_col" "${color}${icon}${NC}  ${message}"

    # Hint text (centered)
    local hint_col=$((start_col + (box_width - ${#hint_text}) / 2))
    print_at "$((start_row+4))" "$hint_col" "${DIM}${hint_text}${NC}"

    read -rsn1
}

# Yes/No dialog
confirm_dialog() {
    local title=$1
    local message=$2
    local default=${3:-y}  # y or n
    local selected

    # In auto mode, return based on default
    if [[ "$AUTO_MODE" == true ]]; then
        if [[ "$default" == "y" ]]; then
            echo -e "${CYAN}ℹ${NC} [${title}] ${message} ${GREEN}(auto: Yes)${NC}"
            return 0
        else
            echo -e "${CYAN}ℹ${NC} [${title}] ${message} ${YELLOW}(auto: No)${NC}"
            return 1
        fi
    fi

    [[ "$default" == "y" ]] && selected=0 || selected=1

    local box_width=60
    local box_height=9
    local start_row=$(( (TERM_HEIGHT - box_height) / 2 ))
    local start_col=$(( (TERM_WIDTH - box_width) / 2 ))

    while true; do
        draw_box "$start_row" "$start_col" "$box_width" "$box_height" "$title" "$CYAN"

        # Clear inside
        for ((i=1; i<box_height-1; i++)); do
            move_cursor "$((start_row+i))" "$((start_col+1))"
            printf '%*s' "$((box_width-2))" ""
        done

        # Message (centered)
        local msg_col=$((start_col + (box_width - ${#message}) / 2))
        print_at "$((start_row+2))" "$msg_col" "$message"

        # Buttons
        local yes_style no_style
        if [[ $selected -eq 0 ]]; then
            yes_style="${GREEN}${BOLD}[ Yes ]${NC}"
            no_style="${DIM}[ No ]${NC}"
        else
            yes_style="${DIM}[ Yes ]${NC}"
            no_style="${GREEN}${BOLD}[ No ]${NC}"
        fi

        print_at "$((start_row+5))" "$((start_col + box_width/2 - 10))" "$yes_style"
        print_at "$((start_row+5))" "$((start_col + box_width/2 + 2))" "$no_style"
        local hint_text="← → to select, Enter to confirm"
        local hint_col=$((start_col + (box_width - ${#hint_text}) / 2))
        print_at "$((start_row+7))" "$hint_col" "${DIM}${hint_text}${NC}"

        read -rsn1 key
        case "$key" in
            $'\x1b')  # Escape sequence
                read -rsn2 -t 0.1 key
                case "$key" in
                    '[D'|'[C') selected=$(( 1 - selected )) ;;  # Left/Right arrow
                esac
                ;;
            'h'|'l') selected=$(( 1 - selected )) ;;  # vim keys
            '') break ;;  # Enter
        esac
    done

    return $selected
}

# Menu selection
menu_select() {
    local title=$1
    shift
    local options=("$@")
    local selected=0
    local num_options=${#options[@]}

    local box_width=60
    local box_height=$(( num_options + 8 ))
    local start_row=$(( (TERM_HEIGHT - box_height) / 2 ))
    local start_col=$(( (TERM_WIDTH - box_width) / 2 ))

    while true; do
        draw_box "$start_row" "$start_col" "$box_width" "$box_height" "$title" "$CYAN"

        # Clear inside
        for ((i=1; i<box_height-1; i++)); do
            move_cursor "$((start_row+i))" "$((start_col+1))"
            printf '%*s' "$((box_width-2))" ""
        done

        # Options
        for ((i=0; i<num_options; i++)); do
            local row=$((start_row + 3 + i))
            if [[ $i -eq $selected ]]; then
                print_at "$row" "$((start_col+4))" "${CYAN}▸${NC} ${WHITE}${BOLD}${options[$i]}${NC}"
            else
                print_at "$row" "$((start_col+4))" "  ${options[$i]}"
            fi
        done

        print_at "$((start_row + box_height - 2))" "$((start_col+4))" "${DIM}↑↓ to select, Enter to confirm, q to quit${NC}"

        read -rsn1 key
        case "$key" in
            $'\x1b')
                read -rsn2 -t 0.1 key
                case "$key" in
                    '[A') ((selected > 0)) && ((selected--)) ;;  # Up
                    '[B') ((selected < num_options-1)) && ((selected++)) ;;  # Down
                esac
                ;;
            'k') ((selected > 0)) && ((selected--)) ;;  # vim up
            'j') ((selected < num_options-1)) && ((selected++)) ;;  # vim down
            'q') return 255 ;;
            '') break ;;
        esac
    done

    return $selected
}

# ─────────────────────────────────────────────────────────────────────────────
# System Detection Functions
# ─────────────────────────────────────────────────────────────────────────────

detect_distro() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        DISTRO="$ID"
        DISTRO_VERSION="$VERSION_ID"

        case "$ID" in
            fedora|rhel|centos|rocky|alma)
                PACKAGE_MANAGER="dnf"
                ;;
            ubuntu|debian|linuxmint|pop|kubuntu|xubuntu|lubuntu)
                PACKAGE_MANAGER="apt"
                # Normalize ubuntu-based distros
                if [[ "$ID_LIKE" == *"ubuntu"* ]] || [[ "$ID" == "ubuntu" ]] || [[ "$ID" == *"buntu"* ]]; then
                    DISTRO="ubuntu"
                fi
                ;;
            *)
                return 1
                ;;
        esac
        return 0
    fi
    return 1
}

detect_nvidia_gpu() {
    if ! command -v lspci &>/dev/null; then
        return 1
    fi

    local gpu_info
    gpu_info=$(lspci -nn 2>/dev/null | grep -iE 'vga|3d|display' | grep -i nvidia)

    if [[ -n "$gpu_info" ]]; then
        GPU_DETECTED=true
        GPU_NAME=$(echo "$gpu_info" | head -1 | sed 's/.*: //' | cut -d'[' -f1 | xargs)

        # Check for legacy Kepler GPUs (600/700 series)
        local lower_gpu
        lower_gpu=$(echo "$gpu_info" | tr '[:upper:]' '[:lower:]')
        if [[ "$lower_gpu" =~ kepler|gk[0-9]|gt\ ?6[0-9][0-9]|gt\ ?7[0-9][0-9]|gtx\ ?6[0-9][0-9]|gtx\ ?7[0-9][0-9] ]]; then
            GPU_IS_LEGACY=true
        fi
        return 0
    fi

    GPU_DETECTED=false
    return 1
}

detect_secure_boot() {
    if command -v mokutil &>/dev/null; then
        if mokutil --sb-state 2>/dev/null | grep -qi "enabled"; then
            SECURE_BOOT_ENABLED=true
            return 0
        fi
    fi
    SECURE_BOOT_ENABLED=false
    return 1
}

detect_luks() {
    if command -v lsblk &>/dev/null; then
        if lsblk -f 2>/dev/null | grep -qi "luks"; then
            LUKS_DETECTED=true
            return 0
        fi
    fi
    LUKS_DETECTED=false
    return 1
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        return 1
    fi
    return 0
}

detect_existing_driver() {
    DRIVER_INSTALLED=false
    DRIVER_VERSION=""
    DRIVER_PACKAGE=""

    # Try to get driver version from nvidia-smi first (most reliable if loaded)
    if command -v nvidia-smi &>/dev/null; then
        local smi_version
        smi_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
        if [[ -n "$smi_version" ]]; then
            DRIVER_INSTALLED=true
            DRIVER_VERSION="$smi_version"
        fi
    fi

    # Check via modinfo if nvidia module exists
    if [[ "$DRIVER_INSTALLED" != true ]] && command -v modinfo &>/dev/null; then
        local mod_version
        mod_version=$(modinfo -F version nvidia 2>/dev/null)
        if [[ -n "$mod_version" ]]; then
            DRIVER_INSTALLED=true
            DRIVER_VERSION="$mod_version"
        fi
    fi

    # Check installed packages based on distro
    if [[ "$PACKAGE_MANAGER" == "dnf" ]]; then
        # Check for Fedora/RPM packages
        if rpm -q akmod-nvidia &>/dev/null; then
            DRIVER_INSTALLED=true
            DRIVER_PACKAGE="akmod-nvidia"
            if [[ -z "$DRIVER_VERSION" ]]; then
                DRIVER_VERSION=$(rpm -q --qf '%{VERSION}' akmod-nvidia 2>/dev/null)
            fi
        elif rpm -q akmod-nvidia-470xx &>/dev/null; then
            DRIVER_INSTALLED=true
            DRIVER_PACKAGE="akmod-nvidia-470xx"
            if [[ -z "$DRIVER_VERSION" ]]; then
                DRIVER_VERSION=$(rpm -q --qf '%{VERSION}' akmod-nvidia-470xx 2>/dev/null)
            fi
        fi
    elif [[ "$PACKAGE_MANAGER" == "apt" ]]; then
        # Check for Ubuntu/Debian packages
        local nvidia_pkg
        nvidia_pkg=$(dpkg -l 2>/dev/null | grep -E '^ii\s+nvidia-driver-[0-9]+' | awk '{print $2}' | head -1)
        if [[ -n "$nvidia_pkg" ]]; then
            DRIVER_INSTALLED=true
            DRIVER_PACKAGE="$nvidia_pkg"
            if [[ -z "$DRIVER_VERSION" ]]; then
                DRIVER_VERSION=$(dpkg -l "$nvidia_pkg" 2>/dev/null | grep "^ii" | awk '{print $3}')
            fi
        fi
    fi

    [[ "$DRIVER_INSTALLED" == true ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Installation Functions - Fedora/RPM
# ─────────────────────────────────────────────────────────────────────────────

setup_rpmfusion() {
    local row=$1
    local col=$2

    print_at "$row" "$col" "${CYAN}●${NC} Checking RPM Fusion repositories..."

    # Check if already enabled
    if dnf repolist --enabled 2>/dev/null | grep -q "rpmfusion-free"; then
        print_at "$row" "$col" "${GREEN}✓${NC} RPM Fusion Free already enabled          "
    else
        print_at "$row" "$col" "${YELLOW}○${NC} Installing RPM Fusion Free...            "
        if ! dnf install -y --nogpgcheck \
            "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${DISTRO_VERSION}.noarch.rpm" \
            &>/dev/null; then
            print_at "$row" "$col" "${RED}✗${NC} Failed to install RPM Fusion Free        "
            return 1
        fi
        print_at "$row" "$col" "${GREEN}✓${NC} RPM Fusion Free installed                 "
    fi

    ((row++))

    if dnf repolist --enabled 2>/dev/null | grep -q "rpmfusion-nonfree"; then
        print_at "$row" "$col" "${GREEN}✓${NC} RPM Fusion Non-Free already enabled      "
    else
        print_at "$row" "$col" "${YELLOW}○${NC} Installing RPM Fusion Non-Free...        "
        if ! dnf install -y --nogpgcheck \
            "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${DISTRO_VERSION}.noarch.rpm" \
            &>/dev/null; then
            print_at "$row" "$col" "${RED}✗${NC} Failed to install RPM Fusion Non-Free    "
            return 1
        fi
        print_at "$row" "$col" "${GREEN}✓${NC} RPM Fusion Non-Free installed            "
    fi

    return 0
}

install_nvidia_fedora() {
    local row=$1
    local col=$2
    local packages

    if [[ "$GPU_IS_LEGACY" == true ]]; then
        packages=("akmod-nvidia-470xx" "xorg-x11-drv-nvidia-470xx-cuda" "xorg-x11-drv-nvidia-470xx")
        print_at "$row" "$col" "${CYAN}●${NC} Installing NVIDIA 470xx legacy drivers..."
    else
        packages=("akmod-nvidia" "xorg-x11-drv-nvidia-cuda")
        print_at "$row" "$col" "${CYAN}●${NC} Installing NVIDIA drivers..."
    fi

    if dnf install -y "${packages[@]}" &>/dev/null; then
        print_at "$row" "$col" "${GREEN}✓${NC} NVIDIA drivers installed                  "
        return 0
    else
        print_at "$row" "$col" "${RED}✗${NC} Failed to install NVIDIA drivers          "
        return 1
    fi
}

configure_dracut() {
    local row=$1
    local col=$2

    if [[ "$LUKS_DETECTED" != true ]]; then
        print_at "$row" "$col" "${DIM}○${NC} Dracut config skipped (no LUKS detected)  "
        return 0
    fi

    print_at "$row" "$col" "${CYAN}●${NC} Configuring dracut for LUKS...            "

    # Create dracut config
    cat > /etc/dracut.conf.d/nvidia.conf << 'EOF'
add_drivers+=" nvidia nvidia_modeset nvidia_uvm nvidia_drm "
EOF

    print_at "$row" "$col" "${GREEN}✓${NC} Dracut config created                     "
    ((row++))

    print_at "$row" "$col" "${CYAN}●${NC} Regenerating initramfs...                 "

    if dracut --force &>/dev/null; then
        print_at "$row" "$col" "${GREEN}✓${NC} Initramfs regenerated                     "
        return 0
    else
        print_at "$row" "$col" "${RED}✗${NC} Failed to regenerate initramfs            "
        return 1
    fi
}

# Auto mode versions (console output)
setup_rpmfusion_auto() {
    echo -e "${CYAN}●${NC} Checking RPM Fusion repositories..."

    if dnf repolist --enabled 2>/dev/null | grep -q "rpmfusion-free"; then
        echo -e "${GREEN}✓${NC} RPM Fusion Free already enabled"
    else
        echo -e "${YELLOW}○${NC} Installing RPM Fusion Free..."
        if ! dnf install -y --nogpgcheck \
            "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${DISTRO_VERSION}.noarch.rpm" \
            &>/dev/null; then
            echo -e "${RED}✗${NC} Failed to install RPM Fusion Free"
            return 1
        fi
        echo -e "${GREEN}✓${NC} RPM Fusion Free installed"
    fi

    if dnf repolist --enabled 2>/dev/null | grep -q "rpmfusion-nonfree"; then
        echo -e "${GREEN}✓${NC} RPM Fusion Non-Free already enabled"
    else
        echo -e "${YELLOW}○${NC} Installing RPM Fusion Non-Free..."
        if ! dnf install -y --nogpgcheck \
            "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${DISTRO_VERSION}.noarch.rpm" \
            &>/dev/null; then
            echo -e "${RED}✗${NC} Failed to install RPM Fusion Non-Free"
            return 1
        fi
        echo -e "${GREEN}✓${NC} RPM Fusion Non-Free installed"
    fi

    return 0
}

install_nvidia_fedora_auto() {
    local packages

    if [[ "$GPU_IS_LEGACY" == true ]]; then
        packages=("akmod-nvidia-470xx" "xorg-x11-drv-nvidia-470xx-cuda" "xorg-x11-drv-nvidia-470xx")
        echo -e "${CYAN}●${NC} Installing NVIDIA 470xx legacy drivers..."
    else
        packages=("akmod-nvidia" "xorg-x11-drv-nvidia-cuda")
        echo -e "${CYAN}●${NC} Installing NVIDIA drivers..."
    fi

    if dnf install -y "${packages[@]}" &>/dev/null; then
        echo -e "${GREEN}✓${NC} NVIDIA drivers installed"
        return 0
    else
        echo -e "${RED}✗${NC} Failed to install NVIDIA drivers"
        return 1
    fi
}

configure_dracut_auto() {
    if [[ "$LUKS_DETECTED" != true ]]; then
        echo -e "${DIM}○${NC} Dracut config skipped (no LUKS detected)"
        return 0
    fi

    echo -e "${CYAN}●${NC} Configuring dracut for LUKS..."

    cat > /etc/dracut.conf.d/nvidia.conf << 'EOF'
add_drivers+=" nvidia nvidia_modeset nvidia_uvm nvidia_drm "
EOF

    echo -e "${GREEN}✓${NC} Dracut config created"
    echo -e "${CYAN}●${NC} Regenerating initramfs..."

    if dracut --force &>/dev/null; then
        echo -e "${GREEN}✓${NC} Initramfs regenerated"
        return 0
    else
        echo -e "${RED}✗${NC} Failed to regenerate initramfs"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Installation Functions - Ubuntu/Debian
# ─────────────────────────────────────────────────────────────────────────────

install_nvidia_ubuntu() {
    local row=$1
    local col=$2

    print_at "$row" "$col" "${CYAN}●${NC} Updating package lists...                 "

    if ! apt update &>/dev/null; then
        print_at "$row" "$col" "${RED}✗${NC} Failed to update package lists            "
        return 1
    fi
    print_at "$row" "$col" "${GREEN}✓${NC} Package lists updated                     "
    ((row++))

    print_at "$row" "$col" "${CYAN}●${NC} Installing ubuntu-drivers-common...       "

    if ! apt install -y ubuntu-drivers-common &>/dev/null; then
        print_at "$row" "$col" "${RED}✗${NC} Failed to install ubuntu-drivers-common   "
        return 1
    fi
    print_at "$row" "$col" "${GREEN}✓${NC} ubuntu-drivers-common installed           "
    ((row++))

    # Detect recommended driver
    print_at "$row" "$col" "${CYAN}●${NC} Detecting recommended driver...           "

    local recommended
    recommended=$(ubuntu-drivers devices 2>/dev/null | grep "recommended" | awk '{print $3}')

    if [[ -z "$recommended" ]]; then
        # Fallback to nvidia-driver-535 if detection fails
        recommended="nvidia-driver-535"
        print_at "$row" "$col" "${YELLOW}○${NC} Using fallback driver: $recommended       "
    else
        print_at "$row" "$col" "${GREEN}✓${NC} Recommended: $recommended                  "
    fi
    ((row++))

    print_at "$row" "$col" "${CYAN}●${NC} Installing $recommended...                "

    if apt install -y "$recommended" &>/dev/null; then
        print_at "$row" "$col" "${GREEN}✓${NC} $recommended installed                    "
        return 0
    else
        print_at "$row" "$col" "${RED}✗${NC} Failed to install driver                  "
        return 1
    fi
}

configure_initramfs_ubuntu() {
    local row=$1
    local col=$2

    if [[ "$LUKS_DETECTED" != true ]]; then
        print_at "$row" "$col" "${DIM}○${NC} initramfs config skipped (no LUKS)        "
        return 0
    fi

    print_at "$row" "$col" "${CYAN}●${NC} Updating initramfs...                     "

    if update-initramfs -u &>/dev/null; then
        print_at "$row" "$col" "${GREEN}✓${NC} Initramfs updated                         "
        return 0
    else
        print_at "$row" "$col" "${RED}✗${NC} Failed to update initramfs                "
        return 1
    fi
}

# Auto mode versions for Ubuntu
install_nvidia_ubuntu_auto() {
    echo -e "${CYAN}●${NC} Updating package lists..."

    if ! apt update &>/dev/null; then
        echo -e "${RED}✗${NC} Failed to update package lists"
        return 1
    fi
    echo -e "${GREEN}✓${NC} Package lists updated"

    echo -e "${CYAN}●${NC} Installing ubuntu-drivers-common..."

    if ! apt install -y ubuntu-drivers-common &>/dev/null; then
        echo -e "${RED}✗${NC} Failed to install ubuntu-drivers-common"
        return 1
    fi
    echo -e "${GREEN}✓${NC} ubuntu-drivers-common installed"

    echo -e "${CYAN}●${NC} Detecting recommended driver..."

    local recommended
    recommended=$(ubuntu-drivers devices 2>/dev/null | grep "recommended" | awk '{print $3}')

    if [[ -z "$recommended" ]]; then
        recommended="nvidia-driver-535"
        echo -e "${YELLOW}○${NC} Using fallback driver: $recommended"
    else
        echo -e "${GREEN}✓${NC} Recommended: $recommended"
    fi

    echo -e "${CYAN}●${NC} Installing $recommended..."

    if apt install -y "$recommended" &>/dev/null; then
        echo -e "${GREEN}✓${NC} $recommended installed"
        return 0
    else
        echo -e "${RED}✗${NC} Failed to install driver"
        return 1
    fi
}

configure_initramfs_ubuntu_auto() {
    if [[ "$LUKS_DETECTED" != true ]]; then
        echo -e "${DIM}○${NC} initramfs config skipped (no LUKS)"
        return 0
    fi

    echo -e "${CYAN}●${NC} Updating initramfs..."

    if update-initramfs -u &>/dev/null; then
        echo -e "${GREEN}✓${NC} Initramfs updated"
        return 0
    else
        echo -e "${RED}✗${NC} Failed to update initramfs"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Screens
# ─────────────────────────────────────────────────────────────────────────────

show_header() {
    local ascii_art=(
        "  _   ___     _____ ____ ___    _    "
        " | \\ | \\ \\   / /_ _|  _ \\_ _|  / \\   "
        " |  \\| |\\ \\ / / | || | | | |  / _ \\  "
        " | |\\  | \\ V /  | || |_| | | / ___ \\ "
        " |_| \\_|  \\_/  |___|____/___/_/   \\_\\"
        "                                      "
        "     Driver Installer TUI v1.0        "
    )

    local start_row=2
    for ((i=0; i<${#ascii_art[@]}; i++)); do
        print_centered "$((start_row + i))" "${ascii_art[$i]}" "$GREEN"
    done
}

show_welcome_screen() {
    # Skip welcome screen in auto mode
    if [[ "$AUTO_MODE" == true ]]; then
        echo -e "${GREEN}NVIDIA Driver Installer${NC} - Automatic Mode"
        echo ""
        return 0
    fi

    clear_screen
    get_terminal_size

    show_header

    local info_row=12
    draw_box "$info_row" 5 "$((TERM_WIDTH - 10))" 10 "Welcome" "$CYAN"

    print_at "$((info_row + 2))" 8 "This tool will help you install NVIDIA proprietary drivers"
    print_at "$((info_row + 3))" 8 "on your Linux system with an easy-to-use interface."
    print_at "$((info_row + 5))" 8 "${BOLD}Supported Systems:${NC}"
    print_at "$((info_row + 6))" 8 "  ${GREEN}●${NC} Fedora / RHEL-based (DNF)"
    print_at "$((info_row + 7))" 8 "  ${GREEN}●${NC} Ubuntu / Debian-based (APT)"

    print_at "$((info_row + 11))" "$((TERM_WIDTH/2 - 12))" "${DIM}Press any key to continue...${NC}"

    read -rsn1
}

show_system_check_screen() {
    # Auto mode: simple console output
    if [[ "$AUTO_MODE" == true ]]; then
        echo -e "${CYAN}●${NC} Checking system..."

        if ! check_root; then
            echo -e "${RED}✗${NC} Error: Please run this script as root (sudo)"
            return 1
        fi
        echo -e "${GREEN}✓${NC} Running as root"

        if ! detect_distro; then
            echo -e "${RED}✗${NC} Error: Unsupported distribution"
            return 1
        fi
        echo -e "${GREEN}✓${NC} Distribution: ${DISTRO^} ${DISTRO_VERSION}"

        if ! detect_nvidia_gpu; then
            echo -e "${RED}✗${NC} Error: No NVIDIA GPU detected"
            return 1
        fi
        echo -e "${GREEN}✓${NC} GPU: ${GPU_NAME}"
        [[ "$GPU_IS_LEGACY" == true ]] && echo -e "${YELLOW}⚠${NC}  Legacy GPU detected (470xx drivers)"

        detect_secure_boot
        [[ "$SECURE_BOOT_ENABLED" == true ]] && echo -e "${YELLOW}⚠${NC}  Secure Boot: ENABLED" || echo -e "${GREEN}✓${NC} Secure Boot: Disabled"

        detect_luks
        [[ "$LUKS_DETECTED" == true ]] && echo -e "${CYAN}ℹ${NC}  LUKS encryption detected" || echo -e "${GREEN}✓${NC} No LUKS encryption"

        echo ""
        return 0
    fi

    clear_screen
    show_header

    local box_row=11
    local box_width=$((TERM_WIDTH - 10))
    draw_box "$box_row" 5 "$box_width" 14 "System Detection" "$CYAN"

    local row=$((box_row + 2))
    local col=8

    # Check root
    print_at "$row" "$col" "${CYAN}●${NC} Checking privileges..."
    sleep 0.3
    if check_root; then
        print_at "$row" "$col" "${GREEN}✓${NC} Running as root                           "
    else
        print_at "$row" "$col" "${RED}✗${NC} Not running as root                       "
        message_box "Error" "Please run this script as root (sudo)" "error" "Press any key to exit..."
        return 1
    fi
    ((row++))

    # Detect distro
    print_at "$row" "$col" "${CYAN}●${NC} Detecting distribution..."
    sleep 0.3
    if detect_distro; then
        print_at "$row" "$col" "${GREEN}✓${NC} Distribution: ${WHITE}${DISTRO^} ${DISTRO_VERSION}${NC}              "
    else
        print_at "$row" "$col" "${RED}✗${NC} Unsupported distribution                  "
        message_box "Error" "Your distribution is not supported" "error" "Press any key to exit..."
        return 1
    fi
    ((row++))

    # Detect GPU
    print_at "$row" "$col" "${CYAN}●${NC} Detecting NVIDIA GPU..."
    sleep 0.3
    if detect_nvidia_gpu; then
        local display_name="${GPU_NAME:0:35}"
        print_at "$row" "$col" "${GREEN}✓${NC} GPU: ${WHITE}${display_name}${NC}"
        ((row++))
        if [[ "$GPU_IS_LEGACY" == true ]]; then
            print_at "$row" "$col" "${YELLOW}⚠${NC}  Legacy GPU detected (470xx drivers)     "
            ((row++))
        fi
    else
        print_at "$row" "$col" "${RED}✗${NC} No NVIDIA GPU detected                    "
        message_box "Error" "No NVIDIA GPU found in your system" "error" "Press any key to exit..."
        return 1
    fi

    # Check Secure Boot
    print_at "$row" "$col" "${CYAN}●${NC} Checking Secure Boot..."
    sleep 0.3
    detect_secure_boot
    if [[ "$SECURE_BOOT_ENABLED" == true ]]; then
        print_at "$row" "$col" "${YELLOW}⚠${NC}  Secure Boot: ${YELLOW}ENABLED${NC}                    "
    else
        print_at "$row" "$col" "${GREEN}✓${NC} Secure Boot: Disabled                     "
    fi
    ((row++))

    # Check LUKS
    print_at "$row" "$col" "${CYAN}●${NC} Checking disk encryption..."
    sleep 0.3
    detect_luks
    if [[ "$LUKS_DETECTED" == true ]]; then
        print_at "$row" "$col" "${CYAN}ℹ${NC}  LUKS encryption detected                 "
    else
        print_at "$row" "$col" "${GREEN}✓${NC} No LUKS encryption                        "
    fi
    ((row++))

    print_at "$((box_row + 12))" "$((TERM_WIDTH/2 - 12))" "${DIM}Press any key to continue...${NC}"
    read -rsn1

    return 0
}

show_driver_already_installed() {
    # Handle force reinstall flag
    if [[ "$FORCE_REINSTALL" == true ]]; then
        if [[ "$AUTO_MODE" == true ]]; then
            echo -e "${GREEN}✓${NC} NVIDIA drivers already installed (Package: ${DRIVER_PACKAGE:-unknown}, Version: ${DRIVER_VERSION:-unknown})"
            echo -e "${CYAN}ℹ${NC} Force reinstall enabled - proceeding with installation"
            echo ""
        fi
        return 0  # Proceed with reinstall
    fi

    # Auto mode without force: skip reinstall by default
    if [[ "$AUTO_MODE" == true ]]; then
        echo -e "${GREEN}✓${NC} NVIDIA drivers already installed (Package: ${DRIVER_PACKAGE:-unknown}, Version: ${DRIVER_VERSION:-unknown})"
        echo -e "${CYAN}ℹ${NC} Use --force to reinstall"
        return 1  # Don't reinstall
    fi

    clear_screen
    show_header

    local box_row=11
    local box_width=$((TERM_WIDTH - 10))
    draw_box "$box_row" 5 "$box_width" 14 "Driver Already Installed" "$GREEN"

    local row=$((box_row + 2))
    local col=8

    print_at "$row" "$col" "${GREEN}✓${NC} NVIDIA drivers are already installed on this system."
    ((row += 2))

    print_at "$row" "$col" "${BOLD}Current Installation:${NC}"
    ((row++))

    if [[ -n "$DRIVER_PACKAGE" ]]; then
        print_at "$row" "$col" "  ${CYAN}●${NC} Package: ${WHITE}${DRIVER_PACKAGE}${NC}"
        ((row++))
    fi

    if [[ -n "$DRIVER_VERSION" ]]; then
        print_at "$row" "$col" "  ${CYAN}●${NC} Version: ${WHITE}${DRIVER_VERSION}${NC}"
        ((row++))
    fi

    ((row++))
    print_at "$row" "$col" "${DIM}You can reinstall/update if you want to refresh the installation.${NC}"

    if confirm_dialog "Reinstall?" "Do you want to reinstall NVIDIA drivers?" "n"; then
        return 0  # User wants to reinstall
    else
        return 1  # User does not want to reinstall
    fi
}

show_secure_boot_warning() {
    if [[ "$SECURE_BOOT_ENABLED" != true ]]; then
        return 0
    fi

    # Auto mode: just show warning and continue
    if [[ "$AUTO_MODE" == true ]]; then
        echo -e "${YELLOW}⚠${NC}  Secure Boot Warning:"
        echo -e "   After installation, you must enroll the MOK key on reboot."
        echo -e "   A blue 'MOK Management' screen will appear - select 'Enroll MOK'."
        if [[ "$PACKAGE_MANAGER" == "dnf" ]]; then
            echo -e "   You will be prompted to create a password during installation."
        else
            echo -e "   You will be prompted to create a password during installation."
        fi
        echo -e "   ${RED}Without MOK enrollment, the NVIDIA module will NOT load.${NC}"
        echo ""
        return 0  # Continue with installation
    fi

    clear_screen
    show_header

    local box_row=10
    local box_width=$((TERM_WIDTH - 10))
    draw_box "$box_row" 5 "$box_width" 18 "⚠ Secure Boot Warning" "$YELLOW"

    local row=$((box_row + 2))
    local col=8

    print_at "$row" "$col" "${YELLOW}${BOLD}Secure Boot is enabled on your system.${NC}"
    ((row += 2))
    print_at "$row" "$col" "The NVIDIA driver requires a signed kernel module. After installation:"
    ((row += 2))
    print_at "$row" "$col" "${WHITE}${BOLD}On Reboot - MOK Enrollment Required:${NC}"
    ((row++))
    print_at "$row" "$col" "  ${WHITE}1.${NC} A blue ${CYAN}MOK Management${NC} screen will appear"
    ((row++))
    print_at "$row" "$col" "  ${WHITE}2.${NC} Select ${CYAN}Enroll MOK${NC} → ${CYAN}Continue${NC} → ${CYAN}Yes${NC}"
    ((row++))
    print_at "$row" "$col" "  ${WHITE}3.${NC} Enter the password you'll create during installation"
    ((row++))
    print_at "$row" "$col" "  ${WHITE}4.${NC} Select ${CYAN}Reboot${NC}"
    ((row += 2))
    print_at "$row" "$col" "${RED}${BOLD}WARNING:${NC} If you skip MOK enrollment or enter the wrong password,"
    ((row++))
    print_at "$row" "$col" "the NVIDIA driver will ${RED}NOT${NC} load and you'll be stuck with nouveau."
    ((row += 2))
    print_at "$row" "$col" "${DIM}Tip: Choose a simple, memorable password - you only enter it once.${NC}"

    if ! confirm_dialog "Secure Boot" "Do you understand and want to continue?"; then
        return 1
    fi

    return 0
}

show_confirmation_screen() {
    # Auto mode: show what will be installed and proceed
    if [[ "$AUTO_MODE" == true ]]; then
        echo -e "${BOLD}Installing:${NC}"
        if [[ "$PACKAGE_MANAGER" == "dnf" ]]; then
            echo -e "  ${GREEN}●${NC} RPM Fusion repositories (if needed)"
            if [[ "$GPU_IS_LEGACY" == true ]]; then
                echo -e "  ${GREEN}●${NC} akmod-nvidia-470xx (legacy driver)"
                echo -e "  ${GREEN}●${NC} xorg-x11-drv-nvidia-470xx-cuda"
            else
                echo -e "  ${GREEN}●${NC} akmod-nvidia (latest driver)"
                echo -e "  ${GREEN}●${NC} xorg-x11-drv-nvidia-cuda"
            fi
        else
            echo -e "  ${GREEN}●${NC} ubuntu-drivers-common"
            echo -e "  ${GREEN}●${NC} NVIDIA driver (recommended version)"
        fi
        [[ "$LUKS_DETECTED" == true ]] && echo -e "  ${GREEN}●${NC} Initramfs/dracut configuration"
        echo ""
        return 0  # Auto-proceed
    fi

    clear_screen
    show_header

    local box_row=11
    local box_width=$((TERM_WIDTH - 10))
    draw_box "$box_row" 5 "$box_width" 12 "Installation Summary" "$CYAN"

    local row=$((box_row + 2))
    local col=8

    print_at "$row" "$col" "${BOLD}The following will be installed:${NC}"
    ((row += 2))

    if [[ "$PACKAGE_MANAGER" == "dnf" ]]; then
        print_at "$row" "$col" "  ${GREEN}●${NC} RPM Fusion repositories (if needed)"
        ((row++))
        if [[ "$GPU_IS_LEGACY" == true ]]; then
            print_at "$row" "$col" "  ${GREEN}●${NC} akmod-nvidia-470xx (legacy driver)"
            ((row++))
            print_at "$row" "$col" "  ${GREEN}●${NC} xorg-x11-drv-nvidia-470xx-cuda"
        else
            print_at "$row" "$col" "  ${GREEN}●${NC} akmod-nvidia (latest driver)"
            ((row++))
            print_at "$row" "$col" "  ${GREEN}●${NC} xorg-x11-drv-nvidia-cuda"
        fi
    else
        print_at "$row" "$col" "  ${GREEN}●${NC} ubuntu-drivers-common"
        ((row++))
        print_at "$row" "$col" "  ${GREEN}●${NC} NVIDIA driver (recommended version)"
    fi
    ((row++))

    if [[ "$LUKS_DETECTED" == true ]]; then
        print_at "$row" "$col" "  ${GREEN}●${NC} Initramfs/dracut configuration"
    fi

    if ! confirm_dialog "Confirm Installation" "Proceed with NVIDIA driver installation?"; then
        return 1
    fi

    return 0
}

show_installation_screen() {
    local failed=false

    # Auto mode uses simplified console output
    if [[ "$AUTO_MODE" == true ]]; then
        echo -e "${CYAN}●${NC} Starting installation..."
        echo ""

        if [[ "$PACKAGE_MANAGER" == "dnf" ]]; then
            if ! setup_rpmfusion_auto; then
                failed=true
            fi

            if [[ "$failed" != true ]]; then
                if ! install_nvidia_fedora_auto; then
                    failed=true
                fi
            fi

            if [[ "$failed" != true ]]; then
                if ! configure_dracut_auto; then
                    failed=true
                fi
            fi
        else
            if ! install_nvidia_ubuntu_auto; then
                failed=true
            fi

            if [[ "$failed" != true ]]; then
                if ! configure_initramfs_ubuntu_auto; then
                    failed=true
                fi
            fi
        fi

        echo ""
        if [[ "$failed" == true ]]; then
            echo -e "${RED}✗${NC} Installation failed!"
            return 1
        else
            echo -e "${GREEN}✓${NC} Installation completed successfully!"
            return 0
        fi
    fi

    # Interactive TUI mode
    clear_screen
    show_header

    local box_row=11
    local box_width=$((TERM_WIDTH - 10))
    draw_box "$box_row" 5 "$box_width" 14 "Installing" "$CYAN"

    local row=$((box_row + 2))
    local col=8

    if [[ "$PACKAGE_MANAGER" == "dnf" ]]; then
        # Fedora installation
        if ! setup_rpmfusion "$row" "$col"; then
            failed=true
        fi
        ((row += 3))

        if [[ "$failed" != true ]]; then
            if ! install_nvidia_fedora "$row" "$col"; then
                failed=true
            fi
        fi
        ((row += 2))

        if [[ "$failed" != true ]]; then
            if ! configure_dracut "$row" "$col"; then
                failed=true
            fi
        fi
    else
        # Ubuntu installation
        if ! install_nvidia_ubuntu "$row" "$col"; then
            failed=true
        fi
        ((row += 5))

        if [[ "$failed" != true ]]; then
            if ! configure_initramfs_ubuntu "$row" "$col"; then
                failed=true
            fi
        fi
    fi

    ((row += 3))

    if [[ "$failed" == true ]]; then
        print_at "$row" "$col" "${RED}${BOLD}Installation failed!${NC}"
        message_box "Error" "Installation encountered errors" "error" "Press any key to exit..."
        return 1
    else
        print_at "$row" "$col" "${GREEN}${BOLD}Installation completed successfully!${NC}"
        sleep 1
        return 0
    fi
}

show_completion_screen() {
    # Auto mode: simple console output
    if [[ "$AUTO_MODE" == true ]]; then
        echo ""
        echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}${BOLD}  NVIDIA drivers have been installed successfully!${NC}"
        echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
        echo ""

        if [[ "$SECURE_BOOT_ENABLED" == true ]]; then
            echo -e "${YELLOW}${BOLD}⚠ SECURE BOOT - ACTION REQUIRED:${NC}"
            echo -e "  On reboot, a blue 'MOK Management' screen will appear."
            echo -e "  Select: ${CYAN}Enroll MOK${NC} → ${CYAN}Continue${NC} → ${CYAN}Yes${NC} → Enter password → ${CYAN}Reboot${NC}"
            echo ""
        fi

        if [[ "$LUKS_DETECTED" == true ]]; then
            echo -e "${CYAN}ℹ LUKS Encryption:${NC}"
            if [[ "$PACKAGE_MANAGER" == "dnf" ]]; then
                echo -e "  Dracut configured: NVIDIA modules added to initramfs"
            else
                echo -e "  Initramfs updated with NVIDIA modules"
            fi
            echo ""
        fi

        echo -e "${BOLD}Next steps:${NC}"
        echo -e "  1. Reboot your system"
        if [[ "$SECURE_BOOT_ENABLED" == true ]]; then
            echo -e "  2. ${YELLOW}Complete MOK enrollment (REQUIRED)${NC}"
            echo -e "  3. Verify with: ${CYAN}nvidia-smi${NC}"
        else
            echo -e "  2. Verify with: ${CYAN}nvidia-smi${NC}"
        fi
        echo ""

        # Handle reboot in auto mode
        if [[ "$NO_REBOOT" == true ]]; then
            echo -e "${DIM}Reboot skipped (--no-reboot flag set)${NC}"
        elif [[ "$AUTO_REBOOT" == true ]]; then
            echo -e "${YELLOW}Rebooting in 5 seconds...${NC}"
            sleep 5
            reboot
        else
            # Auto mode but no --reboot flag: prompt for confirmation
            echo -e -n "Would you like to reboot now? [y/N]: "
            read -r response
            if [[ "$response" =~ ^[Yy]$ ]]; then
                echo -e "${YELLOW}Rebooting in 3 seconds...${NC}"
                sleep 3
                reboot
            else
                echo -e "${DIM}Reboot skipped. Please reboot manually.${NC}"
            fi
        fi
        return 0
    fi

    clear_screen
    show_header

    # Calculate box height based on what needs to be shown
    local box_height=14
    [[ "$SECURE_BOOT_ENABLED" == true ]] && ((box_height += 4))
    [[ "$LUKS_DETECTED" == true ]] && ((box_height += 2))

    local box_row=10
    local box_width=$((TERM_WIDTH - 10))
    draw_box "$box_row" 5 "$box_width" "$box_height" "✓ Installation Complete" "$GREEN"

    local row=$((box_row + 2))
    local col=8

    print_at "$row" "$col" "${GREEN}${BOLD}NVIDIA drivers have been installed successfully!${NC}"
    ((row += 2))

    # Secure Boot instructions
    if [[ "$SECURE_BOOT_ENABLED" == true ]]; then
        print_at "$row" "$col" "${YELLOW}${BOLD}⚠ SECURE BOOT - ACTION REQUIRED ON REBOOT:${NC}"
        ((row++))
        print_at "$row" "$col" "  Select: ${CYAN}Enroll MOK${NC} → ${CYAN}Continue${NC} → ${CYAN}Yes${NC} → Enter password → ${CYAN}Reboot${NC}"
        ((row++))
        print_at "$row" "$col" "  ${DIM}If you miss this step, run: ${NC}${CYAN}sudo mokutil --import /var/lib/dkms/mok.pub${NC}"
        ((row += 2))
    fi

    # LUKS info
    if [[ "$LUKS_DETECTED" == true ]]; then
        print_at "$row" "$col" "${CYAN}ℹ LUKS:${NC} NVIDIA modules added to initramfs for early boot support"
        ((row += 2))
    fi

    print_at "$row" "$col" "${BOLD}Next steps:${NC}"
    ((row++))
    print_at "$row" "$col" "  ${WHITE}1.${NC} Reboot your system"
    ((row++))

    if [[ "$SECURE_BOOT_ENABLED" == true ]]; then
        print_at "$row" "$col" "  ${WHITE}2.${NC} ${YELLOW}Complete MOK enrollment at boot screen${NC}"
        ((row++))
        print_at "$row" "$col" "  ${WHITE}3.${NC} Verify with: ${CYAN}nvidia-smi${NC}"
    else
        print_at "$row" "$col" "  ${WHITE}2.${NC} Verify with: ${CYAN}nvidia-smi${NC}"
    fi
    ((row += 2))

    print_at "$row" "$col" "${DIM}The NVIDIA driver will be active after reboot.${NC}"

    # Handle --no-reboot flag
    if [[ "$NO_REBOOT" == true ]]; then
        message_box "Complete" "Reboot manually when ready" "info"
        return 0
    fi

    if confirm_dialog "Reboot" "Would you like to reboot now?"; then
        clear_screen
        print_centered 12 "Rebooting in 3 seconds..." "$YELLOW"
        sleep 3
        reboot
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Entry Point
# ─────────────────────────────────────────────────────────────────────────────

cleanup() {
    show_cursor
    printf "${NC}"
    # Only clear screen in interactive mode and on success
    [[ "$AUTO_MODE" != true ]] && [[ "$EXIT_CLEAN" == true ]] && clear_screen
}

main() {
    # Parse command-line arguments
    parse_args "$@"

    # Early root check - before TUI setup
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error:${NC} This script must be run as root."
        echo -e "Please run: ${CYAN}sudo $0${NC}"
        exit 1
    fi

    # Setup cleanup and signal handling
    if [[ "$AUTO_MODE" != true ]]; then
        trap cleanup EXIT
        trap 'cleanup; exit 130' INT
        hide_cursor
        get_terminal_size
    else
        trap 'printf "${NC}"; exit 130' INT
    fi

    # Welcome screen
    show_welcome_screen

    # System checks
    if ! show_system_check_screen; then
        [[ "$AUTO_MODE" != true ]] && show_cursor
        exit 1
    fi

    # Check if drivers are already installed
    detect_existing_driver
    if [[ "$DRIVER_INSTALLED" == true ]]; then
        if ! show_driver_already_installed; then
            message_box "No Changes" "Existing installation kept" "info" "Press any key to exit..."
            EXIT_CLEAN=true
            [[ "$AUTO_MODE" != true ]] && show_cursor
            exit 0
        fi
    fi

    # Secure boot warning
    if ! show_secure_boot_warning; then
        message_box "Cancelled" "Installation cancelled by user" "warning" "Press any key to exit..."
        EXIT_CLEAN=true
        [[ "$AUTO_MODE" != true ]] && show_cursor
        exit 0
    fi

    # Confirmation
    if ! show_confirmation_screen; then
        message_box "Cancelled" "Installation cancelled by user" "warning" "Press any key to exit..."
        EXIT_CLEAN=true
        [[ "$AUTO_MODE" != true ]] && show_cursor
        exit 0
    fi

    # Installation
    if ! show_installation_screen; then
        [[ "$AUTO_MODE" != true ]] && show_cursor
        exit 1
    fi

    # Completion
    show_completion_screen

    EXIT_CLEAN=true
    [[ "$AUTO_MODE" != true ]] && show_cursor
    exit 0
}

# Run main
main "$@"
