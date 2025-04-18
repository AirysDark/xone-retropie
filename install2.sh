#!/usr/bin/env sh

set -eu

sudo apt-get install dkms
sudo apt-get install curl
sudo apt-get install cabextract

if [ "$(id -u)" -ne 0 ]; then
    echo 'This script must be run as root!' >&2
    exit 1
fi

if ! [ -x "$(command -v dkms)" ]; then
    echo 'This script requires DKMS!' >&2
    exit 1
fi

if [ -n "$(dkms status xone)" ]; then
    echo 'Driver is already installed!' >&2
    exit 1
fi

if [ -f /usr/local/bin/xow ]; then
    echo 'Please uninstall xow!' >&2
    exit 1
fi

if [ -n "${SUDO_USER:-}" ]; then
    # Run as normal user to prevent "unsafe repository" error
    version=$(sudo -u "$SUDO_USER" git describe --tags 2> /dev/null || echo unknown)
else
    version=unknown
fi

source="/usr/src/xone-$version"
log="/var/lib/dkms/xone/$version/build/make.log"

echo "Installing xone $version..."
cp -r . "$source"
find "$source" -type f \( -name dkms.conf -o -name '*.c' \) -exec sed -i "s/#VERSION#/$version/" {} +

if [ "${1:-}" != --release ]; then
    echo 'ccflags-y += -DDEBUG' >> "$source/Kbuild"
fi

if dkms install -m xone -v "$version"; then
    # The blacklist should be placed in /usr/local/lib/modprobe.d for kmod 29+
    install -D -m 644 install/modprobe.conf /etc/modprobe.d/xone-blacklist.conf

    # Avoid conflicts between xpad and xone
    if lsmod | grep -q '^xpad'; then
        modprobe -r xpad
    fi

    # Avoid conflicts between mt76x2u and xone
    if lsmod | grep -q '^mt76x2u'; then
        modprobe -r mt76x2u
    fi
else
    if [ -r "$log" ]; then
        cat "$log" >&2
    fi

    exit 1
fi

driver_url='http://download.windowsupdate.com/c/msdownload/update/driver/drvs/2017/07/1cd6a87c-623f-4407-a52d-c31be49e925c_e19f60808bdcbfbd3c3df6be3e71ffc52e43261e.cab'
firmware_hash='48084d9fa53b9bb04358f3bb127b7495dc8f7bb0b3ca1437bd24ef2b6eabdf66'

curl -L -o driver.cab "$driver_url"
cabextract -F FW_ACC_00U.bin driver.cab
echo "$firmware_hash" FW_ACC_00U.bin | sha256sum -c
mv FW_ACC_00U.bin /lib/firmware/xow_dongle.bin
rm driver.cab
