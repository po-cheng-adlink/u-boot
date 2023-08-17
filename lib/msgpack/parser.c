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

#include <log.h>
#include <i2c.h>
#include <msgpack.h>

static char* pkey = NULL;
static char* pval = NULL;

/*
 * read_eeprom - reads the eeprom specified by the config bus and addr on the target board
 *        buf: output buffer
 */
#if !defined (EEPROM_I2CBUS)
#  define EEPROM_I2CBUS 1
#endif
#if !defined (EEPROM_ADDR)
#  define EEPROM_ADDR 0x54
#endif
#if !defined (EEPROM_SIZE)
#  define EEPROM_SIZE 1024
#endif
int read_eeprom(uint8_t *buf)
{
	int ret;
#if !CONFIG_IS_ENABLED(DM_I2C)
	int old_bus;

	i2c_init(CONFIG_SYS_I2C_SPEED, CONFIG_SYS_I2C_SLAVE);

	old_bus = i2c_get_bus_num();
	i2c_set_bus_num(EEPROM_I2CBUS);

	ret = i2c_read(EEPROM_ADDR, 0, 1, buf, EEPROM_SIZE);
	i2c_set_bus_num(old_bus);
#else
	struct udevice *dev;

	ret = i2c_get_chip_for_busnum(EEPROM_I2CBUS, EEPROM_ADDR, 1, &dev);
	if (!ret)
		ret = dm_i2c_read(dev, 0, buf, EEPROM_SIZE);
#endif
	if (ret) {
		log_err("%s() ret: %d, Cannot read EEPROM on I2C-%d @0x%02x\n", __func__, ret, EEPROM_I2CBUS, EEPROM_ADDR);
		return ret;
	}
	return 0;
}

/*
 * find_endflag - look for a1 2d a1 2d (our ending flag, i.e. "-":"-") in buffer
 * returns the number of bytes of the valid msgpacked buffer or 0 for not found
 *        buf: msg packed buff
 *        maxlen: max length of msg packed buff
 */
int find_endflag(const char *const buf, size_t maxlen)
{
	const char ending[] = { '\xa1', '\x2d', '\xa1', '\x2d' };
	char* pos = NULL;
	int msglen = 0;

	pos = strstr (buf, ending);
	if (pos != NULL)
		msglen = pos - buf + sizeof(ending);

	return (msglen <= maxlen) ? msglen : 0;
}

/*
 * env_set_kv - a callback function to set key and value
 *              to Uboot Environment Variable if in U-Boot
 */
void env_set_kv(char* key, char* val) {
	if (pkey != NULL && pval != NULL) {
		debug("%s() pkey: %s, pval: %s, key: %s, val: %s\n", __func__, pkey, pval, key, val);
		if (!strcasecmp(pkey, key)) {
			strncpy(pval, val, strlen(val));
		}
	} else {
		debug("%s() env_set(key: %s, val: %s)\n", __func__, key, val);
#ifndef CONFIG_SPL_BUILD
		env_set(key, val);
#endif
	}
}

/*
 * get_msgvars - Sets the uboot env variables according to unpacked msgpack,
 *               adopted from msgpack_object_print_buffer() fn
 *
 * returns -ve for error, 0 for success and +ve number for bytes copied to val.
 */
static int get_msgvars(msgpack_object o, void* key, void* val)
{
	int ret = 0;
	/* clears val buffer everytime the fn is called */
	memset(val, 0, 16);

	switch(o.type) {
	/* When the OBJECT is a BOOLEAN/+INTEGER/-INTEGTER, deal with env_set_kv directly with key passed in */
	case MSGPACK_OBJECT_BOOLEAN:
		env_set_kv(key, o.via.boolean ? "1" : "0");
		ret = sizeof(bool);
		break;

	case MSGPACK_OBJECT_POSITIVE_INTEGER:
		if (o.via.u64 > (~0UL)) {
			ret = ERANGE;
		} else {
			sprintf(val, "%llu", (uint64_t)o.via.u64);
			env_set_kv(key, val);
			ret = sizeof(uint64_t);
		}
		break;

	case MSGPACK_OBJECT_NEGATIVE_INTEGER:
		if (o.via.i64 > ((long)(~0UL>>1)) || o.via.i64 < (-(long)(~0UL>>1) - 1)) {
			ret = ERANGE;
		} else {
			sprintf(val, "%lld", (int64_t)o.via.i64);
			env_set_kv(key, val);
			ret = sizeof(int64_t);
		}
		break;

#if !defined(_KERNEL_MODE)
	/* we don't deal with these other formats for values */
	case MSGPACK_OBJECT_NIL:
	case MSGPACK_OBJECT_FLOAT32:
	case MSGPACK_OBJECT_FLOAT64:
	case MSGPACK_OBJECT_BIN:
	case MSGPACK_OBJECT_EXT:
		ret = ENOSYS;
		break;
#endif

	/* When the OBJECT is a string, the caller deal with env_set
	   NOTE: key is a string object, and some values are also strings,
	         for the values that are BOOLEAN/+INTEGER/-INTEGER, they
	         are dealt with directly (where key already been parsed). */
	case MSGPACK_OBJECT_STR:
		if (o.via.str.size > 0) {
			memcpy(val, o.via.str.ptr, (int)o.via.str.size);
			ret = o.via.str.size;
		}
		break;

	/* for ARRAY, we first make incremental key names, then
	   recursive call to parse more values */
	case MSGPACK_OBJECT_ARRAY:
		if(o.via.array.size != 0) {
			int index = 0;
			char keystr[12];
			msgpack_object* p = o.via.array.ptr;
			msgpack_object* const pend = o.via.array.ptr + o.via.array.size;
			/* loop through array items */
			sprintf(keystr, "%s%d", (char*)key, index);
			ret = get_msgvars(*p, keystr, val);
			if (ret > 0 && ret < 16 && ((*p).type == MSGPACK_OBJECT_STR)) {
				env_set_kv(keystr, val);
			}
			++p; ++index;
			for(; p < pend; ++p, ++index) {
				sprintf(keystr, "%s%d", (char*)key, index);
				ret = get_msgvars(*p, keystr, val);
				if (ret > 0 && ret < 16 && ((*p).type == MSGPACK_OBJECT_STR)) {
					env_set_kv(keystr, val);
				}
			}
		}
		break;

	/* for MAP/DICT, we recursive call to parse more Key, Value pairs */
	case MSGPACK_OBJECT_MAP:
		if(o.via.map.size != 0) {
			msgpack_object_kv* p = o.via.map.ptr;
			msgpack_object_kv* const pend = o.via.map.ptr + o.via.map.size;
			/* get key */
			ret = get_msgvars(p->key, key, val);
			if (ret > 0 && ret < 16 && ((p->key).type == MSGPACK_OBJECT_STR)) {
				memset(key, 0, 8);
				memcpy(key, "E_", 2);
				memcpy(key+2, val, ret);
			}
			/* get value */
			ret = get_msgvars(p->val, key, val);
			if (ret > 0 && ret < 16 && ((p->val).type == MSGPACK_OBJECT_STR)) {
				env_set_kv(key, val);
			}

			/* next element */
			++p;
			for(; p < pend; ++p) {
				/* get key */
				ret = get_msgvars(p->key, key, val);
				if (ret > 0 && ret < 16 &&  ((p->key).type == MSGPACK_OBJECT_STR)) {
					memset(key, 0, 8);
					memcpy(key, "E_", 2);
					memcpy(key+2, val, ret);
				}
				/* get value */
				ret = get_msgvars(p->val, key, val);
				if ((ret > 0 && ret < 16) && ((p->val).type == MSGPACK_OBJECT_STR)) {
					if (! (strcmp(val, "-") == 0 && strcmp(key, "E_-") == 0)) {
						env_set_kv(key, val);
					}
				}
			}
		}
		break;

	default:
		// FIXME
		if (o.via.u64 > (~0UL)) {
			*((uint64_t*)val) = o.type;
			ret = ERANGE;
		} else {
			*((uint64_t*)val) = o.via.u64;
			ret = ENOMSG;
		}
	}

	return ret;
}

/*
 * unpack_msg - unpack msgpacked data
 *        buf: msg packed buffer
 *        buflen: length of msg packed buffer (i.e. size of eeprom, 
 *                with unknowns after original msg-packed buffer)
 */
msgpack_unpack_return unpack_msg(const char *const buf, size_t buflen)
{
	/* buf is allocated by client. */
	msgpack_unpacked result;
	size_t off = 0;
	msgpack_unpack_return ret;
	char k[8]; /* our key is limited to 4 bytes */
	char v[16]; /* our longest value should be mac address (12 bytes) */

	msgpack_unpacked_init(&result);
	ret = msgpack_unpack_next(&result, buf, buflen, &off);
	while (ret == MSGPACK_UNPACK_SUCCESS) {
		msgpack_object obj = result.data;
		/* set uboot env variable accordingly */
		get_msgvars(obj, k, v);
		ret = msgpack_unpack_next(&result, buf, buflen, &off);
	}
	msgpack_unpacked_destroy(&result);

	if (ret == MSGPACK_UNPACK_CONTINUE) {
		debug("All msgpack_object in the buffer is consumed.\n");
		ret = 0;
	}
	else if (ret == MSGPACK_UNPACK_PARSE_ERROR) {
		debug("The data in the buf is invalid format.\n");
	}
	return ret;
}

int parse_eeprom(uint8_t *buffer, char *key, char *val) {
	int msglen;
	msgpack_sbuffer sbuf;
	msgpack_sbuffer_init(&sbuf);

	pkey = key;
	pval = val;

	/* find the end of msgpacked msg */
	msglen = find_endflag(buffer, EEPROM_SIZE);
	if (msglen > 0) {
		/* set sbuf.data to buffer passed in for msg unpack */
		sbuf.data = buffer;
		sbuf.size = msglen;
		/* msg-unpack and set uboot env variable */
		unpack_msg(sbuf.data, sbuf.size);
		sbuf.data = NULL;
		msgpack_sbuffer_destroy(&sbuf);

		/* json parsed into uboot environment variable */
		return 0;
	}
	return -EAGAIN;
}

