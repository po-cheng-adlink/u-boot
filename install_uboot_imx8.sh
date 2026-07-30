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
ATF_BRANCH="lf_v2.10" #branch used by imx-atf under meta-imx
ATF_SRC_COMMIT='49143a1701d9ccd3239e3f95f3042897ca889ea8' #refer to 'imx-atf_2.10.bb' in Yocto
ATF_DIR="imx-atf"

OPTEE_REPO="https://github.com/nxp-imx/imx-optee-os.git"
OPTEE_BRANCH="lf-6.6.23_2.0.0"
OPTEE_SRC_COMMIT="c6be5b572452a2808d1a34588fd10e71715e23cf"
OPTEE_DIR="optee-os"

MKIMAGE_REPO="https://github.com/nxp-imx/imx-mkimage.git"
MKIMAGE_BRANCH="lf-6.6.23_2.0.0" #branch used by imx-mkimage under meta-imx
MKIMAGE_SRC_COMMIT='ca5d6b2d3fd9ab15825b97f7ef6f1ce9a8644966' #refer to 'imx-mkimage_git.inc' in Yocto
MKIMAGE_DIR="imx-mkimage"
MKIMAGE_TARGET="flash_hdmi_spl_uboot"
MKIMAGE_LOG="${WORK_DIR}/${BUILD_DIR}/mkimage-flash.log"
LOG_PRINT_FIT_HAB="${WORK_DIR}/${BUILD_DIR}/mkimage-hab.log"

DDR_FW_VER="8.24" #refer to the name of 'firmware-imx-8.24.inc'
DDR_FW_VER_ABBREV="-fbe0a4c"
FSL_MIRROR="https://www.nxp.com/lgfiles/NMG/MAD/YOCTO"

# Secure HABv4 Boot
#	file://0001-fix-err-msg-linking.patch
CST_MIRROR="https://gitlab.apertis.org/pkg/imx-code-signing-tool.git"
CST_SRC_COMMIT="ca55059b5c9bff5ca27809c4f8d56cbdc8b9ceee"
CST_BRANCH="debian/trixie"
CST_DIR="imx-cst"
CST_VER="3.3.1"
CST_BIN="${WORK_DIR}/${BUILD_DIR}/release/linux64/bin/cst"
CST_FUSE="${WORK_DIR}/${BUILD_DIR}/release/crts/fuse.bin"
FUSE_CMD="${WORK_DIR}/${BUILD_DIR}/fuse.bin.cmd"
CST_CSF_CERT="${WORK_DIR}/${BUILD_DIR}/release/crts/CSF1_1_sha256_2048_65537_v3_usr_crt.pem"
CST_IMG_CERT="${WORK_DIR}/${BUILD_DIR}/release/crts/IMG1_1_sha256_2048_65537_v3_usr_crt.pem"
CST_SRK_TABLE="${WORK_DIR}/${BUILD_DIR}/release/crts/table.bin"
PKI_CRTS_LOG=pki_crt_table_fuse.log

# ArmSystemReady
# edk2
SYSTEM_READY=false
EDK2_REPO="https://github.com/tianocore/edk2.git"
EDK2_BRANCH="master"
EDK2_COMMIT="b24306f15daa2ff8510b06702114724b33895d3c"
EDK2_DIR="edk2"
EDK2_PLATFORM_REPO="https://github.com/tianocore/edk2-platforms.git"
EDK2_PLATFORM_BRANCH="master"
EDK2_PLATFORM_COMMIT="c9e377b00fc086fcb5a5b41663a0149bde9bcc2e"
EDK2_PLATFORM_DIR="edk2-platforms"

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
			if ( ${SYSTEM_READY} ); then
				make PLAT=${PLATFORM} SPD=opteed bl31 || printf "Fails to build STMM ATF firmware\n"
			else
				make PLAT=${PLATFORM} bl31 || printf "Fails to build ATF firmware\n"
			fi
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

	# update optee for system ready and provides BL32_AP_MM.fd from edk2-firmware build
	if ( ${SYSTEM_READY} ); then

		if [ -f ${WORK_DIR}/${BUILD_DIR}/Build/MmStandaloneRpmb/RELEASE_GCC5/FV/BL32_AP_MM.fd ]; then
			cp -f ${WORK_DIR}/${BUILD_DIR}/Build/MmStandaloneRpmb/RELEASE_GCC5/FV/BL32_AP_MM.fd ${WORK_DIR}/${BUILD_DIR}/${OPTEE_DIR}
		else
			echo "BL32_AP_MM.fd not found!"
			exit 1
		fi

		if [ -f ${OPTEE_DIR}/scripts/nxp_build.sh -a -f ${OPTEE_DIR}/BL32_AP_MM.fd ]; then
		pushd ${OPTEE_DIR} > /dev/null
		git checkout HEAD scripts/nxp_build.sh
		popd > /dev/null
		sed -E 's,CFG_WERROR=y \\,CFG_STMM_PATH=${WORK_DIR}/${BUILD_DIR}/${OPTEE_DIR}/BL32_AP_MM.fd \\\
			CFG_RPMB_FS=y \\\
			CFG_IMX_SNVS=n \\\
			CFG_NXP_CAAM=n \\\
			CFG_RPMB_WRITE_KEY=y \\\
			CFG_RPMB_FS_DEV_ID=2 \\\
			CFG_CORE_DYN_SHM=y \\\
			CFG_RPMB_TESTKEY=y \\\
			CFG_REE_FS=n \\\
			CFG_SCTLR_ALIGNMENT_CHECK=n \\\
			CFG_CORE_HEAP_SIZE=2097152 \\\
			CFG_TEE_RAM_VA_SIZE=4194304 \\\
			CFG_PREALLOC_RPC_CACHE=n \\\
			CFG_WERROR=y \\,g' -i ${OPTEE_DIR}/scripts/nxp_build.sh
		fi
	fi

	if [ -d ${OPTEE_DIR} ] ; then
		pushd ${OPTEE_DIR} > /dev/null
		if [ ! -f ./out/arm-plat-imx/core/tee-raw.bin ] ; then
			rm -rf out
			if ( ${SYSTEM_READY} ); then
				echo "build stmm-imx"
				ARCH=arm make PLATFORM=imx-${OPTEE_PLATFORM} \
					CFG_TEE_TA_LOG_LEVEL=0 \
					CFG_TEE_CORE_LOG_LEVEL=0 \
					CFG_STMM_PATH=${WORK_DIR}/${BUILD_DIR}/${OPTEE_DIR}/BL32_AP_MM.fd \
					CFG_RPMB_FS=y \
					CFG_IMX_SNVS=n \
					CFG_NXP_CAAM=n \
					CFG_RPMB_WRITE_KEY=y \
					CFG_RPMB_FS_DEV_ID=2 \
					CFG_CORE_DYN_SHM=y \
					CFG_RPMB_TESTKEY=y \
					CFG_REE_FS=n \
					CFG_SCTLR_ALIGNMENT_CHECK=n \
					CFG_CORE_HEAP_SIZE=2097152 \
					CFG_TEE_RAM_VA_SIZE=4194304 \
					CFG_PREALLOC_RPC_CACHE=n || printf "Fails to build OPTEE firmware\n"
			else
				echo "build optee"
				ARCH=arm make PLATFORM=imx-${OPTEE_PLATFORM} CFG_TEE_TA_LOG_LEVEL=0 CFG_TEE_CORE_LOG_LEVEL=0 all || printf "Fails to build OPTEE firmware\n"
			fi
		fi
		popd > /dev/null
	fi
}

build_ddr_hdmi()
{
	# ===== DDR and HDMI =====
	if [ ! -d firmware-imx-${DDR_FW_VER}${DDR_FW_VER_ABBREV} ] ; then
		if [ ! -x firmware-imx-${DDR_FW_VER}${DDR_FW_VER_ABBREV}.bin ]; then
			wget ${FSL_MIRROR}/firmware-imx-${DDR_FW_VER}${DDR_FW_VER_ABBREV}.bin || \
			printf "Fails to fetch DDR firmware: firmware-imx-${DDR_FW_VER}${DDR_FW_VER_ABBREV}.bin\n"
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

build_edk2()
{
	# ===== EDK2 and EDK2-platforms =====
	if [ ! -d ${EDK2_DIR} ]; then
		git clone ${EDK2_REPO} -b ${EDK2_BRANCH} ${EDK2_DIR} || printf "Fails to fetch EDK2 source code \n"
		pushd ${EDK2_DIR} > /dev/null
		git checkout ${EDK2_COMMIT}
		git submodule init && git submodule update --init --recursive
		popd > /dev/null
	fi
	if [ ! -d ${EDK2_PLATFORM_DIR} ]; then
		git clone ${EDK2_PLATFORM_REPO} -b ${EDK2_PLATFORM_BRANCH} ${EDK2_PLATFORM_DIR} || printf "Fails to fetch EDK2-Platform source code \n"
		pushd ${EDK2_PLATFORM_DIR} > /dev/null
		git checkout ${EDK2_PLATFORM_COMMIT}
		popd > /dev/null
		if [ ! -f ${EDK2_PLATFORM_DIR}/Platform/StandaloneMm/PlatformStandaloneMmPkg/iMXStandaloneMmRpmb.dsc ]; then
			cp -f ${WORK_DIR}/iMXStandaloneMmRpmb.dsc ${EDK2_PLATFORM_DIR}/Platform/StandaloneMm/PlatformStandaloneMmPkg/
		fi
	fi

	# make edk2 base tool
	export WORKSPACE=${WORK_DIR}/${BUILD_DIR}
	export PACKAGES_PATH=${WORK_DIR}/${BUILD_DIR}/${EDK2_DIR}:${WORK_DIR}/${BUILD_DIR}/${EDK2_PLATFORM_DIR}
	export ACTIVE_PLATFORM="Platform/StandaloneMm/PlatformStandaloneMmPkg/iMXStandaloneMmRpmb.dsc"
	export GCC5_AARCH64_PREFIX=aarch64-linux-gnu-
	if [ ! -d ${EDK2_DIR}/BaseTools/Source/C/bin ]; then
		echo "Build ${EDK2_DIR}/BaseTools/Source/C/bin..."
		source ${EDK2_DIR}/edksetup.sh
		make -C ${EDK2_DIR}/BaseTools
		make -C ${EDK2_DIR}/BaseTools/Source/C
	fi

	# build and copy BL32_AP_MM.fd to optee
	if [ ! -d ./Build ]; then
		build -p ${ACTIVE_PLATFORM} -b RELEASE -a AARCH64 -t GCC5 -n `nproc`
		if [ ! -f ./Build/MmStandaloneRpmb/RELEASE_GCC5/FV/BL32_AP_MM.fd ]; then
			echo "No BL32_AP_MM.fd built!"
		fi
	fi
	unset WORKSPACE
	unset CONF_PATH
	unset EDK_TOOLS_PATH
	unset PACKAGES_PATH
	unset ACTIVE_PLATFORM
	unset GCC5_AARCH64_PREFIX
}

build_firmware()
{
	cd ${WORK_DIR}
	# ===== Collect required firmware files to generate bootable binary ======
	if [ ! -d ${BUILD_DIR} ] ; then
		mkdir -p ${BUILD_DIR}
	fi
	cd ${BUILD_DIR}

	if ( ${SYSTEM_READY} ); then
		build_edk2
	fi
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
		if ( ${SYSTEM_READY} ); then
			printf "Copy ${OPTEE_DIR}/out/arm-plat-imx/core/tee-raw.bin to ${MKIMAGE_DIR}/tee.bin-stmm\n"
			cp -f ${OPTEE_DIR}/out/arm-plat-imx/core/tee-raw.bin ${MKIMAGE_DIR}/${SOC_DIR}/tee.bin-stmm
		else
			printf "Copy ${OPTEE_DIR}/out/arm-plat-imx/core/tee-raw.bin to ${MKIMAGE_DIR}/tee.bin\n"
			cp -f ${OPTEE_DIR}/out/arm-plat-imx/core/tee-raw.bin ${MKIMAGE_DIR}/${SOC_DIR}/tee.bin
		fi
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

	if ( ${SYSTEM_READY} ); then
		if [ -f ${WORK_DIR}/tools/mkeficapsule ]; then
			cp -f ${WORK_DIR}/tools/mkeficapsule ${WORK_DIR}/${BUILD_DIR}/${MKIMAGE_DIR}/iMX8M
		fi
		# update "KEY_EXISTS = $(shell if ls CRT.* &> /dev/null 2>&1" line in soc.mak
		if grep "^KEY_EXISTS = \$(shell.*" ${WORK_DIR}/${BUILD_DIR}/${MKIMAGE_DIR}/iMX8M/soc.mak; then
			sed "s|^KEY_EXISTS.*|KEY_EXISTS=\$(sh -c 'if ls CRT\.\* \&> /dev/null 2>\&1; then echo exist; else echo noexist; fi')|g" -i ${WORK_DIR}/${BUILD_DIR}/${MKIMAGE_DIR}/iMX8M/soc.mak
		fi
		# update "fdtoverlay -i $(dtbs) -o $(PLAT)-evk.dtb signature.dtbo" line in soc.mak
		if grep "fdtoverlay -i \$(PLAT)-evk.dtb -o \$(PLAT)-evk.dtb signature.dtbo$" ${WORK_DIR}/${BUILD_DIR}/${MKIMAGE_DIR}/iMX8M/soc.mak; then
			sed 's,fdtoverlay -i \$(PLAT)-evk.dtb -o \$(PLAT)-evk.dtb signature.dtbo$,fdtoverlay -i \$(dtbs) -o \$(PLAT)-evk.dtb signature.dtbo,g' -i ${WORK_DIR}/${BUILD_DIR}/${MKIMAGE_DIR}/iMX8M/soc.mak
		fi
		if [ ! -f ${WORK_DIR}/${BUILD_DIR}/${MKIMAGE_DIR}/iMX8M/CRT.esl ] ; then
			make SOC=${SOC_TARGET} dtbs="${DTBS}" ovlays="${OVERLAYS}" TEE=tee.bin-stmm capsule_key 2>&1 | tee ${MKIMAGE_LOG} &&
			printf "Make target: capsule_key and generate capsule key... \n" || printf "Fails to generate capsule key... \n"
		fi
		printf "\nIssue Command: make SOC=${SOC_TARGET} dtbs=\"${DTBS}\" ovlays=\"${OVERLAYS}\" TEE=tee.bin-stmm flash_evk_stmm_capsule\n"
		make SOC=${SOC_TARGET} dtbs="${DTBS}" ovlays="${OVERLAYS}" TEE=tee.bin-stmm flash_evk_stmm_capsule 2>&1 | tee ${MKIMAGE_LOG} && \
		printf "Make target: ${MKIMAGE_TARGET} and generate flash.bin... \n" || printf "Fails to generate flash.bin... \n"
	else
		printf "\nIssue Command: make SOC=${SOC_TARGET} dtbs=\"${DTBS}\" ovlays=\"${OVERLAYS}\" ${MKIMAGE_TARGET}\n"
		make SOC=${SOC_TARGET} dtbs="${DTBS}" ovlays="${OVERLAYS}" ${MKIMAGE_TARGET} 2>&1 | tee ${MKIMAGE_LOG} && \
		printf "Make target: ${MKIMAGE_TARGET} and generate flash.bin... \n" || printf "Fails to generate flash.bin... \n"
	fi

	if ( ${SYSTEM_READY} ); then
		printf "\nIssue Command: make SOC=${SOC_TARGET} dtbs=\"${DTBS}\" ovlays=\"${OVERLAYS}\" TEE=tee.bin-stmm print_fit_hab\n"
		make SOC=${SOC_TARGET} dtbs="${DTBS}" ovlays="${OVERLAYS}" TEE=tee.bin-stmm print_fit_hab 2>&1 | tee ${LOG_PRINT_FIT_HAB} && \
		printf "Make target: print_fit_hab...\n" || printf "Fails to generate fit hab... \n"
	else
		printf "\nIssue Command: make SOC=${SOC_TARGET} dtbs=\"${DTBS}\" ovlays=\"${OVERLAYS}\" print_fit_hab\n"
		make SOC=${SOC_TARGET} dtbs="${DTBS}" ovlays="${OVERLAYS}" print_fit_hab 2>&1 | tee ${LOG_PRINT_FIT_HAB} && \
		printf "Make target: print_fit_hab...\n" || printf "Fails to generate fit hab... \n"
	fi

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
	if ( ${SECURE_BOOT} ); then
		sudo dd if=${WORK_DIR}/${BUILD_DIR}/${MKIMAGE_DIR}/${SOC_DIR}/${IMX_BOOT}.signed of=${DRIVE} bs=1k seek=${IMX_BOOT_SEEK} oflag=dsync status=progress && \
		printf "Flash flash.bin.signed... \n" || printf "Fails to flash flash.bin.signed... \n"
	else
		sudo dd if=${WORK_DIR}/${BUILD_DIR}/${MKIMAGE_DIR}/${SOC_DIR}/${IMX_BOOT} of=${DRIVE} bs=1k seek=${IMX_BOOT_SEEK} oflag=dsync status=progress && \
		printf "Flash flash.bin... \n" || printf "Fails to flash flash.bin... \n"
	fi
}

build_cst()
{
	# ===== Code Singing Tool =====
	if [ ! -d ${CST_DIR} ] ; then
		git clone ${CST_MIRROR} -b ${CST_BRANCH} ${CST_DIR} || printf "Fails to fetch OPTEE source code \n"
		pushd ${CST_DIR} > /dev/null
		git checkout ${CST_SRC_COMMIT}
		sed 's,curl -O,curl -L -O,g' -i Makefile
		popd > /dev/null
	fi

	if [ ! -d ${CST_DIR}/build ] ; then
		pushd ${CST_DIR} > /dev/null
		if [ ! -x build/linux64/bin/cst -a ! -x build/linux64/bin/srktool ] ; then
			make clean OSTYPE=linux64 ENCRYPTION=yes || printf "Fails to clean CST utility\n"
			make build OSTYPE=linux64 ENCRYPTION=yes || printf "Fails to build CST utility\n"
		fi
		if [ ! -x add-ons/hab_csf_parser/csf_parser ]; then
			make clean -C add-ons/hab_csf_parser || printf "Failed to clean hab_csf_parser\n"
			make all -C add-ons/hab_csf_parser || printf "Failed to build hab_csf_parser\n"
			install -m 755 add-ons/hab_csf_parser/csf_parser build/linux64/bin/hab_csf_parser
		fi
		# install to release
		cp -rf ca build/
		cp -rf keys build/
		mkdir -p build/crts
		popd > /dev/null
	fi

	# create release to ${BUILD_DIR}
	if [ ! -d ${WORK_DIR}/${BUILD_DIR}/release ]; then
		mkdir -p ${WORK_DIR}/${BUILD_DIR}/release/
	fi
	if [ -x ${CST_DIR}/build/linux64/bin/cst -a ! -x ${CST_DIR}/release/linux64/bin/cst ]; then
		# install to release
		cp -rf ${CST_DIR}/build/* ${WORK_DIR}/${BUILD_DIR}/release
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
		./keys/hab4_pki_tree.sh -existing-ca n -kt rsa -kl 2048 -duration 5 -num-srk 4 -srk-ca y 2>&1 | tee ${WORK_DIR}/${PKI_CRTS_LOG}
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
	* [-a]: arm-system-ready with stmm
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
	echo "Make platform: ${PLATFORM}"
	echo "Make target: ${MKIMAGE_TARGET}"
	echo "Specified SOC: ${SOC}"
	echo "*************************************************************"
}

if [ $# -eq 0 ]; then
	usage
	exit 1
fi

while getopts "stchad:b:o:" OPTION
do
	case $OPTION in
	a)
	    SYSTEM_READY=true;
	    ;;
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
		rm -rf ${WORK_DIR}${BUILD_DIR}
		echo "Clean ${BUILD_DIR}..."
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

	printf "\n***** Generate imx-cst *****\n"
	cd ${WORK_DIR}/${BUILD_DIR}
	(
		unset ARCH
		unset CROSS_COMPILE
		declare -x PATH=${PATH#\/opt\/gcc-linaro*:}
		build_cst
	)
	printf "\n***** Generate crts fuse table *****\n"
	generate_crts_table_fuse
	printf "\n***** Generate csf table *****\n"
	generate_csf ${SOC_TARGET}
	printf "\n***** Sign flash.bin *****\n"
	sign_flash_habv4
	printf "\n***** Generate U-boot Fuse Command *****\n"
	generate_fuse_cmds ${SOC_TARGET}
fi
printf "\n***** Flash to NXP Device *****\n"
flash_imx_boot

