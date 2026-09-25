#!/usr/bin/env bash

# ============================================================
# Kali Restore v 2.4
# Author: jumper-hash
# Run: chmod +x kali-restore.sh && sudo ./kali-restore.sh <username>
# ============================================================

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <username>"
    exit 1
fi

Username="$1"

if [[ $EUID -ne 0 ]]; then
    echo "This script requires root privileges."
    exit 1
fi

if ! id "$Username" >/dev/null 2>&1; then
    echo "User '$Username' does not exist."
    exit 1
fi

USER_HOME="$(getent passwd "$Username" | cut -d: -f6)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="${SCRIPT_DIR}/tools"
STAGE_DIR="${TOOLS_DIR}/staging"
DATE_TAG="$(date +%Y%m%d)"
LOGFILE="${TOOLS_DIR}/kali-restore-${DATE_TAG}.log"

mkdir -p "$TOOLS_DIR" "$STAGE_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[+]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

err() {
    echo -e "${RED}[x]${NC} $1"
}

info() {
    echo -e "${CYAN}[*]${NC} $1"
}


# ============================================================
# APT TOOLS
# ============================================================

install_apt_pkgs() {
    log "Updating package lists..."
    apt update -qq

    local -a apt_pkgs=(
        enum4linux
        smbclient
        smbmap
        impacket-scripts
        bloodhound
        chisel
        ligolo-ng
        ffuf
        gobuster
        dirb
        nikto
        wpscan
        evil-winrm
        hydra
        john
        hashcat
        metasploit-framework
        sqlmap
        burpsuite
        wireshark
        responder
        mitm6
        bettercap
        exploitdb
        jq
        netcat-openbsd
        ncat
        tmux
        rlwrap
        xclip
        bat
        fzf
        pipx
    )

    local success=0
    local fail=0

    for pkg in "${apt_pkgs[@]}"; do
        if apt install -y "$pkg" &>> "$LOGFILE"; then
            ((++success))
        else
            warn "Package '$pkg' not available or failed to install — skipping."
            ((++fail))
        fi
    done

    log "APT packages: $success installed, $fail skipped."
}


# ============================================================
# PIP TOOLS
# ============================================================

install_pip_tools() {
    log "Installing Python tools..."

    python3 -m pip install \
        --break-system-packages \
        bloodhound \
        ldapdomaindump \
        wfuzz \
        arjun \
        2>&1 | tee -a "$LOGFILE" \
        || warn "Some Python packages failed — check the log."

    log "Python tools installation finished."
}


# ============================================================
# KERBRUTE
# ============================================================

install_kerbrute() {
    log "Installing Kerbrute..."

    local kerb_url="https://github.com/ropnop/kerbrute/releases/latest/download/kerbrute_linux_amd64"
    local kerb_fallback="https://github.com/ropnop/kerbrute/releases/download/v1.0.3/kerbrute_linux_amd64"
    local kerb_bin="/usr/local/bin/kerbrute"

    if [[ -x "$kerb_bin" ]]; then
        info "Kerbrute already installed at $kerb_bin."
    else
        if wget -q -O /tmp/kerbrute_linux_amd64 "$kerb_url"; then
            chmod +x /tmp/kerbrute_linux_amd64
            mv /tmp/kerbrute_linux_amd64 "$kerb_bin"
            log "Kerbrute installed."
        elif wget -q -O /tmp/kerbrute_linux_amd64 "$kerb_fallback"; then
            chmod +x /tmp/kerbrute_linux_amd64
            mv /tmp/kerbrute_linux_amd64 "$kerb_bin"
            log "Kerbrute v1.0.3 installed."
        else
            warn "Failed to download Kerbrute."
        fi
    fi

    log "Installing latest NetExec through pipx..."

    if command -v pipx >/dev/null 2>&1; then
        pipx ensurepath >/dev/null 2>&1 || true

        pipx install \
            git+https://github.com/Pennyw0rth/NetExec \
            --force \
            2>&1 | tee -a "$LOGFILE" \
            || warn "NetExec installation failed."
    else
        warn "pipx not available — NetExec skipped."
    fi
}


# ============================================================
# ROCKYOU
# ============================================================

extract_rockyou() {
    local rock="/usr/share/wordlists/rockyou.txt.gz"

    if [[ -f "$rock" ]]; then
        if [[ ! -f "/usr/share/wordlists/rockyou.txt" ]]; then
            log "Extracting rockyou.txt..."
            gunzip -k "$rock"
        else
            info "rockyou.txt already extracted."
        fi
    else
        warn "rockyou.txt.gz not found. Skipping."
    fi
}


# ============================================================
# TOOL REPOSITORIES
# ============================================================

clone_tools() {
    mkdir -p "$TOOLS_DIR" "$STAGE_DIR"
    cd "$TOOLS_DIR"

    if [[ ! -d PEASS-ng/.git ]]; then
        log "Cloning PEASS-ng..."
        git clone --depth 1 \
            https://github.com/peass-ng/PEASS-ng.git
    else
        info "PEASS-ng exists — updating..."
        git -C PEASS-ng pull
    fi

    log "Downloading LinPEAS.sh..."
    wget -q -O linpeas.sh \
        "https://github.com/peass-ng/PEASS-ng/releases/latest/download/linpeas.sh" \
        2>/dev/null \
        && chmod +x linpeas.sh \
        || warn "Failed to download linpeas.sh."

    log "Downloading winPEASx64.exe..."
    wget -q -O winPEASx64.exe \
        "https://github.com/peass-ng/PEASS-ng/releases/latest/download/winPEASx64.exe" \
        2>/dev/null \
        || warn "Failed to download winPEASx64.exe."

    log "Downloading winPEASx86.exe..."
    wget -q -O winPEASx86.exe \
        "https://github.com/peass-ng/PEASS-ng/releases/latest/download/winPEASx86.exe" \
        2>/dev/null \
        || warn "Failed to download winPEASx86.exe."


    if [[ -d /usr/share/seclists ]]; then
        info "SecLists already exists at /usr/share/seclists — skipping clone."
    else
        log "Cloning SecLists..."
        git clone --depth 1 \
            https://github.com/danielmiessler/SecLists.git \
            /usr/share/seclists
    fi


    if [[ ! -d PayloadsAllTheThings/.git ]]; then
        log "Cloning PayloadsAllTheThings..."
        git clone --depth 1 \
            https://github.com/swisskyrepo/PayloadsAllTheThings.git
    else
        info "PayloadsAllTheThings exists — updating..."
        git -C PayloadsAllTheThings pull
    fi


    if [[ ! -d LinEnum/.git ]]; then
        log "Cloning LinEnum..."
        git clone --depth 1 \
            https://github.com/rebootuser/LinEnum.git
    fi


    if [[ ! -d linux-smart-enumeration/.git ]]; then
        log "Cloning linux-smart-enumeration..."
        git clone --depth 1 \
            https://github.com/diego-treitos/linux-smart-enumeration.git
    fi


    if [[ ! -d linux-exploit-suggester/.git ]]; then
        log "Cloning Linux Exploit Suggester..."
        git clone --depth 1 \
            https://github.com/The-Z-Labs/linux-exploit-suggester.git
    else
        info "Linux Exploit Suggester exists — updating..."
        git -C linux-exploit-suggester pull
    fi


    if [[ ! -d pspy/.git ]]; then
        log "Cloning pspy..."
        git clone --depth 1 \
            https://github.com/DominicBreuker/pspy.git
    fi


    if [[ ! -d wesng/.git ]]; then
        log "Cloning WES-NG..."
        git clone --depth 1 \
            https://github.com/bitsadmin/wesng.git
    fi


    if [[ ! -d PowerSploit/.git ]]; then
        log "Cloning PowerSploit..."
        git clone --depth 1 \
            https://github.com/PowerShellMafia/PowerSploit.git
    fi


    if [[ ! -d PKINITtools/.git ]]; then
        log "Cloning PKINITtools..."
        git clone --depth 1 \
            https://github.com/dirkjanm/PKINITtools.git
    fi


    if [[ ! -d fuzzdb/.git ]]; then
        log "Cloning fuzzdb..."
        git clone --depth 1 \
            https://github.com/fuzzdb-project/fuzzdb.git
    fi


    if [[ ! -d IntruderPayloads/.git ]]; then
        log "Cloning IntruderPayloads..."
        git clone --depth 1 \
            https://github.com/1N3/IntruderPayloads.git
    fi


    if [[ ! -d static-binaries/.git ]]; then
        log "Cloning static-binaries..."
        git clone --depth 1 \
            https://github.com/andrew-d/static-binaries.git
    fi


    if [[ ! -d SUID3NUM/.git ]]; then
        log "Cloning SUID3NUM..."
        git clone --depth 1 \
            https://github.com/Anon-Exploiter/SUID3NUM.git
    fi

    chown -R "$Username:$Username" "$TOOLS_DIR"

    log "Tools cloned to: $TOOLS_DIR"
}


# ============================================================
# PSPY BINARIES
# ============================================================

download_static_bins() {
    local psdir="${TOOLS_DIR}/pspy"

    if [[ ! -d "$psdir" ]]; then
        return
    fi

    log "Downloading precompiled pspy binaries..."

    cd "$psdir"

    for arch in amd64 arm64; do
        wget -q -O "pspy64_${arch}" \
            "https://github.com/DominicBreuker/pspy/releases/latest/download/pspy64_${arch}" \
            2>/dev/null \
            || true

        chmod +x "pspy64_${arch}" 2>/dev/null || true
    done

    cd "$SCRIPT_DIR"
}


# ============================================================
# ZSH ALIASES
# ============================================================

configure_shell_aliases() {
    local shell_d="${USER_HOME}/.zshrc.d"
    local commands_file="${shell_d}/commands"
    local shell_rc="${USER_HOME}/.zshrc"

    log "Configuring Zsh aliases..."

    mkdir -p "$shell_d"

    cat > "$commands_file" <<EOF
alias htb='cd ${USER_HOME}/Desktop/htb'
alias hs='sudo nano /etc/hosts'
alias nmap-all='sudo nmap -p- -sV -sC -O -T4'
alias enum4='enum4linux -a'
alias smb='smbclient -L \\\\\\\\'
alias mkdir='mkdir -p'
alias ll='ls -lah'
alias la='ls -A'
alias l='ls -CF'
EOF

    chown "$Username:$Username" "$commands_file"
    chmod 644 "$commands_file"

    if [[ ! -f "$shell_rc" ]]; then
        touch "$shell_rc"
    fi

    if ! grep -qF 'for f in ~/.zshrc.d/*' "$shell_rc"; then
        cat >> "$shell_rc" <<'EOF'

for f in ~/.zshrc.d/*; do
    [[ -f "$f" ]] && source "$f"
done
EOF
    fi

    chown "$Username:$Username" "$shell_rc"

    log "Aliases saved to $commands_file."
}


# ============================================================
# CONVENIENCE SYMLINKS
# ============================================================

post_install_symlinks() {
    log "Creating convenience links..."

    mkdir -p "${TOOLS_DIR}/bin"

    ln -sf \
        "${TOOLS_DIR}/linpeas.sh" \
        "${TOOLS_DIR}/bin/linpeas"

    if [[ -d /usr/share/seclists ]]; then
        ln -sfn \
            /usr/share/seclists \
            "${TOOLS_DIR}/seclists-link"
    fi
}


# ============================================================
# SUMMARY
# ============================================================

summary() {
    cat <<EOF

============================================================
KALI RESTORE COMPLETED
============================================================

User:
  ${Username}

Tools directory:
  ${TOOLS_DIR}

APT tools:
  enum4linux
  smbclient
  smbmap
  impacket-scripts
  bloodhound
  ffuf
  gobuster
  dirb
  nikto
  wpscan
  evil-winrm
  hydra
  john
  hashcat
  metasploit-framework
  sqlmap
  burpsuite
  wireshark
  responder
  mitm6
  bettercap
  exploitdb
  jq
  netcat
  tmux
  rlwrap
  xclip
  bat
  fzf

Python tools:
  bloodhound
  ldapdomaindump
  wfuzz
  arjun

Additional:
  NetExec
  Kerbrute

Repositories:
  PEASS-ng
  SecLists
  PayloadsAllTheThings
  LinEnum
  linux-smart-enumeration
  Linux Exploit Suggester
  pspy
  WES-NG
  PowerSploit
  PKINITtools
  fuzzdb
  IntruderPayloads
  static-binaries
  SUID3NUM

Shell:
  ~/.zshrc.d/commands

Log:
  ${LOGFILE}

============================================================

EOF
}


# ============================================================
# MAIN
# ============================================================

echo ""
info "============================================"
info " Kali Restore v2.4"
info " User      : ${Username}"
info " Tools dir : ${TOOLS_DIR}"
info "============================================"
echo ""

install_apt_pkgs
install_pip_tools
install_kerbrute
extract_rockyou
clone_tools
download_static_bins
configure_shell_aliases
post_install_symlinks
summary

log "Done."
