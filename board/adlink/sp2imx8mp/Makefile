#
# Copyright 2019 NXP
#
# SPDX-License-Identifier:      GPL-2.0+
#

obj-y += sp2imx8mp.o
obj-y += ../../freescale/common/

ifdef CONFIG_SPL_BUILD
obj-y += spl.o
ifdef CONFIG_IMX8M_LPDDR4_FREQ0_3200MTS
obj-y += lpddr4_timing_ndm.o
else
obj-$(CONFIG_LPDDR4_2GB)$(CONFIG_LPDDR4_ALL) += lpddr4_timing_MT53E512M32D1ZW-046_WTD_2000MHz.o
obj-$(CONFIG_LPDDR4_4GB)$(CONFIG_LPDDR4_ALL) += lpddr4_timing_MT53E1G32D2FW-046_WTD_2000MHz.o
obj-$(CONFIG_LPDDR4_8GB)$(CONFIG_LPDDR4_ALL) += lpddr4_timing_MT53E2G32D4DE-046_AIT_2000MHz.o
obj-$(CONFIG_IMX8M_DDR4) += ddr4_timing.o
endif
endif
