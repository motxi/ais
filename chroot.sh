# Not meant to be run directly.
# Copied into the new system and executed inside the chroot by "install.sh".

set -euo pipefail

source "$(dirname "$0")/utils.sh"
source "$(dirname "$0")/packages.sh"

[[ -n "${TIMEZONE:-}" ]] || die 'TIMEZONE must be set by "install.sh".'
[[ -n "${KEYMAP:-}" ]] || die 'KEYMAP must be set by "install.sh".'
[[ -n "${HOSTNAME:-}" ]] || die 'HOSTNAME must be set by "install.sh".'
[[ -n "${USERNAME:-}" ]] || die 'USERNAME must be set by "install.sh".'
[[ -n "${DRIVE:-}" ]] || die 'DRIVE must be set by "install.sh".'

readonly PARU_SUDOERS='/etc/sudoers.d/99-paru-install'

say blue "Setting the timezone to \"${TIMEZONE}\"..."

ln --symbolic --force "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime \
    || die "Failed to set the timezone to \"${TIMEZONE}\"."

hwclock --systohc || die 'Failed to sync the hardware clock.'

say blue 'Generating the locales...'

locale-gen || die 'Failed to generate the locales.'

echo 'LANG=en_US.UTF-8' > /etc/locale.conf
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf

say blue "Setting the hostname to \"${HOSTNAME}\"..."

echo "${HOSTNAME}" > /etc/hostname

cat > /etc/hosts << HOSTS || die 'Failed to write the hosts file.'
127.0.0.1 localhost.localdomain localhost
::1 localhost.localdomain localhost
127.0.1.1 ${HOSTNAME}.localdomain ${HOSTNAME}
HOSTS

say blue 'Enabling the multilib repository...'

# Enable multilib packages in pacman.
sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' /etc/pacman.conf \
    || die 'Failed to enable the multilib repository.'

say blue "Installing ${#PACMAN_PACKAGES[@]} packages from the official repositories. This can take a while..."

pacman --sync --refresh --refresh --sysupgrade --noconfirm --color always "${PACMAN_PACKAGES[@]}" \
    || die 'Failed to install the official packages.'

say green 'The official packages have been installed.'

say blue 'Configuring and rebuilding the initramfs...'

# Load amdgpu in the initramfs (early KMS).
mkdir --parents /etc/mkinitcpio.conf.d
echo 'MODULES+=(amdgpu)' > /etc/mkinitcpio.conf.d/amdgpu.conf

cat > /etc/mkinitcpio.conf.d/hooks.conf << 'HOOKS' || die 'Failed to write the initramfs hooks.'
HOOKS=(base udev autodetect microcode modconf consolefont kms keyboard keymap block filesystems fsck encrypt)
HOOKS

# Rebuild because the kernel package already generated the initramfs.
mkinitcpio --allpresets || die 'Failed to rebuild the initramfs.'

say green 'The initramfs has been rebuilt.'

say blue 'Installing the Limine bootloader...'

# Install Limine in the dedicated directory and in the UEFI fallback path, which
# firmware uses when it drops the efibootmgr entry.
mkdir --parents /boot/EFI/limine /boot/EFI/BOOT

cp /usr/share/limine/BOOTX64.EFI /boot/EFI/limine/
cp /usr/share/limine/BOOTX64.EFI /boot/EFI/BOOT/

say blue 'Creating the UEFI boot entry...'

efibootmgr \
    --create \
    --disk "${DRIVE}" \
    --part 1 \
    --label 'Limine' \
    --loader '\EFI\limine\BOOTX64.EFI' \
    --unicode \
    || say red 'Could not create the UEFI entry for Limine. The fallback path will be used.'

say blue 'Adding a pacman hook to keep Limine up to date...'

# Keep the copies of the Limine binary up to date when the package is upgraded.
mkdir --parents /etc/pacman.d/hooks

cat > /usr/local/bin/limine-deploy << 'LIMINE_DEPLOY' || die 'Failed to write the Limine deploy script.'
#! /usr/bin/env bash

set -euo pipefail

for dir in limine BOOT; do
    cp /usr/share/limine/BOOTX64.EFI "/boot/EFI/${dir}/"
done
LIMINE_DEPLOY

chmod 0755 /usr/local/bin/limine-deploy

cat > /etc/pacman.d/hooks/limine-deploy.hook << 'LIMINE_HOOK' || die 'Failed to write the Limine pacman hook.'
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

say green 'The Limine bootloader has been installed.'

say blue "Creating the user \"${USERNAME}\"..."

useradd --create-home --groups wheel,docker,gamemode "${USERNAME}" \
    || die "Failed to create the user \"${USERNAME}\"."

echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
chmod 0440 /etc/sudoers.d/10-wheel

say blue 'Granting temporary passwordless sudo for the AUR build...'

# The `makepkg` script refuses to run as root, so paru and the AUR packages are
# built as the new user. `makepkg` and `paru` call `sudo pacman`, and there is
# no password prompt in a script, so a temporary passwordless rule is granted
# and always removed afterwards, even if the build fails.
echo "${USERNAME} ALL=(ALL:ALL) NOPASSWD: ALL" > "${PARU_SUDOERS}"
chmod 0440 "${PARU_SUDOERS}"

trap 'rm --force "${PARU_SUDOERS}"' EXIT

say blue "Building paru and installing ${#PARU_PACKAGES[@]} AUR packages. This can take a while..."

# `-l` gives a login shell so `HOME` and `PATH` are the user's, not root's.
runuser -l "${USERNAME}" -c "
    set -euo pipefail

    rustup default stable

    git clone https://aur.archlinux.org/paru.git /tmp/paru
    cd /tmp/paru

    makepkg --syncdeps --install --noconfirm
    rm --recursive --force /tmp/paru

    paru --sync --skipreview --noconfirm ${PARU_PACKAGES[*]}
" || die 'Failed to build paru or install the AUR packages.'

say blue 'Removing the temporary passwordless sudo rule...'

rm --force "${PARU_SUDOERS}"
trap - EXIT

say green 'The AUR packages have been installed.'

say blue 'Enabling the system services and timers...'

systemctl enable \
    dhcpcd.service docker.service lactd.service power-profiles-daemon.service systemd-timesyncd.service \
    fstrim.timer fwupd-refresh.timer paccache.timer pacman-filesdb-refresh.timer reflector.timer \
    || die 'Failed to enable the system services and timers.'

say blue 'Enabling the user services for everyone...'

# Trying to use `--user` here fails in chroot because there is no running user
# manager or D-Bus session to talk to.
systemctl enable --global pipewire.service pipewire-pulse.service wireplumber.service \
    || die 'Failed to enable the user services.'

say blue 'Enabling the Ly display manager on "tty2"...'

# The TTY service that Ly will run on must be disabled.
systemctl enable ly@tty2.service || die 'Failed to enable "ly@tty2.service".'
systemctl disable getty@tty2.service || die 'Failed to disable "getty@tty2.service".'

say green 'All services have been enabled.'
