#! /usr/bin/env bash

set -euo pipefail

exec > >(tee install.log) 2>&1 || true

# Must be a valid block device without the partition number.
# Run `fdisk -l` for possible values.
readonly DRIVE='/dev/sda'

# Run `localectl list-keymaps` for possible values.
readonly KEYMAP='us'

# Run `cat /etc/locale.gen` for possible values.
readonly LOCALES=('en_US.UTF-8 UTF-8' 'es_ES.UTF-8 UTF-8' 'ja_JP.UTF-8 UTF-8')

# Must follow the format "Zone/Location".
readonly TIMEZONE='Europe/Madrid'

readonly USERNAME='motxi'
readonly HOSTNAME='arch'

readonly R='\033[1;31m' # Red
readonly G='\033[1;32m' # Green
readonly B='\033[1;34m' # Blue
readonly S='\033[0m' # Reset

# The chroot script must live next to this one.
readonly SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly CHROOT_SCRIPT="${SCRIPT_DIR}/chroot.sh"
readonly CHROOT_SCRIPT_DEST='/root/chroot.sh'

MOUNTED=0

say() {
    local color=$1
    local message=${2:-}

    case "${color}" in
        'red') color="${R}" ;;
        'green') color="${G}" ;;
        'blue') color="${B}" ;;
        *) color="${S}" ;;
    esac

    echo -e "${color}${message}${S}" >&2
}

die() {
    echo
    say red "$1"

    exit 1
}

password() {
    local user=$1

    say blue "Set the password for ${user}:"

    until arch-chroot /mnt passwd "${user}"; do
        say red 'Password not set. Try again.'
    done
}

cleanup() {
    local status=$?

    trap - EXIT

    if (( MOUNTED )); then
        rm --force "/mnt${CHROOT_SCRIPT_DEST}"

        say green 'Unmounting /mnt...'
        umount --recursive /mnt || die 'Failed to unmount /mnt.'
    fi

    exit "${status}"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

setfont ter-120b || true

(( EUID == 0 )) || die 'This script must be run as root.'

if mountpoint --quiet /mnt; then
    say blue 'Unmounting previous /mnt...'
    umount --recursive /mnt || die 'Failed to unmount /mnt.'
fi

curl --fail --silent --head --max-time 5 https://archlinux.org > /dev/null \
    || die 'No internet connection. Connect to the network and try again.'

platform_size=$(cat /sys/firmware/efi/fw_platform_size 2> /dev/null || true)

[[ "${platform_size}" == @(32|64) ]] || die 'This script only works in UEFI mode.'
[[ -f /usr/bin/pacstrap ]] || die 'This script must be run from a valid installation environment.'
[[ -b "${DRIVE}" ]] || die 'The selected drive is not a valid block device.'
[[ -f "${CHROOT_SCRIPT}" ]] || die "Missing chroot script: ${CHROOT_SCRIPT}."

loadkeys "${KEYMAP}" || die "Failed to load keymap ${KEYMAP}."
timedatectl set-ntp true

say blue "Arch Linux will be installed in ${DRIVE}."
say red 'The drive will be completely wiped.'
say red 'This CAN NOT be undone.'
say ''

say blue "Type '${DRIVE}' to confirm:"
say ''

read -r decision

[[ "${decision}" == "${DRIVE}" ]] || die 'Installation aborted by the user.'

wipefs --all "${DRIVE}" || die 'Failed to wipe filesystem signatures.'
sgdisk --zap-all "${DRIVE}" || die 'Failed to wipe the drive data structures.'

say green "The drive ${DRIVE} has been successfully wiped."
say green 'Now the drive will be partitioned.'

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
    || die 'Disk partitioning failed.'

udevadm settle

# NVMe and MMC devices name their partitions using the "<drive>p<N>" format
# instead of "<drive><N>".
PART_PREFIX="${DRIVE}"

if [[ "${DRIVE}" == *[0-9] ]]; then
    PART_PREFIX+='p'
fi

mkfs.fat -F 32 -n EFI "${PART_PREFIX}1"
mkfs.ext4 -L ROOT "${PART_PREFIX}2"

mount "${PART_PREFIX}2" /mnt
MOUNTED=1
mount --mkdir --options umask=0077 "${PART_PREFIX}1" /mnt/boot

pacstrap -K /mnt base

# Generate and cleanup the fstab file (personal preference).
genfstab -t PARTUUID /mnt | tr -s '[:blank:]' ' ' > /mnt/etc/fstab

# Arrays can't be passed through the environment, so the locales are written
# from outside the chroot.
printf '%s\n' "${LOCALES[@]}" > /mnt/etc/locale.gen

ROOT_PARTUUID=$(blkid --match-tag PARTUUID --output value "${PART_PREFIX}2")

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
# which is the ESP (mounted at /boot).
#
# This heredoc is intentionally unquoted so ${ROOT_PARTUUID} gets expanded.
cat > /mnt/boot/limine.conf << LIMINE
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

# Copy the chroot script into the new system and run it there. The values it
# needs are passed explicitly through the environment and the copy is removed
# afterwards (or by the cleanup trap if anything fails).
install --mode 0700 "${CHROOT_SCRIPT}" "/mnt${CHROOT_SCRIPT_DEST}"

arch-chroot /mnt /usr/bin/env \
    TIMEZONE="${TIMEZONE}" \
    KEYMAP="${KEYMAP}" \
    HOSTNAME="${HOSTNAME}" \
    USERNAME="${USERNAME}" \
    DRIVE="${DRIVE}" \
    bash "${CHROOT_SCRIPT_DEST}" \
    || die 'The chroot script failed.'

rm --force "/mnt${CHROOT_SCRIPT_DEST}"

set_password root
set_password "${USERNAME}"

say green 'Installation successfully finished!'
say green 'You may reboot now'
