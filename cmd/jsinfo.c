// SPDX-License-Identifier: GPL-2.0+
/*
 * Serial Presence Detect - EEPROM but not for DDR modules
 * spd_eeprom.c - based on spd_sdram.c from arch/powerpc/ (freescale mpc83xx)
 *
 * Created on: Aug 16, 2023
 *
 * (C) Copyright 2013 ADLINK, Inc.
 *
 * Po Cheng, ADLINK, Inc, po@adlinktech.com
 *  *
 */

#include <common.h>
#include <log.h>
#include <time.h>
#include <vsprintf.h>
#include <i2c.h>
#include <command.h>
#include <env.h>

#include <inttypes.h>
#include <ctype.h>

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if !defined (EEPROM_SIZE)
#  define EEPROM_SIZE 1024
#endif

extern int read_eeprom(uint8_t *buf);
extern int parse_eeprom(uint8_t *buffer, const char *key, char *value);

/*
 * do_parse_eeprom - handles the jsinfo command.
 */
static int do_parse_eeprom(struct cmd_tbl *cmdtp, int flag, int argc, char *const argv[])
{
	int ret;
	uint8_t buffer[EEPROM_SIZE];

	/* read msg packed content from eeprom */
	ret = read_eeprom(buffer);
	if (ret)
		return ret;

	/* parse the eeprom content */
	ret = parse_eeprom(buffer, NULL, NULL);

	return (ret) ? CMD_RET_FAILURE : CMD_RET_SUCCESS;
}

/* U_BOOT_CMD(_name, _maxargs, _rep, _cmd, _usage, _help) */
U_BOOT_CMD(jsinfo, 1, 1, do_parse_eeprom,
	"read msgpacked eeprom and parse to json format",
	"    Parse MsgPacked EEPROM as json and show Adlink Specific Configurations"
);

