#!/bin/bash
#################################################################################
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#################################################################################

#platform related parameters
#PLATFORM="imx8mm"
#SOC_TARGET="iMX8MM"
#SOC_DIR="iMX8M"
#DTBS="fsl-imx8mq-evk"

WORK_DIR=`pwd`
BUILD_DIR="build_fw_imx8"

DRIVE=/dev/sdX
OVERLAYS=$(echo ${OVERLAYS} | xargs)
SECURE_BOOT=false

SPL_ORI="spl/u-boot-spl.bin"
UBOOT_ORI="u-boot-nodtb.bin"
IMX_BOOT="flash.bin"

ATF_REPO="https://github.com/nxp-imx/imx-atf.git"
ATF_BRANCH="lf_v2.6" #branch used by imx-atf under meta-imx
ATF_SRC_COMMIT='3c1583ba0a5d11e5116332e91065cb3740153a46' #refer to 'imx-atf_2.10.bb' in Yocto
ATF_DIR="imx-atf"

OPTEE_REPO="https://github.com/nxp-imx/imx-optee-os.git"
OPTEE_BRANCH="lf-5.15.71_2.2.0"
OPTEE_SRC_COMMIT="00919403f040fad4f8603e605932281ff8451b1d"
OPTEE_DIR="optee-os"

MKIMAGE_REPO="https://github.com/nxp-imx/imx-mkimage.git"
MKIMAGE_BRANCH="lf-5.15.71_2.2.0" #branch used by imx-mkimage under meta-imx
MKIMAGE_SRC_COMMIT='3bfcfccb71ddf894be9c402732ccb229fe72099e' #refer to 'imx-mkimage_git.inc' in Yocto
MKIMAGE_DIR="imx-mkimage"
MKIMAGE_TARGET="flash_hdmi_spl_uboot"
MKIMAGE_LOG="${WORK_DIR}/${BUILD_DIR}/mkimage-flash.log"
LOG_PRINT_FIT_HAB="${WORK_DIR}/${BUILD_DIR}/mkimage-hab.log"

DDR_FW_VER="8.18" #refer to the name of 'firmware-imx-8.24.inc'
DDR_FW_VER_ABBREV=""
FSL_MIRROR="https://www.nxp.com/lgfiles/NMG/MAD/YOCTO"

# Secure HABv4 Boot
#	file://0001-fix-err-msg-linking.patch
CST_MIRROR="https://gitlab.apertis.org/pkg/imx-code-signing-tool.git"
CST_SRC_COMMIT="e2c687a856e6670e753147aacef42d0a3c07891a"
CST_BRANCH="apertis/v2022pre"
CST_DIR="imx-cst"
CST_VER="3.3.1"
CST_BIN="${WORK_DIR}/${BUILD_DIR}/release/linux64/bin/cst"
CST_FUSE="${WORK_DIR}/${BUILD_DIR}/release/crts/fuse.bin"
FUSE_CMD="${WORK_DIR}/${BUILD_DIR}/fuse.bin.cmd"
CST_CSF_CERT="${WORK_DIR}/${BUILD_DIR}/release/crts/CSF1_1_sha256_2048_65537_v3_usr_crt.pem"
CST_IMG_CERT="${WORK_DIR}/${BUILD_DIR}/release/crts/IMG1_1_sha256_2048_65537_v3_usr_crt.pem"
CST_SRK_TABLE="${WORK_DIR}/${BUILD_DIR}/release/crts/table.bin"
PKI_CRTS_LOG=pki_crt_table_fuse.log

setup_platform()
{
	SOC=$( echo "${DTBS%%.*}" | cut -d'-' -f2 )
	case "${SOC}" in
	*imx8mn*)
		OPTEE_PLATFORM="mx8mnevk"
		PLATFORM="imx8mn"
		SOC_TARGET="iMX8MN"
		SOC_DIR="iMX8M"
		IMX_BOOT_SEEK="32"
		;;
	*imx8mm*)
		OPTEE_PLATFORM="mx8mmevk"
		PLATFORM="imx8mm"
		SOC_TARGET="iMX8MM"
		SOC_DIR="iMX8M"
		IMX_BOOT_SEEK="33"
		;;
	*imx8mp*)
		OPTEE_PLATFORM="mx8mpevk"
		PLATFORM="imx8mp"
		SOC_TARGET="iMX8MP"
		SOC_DIR="iMX8M"
		IMX_BOOT_SEEK="32"
		;;
	*imx8mq*)
		OPTEE_PLATFORM="mx8mqevk"
		PLATFORM="imx8mq"
		SOC_TARGET="iMX8M"
		SOC_DIR="iMX8M"
		IMX_BOOT_SEEK="33"
		BUILD_DIR="build_imx8mq"
		;;
	*imx8m*)
		OPTEE_PLATFORM="mx8mqevk"
		PLATFORM="imx8mq"
		SOC_TARGET="iMX8M"
		SOC_DIR="iMX8M"
		IMX_BOOT_SEEK="33"
		BUILD_DIR="build_fw_imx8mq"
		;;
	*8mp)
		OPTEE_PLATFORM="mx8mpevk"
		PLATFORM="imx8mp"
		SOC_TARGET="iMX8MP"
		SOC_DIR="iMX8M"
		IMX_BOOT_SEEK="32"
		;;
	*8m)
		OPTEE_PLATFORM="mx8mqevk"
		PLATFORM="imx8mq"
		SOC_TARGET="iMX8M"
		SOC_DIR="iMX8M"
		IMX_BOOT_SEEK="33"
		MKIMAGE_TARGET="flash_ddr3l_evk"
		BUILD_DIR="build_fw_imx8mq"
		;;
	default)
		printf "Targest SOC isn't supported by this script\n"
		exit 1
		;;
	esac
	printf "Specified SOC: ${SOC}, PLATFORM: ${PLATFORM} SOC_TARGET: ${SOC_TARGET} SOC_DIR: ${SOC_DIR} IMX_BOOT_SEEK: ${IMX_BOOT_SEEK} OPTEE_PLATFORM: ${OPTEE_PLATFORM}\n"
}

fetch_mkimage()
{
	# ===== imx-mkimage =====
	if [ ! -d ${MKIMAGE_DIR} ] ; then
		git clone ${MKIMAGE_REPO} -b ${MKIMAGE_BRANCH} ${MKIMAGE_DIR} || printf "Fails to fetch imx-mkimage source code\n"
		pushd ${MKIMAGE_DIR} > /dev/null
		git checkout ${MKIMAGE_SRC_COMMIT}
		popd > /dev/null
	fi
}

build_atf()
{
	# ===== ARM Trusted Firmware (ATF) =====
	if [ ! -d ${ATF_DIR} ] ; then
		git clone ${ATF_REPO} -b ${ATF_BRANCH} ${ATF_DIR} || printf "Fails to fetch ATF source code\n"
		pushd ${ATF_DIR} > /dev/null
		git checkout ${ATF_SRC_COMMIT}
		popd > /dev/null
	fi

	if [ -d ${ATF_DIR} ] ; then
		pushd ${ATF_DIR} > /dev/null
		if [ ! -f build/${PLATFORM}/release/bl31.bin ] ; then
			rm -rf build
			make PLAT=${PLATFORM} bl31 || printf "Fails to build ATF firmware\n"
		fi
		popd > /dev/null
	fi
}

build_optee()
{
	# ===== OPTEE =====
	if [ ! -d ${OPTEE_DIR} ] ; then
		git clone ${OPTEE_REPO} -b ${OPTEE_BRANCH} ${OPTEE_DIR} || printf "Fails to fetch OPTEE source code \n"
		pushd ${OPTEE_DIR} > /dev/null
		git checkout ${OPTEE_SRC_COMMIT}
		popd > /dev/null
	fi

	if [ -d ${OPTEE_DIR} ] ; then
		pushd ${OPTEE_DIR} > /dev/null
		if [ ! -f ./out/arm-plat-imx/core/tee-raw.bin ] ; then
			rm -rf out
			ARCH=arm make PLATFORM=imx-${OPTEE_PLATFORM} CFG_TEE_TA_LOG_LEVEL=0 CFG_TEE_CORE_LOG_LEVEL=0 all || printf "Fails to build OPTEE firmware\n"
		fi
		popd > /dev/null
	fi
}

build_ddr_hdmi()
{
	# ===== DDR and HDMI =====
	if [ ! -d firmware-imx-${DDR_FW_VER}${DDR_FW_VER_ABBREV} ] ; then
		if [ ! -x firmware-imx-${DDR_FW_VER}${DDR_FW_VER_ABBREV}.bin ]; then
			wget ${FSL_MIRROR}/firmware-imx-${DDR_FW_VER}${DDR_FW_VER_ABBREV}.bin || printf "Fails to fetch DDR firmware: firmware-imx-${DDR_FW_VER}${DDR_FW_VER_ABBREV}.bin\n"
		else
			printf "Already downloaded firmware-imx-${DDR_FW_VER}${DDR_FW_VER_ABBREV}.bin\n"
		fi
		if [ -f firmware-imx-${DDR_FW_VER}${DDR_FW_VER_ABBREV}.bin ]; then
			chmod +x firmware-imx-${DDR_FW_VER}${DDR_FW_VER_ABBREV}.bin && \
			./firmware-imx-${DDR_FW_VER}${DDR_FW_VER_ABBREV}.bin || \
			printf "Fails to extract DDR firmware: firmware-imx-${DDR_FW_VER}${DDR_FW_VER_ABBREV}.bin \n"
		fi
	fi
}

build_firmware()
{
	cd ${WORK_DIR}
	# ===== Collect required firmware files to generate bootable binary ======
	if [ ! -d ${BUILD_DIR} ] ; then
		mkdir -p ${BUILD_DIR}
	fi
	cd ${BUILD_DIR}

	fetch_mkimage
	build_atf
	build_optee
	build_ddr_hdmi

	# ===== collect atf =====
	if [ -f ${ATF_DIR}/build/${PLATFORM}/release/bl31.bin ] ; then
		printf "Copy ${ATF_DIR}/build/${PLATFORM}/release/bl31.bin to ${MKIMAGE_DIR}\n"
		cp -f ${ATF_DIR}/build/${PLATFORM}/release/bl31.bin ${MKIMAGE_DIR}/${SOC_DIR}
	else
		printf "Cannot find release/bl31.bin \n"
	fi

	# ===== collect optee =====
	if [ -f ${OPTEE_DIR}/out/arm-plat-imx/core/tee-raw.bin ] ; then
		printf "Copy ${OPTEE_DIR}/out/arm-plat-imx/core/tee-raw.bin to ${MKIMAGE_DIR}\n"
		cp -f ${OPTEE_DIR}/out/arm-plat-imx/core/tee-raw.bin ${MKIMAGE_DIR}/${SOC_DIR}/tee.bin
	else
		printf "Cannot find core/tee-raw.bin \n"
	fi

	# ===== collect ddr and hdmi =====
	if [ -d firmware-imx-${DDR_FW_VER}${DDR_FW_VER_ABBREV}/firmware/ddr/synopsys ] ; then
		if [ ${PLATFORM} = "imx8mp" ] ; then
			cp -f firmware-imx-${DDR_FW_VER}${DDR_FW_VER_ABBREV}/firmware/ddr/synopsys/lpddr4_pmu_train_1d_dmem_202006.bin ${MKIMAGE_DIR}/${SOC_DIR}
			cp -f firmware-imx-${DDR_FW_VER}${DDR_FW_VER_ABBREV}/firmware/ddr/synopsys/lpddr4_pmu_train_1d_imem_202006.bin ${MKIMAGE_DIR}/${SOC_DIR}
			cp -f firmware-imx-${DDR_FW_VER}${DDR_FW_VER_ABBREV}/firmware/ddr/synopsys/lpddr4_pmu_train_2d_dmem_202006.bin ${MKIMAGE_DIR}/${SOC_DIR}
			cp -f firmware-imx-${DDR_FW_VER}${DDR_FW_VER_ABBREV}/firmware/ddr/synopsys/lpddr4_pmu_train_2d_imem_202006.bin ${MKIMAGE_DIR}/${SOC_DIR}
		else
			cp -f firmware-imx-${DDR_FW_VER}${DDR_FW_VER_ABBREV}/firmware/ddr/synopsys/lpddr4_pmu_train_1d_dmem.bin ${MKIMAGE_DIR}/${SOC_DIR}
			cp -f firmware-imx-${DDR_FW_VER}${DDR_FW_VER_ABBREV}/firmware/ddr/synopsys/lpddr4_pmu_train_1d_imem.bin ${MKIMAGE_DIR}/${SOC_DIR}
			cp -f firmware-imx-${DDR_FW_VER}${DDR_FW_VER_ABBREV}/firmware/ddr/synopsys/lpddr4_pmu_train_2d_dmem.bin ${MKIMAGE_DIR}/${SOC_DIR}
			cp -f firmware-imx-${DDR_FW_VER}${DDR_FW_VER_ABBREV}/firmware/ddr/synopsys/lpddr4_pmu_train_2d_imem.bin ${MKIMAGE_DIR}/${SOC_DIR}
		fi
		cp -f firmware-imx-${DDR_FW_VER}${DDR_FW_VER_ABBREV}/firmware/hdmi/cadence/signed_hdmi_imx8m.bin ${MKIMAGE_DIR}/${SOC_DIR}
	else
		printf "Cannot find DDR firmware \n"
	fi
}

install_uboot_dtb()
{
	#Copy uboot binary
	cd ${WORK_DIR}
	if [ -f u-boot-nodtb.bin ] ; then
		printf "Copy u-boot-nodtb.bin to ${MKIMAGE_DIR}\n"
		cp u-boot-nodtb.bin ${WORK_DIR}/${BUILD_DIR}/${MKIMAGE_DIR}/${SOC_DIR}
	else
		printf "Cannot find u-boot-nodtb.bin. Please build u-boot first! \n"
	fi

	#Copy SPL binary
	cd ${WORK_DIR}
	if [ -f spl/u-boot-spl.bin ] ; then
		printf "Copy spl/u-boot-spl.bin to ${MKIMAGE_DIR}\n"
		cp spl/u-boot-spl.bin ${WORK_DIR}/${BUILD_DIR}/${MKIMAGE_DIR}/${SOC_DIR}
	else
		printf "Cannot find spl/u-boot-spl.bin. Please build u-boot first! \n"
	fi

	#Copy device tree file
	cd ${WORK_DIR}
	for DTB in ${DTBS}
	do
		if [ -f arch/arm/dts/${DTB} ] ; then
			printf "Copy arch/arm/dts/${DTB} to ${MKIMAGE_DIR}\n"
			cp arch/arm/dts/${DTB} ${WORK_DIR}/${BUILD_DIR}/${MKIMAGE_DIR}/${SOC_DIR}
		else
			printf "Cannot find arch/arm/dts/${DTB} . Please build u-boot first! \n"
		fi
	done

	for OV in ${OVERLAYS}
	do
		if [ -f arch/arm/dts/${OV} ]; then
			printf "Copy arch/arm/dts/${OV} to ${MKIMAGE_DIR}\n"
			cp arch/arm/dts/${OV} ${WORK_DIR}/${BUILD_DIR}/${MKIMAGE_DIR}/${SOC_DIR}
		else
			printf "Cannot find arch/arm/dts/${OV}, Please build u-boot dts first! \n"
		fi
	done
}

generate_imx_boot()
{
	cd ${WORK_DIR}
	#Before generating the flash.bin, transfer the mkimage generated by U-Boot to iMX8M folder
	if [ -f tools/mkimage ] ; then
		printf "Copy tools/mkimage to ${MKIMAGE_DIR}/${SOC_DIR}/mkimage_uboot\n"
		cp tools/mkimage ${WORK_DIR}/${BUILD_DIR}/${MKIMAGE_DIR}/${SOC_DIR}/mkimage_uboot
		:;
	else
		printf "Cannot find tools/mkimage. Please build u-boot first! \n"
	fi

	#Generate bootable binary (This binary contains SPL and u-boot.bin) for flashing
	cd ${WORK_DIR}/${BUILD_DIR}/${MKIMAGE_DIR}

	printf "\nIssue Command: make SOC=${SOC_TARGET} dtbs=\"${DTBS}\" ovlays=\"${OVERLAYS}\" ${MKIMAGE_TARGET}\n"
	make SOC=${SOC_TARGET} dtbs="${DTBS}" ovlays="${OVERLAYS}" ${MKIMAGE_TARGET} 2>&1 | tee ${MKIMAGE_LOG} && \
	printf "Make target: ${MKIMAGE_TARGET} and generate flash.bin... \n" || printf "Fails to generate flash.bin... \n"

	printf "\nIssue Command: make SOC=${SOC_TARGET} dtbs=\"${DTBS}\" ovlays=\"${OVERLAYS}\" print_fit_hab\n"
	make SOC=${SOC_TARGET} dtbs="${DTBS}" ovlays="${OVERLAYS}" print_fit_hab 2>&1 | tee ${LOG_PRINT_FIT_HAB} && \
	printf "Make target: print_fit_hab...\n" || printf "Fails to generate fit hab... \n"

	if [ -f ${WORK_DIR}/${BUILD_DIR}/${MKIMAGE_DIR}/${SOC_DIR}/flash.bin ]; then
		FLASH_IMAGE="${WORK_DIR}/${BUILD_DIR}/${MKIMAGE_DIR}/${SOC_DIR}/flash.bin"
	fi
}

flash_imx_boot()
{
	cd ${WORK_DIR}
	if [ ! -b $DRIVE ]; then
		printf "$DRIVE doesn't exist !!!\n"
		exit 19
	fi
	sudo umount ${DRIVE}?
	sleep 0.1
	sudo dd if=${WORK_DIR}/${BUILD_DIR}/${MKIMAGE_DIR}/${SOC_DIR}/${IMX_BOOT} of=${DRIVE} bs=1k seek=${IMX_BOOT_SEEK} oflag=dsync status=progress && \
	printf "Flash flash.bin... \n" || printf "Fails to flash flash.bin... \n"
}

build_cst()
{
	# ===== Code Singing Tool =====
	if [ ! -d ${CST_DIR} ] ; then
		git clone ${CST_MIRROR} -b ${CST_BRANCH} ${CST_DIR} || printf "Fails to fetch OPTEE source code \n"
		pushd ${CST_DIR} > /dev/null
		git checkout ${CST_SRC_COMMIT}
		popd > /dev/null
	fi

	if [ -d ${CST_DIR} ] ; then
		pushd ${CST_DIR} > /dev/null
		if [ ! -x code/cst/release/linux64/bin/cst -a ! -x code/cst/release/linux64/bin/srktool ] ; then
			pushd code/cst > /dev/null
			make clean OSTYPE=linux64 ENCRYPTION=yes || printf "Fails to clean CST utility\n"
			make build OSTYPE=linux64 ENCRYPTION=yes || printf "Fails to build CST utility\n"
			make rel_bin OSTYPE=linux64 ENCRYPTION=yes || printf "Fails to release CST utility\n"
			popd > /dev/null
		fi
		if [ ! -x code/hab_csf_parser/csf_parser ]; then
			make clean -C code/hab_csf_parser || printf "Failed to clean hab_csf_parser\n"
			make all -C code/hab_csf_parser || printf "Failed to build hab_csf_parser\n"
		fi
		# install to release
		install -m 755 code/hab_csf_parser/csf_parser code/cst/release/linux64/bin/hab_csf_parser
		cp -rf ca code/cst/release
		cp -rf keys code/cst/release
		mkdir -p code/cst/release/crts
		popd > /dev/null
	fi

	# copy release to ${BUILD_DIR}
	if [ ! -d ${WORK_DIR}/${BUILD_DIR}/release ]; then
		cp -rf ${CST_DIR}/code/cst/release ${WORK_DIR}/${BUILD_DIR}/
	fi
}

generate_crts_table_fuse()
{
	pushd ${WORK_DIR}/${BUILD_DIR}/release > /dev/null
	if [ -f crts/CA1_sha256_2048_65537_v3_ca_crt.pem -a \
		-f crts/CSF1_1_sha256_2048_65537_v3_usr_crt.pem -a \
		-f crts/CSF2_1_sha256_2048_65537_v3_usr_crt.pem -a \
		-f crts/CSF3_1_sha256_2048_65537_v3_usr_crt.pem -a \
		-f crts/CSF2_1_sha256_2048_65537_v3_usr_crt.pem -a \
		-f crts/IMG1_1_sha256_2048_65537_v3_usr_crt.pem -a \
		-f crts/IMG2_1_sha256_2048_65537_v3_usr_crt.pem -a \
		-f crts/IMG3_1_sha256_2048_65537_v3_usr_crt.pem -a \
		-f crts/IMG4_1_sha256_2048_65537_v3_usr_crt.pem -a \
		-f crts/SRK1_sha256_2048_65537_v3_ca_crt.pem -a \
		-f crts/SRK2_sha256_2048_65537_v3_ca_crt.pem -a \
		-f crts/SRK3_sha256_2048_65537_v3_ca_crt.pem -a \
		-f crts/SRK4_sha256_2048_65537_v3_ca_crt.pem ]; then
		printf "Using existing generated crts\n"
	else
		./keys/hab4_pki_tree.sh -existing-ca n -use-ecc n -kl 2048 -duration 5 -num-srk 4 -srk-ca y 2>&1 | tee ${WORK_DIR}/${PKI_CRTS_LOG}
	fi

	if [ -f crts/table.bin -a -f crts/fuse.bin ]; then
		printf "Using existing generated table.bin and fuse.bin\n"
	else
		pushd crts > /dev/null
		../linux64/bin/srktool -h 4 -d sha256 -t table.bin -e fuse.bin -c \
			SRK1_sha256_2048_65537_v3_ca_crt.pem, \
			SRK2_sha256_2048_65537_v3_ca_crt.pem, \
			SRK3_sha256_2048_65537_v3_ca_crt.pem, \
			SRK4_sha256_2048_65537_v3_ca_crt.pem 2>&1 | tee -a ${WORK_DIR}/${PKI_CRTS_LOG}
		popd > /dev/null
	fi
	popd > /dev/null
}

usage()
{
	echo -e "\nUsage: install_uboot_imx8.sh
	Optional parameters: [-d disk-path] [-b DTBS_name] [-s] [-t] [-c] [-h]"
	echo "
	* This script is used to download required firmware files, generate and flash bootable u-boot binary
	*
	* [-d disk-path]: specify the disk to flash u-boot binary, e.g., /dev/sdd
	* [-b dtb_name]: specify the name of dtb, which will be included in FIT image
	* [-s]: secure boot
	* [-t]: target u-boot binary is without HDMI firmware
	* [-c]: clean temporary directory
	* [-h]: help

	For example:

	i.mx8MP:
	* SP2-IMX8MP:
	./install_uboot_imx8.sh -b sp2-imx8mp.dtb -d /dev/sdX
"
}

print_settings()
{
	echo "*************************************************************"
	echo "Before run this script, please build u-boot first!"
	echo "The disk path to flash u-boot: $DRIVE"
	echo "The default DTB name: ${DTBS}"
	echo "Additional DTBO names: ${OVERLAYS}"
	echo "Make target: ${PLATFORM}"
	echo "Make target: ${MKIMAGE_TARGET}"
	echo "Specified SOC: ${SOC}"
	echo "*************************************************************"
}

if [ $# -eq 0 ]; then
	usage
	exit 1
fi

while getopts "stchd:b:o:" OPTION
do
	case $OPTION in
	d)
		DRIVE="$OPTARG"
		;;
	b)
		DTBS="$DTBS $OPTARG"
		;;
	o)
		OVERLAYS="$OVERLAYS $OPTARG"
		;;
	s)
		SECURE_BOOT=true;
		;;
	t)
		MKIMAGE_TARGET='flash_spl_uboot';
		;;
	c)
		rm -rf ${BUILD_DIR} ${MKIMAGE_DIR}
		echo "Clean ${BUILD_DIR} ${MKIMAGE_DIR}..."
		exit
		;;
	?|h) usage
		exit
		;;
	esac
done

if [ "$(id -u)" = "0" ]; then
	echo "This script can not be run as root"
	exit 1
fi

DTBS=$(echo ${DTBS} | cut -c 1-)

setup_platform
print_settings
build_firmware
install_uboot_dtb
generate_imx_boot

# habv4 - sign components in flash.bin
if ( ${SECURE_BOOT} ); then
	if [ ! -x "${WORK_DIR}/create_hab_boot.sh" ]; then
		echo "Cannot source create_hab_boot.sh for HABv4"
		exit 1;
	else
		source ${WORK_DIR}/create_hab_boot.sh
	fi

	printf "\nGenerate Secure Boot Components\n"
	cd ${WORK_DIR}/${BUILD_DIR}
	build_cst
	generate_crts_table_fuse
	generate_csf ${SOC_TARGET}
	sign_flash_habv4
	generate_fuse_cmds ${SOC_TARGET}
fi
flash_imx_boot

