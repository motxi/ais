# Not meant to be run directly.
# Sourced by "install.sh".

# Drive that Arch Linux will be installed on. It will be completely wiped.
# Must be a valid block device without the partition number, for example
# "/dev/sda" or "/dev/nvme0n1".
#
# Run `fdisk -l` or `lsblk` for possible values.
DRIVE='/dev/sda'

# Console keymap used during the installation and set in "/etc/vconsole.conf".
#
# Run `localectl list-keymaps` for possible values.
KEYMAP='us'

# Locales to generate written to "/etc/locale.gen". The system language (LANG)
# is always "en_US.UTF-8", so keep that one in the list.
#
# Run `cat /etc/locale.gen` for possible values.
LOCALES=('en_US.UTF-8 UTF-8' 'es_ES.UTF-8 UTF-8' 'ja_JP.UTF-8 UTF-8')

# System timezone. Must follow the format "Zone/Location".
#
# Run `timedatectl list-timezones` for possible values.
TIMEZONE='Europe/Madrid'

USERNAME='motxi'
HOSTNAME='arch'
