#!/bin/bash
# Port of pkgbuild anbox-image-gapps to work on debian based distros.
#
# Contributor: Mark Wagie <mark dot wagie at tutanota dot com>
# Contributor: Robosky <fangyuhao0612 at gmail dot com>
# Contributor: Tibério A. dos Santos <tiberius.santos at yahoo dot com>

if [[ $(id -u) -ne 0 ]]; then
    echo "You must be root"
    exit 1
fi

echo "Android image for running in Anbox, with OpenGApps and Houdini"
apt install adb aria2 anbox curl lzip squashfs-tools tar unzip

srcdir="/var/lib/anbox/build"
pkgver=2018.07.19
pkgrel=13
_gapps_rel="$(curl -s -L https://api.github.com/repos/opengapps/x86_64/releases/latest | head -n 10 | grep tag_name | sed -r 's/.*\"([0-9]+)\".*/\1/')"
_gapps_src="https://downloads.sourceforge.net/project/opengapps/x86_64/$_gapps_rel/open_gapps-x86_64-7.1-pico-$_gapps_rel.zip"
_gapps_md5="$(curl -s -L $_gapps_src.md5 | sed -r 's/^([0-9a-z]+).*/\1/')"
_gapps_list=(
    'gsfcore-all'
    'gsflogin-all'
    'gmscore-x86_64'
    'vending-x86_64'
)
source=(
    "http://build.anbox.io/android-images/${pkgver//./\/}/android_amd64.img"
    "houdini_y.sfs::http://dl.android-x86.org/houdini/7_y/houdini.sfs"
    "houdini_z.sfs::http://dl.android-x86.org/houdini/7_z/houdini.sfs"
    "$_gapps_src"
)

systemctl stop anbox-container-manager.service
mkdir -p "${srcdir}"
pushd "${srcdir}"

for p in ${source[*]}; do
    if [[ "${p}" =~ '::' ]]; then 
        aria2c -c -x 4 -k 5M "${p#*::}" --out "${p%::*}"
    else
        aria2c -c -x 4 -k 5M "${p}"
    fi
done

# unpack anbox image
mkdir -p squashfs-root
rm -rf ./squashfs-root/*
unsquashfs -f -d ./squashfs-root ./android_amd64.img

# load houdini_y
mkdir -p houdini_y
rm -rf ./houdini_y/*
unsquashfs -f -d ./houdini_y ./houdini_y.sfs

mkdir -p ./squashfs-root/system/lib/arm
cp -r ./houdini_y/* ./squashfs-root/system/lib/arm
mv ./squashfs-root/system/lib/arm/libhoudini.so ./squashfs-root/system/lib/libhoudini.so

# load houdini_z
mkdir -p houdini_z
rm -rf ./houdini_z/*
unsquashfs -f -d ./houdini_z ./houdini_z.sfs

mkdir -p ./squashfs-root/system/lib64/arm64
cp -r ./houdini_z/* ./squashfs-root/system/lib64/arm64
mv ./squashfs-root/system/lib64/arm64/libhoudini.so ./squashfs-root/system/lib64/libhoudini.so

# add houdini parser
mkdir -p ./squashfs-root/system/etc/binfmt_misc
echo ':arm_exe:M::\x7f\x45\x4c\x46\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28::/system/lib/arm/houdini:P' >> ./squashfs-root/system/etc/binfmt_misc/arm_exe
echo ':arm_dyn:M::\x7f\x45\x4c\x46\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x03\x00\x28::/system/lib/arm/houdini:P' >> ./squashfs-root/system/etc/binfmt_misc/arm_dyn
echo ':arm64_exe:M::\x7f\x45\x4c\x46\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7::/system/lib64/arm64/houdini64:P' >> ./squashfs-root/system/etc/binfmt_misc/arm64_exe
echo ':arm64_dyn:M::\x7f\x45\x4c\x46\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x03\x00\xb7::/system/lib64/arm64/houdini64:P' >> ./squashfs-root/system/etc/binfmt_misc/arm64_dyn

# add features
sed -i '/<\/permissions>/d' ./squashfs-root/system/etc/permissions/anbox.xml
sed -i '/<unavailable-feature name=\"android.hardware.wifi\" \/>/d' ./squashfs-root/system/etc/permissions/anbox.xml
sed -i '/<unavailable-feature name=\"android.hardware.bluetooth\" \/>/d' ./squashfs-root/system/etc/permissions/anbox.xml

echo '    <feature name="android.hardware.touchscreen" />
<feature name="android.hardware.audio.output" />
<feature name="android.hardware.camera" />
<feature name="android.hardware.camera.any" />
<feature name="android.hardware.location" />
<feature name="android.hardware.location.gps" />
<feature name="android.hardware.location.network" />
<feature name="android.hardware.microphone" />
<feature name="android.hardware.screen.portrait" />
<feature name="android.hardware.screen.landscape" />
<feature name="android.hardware.wifi" />
<feature name="android.hardware.bluetooth" />' >> ./squashfs-root/system/etc/permissions/anbox.xml
echo '</permissions>' >> ./squashfs-root/system/etc/permissions/anbox.xml

# set processors
sed -i '/^ro.product.cpu.abilist=x86_64,x86/ s/$/,arm64-v8a,armeabi-v7a,armeabi/' ./squashfs-root/system/build.prop
sed -i '/^ro.product.cpu.abilist32=x86/ s/$/,armeabi-v7a,armeabi/' ./squashfs-root/system/build.prop
sed -i '/^ro.product.cpu.abilist64=x86_64/ s/$/,arm64-v8a/' ./squashfs-root/system/build.prop

# enable nativebridge
echo 'persist.sys.nativebridge=1' >> ./squashfs-root/system/build.prop
sed -i 's/ro.dalvik.vm.native.bridge=0/ro.dalvik.vm.native.bridge=libhoudini.so/' ./squashfs-root/default.prop

# enable opengles
echo 'ro.opengles.version=131072' >> ./squashfs-root/system/build.prop

# install gapps
unzip open_gapps-x86_64-7.1-pico-$_gapps_rel.zip
for i in ${_gapps_list[*]}; do
    mkdir -p $i
    rm -rf ./$i/*
    tar --lzip -xvf ./Core/$i.tar.lz
    cp -r ./$i/nodpi/priv-app/* ./squashfs-root/system/priv-app/
done

# rebuild the image
mksquashfs ./squashfs-root ../android.img -noappend -b 131072 -comp xz -Xbcj x86

# cleanup temporary files
popd
rm -rf "${srcdir}"
systemctl start anbox-container-manager.service
