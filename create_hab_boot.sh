#!/bin/bash
#
# Copyright 2025 ADLINK
#
# SPDX-License-Identifier: BSD-3-Clause
#
# A generic function to create NXP Hab Boot software components
#
# ${BOOTLOADER_TYPE} can be uboot, uefi
#
# ${BOOT_TYPE} can be sd, emmc, qspi, xspi, nor, nand, defined in configs/board/<machine>.conf
#
#
#
# Po Cheng <po.cheng@adlinktech.com>
#
# - docs/mx8m_secure_boot.txt (from u-boot)
# - configs/board/common/
# - configs/board/<machine>.conf
#



# Verify environment variable is set and file exists
verify_env() {
	[ -z "$1" ] && echo "Please set environment variable '$2'"
	[ ! -f $1 ] && echo "Could not find '$1'"
}

################################################################################
#
# Fuse extracted from cst srktool generated fuse.bin
#
readonly HAB_WARNING1="# Note: These are One-Time Programmable e-fuses. Once you write them you can't go back, so get it right the first time."
readonly HAB_WARNING2="
# After the device successfully boots a signed image without generating any HAB events, it is safe to secure, or 'close', the device.
# This is the last step in the process. Once the fuse is blown, the chip does not load an image that has not been signed using the correct PKI tree.
# Important notes:
# - This is again a One-Time Programmable e-fuse. Once you write it you can't go back, so get it right the first time.
# - If anything in the previous steps wasn't done correctly, the SOM will not boot after writing this bit.
"

create_fuse_cmds_mx8m() {
	echo "${HAB_WARNING1}" | tee ${FUSE_CMD}
	word=0
	bank=6
	for i in $(seq 0 7); do
		if [ "$i" -eq "4" ]; then
			bank=7
			word=0
		fi
		offset=$(echo "$i * 4" | bc)
		value=$(hexdump -s $offset -n 4 -e '/4 "0x"' -e '/4 "%X""\n"' ${CST_FUSE})
		echo "fuse prog -y $bank $word $value" | tee -a ${FUSE_CMD}
		word="$(expr $word + 1)"
	done
	echo "${HAB_WARNING2}" | tee -a ${FUSE_CMD}
	echo "fuse prog 1 3 0x02000000" | tee -a ${FUSE_CMD}
}

create_fuse_cmds_mx8() {
	echo "${HAB_WARNING1}" > ${FUSE_CMD}
	word="$1"
	bank=0
	for i in $(seq 0 15); do
		offset=$(echo "$i * 4" | bc)
		value=$(hexdump -s $offset -n 4 -e '/4 "0x"' -e '/4 "%X""\n"' ${CST_FUSE})
		echo "fuse prog -y 0 $word $value" >> ${FUSE_CMD}
		word="$(expr $word + 1)"
	done
	echo "${HAB_WARNING2}" >> ${FUSE_CMD}
	echo "ahab_close" >> ${FUSE_CMD}
}

generate_fuse_cmds() {
	tgt="$1"

	verify_env "${CST_FUSE}" "CST_FUSE"

	if [ ! -f ${CST_FUSE} ]; then
		echo "Could not find '$CST_FUSE'"
		return 2
		# ENOENT 2 No such file or directory
	fi

	# iMX8MN, iMX8MM, iMX8MP, iMX8M
	case ${tgt} in
	*MX8M*)
		create_fuse_cmds_mx8m
		;;
	*MX8X)
		create_fuse_cmds_mx8 730
		;;
	*MX8)
		create_fuse_cmds_mx8 722
		;;
	*)
		help "Unsupported SOC $1"
		;;
	esac
}

################################################################################
#
# csf for SPL and UBOOT(FIT)
#


readonly CSF_SPL="${SOC}-csf-spl"
readonly CSF_FIT="${SOC}-csf-fit"

# MX8M
create_csf_spl() {
	# Copy template file
	cat > ${CSF_SPL}.csf << EOF
[Header]
	Version = 4.3
	Hash Algorithm = sha256
	Engine = CAAM
	Engine Configuration = 0
	Certificate Format = X509
	Signature Format = CMS

[Install SRK]
	# Index of the key location in the SRK table to be installed
	File = "@CST_SRK_TABLE@"
	Source index = 0

[Install CSFK]
	# Key used to authenticate the CSF data
	File = "@CST_CSF_CERT@"

[Authenticate CSF]

[Unlock]
	# Leave Job Ring and DECO master ID registers Unlocked
	Engine = CAAM
	Features = MID

[Install Key]
	# Key slot index used to authenticate the key to be installed
	Verification index = 0
	# Target key slot in HAB key store where key will be installed
	Target index = 2
	# Key to install
	File = "@CST_IMG_CERT@"

[Authenticate Data]
	# Key slot index used to authenticate the image data
	Verification index = 2
	# Authenticate Start Address, Offset, Length and file
EOF

	# Update Key Locations
	sed -i "s|@CST_SRK_TABLE@|${CST_SRK_TABLE}|g" ${CSF_SPL}.csf
	sed -i "s|@CST_CSF_CERT@|${CST_CSF_CERT}|g" ${CSF_SPL}.csf
	sed -i "s|@CST_IMG_CERT@|${CST_IMG_CERT}|g" ${CSF_SPL}.csf

	# Append Blocks
	echo "	Blocks = $(grep 'spl hab block' ${MKIMAGE_LOG} | awk '{print $4, $5, $6}') \"${FLASH_IMAGE}\"" >> ${CSF_SPL}.csf

	# Generate Binary
	${CST_BIN} -i ${CSF_SPL}.csf -o ${CSF_SPL}.bin 2>&1 | tee ${CSF_SPL}.log
	cat ${CSF_SPL}.log
}

create_csf_fit() {
	# Use SPL CSF as template
	cat > ${CSF_FIT}.csf << EOF
[Header]
	Version = 4.3
	Hash Algorithm = sha256
	Engine = CAAM
	Engine Configuration = 0
	Certificate Format = X509
	Signature Format = CMS

[Install SRK]
	# Index of the key location in the SRK table to be installed
	File = "@CST_SRK_TABLE@"
	Source index = 0

[Install CSFK]
	# Key used to authenticate the CSF data
	File = "@CST_CSF_CERT@"

[Authenticate CSF]

[Install Key]
	# Key slot index used to authenticate the key to be installed
	Verification index = 0
	# Target key slot in HAB key store where key will be installed
	Target index = 2
	# Key to install
	File = "@CST_IMG_CERT@"

[Authenticate Data]
	# Key slot index used to authenticate the image data
	Verification index = 2
	# Authenticate Start Address, Offset, Length and file
EOF

	# Update Key Locations
	sed -i "s|@CST_SRK_TABLE@|${CST_SRK_TABLE}|g" ${CSF_FIT}.csf
	sed -i "s|@CST_CSF_CERT@|${CST_CSF_CERT}|g" ${CSF_FIT}.csf
	sed -i "s|@CST_IMG_CERT@|${CST_IMG_CERT}|g" ${CSF_FIT}.csf

	# Append Blocks

	# Append block from mkimage log
	echo "	Blocks = $(grep 'sld hab block' ${MKIMAGE_LOG} | awk '{print $4, $5, $6}') \"${FLASH_IMAGE}\", \\" >> ${CSF_FIT}.csf

	# Append blocks from mkimage print_fit_hab
	# It looks like this, with a variable number of lines after TEE_LOAD_ADDR....
	# TEE_LOAD_ADDR=0xbe000000 ATF_LOAD_ADDR=0x00920000 VERSION=v1 ./print_fit_hab.sh 0x60000 imx8mm-var-dart-customboard.dtb imx8mm-var-som-symphony.dtb
	# 0x40200000 0x5AC00 0xA8F90
	# 0x402A8F90 0x103B90 0x7942
	# 0x402B08D2 0x10B4D4 0x7AEA
	# 0x920000 0x112FC0 0xA1E0

	# Read to end of file
	BLOCKS_RAW="$(sed -n '/TEE_LOAD_ADDR=/,$p' ${LOG_PRINT_FIT_HAB})"
	# Split each newline into array
	readarray -t BLOCKS <<<"$BLOCKS_RAW"
	# Remove first line
	unset BLOCKS[0]
	# Loop through each line
	PREFIX=""
	for BLOCK in "${BLOCKS[@]}"; do
		printf "${PREFIX}	${BLOCK} \"${FLASH_IMAGE}\"" >> ${CSF_FIT}.csf
		PREFIX=", \\ \n"
	done
	echo "" >> ${CSF_FIT}.csf

	# Generate Binary
	${CST_BIN} -i ${CSF_FIT}.csf -o ${CSF_FIT}.bin > ${CSF_FIT}.log 2>&1
	cat ${CSF_FIT}.log
}

# MX8
create_csf_ahab() {
	CST_DIR=${CST_BIN%/*}
	IMAGE_CSF=${CST_DIR}/${TARGET}.csf

	# Copy template file
	cat > ${IMAGE_CSF} << EOF
[Header]
Target = AHAB
Version = 1.0

[Install SRK]
# SRK table generated by srktool
File = "@CST_SRK_TABLE@"
# Public key certificate in PEM format
Source = "@CST_KEY@"
# Index of the public key certificate within the SRK table (0 .. 3)
Source index = 0
# Type of SRK set (NXP or OEM)
Source set = OEM
# bitmask of the revoked SRKs
Revocations = 0x0

[Authenticate Data]
# Binary to be signed generated by mkimage
File = "@FLASH_BIN@"
# Offsets = Container header Signature block (printed out by mkimage)
Offsets   = 0x400			 0x590
EOF

	# Get offset from log
	HEADER=$(cat ${MKIMAGE_LOG} | grep "CST: CONTAINER 0 offset:" | tail -1 | awk '{print $5}')
	BLOCK=$(cat ${MKIMAGE_LOG} | grep "CST: CONTAINER 0: Signature Block" | tail -1 | awk '{print $9}')

	# Update SRK files
	sed -i "s|@CST_SRK_TABLE@|${CST_SRK_TABLE}|g" ${IMAGE_CSF}
	sed -i "s|@CST_KEY@|${CST_KEY}|g" ${IMAGE_CSF}

	# Update offset
	sed -i "s|@FLASH_BIN@|${FLASH_IMAGE}|g" ${IMAGE_CSF}
	sed -i '/Offsets   = 0x400/d' ${IMAGE_CSF}
	echo "Offsets = ${HEADER} ${BLOCK}" >> ${IMAGE_CSF}
}

sign_flash_ahab () {
	# Sign flash.bin
	${CST_BIN} -i ${IMAGE_CSF} -o flash.bin.signed

    printf "Copy ${BOOT_STAGING}/flash.bin-signed to ${S}/${BOOT_CONFIG_MACHINE}-${TARGET}-signed\n"
    cp ${BOOT_STAGING}/flash.bin-signed ${S}/${BOOT_CONFIG_MACHINE}-${TARGET}-signed
}

sign_flash_habv4 () {
    offset_spl="$(cat ${MKIMAGE_LOG} | grep -w " csf_off" | awk '{print $NF}')"
    offset_fit="$(cat ${MKIMAGE_LOG} | grep -w " sld_csf_off" | awk '{print $NF}')"
    printf "offset_spl: ${offset_spl}, offset_fit: ${offset_fit}\n"

    # Copy imx-boot image
    IMG_ORIG="${FLASH_IMAGE}"
    IMG_SIGNED="${FLASH_IMAGE}.signed"
    cp -f ${IMG_ORIG} ${IMG_SIGNED}

    # Insert SPL and FIT Signatures
    dd if=${CSF_SPL}.bin of=${IMG_SIGNED} seek=$(printf "%d" ${offset_spl}) bs=1 conv=notrunc
    dd if=${CSF_FIT}.bin of=${IMG_SIGNED} seek=$(printf "%d" ${offset_fit}) bs=1 conv=notrunc
}

generate_csf() {
	tgt="$1"

	verify_env "${CST_BIN}" "CST_BIN"
	verify_env "${FLASH_IMAGE}" "FLASH_IMAGE"
	verify_env "${CST_SRK_TABLE}" "CST_SRK_TABLE"
	verify_env "${MKIMAGE_LOG}" "MKIMAGE_LOG"

	case ${tgt} in
	*MX8M*)
		verify_env "${CST_CSF_CERT}" "CST_CSF_CERT"
		verify_env "${CST_IMG_CERT}" "CST_IMG_CERT"
		verify_env "${LOG_PRINT_FIT_HAB}" "LOG_PRINT_FIT_HAB"
		create_csf_spl
		create_csf_fit
		sign_flash_habv4
		;;
	*MX8X|*MX8)
		verify_env "${CST_KEY}" "CST_KEY"
		create_csf_ahab
		sign_flash_ahab
		;;
	*)
		echo "Unsupported SOC $1"
		;;
	esac
}

