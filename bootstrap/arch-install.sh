#!/usr/bin/env bash
# Fresh Arch Linux install from the live ISO: one whole disk, btrfs, GRUB,
# snapper. The dotfiles install.sh runs on the first tty1 login.
#
#   curl -LO https://raw.githubusercontent.com/ZChenW/dotfiles/main/bootstrap/arch-install.sh
#   bash arch-install.sh --dry-run    # print every step, change nothing
#   bash arch-install.sh
#
# Any question can be answered ahead of time with its ARCH_INSTALL_* variable
# (see ask_questions). Erasing the disk still needs ARCH_INSTALL_CONFIRM=<disk>
# or the disk name typed at the prompt.

set -Eeuo pipefail

DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/ZChenW/dotfiles.git}"
DOTFILES_PUSH_URL="${DOTFILES_PUSH_URL:-git@github.com:ZChenW/dotfiles.git}"
TARGET=/mnt
MAPPER=cryptroot
MOUNT_OPTS="noatime,compress=zstd:3,space_cache=v2"
DRY_RUN=false

# subvolume:mountpoint, in mount order. @snapshots sits beside @ so a
# rollback can replace @ without touching the snapshots.
SUBVOLUMES=(
    "@:/"
    "@home:/home"
    "@snapshots:/.snapshots"
    "@log:/var/log"
    "@pkg:/var/cache/pacman/pkg"
    "@swap:/swap"
)

# fuse3: os-prober only looks inside other disks through grub-mount, which
# needs it; without it Windows is silently left out of the GRUB menu.
BASE_PACKAGES=(
    base base-devel linux linux-firmware
    btrfs-progs dosfstools grub efibootmgr os-prober fuse3
    grub-btrfs inotify-tools snapper snap-pac btrfs-assistant pacman-contrib
    networkmanager bluez sudo git openssh rsync zsh vim
    pipewire pipewire-alsa pipewire-pulse wireplumber sof-firmware alsa-firmware
    greetd greetd-tuigreet
    mesa lib32-mesa
)

say() { printf '\n==> %s\n' "$*"; }
die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

run() {
    if $DRY_RUN; then
        printf '+'
        printf ' %q' "$@"
        printf '\n'
    else
        "$@"
    fi
}

# For commands that need a shell (redirections). Prints the string in dry run.
run_sh() {
    if $DRY_RUN; then
        printf '+ %s\n' "$1"
    else
        bash -o pipefail -c "$1"
    fi
}

# run_secret SECRET CMD...: CMD reads SECRET on stdin; it never reaches the output.
run_secret() {
    local secret=$1
    shift
    if $DRY_RUN; then
        printf '+'
        printf ' %q' "$@"
        printf ' <<< [hidden]\n'
    else
        printf '%s' "$secret" | "$@"
    fi
}

in_target() { run arch-chroot "$TARGET" "$@"; }

# write_file PATH MODE: stdin becomes PATH inside the new system.
write_file() {
    local path=$TARGET$1 mode=$2 content
    content=$(cat)
    if $DRY_RUN; then
        printf '+ write %s (mode %s)\n' "$path" "$mode"
        printf '%s\n' "$content" | sed 's/^/    | /'
    else
        mkdir -p "$(dirname "$path")"
        printf '%s\n' "$content" >"$path"
        chmod "$mode" "$path"
    fi
}

uuid_of() {
    if $DRY_RUN; then
        printf 'UUID-OF-%s' "${1##*/}"
    else
        blkid -s UUID -o value "$1"
    fi
}

# part_path DISK N: /dev/sda 1 -> /dev/sda1, /dev/nvme0n1 1 -> /dev/nvme0n1p1
part_path() {
    if [[ $1 =~ [0-9]$ ]]; then
        printf '%sp%s' "$1" "$2"
    else
        printf '%s%s' "$1" "$2"
    fi
}

# ucode_package CPUINFO
ucode_package() {
    case $1 in
        *GenuineIntel*) echo intel-ucode ;;
        *AuthenticAMD*) echo amd-ucode ;;
    esac
}

# gpu_packages LSPCI_N: driver packages for every display controller listed
# by `lspci -n` (class 03xx). nvidia-open needs an RTX 20 / GTX 16 or newer.
gpu_packages() {
    local nvidia=false amd=false intel=false _ class id
    local -a pkgs=()
    while read -r _ class id _; do
        [[ $class == 03* ]] || continue
        case ${id%%:*} in
            10de) nvidia=true ;;
            1002) amd=true ;;
            8086) intel=true ;;
        esac
    done <<<"$1"
    if $nvidia; then pkgs+=(nvidia-open nvidia-utils lib32-nvidia-utils); fi
    if $amd; then pkgs+=(vulkan-radeon lib32-vulkan-radeon); fi
    if $intel; then pkgs+=(vulkan-intel lib32-vulkan-intel intel-media-driver); fi
    if $nvidia && { $amd || $intel; }; then pkgs+=(nvidia-prime); fi
    echo "${pkgs[*]}"
}

# The disk holding the live USB, so it is never offered as a target.
live_disk() {
    local src parent
    src=$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null) || return 0
    parent=$(lsblk -no PKNAME "$src" 2>/dev/null | head -n1)
    if [[ -n $parent ]]; then printf '/dev/%s' "$parent"; else printf '%s' "$src"; fi
}

ram_gib() {
    awk '/^MemTotal:/ { printf "%d", ($2 + 1048575) / 1048576 }' /proc/meminfo
}

valid_disk() {
    [[ $1 != "$(live_disk)" ]] || return 1
    $DRY_RUN || [[ $(lsblk -dno TYPE "$1" 2>/dev/null) == disk ]]
}
valid_hostname() { [[ $1 =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; }
valid_user() { [[ $1 =~ ^[a-z_][a-z0-9_-]{0,31}$ && $1 != root ]]; }
valid_timezone() { [[ -f /usr/share/zoneinfo/$1 ]]; }
valid_profile() { [[ $1 == standard || $1 == lightweight ]]; }
valid_yes_no() { [[ $1 == yes || $1 == no ]]; }
valid_number() { [[ $1 =~ ^[1-9][0-9]*$ ]]; }

# ask VAR QUESTION DEFAULT CHECK: prompt unless VAR is already set.
ask() {
    local var=$1 question=$2 default=$3 check=$4 reply
    if [[ -n ${!var:-} ]]; then
        "$check" "${!var}" || die "$var=${!var} is not valid"
        return 0
    fi
    while true; do
        read -rp "$question${default:+ [$default]}: " reply </dev/tty
        reply=${reply:-$default}
        if "$check" "$reply"; then break; fi
        echo "  not valid, try again"
    done
    printf -v "$var" '%s' "$reply"
}

# ask_password VAR LABEL [FALLBACK_VAR]: empty input reuses FALLBACK_VAR.
ask_password() {
    local var=$1 label=$2 fallback=${3:-} first second
    if [[ -n ${!var:-} ]]; then return 0; fi
    while true; do
        read -rsp "$label: " first </dev/tty
        echo
        if [[ -z $first && -n $fallback ]]; then
            first=${!fallback}
            break
        fi
        read -rsp "Repeat: " second </dev/tty
        echo
        if [[ -n $first && $first == "$second" ]]; then break; fi
        echo "  empty or different, try again"
    done
    printf -v "$var" '%s' "$first"
}

preflight() {
    [[ $EUID -eq 0 ]] || die "run as root from the Arch live ISO"
    [[ -d /run/archiso ]] || die "this is not the Arch live ISO; nothing was changed"
    [[ -d /sys/firmware/efi/efivars ]] || die "booted in BIOS mode; reboot the USB in UEFI mode"
    curl -fsS --max-time 10 -o /dev/null https://archlinux.org ||
        die "no internet; for Wi-Fi run: iwctl station wlan0 connect <SSID>"
}

ask_questions() {
    say "Disks"
    lsblk -e 7,11 -o NAME,SIZE,TYPE,FSTYPE,LABEL,MODEL
    local live
    live=$(live_disk)
    [[ -z $live ]] || echo "(the live USB $live is not an option)"
    echo

    ask ARCH_INSTALL_DISK "Disk to ERASE for Arch, e.g. /dev/nvme0n1" "" valid_disk
    ask ARCH_INSTALL_HOSTNAME "Hostname" "arch" valid_hostname
    ask ARCH_INSTALL_USER "User name" "chakew" valid_user
    ask_password ARCH_INSTALL_PASSWORD "Password for $ARCH_INSTALL_USER (also used for sudo)"
    ask ARCH_INSTALL_ENCRYPT "Encrypt the disk with LUKS? (yes/no)" "yes" valid_yes_no
    if [[ $ARCH_INSTALL_ENCRYPT == yes ]]; then
        ask_password ARCH_INSTALL_LUKS_PASSWORD \
            "Disk password, asked at every boot (Enter = same as login)" ARCH_INSTALL_PASSWORD
    fi
    ask ARCH_INSTALL_TIMEZONE "Time zone" "America/New_York" valid_timezone
    ask ARCH_INSTALL_PROFILE "Dotfiles profile (standard/lightweight)" "standard" valid_profile
    # Swap as large as RAM so hibernate always fits.
    ARCH_INSTALL_SWAP_GIB=${ARCH_INSTALL_SWAP_GIB:-$(ram_gib)}
    valid_number "$ARCH_INSTALL_SWAP_GIB" || die "ARCH_INSTALL_SWAP_GIB=$ARCH_INSTALL_SWAP_GIB is not valid"
}

detect_hardware() {
    UCODE=$(ucode_package "$(grep -m1 '^vendor_id' /proc/cpuinfo || true)")
    GPU_PACKAGES=$(gpu_packages "$(lspci -n 2>/dev/null || true)")
}

show_plan_and_confirm() {
    local disk=$ARCH_INSTALL_DISK about
    about=$(lsblk -dno SIZE,MODEL "$disk" 2>/dev/null | xargs) || about="not found"
    say "Plan"
    cat <<EOF
  Disk:      $disk  ($about) -> ERASED
  Layout:    1 GiB EFI at /boot, rest btrfs: ${SUBVOLUMES[*]%%:*}
  Encrypt:   $ARCH_INSTALL_ENCRYPT
  Swap:      ${ARCH_INSTALL_SWAP_GIB} GiB swap file (hibernate)
  Host/user: $ARCH_INSTALL_HOSTNAME / $ARCH_INSTALL_USER (root is locked; use sudo)
  Time zone: $ARCH_INSTALL_TIMEZONE
  Hardware:  ${UCODE:-no microcode} ${GPU_PACKAGES:-(no GPU driver detected; mesa only)}
  Boot:      GRUB, with Windows or other systems found by os-prober
  Then:      first login on tty1 runs ./install.sh --install-profile $ARCH_INSTALL_PROFILE --yes
EOF
    if lsblk -no FSTYPE "$disk" 2>/dev/null | grep -qiE 'ntfs|bitlocker'; then
        echo
        echo "  !! $disk has Windows (NTFS/BitLocker) partitions. They will be destroyed."
    fi
    echo
    $DRY_RUN && return 0
    if [[ ${ARCH_INSTALL_CONFIRM:-} == "$disk" ]]; then return 0; fi
    local reply
    read -rp "Type the disk name (${disk#/dev/}) to erase it and install: " reply </dev/tty
    [[ $reply == "$disk" || $reply == "${disk#/dev/}" ]] || die "not confirmed; nothing was changed"
}

prepare_live_system() {
    say "Preparing the live system"
    # A rerun after a failure starts from a clean slate.
    if mountpoint -q "$TARGET"; then run umount -R "$TARGET"; fi
    if [[ -e /dev/mapper/$MAPPER ]]; then run cryptsetup close "$MAPPER"; fi
    run timeout 120 bash -c 'until systemctl -q is-active pacman-init.service; do sleep 1; done'
    # pacman's signature checks fail when the clock is far off.
    run timedatectl set-ntp true
    # shellcheck disable=SC2016 # expanded by the inner bash on each try
    run timeout 60 bash -c 'until [[ $(timedatectl show -p NTPSynchronized --value) == yes ]]; do sleep 1; done' ||
        echo "warning: the clock is not synchronized yet; continuing"
    run sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
    run pacman -Sy --needed --noconfirm archlinux-keyring
}

partition_disk() {
    local disk=$ARCH_INSTALL_DISK root_type=8304
    [[ $ARCH_INSTALL_ENCRYPT == yes ]] && root_type=8309
    say "Partitioning $disk"
    if ! $DRY_RUN && lsblk -no MOUNTPOINTS "$disk" | grep -q .; then
        die "$disk has mounted partitions; unmount them first"
    fi
    run wipefs -af "$disk"
    run sgdisk --zap-all "$disk"
    run sgdisk -n 1:0:+1G -t 1:ef00 -c 1:EFI -n "2:0:0" -t "2:$root_type" -c 2:arch "$disk"
    run partprobe "$disk"
    run udevadm settle
    ESP=$(part_path "$disk" 1)
    ROOT_PART=$(part_path "$disk" 2)
    ROOT_DEV=$ROOT_PART
}

make_filesystems() {
    say "Creating file systems"
    if [[ $ARCH_INSTALL_ENCRYPT == yes ]]; then
        run_secret "$ARCH_INSTALL_LUKS_PASSWORD" \
            cryptsetup luksFormat --type luks2 --batch-mode --key-file=- "$ROOT_PART"
        # --persistent stores allow-discards in the header, so TRIM works at boot too.
        run_secret "$ARCH_INSTALL_LUKS_PASSWORD" \
            cryptsetup open --allow-discards --persistent --key-file=- "$ROOT_PART" "$MAPPER"
        ROOT_DEV=/dev/mapper/$MAPPER
    fi
    run mkfs.fat -F 32 -n EFI "$ESP"
    run mkfs.btrfs -f -L arch "$ROOT_DEV"

    local entry subvol mountpoint
    run mount "$ROOT_DEV" "$TARGET"
    for entry in "${SUBVOLUMES[@]}"; do
        run btrfs subvolume create "$TARGET/${entry%%:*}"
    done
    run umount "$TARGET"
    for entry in "${SUBVOLUMES[@]}"; do
        subvol=${entry%%:*}
        mountpoint=${entry#*:}
        run mount --mkdir -o "$MOUNT_OPTS,subvol=$subvol" "$ROOT_DEV" "$TARGET${mountpoint%/}"
    done
    run mount --mkdir "$ESP" "$TARGET/boot"
    run btrfs filesystem mkswapfile --size "${ARCH_INSTALL_SWAP_GIB}g" --uuid clear "$TARGET/swap/swapfile"
}

install_packages() {
    say "Installing packages"
    local -a packages=("${BASE_PACKAGES[@]}")
    # Unquoted on purpose: both hold space-separated package names.
    # shellcheck disable=SC2206
    packages+=($UCODE $GPU_PACKAGES)
    run pacstrap -K "$TARGET" "${packages[@]}"
    run sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' "$TARGET/etc/pacman.conf"
    run_sh "genfstab -U $TARGET | sed -E 's/,subvolid=[0-9]+//' >>$TARGET/etc/fstab"
    run_sh "printf '/swap/swapfile none swap defaults 0 0\n' >>$TARGET/etc/fstab"
}

configure_system() {
    local user=$ARCH_INSTALL_USER home=/home/$ARCH_INSTALL_USER
    say "Configuring the new system"
    in_target ln -sf "/usr/share/zoneinfo/$ARCH_INSTALL_TIMEZONE" /etc/localtime
    in_target hwclock --systohc
    run sed -i -E 's/^#((en_US|zh_CN)\.UTF-8 UTF-8)/\1/' "$TARGET/etc/locale.gen"
    in_target locale-gen
    write_file /etc/locale.conf 644 <<<"LANG=en_US.UTF-8"
    write_file /etc/vconsole.conf 644 <<<"KEYMAP=us"
    write_file /etc/hostname 644 <<<"$ARCH_INSTALL_HOSTNAME"

    in_target useradd -m -G wheel -s /usr/bin/zsh "$user"
    run_secret "$user:$ARCH_INSTALL_PASSWORD" arch-chroot "$TARGET" chpasswd
    in_target passwd -l root
    write_file /etc/sudoers.d/10-wheel 440 <<<"%wheel ALL=(ALL:ALL) ALL"

    # nowatchdog on the kernel line does not stop these drivers from loading.
    write_file /etc/modprobe.d/nowatchdog.conf 644 <<'EOF'
blacklist iTCO_wdt
blacklist sp5100_tco
EOF
    if [[ $ARCH_INSTALL_ENCRYPT == yes ]]; then
        write_file /etc/mkinitcpio.conf.d/10-encrypt.conf 644 <<'EOF'
HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)
EOF
    fi
    in_target mkinitcpio -P

    # snapper create-config would make its own nested .snapshots; @snapshots
    # is already mounted there, so only the config files are needed.
    run install -Dm640 "$TARGET/usr/share/snapper/config-templates/default" "$TARGET/etc/snapper/configs/root"
    run sed -i 's/^SNAPPER_CONFIGS=.*/SNAPPER_CONFIGS="root"/' "$TARGET/etc/conf.d/snapper"
    run chmod 750 "$TARGET/.snapshots"

    # Enabled by the first-boot script, once niri is installed.
    write_file /etc/greetd/config.toml 644 <<'EOF'
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --remember --remember-session --sessions /usr/share/wayland-sessions --cmd niri-session"
user = "greeter"
EOF
    in_target systemctl enable NetworkManager.service bluetooth.service systemd-timesyncd.service \
        snapper-timeline.timer snapper-cleanup.timer grub-btrfsd.service paccache.timer

    in_target git clone "$DOTFILES_REPO" "$home/Projects/dotfiles"
    in_target git -C "$home/Projects/dotfiles" remote set-url --push origin "$DOTFILES_PUSH_URL"
    write_first_boot
    in_target chown -R "$user:$user" "$home/Projects" "$home/.dotfiles-first-boot" "$home/.zprofile"
}

write_first_boot() {
    local home=/home/$ARCH_INSTALL_USER
    {
        echo '#!/usr/bin/env bash'
        echo '# Written by arch-install.sh. Runs on the first tty1 login: installs the'
        echo '# dotfiles, turns on the greetd login screen, then removes itself.'
        echo "profile=$ARCH_INSTALL_PROFILE"
        cat <<'EOF'
set -uo pipefail

until nm-online -q -t 15; do
    echo "No network yet. Pick a connection in nmtui, then quit it."
    read -rp "Press Enter to open nmtui. " _
    nmtui
done

if ! "$HOME/Projects/dotfiles/install.sh" --install-profile "$profile" --yes; then
    echo "install.sh failed; it runs again at the next tty1 login."
    echo "To stop that: rm ~/.dotfiles-first-boot"
    exit 1
fi
# Again from the running system, in case the chroot missed another disk.
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo systemctl enable greetd.service
rm -f "$HOME/.dotfiles-first-boot"
sed -i '/dotfiles-first-boot/d' "$HOME/.zprofile"
read -rp "Done. Press Enter to reboot into the login screen. " _
sudo systemctl reboot
EOF
    } | write_file "$home/.dotfiles-first-boot" 755
    # Any zsh startup file also skips zsh's new-user wizard.
    write_file "$home/.zprofile" 644 <<'EOF'
[[ $TTY == /dev/tty1 && -x ~/.dotfiles-first-boot ]] && ~/.dotfiles-first-boot
EOF
}

install_bootloader() {
    local cmdline="${ARCH_INSTALL_KERNEL_ARGS:-}"
    say "Installing GRUB"
    if [[ $ARCH_INSTALL_ENCRYPT == yes ]]; then
        cmdline="rd.luks.name=$(uuid_of "$ROOT_PART")=$MAPPER${cmdline:+ $cmdline}"
    fi
    run sed -i -E \
        -e 's/^#?GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' \
        -e 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet nowatchdog"/' \
        -e "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"$cmdline\"|" \
        "$TARGET/etc/default/grub"
    in_target grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
    # Fallback path for firmware that forgets the boot entry.
    in_target grub-install --target=x86_64-efi --efi-directory=/boot --removable
    in_target snapper --no-dbus -c root create --description "fresh install"
    in_target grub-mkconfig -o /boot/grub/grub.cfg
}

finish() {
    say "Unmounting"
    run umount -R "$TARGET"
    if [[ $ARCH_INSTALL_ENCRYPT == yes ]]; then run cryptsetup close "$MAPPER"; fi
    say "Done"
    cat <<EOF
  Remove the USB stick and reboot. Log in on tty1 as $ARCH_INSTALL_USER;
  the dotfiles install starts by itself and reboots into the login screen.
EOF
    $DRY_RUN && return 0
    ask ARCH_INSTALL_REBOOT "Reboot now? (yes/no)" "yes" valid_yes_no
    if [[ $ARCH_INSTALL_REBOOT == yes ]]; then reboot; fi
}

usage() {
    sed -n '2,12s/^# \{0,1\}//p' "$0"
}

main() {
    case ${1:-} in
        --dry-run) DRY_RUN=true ;;
        -h | --help)
            usage
            return 0
            ;;
        "") ;;
        *) die "unknown option: $1 (try --help)" ;;
    esac
    $DRY_RUN || preflight
    trap 'echo "error: failed at line $LINENO: $BASH_COMMAND" >&2; echo "Rerun the script to start over." >&2' ERR
    ask_questions
    detect_hardware
    show_plan_and_confirm
    prepare_live_system
    partition_disk
    make_filesystems
    install_packages
    configure_system
    install_bootloader
    finish
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
