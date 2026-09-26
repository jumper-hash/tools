#!/usr/bin/env bash

# Debian 13 Pentest / Kali-like Tool Restore
# Installs a broad pentesting toolkit on Debian 13.
# Uses Debian APT packages where available.
# Uses global pipx environments for Python CLI applications.
# Uses isolated virtual environments as fallback for Python tools.
# Does not add Kali repositories.
# Does not run apt autoremove.
# Does not run apt purge.

set -uo pipefail

export DEBIAN_FRONTEND=noninteractive
export PATH="/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PYTHONDONTWRITEBYTECODE=1

# ---------------------------------------------------------------------------
# Arguments and paths
# ---------------------------------------------------------------------------

if [[ "${EUID}" -ne 0 ]]; then
    echo "This script requires root privileges."
    echo "Run: sudo ./upgrade.sh <username>"
    exit 1
fi

USERNAME="${1:-}"

if [[ -z "${USERNAME}" ]]; then
    echo "Usage: $0 <username>"
    exit 1
fi

if ! id "${USERNAME}" >/dev/null 2>&1; then
    echo "User does not exist: ${USERNAME}"
    exit 1
fi

USER_HOME="$(getent passwd "${USERNAME}" | cut -d: -f6)"

if [[ -z "${USER_HOME}" || ! -d "${USER_HOME}" ]]; then
    echo "Could not determine home directory for ${USERNAME}"
    exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="${SCRIPT_DIR}/tools"

mkdir -p "${TOOLS_DIR}"

STAMP="$(date +%Y%m%d-%H%M%S)"

LOG_FILE="${TOOLS_DIR}/kali-restore-${STAMP}.log"
APT_SKIPPED="${TOOLS_DIR}/apt-skipped-${STAMP}.txt"
PYTHON_SKIPPED="${TOOLS_DIR}/pip-skipped-${STAMP}.txt"
OTHER_SKIPPED="${TOOLS_DIR}/other-skipped-${STAMP}.txt"

touch "${APT_SKIPPED}" "${PYTHON_SKIPPED}" "${OTHER_SKIPPED}"

exec > >(tee -a "${LOG_FILE}") 2>&1

FAILED_ITEMS=()
INSTALLED_ITEMS=()
SKIPPED_ITEMS=()

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------

info() {
    echo "[*] $*"
}

ok() {
    echo "[+] $*"
}

warn() {
    echo "[!] $*"
}

fail_item() {
    FAILED_ITEMS+=("$1")
    echo "[!] FAILED: $1"
}

installed() {
    INSTALLED_ITEMS+=("$1")
    echo "[+] $1"
}

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------

echo
echo "============================================================"
echo "  Debian 13 Pentest / Kali-like Restore"
echo "============================================================"
echo
echo "User       : ${USERNAME}"
echo "Home       : ${USER_HOME}"
echo "Script dir : ${SCRIPT_DIR}"
echo "Tools dir  : ${TOOLS_DIR}"
echo "Log        : ${LOG_FILE}"
echo

# ---------------------------------------------------------------------------
# Basic dependencies
# ---------------------------------------------------------------------------

info "Installing base tooling required by the restore process..."

BASE_PACKAGES=(
    ca-certificates
    curl
    wget
    git
    gnupg
    unzip
    zip
    tar
    gzip
    xz-utils
    jq
    file
    procps
    psmisc
)

apt-get update

apt-get install -y "${BASE_PACKAGES[@]}" || {
    warn "Some base packages could not be installed."
}

# ---------------------------------------------------------------------------
# Debian non-free / contrib
# ---------------------------------------------------------------------------

enable_nonfree() {
    local file

    for file in \
        /etc/apt/sources.list.d/debian.sources \
        /etc/apt/sources.list.d/debian-security.sources
    do
        if [[ -f "${file}" ]]; then
            sed -i \
                -E 's/^Components: .*/Components: main contrib non-free non-free-firmware/' \
                "${file}"
        fi
    done
}

info "Enabling Debian contrib/non-free components where supported..."
enable_nonfree

apt-get update || warn "APT update returned an error."

# ---------------------------------------------------------------------------
# APT package helpers
# ---------------------------------------------------------------------------

apt_available() {
    local package="$1"
    local candidate

    candidate="$(apt-cache policy "${package}" 2>/dev/null |
        awk '/Candidate:/ {print $2; exit}')"

    [[ -n "${candidate}" && "${candidate}" != "(none)" ]]
}

install_apt_group() {
    local description="$1"
    shift

    local -a available=()
    local package

    echo
    info "Checking APT packages: ${description}"

    for package in "$@"; do
        if apt_available "${package}"; then
            echo "[+] APT available: ${package}"
            available+=("${package}")
        else
            echo "[!] APT unavailable: ${package}"
            printf '%s\n' "${package}" >> "${APT_SKIPPED}"
        fi
    done

    if [[ "${#available[@]}" -eq 0 ]]; then
        warn "No packages available for category: ${description}"
        return
    fi

    if apt-get install -y "${available[@]}"; then
        ok "APT category installed: ${description}"
        return
    fi

    warn "Bulk APT installation failed. Retrying packages individually."

    for package in "${available[@]}"; do
        if apt-get install -y "${package}"; then
            installed "APT: ${package}"
        else
            fail_item "APT: ${package}"
            printf '%s\n' "${package}" >> "${APT_SKIPPED}"
        fi
    done
}

# ---------------------------------------------------------------------------
# Network reconnaissance
# ---------------------------------------------------------------------------

install_apt_group "Network reconnaissance" \
    nmap \
    ncat \
    netcat-openbsd \
    socat \
    masscan \
    hping3 \
    fping \
    arp-scan \
    traceroute \
    mtr-tiny \
    whois \
    sslscan \
    openssl \
    gnutls-bin \
    swaks \
    nbtscan \
    onesixtyone \
    snmp \
    ncrack \
    ike-scan \
    p0f \
    amass \
    dnsenum \
    dnsrecon \
    fierce \
    subfinder \
    assetfinder \
    httpx-toolkit \
    nuclei

# ---------------------------------------------------------------------------
# SMB / Windows / Active Directory
# ---------------------------------------------------------------------------

install_apt_group "SMB / Windows / Active Directory" \
    smbclient \
    samba-common-bin \
    smbmap \
    ldap-utils \
    rpcbind \
    krb5-user \
    krb5-config \
    sshpass \
    python3-impacket \
    python3-ldap3 \
    python3-yaml \
    enum4linux \
    enum4linux-ng

# ---------------------------------------------------------------------------
# Web reconnaissance
# ---------------------------------------------------------------------------

install_apt_group "Web reconnaissance" \
    ffuf \
    gobuster \
    dirb \
    dirsearch \
    sqlmap \
    whatweb \
    nikto \
    wfuzz \
    feroxbuster \
    zaproxy \
    httprobe

# ---------------------------------------------------------------------------
# Password attacks
# ---------------------------------------------------------------------------

install_apt_group "Password attacks" \
    hydra \
    john \
    hashcat \
    crunch \
    hashid \
    hcxtools \
    hcxdumptool \
    patator

# ---------------------------------------------------------------------------
# MITM and traffic manipulation
# ---------------------------------------------------------------------------

install_apt_group "MITM / traffic manipulation" \
    bettercap \
    bettercap-caplets \
    ettercap-text-only \
    ettercap-graphical \
    dsniff

# ---------------------------------------------------------------------------
# Proxying and tunneling
# ---------------------------------------------------------------------------

install_apt_group "Proxying / tunneling" \
    proxychains4 \
    torsocks \
    sshuttle \
    wireguard-tools \
    openvpn \
    stunnel4

# ---------------------------------------------------------------------------
# Packet capture and analysis
# ---------------------------------------------------------------------------

install_apt_group "Packet capture / analysis" \
    tcpdump \
    wireshark \
    tshark \
    termshark \
    ngrep

# ---------------------------------------------------------------------------
# Terminal and workflow
# ---------------------------------------------------------------------------

install_apt_group "Terminal workflow" \
    tmux \
    rlwrap \
    xclip \
    xsel \
    fzf \
    bat \
    ripgrep \
    fd-find \
    tree \
    less \
    vim \
    nano \
    jq \
    yq \
    sqlite3

# ---------------------------------------------------------------------------
# Python and development
# ---------------------------------------------------------------------------

install_apt_group "Python / development" \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    python3-full \
    python3-setuptools \
    python3-wheel \
    pipx \
    build-essential \
    gcc \
    g++ \
    gcc-multilib \
    make \
    cmake \
    pkg-config \
    libssl-dev \
    libffi-dev \
    libxml2-dev \
    libxslt1-dev \
    zlib1g-dev \
    libcurl4-openssl-dev \
    libkrb5-dev \
    libldap2-dev \
    libsasl2-dev \
    rustc \
    cargo

# ---------------------------------------------------------------------------
# Binary exploitation and debugging
# ---------------------------------------------------------------------------

install_apt_group "Binary exploitation / debugging" \
    gdb \
    gdb-multiarch \
    gdbserver \
    binutils \
    binutils-multiarch \
    patchelf \
    checksec \
    strace \
    ltrace \
    lsof \
    procps \
    psmisc \
    qemu-user \
    qemu-user-static

# ---------------------------------------------------------------------------
# File and binary analysis
# ---------------------------------------------------------------------------

install_apt_group "File / binary analysis" \
    file \
    p7zip-full \
    unzip \
    zip \
    xxd \
    libimage-exiftool-perl \
    binwalk \
    foremost \
    sleuthkit \
    testdisk \
    yara

# ---------------------------------------------------------------------------
# Remote access and transfer
# ---------------------------------------------------------------------------

install_apt_group "Remote access / transfer" \
    openssh-client \
    rsync \
    curl \
    wget \
    ftp \
    telnet \
    lftp

# ---------------------------------------------------------------------------
# Database clients
# ---------------------------------------------------------------------------

install_apt_group "Database clients" \
    default-mysql-client \
    postgresql-client \
    redis-tools \
    sqlite3

# ---------------------------------------------------------------------------
# Additional runtimes
# ---------------------------------------------------------------------------

install_apt_group "Additional runtimes" \
    nodejs \
    npm \
    ruby \
    ruby-dev \
    ruby-bundler \
    php-cli \
    php-curl \
    php-xml \
    php-mbstring

# ---------------------------------------------------------------------------
# Cloud and miscellaneous
# ---------------------------------------------------------------------------

install_apt_group "Cloud / miscellaneous" \
    awscli \
    rclone \
    remmina \
    freerdp3-x11 \
    smbclient

# ---------------------------------------------------------------------------
# Go
# ---------------------------------------------------------------------------

install_apt_group "Go toolchain" \
    golang-go

# ---------------------------------------------------------------------------
# Python / pipx setup
# ---------------------------------------------------------------------------

echo
echo "============================================================"
echo "  Python / pipx setup"
echo "============================================================"
echo

if ! command -v python3 >/dev/null 2>&1; then
    fail_item "python3"
else
    ok "python3: $(python3 --version 2>&1)"
fi

if ! command -v python3 -m venv >/dev/null 2>&1; then
    :
fi

if ! command -v pipx >/dev/null 2>&1; then
    info "pipx is missing. Installing it explicitly from Debian..."

    if apt-get install -y pipx; then
        ok "pipx installed."
    else
        fail_item "pipx"
    fi
fi

if ! command -v pipx >/dev/null 2>&1; then
    warn "pipx is still unavailable."
else
    ok "pipx: $(pipx --version 2>&1)"

    mkdir -p \
        /opt/pipx \
        /usr/local/share/man

    export PIPX_GLOBAL_HOME="/opt/pipx"
    export PIPX_GLOBAL_BIN_DIR="/usr/local/bin"
    export PIPX_GLOBAL_MAN_DIR="/usr/local/share/man"

    pipx ensurepath --global >/dev/null 2>&1 || true

    cat > /etc/profile.d/pipx.sh <<'EOF'
export PATH="/usr/local/bin:$PATH"
EOF

    chmod 644 /etc/profile.d/pipx.sh

    export PATH="/usr/local/bin:${PATH}"
fi

# ---------------------------------------------------------------------------
# Python venv fallback
# ---------------------------------------------------------------------------

PYTHON_VENV_ROOT="/opt/pentest-python"

mkdir -p "${PYTHON_VENV_ROOT}"

python_venv_fallback() {
    local label="$1"
    local venv_name="$2"
    local spec="$3"
    local command_name="$4"

    local venv_dir="${PYTHON_VENV_ROOT}/${venv_name}"

    info "Python fallback: ${label}"

    if [[ ! -x "${venv_dir}/bin/python" ]]; then
        if ! python3 -m venv "${venv_dir}"; then
            fail_item "Python fallback venv: ${label}"
            return 1
        fi
    fi

    if ! "${venv_dir}/bin/python" -m pip install \
        --disable-pip-version-check \
        --upgrade \
        pip \
        setuptools \
        wheel
    then
        fail_item "Python fallback prerequisites: ${label}"
        return 1
    fi

    if ! "${venv_dir}/bin/python" -m pip install \
        --disable-pip-version-check \
        "${spec}"
    then
        fail_item "Python fallback install: ${label}"
        printf '%s\n' "${label}" >> "${PYTHON_SKIPPED}"
        return 1
    fi

    if [[ -x "${venv_dir}/bin/${command_name}" ]]; then
        ln -sfn \
            "${venv_dir}/bin/${command_name}" \
            "/usr/local/bin/${command_name}"
        ok "Python fallback installed: ${command_name}"
        return 0
    fi

    fail_item "${label}: command ${command_name} not found"
    printf '%s\n' "${label}" >> "${PYTHON_SKIPPED}"
    return 1
}

# ---------------------------------------------------------------------------
# Global pipx installer
# ---------------------------------------------------------------------------

pipx_global_install() {
    local label="$1"
    local package_name="$2"
    local spec="$3"
    local command_name="$4"

    if ! command -v pipx >/dev/null 2>&1; then
        warn "pipx unavailable: ${label}"
        python_venv_fallback \
            "${label}" \
            "${package_name}" \
            "${spec}" \
            "${command_name}"
        return
    fi

    if command -v "${command_name}" >/dev/null 2>&1; then
        ok "Already available: ${command_name}"
        return
    fi

    if pipx list --global 2>/dev/null |
        grep -qE "package ${package_name}([[:space:]]|$)"
    then
        info "pipx package already exists: ${package_name}"

        if ! pipx upgrade --global "${package_name}"; then
            warn "pipx upgrade failed. Reinstalling: ${package_name}"

            if ! pipx reinstall --global "${package_name}"; then
                warn "pipx reinstall failed: ${package_name}"
            fi
        fi
    else
        info "Installing Python tool: ${label}"

        if ! pipx install \
            --global \
            --python /usr/bin/python3 \
            "${spec}"
        then
            warn "pipx installation failed: ${label}"
            python_venv_fallback \
                "${label}" \
                "${package_name}" \
                "${spec}" \
                "${command_name}"
            return
        fi
    fi

    if command -v "${command_name}" >/dev/null 2>&1; then
        installed "Python: ${label}"
    else
        warn "Python package installed but command is missing: ${command_name}"

        python_venv_fallback \
            "${label}" \
            "${package_name}" \
            "${spec}" \
            "${command_name}"
    fi
}

# ---------------------------------------------------------------------------
# Python security tooling
# ---------------------------------------------------------------------------

echo
echo "============================================================"
echo "  Python security tooling"
echo "============================================================"
echo

pipx_global_install \
    "Impacket" \
    "impacket" \
    "impacket" \
    "GetUserSPNs.py"

pipx_global_install \
    "BloodHound Python legacy" \
    "bloodhound" \
    "bloodhound" \
    "bloodhound-python"

pipx_global_install \
    "BloodHound CE Python" \
    "bloodhound-ce" \
    "bloodhound-ce" \
    "bloodhound-ce-python"

pipx_global_install \
    "enum4linux-ng" \
    "enum4linux-ng" \
    "git+https://github.com/cddmp/enum4linux-ng.git" \
    "enum4linux-ng.py"

pipx_global_install \
    "Certipy" \
    "certipy-ad" \
    "certipy-ad" \
    "certipy"

pipx_global_install \
    "bloodyAD" \
    "bloodyad" \
    "bloodyAD" \
    "bloodyAD"

pipx_global_install \
    "pyWhisker" \
    "pywhisker" \
    "git+https://github.com/ShutdownRepo/pywhisker.git" \
    "pywhisker"

pipx_global_install \
    "adidnsdump" \
    "adidnsdump" \
    "git+https://github.com/dirkjanm/adidnsdump.git" \
    "adidnsdump"

pipx_global_install \
    "ldapdomaindump" \
    "ldapdomaindump" \
    "ldapdomaindump" \
    "ldapdomaindump"

pipx_global_install \
    "wfuzz" \
    "wfuzz" \
    "wfuzz" \
    "wfuzz"

pipx_global_install \
    "Arjun" \
    "arjun" \
    "arjun" \
    "arjun"

pipx_global_install \
    "pwntools" \
    "pwntools" \
    "pwntools" \
    "pwn"

pipx_global_install \
    "ROPgadget" \
    "ropgadget" \
    "ropgadget" \
    "ROPgadget"

pipx_global_install \
    "mitm6" \
    "mitm6" \
    "mitm6" \
    "mitm6"

pipx_global_install \
    "Coercer" \
    "coercer" \
    "coercer" \
    "Coercer"

pipx_global_install \
    "pwncat-cs" \
    "pwncat-cs" \
    "pwncat-cs" \
    "pwncat-cs"

pipx_global_install \
    "LaZagne" \
    "lazagne" \
    "LaZagne" \
    "laZagne"

pipx_global_install \
    "pypykatz" \
    "pypykatz" \
    "pypykatz" \
    "pypykatz"

# ---------------------------------------------------------------------------
# Normalize LaZagne command aliases
# ---------------------------------------------------------------------------

if [[ -x /usr/local/bin/laZagne && ! -e /usr/local/bin/lazagne ]]; then
    ln -s /usr/local/bin/laZagne /usr/local/bin/lazagne
fi

# ---------------------------------------------------------------------------
# NetExec
# ---------------------------------------------------------------------------

echo
echo "============================================================"
echo "  NetExec"
echo "============================================================"
echo

if command -v nxc >/dev/null 2>&1; then
    ok "NetExec already available."
else
    if command -v pipx >/dev/null 2>&1; then
        if pipx list --global 2>/dev/null | grep -qE "package netexec([[:space:]]|$)"; then
            pipx upgrade --global netexec || true
        else
            if ! pipx install \
                --global \
                --python /usr/bin/python3 \
                "git+https://github.com/Pennyw0rth/NetExec"
            then
                warn "NetExec pipx installation failed."
            fi
        fi
    fi
fi

if command -v nxc >/dev/null 2>&1; then
    installed "NetExec"
else
    fail_item "NetExec / nxc"
fi

# ---------------------------------------------------------------------------
# Kerbrute
# ---------------------------------------------------------------------------

echo
echo "============================================================"
echo "  Kerbrute"
echo "============================================================"
echo

if ! command -v kerbrute >/dev/null 2>&1; then
    KERBRUTE_URL="https://github.com/ropnop/kerbrute/releases/latest/download/kerbrute_linux_amd64"

    if curl -fL \
        --retry 3 \
        --connect-timeout 15 \
        "${KERBRUTE_URL}" \
        -o /usr/local/bin/kerbrute
    then
        chmod +x /usr/local/bin/kerbrute
        ok "Kerbrute installed."
    else
        fail_item "Kerbrute"
    fi
else
    ok "Kerbrute already available."
fi

# ---------------------------------------------------------------------------
# Chisel
# ---------------------------------------------------------------------------

echo
echo "============================================================"
echo "  Chisel"
echo "============================================================"
echo

if ! command -v chisel >/dev/null 2>&1; then
    if command -v go >/dev/null 2>&1; then
        if GOPATH=/tmp/go-build \
            GOBIN=/usr/local/bin \
            go install github.com/jpillora/chisel@latest
        then
            ok "Chisel installed."
        else
            fail_item "Chisel"
        fi
    else
        fail_item "Chisel: Go is unavailable"
    fi
else
    ok "Chisel already available."
fi

# ---------------------------------------------------------------------------
# Ligolo-ng
# ---------------------------------------------------------------------------

echo
echo "============================================================"
echo "  Ligolo-ng"
echo "============================================================"
echo

LIGOLO_DIR="${TOOLS_DIR}/ligolo-ng"

if command -v ligolo-proxy >/dev/null 2>&1 &&
   command -v ligolo-agent >/dev/null 2>&1
then
    ok "Ligolo-ng already available."
else
    if [[ ! -d "${LIGOLO_DIR}/.git" ]]; then
        rm -rf "${LIGOLO_DIR}"
        if git clone \
            --depth 1 \
            https://github.com/nicocha30/ligolo-ng.git \
            "${LIGOLO_DIR}"
        then
            ok "Ligolo-ng repository cloned."
        else
            fail_item "Ligolo-ng clone"
        fi
    else
        git -C "${LIGOLO_DIR}" pull --ff-only || true
    fi

    if [[ -d "${LIGOLO_DIR}" && -f "${LIGOLO_DIR}/go.mod" ]]; then
        if command -v go >/dev/null 2>&1; then
            if (
                cd "${LIGOLO_DIR}" &&
                go build -o /usr/local/bin/ligolo-proxy ./cmd/proxy &&
                go build -o /usr/local/bin/ligolo-agent ./cmd/agent
            ); then
                chmod +x \
                    /usr/local/bin/ligolo-proxy \
                    /usr/local/bin/ligolo-agent

                ok "Ligolo-ng built."
            else
                fail_item "Ligolo-ng build"
            fi
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Responder
# ---------------------------------------------------------------------------

echo
echo "============================================================"
echo "  Responder"
echo "============================================================"
echo

RESPONDER_DIR="/opt/Responder"

if [[ ! -d "${RESPONDER_DIR}/.git" ]]; then
    rm -rf "${RESPONDER_DIR}"

    if git clone \
        --depth 1 \
        https://github.com/lgandx/Responder.git \
        "${RESPONDER_DIR}"
    then
        ok "Responder cloned."
    else
        fail_item "Responder clone"
    fi
else
    git -C "${RESPONDER_DIR}" pull --ff-only || true
fi

if [[ -f "${RESPONDER_DIR}/Responder.py" ]]; then
    cat > /usr/local/bin/responder <<EOF
#!/usr/bin/env bash
exec /usr/bin/python3 "${RESPONDER_DIR}/Responder.py" "\$@"
EOF

    chmod +x /usr/local/bin/responder
    ok "Responder wrapper installed."
else
    fail_item "Responder"
fi

# ---------------------------------------------------------------------------
# Evil-WinRM
# ---------------------------------------------------------------------------

echo
echo "============================================================"
echo "  Evil-WinRM"
echo "============================================================"
echo

if command -v evil-winrm >/dev/null 2>&1; then
    ok "Evil-WinRM already available."
else
    if command -v gem >/dev/null 2>&1; then
        if gem install \
            --no-document \
            evil-winrm
        then
            ok "Evil-WinRM installed."
        else
            warn "Direct gem installation failed."

            EVIL_WINRM_DIR="${TOOLS_DIR}/evil-winrm"

            if [[ ! -d "${EVIL_WINRM_DIR}/.git" ]]; then
                rm -rf "${EVIL_WINRM_DIR}"

                if git clone \
                    --depth 1 \
                    https://github.com/Hackplayers/evil-winrm.git \
                    "${EVIL_WINRM_DIR}"
                then
                    if (
                        cd "${EVIL_WINRM_DIR}" &&
                        gem install --no-document bundler &&
                        bundle config set --local path vendor/bundle &&
                        bundle install
                    ); then

                        cat > /usr/local/bin/evil-winrm <<EOF
#!/usr/bin/env bash
cd "${EVIL_WINRM_DIR}"
exec bundle exec ruby evil-winrm.rb "\$@"
EOF

                        chmod +x /usr/local/bin/evil-winrm

                        ok "Evil-WinRM installed through Bundler."
                    else
                        fail_item "Evil-WinRM"
                    fi
                else
                    fail_item "Evil-WinRM clone"
                fi
            fi
        fi
    else
        fail_item "Evil-WinRM: Ruby unavailable"
    fi
fi

# ---------------------------------------------------------------------------
# Metasploit Framework
# ---------------------------------------------------------------------------

echo
echo "============================================================"
echo "  Metasploit Framework"
echo "============================================================"
echo

if command -v msfconsole >/dev/null 2>&1; then
    ok "Metasploit already available."
else
    MSF_INSTALLER="/tmp/msfinstall"

    if curl -fL \
        --retry 3 \
        https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfinstall \
        -o "${MSF_INSTALLER}"
    then
        chmod 755 "${MSF_INSTALLER}"

        if "${MSF_INSTALLER}"; then
            ok "Metasploit Framework installed."
        else
            fail_item "Metasploit Framework"
        fi

        rm -f "${MSF_INSTALLER}"
    else
        fail_item "Metasploit installer download"
    fi
fi

# ---------------------------------------------------------------------------
# Radare2
# ---------------------------------------------------------------------------

echo
echo "============================================================"
echo "  Radare2"
echo "============================================================"
echo

if command -v r2 >/dev/null 2>&1; then
    ok "Radare2 already available."
else
    R2_DIR="${TOOLS_DIR}/radare2"

    if [[ ! -d "${R2_DIR}/.git" ]]; then
        rm -rf "${R2_DIR}"

        if git clone \
            --depth 1 \
            https://github.com/radareorg/radare2.git \
            "${R2_DIR}"
        then
            if "${R2_DIR}/sys/install.sh"; then
                ok "Radare2 installed."
            else
                fail_item "Radare2 installation"
            fi
        else
            fail_item "Radare2 clone"
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Ghidra
# ---------------------------------------------------------------------------

echo
echo "============================================================"
echo "  Ghidra"
echo "============================================================"
echo

GHIDRA_ROOT="/opt/ghidra"
GHIDRA_API="https://api.github.com/repos/NationalSecurityAgency/ghidra/releases/latest"

if [[ -x "${GHIDRA_ROOT}/ghidraRun" ]]; then
    ok "Ghidra already available."
else
    GHIDRA_JSON="/tmp/ghidra-release.json"

    if curl -fsSL \
        --retry 3 \
        "${GHIDRA_API}" \
        -o "${GHIDRA_JSON}"
    then
        GHIDRA_URL="$(
            jq -r '
                .assets[]
                | select(.name | test("PUBLIC.*zip$"))
                | .browser_download_url
            ' "${GHIDRA_JSON}" |
            head -n1
        )"

        GHIDRA_ASSET="$(
            jq -r '
                .assets[]
                | select(.name | test("PUBLIC.*zip$"))
                | .name
            ' "${GHIDRA_JSON}" |
            head -n1
        )"

        if [[ -n "${GHIDRA_URL}" && "${GHIDRA_URL}" != "null" ]]; then
            GHIDRA_TMP="/tmp/${GHIDRA_ASSET}"

            if curl -fL \
                --retry 3 \
                "${GHIDRA_URL}" \
                -o "${GHIDRA_TMP}"
            then
                rm -rf "${GHIDRA_ROOT}"
                mkdir -p "${GHIDRA_ROOT}"

                if unzip -q "${GHIDRA_TMP}" -d /opt; then
                    EXTRACTED_DIR="$(find /opt -maxdepth 1 -type d -name 'ghidra_*_PUBLIC' | sort -V | tail -n1)"

                    if [[ -n "${EXTRACTED_DIR}" && -x "${EXTRACTED_DIR}/ghidraRun" ]]; then
                        mv "${EXTRACTED_DIR}" "${GHIDRA_ROOT}"

                        cat > /usr/local/bin/ghidra <<EOF
#!/usr/bin/env bash
exec "${GHIDRA_ROOT}/ghidraRun" "\$@"
EOF

                        chmod +x /usr/local/bin/ghidra

                        ok "Ghidra installed: ${GHIDRA_ASSET}"
                    else
                        fail_item "Ghidra extracted directory"
                    fi
                else
                    fail_item "Ghidra extraction"
                fi

                rm -f "${GHIDRA_TMP}"
            else
                fail_item "Ghidra download"
            fi
        else
            fail_item "Ghidra release asset detection"
        fi

        rm -f "${GHIDRA_JSON}"
    else
        fail_item "Ghidra GitHub API"
    fi
fi

# ---------------------------------------------------------------------------
# Pentesting repositories
# ---------------------------------------------------------------------------

echo
echo "============================================================"
echo "  Pentesting repositories"
echo "============================================================"
echo

clone_or_update() {
    local name="$1"
    local url="$2"
    local destination="$3"

    if [[ -d "${destination}/.git" ]]; then
        info "Updating ${name}..."
        git -C "${destination}" pull --ff-only || true
        ok "${name}: repository present."
        return
    fi

    rm -rf "${destination}"

    if git clone \
        --depth 1 \
        "${url}" \
        "${destination}"
    then
        ok "${name}: cloned."
    else
        fail_item "Repository: ${name}"
    fi
}

REPO_ROOT="${TOOLS_DIR}/repos"
mkdir -p "${REPO_ROOT}"

clone_or_update \
    "PEASS-ng" \
    "https://github.com/peass-ng/PEASS-ng.git" \
    "${REPO_ROOT}/PEASS-ng"

clone_or_update \
    "PayloadsAllTheThings" \
    "https://github.com/swisskyrepo/PayloadsAllTheThings.git" \
    "${REPO_ROOT}/PayloadsAllTheThings"

clone_or_update \
    "LinEnum" \
    "https://github.com/rebootuser/LinEnum.git" \
    "${REPO_ROOT}/LinEnum"

clone_or_update \
    "linux-smart-enumeration" \
    "https://github.com/diego-treitos/linux-smart-enumeration.git" \
    "${REPO_ROOT}/linux-smart-enumeration"

clone_or_update \
    "linux-exploit-suggester" \
    "https://github.com/mzet-/linux-exploit-suggester.git" \
    "${REPO_ROOT}/linux-exploit-suggester"

clone_or_update \
    "pspy" \
    "https://github.com/DominicBreuker/pspy.git" \
    "${REPO_ROOT}/pspy"

clone_or_update \
    "WES-NG" \
    "https://github.com/bitsadmin/wesng.git" \
    "${REPO_ROOT}/wesng"

clone_or_update \
    "PowerSploit" \
    "https://github.com/PowerShellMafia/PowerSploit.git" \
    "${REPO_ROOT}/PowerSploit"

clone_or_update \
    "PKINITtools" \
    "https://github.com/dirkjanm/PKINITtools.git" \
    "${REPO_ROOT}/PKINITtools"

clone_or_update \
    "FuzzDB" \
    "https://github.com/fuzzdb-project/fuzzdb.git" \
    "${REPO_ROOT}/fuzzdb"

clone_or_update \
    "IntruderPayloads" \
    "https://github.com/1N3/IntruderPayloads.git" \
    "${REPO_ROOT}/IntruderPayloads"

clone_or_update \
    "static-binaries" \
    "https://github.com/andrew-d/static-binaries.git" \
    "${REPO_ROOT}/static-binaries"

clone_or_update \
    "SUID3NUM" \
    "https://github.com/Anon-Exploiter/SUID3NUM.git" \
    "${REPO_ROOT}/SUID3NUM"

clone_or_update \
    "LinWinPwn" \
    "https://github.com/lefayjey/linWinPwn.git" \
    "${REPO_ROOT}/LinWinPwn"

clone_or_update \
    "unix-privesc-check" \
    "https://github.com/pentestmonkey/unix-privesc-check.git" \
    "${REPO_ROOT}/unix-privesc-check"

# ---------------------------------------------------------------------------
# SecLists
# ---------------------------------------------------------------------------

echo
echo "============================================================"
echo "  SecLists"
echo "============================================================"
echo

SECLISTS_DIR="/usr/share/seclists"

if [[ -d "${SECLISTS_DIR}/.git" ]]; then
    git -C "${SECLISTS_DIR}" pull --ff-only || true
    ok "SecLists repository already exists."
else
    rm -rf "${SECLISTS_DIR}"

    if git clone \
        --depth 1 \
        https://github.com/danielmiessler/SecLists.git \
        "${SECLISTS_DIR}"
    then
        ok "SecLists installed."
    else
        warn "Git clone failed. Trying ZIP fallback."

        SECLISTS_ZIP="/tmp/SecLists.zip"

        if curl -fL \
            --retry 3 \
            https://github.com/danielmiessler/SecLists/archive/refs/heads/master.zip \
            -o "${SECLISTS_ZIP}"
        then
            rm -rf /usr/share/SecLists-master

            if unzip -q \
                "${SECLISTS_ZIP}" \
                -d /usr/share
            then
                rm -rf "${SECLISTS_DIR}"

                mv \
                    /usr/share/SecLists-master \
                    "${SECLISTS_DIR}"

                ok "SecLists installed from ZIP."
            else
                fail_item "SecLists ZIP extraction"
            fi

            rm -f "${SECLISTS_ZIP}"
        else
            fail_item "SecLists"
        fi
    fi
fi

# ---------------------------------------------------------------------------
# LinPEAS / WinPEAS / pspy
# ---------------------------------------------------------------------------

echo
echo "============================================================"
echo "  Standalone enumeration binaries"
echo "============================================================"
echo

BIN_DIR="${TOOLS_DIR}/binaries"

mkdir -p "${BIN_DIR}"

download_file() {
    local name="$1"
    local url="$2"
    local destination="$3"

    if [[ -f "${destination}" ]]; then
        ok "${name} already exists."
        return
    fi

    if curl -fL \
        --retry 3 \
        "${url}" \
        -o "${destination}"
    then
        chmod +x "${destination}"
        ok "${name} downloaded."
    else
        fail_item "${name}"
    fi
}

download_file \
    "LinPEAS" \
    "https://github.com/peass-ng/PEASS-ng/releases/latest/download/linpeas.sh" \
    "${BIN_DIR}/linpeas.sh"

download_file \
    "WinPEAS x64" \
    "https://github.com/peass-ng/PEASS-ng/releases/latest/download/winPEASx64.exe" \
    "${BIN_DIR}/winPEASx64.exe"

download_file \
    "WinPEAS x86" \
    "https://github.com/peass-ng/PEASS-ng/releases/latest/download/winPEASx86.exe" \
    "${BIN_DIR}/winPEASx86.exe"

download_file \
    "pspy64" \
    "https://github.com/DominicBreuker/pspy/releases/latest/download/pspy64" \
    "${BIN_DIR}/pspy64"

# ---------------------------------------------------------------------------
# RockYou
# ---------------------------------------------------------------------------

echo
echo "============================================================"
echo "  RockYou"
echo "============================================================"
echo

WORDLIST_DIR="/usr/share/wordlists"

mkdir -p "${WORDLIST_DIR}"

if [[ -f "${WORDLIST_DIR}/rockyou.txt" ]]; then
    ok "rockyou.txt already available."
elif [[ -f "${WORDLIST_DIR}/rockyou.txt.gz" ]]; then
    info "Extracting rockyou.txt.gz..."

    if gzip -dk "${WORDLIST_DIR}/rockyou.txt.gz"; then
        ok "rockyou.txt extracted."
    else
        fail_item "rockyou extraction"
    fi
else
    ROCKYOU_URL="https://github.com/brannondorsey/naive-hashcat/releases/download/data/rockyou.txt"

    if curl -fL \
        --retry 3 \
        "${ROCKYOU_URL}" \
        -o "${WORDLIST_DIR}/rockyou.txt"
    then
        chmod 644 "${WORDLIST_DIR}/rockyou.txt"
        ok "rockyou.txt downloaded."
    else
        fail_item "rockyou.txt"
    fi
fi

# ---------------------------------------------------------------------------
# Convenience links
# ---------------------------------------------------------------------------

echo
echo "============================================================"
echo "  Convenience links"
echo "============================================================"
echo

mkdir -p /usr/local/share/pentest

ln -sfn "${SECLISTS_DIR}" /usr/local/share/pentest/seclists
ln -sfn "${REPO_ROOT}" /usr/local/share/pentest/repos
ln -sfn "${BIN_DIR}" /usr/local/share/pentest/binaries

if [[ -x "${BIN_DIR}/linpeas.sh" ]]; then
    ln -sfn "${BIN_DIR}/linpeas.sh" /usr/local/bin/linpeas
fi

if [[ -x "${BIN_DIR}/pspy64" ]]; then
    ln -sfn "${BIN_DIR}/pspy64" /usr/local/bin/pspy64
fi

# ---------------------------------------------------------------------------
# Zsh aliases
# ---------------------------------------------------------------------------

echo
echo "============================================================"
echo "  Zsh aliases"
echo "============================================================"
echo

ZSHRC="${USER_HOME}/.zshrc"

touch "${ZSHRC}"

if ! grep -q "BEGIN PENTEST ALIASES" "${ZSHRC}" 2>/dev/null; then
    cat >> "${ZSHRC}" <<'EOF'

# BEGIN PENTEST ALIASES

alias ll='ls -la'
alias la='ls -la'
alias ports='ss -tulpn'
alias listening='ss -lntup'
alias psg='ps aux | grep -i'
alias myip='ip -br addr'
alias routes='ip route'
alias nmap-full='nmap -sC -sV -p-'
alias nmap-quick='nmap -Pn -sC -sV'
alias smb-shares='smbclient -L'
alias seclists='cd /usr/share/seclists'
alias pentest='cd /usr/local/share/pentest'
alias tools='cd ~/kali/tools'

# END PENTEST ALIASES
EOF

    chown "${USERNAME}:${USERNAME}" "${ZSHRC}"
fi

# ---------------------------------------------------------------------------
# Python import sanity checks
# ---------------------------------------------------------------------------

echo
echo "============================================================"
echo "  Python sanity checks"
echo "============================================================"
echo

python_import_test() {
    local package="$1"
    local label="$2"

    if python3 -c "import ${package}" >/dev/null 2>&1; then
        ok "Python import: ${label}"
    else
        warn "Python import missing from system Python: ${label}"
    fi
}

python_import_test "Crypto" "pycryptodome"
python_import_test "ldap3" "ldap3"
python_import_test "yaml" "PyYAML"

if python3 -c "import minikerberos" >/dev/null 2>&1; then
    ok "Python import: minikerberos"
else
    info "Installing minikerberos into an isolated global Python environment..."

    MK_VENV="${PYTHON_VENV_ROOT}/minikerberos"

    if [[ ! -x "${MK_VENV}/bin/python" ]]; then
        if python3 -m venv "${MK_VENV}"; then
            "${MK_VENV}/bin/python" -m pip install \
                --disable-pip-version-check \
                -U \
                pip \
                setuptools \
                wheel \
                minikerberos || \
                fail_item "minikerberos"
        fi
    else
        "${MK_VENV}/bin/python" -m pip install \
            --disable-pip-version-check \
            -U \
            minikerberos || \
            fail_item "minikerberos"
    fi
fi

# ---------------------------------------------------------------------------
# Final ownership fixes
# ---------------------------------------------------------------------------

chown -R "${USERNAME}:${USERNAME}" \
    "${USER_HOME}/.cache" \
    "${USER_HOME}/.config" \
    "${USER_HOME}/.local" \
    2>/dev/null || true

# Keep root-installed pentest files root-owned.
chown -R root:root \
    /opt/pipx \
    /opt/pentest-python \
    /opt/Responder \
    /opt/ghidra \
    /usr/share/seclists \
    2>/dev/null || true

# ---------------------------------------------------------------------------
# Final validation
# ---------------------------------------------------------------------------

echo
echo "============================================================"
echo "  TOOL VALIDATION"
echo "============================================================"
echo

validate_command() {
    local command_name="$1"

    if command -v "${command_name}" >/dev/null 2>&1; then
        printf '[+] %s -> %s\n' \
            "${command_name}" \
            "$(command -v "${command_name}")"
        return 0
    fi

    printf '[MISSING] %s\n' "${command_name}"
    return 1
}

VALIDATION_COMMANDS=(
    nmap
    ffuf
    gobuster
    sqlmap
    hydra
    john
    hashcat
    smbclient
    rpcclient
    nxc
    GetUserSPNs.py
    bloodhound-python
    bloodhound-ce-python
    certipy
    bloodyAD
    pywhisker
    adidnsdump
    ldapdomaindump
