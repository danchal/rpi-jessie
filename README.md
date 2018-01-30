# rpi-debian

Debian image builder for Raspberry Pi.

Based on worky by Klaus M Pfeiffer, http://www.kmp.or.at/~klaus/raspberry/build_rpi_sd_card.sh

rpi-debian will:
  - create, partition and format an image or disk
  - install and configure base debian system with Open SSH server
  - download rpi-update which will install the nescessary firmware and bootloader for RPi
  - install a first-run script that will re-configure SSH server keys and resize partition to fill the disk on the first run.

### Requirements
Debian host with the following packages installed:

```binfmt-support qemu qemu-user-static debootstrap kpartx lvm2 dosfstools```

### Usage

Optionally, replace id_rsa.pub file with a link to your ssh public key (most likely ~/.ssh/id_rsa.pub) if you want to log into the RPi with your keypair.

```sudo ./build_image.sh [block_device|image_file]```

You can pass block_device (/dev/mmcblk0) to create the image directly on a card, or specify image_file you would like to create. If neither is given, an image file called rpi_debian_{arch}\_{release}\_{date}.img will be created. You can write this image to a card using dd or other tools.

### Command-line parameters
The script accepts shell-variables to configure specific features during build.

E.g.

```
sudo BUILD_HTTP_PROXY="yourproxy:port" ./build_image.sh
sudo DEB_ARCH="armhf" ./build_image.sh
sudo DEB_ARCH="armel" ./build_image.sh
```

root password is ```raspberry```