#! /usr/bin/env bash

# This script is not meant to be run directly. It is copied into the new system
# and executed inside the chroot by "install.sh", which passes the values below
# through the environment.

set -euo pipefail

: "${TIMEZONE:?Must be set by install.sh}"
: "${KEYMAP:?Must be set by install.sh}"
: "${HOSTNAME:?Must be set by install.sh}"
: "${USERNAME:?Must be set by install.sh}"
: "${DRIVE:?Must be set by install.sh}"

ln --symbolic --force "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
hwclock --systohc

locale-gen

echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf
echo "${HOSTNAME}" > /etc/hostname

cat > /etc/hosts << HOSTS
127.0.0.1 localhost.localdomain localhost
::1 localhost.localdomain localhost
127.0.1.1 ${HOSTNAME}.localdomain ${HOSTNAME}
HOSTS

# Enable multilib packages in pacman.
sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' /etc/pacman.conf

pacman --sync --refresh --refresh --sysupgrade --noconfirm --color always \
    amd-ucode arandr \
    bash-completion base base-devel btop \
    dex dhcpcd docker docker-compose dosfstools dunst \
    efibootmgr \
    fd feh ffmpeg firefox fzf \
    gcc git \
    i3-wm i3lock i3status imagemagick \
    jq \
    keepassxc kitty \
    lib32-mesa lib32-vulkan-radeon libva-utils limine linux linux-firmware ly \
    man-db man-pages mesa memtest86+-efi mpv \
    neovim noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra \
    openssh \
    pacman-contrib picom pipewire pipewire-pulse polkit python \
    reflector ripgrep rofi rustup \
    shellcheck sshfs \
    tree ttf-dejavu ttf-liberation ttf-mononoki-nerd \
    unp unrar unzip \
    vulkan-radeon \
    wget wireplumber \
    xclip xdg-user-dirs xdg-utils xorg-xauth xorg-server xorg-xinit xorg-xrandr xorg-xset xsel xss-lock \
    yazi yt-dlp \
    zoxide

# Install Limine in the dedicated directory and in the UEFI fallback path, which
# firmware uses when it drops the efibootmgr entry.
mkdir --parents /boot/EFI/limine /boot/EFI/BOOT

cp /usr/share/limine/BOOTX64.EFI /boot/EFI/limine/
cp /usr/share/limine/BOOTX64.EFI /boot/EFI/BOOT/

efibootmgr \
    --create \
    --disk "${DRIVE}" \
    --part 1 \
    --label 'Limine' \
    --loader '\EFI\limine\BOOTX64.EFI' \
    --unicode

# Keep the copies of the Limine binary up to date when the package is upgraded.
mkdir --parents /etc/pacman.d/hooks

cat > /usr/local/bin/limine-deploy << 'LIMINE_DEPLOY'
#! /usr/bin/env bash

set -euo pipefail

for dir in limine BOOT; do
    cp /usr/share/limine/BOOTX64.EFI "/boot/EFI/${dir}/"
done
LIMINE_DEPLOY

chmod 0755 /usr/local/bin/limine-deploy

cat > /etc/pacman.d/hooks/limine-deploy.hook << 'LIMINE_HOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = limine

[Action]
Description = Deploying Limine to the ESP...
When = PostTransaction
Exec = /usr/local/bin/limine-deploy
LIMINE_HOOK

useradd --create-home --groups wheel "${USERNAME}"
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
chmod 0440 /etc/sudoers.d/10-wheel

systemctl enable dhcpcd systemd-timesyncd docker ly@tty2.service

# The TTY service that Ly will run on must be disabled.
systemctl disable getty@tty2.service
