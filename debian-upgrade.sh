#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <username>"
    exit 1
fi

Username="$1"

if [[ $EUID -ne 0 ]]; then
    echo "Uruchom jako root: sudo $0 <username>"
    exit 1
fi

if [[ ! "$Username" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]; then
    echo "Nieprawidłowy username: $Username"
    exit 1
fi

echo ">>> Konfiguracja dla użytkownika: $Username"

# ============================================================
# 1. BASE SYSTEM + ZSH + SUDO
# ============================================================

apt update

apt install -y \
    zsh \
    sudo \
    git \
    ca-certificates \
    curl \
    locales

if id "$Username" &>/dev/null; then
    echo "Użytkownik $Username już istnieje"
else
    adduser "$Username"
fi

USER_HOME="$(getent passwd "$Username" | cut -d: -f6)"

usermod -aG sudo "$Username"
chsh -s /usr/bin/zsh "$Username"

echo '%sudo ALL=(ALL:ALL) NOPASSWD: ALL' \
    > /etc/sudoers.d/sudo-nopasswd

chmod 440 /etc/sudoers.d/sudo-nopasswd

visudo -c


# ============================================================
# 2. DOCKER + DOCKER COMPOSE
# ============================================================

apt update

apt install -y \
    ca-certificates \
    curl

install -m 0755 -d /etc/apt/keyrings

curl -fsSL \
    https://download.docker.com/linux/debian/gpg \
    -o /etc/apt/keyrings/docker.asc

chmod a+r /etc/apt/keyrings/docker.asc

cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt update

apt install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

usermod -aG docker "$Username"

systemctl enable --now docker


# ============================================================
# 3. KDE PLASMA + XRDP
# ============================================================

apt update

apt install -y \
    kde-plasma-desktop \
    plasma-desktop \
    plasma-workspace \
    kwin-x11 \
    xorg \
    xserver-xorg \
    xrdp \
    xorgxrdp \
    dbus-x11 \
    sddm

cat > "$USER_HOME/.xsession" <<EOF
exec startplasma-x11
EOF

chown "$Username:$Username" "$USER_HOME/.xsession"
chmod 644 "$USER_HOME/.xsession"

systemctl enable sddm
systemctl enable --now xrdp


# ============================================================
# 4. FIREFOX + TILIX + FONT
# ============================================================

apt install -y \
    firefox-esr \
    tilix \
    dconf-cli \
    fonts-jetbrains-mono


# ============================================================
# 5. XRDP - USTAWIENIA
# ============================================================

sed -i \
    -e 's/^bitmap_cache=.*/bitmap_cache=true/' \
    -e 's/^bitmap_compression=.*/bitmap_compression=false/' \
    -e 's/^bulk_compression=.*/bulk_compression=false/' \
    -e 's/^max_bpp=.*/max_bpp=32/' \
    -e 's/^use_fastpath=.*/use_fastpath=both/' \
    -e 's/^h264_frame_interval=.*/h264_frame_interval=16/' \
    -e 's/^rfx_frame_interval=.*/rfx_frame_interval=32/' \
    -e 's/^normal_frame_interval=.*/normal_frame_interval=40/' \
    /etc/xrdp/xrdp.ini

sed -i \
    's/^order = .*/order = [ "RFX","H.264"]/' \
    /etc/xrdp/gfx.toml

usermod -aG ssl-cert xrdp

chown root:ssl-cert /etc/xrdp/key.pem
chmod 640 /etc/xrdp/key.pem


# ============================================================
# 6. MC SUR KDE
# ============================================================

rm -rf /tmp/McSur-kde

cd /tmp

git clone \
    https://github.com/yeyushengfan258/McSur-kde.git

cd /tmp/McSur-kde

chmod +x install.sh

su - "$Username" -c './install.sh'


# ============================================================
# 7. CATPPUCCIN KDE
# ============================================================

apt install -y unzip

rm -rf /tmp/catppuccin-kde

cd /tmp

git clone --depth=1 \
    https://github.com/catppuccin/kde \
    catppuccin-kde

cd /tmp/catppuccin-kde

chmod +x install.sh

su - "$Username" -c './install.sh 1 13 2 auto'


# ============================================================
# 8. PURPURNIGHT GLOBAL 6
# ============================================================

PURPUR_ARCHIVE="/tmp/SCsEoa-PurPurNight-Global-6.tar.gz"

if [[ -f "$PURPUR_ARCHIVE" ]]; then

    install -d \
        -o "$Username" \
        -g "$Username" \
        "$USER_HOME/.local/share/plasma/look-and-feel"

    tar -xzf \
        "$PURPUR_ARCHIVE" \
        -C "$USER_HOME/.local/share/plasma/look-and-feel"

    chown -R \
        "$Username:$Username" \
        "$USER_HOME/.local/share/plasma/look-and-feel"

else

    echo "Brak $PURPUR_ARCHIVE - PurPurNight pomijam."

fi


# ============================================================
# 9. ZSH - USER
# ============================================================

if [[ -f "$USER_HOME/.zshrc" ]]; then
    cp "$USER_HOME/.zshrc" "$USER_HOME/.zshrc.bak"
else
    touch "$USER_HOME/.zshrc"
fi

sed -i \
    '/^# Set up the prompt$/,/^prompt adam1$/d' \
    "$USER_HOME/.zshrc"

cat >> "$USER_HOME/.zshrc" <<'EOF'

setopt interactivecomments

PROMPT_EOL_MARK=''
unset RPROMPT

if [[ $EUID -eq 0 ]]; then
    PROMPT=$'%F{red}┌──(%B%n㉿%m%b)-[%~]%f\n%F{red}└─%b#%f '
else
    PROMPT=$'%F{blue}┌──(%B%n㉿%m%b)-[%~]%f\n%F{blue}└─%b%% %f'
fi
EOF

chown "$Username:$Username" "$USER_HOME/.zshrc"

chsh -s /usr/bin/zsh "$Username"


# ============================================================
# 10. ZSH - ROOT
# ============================================================

if [[ -f /root/.zshrc ]]; then
    cp /root/.zshrc /root/.zshrc.bak
else
    touch /root/.zshrc
fi

sed -i \
    '/^# Set up the prompt$/,/^prompt adam1$/d' \
    /root/.zshrc

cat >> /root/.zshrc <<'EOF'

setopt interactivecomments

PROMPT_EOL_MARK=''
unset RPROMPT

if [[ $EUID -eq 0 ]]; then
    PROMPT=$'%F{red}┌──(%B%n㉿%m%b)-[%~]%f\n%F{red}└─%b#%f '
else
    PROMPT=$'%F{blue}┌──(%B%n㉿%m%b)-[%~]%f\n%F{blue}└─%b%% %f'
fi
EOF

chsh -s /usr/bin/zsh root


# ============================================================
# 11. TIMEZONE + FORMAT 24H
# ============================================================

if ! grep -q '^pl_PL.UTF-8 UTF-8$' /etc/locale.gen; then
    sed -i \
        's/^# *pl_PL.UTF-8 UTF-8/pl_PL.UTF-8 UTF-8/' \
        /etc/locale.gen
fi

locale-gen pl_PL.UTF-8

timedatectl set-timezone Europe/Warsaw

mkdir -p "$USER_HOME/.config"

cat > "$USER_HOME/.config/plasma-localerc" <<'EOF'
[Formats]
LANG=en_US.UTF-8
LC_TIME=pl_PL.UTF-8

[Translations]
LANGUAGE=en_US
EOF

chown "$Username:$Username" \
    "$USER_HOME/.config/plasma-localerc"

if [[ -f "$USER_HOME/.profile" ]]; then

    if ! grep -q '^export LC_TIME=pl_PL.UTF-8$' "$USER_HOME/.profile"; then
        printf '\nexport LC_TIME=pl_PL.UTF-8\n' \
            >> "$USER_HOME/.profile"
    fi

else

    cat > "$USER_HOME/.profile" <<'EOF'
export LC_TIME=pl_PL.UTF-8
EOF

fi

chown "$Username:$Username" "$USER_HOME/.profile"


# ============================================================
# 12. TILIX
# ============================================================

TILIX_SCRIPT="/tmp/tilix-setup-${Username}.sh"

cat > "$TILIX_SCRIPT" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

P="$(gsettings get \
    com.gexperts.Tilix.ProfilesList \
    default | tr -d "'\r\n")"

PREFIX="com.gexperts.Tilix.Profile:/com/gexperts/Tilix/profiles/$P/"

gsettings set \
    com.gexperts.Tilix.Settings \
    theme-variant \
    'dark'

gsettings set \
    com.gexperts.Tilix.Settings \
    use-tabs \
    true

gsettings set \
    com.gexperts.Tilix.Settings \
    terminal-title-style \
    'none'

gsettings set \
    "$PREFIX" \
    use-theme-colors \
    false

gsettings set \
    "$PREFIX" \
    background-color \
    '#111118'

gsettings set \
    "$PREFIX" \
    foreground-color \
    '#E6E1EE'

gsettings set \
    "$PREFIX" \
    background-transparency-percent \
    5

gsettings set \
    "$PREFIX" \
    use-system-font \
    false

gsettings set \
    "$PREFIX" \
    font \
    'JetBrains Mono 11'

gsettings set \
    "$PREFIX" \
    cursor-blink-mode \
    'off'

gsettings set \
    com.gexperts.Tilix.Keybindings \
    session-add-right \
    '<Primary><Shift>Right'

gsettings set \
    com.gexperts.Tilix.Keybindings \
    session-add-down \
    '<Primary><Shift>Down'
EOF

chown "$Username:$Username" "$TILIX_SCRIPT"
chmod 700 "$TILIX_SCRIPT"

su - "$Username" -c \
    "dbus-run-session -- bash '$TILIX_SCRIPT'"

rm -f "$TILIX_SCRIPT"


# ============================================================
# 13. OCHRONA PRZED PRZYPADKOWYM AUTOREMOVE
# ============================================================

apt-mark manual \
    kde-plasma-desktop \
    plasma-desktop \
    plasma-workspace \
    kwin-x11 \
    xorg \
    xserver-xorg \
    sddm \
    xrdp \
    xorgxrdp \
    dbus-x11 \
    tilix \
    zsh \
    sudo \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin


# ============================================================
# 14. RESTART XRDP
# ============================================================

systemctl restart xrdp


# ============================================================
# 15. WERYFIKACJA
# ============================================================

echo
echo "===== USER ====="
id "$Username"

echo
echo "===== SHELL ====="
getent passwd "$Username"
getent passwd root

echo
echo "===== DOCKER ====="
docker --version
docker compose version

echo
echo "===== ZSH ====="
su - "$Username" -c 'zsh --version'
su - "$Username" -c 'zsh -lic "echo ZSH_OK"'

echo
echo "===== TIMEZONE ====="
timedatectl

echo
echo "===== SDDM ====="
systemctl is-active sddm

echo
echo "===== XRDP ====="
xrdp --version
xrdp-sesman --version
systemctl is-active xrdp

echo
echo "===== XRDP KEY ====="
ls -l /etc/xrdp/key.pem

echo
echo "===== XRDP SETTINGS ====="
grep -E \
    '^(bitmap_cache|bitmap_compression|bulk_compression|max_bpp|use_fastpath|h264_frame_interval|rfx_frame_interval|normal_frame_interval)' \
    /etc/xrdp/xrdp.ini

echo
echo "===== CODEC ORDER ====="
grep '^order =' /etc/xrdp/gfx.toml

echo
echo "===== GLOBAL THEMES ====="
su - "$Username" -c \
    "lookandfeeltool --list | grep -Ei 'breeze|mcsur|catppuccin|purpur' || true"

echo
echo "===== PLASMA ====="
command -v startplasma-x11
dpkg -l | grep -E \
    '^ii  (kde-plasma-desktop|plasma-desktop|plasma-workspace|kwin-x11|xorg|sddm)'

echo
echo "=========================================="
echo " KONFIGURACJA ZAKONCZONA"
echo " User: $Username"
echo "=========================================="
