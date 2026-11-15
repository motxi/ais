# Not meant to be run directly.
# Sourced by "install.sh" and "chroot.sh".
#
# Expects "install.sh" to define `CHROOT_SCRIPT_DEST`, `PACKAGES_SCRIPT_DEST`
# and `UTILS_SCRIPT_DEST` before "cleanup()" runs.

readonly R='\033[1;31m' # Red
readonly G='\033[1;32m' # Green
readonly B='\033[1;34m' # Blue
readonly S='\033[0m' # Reset

# Set to 1 by "install.sh" once "/mnt" is mounted, so "cleanup()" knows it has
# something to undo.
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

    say blue "Set the password for \"${user}\":"

    until arch-chroot /mnt passwd "${user}"; do
        say red 'Password not set. Try again.'
    done
}

cleanup() {
    local status=$?

    trap - EXIT

    if (( MOUNTED )); then
        say blue 'Removing the temporary installation scripts...'
        rm --force \
            "/mnt${CHROOT_SCRIPT_DEST}" \
            "/mnt${PACKAGES_SCRIPT_DEST}" \
            "/mnt${UTILS_SCRIPT_DEST}"

        say green 'Unmounting "/mnt"...'
        umount --recursive /mnt || die 'Failed to unmount "/mnt".'
    fi

    if (( status != 0 )); then
        say red "The installation failed with exit code ${status}."
    fi

    exit "${status}"
}
