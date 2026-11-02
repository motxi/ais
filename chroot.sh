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

source "$(dirname "$0")/packages.sh"

ln --symbolic --force "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
hwclock --systohc

locale-gen

echo 'LANG=en_US.UTF-8' > /etc/locale.conf
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf
echo "${HOSTNAME}" > /etc/hostname

cat > /etc/hosts << HOSTS
127.0.0.1 localhost.localdomain localhost
::1 localhost.localdomain localhost
127.0.1.1 ${HOSTNAME}.localdomain ${HOSTNAME}
HOSTS

# Enable multilib packages in pacman.
sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' /etc/pacman.conf

pacman --sync --refresh --refresh --sysupgrade --noconfirm --color always "${PACMAN_PACKAGES[@]}"

# Load amdgpu in the initramfs (early KMS).
mkdir --parents /etc/mkinitcpio.conf.d
echo 'MODULES+=(amdgpu)' > /etc/mkinitcpio.conf.d/amdgpu.conf

cat > /etc/mkinitcpio.conf.d/hooks.conf << 'HOOKS'
HOOKS=(base udev autodetect microcode modconf consolefont kms keyboard keymap block filesystems fsck encrypt)
HOOKS

# Rebuild because the kernel package already generated the initramfs.
mkinitcpio --allpresets

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
    --unicode \
    || echo 'Could not create the UEFI entry for Limine.'

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

useradd --create-home --groups wheel,docker,gamemode "${USERNAME}"
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
chmod 0440 /etc/sudoers.d/10-wheel

systemctl enable \
    dhcpcd.service docker.service lact.service power-profiles-daemon.service systemd-timesyncd.service \
    fstrim.timer fwupd-refresh.timer paccache.timer pacman-filesdb-refresh.timer reflector.timer

# Trying to use "--user" here fails in chroot because there is no running user
# manager or D-Bus session to talk to.
systemctl enable --global pipewire.service pipewire-pulse.service wireplumber.service

# The TTY service that Ly will run on must be disabled.
systemctl enable ly@tty2.service
systemctl disable getty@tty2.service
