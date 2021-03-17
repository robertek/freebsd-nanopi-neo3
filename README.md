# Freebsd on NanoPI NEO3 with zfs

This is simple creation script of image for NanoPI NEO3.
It creates ZFS root and set up root ssh login using ssh key.

## Requirements

 - Freebsd system with ZFS pool
 - microSD card >=4GB
 - NanoPI NEO3 board

## Image Creation

```
$ fetch https://raw.githubusercontent.com/robertek/freebsd-nanopi-neo3/main/create_img.sh
$ chmod +x create_img.sh
$ ./create_img.sh
```

You may edit the variables at the beginning of `create_img.sh` to set up things like which dataset of your ZFS will be used.

Mainly is suggested to change the PUB_KEY variable with your ssh pub key

## Image upload and start

Copy the image to the sdcard, use the correct path to the image and the correct mmc device.

```
dd if=/rpool/nanopi/nanopi-neo3-13.0.img of=/dev/mmcXXX bs=1M
```

Then you can plug the SD card to NanoPI and boot it.
It is adwised to have the LAN cable connected.

You may use serial cable, but it is not needed.
If you do, the speed is 1500000.

Example connecting from my linux laptop:
```
$ screen /dev/ttyUSB0 1500000
```

## TODO

 - create package for uboot directly under FreeBSD with correct patches. Now the uboot for NanoPI R2S is used (which is nearly the same, but not exactly).
