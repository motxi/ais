# Not meant to be run directly.
# Sourced by "chroot.sh".

_BASE=(
    base
    base-devel
    linux
    linux-firmware
    amd-ucode
    man-db
    man-pages
    polkit
)

_BOOT=(
    dosfstools
    efibootmgr
    limine
    memtest86+-efi
)

_AUDIO=(
    pipewire
    pipewire-alsa
    pipewire-jack
    pipewire-pulse
    playerctl
    wireplumber
    headsetcontrol
)

_VIDEO=(
    lact
    lib32-mesa
    lib32-vulkan-radeon
    libva-utils
    mesa
    nvtop
    vulkan-radeon
)

_NETWORK=(
    dhcpcd
    openssh
    sshfs
    wget
)

_XORG=(
    xclip
    xdg-user-dirs
    xdg-utils
    xorg-server
    xorg-xinit
    xorg-xinput
    xorg-xset
    xsel
    xss-lock
)

_DESKTOP=(
    arandr
    dex
    dunst
    feh
    i3-wm
    i3lock
    i3status
    libnotify
    ly
    picom
    rofi
    scrot
)

_TERMINAL=(
    kitty
    zsh
    zsh-autosuggestions
    zsh-syntax-highlighting
)

_CLI=(
    bat
    btop
    eza
    fd
    fzf
    glow
    jq
    ripgrep
    tree
    unp
    unrar
    unzip
    yazi
    zoxide
)

_DEV=(
    docker
    docker-compose
    git
    neovim
    python
    rustup
    uv
)

_APPS=(
    firefox
    keepassxc
)

_MEDIA=(
    ffmpeg
    imagemagick
    mpv
    yt-dlp
)

_GAMING=(
    gamemode
    lib32-gamemode
    lib32-mangohud
    mangohud
    steam
)

_FONTS=(
    noto-fonts
    noto-fonts-cjk
    noto-fonts-emoji
    noto-fonts-extra
    ttf-dejavu
    ttf-liberation
    ttf-mononoki-nerd
)

_MAINTENANCE=(
    fwupd
    pacman-contrib
    power-profiles-daemon
    reflector
)

readonly PACMAN_PACKAGES=(
    "${_BASE[@]}"
    "${_BOOT[@]}"
    "${_AUDIO[@]}"
    "${_VIDEO[@]}"
    "${_NETWORK[@]}"
    "${_XORG[@]}"
    "${_DESKTOP[@]}"
    "${_TERMINAL[@]}"
    "${_CLI[@]}"
    "${_DEV[@]}"
    "${_APPS[@]}"
    "${_MEDIA[@]}"
    "${_GAMING[@]}"
    "${_FONTS[@]}"
    "${_MAINTENANCE[@]}"
)

readonly PARU_PACKAGES=(
    shellcheck-bin
    spotifast-bin
    vesktop-bin
    zapfast-bin
)
