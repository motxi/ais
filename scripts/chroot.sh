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

say blue "Setting the timezone to \"${TIMEZONE}\" and syncing the hardware clock..."
ln --symbolic --force "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
hwclock --systohc

say blue 'Generating the locales...'
locale-gen

say blue "Setting the system language and the console keymap (\"${KEYMAP}\")..."
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf

say blue "Setting the hostname to \"${HOSTNAME}\"..."
echo "${HOSTNAME}" > /etc/hostname

cat > /etc/hosts << HOSTS
127.0.0.1 localhost.localdomain localhost
::1 localhost.localdomain localhost
127.0.1.1 ${HOSTNAME}.localdomain ${HOSTNAME}
HOSTS

say green 'The time, language and hostname settings have been applied.'

# Enable multilib packages in pacman.
say blue 'Enabling the multilib repository...'
sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' /etc/pacman.conf

say blue "Installing ${#PACMAN_PACKAGES[@]} packages from the official repositories. This can take a while..."
pacman --sync --refresh --refresh --sysupgrade --noconfirm --color always "${PACMAN_PACKAGES[@]}"

say green 'The official packages have been installed.'

# Load amdgpu in the initramfs (early KMS).
say blue 'Configuring the initramfs (early amdgpu KMS)...'
mkdir --parents /etc/mkinitcpio.conf.d
echo 'MODULES+=(amdgpu)' > /etc/mkinitcpio.conf.d/amdgpu.conf

cat > /etc/mkinitcpio.conf.d/hooks.conf << 'HOOKS'
HOOKS=(base udev autodetect microcode modconf consolefont kms keyboard keymap block filesystems fsck)
HOOKS

# Rebuild because the kernel package already generated the initramfs.
say blue 'Rebuilding the initramfs...'
mkinitcpio --allpresets

say green 'The initramfs has been rebuilt.'

# Install Limine in the dedicated directory and in the UEFI fallback path, which
# firmware uses when it drops the efibootmgr entry.
say blue 'Copying the Limine bootloader to the EFI partition...'
mkdir --parents /boot/EFI/limine /boot/EFI/BOOT

cp /usr/share/limine/BOOTX64.EFI /boot/EFI/limine/
cp /usr/share/limine/BOOTX64.EFI /boot/EFI/BOOT/

say blue 'Creating the UEFI boot entry...'

if efibootmgr \
    --create \
    --disk "${DRIVE}" \
    --part 1 \
    --label 'Limine' \
    --loader '\EFI\limine\BOOTX64.EFI' \
    --unicode; then
    say green 'The UEFI boot entry has been created.'
else
    say red 'Could not create the UEFI boot entry. The fallback path will be used instead.'
fi

# Keep the copies of the Limine binary up to date when the package is upgraded.
say blue 'Adding a pacman hook to keep Limine up to date...'
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

say green 'The Limine bootloader has been installed.'

say blue "Creating the user \"${USERNAME}\" and allowing the wheel group to use sudo..."
useradd --create-home --groups wheel,docker,gamemode "${USERNAME}"

echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
chmod 0440 /etc/sudoers.d/10-wheel

say green "The user \"${USERNAME}\" has been created."

# The `makepkg` script refuses to run as root, so paru and the AUR packages are
# built as the new user. `makepkg` and `paru` call `sudo pacman`, and there is
# no password prompt in a script, so a temporary passwordless rule is granted
# and always removed afterwards, even if the build fails.
say blue 'Granting temporary passwordless sudo for the AUR packages...'
echo "${USERNAME} ALL=(ALL:ALL) NOPASSWD: ALL" > "${PARU_SUDOERS}"
chmod 0440 "${PARU_SUDOERS}"

trap 'rm --force "${PARU_SUDOERS}"' EXIT

# `-l` gives a login shell so `HOME` and `PATH` are the user's, not root's.
say blue "Installing paru and ${#PARU_PACKAGES[@]} AUR packages (${PARU_PACKAGES[*]}). This can take a while..."
runuser -l "${USERNAME}" -c "
    set -euo pipefail

    git clone https://aur.archlinux.org/paru-bin.git /tmp/paru-bin
    cd /tmp/paru-bin

    makepkg --syncdeps --install --noconfirm
    rm --recursive --force /tmp/paru-bin

    paru --sync --skipreview --noconfirm ${PARU_PACKAGES[*]}
" || die 'Failed to install paru or the AUR packages.'

say green 'Paru and the AUR packages have been installed.'

say blue 'Removing the temporary passwordless sudo rule...'
rm --force "${PARU_SUDOERS}"

trap - EXIT

# Unlock the login keyring with the login password, so the Secret Service is
# ready without opening any database.
say blue 'Enabling the login keyring for Ly...'
cat >> /etc/pam.d/ly << 'PAM'
auth optional pam_gnome_keyring.so
session optional pam_gnome_keyring.so auto_start
PAM

say blue 'Enabling the system services and timers...'
systemctl enable \
    dhcpcd.service docker.service lactd.service power-profiles-daemon.service systemd-timesyncd.service \
    fstrim.timer fwupd-refresh.timer paccache.timer pacman-filesdb-refresh.timer reflector.timer

# Trying to use `--user` here fails in chroot because there is no running user
# manager or D-Bus session to talk to.
say blue 'Enabling the user services for all users...'
systemctl enable --global pipewire.service pipewire-pulse.service wireplumber.service

# The TTY service that Ly will run on must be disabled.
say blue 'Enabling the Ly display manager on "tty2"...'
systemctl enable ly@tty2.service
systemctl disable getty@tty2.service

say green 'All services have been enabled.'
