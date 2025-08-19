#!/bin/bash
# build script to create desktop_name-of-desktop.img for Atlantis OS
# overlay image, for some typs of desktop based on the Ubuntu Versions
set -e

# base image 
SYSTEM_IMG="system.img"
WORK_DIR="build_desktops"
IMG_SIZE="2048M"

# define the desktop and apps
# I will probably remove the additional app stores and flatpak
declare -A DESKTOPS=(
    [gnome]="ubuntu-desktop gnome-shell gdm3 gnome-software-plugin-snap gnome-software-plugin-flatpak evince gnome-disk-utility"
    [kde]="kubuntu-desktop plasma-desktop sddm plasma-discover okular plasma-discover-backend-snap plasma-discover-backend-flatpak"
    [xfce]="xubuntu-desktop xfce4 lightdm synaptic evince"
    [lxqt]="lxqt sddm synaptic"
    [mate]="ubuntu-mate-desktop mate-desktop-environment lightdm synaptic atril"
)

# extra apps
EXTRA_APPS="libreoffice vlc"

mkdir -p "$WORK_DIR"

if [ $# -eq 0 ]; then
    BUILD_LIST=("${!DESKTOPS[@]}")
else
    BUILD_LIST=("$@")
fi

# check for system.img
if [ ! -f "$SYSTEM_IMG" ]; then
    echo "Error: $SYSTEM_IMG not found!"
    exit 1
fi

for desktop in "${BUILD_LIST[@]}"; do
    if [[ -z "${DESKTOPS[$desktop]}" ]]; then
        echo "Desktop ‘$desktop’ not defined. Skip..."
        continue
    fi

    echo "=== Build Desktop: $desktop ==="
	
	# working dirs
    LOWER_DIR="$WORK_DIR/lower"
    UPPER_DIR="$WORK_DIR/upper_$desktop"
    WORK_DIR_OVL="$WORK_DIR/work_$desktop"
    MERGE_DIR="$WORK_DIR/merged"

    mkdir -p "$LOWER_DIR" "$UPPER_DIR" "$WORK_DIR_OVL" "$MERGE_DIR"
	
	# mount the base image
    sudo mount -o loop,ro "$SYSTEM_IMG" "$LOWER_DIR"
	# mount and overlay structure
    sudo mount -t overlay overlay \
        -o lowerdir="$LOWER_DIR",upperdir="$UPPER_DIR",workdir="$WORK_DIR_OVL" \
        "$MERGE_DIR"
	
	# add mount binds
    sudo mount --bind /dev "$MERGE_DIR/dev"
    sudo mount --bind /proc "$MERGE_DIR/proc"
    sudo mount --bind /sys "$MERGE_DIR/sys"
	
	# install all packages
    echo "Install packages for $desktop ..."
    sudo chroot "$MERGE_DIR" bash -c "
        export DEBIAN_FRONTEND=noninteractive
        apt update
        apt install -y ${DESKTOPS[$desktop]} $EXTRA_APPS snapd flatpak apparmor

        # add flathub
        flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

        # start snap services
        systemctl enable snapd
        systemctl enable apparmor

        # install firefox as snap
        snap install firefox

        # enable display service
        if [[ ${DESKTOPS[$desktop]} == *gdm3* ]]; then
            systemctl enable gdm
        elif [[ ${DESKTOPS[$desktop]} == *sddm* ]]; then
            systemctl enable sddm
        elif [[ ${DESKTOPS[$desktop]} == *lightdm* ]]; then
            systemctl enable lightdm
        fi
    "
	# unmount
    sudo umount "$MERGE_DIR/dev" "$MERGE_DIR/proc" "$MERGE_DIR/sys"
    sudo umount "$MERGE_DIR"
    sudo umount "$LOWER_DIR"
	
	# create the desktop.img
    DESKTOP_IMG="desktop_${desktop}.img"
    echo "Create image file $DESKTOP_IMG ..."
    dd if=/dev/zero of="$DESKTOP_IMG" bs=1M count=$(( ${IMG_SIZE//M/} ))
    mkfs.ext4 "$DESKTOP_IMG"
	
	# copy this to the upper dir
    TMP_MNT="$WORK_DIR/tmp_mnt"
    mkdir -p "$TMP_MNT"
    sudo mount -o loop "$DESKTOP_IMG" "$TMP_MNT"
    sudo cp -a "$UPPER_DIR"/. "$TMP_MNT"/
    sudo umount "$TMP_MNT"
	
	# cleanup
    echo "Finished: $DESKTOP_IMG"
    rm -rf "$UPPER_DIR" "$WORK_DIR_OVL"
done

echo "All desktop images built!"

