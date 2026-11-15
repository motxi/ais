# Not meant to be run directly.
# Sourced by "install.sh" and "chroot.sh".
#
# Expects "install.sh" to define `CHROOT_SCRIPT_DEST`, `PACKAGES_SCRIPT_DEST`,
# `UTILS_SCRIPT_DEST` and `LOG_FILE` before `cleanup` runs, and to point file
# descriptor 3 to the real terminal (`exec 3>&2`).

readonly R='\033[1;31m' # Red
readonly G='\033[1;32m' # Green
readonly B='\033[1;34m' # Blue
readonly S='\033[0m' # Reset

# Set to 1 by "install.sh" once "/mnt" is mounted, so `cleanup` knows it has
# something to undo.
MOUNTED=0

clear_screen() {
    clear >&3 || true
}

say() {
    local color=$1
    local message=${2:-}

    case "${color}" in
        'red') color="${R}" ;;
        'green') color="${G}" ;;
        'blue') color="${B}" ;;
        *) color="${S}" ;;
    esac

    local output="${color}${message}${S}"

    echo -e "${output}" >&2

    if [[ "${HIDE_COMMAND_OUTPUT:-false}" == true ]]; then
        # Stderr only goes to the log file in this mode, so show the messages on
        # the terminal (FD 3) too.
        { echo -e "${output}" >&3; } 2> /dev/null || true
    fi
}

die() {
    say ''
    say red "$1"

    exit 1
}

password() {
    local user=$1

    say blue "Set the password for \"${user}\":"

    # Talk to the terminal directly so the prompts are always visible and the
    # passwords never reach the log.
    until arch-chroot /mnt passwd "${user}" >&3 2>&3; do
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
        say ''
        say red "The installation failed with exit code ${status}."
        say ''

        if [[ "${HIDE_COMMAND_OUTPUT:-false}" == true ]]; then
            say red "Last lines of the log (\"${LOG_FILE}\"):"
            tail --lines 15 "${LOG_FILE}" >&3
        fi
    fi

    exit "${status}"
}
