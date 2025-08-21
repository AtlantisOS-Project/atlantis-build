#!/bin/bash
# build_system.sh
# build script to create system.img for Atlantis OS
# this script create a basic system for AtlantisOS based on Ubuntu
set -e

# define basics
SYSTEM_IMG="system.img"
IMG_SIZE="4096M"
MNT_DIR="mnt/system"

# basic dir
mkdir -p "$MNT_DIR"
rm -f "$SYSTEM_IMG"

# create the image and formate it
echo "[INFO] Creating system.img..."
dd if=/dev/zero of="$SYSTEM_IMG" bs=1M count=4096
mkfs.ext4 "$SYSTEM_IMG"

# mount the image
echo "[INFO] Mount system.img..."
sudo mount "$SYSTEM_IMG" "$MNT_DIR"

# install the Ubuntu basic system
echo "[INFO] Installing basic Ubuntu System..."
sudo debootstrap --arch=amd64 noble "$MNT_DIR" http://archive.ubuntu.com/ubuntu

# add mount binds
echo "[INFO] Adding mount binds..."
sudo mount --bind /dev "$MNT_DIR/dev"
sudo mount --bind /proc "$MNT_DIR/proc"
sudo mount --bind /sys "$MNT_DIR/sys"

# install basic tools
echo "[INFO] Installing basic system tools..."
sudo chroot "$MNT_DIR" bash -c "
export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y \
    linux-image-generic linux-headers-generic linux-firmware \
    qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager \
    grub-pc sudo systemd-sysv net-tools curl wget nano vim htop openssh-server \
    locales less iproute2 bash-completion network-manager dbus-x11 \
    xserver-xorg xserver-xorg-core xserver-xorg-video-all xserver-xorg-input-all \
    xserver-xorg-video-amdgpu xserver-xorg-video-intel xserver-xorg-video-nouveau \
    mesa-utils mesa-utils-extra libgl1-mesa-dri libglx-mesa0 \
    libwayland-client0 libwayland-server0 libwayland-egl1 \
    pipewire pipewire-pulse alsa-utils p7zip-full unrar zip unzip tar \
    cups system-config-printer bluez blueman systemd-container
"

# install GRUB on the system (for emergency startup from USB/ISO)
echo "[INFO] Installing Grub on the system..."
sudo chroot "$MNT_DIR" grub-install --target=i386-pc --boot-directory=/boot --recheck /dev/loop0 || true

# unmount 
echo "[INFO] Unmount everything..."
sudo umount "$MNT_DIR/dev"
sudo umount "$MNT_DIR/proc"
sudo umount "$MNT_DIR/sys"
sudo umount "$MNT_DIR"

# cleanup
echo "[INFO] Running cleanup..."
rmdir "$MNT_DIR"

echo "[OK] System image created: $SYSTEM_IMG"
