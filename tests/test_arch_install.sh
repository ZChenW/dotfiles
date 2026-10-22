#!/usr/bin/env bash

set -euo pipefail
# Each fixture supplies its own HOME; its XDG defaults must follow that HOME.
unset XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
INSTALLER="$REPO_ROOT/bootstrap/arch-install.sh"

# shellcheck source=bootstrap/arch-install.sh
source "$INSTALLER"

expect_eq() {
    if [[ "$1" != "$2" ]]; then
        echo "Expected '$2', got '$1'" >&2
        exit 1
    fi
}

expect_contains() {
    if [[ "$1" != *"$2"* ]]; then
        echo "Expected output to contain: $2" >&2
        exit 1
    fi
}

expect_absent() {
    if [[ "$1" == *"$2"* ]]; then
        echo "Expected output not to contain: $2" >&2
        exit 1
    fi
}

dry_run() {
    env -i PATH="$PATH" HOME="$HOME" TMPDIR="${TMPDIR:?}" \
        ARCH_INSTALL_HOSTNAME=newbox \
        ARCH_INSTALL_USER=tester \
        ARCH_INSTALL_PASSWORD='login secret' \
        ARCH_INSTALL_TIMEZONE=America/New_York \
        ARCH_INSTALL_PROFILE=lightweight \
        ARCH_INSTALL_SWAP_GIB=8 \
        "$@" bash "$INSTALLER" --dry-run 2>&1
}

echo "==> test 1: partition paths"
expect_eq "$(part_path /dev/sda 1)" /dev/sda1
expect_eq "$(part_path /dev/nvme0n1 2)" /dev/nvme0n1p2
expect_eq "$(part_path /dev/mmcblk0 1)" /dev/mmcblk0p1

echo "==> test 2: microcode follows the CPU vendor"
expect_eq "$(ucode_package 'vendor_id	: GenuineIntel')" intel-ucode
expect_eq "$(ucode_package 'vendor_id	: AuthenticAMD')" amd-ucode
expect_eq "$(ucode_package '')" ""

echo "==> test 3: GPU drivers follow lspci"
hybrid=$'00:02.0 0300: 8086:a7a0 (rev 04)\n01:00.0 0300: 10de:2860 (rev a1)\n00:1f.3 0403: 8086:51ca'
expect_eq "$(gpu_packages "$hybrid")" \
    "nvidia-open nvidia-utils lib32-nvidia-utils vulkan-intel lib32-vulkan-intel intel-media-driver nvidia-prime"
expect_eq "$(gpu_packages '03:00.0 0300: 1002:744c (rev c8)')" "vulkan-radeon lib32-vulkan-radeon"
expect_eq "$(gpu_packages '00:01.0 0300: 1234:1111 (rev 02)')" ""
# An Intel audio device alone is not a GPU.
expect_eq "$(gpu_packages '00:1f.3 0403: 8086:51ca')" ""

echo "==> test 4: the live USB is found behind Ventoy and never offered"
findmnt() { echo /dev/mapper/ventoy; }
lsblk() { printf '%s\n' '/dev/mapper/ventoy dm' '/dev/sdb1 part' '/dev/sdb disk'; }
expect_eq "$(live_disk)" /dev/sdb
DRY_RUN=true
if valid_disk /dev/sdb; then
    echo "Expected the live USB to be rejected as a target" >&2
    exit 1
fi
valid_disk /dev/nvme0n1
DRY_RUN=false
unset -f findmnt lsblk

echo "==> test 5: plain install on a SATA disk"
out="$(dry_run ARCH_INSTALL_DISK=/dev/sdz ARCH_INSTALL_ENCRYPT=no)"
expect_contains "$out" "sgdisk -n 1:0:+1G -t 1:ef00 -c 1:EFI -n 2:0:0 -t 2:8304 -c 2:arch /dev/sdz"
expect_contains "$out" "mkfs.fat -F 32 -n EFI /dev/sdz1"
expect_contains "$out" "mkfs.btrfs -f -L arch /dev/sdz2"
expect_contains "$out" "btrfs filesystem mkswapfile --size 8g"
# os-prober needs grub-mount, and grub-mount needs fuse3, to find Windows.
expect_contains "$out" " os-prober fuse3 "
# The clone's push URL is SSH.
expect_contains "$out" " openssh "
expect_contains "$out" "timedatectl set-ntp true"
expect_contains "$out" "blacklist sp5100_tco"
expect_contains "$out" "paccache.timer"
expect_contains "$out" "pam_gnome_keyring.so auto_start"
expect_contains "$out" "sudo grub-mkconfig -o /boot/grub/grub.cfg"
expect_contains "$out" 'GRUB_CMDLINE_LINUX=\"\"'
expect_contains "$out" "profile=lightweight"
expect_absent "$out" "cryptsetup"
expect_absent "$out" "sd-encrypt"
expect_absent "$out" "error:"

echo "==> test 6: encrypted install hides both passwords"
out="$(dry_run ARCH_INSTALL_DISK=/dev/nvme7n1 ARCH_INSTALL_ENCRYPT=yes ARCH_INSTALL_LUKS_PASSWORD='disk secret')"
expect_contains "$out" "cryptsetup luksFormat --type luks2 --batch-mode --key-file=- /dev/nvme7n1p2 <<< [hidden]"
expect_contains "$out" "mkfs.btrfs -f -L arch /dev/mapper/cryptroot"
expect_contains "$out" "block sd-encrypt filesystems"
expect_contains "$out" "rd.luks.name=UUID-OF-nvme7n1p2=cryptroot"
expect_contains "$out" "chpasswd <<< [hidden]"
expect_absent "$out" "login secret"
expect_absent "$out" "disk secret"

echo "==> test 7: a bad preset answer stops before any command"
if out="$(dry_run ARCH_INSTALL_DISK=/dev/sdz ARCH_INSTALL_ENCRYPT=no ARCH_INSTALL_USER=Root)"; then
    echo "Expected an invalid user name to fail" >&2
    exit 1
fi
expect_contains "$out" "ARCH_INSTALL_USER=Root is not valid"
expect_absent "$out" "+ "

echo "==> test 8: unknown option"
if bash "$INSTALLER" --wipe-everything >/dev/null 2>&1; then
    echo "Expected an unknown option to fail" >&2
    exit 1
fi

echo "==> test 9: a nonstandard home is passed to useradd and first boot"
out="$(dry_run ARCH_INSTALL_DISK=/dev/sdz ARCH_INSTALL_ENCRYPT=no ARCH_INSTALL_HOME=/srv/people/tester)"
expect_contains "$out" 'useradd -m -d /srv/people/tester'
expect_contains "$out" '/srv/people/tester/Projects/dotfiles'
expect_contains "$out" '/srv/people/tester/.dotfiles-first-boot'
expect_absent "$out" '/home/tester'

echo "All arch-install tests passed."
