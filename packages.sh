#! /usr/bin/env bash

readonly _BASE=(
    base
    base-devel
    linux
    linux-firmware
    amd-ucode
    man-db
    man-pages
    polkit
)

readonly _BOOT=(
    dosfstools
    efibootmgr
    limine
    memtest86+-efi
)

readonly _AUDIO=(
    pipewire
    pipewire-alsa
    pipewire-jack
    pipewire-pulse
    playerctl
    wireplumber
    headsetcontrol
)

readonly _VIDEO=(
    lact
    lib32-mesa
    lib32-vulkan-radeon
    libva-utils
    mesa
    nvtop
    vulkan-radeon
)

readonly _NETWORK=(
    dhcpcd
    openssh
    sshfs
    wget
)

readonly _XORG=(
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

readonly _DESKTOP=(
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

readonly _TERMINAL=(
    kitty
    zsh
    zsh-autosuggestions
    zsh-syntax-highlighting
)

readonly _CLI=(
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

readonly _DEV=(
    docker
    docker-compose
    git
    neovim
    python
    rustup
    uv
)

readonly _APPS=(
    firefox
    keepassxc
)

readonly _MEDIA=(
    ffmpeg
    imagemagick
    mpv
    yt-dlp
)

readonly _GAMING=(
    gamemode
    lib32-gamemode
    lib32-mangohud
    mangohud
    steam
)

readonly _FONTS=(
    noto-fonts
    noto-fonts-cjk
    noto-fonts-emoji
    noto-fonts-extra
    ttf-dejavu
    ttf-liberation
    ttf-mononoki-nerd
)

readonly _MAINTENANCE=(
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
