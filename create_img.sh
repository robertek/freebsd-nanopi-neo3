#!/bin/sh -x

FREEBSD_VER="13.0-RELEASE"
#FREEBSD_VER="14.0-CURRENT"
FREEBSD_BRANCH="releases"
#FREEBSD_BRANCH="snapshots"
UBOOT_VER="21.02.3"
POOL="nanopool"
HOSTNAME="nanopi"
PUB_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAuZYFW6wzyEzZpMwjBmqRgAQgsVjrxcAvZEyFN93Bs+WwwI8snVAi5hzD7qGb9CldiLOL7ON1dds0kSYJAVKEvgXJd9HXJi3RPuVr72REmOakgSJStGtAb2DqaOny4hDi8NkBu9rWs1lFJftugYz+RVU4EjdTjRZ0ZdIpZyeoSSass8Lby60AxULzhEXEZCse1Ge+lKgcWHWHuNuo+CVQIXSDfmzCCsUqu8KntAkSBCY8JiWKEjS6Ju+rD7wiG/ktdbq+EWfQmryInYT4SWMkK1z0wQ9GCnVXhm13q2kHY3td7Xk/klXEwrc+zDhsR5YIdwxmKF2S7wW5wZ6+ob7Wdw=="

UBOOT_MIRROR="https://mirrors.dotsrc.org/armbian-apt/pool/main/l/linux-u-boot-nanopineo3-current"
FREEBSD_MIRROR="https://download.freebsd.org/ftp/$FREEBSD_BRANCH/arm64"
DEV="md99"
DATASET="rpool/nanopi"
IMG="nanopi-neo3-$FREEBSD_VER.img"


create_dataset() {
	zfs list $DATASET >/dev/null 2>&1
	if [ $? -eq 1 ]
	then
		zfs create $DATASET
	fi
	WORK_DIR=`zfs get -H -o value mountpoint $DATASET`
	MOUNTPOINT="$WORK_DIR/$POOL"
	cd $WORK_DIR
}

fetch_uboot() {
	UBOOT_NAME="linux-u-boot-current-nanopineo3_${UBOOT_VER}_arm64"
	DATA="data.tar.xz"
	UBOOT_PATH="uboot"
	[ -f $UBOOT_NAME.deb ] || fetch $UBOOT_MIRROR/$UBOOT_NAME.deb
	ar -x $UBOOT_NAME.deb $DATA || exit 1
	tar -xJf $DATA --strip-components 3 usr/lib/$UBOOT_NAME || exit 1
	mv $UBOOT_NAME $UBOOT_PATH
	rm $DATA
}

create_img() {
	dd if=/dev/zero of=$IMG bs=1M count=4k || exit 1
	mdconfig -a -f $IMG -u $DEV || exit 1
	gpart create -s gpt $DEV || exit 1
	gpart add -a 4k -b 32768 -s 64M -t efi -l efi $DEV
	gpart add -a 4k -t freebsd-zfs $DEV
	newfs_msdos ${DEV}p1 || exit 1
}

install_uboot() {
	dd if=$UBOOT_PATH/idbloader.bin of=$IMG seek=64 conv=notrunc
	dd if=$UBOOT_PATH/uboot.img of=$IMG seek=16384 conv=notrunc
	dd if=$UBOOT_PATH/trust.bin of=$IMG seek=24576 conv=notrunc
}

create_pool() {
	mkdir $MOUNTPOINT
	zpool create -R $MOUNTPOINT $POOL ${DEV}p2

	zfs set compression=lz4 $POOL
	zfs create $POOL/ROOT
	zfs set mountpoint=none $POOL/ROOT
	zfs create $POOL/ROOT/freebsd-$FREEBSD_VER
	zfs set mountpoint=legacy $POOL/ROOT/freebsd-$FREEBSD_VER
	mount -t zfs $POOL/ROOT/freebsd-$FREEBSD_VER $MOUNTPOINT

	zfs create $POOL/DATA
	zfs set canmount=off $POOL/DATA
	zfs set mountpoint=/ $POOL/DATA
	zfs create $POOL/DATA/root
	zfs create $POOL/DATA/usr
	zfs set canmount=off $POOL/DATA/usr
	zfs create $POOL/DATA/var
	zfs set canmount=off $POOL/DATA/var

	zfs create $POOL/DATA/usr/home
	zfs create $POOL/DATA/usr/obj
	zfs create $POOL/DATA/usr/src
	zfs create $POOL/DATA/usr/ports

	zfs create $POOL/DATA/var/audit
	zfs create $POOL/DATA/var/cache
	zfs create $POOL/DATA/var/crash
	zfs create $POOL/DATA/var/mail
	zfs create $POOL/DATA/var/tmp
}

install_freebsd() {
	[ -f base.txz ] || fetch $FREEBSD_MIRROR/$FREEBSD_VER/base.txz
	[ -f kernel.txz ] || fetch $FREEBSD_MIRROR/$FREEBSD_VER/kernel.txz

	cd $MOUNTPOINT
	tar -xJf $WORK_DIR/base.txz
	tar -xJf $WORK_DIR/kernel.txz
	cd $WORK_DIR
}

configure_freebsd() {
	# create fstab
	echo "#/dev/label/efi /boot/efi msdosfs rw 0 0" > $MOUNTPOINT/etc/fstab
	echo "md /tmp mfs rw,noatime,-s50m 0 0" >> $MOUNTPOINT/etc/fstab
	echo "md /var/log mfs rw,noatime,-s15m 0 0" >> $MOUNTPOINT/etc/fstab
	# create rc.conf
	cat >$MOUNTPOINT/etc/rc.conf <<EOF
# network
hostname="$HOSTNAME"
ifconfig_DEFAULT="DHCP"

# powerd
powerd_enable="yes"

# ntpd
ntpd_enable="yes"
ntpd_sync_on_start="yes"

# sshd
sshd_enable="yes"

# zfs
zfs_enable="yes"

# disable sendmail
sendmail_enable="none"
sendmail_submit_enable="no"
sendmail_outbound_enable="no"
sendmail_msp_queue_enable="no"
EOF
	#create loader.conf
	cat >$MOUNTPOINT/boot/loader.conf <<EOF
# serial console
boot_serial="yes"

# geom
geom_label_load="yes"

# zfs
zfs_load="yes"
opensolaris_load="yes"
vfs.zfs.prefetch_disable=1

# usb3
fdt_overlays="rk3328-dwc3.dtbo"
EOF
	
	# permit ssh root login with key
	sed -e 's/#PermitRootLogin no/PermitRootLogin without-password/' -i '' $MOUNTPOINT/etc/ssh/sshd_config
	# set root public key
	mkdir $MOUNTPOINT/root/.ssh
	echo $PUB_KEY >> $MOUNTPOINT/root/.ssh/authorized_keys

	# copy the efi binary
	mount -t msdosfs /dev/${DEV}p1 $MOUNTPOINT/boot/efi
	mkdir -p $MOUNTPOINT/boot/efi/EFI/BOOT
	cp $MOUNTPOINT/boot/loader.efi $MOUNTPOINT/boot/efi/EFI/BOOT/bootaa64.efi
	umount $MOUNTPOINT/boot/efi
}

cleanup() {
	zpool export $POOL
	zpool import -N $POOL
	zfs set mountpoint=none $POOL/ROOT/freebsd-$FREEBSD_VER
	zpool set bootfs=$POOL/ROOT/freebsd-$FREEBSD_VER $POOL
	zpool export $POOL
	rmdir $MOUNTPOINT
	mdconfig -d -u $DEV
	rm -r $UBOOT_PATH
}

# main
create_dataset
fetch_uboot
create_img
install_uboot
create_pool
install_freebsd
configure_freebsd
cleanup
