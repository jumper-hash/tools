```bash
#!/usr/bin/env bash

# ============================================================
# Kali Restore
# Author: jumper-hash
#
# Run:
#   chmod +x kali-restore.sh
#   sudo ./kali-restore.sh <username>
#
# This script installs the pentesting layer globally.
# Base system, KDE, XRDP, Docker and desktop themes are handled
# by the separate upgrade.sh script.
# ============================================================

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <username>"
    exit 1
fi

Username="$1"

if [[ $EUID -ne 0 ]]; then
    echo "This script requires root privileges."
    exit 1
fi

if ! [[ "$Username" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]; then
    echo "Invalid username: $Username"
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
APT_FAILED="${TOOLS_DIR}/apt-failed-${DATE_TAG}.txt"
MISSING_TOOLS="${TOOLS_DIR}/missing-${DATE_TAG}.txt"

mkdir -p \
    "$TOOLS_DIR" \
    "$STAGE_DIR"

touch \
    "$LOGFILE" \
    "$APT_FAILED" \
    "$MISSING_TOOLS"

chown \
    "$Username:$Username" \
    "$TOOLS_DIR" \
    "$STAGE_DIR" \
    "$LOGFILE" \
    "$APT_FAILED" \
    "$MISSING_TOOLS"


# ============================================================
# COLORS
# ============================================================

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

    apt-get update -qq


    local -a apt_pkgs=(

        # =========================
        # Network reconnaissance
        # =========================
        nmap
        ncat
        netcat-openbsd
        socat
        masscan
        hping3
        fping
        arp-scan
        traceroute
        mtr-tiny
        dnsutils
        whois
        sslscan
        openssl
        gnutls-bin
        swaks
        nbtscan
        onesixtyone
        snmp
        snmp-mibs-downloader
        sipvicious

        # =========================
        # SMB / Windows / AD
        # =========================
        smbclient
        samba-common-bin
        smbmap
        enum4linux
        enum4linux-ng
        impacket-scripts
        bloodhound
        ldap-utils
        rpcbind
        krb5-user
        krb5-config
        sshpass
        evil-winrm

        # =========================
        # Web reconnaissance
        # =========================
        ffuf
        gobuster
        feroxbuster
        dirb
        dirsearch
        nikto
        wpscan
        whatweb
        sqlmap
        commix
        zaproxy

        # =========================
        # Password attacks / cracking
        # =========================
        hydra
        hydra-gtk
        john
        hashcat
        crunch
        hashid
        hcxtools
        hcxdumptool
        patator

        # =========================
        # Exploitation
        # =========================
        metasploit-framework
        exploitdb

        # =========================
        # MITM / network attacks
        # =========================
        responder
        mitm6
        bettercap
        ettercap-text-only
        ettercap-graphical
        dsniff
        mitmproxy

        # =========================
        # Proxying / tunneling
        # =========================
        proxychains4
        torsocks
        chisel
        ligolo-ng
        sshuttle
        wireguard-tools
        openvpn

        # =========================
        # Packet capture / analysis
        # =========================
        tcpdump
        wireshark
        tshark
        termshark

        # =========================
        # Terminal / workflow
        # =========================
        tmux
        rlwrap
        xclip
        xsel
        fzf
        bat
        ripgrep
        fd-find
        tree
        less
        vim
        nano

        # =========================
        # Python environment
        # =========================
        python3
        python3-pip
        python3-venv
        python3-dev
        python3-setuptools
        python3-wheel

        # =========================
        # Build environment
        # =========================
        build-essential
        gcc
        g++
        gcc-multilib
        make
        cmake
        pkg-config
        libssl-dev
        libffi-dev
        libxml2-dev
        libxslt1-dev
        zlib1g-dev

        # =========================
        # Binary exploitation
        # =========================
        gdb
        gdb-multiarch
        gdbserver
        binutils
        binutils-multiarch
        patchelf
        checksec
        strace
        ltrace
        lsof
        procps
        psmisc

        # =========================
        # Binary / file analysis
        # =========================
        file
        p7zip-full
        unzip
        zip
        xxd
        libimage-exiftool-perl
        binwalk
        foremost
        sleuthkit
        testdisk
        yara

        # =========================
        # Data processing
        # =========================
        jq
        yq
        sqlite3

        # =========================
        # Remote access / transfer
        # =========================
        openssh-client
        rsync
        curl
        wget
        ftp
        telnet

        # =========================
        # Database clients
        # =========================
        default-mysql-client
        postgresql-client
        redis-tools

        # =========================
        # Web / scripting runtimes
        # =========================
        nodejs
        npm
        ruby
        ruby-dev
        php-cli
        php-curl
        php-xml
        php-mbstring

        # =========================
        # Cloud / misc.
        # =========================
        awscli

        # =========================
        # Go toolchain
        # =========================
        golang-go

        # =========================
        # Reverse engineering
        # =========================
        ghidra
        radare2

        # =========================
        # Wordlists
        # =========================
        wordlists
    )


    local success=0
    local fail=0


    : > "$APT_FAILED"


    for pkg in "${apt_pkgs[@]}"; do

        if apt-get install -y "$pkg" >>"$LOGFILE" 2>&1; then

            ((++success))

        else

            warn \
                "Package '$pkg' unavailable or failed to install — skipping."

            printf '%s\n' \
                "$pkg" \
                >> "$APT_FAILED"

            ((++fail))

        fi

    done


    log \
        "APT packages: $success installed, $fail skipped."

}


# ============================================================
# GLOBAL PYTHON TOOLS
# ============================================================

install_pip_tools() {

    log "Installing global Python security tools..."


    local -a pip_pkgs=(

        # =========================
        # Active Directory
        # =========================
        bloodhound
        ldapdomaindump
        certipy-ad
        bloodyAD
        pywhisker
        adidnsdump
        minikerberos

        # =========================
        # LDAP / DNS / Kerberos
        # =========================
        ldap3
        dnspython

        # =========================
        # Web / fuzzing
        # =========================
        wfuzz
        arjun
        requests
        beautifulsoup4

        # =========================
        # Exploit development
        # =========================
        pwntools
        ROPGadget

        # =========================
        # SMB / Windows
        # =========================
        impacket
    )


    if python3 -m pip install \
        --break-system-packages \
        "${pip_pkgs[@]}" \
        >> "$LOGFILE" 2>&1; then

        log "Python security tools installed."

    else

        warn \
            "Some Python packages failed — check $LOGFILE."

    fi

}


# ============================================================
# NETEXEC
# ============================================================

install_netexec() {

    log "Installing NetExec globally..."


    if python3 -m pip install \
        --break-system-packages \
        "git+https://github.com/Pennyw0rth/NetExec.git" \
        >> "$LOGFILE" 2>&1; then

        log "NetExec installed globally."

    else

        warn \
            "NetExec installation failed — check $LOGFILE."

    fi

}


# ============================================================
# KERBRUTE
# ============================================================

install_kerbrute() {

    log "Installing Kerbrute..."


    local architecture
    local asset
    local temporary


    architecture="$(dpkg --print-architecture)"


    case "$architecture" in

        amd64)
            asset="kerbrute_linux_amd64"
            ;;

        arm64)
            asset="kerbrute_linux_arm64"
            ;;

        *)
            warn \
                "Kerbrute is not configured for architecture: $architecture"

            return
            ;;

    esac


    if [[ -x /usr/local/bin/kerbrute ]]; then

        info \
            "Kerbrute already installed."

        return

    fi


    temporary="$(mktemp)"


    if curl -fsSL \
        --retry 3 \
        -o "$temporary" \
        "https://github.com/ropnop/kerbrute/releases/latest/download/$asset"; then

        install \
            -m 0755 \
            "$temporary" \
            /usr/local/bin/kerbrute

        rm -f \
            "$temporary"

        log "Kerbrute installed."

    else

        rm -f \
            "$temporary"

        warn \
            "Kerbrute download failed."

    fi

}


# ============================================================
# EVIL-WINRM FALLBACK
# ============================================================

install_evil_winrm_fallback() {

    if command -v evil-winrm >/dev/null 2>&1; then

        info "Evil-WinRM is already available."

        return

    fi


    log "Trying Evil-WinRM RubyGems fallback..."


    if ! command -v gem >/dev/null 2>&1; then

        warn \
            "RubyGems is unavailable — Evil-WinRM fallback skipped."

        return

    fi


    if gem install \
        evil-winrm \
        --no-document \
        >> "$LOGFILE" 2>&1; then

        log \
            "Evil-WinRM installed through RubyGems."

    else

        warn \
            "Evil-WinRM fallback installation failed."

    fi

}


# ============================================================
# GO TOOLS
# ============================================================

install_go_tools() {

    if ! command -v go >/dev/null 2>&1; then

        warn \
            "Go is unavailable — skipping Go-based tools."

        return

    fi


    log \
        "Installing Go-based reconnaissance tools globally..."


    local -a go_tools=(

        # ProjectDiscovery
        github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
        github.com/projectdiscovery/httpx/cmd/httpx@latest
        github.com/projectdiscovery/dnsx/cmd/dnsx@latest
        github.com/projectdiscovery/naabu/v2/cmd/naabu@latest
        github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
        github.com/projectdiscovery/katana/cmd/katana@latest

        # Tomnomnom ecosystem
        github.com/tomnomnom/waybackurls@latest
        github.com/tomnomnom/anew@latest
        github.com/tomnomnom/qsreplace@latest

        # Other enumeration
        github.com/lc/gau/v2/cmd/gau@latest
        github.com/hakluke/hakrawler@latest
    )


    local tool


    for tool in "${go_tools[@]}"; do

        if GOBIN=/usr/local/bin \
            go install "$tool" \
            >> "$LOGFILE" 2>&1; then

            info \
                "Installed $(basename "${tool%@*}")."

        else

            warn \
                "Failed to install $tool."

        fi

    done

}


# ============================================================
# ROCKYOU
# ============================================================

install_wordlists() {

    local rockyou_gz="/usr/share/wordlists/rockyou.txt.gz"
    local rockyou_txt="/usr/share/wordlists/rockyou.txt"


    if [[ -f "$rockyou_txt" ]]; then

        info \
            "rockyou.txt already exists."

        return

    fi


    if [[ -f "$rockyou_gz" ]]; then

        log \
            "Extracting rockyou.txt..."

        gunzip -k \
            "$rockyou_gz"

    else

        warn \
            "rockyou.txt.gz not available in the configured repositories."

    fi

}


# ============================================================
# REPOSITORY HELPER
# ============================================================

clone_repo() {

    local url="$1"
    local destination="$2"


    if [[ -d "$destination/.git" ]]; then

        info \
            "$(basename "$destination") already exists — updating..."

        git -C "$destination" pull --ff-only \
            >> "$LOGFILE" 2>&1 \
            || warn \
                "Failed to update $destination."

    else

        log \
            "Cloning $(basename "$destination")..."

        rm -rf \
            "$destination"

        git clone \
            --depth 1 \
            "$url" \
            "$destination" \
            >> "$LOGFILE" 2>&1 \
            || warn \
                "Failed to clone $url."

    fi

}


# ============================================================
# TOOL REPOSITORIES
# ============================================================

clone_tools() {

    log \
        "Preparing pentesting repositories..."


    # =========================
    # Privilege escalation
    # =========================

    clone_repo \
        "https://github.com/peass-ng/PEASS-ng.git" \
        "$TOOLS_DIR/PEASS-ng"


    clone_repo \
        "https://github.com/rebootuser/LinEnum.git" \
        "$TOOLS_DIR/LinEnum"


    clone_repo \
        "https://github.com/diego-treitos/linux-smart-enumeration.git" \
        "$TOOLS_DIR/linux-smart-enumeration"


    clone_repo \
        "https://github.com/The-Z-Labs/linux-exploit-suggester.git" \
        "$TOOLS_DIR/linux_
```
