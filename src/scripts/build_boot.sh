#!/bin/bash
# build script to create bootloader.img for Atlantis OS
# includes dynamic system + desktop detection via atlantis.conf
set -e

BOOT_IMG="bootloader.img"
IMG_SIZE="64M"
MNT_DIR="mnt/boot"

mkdir -p "$MNT_DIR"
rm -f "$BOOT_IMG"

# create bootloader.img (FAT32 for EFI)
dd if=/dev/zero of="$BOOT_IMG" bs=1M count=64
mkfs.vfat "$BOOT_IMG"

sudo mount "$BOOT_IMG" "$MNT_DIR"

# EFI/GRUB structure
sudo mkdir -p "$MNT_DIR/EFI/BOOT"
sudo mkdir -p "$MNT_DIR/boot/grub"

# create default atlantis.conf
cat <<'EOF' | sudo tee "$MNT_DIR/atlantis.conf"
SYSTEM_IMG=/system.img
DESKTOP_IMG=/desktop_gnome.img
SLOT_A=/system_a.img
SLOT_B=/system_b.img
# UUIDs for specific partitions (to be filled by installer)
SLOT_A_PARTUUID=
SLOT_B_PARTUUID=
EOF

# create grub.cfg that reads atlantis.conf dynamically
cat <<'EOF' | sudo tee "$MNT_DIR/boot/grub/grub.cfg"
set default=0
set timeout=5

# load configuration if available
if [ -f /atlantis.conf ]; then
    source /atlantis.conf
else
    set SYSTEM_IMG=/system.img
    set DESKTOP_IMG=/desktop_gnome.img
fi

# automatic detection menu
menuentry "AtlantisOS Live (Automatic Detection)" {
    insmod part_gpt
    insmod fat
    insmod ext2
    insmod search
    insmod search_fs_uuid
    insmod loopback

    echo "Searching for system.img ..."
    search --no-floppy --set=founddev --file $SYSTEM_IMG

    if [ -n "$founddev" ]; then
        echo "Found on: $founddev"
        loopback loop0 ($founddev)$SYSTEM_IMG
        set root=(loop0)
        linux /boot/vmlinuz root=/dev/loop0 overlay=$DESKTOP_IMG rw quiet splash
        initrd /boot/initrd.img
    else
        echo "system.img not found!"
        sleep 5
    fi
}

# Slot A
menuentry "AtlantisOS (Slot A)" {
    insmod part_gpt
    insmod ext2
    insmod loopback
    if [ -n "$SLOT_A_PARTUUID" ]; then
        search --no-floppy --set=founddev --fs-uuid $SLOT_A_PARTUUID
    else
        search --no-floppy --set=founddev --file $SLOT_A
    fi
    loopback loop0 ($founddev)$SLOT_A
    set root=(loop0)
    linux /boot/vmlinuz root=/dev/loop0 overlay=$DESKTOP_IMG rw quiet splash
    initrd /boot/initrd.img
}

# Slot B
menuentry "AtlantisOS (Slot B)" {
    insmod part_gpt
    insmod ext2
    insmod loopback
    if [ -n "$SLOT_B_PARTUUID" ]; then
        search --no-floppy --set=founddev --fs-uuid $SLOT_B_PARTUUID
    else
        search --no-floppy --set=founddev --file $SLOT_B
    fi
    loopback loop0 ($founddev)$SLOT_B
    set root=(loop0)
    linux /boot/vmlinuz root=/dev/loop0 overlay=$DESKTOP_IMG rw quiet splash
    initrd /boot/initrd.img
}
EOF

# GRUB Standalone for UEFI
sudo grub-mkstandalone \
  --format=x86_64-efi \
  --output="$MNT_DIR/EFI/BOOT/BOOTX64.EFI" \
  --install-modules="part_gpt part_msdos fat ext2 normal search search_fs_uuid loopback linux" \
  --locales="" \
  --themes="" \
  "boot/grub/grub.cfg=$MNT_DIR/boot/grub/grub.cfg"

sudo umount "$MNT_DIR"
rmdir "$MNT_DIR"

echo "Boot image created: $BOOT_IMG (with dynamic system + desktop detection via atlantis.conf)"

