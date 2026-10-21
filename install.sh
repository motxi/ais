#! /usr/bin/env bash

set -euo pipefail

exec > >(tee install.log) 2>&1

# Must be a valid block device without the partition number.
# Run `fdisk -l` for possible values.
DRIVE="/dev/sda"

# Run `localectl list-keymaps` for possible values.
KEYMAP="us"

# Run `cat /etc/locale.gen` for possible values.
LOCALES=("en_US.UTF-8 UTF-8" "es_ES.UTF-8 UTF-8" "ja_JP.UTF-8 UTF-8")

# Must follow the format "Zone/Location".
TIMEZONE="Europe/Madrid"

USERNAME="motxi"
HOSTNAME="arch"

R='\033[0;31m' # Red
G='\033[0;32m' # Green
B='\033[0;34m' # Blue
S='\033[0m' # Reset

# The chroot script must live next to this one.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CHROOT_SCRIPT="${SCRIPT_DIR}/chroot.sh"
CHROOT_SCRIPT_DEST="/root/chroot.sh"

MOUNTED=0

die() {
    local message=$1

    echo
    echo -e "${R}${message}${S}" >&2

    exit 1
}

cleanup() {
    local status=$?

    trap - EXIT

    if (( MOUNTED )); then
        rm --force "/mnt${CHROOT_SCRIPT_DEST}"

        echo "Unmounting /mnt..."
        umount --recursive /mnt || die "Failed to unmount /mnt."
    fi

    exit "$status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

setfont ter-120b

(( EUID == 0 )) || die "This script must be run as root."

curl --fail --silent --head --max-time 5 https://archlinux.org > /dev/null \
    || die "No internet connection. Connect to the network and try again."

platform_size=$(cat /sys/firmware/efi/fw_platform_size 2> /dev/null || true)

[[ "$platform_size" == @(32|64) ]] || die "This script only works in UEFI mode."
[[ -f /usr/bin/pacstrap ]] || die "This script must be run from a valid installation environment."
[[ -b "$DRIVE" ]] || die "The selected drive is not a valid block device."
[[ -f "$CHROOT_SCRIPT" ]] || die "Missing chroot script: ${CHROOT_SCRIPT}."

loadkeys "$KEYMAP" || die "Failed to load keymap ${KEYMAP}."
timedatectl set-ntp true

echo -e "Arch Linux will be installed in ${B}${DRIVE}${S}."
echo
echo -e "The drive will be ${R}completely${S} wiped."
echo -e "This ${R}CAN NOT${S} be undone."
echo

echo -en "Type ${B}${DRIVE}${S} to confirm: "
read -r decision

[[ "$decision" == "$DRIVE" ]] || die "Installation aborted by the user."

wipefs --all "$DRIVE" || die "Failed to wipe filesystem signatures."
sgdisk --zap-all "$DRIVE" || die "Failed to wipe the drive data structures."

echo -e "The drive ${B}${DRIVE}${S} has been ${G}successfully${S} wiped."
echo "Now the drive will be partitioned."

# Feel free to modify the partitioning structure as you like.
#
# The current setup creates a 512 MiB FAT32 EFI partition (1) and the rest is
# used for the ext4 ROOT partition (2).
#
# Partition 2 starts at partition 1 end sector + 1.
#
# For more information about partition type GUIDs refer to:
# https://en.wikipedia.org/wiki/GUID_Partition_Table#Partition_type_GUIDs
#
# Make sure to also modify the partition formatting/mounting structure below if
# you change anything here.
parted "$DRIVE" --script --align optimal \
    mklabel gpt \
    mkpart EFI fat32 0% 512MiB \
    mkpart ROOT ext4 1048576s 100% \
    type 1 C12A7328-F81F-11D2-BA4B-00A0C93EC93B \
    type 2 4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709 \
    align-check optimal 1 \
    align-check optimal 2 \
    || die "Disk partitioning failed."

udevadm settle

# NVMe and MMC devices name their partitions using the "<drive>p<N>" format
# instead of "<drive><N>".
PART_PREFIX="$DRIVE"

if [[ "$DRIVE" == *[0-9] ]]; then
    PART_PREFIX+="p"
fi

mkfs.fat -F 32 -n EFI "${PART_PREFIX}1"
mkfs.ext4 -L ROOT "${PART_PREFIX}2"

mount "${PART_PREFIX}2" /mnt
mount --mkdir --options umask=0077 "${PART_PREFIX}1" /mnt/boot
MOUNTED=1

pacstrap -K /mnt
genfstab -t PARTUUID /mnt | tr -s '[:blank:]' ' ' > /mnt/etc/fstab

# Arrays can't be passed through the environment, so the locales are written
# from outside the chroot.
printf '%s\n' "${LOCALES[@]}" > /mnt/etc/locale.gen

ROOT_PARTUUID=$(blkid --match-tag PARTUUID --output value "${PART_PREFIX}2")

# Limine looks for its config in the root of the partition it was loaded from,
# which is the ESP (mounted at "/boot").
#
# This heredoc is intentionally unquoted so ${ROOT_PARTUUID} gets expanded.
cat > /mnt/boot/limine.conf << LIMINE
timeout: 5

/Arch Linux
    protocol: linux
    path: boot():/vmlinuz-linux
    cmdline: root=PARTUUID=${ROOT_PARTUUID} rw
    module_path: boot():/amd-ucode.img
    module_path: boot():/initramfs-linux.img
LIMINE

# Copy the chroot script into the new system and run it there. The values it
# needs are passed explicitly through the environment and the copy is removed
# afterwards (or by the cleanup trap if anything fails).
install --mode 0700 "$CHROOT_SCRIPT" "/mnt${CHROOT_SCRIPT_DEST}"

arch-chroot /mnt /usr/bin/env \
    TIMEZONE="$TIMEZONE" \
    KEYMAP="$KEYMAP" \
    HOSTNAME="$HOSTNAME" \
    USERNAME="$USERNAME" \
    DRIVE="$DRIVE" \
    bash "$CHROOT_SCRIPT_DEST" \
    || die "The chroot script failed."

rm --force "/mnt${CHROOT_SCRIPT_DEST}"

# The following commands are ran outside the chroot script because passwd needs
# the terminal on stdin to work properly.
echo "Set the root password:"
arch-chroot /mnt passwd root

echo "Set the password for ${USERNAME}:"
arch-chroot /mnt passwd "$USERNAME"

echo -e "Installation ${G}successfully${S} finished!"
echo "You may reboot now"
