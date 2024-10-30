// SPDX-License-Identifier: GPL-2.0+
/*
 * (C) Copyright 2018
 * DENX Software Engineering, Anatolij Gustschin <agust@denx.de>
 *
 * cls - clear screen command
 */
#include <common.h>
#include <command.h>
#include <dm.h>
#include <panel.h>
#include <backlight.h>

/* Disable panel */
static int do_panel(struct cmd_tbl *cmdtp, int flag, int argc,
		   char *const argv[])
{
	struct udevice *dev;
	if (uclass_first_device_err(UCLASS_PANEL, &dev)) {
		printf("\rCouldn't get PANEL device\n");
		return CMD_RET_FAILURE;
	}

	if (argc > 1 && argc <= 2) {
		if (strcmp(argv[1], "on") == 0) {
			panel_set_backlight(dev, 80);
			panel_enable_backlight(dev);
			return CMD_RET_SUCCESS;
		} else if (strcmp(argv[1], "off") == 0) {
			panel_set_backlight(dev, BACKLIGHT_OFF);
			panel_enable_backlight(dev);
			return CMD_RET_SUCCESS;
		}
	}
	return CMD_RET_FAILURE;
}

U_BOOT_CMD(panel, 2, 1, do_panel, "turn panel on or off", "<on|off>\n" "    e.g panel off");

