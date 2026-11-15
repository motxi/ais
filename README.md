# ais

> [!CAUTION]
> Do **NOT** run without reading the code first. \
>
> This script is extremely opinionated and made for my own machine. \
> Worst-case scenario you might wipe your entire disk by accident.

## Usage

First, boot the Arch Linux ISO in **UEFI mode** and connect to the internet.
Ethernet works out of the box, and for Wi-Fi you can use [`iwctl`](https://wiki.archlinux.org/title/Iwd#iwctl).

Then download the installer:

```bash
curl -fsSL https://raw.githubusercontent.com/motxi/ais/master/ais.sh | bash
```

This extracts all the scripts to `./ais` and makes `install.sh` executable.
You can then review and modify `config.sh` and `packages.sh` to your likings.
