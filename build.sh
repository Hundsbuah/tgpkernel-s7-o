#!/bin/bash
# -----------------------------
# TGPKERNEL BUILD SCRIPT 4.11.4
# Created by @djb77
# -----------------------------

# Set Variables
export RDIR=$(pwd)
export KERNELNAME=TGPKernel
export VERSION_NUMBER=$(<build/version)
export ARCH=arm64
export SUBARCH=arm64
export PLATFORM_VERSION=8.0.0
export BUILD_CROSS_COMPILE=~/android/toolchains/aarch64-linux-android-4.9/bin/aarch64-linux-android-
BUILD_JOB_NUMBER=`grep processor /proc/cpuinfo|wc -l`
WORKDIR=$RDIR/.work
ZIPDIR=$RDIR/.work_zip
OUTPUT=$RDIR/.output
OUTDIR=$WORKDIR/arch/$ARCH/boot
KERNELCONFIG=.work/arch/arm64/configs/build_defconfig
KEEP=no
SILENT=no

########################################################################################################################################################
# Functions

# Clean Function
FUNC_CLEAN()
{
echo ""
echo "Deleting old work files ..."
echo ""
if [ -d $WORKDIR ]; then
sudo chown 0:0 $WORKDIR 2>/dev/null
sudo chmod -R 777 $WORKDIR
sudo rm -rf $WORKDIR
fi
}

# Full clean Function
FUNC_CLEAN_ALL()
{
FUNC_CLEAN
[ -d $ZIPDIR ] && rm -rf $ZIPDIR
[ -d $OUTPUT ] && rm -rf $OUTPUT
[ -d "$RDIR/net/wireguard" ] && rm -rf $RDIR/net/wireguard
exit
}

# Clean ccache
FUNC_CLEAN_CCACHE()
{
echo ""
ccache -C
echo ""
exit
}

# Copy files to work locations
FUNC_COPY()
{
echo "Copying work files ..."
echo ""
mkdir -p $WORKDIR/arch
mkdir -p $WORKDIR/firmware
mkdir -p $WORKDIR/include
mkdir -p $WORKDIR/init
mkdir -p $WORKDIR/net
mkdir -p $WORKDIR/ramdisk/ramdisk
sudo chown 0:0 $WORKDIR/ramdisk/ramdisk 2>/dev/null
mkdir -p $WORKDIR/scripts
cp -rf $RDIR/arch/arm/ $WORKDIR/arch/
cp -rf $RDIR/arch/arm64/ $WORKDIR/arch/
cp -rf $RDIR/arch/x86 $WORKDIR/arch/
cp -rf $RDIR/firmware $WORKDIR/
cp -rf $RDIR/include $WORKDIR/
cp -rf $RDIR/init $WORKDIR/
cp -rf $RDIR/net $WORKDIR/
cp -rf $RDIR/build/aik/* $WORKDIR/ramdisk
cp -rf $RDIR/scripts $WORKDIR/
sudo cp -rf $RDIR/build/ramdisk/* $WORKDIR/ramdisk 
}

# Prepare for zimage build
FUNC_PREPARE()
{
cp -f $WORKDIR/arch/arm64/configs/tgpkernel_defconfig $KERNELCONFIG
[ $MODEL = "S7" ] && cat $WORKDIR/arch/arm64/configs/herolte_defconfig >> $KERNELCONFIG
[ $MODEL = "S7E" ] && cat $WORKDIR/arch/arm64/configs/hero2lte_defconfig >> $KERNELCONFIG
}

# Build zimage Function
FUNC_BUILD_KERNEL()
{
cd $WORKDIR
sudo find . -name \.placeholder -type f -delete
cd ..
if [ $SILENT = "no" ]; then
	echo "Loading configuration ..."
	echo ""
	make -C $RDIR O=.work -j$BUILD_JOB_NUMBER ARCH=$ARCH CROSS_COMPILE=$BUILD_CROSS_COMPILE ../../../$KERNELCONFIG || exit -1
	echo ""
	echo "Compiling zImage ..."
	echo ""
	make -C $RDIR O=.work -j$BUILD_JOB_NUMBER ARCH=$ARCH CROSS_COMPILE=$BUILD_CROSS_COMPILE || exit -1
	echo ""
else
	echo "Loading configuration ..."
	echo ""
	make -s -C $RDIR O=.work -j$BUILD_JOB_NUMBER ARCH=$ARCH CROSS_COMPILE=$BUILD_CROSS_COMPILE ../../../$KERNELCONFIG || exit -1
	echo ""
	echo "Compiling zImage ..."
	echo ""
	make -s -C $RDIR O=.work -j$BUILD_JOB_NUMBER ARCH=$ARCH CROSS_COMPILE=$BUILD_CROSS_COMPILE || exit -1
	echo ""
fi
}

# Build Ramdisk Function
FUNC_BUILD_RAMDISK()
{
sudo cp $WORKDIR/arch/$ARCH/boot/Image $WORKDIR/ramdisk/split_img/boot.img-zImage
sudo cp $WORKDIR/arch/$ARCH/boot/dtb.img $WORKDIR/ramdisk/split_img/boot.img-dtb
if [ $MODEL = "S7" ]; then
	sudo sed -i -- 's/G935/G930/g' $WORKDIR/ramdisk/ramdisk/default.prop
	sudo sed -i -- 's/G935/G930/g' $WORKDIR/ramdisk/ramdisk/sbin/tgpkernel.sh
	sudo sed -i -- 's/hero2lte/herolte/g' $WORKDIR/ramdisk/ramdisk/default.prop
	sudo sed -i -- 's/hero2lte/herolte/g' $WORKDIR/ramdisk/ramdisk/sbin/tgpkernel.sh
	sudo sed -i -- 's/SRPOI30A001KU/SRPOI17A001KU/g' $WORKDIR/ramdisk/split_img/boot.img-board
	cd $WORKDIR/ramdisk
	./repackimg.sh
else
	cd $WORKDIR/ramdisk
	./repackimg.sh
fi
}

# Build boot.img Function
FUNC_BUILD_BOOTIMG()
{
	(
	FUNC_CLEAN
	FUNC_COPY
	FUNC_PREPARE
	FUNC_BUILD_KERNEL
	FUNC_BUILD_RAMDISK
	) 2>&1	 | tee -a $LOGFILE
}

# Build Zip Function
FUNC_BUILD_ZIP()
{
echo "Preparing Zip File  ..."
echo ""
echo "- Building anykernel2.zip file ..."
cd $ZIPDIR/tgpkernel/anykernel2
rm -f $ZIPDIR/tgpkernel/anykernel2/.git.zip
[ -d $ZIPDIR/tgpkernel/anykernel2/.git ] && rm -rf $ZIPDIR/tgpkernel/anykernel2/.git
zip -9gq anykernel2.zip -r * -x "*~"
if [ -n `which java` ]; then
	echo "  Java detected, signing zip"
	AK2_NAME=anykernel2.zip
	mv $AK2_NAME unsigned-$AK2_NAME
	java -Xmx1024m -jar $RDIR/build/signapk/signapk.jar -w $RDIR/build/signapk/testkey.x509.pem $RDIR/build/signapk/testkey.pk8 unsigned-$AK2_NAME $AK2_NAME
	rm unsigned-$AK2_NAME
fi
echo "  Deleting unwanted files"
rm -rf META-INF tgpkernel patch tools anykernel.sh README.md
echo "- Building system.tar.xz file ..."
cd $ZIPDIR/tgpkernel
tar -cf - system/ | xz -9 -c - > system.tar.xz
mv -f system.tar.xz $ZIPDIR/tgpkernel/files/system.tar.xz
rm -rf $ZIPDIR/tgpkernel/system
echo "- Building kernels.tar.xz file ..."
tar -cf - kernels/ | xz -9 -c - > kernels.tar.xz
mv -f kernels.tar.xz $ZIPDIR/tgpkernel/files/kernels.tar.xz
rm -rf $ZIPDIR/tgpkernel/kernels
echo "- Building final zip ..."
cd $ZIPDIR
zip -9gq $ZIP_NAME -r META-INF/ -x "*~"
zip -9gq $ZIP_NAME -r tgpkernel/ -x "*~" 
if [ -n `which java` ]; then
	echo "  Java detected, signing zip"
	mv $ZIP_NAME unsigned-$ZIP_NAME
	java -Xmx1024m -jar $RDIR/build/signapk/signapk.jar -w $RDIR/build/signapk/testkey.x509.pem $RDIR/build/signapk/testkey.pk8 unsigned-$ZIP_NAME $ZIP_NAME
	rm unsigned-$ZIP_NAME
fi
chmod a+r $ZIP_NAME
mv -f $ZIP_FILE_TARGET $OUTPUT/$ZIP_NAME
cd $RDIR
}

########################################################################################################################################################
# Main script

# Check command line for switches
[ "$1" = "0" ] && FUNC_CLEAN_ALL
[ "$1" = "00" ] && FUNC_CLEAN_CCACHE
if [ "$1" = "-k" ] || [ "$2" = "-k" ]; then
KEEP=yes
fi
if [ "$1" = "-s" ] || [ "$2" = "-s" ]; then
SILENT=yes
fi
if [ "$1" = "-ks" ] || [ "$2" = "-ks" ]; then
SILENT=yes
KEEP=yes
fi

# Compile Kernels
echo ""
echo "-----------------------------------"
echo "- TGPKernel Build Script by djb77 -"
echo "-----------------------------------"
echo ""
sudo echo ""
[ -d "$WORKDIR" ] && rm -rf $WORKDIR
[ -d "$ZIPDIR" ] && rm -rf $ZIPDIR
[ -d "$OUTPUT" ] && rm -rf $OUTPUT
[ -d "$RDIR/net/wireguard" ] && rm -rf $RDIR/net/wireguard
mkdir $ZIPDIR
mkdir $OUTPUT
cp -rf $RDIR/build/zip/* $ZIPDIR
mkdir -p $ZIPDIR/tgpkernel/files
mkdir -p $ZIPDIR/tgpkernel/kernels

START_TIME=`date +%s`

# Build S7 img files
echo ""
echo "Building .img files"
echo "-------------------"
echo ""
MODEL=S7
export KERNELTITLE=$KERNELNAME.$MODEL.$VERSION_NUMBER
LOGFILE=$OUTPUT/build-s7.log
FUNC_BUILD_BOOTIMG
mv -f $WORKDIR/ramdisk/image-new.img $ZIPDIR/tgpkernel/kernels/boot-s7.img
MODEL=S7E
export KERNELTITLE=$KERNELNAME.$MODEL.$VERSION_NUMBER
LOGFILE=$OUTPUT/build-s7e.log
FUNC_BUILD_BOOTIMG
mv -f $WORKDIR/ramdisk/image-new.img $ZIPDIR/tgpkernel/kernels/boot-s7e.img

# Final archiving
echo ""
echo "Final archiving"
echo "---------------"
echo ""
if [ $KEEP = "yes" ]; then
	echo "- Copying .img files to .output folder ..."
	cp -f $ZIPDIR/tgpkernel/kernels/boot-s7.img $OUTPUT/boot-s7.img
	cp -f $ZIPDIR/tgpkernel/kernels/boot-s7e.img $OUTPUT/boot-s7e.img
	echo ""
fi
ZIP_DATE=`date +%Y%m%d`
ZIP_NAME=$KERNELNAME.G93xx.v$VERSION_NUMBER.$ZIP_DATE.zip
ZIP_FILE_TARGET=$ZIPDIR/$ZIP_NAME
FUNC_BUILD_ZIP
END_TIME=`date +%s`
FUNC_CLEAN
[ -d "$ZIPDIR" ] && rm -rf $ZIPDIR
let "ELAPSED_TIME=$END_TIME-$START_TIME"
echo ""
echo "Total compiling time is $ELAPSED_TIME seconds"
echo "You will find your logs and files in the .output folder"
echo ""
[ -d "$RDIR/net/wireguard" ] && rm -rf $RDIR/net/wireguard
exit

