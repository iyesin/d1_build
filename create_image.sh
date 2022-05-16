#!/bin/sh
#
# Author. Tim Molteno tim@molteno.net
# (C) 2022.
# http://www.orangepi.org/Docs/Makingabootable.html

# Make Image the first parameter of this script is the directory containing all the files needed
# This is done to allow the script to be run outside of Docker for testing.
OUTPORT=$1

IMG=${OUTPORT}/licheerv.img

echo "Creating Blank Image ${IMG}"

dd if=/dev/zero of=${IMG} bs=1M count=3500

# Setup Loopback device
LOOP=`losetup -f --show ${IMG} | cut -d'/' -f3`
LOOPDEV=/dev/${LOOP}
echo "Partitioning loopback device ${LOOPDEV}"


dd if=/dev/zero of=${LOOPDEV} bs=1M count=200
parted -s -a optimal -- ${LOOPDEV} mklabel gpt
parted -s -a optimal -- ${LOOPDEV} mkpart primary ext2 40MiB 100MiB
parted -s -a optimal -- ${LOOPDEV} mkpart primary ext4 100MiB -1GiB
parted -s -a optimal -- ${LOOPDEV} mkpart primary linux-swap -1GiB 100%

kpartx -av ${LOOPDEV}

mkfs.ext2 /dev/mapper/${LOOP}p1
mkfs.ext4 /dev/mapper/${LOOP}p2
mkswap /dev/mapper/${LOOP}p3

# Burn U-boot
echo "Burning u-boot to ${LOOPDEV}"

dd if=${OUTPORT}/boot0_sdcard_sun20iw1p1.bin of=${LOOPDEV} bs=8192 seek=16

# Copy files https://linux-sunxi.org/Allwinner_Nezha
dd if=${OUTPORT}/u-boot.toc1 of=${LOOPDEV} bs=512 seek=32800


# Copy Files, first the boot partition
echo "Mounting  partitions ${LOOPDEV}"
MNTPOINT=/sdcard_rootfs
BOOTPOINT=/sdcard_boot

mkdir -p ${BOOTPOINT}
mount /dev/mapper/${LOOP}p1 ${BOOTPOINT}

# Boot partition
cp ${OUTPORT}/Image.gz "${BOOTPOINT}/"
cp ${OUTPORT}/Image "${BOOTPOINT}/"
# install U-Boot
cp ${OUTPORT}/boot.scr "${BOOTPOINT}/"

umount ${BOOTPOINT}
rm -rf ${BOOTPOINT}



mkdir -p ${MNTPOINT}
mount /dev/mapper/${LOOP}p2 ${MNTPOINT}

# Copy the rootfs
cp -a ${OUTPORT}/rv64-port/* ${MNTPOINT}


# install kernel and modules


cd /build/linux-build && make ARCH=riscv INSTALL_MOD_PATH=${MNTPOINT} modules_install

MODDIR=`ls ${MNTPOINT}/lib/modules/`
echo "Creating wireless module in ${MODDIR}"
install -v -D -p -m 644 /build/rtl8723ds/8723ds.ko ${MNTPOINT}/lib/modules/${MODDIR}/kernel/drivers/net/wireless/8723ds.ko

rm "${MNTPOINT}/lib/modules/${MODDIR}/build"
rm "${MNTPOINT}/lib/modules/${MODDIR}/source"

depmod -a -b "${MNTPOINT}" "${MODDIR}"
echo '8723ds' >> "${MNTPOINT}/etc/modules"



# Clean Up
umount ${MNTPOINT}
rm -rf ${MNTPOINT}

kpartx -d ${LOOPDEV}
losetup -d ${LOOPDEV}
