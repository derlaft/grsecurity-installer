#!/bin/bash
#
# Install grsecurity from source, Debian version
#
# Author:  Rickard Bennison <rickard@0x539.se>
# License: WTFPL, see http://www.wtfpl.net/txt/copying/
# Version: 1.4.2
# Release: 2015-03-15
#

set -e
set -o pipefail
set -o errtrace

if test -o xtrace ; then
   output_cmd="true"
else
   output_cmd="echo"
fi

error_handler() {
   $output_cmd "Failed with exit code ${?}!"
   exit 1
}

trap "error_handler" ERR

if [ ! "$(whoami)" = "root" ]; then
	$output_cmd "This script needs to be run as root!"
	exit 1
fi

if [ -z "/etc/debian_version" ]; then
	$output_cmd "This script is made for Debian environments!"
	exit 1
fi

$output_cmd "Welcome to the automagic grsecurity Debian Installer

We will be working from /usr/src so make sure to have at least
4 GB of free space on the partition where /usr/src resides.

The installation will be carried out in the following steps:
1. Fetch the current version from grsecurity.net
2. Letting you choose which version you would like to install
3. Download PGP keys for download verification (first run only)

5. Download the kernel source from www.kernel.org
6. Download the grsecurity patch from grsecurity.net
7. Verify the downloads and extract the kernel
8. Apply the grsecurity kernel patch to the kernel source
9. Copy the current kernel configuration from /boot
10. Configure the kernel by
	a) running 'make menuconfig' if the current kernel doesn't support grsecurity
	b) running 'make oldconfig' if the current kernel supports grsecurity
11. Compile the kernel into a debian package
12. Install the debian package

"

cache_dir="/var/cache/grsecurity-installer"

exit_handler() {
   local exit_code="$?"
   $output_cmd "cache_dir: $cache_dir"
   ## TODO: remove cache_dir?
   if [ "$exit_code" = "0" ]; then
      $output_cmd "INFO: Kernel installation succeeded."
   else
      $output_cmd "ERROR: Kernel installation failed!"
   fi
   exit "$exit_code"
}

trap "exit_handler" EXIT

mkdir --parents "$cache_dir"

pushd "$cache_dir" >/dev/null

DOWNLOAD_STABLE=1
DOWNLOAD_STABLE2=1
DOWNLOAD_TESTING=1

if [ -f latest_stable_patch ]; then
	STABLE_MTIME=$(expr $(date +%s) - $(date +%s -r latest_stable_patch))

	if [ $STABLE_MTIME -gt 3600 ]; then
		rm latest_stable_patch
	else
		DOWNLOAD_STABLE=0
	fi
fi

if [ -f latest_stable2_patch ]; then
	STABLE2_MTIME=$(expr $(date +%s) - $(date +%s -r latest_stable2_patch))

	if [ $STABLE2_MTIME -gt 3600 ]; then
		rm latest_stable2_patch
	else
		DOWNLOAD_STABLE2=0
	fi
fi

if [ -f latest_test_patch ]; then
	TESTING_MIME=$(expr $(date +%s) - $(date +%s -r latest_test_patch))

	if [ $TESTING_MIME -gt 3600 ]; then
		rm latest_test_patch
	else
		DOWNLOAD_TESTING=0
	fi
fi

function secure_download {
	curl --continue-at - --progress-bar --remote-name --tlsv1 --proto =https $1
}

$output_cmd "==> Checking current versions of grsecurity ..."

if [ $DOWNLOAD_STABLE -eq 1 ]; then
	secure_download https://grsecurity.net/latest_stable_patch
fi

if [ $DOWNLOAD_STABLE2 -eq 1 ]; then
	secure_download https://grsecurity.net/latest_stable2_patch
fi

if [ $DOWNLOAD_TESTING -eq 1 ]; then
	secure_download https://grsecurity.net/latest_test_patch
fi

STABLE_VERSIONS=$(cat latest_stable_patch | sed -e 's/\.patch//g' | sed -e 's/grsecurity-//g')
STABLE2_VERSIONS=$(cat latest_stable2_patch | sed -e 's/\.patch//g' | sed -e 's/grsecurity-//g')
TESTING_VERSIONS=$(cat latest_test_patch | sed -e 's/\.patch//g' | sed -e 's/grsecurity-//g')

COUNTER=0

for x in ${STABLE_VERSIONS} ${STABLE2_VERSIONS}; do

	let COUNTER=COUNTER+1

	GRSEC=$(echo ${x} | sed -e 's/-/ /g' | awk '{print $1}')
	KERNEL=$(echo ${x} | sed -e 's/-/ /g' | awk '{print $2}')
	REVISION=$(echo ${x} | sed -e 's/-/ /g' | awk '{print $3}')

	VERSIONS[$COUNTER]=${x}-stable

	grsecurity_selections_output="$grsecurity_selections_output
==> $COUNTER. grsecurity version ${GRSEC} for kernel ${KERNEL}, revision ${REVISION} (stable version)"
done

for x in ${TESTING_VERSIONS}; do

	let COUNTER=COUNTER+1

	GRSEC=$(echo ${x} | sed -e 's/-/ /g' | awk '{print $1}')
	KERNEL=$(echo ${x} | sed -e 's/-/ /g' | awk '{print $2}')
	REVISION=$(echo ${x} | sed -e 's/-/ /g' | awk '{print $3}')

	VERSIONS[$COUNTER]=${x}-testing

	grsecurity_selections_output="$grsecurity_selections_output
==> $COUNTER. grsecurity version ${GRSEC} for kernel ${KERNEL}, revision ${REVISION} (testing version)"
done

if test -o xtrace ; then
   true "==> Please make your selection: [1-$COUNTER]: "
else
   echo "$grsecurity_selections_output"
   echo -n "==> Please make your selection: [1-$COUNTER]: "
fi

read SELECTION

DATA=${VERSIONS[$SELECTION]}
VERSION=$(echo $DATA | sed -e 's/-/ /g' | awk '{print $1}')
KERNEL=$(echo $DATA | sed -e 's/-/ /g' | awk '{print $2}')
REVISION=$(echo $DATA | sed -e 's/-/ /g' | awk '{print $3}')
BRANCH=$(echo $DATA | sed -e 's/-/ /g' | awk '{print $4}')
GRSEC=$(echo $VERSION-${KERNEL}-${REVISION})
KERNEL_BRANCH=$(echo ${KERNEL} | cut -c 1)

if [ "${BRANCH}" == "testing" ]; then
	TESTING=y
else
	TESTING=n
fi

$output_cmd "==> Installing grsecurity ${BRANCH} version $VERSION using kernel version ${KERNEL} ... "

if [ ! -f spender-gpg-key.asc ]; then
	$output_cmd "==> Downloading grsecurity GPG keys for package verification ... "
	secure_download https://grsecurity.net/spender-gpg-key.asc

	$output_cmd -n "==> Importing grsecurity GPG key ... "
	gpg --import spender-gpg-key.asc
fi

if [ $(gpg --list-keys | grep 6092693E | wc -l) -eq 0 ]; then
	$output_cmd -n "==> Fetching kernel GPG key ... "
	gpg --recv-keys 647F28654894E3BD457199BE38DBBDC86092693E
fi

if [ -h linux ]; then
	rm linux
fi

if [ ! -f linux-${KERNEL}.tar.xz ] && [ ! -f linux-${KERNEL}.tar ]; then
	$output_cmd "==> Downloading kernel version ${KERNEL} ... "

	if [ ${KERNEL_BRANCH} -eq 2 ]; then
		secure_download https://www.kernel.org/pub/linux/kernel/v2.6/longterm/v2.6.32/linux-${KERNEL}.tar.sign
		secure_download https://www.kernel.org/pub/linux/kernel/v2.6/longterm/v2.6.32/linux-${KERNEL}.tar.xz
	elif [ ${KERNEL_BRANCH} -eq 3 ]; then
		secure_download https://www.kernel.org/pub/linux/kernel/v3.0/linux-${KERNEL}.tar.sign
		secure_download https://www.kernel.org/pub/linux/kernel/v3.0/linux-${KERNEL}.tar.xz
	fi

	$output_cmd -n "==> Extracting linux-${KERNEL}.tar.xz ... "
	unxz linux-${KERNEL}.tar.xz
fi

$output_cmd "==> Verifying linux-${KERNEL}.tar ... "
gpg --verify linux-${KERNEL}.tar.sign

$output_cmd "Continue? [y/N] "
read verification_continue
if [ ! "$verification_continue" = "y" ]; then
   exit 1
fi

if [ ! -f grsecurity-${GRSEC}.patch ]; then
	$output_cmd "==> Downloading grsecurity patch version ${GRSEC} ... "

	if [ "${TESTING}" == "y" ]; then
		secure_download https://grsecurity.net/test/grsecurity-${GRSEC}.patch
		secure_download https://grsecurity.net/test/grsecurity-${GRSEC}.patch.sig
	else
		secure_download https://grsecurity.net/stable/grsecurity-${GRSEC}.patch
		secure_download https://grsecurity.net/stable/grsecurity-${GRSEC}.patch.sig
	fi
fi

$output_cmd "==> Verifying grsecurity-${GRSEC}.patch ... "
gpg --verify grsecurity-${GRSEC}.patch.sig

$output_cmd "Continue? [y/N] "
read verification_continue
if [ ! "$verification_continue" = "y" ]; then
   exit 1
fi

if [ ! -d linux-${KERNEL} ]; then
	$output_cmd "==> Unarchiving linux-${KERNEL}.tar ... "
	tar xf linux-${KERNEL}.tar
fi

if [ ! -d linux-${KERNEL}-grsec ]; then
	mv linux-${KERNEL} linux-${KERNEL}-grsec
fi

ln -s linux-${KERNEL}-grsec linux
pushd linux >/dev/null

patch_exit_code="0"
patch --silent -p1 --forward --dry-run < ../grsecurity-${GRSEC}.patch || { patch_exit_code="$?" ; true; };

if [ "$patch_exit_code" = "0" ]; then
	$output_cmd "==> Applying patch ... "
	patch --silent -p1 --forward < ../grsecurity-${GRSEC}.patch
else
	$output_cmd "==> Patch seems to already been applied, skipping ..."
fi

# Fix http://bugs.debian.org/cgi-bin/bugreport.cgi?bug=638012
#
# the lguest directory seems to be moving around quite a bit, as of 3.3.something
# it resides under the tools directory. The best approach should be to just search for it
if [ ${KERNEL_BRANCH} -eq 3 ] && [ ! -s Documentation/lguest ]; then
	pushd Documentation >/dev/null
	find .. -name lguest.c | xargs dirname | xargs ln -s
	popd >/dev/null
fi

cp /boot/config-$(uname -r) .config
if [ -z $(grep "CONFIG_GRKERNSEC=y" .config) ]; then
	$output_cmd "==> Current kernel doesn't seem to be running grsecurity. Running 'make menuconfig'"
	make menuconfig
else
	$output_cmd "==> Current kernel seems to be running grsecurity. Running 'make oldconfig' ... "
	yes "" | make oldconfig
	$output_cmd "OK"
fi

$output_cmd "==> Building kernel ... "

NUM_CORES=$(grep -c ^processor /proc/cpuinfo)

make-kpkg clean
$output_cmd "phase 1 OK ... "

make-kpkg --jobs=${NUM_CORES} --initrd --revision=${REVISION} kernel_image
$output_cmd "phase 2 OK ... "

$output_cmd -n "==> Installing kernel ... "
dpkg -i linux-image-${KERNEL}-grsec_${REVISION}_*.deb

$output_cmd "OK"
