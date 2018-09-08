#!/bin/bash

set -e
set -x

function _echo {
  echo "###===### $1"
}

function start_container {
  _echo "Starting container for image $1"
  docker pull $1
  docker rmi $(docker images --filter 'dangling=true' -q --no-trunc) || true
  docker run -i --rm --privileged -v /dev:/dev -v $(pwd)/in_container:/in_container $1 /in_container/build.sh
}

function create_disk {
  _echo "Creating new disk image with size $1 Mb"
  rm -f disk.img || true
  dd if=/dev/zero of=disk.img bs=1024k seek=$1 count=0
  #Start sector: 2048 (reserved for GRUB), end: whole disk, type: 83 (Linux)
  echo "2048,,83" | sfdisk -u S -f disk.img
  _echo "Attaching device"
  DEVICE=$(losetup -f --show -P disk.img)
  PART=${DEVICE}p1
  _echo "Attached device with partition ${PART}"
  _echo "Formatting for ext4"
  mkfs.ext4 $PART
  _echo "Mounting to /target"
  mkdir /target
  mount $PART /target
  mkdir /target/in_chroot
  echo $DEVICE > /in_container/device
  echo $DEVICE > /target/in_chroot/device
  echo $PART > /target/in_chroot/part
}

function make_fstab {
  _echo "Making fstab"
  PART=$(cat /target/in_chroot/part)
  UUID=$(blkid -o value $PART | head -1)
  echo -e "UUID=$UUID\t/\text4\trw,relatime,data=ordered\t0\t1\n" >> /target/etc/fstab
  _echo "========== [fstab] =========="
  cat /target/etc/fstab
  _echo "============================="
}

function prepare_chroot {
  _echo "Preparing chroot"
  cp /etc/resolv.conf /target/etc
  mount --bind /dev/ /target/dev/
  mount -t proc procfs /target/proc/
  mount -t sysfs sysfs /target/sys/
}

function set_password {
  echo -e "osimg.ru\nosimg.ru\n" | passwd
}

function enable_dhcp {
  systemctl enable dhcpcd
}

function disk_clean {
  rm -rf /target/in_chroot
  dd if=/dev/zero of=/target/zroes bs=1M || rm -f /target/zroes
}

function umount_disk {
  sync
  umount -l /target
  DISK=$(cat /in_container/device)
  rm -f /in_container/device
  losetup -d $DISK
}

function make_image_format {
  _echo "Converting disk image to $2 $1"
  rm -f disk.$1 || true
  qemu-img convert -O $1 disk.img disk.$1
  xz -e9 -T0 disk.$1
}

function convert_image {
  make_image_format qcow2 QEMU
  make_image_format vmdk VMWare
  make_image_format vhdx VirtualBox
  xz -e9 -T0 disk.img
}
