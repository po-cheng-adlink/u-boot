// SPDX-License-Identifier: GPL-2.0+
/*
 * Copyright (c) 2016 Google, Inc
 * Written by Simon Glass <sjg@chromium.org>
 */

#include <common.h>
#include <backlight.h>
#include <dm.h>
#include <log.h>
#include <panel.h>
#include <asm/gpio.h>
#include <power/regulator.h>

struct lvds_panel_priv {
	struct udevice *reg;
	struct udevice *power;
	struct udevice *backlight;
	struct gpio_desc enable;
	struct gpio_desc reset;
	struct display_timing of_timings;
};

static const struct display_timing default_timing = {
	.pixelclock.typ	= 62000000,
	.hactive.typ	= 720,
	.hfront_porch.typ	= 10,
	.hback_porch.typ	= 30,
	.hsync_len.typ	= 20,
	.vactive.typ	= 1280,
	.vfront_porch.typ	= 10,
	.vback_porch.typ	= 20,
	.vsync_len.typ	= 10,
};

static int lvds_panel_get_display_timing(struct udevice *dev,
					    struct display_timing *timings)
{
	struct lvds_panel_priv *priv = dev_get_priv(dev);

	if (priv->of_timings.pixelclock.typ != 0) {
		debug("%s: retrieve display timing: (%d, %d)\n", __func__, priv->of_timings.hactive.typ, priv->of_timings.vactive.typ);
		memcpy(timings, &priv->of_timings, sizeof(*timings));
	} else {
		debug("%s: retrieve default display timing: (%d, %d)\n", __func__, priv->of_timings.hactive.typ, priv->of_timings.vactive.typ);
		memcpy(timings, &default_timing, sizeof(*timings));
	}

	return 0;
}

static int lvds_panel_enable_backlight(struct udevice *dev)
{
	struct lvds_panel_priv *priv = dev_get_priv(dev);
	int ret;

	dm_gpio_set_value(&priv->enable, 1);
	if (priv->backlight) {
		debug("%s: start, backlight = '%s'\n", __func__, priv->backlight->name);
		ret = backlight_enable(priv->backlight);
		debug("%s: done, ret = %d\n", __func__, ret);
		if (ret)
			return ret;
	}

	return 0;
}

static int lvds_panel_set_backlight(struct udevice *dev, int percent)
{
	struct lvds_panel_priv *priv = dev_get_priv(dev);
	int ret;

	debug("%s: start, backlight = '%s'\n", __func__, priv->backlight->name);
	dm_gpio_set_value(&priv->enable, 1);
	if (priv->backlight) {
		ret = backlight_set_brightness(priv->backlight, percent);
		debug("%s: done, ret = %d\n", __func__, ret);
		if (ret)
			return ret;
	}

	return 0;
}

static int lvds_panel_of_to_plat(struct udevice *dev)
{
	struct lvds_panel_priv *priv = dev_get_priv(dev);
	int ret;

	if (IS_ENABLED(CONFIG_DM_REGULATOR)) {
		ret = uclass_get_device_by_phandle(UCLASS_REGULATOR, dev,
						   "power-supply", &priv->reg);
		if (ret) {
			debug("%s: Warning: cannot get power supply: ret=%d\n", __func__, ret);
			if (ret != -ENOENT)
				return ret;
		}
	}
	ret = uclass_get_device_by_phandle(UCLASS_PANEL_BACKLIGHT, dev,
					   "backlight", &priv->backlight);
	if (ret) {
		debug("%s: Cannot get backlight: ret=%d\n", __func__, ret);
		priv->backlight = NULL;
	}

	ret = ofnode_decode_display_timing(dev_ofnode(dev), 0, &priv->of_timings);
	if (ret) {
		debug("%s: Cannot get display timing: ret=%d\n", __func__, ret);
		memset(&priv->of_timings, 0, sizeof(struct display_timing));
	}

	ret = gpio_request_by_name(dev, "enable-gpios", 0, &priv->enable, GPIOD_IS_OUT);
	if (ret) {
		debug("%s: Warning: cannot get enable GPIO: ret=%d\n", __func__, ret);
		if (ret != -ENOENT)
			return log_ret(ret);
	}

	return 0;
}

static int lvds_panel_probe(struct udevice *dev)
{
	struct lvds_panel_priv *priv = dev_get_priv(dev);
	int ret;

	if (IS_ENABLED(CONFIG_DM_REGULATOR) && priv->reg) {
		debug("%s: Enable regulator '%s'\n", __func__, priv->reg->name);
		ret = regulator_set_enable(priv->reg, true);
		if (ret)
			return ret;
	}

	return 0;
}

static const struct panel_ops lvds_panel_ops = {
	.enable_backlight	= lvds_panel_enable_backlight,
	.set_backlight		= lvds_panel_set_backlight,
	.get_display_timing = lvds_panel_get_display_timing,
};

static const struct udevice_id lvds_panel_ids[] = {
	{ .compatible = "lvds-panel" },
	{ }
};

U_BOOT_DRIVER(lvds_panel) = {
	.name	= "lvds_panel",
	.id	= UCLASS_PANEL,
	.of_match = lvds_panel_ids,
	.ops	= &lvds_panel_ops,
	.of_to_plat	= lvds_panel_of_to_plat,
	.probe		= lvds_panel_probe,
	.priv_auto	= sizeof(struct lvds_panel_priv),
};
