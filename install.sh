#! /usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

exec > >(tee "${SCRIPT_DIR}/install.log") 2>&1

readonly UTILS_SCRIPT="${SCRIPT_DIR}/utils.sh"

[[ -f "${UTILS_SCRIPT}" ]] || {
    echo "Missing utils script: \"${UTILS_SCRIPT}\"." >&2
    exit 1
}

readonly CONFIG_SCRIPT="${SCRIPT_DIR}/config.sh"
readonly CHROOT_SCRIPT="${SCRIPT_DIR}/chroot.sh"
readonly PACKAGES_SCRIPT="${SCRIPT_DIR}/packages.sh"

readonly CHROOT_SCRIPT_DEST='/root/chroot.sh'
readonly PACKAGES_SCRIPT_DEST='/root/packages.sh'
readonly UTILS_SCRIPT_DEST='/root/utils.sh'

source "${UTILS_SCRIPT}"

[[ -f "${CONFIG_SCRIPT}" ]] || die "Missing config script: \"${CONFIG_SCRIPT}\"."
[[ -f "${CHROOT_SCRIPT}" ]] || die "Missing chroot script: \"${CHROOT_SCRIPT}\"."
[[ -f "${PACKAGES_SCRIPT}" ]] || die "Missing packages script: \"${PACKAGES_SCRIPT}\"."

# Bash always sets `HOSTNAME` itself, so clear it to detect a missing value.
unset HOSTNAME

source "${CONFIG_SCRIPT}"

[[ -n "${DRIVE:-}" ]] || die 'DRIVE must be set in "config.sh".'
[[ -n "${KEYMAP:-}" ]] || die 'KEYMAP must be set in "config.sh".'
[[ -n "${TIMEZONE:-}" ]] || die 'TIMEZONE must be set in "config.sh".'
[[ -n "${USERNAME:-}" ]] || die 'USERNAME must be set in "config.sh".'
[[ -n "${HOSTNAME:-}" ]] || die 'HOSTNAME must be set in "config.sh".'
(( ${#LOCALES[@]} )) || die 'LOCALES must not be empty in "config.sh".'

readonly DRIVE KEYMAP LOCALES TIMEZONE USERNAME HOSTNAME

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

setfont ter-120b || true

say blue 'Checking the installation environment...'

(( EUID == 0 )) || die 'This script must be run as root.'

if mountpoint --quiet /mnt; then
    say blue 'Unmounting previous "/mnt"...'
    umount --recursive /mnt || die 'Failed to unmount "/mnt".'
fi

say blue 'Checking the internet connection...'

curl --fail --silent --head --max-time 5 https://archlinux.org > /dev/null \
    || die 'No internet connection. Connect to the network and try again.'

say blue 'Checking the boot mode and the target drive...'

platform_size=$(cat /sys/firmware/efi/fw_platform_size 2> /dev/null || true)

[[ "${platform_size}" == @(32|64) ]] || die 'This script only works in UEFI mode.'
[[ -f /usr/bin/pacstrap ]] || die 'This script must be run from a valid installation environment.'
[[ -b "${DRIVE}" ]] || die "The selected drive \"${DRIVE}\" is not a valid block device."

say green "UEFI mode detected (${platform_size}-bit) and \"${DRIVE}\" is a valid drive."

say blue "Loading the keymap \"${KEYMAP}\"..."
loadkeys "${KEYMAP}" || die "Failed to load the keymap \"${KEYMAP}\"."

say blue 'Enabling time synchronization (NTP)...'
timedatectl set-ntp true || die 'Failed to enable time synchronization.'

clear || true

say blue 'Installation summary:'
say ''

say blue "    - Drive    : ${DRIVE}"
say blue "    - Keymap   : ${KEYMAP}"
say blue "    - Timezone : ${TIMEZONE}"
say blue "    - Locales  : ${LOCALES[*]}"
say blue "    - Username : ${USERNAME}"
say blue "    - Hostname : ${HOSTNAME}"
say ''

say blue "Arch Linux will be installed in \"${DRIVE}\"."
say red 'The drive will be completely wiped.'
say red 'This CAN NOT be undone.'
say ''

say blue "Type \"${DRIVE}\" to confirm:"
say ''

read -r decision

[[ "${decision}" == "${DRIVE}" ]] || die 'Installation aborted by the user.'

clear || true

say blue "Wiping \"${DRIVE}\"..."

wipefs --all "${DRIVE}" || die 'Failed to wipe the filesystem signatures.'
sgdisk --zap-all "${DRIVE}" || die 'Failed to wipe the drive data structures.'

say green "The drive \"${DRIVE}\" has been successfully wiped."
say green 'Now the drive will be partitioned...'

# Feel free to modify the partitioning structure as you like.
#
# The current setup creates a 512 MiB FAT32 EFI partition (1) and the rest is
# used for the ext4 ROOT partition (2).
#
# For more information about partition type GUIDs refer to:
# https://en.wikipedia.org/wiki/GUID_Partition_Table#Partition_type_GUIDs
#
# Make sure to also modify the partition formatting/mounting structure below if
# you change anything here.
parted "${DRIVE}" --script --align minimal \
    mklabel gpt \
    mkpart EFI fat32 1MiB 513MiB \
    mkpart ROOT ext4 513MiB 100% \
    type 1 C12A7328-F81F-11D2-BA4B-00A0C93EC93B \
    type 2 4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709 \
    align-check minimal 1 \
    align-check minimal 2 \
    || die 'Failed to partition the drive.'

udevadm settle || die 'Failed to wait for the partitions to be ready.'

# NVMe and MMC devices name their partitions using the "<drive>p<N>" format
# instead of "<drive><N>".
PART_PREFIX="${DRIVE}"

if [[ "${DRIVE}" == *[0-9] ]]; then
    PART_PREFIX+='p'
fi

say green "Created the EFI partition (${PART_PREFIX}1)."
say green "Created the ROOT partition (${PART_PREFIX}2)."

say blue "Formatting ${PART_PREFIX}1 as FAT32 (EFI)..."
mkfs.fat -F 32 -n EFI "${PART_PREFIX}1" || die "Failed to format \"${PART_PREFIX}1\" as FAT32."

say blue "Formatting ${PART_PREFIX}2 as ext4 (ROOT)..."
mkfs.ext4 -L ROOT "${PART_PREFIX}2" || die "Failed to format \"${PART_PREFIX}2\" as ext4."

say blue 'Mounting the partitions...'

mount "${PART_PREFIX}2" /mnt || die "Failed to mount \"${PART_PREFIX}2\" at \"/mnt\"."
MOUNTED=1
mount --mkdir --options umask=0077 "${PART_PREFIX}1" /mnt/boot \
    || die "Failed to mount \"${PART_PREFIX}1\" at \"/mnt/boot\"."

say green 'ROOT partition mounted at "/mnt".'
say green 'EFI partition mounted at "/mnt/boot".'

say blue 'Installing the base system. This can take a few minutes...'

pacstrap -K /mnt base || die 'Failed to install the base system.'

say green 'The base system has been installed.'

say blue 'Generating the fstab file...'

# Generate and cleanup the fstab file (personal preference).
genfstab -t PARTUUID /mnt | tr -s '[:blank:]' ' ' > /mnt/etc/fstab \
    || die 'Failed to generate the fstab file.'

say blue 'Writing the locales...'

# Arrays can't be passed through the environment, so the locales are written
# from outside the chroot.
printf '%s\n' "${LOCALES[@]}" > /mnt/etc/locale.gen \
    || die 'Failed to write the locales.'

say blue 'Writing the Limine boot configuration...'

ROOT_PARTUUID=$(blkid --match-tag PARTUUID --output value "${PART_PREFIX}2") \
    || die "Failed to read the PARTUUID of \"${PART_PREFIX}2\"."

PP_FEATURE_MASK_PATH='/sys/module/amdgpu/parameters/ppfeaturemask'
default_mask='0xfff7bfff'

if [[ -r "${PP_FEATURE_MASK_PATH}" ]]; then
    default_mask=$(<"${PP_FEATURE_MASK_PATH}")
fi

# The amdgpu's default ppfeaturemask with the overdrive bit (0x4000) set, which
# unlocks overclocking and undervolting. Falls back to the kernel default when
# the amdgpu module isn't loaded in the live environment.
PP_FEATURE_MASK=$(printf '0x%x' $(( default_mask | 0x4000 )))

# Limine looks for its config in the root of the partition it was loaded from,
# which is the ESP (mounted at "/boot").
#
# This heredoc is intentionally unquoted so `${ROOT_PARTUUID}` gets expanded.
cat > /mnt/boot/limine.conf << LIMINE || die 'Failed to write the Limine configuration.'
timeout: 5

/Arch Linux
    protocol: linux
    path: boot():/vmlinuz-linux
    cmdline: root=PARTUUID=${ROOT_PARTUUID} rw amdgpu.ppfeaturemask=${PP_FEATURE_MASK}
    module_path: boot():/amd-ucode.img
    module_path: boot():/initramfs-linux.img

/Memtest86+
    protocol: efi
    path: boot():/memtest86+/memtest86x64.efi
LIMINE

say green "Limine configuration written (PP_FEATURE_MASK = ${PP_FEATURE_MASK})."

say blue 'Copying the chroot scripts into the new system...'

# Copy the chroot script into the new system and run it there. The values it
# needs are passed explicitly through the environment and the copy is removed
# afterwards (or by the cleanup trap if anything fails).
install --mode 0700 "${CHROOT_SCRIPT}" "/mnt${CHROOT_SCRIPT_DEST}" \
    || die 'Failed to copy the chroot script.'

# Copy the "packages.sh" and "utils.sh" scripts too, since the chroot script
# sources them.
install --mode 0600 "${PACKAGES_SCRIPT}" "/mnt${PACKAGES_SCRIPT_DEST}" \
    || die 'Failed to copy the packages script.'

install --mode 0600 "${UTILS_SCRIPT}" "/mnt${UTILS_SCRIPT_DEST}" \
    || die 'Failed to copy the utils script.'

say blue 'Configuring the system inside the chroot...'
say blue 'This installs all the packages, the bootloader and the services, so it will take a while...'

arch-chroot /mnt /usr/bin/env \
    TIMEZONE="${TIMEZONE}" \
    KEYMAP="${KEYMAP}" \
    HOSTNAME="${HOSTNAME}" \
    USERNAME="${USERNAME}" \
    DRIVE="${DRIVE}" \
    bash "${CHROOT_SCRIPT_DEST}" \
    || die 'The chroot script failed.'

say green 'The system has been configured.'

say blue 'Removing the temporary installation scripts...'
rm --force "/mnt${CHROOT_SCRIPT_DEST}" "/mnt${PACKAGES_SCRIPT_DEST}" "/mnt${UTILS_SCRIPT_DEST}"

password root
password "${USERNAME}"

clear || true

say green 'Installation successfully finished!'
say green 'You may reboot now.'
