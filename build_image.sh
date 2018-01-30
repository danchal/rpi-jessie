#!/bin/bash

# build your own Raspberry Pi SD card
#
# original by Klaus M Pfeiffer, http://www.kmp.or.at/~klaus/raspberry/build_rpi_sd_card.sh, 2012-06-24
# updated by Dovydas Stepanavicius for Jessie, https://github.com/dovydas/rpi-jessie, 2015-10-12

# you need at least
# apt-get install binfmt-support qemu qemu-user-static debootstrap kpartx lvm2 dosfstools

DEB_MIRROR="deb.debian.org"
DEB_MIRROR_BUILD="http://${BUILD_HTTP_PROXY:+${BUILD_HTTP_PROXY}/}${DEB_MIRROR}"

# Image size in Mb
imagesize="1000"
# Boot partition size
bootsize="64M"
deb_release="stretch"
DEB_ARCH=${DEB_ARCH:=armhf}

scriptroot=$(pwd)
# Build root
buildenv=$(pwd)/build

# Additional scripts
scripts=$(pwd)/scripts

rootfs="${buildenv}/rootfs"
bootfs="${rootfs}/boot"

mydate=`date +%Y%m%d`

if [ $EUID -ne 0 ]; then
  echo "this tool must be run as root"
  exit 1
fi

# If no block device or image supplied
if [ "$1" == "" ]; then
  image="$(pwd)/rpi_debian_${DEB_ARCH}_${deb_release}_${mydate}.img"
else
  # If $1 is block device
  if [ -b $1 ]; then
    device=$1
  else
    image=$1
    if [ -f $image ]; then
      read -p "The file ${image} already exists. Do you want to overwrite it? [y/N] " -n 1 -r
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
      fi
      rm -y $image
    fi
  fi
fi

if [ "$device" == "" ]; then
  echo "no block device given, creating an image"
  mkdir -p $buildenv
  dd if=/dev/zero of=$image bs=1MB count=$imagesize
  device=`losetup -f --show $image`
  echo "image $image created and mounted as $device"
else
  dd if=/dev/zero of=$device bs=512 count=1
fi

fdisk $device << EOF
n
p
1

+$bootsize
t
c
n
p
2


w
EOF


if [ "$image" != "" ]; then
  losetup -d $device
  device=`kpartx -va $image | sed -E 's/.*(loop[0-9])p.*/\1/g' | head -1`
  device="/dev/mapper/${device}"
  bootp=${device}p1
  rootp=${device}p2
else
  if ! [ -b ${device}1 ]; then
    bootp=${device}p1
    rootp=${device}p2
    if ! [ -b ${bootp} ]; then
      echo "uh, oh, something went wrong, can't find bootpartition neither as ${device}1 nor as ${device}p1, exiting."
      exit 1
    fi
  else
    bootp=${device}1
    rootp=${device}2
  fi  
fi

# Let the kernel update partition mappings
sleep 2

if ! [ -b ${bootp} ];  then
  echo "${bootp} does not exist. Aborting"
  exit 1
fi

mkfs.vfat $bootp
mkfs.ext4 $rootp
mkdir -p $rootfs
mount $rootp $rootfs

cd $rootfs

echo "Bootstrapping the image"

debootstrap --foreign --arch $DEB_ARCH $deb_release $rootfs ${DEB_MIRROR_BUILD}/debian
cp /usr/bin/qemu-arm-static usr/bin/
LANG=C chroot $rootfs /debootstrap/debootstrap --second-stage

mount $bootp $bootfs

echo "deb http://${DEB_MIRROR}/debian $deb_release main contrib non-free
" > etc/apt/sources.list

[ -n "${BUILD_HTTP_PROXY}" ] && echo "Acquire::http::Proxy \"http://${BUILD_HTTP_PROXY}/\";
" > etc/apt/apt.conf.d/02buildproxy

echo "dwc_otg.lpm_enable=0 console=serial0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 elevator=deadline fsck.repair=yes rootwait" > boot/cmdline.txt

echo "/dev/mmcblk0p2  /		ext4    noatime        0       0
proc            /proc           proc    defaults        0       0
/dev/mmcblk0p1  /boot           vfat    defaults        0       0
" > etc/fstab

echo "raspberrypi" > etc/hostname

echo "auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
" > etc/network/interfaces

echo "vchiq
snd_bcm2835
" >> etc/modules

echo "console-common	console-data/keymap/policy	select	Select keymap from full list
console-common	console-data/keymap/full	select	de-latin1-nodeadkeys
" > debconf.set

cp -R ${scripts}/* .

mkdir -m 700 root/.ssh
if [ -f "${scriptroot}/id_rsa.pub" ] ; then
    cat "${scriptroot}/id_rsa.pub" > root/.ssh/authorized_keys
    chmod 600 root/.ssh/authorized_keys
fi
echo "root:raspberry" | chpasswd

echo "#!/bin/bash
debconf-set-selections /debconf.set
rm -f /debconf.set
apt-get update 
apt-get -y install git-core binutils ca-certificates wget curl
wget https://raw.githubusercontent.com/Hexxeh/rpi-update/master/rpi-update -O /usr/bin/rpi-update
chmod +x /usr/bin/rpi-update
UPDATE_SELF=0 SKIP_BACKUP=1 /usr/bin/rpi-update
apt-get -y install locales console-common ntp openssh-server less vim parted
sed -i -e 's/KERNEL\!=\"eth\*|/KERNEL\!=\"/' /lib/udev/rules.d/75-persistent-net-generator.rules
rm -f /etc/udev/rules.d/70-persistent-net.rules
rm -f third-stage
" > third-stage
chmod +x third-stage

echo "Installing packages"
LANG=C chroot $rootfs /third-stage

echo "#!/bin/bash
apt-get -f install
apt-get clean
rm -f cleanup
service ntp stop
service ssh stop
systemctl enable rpi-firstrun.service
rm -f /etc/apt/apt.conf.d/02buildproxy
" > cleanup
chmod +x cleanup
LANG=C chroot $rootfs /cleanup

cd -

umount $bootp
umount $rootp

if [ "$image" != "" ]; then
  kpartx -d $image
  echo "created image $image"
fi


echo "done."

