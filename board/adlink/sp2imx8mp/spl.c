// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * Copyright 2018-2019, 2021 NXP
 *
 */

#include <common.h>
#include <hang.h>
#include <init.h>
#include <log.h>
#include <spl.h>
#include <asm/global_data.h>
#include <asm/arch/imx8mp_pins.h>
#include <asm/arch/sys_proto.h>
#include <asm/mach-imx/boot_mode.h>
#include <power/pmic.h>

#include <power/pca9450.h>
#include <asm/arch/clock.h>
#include <dm/uclass.h>
#include <dm/device.h>
#include <dm/uclass-internal.h>
#include <dm/device-internal.h>
#include <asm/mach-imx/gpio.h>
#include <asm/mach-imx/iomux-v3.h>
#include <asm/mach-imx/mxc_i2c.h>
#include <fsl_esdhc_imx.h>
#include <mmc.h>
#include <asm/arch/ddr.h>
#include <asm/sections.h>

#include "lpddr4_timing.h"

DECLARE_GLOBAL_DATA_PTR;

int spl_board_boot_device(enum boot_device boot_dev_spl)
{
#ifdef CONFIG_SPL_BOOTROM_SUPPORT
	return BOOT_DEVICE_BOOTROM;
#else
	switch (boot_dev_spl) {
	case SD1_BOOT:
	case MMC1_BOOT:
	case SD2_BOOT:
	case MMC2_BOOT:
		return BOOT_DEVICE_MMC1;
	case SD3_BOOT:
	case MMC3_BOOT:
		return BOOT_DEVICE_MMC2;
	case QSPI_BOOT:
		return BOOT_DEVICE_NOR;
	case NAND_BOOT:
		return BOOT_DEVICE_NAND;
	case USB_BOOT:
		return BOOT_DEVICE_BOARD;
	default:
		return BOOT_DEVICE_NONE;
	}
#endif
}

/*********************************************
 * LPDDR4
 *********************************************/
/* dram sku detection using gpio */
#define SKU_DET_GPIO_PAD_CTRL (PAD_CTL_HYS | PAD_CTL_DSE1)
static iomux_v3_cfg_t const sku_det_pads[] = {
	MX8MP_PAD_SPDIF_EXT_CLK__GPIO5_IO05 | MUX_PAD_CTRL(SKU_DET_GPIO_PAD_CTRL), /* HWID_1 */
	MX8MP_PAD_SAI3_RXFS__GPIO4_IO28 | MUX_PAD_CTRL(SKU_DET_GPIO_PAD_CTRL), /* HWID_2 */
	MX8MP_PAD_SAI3_RXC__GPIO4_IO29 | MUX_PAD_CTRL(SKU_DET_GPIO_PAD_CTRL), /* HWID_3 */
};
#define HWID_1		IMX_GPIO_NR(5, 5)
#define HWID_2		IMX_GPIO_NR(4, 28)
#define HWID_3		IMX_GPIO_NR(4, 29)
/*******************************************************************************
 HWID3       HWID2       HWID1       DRAM(LPDDR4)  PN
    0           0           0          2G*         MT53E512M32D1ZW-046 WT:B
    0           0           1          4G          MT53E1G32D2FW-046 WT:B/IT:B
    0           1           0          8G          MT53E2G32D4DE-046 AIT:C
    0           1           1          1G          MT53E256M32D1KS-046 WT:L
*******************************************************************************/
int get_dram_sku(void)
{
	uint32_t hwid = 0;
	imx_iomux_v3_setup_multiple_pads(sku_det_pads, ARRAY_SIZE(sku_det_pads));

	gpio_request(HWID_1, "sku_hwid1");
	gpio_direction_input(HWID_1);
	gpio_request(HWID_2, "sku_hwid2");
	gpio_direction_input(HWID_2);
	gpio_request(HWID_3, "sku_hwid3");
	gpio_direction_input(HWID_3);

	hwid = (gpio_get_value(HWID_3) << 2) | (gpio_get_value(HWID_2) << 1) | gpio_get_value(HWID_1);
	return hwid;
}

#if CONFIG_IS_ENABLED(HANDOFF)
int handoff_arch_save(struct spl_handoff *ho)
{
	debug("%s() handoff: %p\n", __func__, ho);
	ho->arch.sku = get_dram_sku();
	return 0;
}
#endif

void spl_dram_init(void)
{
	struct { int size; struct dram_timing_info *timing; } dram_timing[] = {

#if defined(CONFIG_LPDDR4_2GB) || defined(CONFIG_LPDDR4_ALL)
		{2, &dram_timing_2G}, /* default */
#else
		{2, NULL}, /* point to nothing to keep array index */
#endif
#if defined(CONFIG_LPDDR4_4GB) || defined(CONFIG_LPDDR4_ALL)
		{4, &dram_timing_4G}, /* &dram_timing_lpddr4_4gb, */
#else
		{4, NULL}, /* point to nothing to keep array index */
#endif
#if defined(CONFIG_LPDDR4_8GB) || defined(CONFIG_LPDDR4_ALL)
		{8, &dram_timing_8G}, /* &dram_timing_lpddr4_8gb, */
#else
		{8, NULL}, /* point to nothing to keep array index */
#endif
#if defined(CONFIG_LPDDR4_ALL)
		{1, &dram_timing_2G}, /* &dram_timing_lpddr4_1gb, */
		{2, &dram_timing_2G}, /* NULL, default to 2gb */
		{2, &dram_timing_2G}, /* NULL, default to 2gb */
		{2, &dram_timing_2G}, /* NULL, default to 2gb */
		{2, &dram_timing_2G}, /* NULL, default to 2gb */
#else
		{1, NULL}, /* point to nothing to keep array index */
		{2, NULL}, /* point to nothing to keep array index */
		{2, NULL}, /* point to nothing to keep array index */
		{2, NULL}, /* point to nothing to keep array index */
		{2, NULL}, /* point to nothing to keep array index */
#endif
	};
	int dram_sku = get_dram_sku();

	printf("DRAM SKU(0x%02x) => %dGB\n", dram_sku, dram_timing[dram_sku].size);
	ddr_init(dram_timing[dram_sku].timing);
}

void spl_board_init(void)
{
	arch_misc_init();

	/*
	 * Set GIC clock to 500Mhz for OD VDD_SOC. Kernel driver does
	 * not allow to change it. Should set the clock after PMIC
	 * setting done. Default is 400Mhz (system_pll1_800m with div = 2)
	 * set by ROM for ND VDD_SOC
	 */
#if defined(CONFIG_IMX8M_LPDDR4) && !defined(CONFIG_IMX8M_VDD_SOC_850MV)
	clock_enable(CCGR_GIC, 0);
	clock_set_target_val(GIC_CLK_ROOT, CLK_ROOT_ON | CLK_ROOT_SOURCE_SEL(5));
	clock_enable(CCGR_GIC, 1);

	puts("Normal Boot\n");
#endif
}

#if CONFIG_IS_ENABLED(DM_PMIC_PCA9450)
int power_init_board(void)
{
	struct udevice *dev;
	int ret;
	int value;

	ret = pmic_get("pmic@25", &dev);
	if (ret == -ENODEV) {
		puts("No pmic@25\n");
		return 0;
	}
	if (ret < 0)
		return ret;

	value = pmic_reg_read(dev, PCA9450_BUCK5CTRL);
	printf("PMIC: PCA9450_BUCK5CTRL: 0x%x\n", value);
	value = pmic_reg_read(dev, PCA9450_BUCK5OUT);
	printf("PMIC: PCA9450_BUCK5OUT: 0x%x\n", value);

	/* BUCKxOUT_DVS0/1 control BUCK123 output */
	pmic_reg_write(dev, PCA9450_BUCK123_DVS, 0x29);

#ifdef CONFIG_IMX8M_LPDDR4
	/*
	 * Increase VDD_SOC to typical value 0.95V before first
	 * DRAM access, set DVS1 to 0.85V for suspend.
	 * Enable DVS control through PMIC_STBY_REQ and
	 * set B1_ENMODE=1 (ON by PMIC_ON_REQ=H)
	 */
	if (CONFIG_IS_ENABLED(IMX8M_VDD_SOC_850MV))
		pmic_reg_write(dev, PCA9450_BUCK1OUT_DVS0, 0x14);
	else
		pmic_reg_write(dev, PCA9450_BUCK1OUT_DVS0, 0x1C);

	pmic_reg_write(dev, PCA9450_BUCK1OUT_DVS1, 0x14);
	pmic_reg_write(dev, PCA9450_BUCK1CTRL, 0x59);

	/*
	 * Kernel uses OD/OD freq for SOC.
	 * To avoid timing risk from SOC to ARM,increase VDD_ARM to OD
	 * voltage 0.95V.
	 */

	pmic_reg_write(dev, PCA9450_BUCK2OUT_DVS0, 0x1C);
#elif defined(CONFIG_IMX8M_DDR4)
	/* DDR4 runs at 3200MTS, uses default ND 0.85v for VDD_SOC and VDD_ARM */
	pmic_reg_write(dev, PCA9450_BUCK1CTRL, 0x59);

	/* Set NVCC_DRAM to 1.2v for DDR4 */
	pmic_reg_write(dev, PCA9450_BUCK6OUT, 0x18);
#endif

	return 0;
}
#endif

#ifdef CONFIG_SPL_LOAD_FIT
int board_fit_config_name_match(const char *name)
{
	/* Just empty function now - can't decide what to choose */
	debug("%s: %s\n", __func__, name);

	return 0;
}
#endif

void board_init_f(ulong dummy)
{
	struct udevice *dev;
	int ret;

	/* Clear the BSS. */
	memset(__bss_start, 0, __bss_end - __bss_start);

	arch_cpu_init();

	board_early_init_f();

	timer_init();

	ret = spl_early_init();
	if (ret) {
		debug("spl_early_init() failed: %d\n", ret);
		hang();
	}

	ret = uclass_get_device_by_name(UCLASS_CLK,
					"clock-controller@30380000",
					&dev);
	if (ret < 0) {
		printf("Failed to find clock node. Check device tree\n");
		hang();
	}

	preloader_console_init();

	enable_tzc380();

	power_init_board();

	/* DDR initialization */
	spl_dram_init();

	board_init_r(NULL, 0);
}
