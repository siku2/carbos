// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * Razer BlackWidow Chroma V2 (1532:0221).
 *
 * The keyboard takes 90 byte feature reports on interface 1, the layout
 * openrazer documents. Key input is handled like hid-generic does.
 *
 * Lighting is one LED for the whole backlight plus one LED per key. The
 * whole backlight runs hardware effects. While a key LED is lit, the driver
 * draws the frame itself, with the lit keys on top. Brightness is never
 * stored in the keyboard.
 */

#include <linux/fixp-arith.h>
#include <linux/hid.h>
#include <linux/led-class-multicolor.h>
#include <linux/leds.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/usb.h>
#include <linux/workqueue.h>

#define RKBD_CONTROL_INTERFACE 1

#define RKBD_REPORT_SIZE 90
#define RKBD_ARGS_MAX 80
#define RKBD_RETRIES 10

#define RKBD_ROWS 6
#define RKBD_COLS 22
#define RKBD_ROW_SIZE (3 * RKBD_COLS)

#define RKBD_FRAME_MS 40

enum {
	STATUS_BUSY = 0x01,
	STATUS_OK = 0x02,
	STATUS_FAILED = 0x03,
	STATUS_TIMEOUT = 0x04,
	STATUS_UNSUPPORTED = 0x05,
};

#define TID_DEFAULT 0xff
#define TID_MATRIX 0x3f

#define CLASS_DEVICE 0x00
#define CMD_FIRMWARE 0x81

#define CLASS_LED 0x03
#define CMD_BRIGHTNESS 0x03
#define CMD_MATRIX_EFFECT 0x0a
#define CMD_MATRIX_ROW 0x0b

#define NOSTORE 0x00
#define BACKLIGHT_LED 0x05
#define FRAME_ID 0xff

enum {
	EFFECT_WAVE = 0x01,
	EFFECT_REACTIVE = 0x02,
	EFFECT_BREATHING = 0x03,
	EFFECT_SPECTRUM = 0x04,
	EFFECT_CUSTOM = 0x05,
	EFFECT_STATIC = 0x06,
	EFFECT_STARLIGHT = 0x19,
};

#define RKBD_EFFECT_DIRECTION BIT(0)
/* The driver can draw the effect itself, under lit keys. */
#define RKBD_EFFECT_SOFT BIT(1)

#define HUE_MAX 1536
#define WAVE_STEP 30
#define SPECTRUM_STEP 10
#define BREATHING_FRAMES 100

struct rkbd_effect {
	struct led_trigger trigger;
	u8 id;
	u8 flags;
	/* Number of speed steps, 0 if the effect has no speed. */
	u8 speeds;
};

struct rkbd_key {
	u8 row;
	u8 col;
	u16 code;
	const char *name;
};

#include "layout.h"

#define RKBD_KEYS ARRAY_SIZE(rkbd_keys)

struct rkbd;

struct rkbd_led {
	struct rkbd *kb;
	struct led_classdev_mc mc;
	struct mc_subled subleds[3];
	unsigned int brightness;
	bool registered;
};

struct rkbd {
	struct hid_device *hdev;
	struct delayed_work animate;

	/* Serializes device I/O and all state below. */
	struct mutex lock;
	u8 *buf;
	/* No device I/O while suspended or after shutdown. */
	bool suspended;
	bool stopped;

	struct rkbd_led backlight;
	const struct rkbd_effect *effect;
	u8 speed;
	bool reverse;
	unsigned int tick;

	/* The effect the keyboard runs, to not restart it on brightness changes. */
	bool effect_valid;
	u8 effect_args[RKBD_ARGS_MAX];
	u8 effect_len;

	/* The driver draws the frame, and the keyboard is known to show it. */
	bool drawing;
	bool custom;
	bool shown_valid;
	u8 frame[RKBD_ROWS][RKBD_ROW_SIZE];
	u8 shown[RKBD_ROWS][RKBD_ROW_SIZE];

	struct rkbd_led keys[RKBD_KEYS];
};

static int rkbd_cmd(struct rkbd *kb, u8 tid, u8 class, u8 cmd, const u8 *args,
		    u8 len, u8 *resp)
{
	u8 *report = kb->buf + 1;
	u8 crc = 0;
	int i, ret;

	lockdep_assert_held(&kb->lock);

	if (len > RKBD_ARGS_MAX)
		return -EINVAL;

	memset(kb->buf, 0, RKBD_REPORT_SIZE + 1);
	report[1] = tid;
	report[5] = len;
	report[6] = class;
	report[7] = cmd;
	if (args)
		memcpy(report + 8, args, len);
	for (i = 2; i < 88; i++)
		crc ^= report[i];
	report[88] = crc;

	ret = hid_hw_raw_request(kb->hdev, 0, kb->buf, RKBD_REPORT_SIZE + 1,
				 HID_FEATURE_REPORT, HID_REQ_SET_REPORT);
	if (ret < 0)
		return ret;

	for (i = 0; i < RKBD_RETRIES; i++) {
		usleep_range(600, 800);
		ret = hid_hw_raw_request(kb->hdev, 0, kb->buf,
					 RKBD_REPORT_SIZE + 1,
					 HID_FEATURE_REPORT, HID_REQ_GET_REPORT);
		if (ret < 0)
			return ret;
		if (report[0] != STATUS_BUSY)
			break;
	}

	switch (report[0]) {
	case STATUS_OK:
		break;
	case STATUS_BUSY:
	case STATUS_TIMEOUT:
		return -ETIMEDOUT;
	case STATUS_UNSUPPORTED:
		return -EOPNOTSUPP;
	default:
		return -EIO;
	}
	if (report[6] != class || report[7] != cmd)
		return -EPROTO;

	if (resp)
		memcpy(resp, report + 8, RKBD_ARGS_MAX);
	return 0;
}

static int rkbd_set_brightness(struct rkbd *kb, u8 brightness)
{
	u8 args[] = { NOSTORE, BACKLIGHT_LED, brightness };

	return rkbd_cmd(kb, TID_DEFAULT, CLASS_LED, CMD_BRIGHTNESS, args,
			sizeof(args), NULL);
}

static void rkbd_led_rgb(const struct rkbd_led *led, unsigned int brightness,
			 u8 *rgb)
{
	int i;

	for (i = 0; i < 3; i++)
		rgb[i] = led->subleds[i].intensity * brightness / LED_FULL;
}

/* Builds the matrix effect command for the current state, returns its length. */
static u8 rkbd_effect_args(struct rkbd *kb, u8 *args)
{
	const struct rkbd_effect *effect = kb->effect;
	u8 rgb[3];

	rkbd_led_rgb(&kb->backlight, LED_FULL, rgb);

	if (!effect) {
		args[0] = EFFECT_STATIC;
		memcpy(args + 1, rgb, 3);
		return 4;
	}

	args[0] = effect->id;
	switch (effect->id) {
	case EFFECT_WAVE:
		args[1] = kb->reverse ? 2 : 1;
		return 2;
	case EFFECT_REACTIVE:
		/* The afterglow time, 1 is the shortest. */
		args[1] = effect->speeds - kb->speed;
		memcpy(args + 2, rgb, 3);
		return 5;
	case EFFECT_BREATHING:
		/* One color. */
		args[1] = 0x01;
		memcpy(args + 2, rgb, 3);
		return 8;
	case EFFECT_STARLIGHT:
		args[1] = 0x01;
		args[2] = effect->speeds - kb->speed;
		memcpy(args + 3, rgb, 3);
		return 9;
	default:
		return 1;
	}
}

static int rkbd_update_hardware(struct rkbd *kb)
{
	unsigned int brightness = kb->backlight.brightness;
	u8 args[RKBD_ARGS_MAX] = { };
	u8 len;
	int ret;

	/* Leaving custom mode, or changing its brightness behind the frame. */
	kb->custom = false;
	if (brightness) {
		len = rkbd_effect_args(kb, args);
		if (!kb->effect_valid || len != kb->effect_len ||
		    memcmp(args, kb->effect_args, len)) {
			kb->effect_valid = false;
			ret = rkbd_cmd(kb, TID_MATRIX, CLASS_LED,
				       CMD_MATRIX_EFFECT, args, len, NULL);
			if (ret)
				return ret;
			memcpy(kb->effect_args, args, len);
			kb->effect_len = len;
			kb->effect_valid = true;
		}
	}
	return rkbd_set_brightness(kb, brightness);
}

static void rkbd_hue_to_rgb(unsigned int hue, unsigned int brightness, u8 *rgb)
{
	u8 up = hue % 256, down = 255 - up;
	const u8 sectors[6][3] = {
		{ 255, up, 0 }, { down, 255, 0 }, { 0, 255, up },
		{ 0, down, 255 }, { up, 0, 255 }, { 255, 0, down },
	};
	const u8 *c = sectors[hue / 256];
	int i;

	for (i = 0; i < 3; i++)
		rgb[i] = c[i] * brightness / LED_FULL;
}

static bool rkbd_animated(struct rkbd *kb)
{
	return kb->drawing && kb->backlight.brightness && kb->effect;
}

static void rkbd_render(struct rkbd *kb)
{
	unsigned int brightness = kb->backlight.brightness;
	unsigned int row, col, hue, level, i;
	u8 *p;

	for (row = 0; row < RKBD_ROWS; row++) {
		for (col = 0; col < RKBD_COLS; col++) {
			p = &kb->frame[row][3 * col];
			if (!brightness) {
				memset(p, 0, 3);
				continue;
			}
			switch (kb->effect ? kb->effect->id : EFFECT_STATIC) {
			case EFFECT_WAVE:
				hue = col * HUE_MAX / RKBD_COLS;
				hue = kb->reverse ?
				      hue + kb->tick * WAVE_STEP :
				      hue + HUE_MAX - kb->tick * WAVE_STEP % HUE_MAX;
				rkbd_hue_to_rgb(hue % HUE_MAX, brightness, p);
				break;
			case EFFECT_SPECTRUM:
				hue = kb->tick * SPECTRUM_STEP % HUE_MAX;
				rkbd_hue_to_rgb(hue, brightness, p);
				break;
			case EFFECT_BREATHING:
				level = 0x7fff - fixp_cos16(kb->tick % BREATHING_FRAMES *
							   360 / BREATHING_FRAMES);
				rkbd_led_rgb(&kb->backlight,
					     brightness * level / 0xfffe, p);
				break;
			default:
				rkbd_led_rgb(&kb->backlight, brightness, p);
				break;
			}
		}
	}

	for (i = 0; i < RKBD_KEYS; i++) {
		const struct rkbd_led *key = &kb->keys[i];

		if (key->brightness)
			rkbd_led_rgb(key, key->brightness,
				     &kb->frame[rkbd_keys[i].row][3 * rkbd_keys[i].col]);
	}
}

static int rkbd_update_frame(struct rkbd *kb)
{
	u8 args[4 + RKBD_ROW_SIZE] = { FRAME_ID };
	u8 show[] = { EFFECT_CUSTOM, NOSTORE };
	bool entering = !kb->custom, changed = false, last_row = false;
	unsigned int row;
	int ret;

	rkbd_render(kb);

	for (row = 0; row < RKBD_ROWS; row++) {
		if (kb->shown_valid && !entering &&
		    !memcmp(kb->frame[row], kb->shown[row], RKBD_ROW_SIZE))
			continue;
		args[1] = row;
		args[2] = 0;
		args[3] = RKBD_COLS - 1;
		memcpy(args + 4, kb->frame[row], RKBD_ROW_SIZE);
		ret = rkbd_cmd(kb, TID_MATRIX, CLASS_LED, CMD_MATRIX_ROW, args,
			       sizeof(args), NULL);
		if (ret)
			goto err;
		changed = true;
		last_row = row == RKBD_ROWS - 1;
	}

	if (changed) {
		ret = rkbd_cmd(kb, TID_MATRIX, CLASS_LED, CMD_MATRIX_EFFECT,
			       show, sizeof(show), NULL);
		if (ret)
			goto err;
	}

	/*
	 * Entering custom mode and writing the last row reset the brightness to
	 * the stored one. The frame carries the brightness.
	 */
	if (entering || last_row) {
		ret = rkbd_set_brightness(kb, LED_FULL);
		if (ret)
			goto err;
		kb->custom = true;
		kb->effect_valid = false;
	}

	memcpy(kb->shown, kb->frame, sizeof(kb->shown));
	kb->shown_valid = true;
	return 0;

err:
	kb->shown_valid = false;
	kb->custom = false;
	return ret;
}

static bool rkbd_overlay(struct rkbd *kb)
{
	unsigned int i;

	for (i = 0; i < RKBD_KEYS; i++)
		if (kb->keys[i].brightness)
			return true;
	return false;
}

static void rkbd_schedule(struct rkbd *kb)
{
	if (rkbd_animated(kb))
		mod_delayed_work(system_dfl_wq, &kb->animate,
				 msecs_to_jiffies(RKBD_FRAME_MS));
}

static int rkbd_update(struct rkbd *kb)
{
	bool soft = !kb->effect || kb->effect->flags & RKBD_EFFECT_SOFT;
	int ret;

	lockdep_assert_held(&kb->lock);

	if (kb->suspended || kb->stopped)
		return 0;

	kb->drawing = soft && rkbd_overlay(kb);
	if (kb->drawing)
		ret = rkbd_update_frame(kb);
	else
		ret = rkbd_update_hardware(kb);
	if (ret)
		hid_err(kb->hdev, "failed to set the lighting: %d\n", ret);
	rkbd_schedule(kb);
	return ret;
}

static void rkbd_animate_work(struct work_struct *work)
{
	struct rkbd *kb = container_of(to_delayed_work(work), struct rkbd,
				       animate);

	guard(mutex)(&kb->lock);
	if (!rkbd_animated(kb))
		return;
	kb->tick++;
	rkbd_update(kb);
}

static struct rkbd_led *to_rkbd_led(struct led_classdev *cdev)
{
	return container_of(lcdev_to_mccdev(cdev), struct rkbd_led, mc);
}

static int rkbd_brightness_set(struct led_classdev *cdev,
			       enum led_brightness brightness)
{
	struct rkbd_led *led = to_rkbd_led(cdev);

	guard(mutex)(&led->kb->lock);
	led->brightness = brightness;
	return rkbd_update(led->kb);
}

static int rkbd_trigger_activate(struct led_classdev *cdev)
{
	struct rkbd *kb = to_rkbd_led(cdev)->kb;
	int ret;

	guard(mutex)(&kb->lock);
	kb->effect = container_of(cdev->trigger, struct rkbd_effect, trigger);
	if (kb->effect->speeds)
		kb->speed = min_t(u8, kb->speed, kb->effect->speeds - 1);
	if (!cdev->brightness)
		cdev->brightness = cdev->max_brightness;
	kb->backlight.brightness = cdev->brightness;
	ret = rkbd_update(kb);
	/* The LED core does not call deactivate after a failed activate. */
	if (ret)
		kb->effect = NULL;
	return ret;
}

/* The LED core turns the LED off after this, which writes the hardware. */
static void rkbd_trigger_deactivate(struct led_classdev *cdev)
{
	struct rkbd *kb = to_rkbd_led(cdev)->kb;

	guard(mutex)(&kb->lock);
	kb->effect = NULL;
}

static ssize_t speed_show(struct device *dev, struct device_attribute *attr,
			  char *buf)
{
	struct rkbd *kb = to_rkbd_led(led_trigger_get_led(dev))->kb;

	return sysfs_emit(buf, "%u\n", kb->speed);
}

static ssize_t speed_store(struct device *dev, struct device_attribute *attr,
			   const char *buf, size_t count)
{
	struct rkbd *kb = to_rkbd_led(led_trigger_get_led(dev))->kb;
	u8 speed;
	int ret;

	ret = kstrtou8(buf, 10, &speed);
	if (ret)
		return ret;

	guard(mutex)(&kb->lock);
	if (!kb->effect || speed >= kb->effect->speeds)
		return -EINVAL;
	kb->speed = speed;
	ret = rkbd_update(kb);
	return ret ?: count;
}
static DEVICE_ATTR_RW(speed);

static ssize_t direction_show(struct device *dev,
			      struct device_attribute *attr, char *buf)
{
	struct rkbd *kb = to_rkbd_led(led_trigger_get_led(dev))->kb;

	return sysfs_emit(buf, "%s\n", kb->reverse ? "reverse" : "forward");
}

static ssize_t direction_store(struct device *dev,
			       struct device_attribute *attr, const char *buf,
			       size_t count)
{
	struct rkbd *kb = to_rkbd_led(led_trigger_get_led(dev))->kb;
	bool reverse;
	int ret;

	if (sysfs_streq(buf, "forward"))
		reverse = false;
	else if (sysfs_streq(buf, "reverse"))
		reverse = true;
	else
		return -EINVAL;

	guard(mutex)(&kb->lock);
	kb->reverse = reverse;
	ret = rkbd_update(kb);
	return ret ?: count;
}
static DEVICE_ATTR_RW(direction);

static struct attribute *rkbd_speed_attrs[] = {
	&dev_attr_speed.attr,
	NULL
};
ATTRIBUTE_GROUPS(rkbd_speed);

static struct attribute *rkbd_direction_attrs[] = {
	&dev_attr_direction.attr,
	NULL
};
ATTRIBUTE_GROUPS(rkbd_direction);

static struct led_hw_trigger_type rkbd_trigger_type;

#define RKBD_EFFECT(_name, _id, _flags, _speeds) {			\
	.trigger = {							\
		.name = _name,						\
		.activate = rkbd_trigger_activate,			\
		.deactivate = rkbd_trigger_deactivate,			\
		.trigger_type = &rkbd_trigger_type,			\
		.groups = (_flags) & RKBD_EFFECT_DIRECTION ?		\
			  rkbd_direction_groups :			\
			  (_speeds) ? rkbd_speed_groups : NULL,		\
	},								\
	.id = _id,							\
	.flags = _flags,						\
	.speeds = _speeds,						\
}

static struct rkbd_effect rkbd_effects[] = {
	RKBD_EFFECT("breathing", EFFECT_BREATHING, RKBD_EFFECT_SOFT, 0),
	RKBD_EFFECT("spectrum-cycle", EFFECT_SPECTRUM, RKBD_EFFECT_SOFT, 0),
	RKBD_EFFECT("rainbow", EFFECT_WAVE,
		    RKBD_EFFECT_SOFT | RKBD_EFFECT_DIRECTION, 0),
	RKBD_EFFECT("reactive", EFFECT_REACTIVE, 0, 4),
	RKBD_EFFECT("starlight", EFFECT_STARLIGHT, 0, 3),
};

static int rkbd_led_register(struct rkbd *kb, struct rkbd_led *led,
			     const char *function, bool triggers)
{
	struct device *dev = &kb->hdev->dev;
	struct led_classdev *cdev = &led->mc.led_cdev;
	int i, ret;

	led->kb = kb;
	for (i = 0; i < 3; i++) {
		led->subleds[i].channel = i;
		led->subleds[i].intensity = LED_FULL;
	}
	led->subleds[0].color_index = LED_COLOR_ID_RED;
	led->subleds[1].color_index = LED_COLOR_ID_GREEN;
	led->subleds[2].color_index = LED_COLOR_ID_BLUE;
	led->mc.subled_info = led->subleds;
	led->mc.num_colors = 3;

	cdev->name = devm_kasprintf(dev, GFP_KERNEL, "%s:rgb:%s",
				    dev_name(dev), function);
	if (!cdev->name)
		return -ENOMEM;
	cdev->max_brightness = LED_FULL;
	cdev->brightness_set_blocking = rkbd_brightness_set;
	if (triggers)
		cdev->trigger_type = &rkbd_trigger_type;
	cdev->flags = LED_HW_PLUGGABLE | LED_RETAIN_AT_SHUTDOWN;

	ret = led_classdev_multicolor_register(dev, &led->mc);
	if (!ret)
		led->registered = true;
	return ret;
}

static void rkbd_leds_unregister(struct rkbd *kb)
{
	unsigned int i;

	for (i = 0; i < RKBD_KEYS; i++)
		if (kb->keys[i].registered)
			led_classdev_multicolor_unregister(&kb->keys[i].mc);
	if (kb->backlight.registered)
		led_classdev_multicolor_unregister(&kb->backlight.mc);
}

static int rkbd_leds_register(struct rkbd *kb)
{
	unsigned int i;
	char function[32];
	int ret;

	ret = rkbd_led_register(kb, &kb->backlight, "kbd_backlight", true);
	for (i = 0; !ret && i < RKBD_KEYS; i++) {
		snprintf(function, sizeof(function), "key-%s",
			 rkbd_keys[i].name);
		ret = rkbd_led_register(kb, &kb->keys[i], function, false);
	}
	if (ret)
		rkbd_leds_unregister(kb);
	return ret;
}

/* Turns the backlight off and stops all device I/O. */
static void rkbd_release(struct rkbd *kb)
{
	int ret;

	guard(mutex)(&kb->lock);
	if (kb->stopped)
		return;
	kb->stopped = true;
	ret = rkbd_set_brightness(kb, 0);
	if (ret && ret != -ENODEV)
		hid_warn(kb->hdev, "failed to turn the backlight off: %d\n",
			 ret);
}

static bool rkbd_is_control(struct hid_device *hdev)
{
	struct usb_interface *intf;

	if (!hid_is_usb(hdev))
		return false;
	intf = to_usb_interface(hdev->dev.parent);
	return intf->cur_altsetting->desc.bInterfaceNumber ==
	       RKBD_CONTROL_INTERFACE;
}

static int rkbd_probe(struct hid_device *hdev, const struct hid_device_id *id)
{
	struct device *dev = &hdev->dev;
	u8 version[RKBD_ARGS_MAX];
	struct rkbd *kb;
	int ret;

	ret = hid_parse(hdev);
	if (ret)
		return ret;

	if (!rkbd_is_control(hdev))
		return hid_hw_start(hdev, HID_CONNECT_DEFAULT);

	kb = devm_kzalloc(dev, sizeof(*kb), GFP_KERNEL);
	if (!kb)
		return -ENOMEM;

	kb->buf = devm_kzalloc(dev, RKBD_REPORT_SIZE + 1, GFP_KERNEL);
	if (!kb->buf)
		return -ENOMEM;

	ret = devm_mutex_init(dev, &kb->lock);
	if (ret)
		return ret;

	kb->hdev = hdev;
	INIT_DELAYED_WORK(&kb->animate, rkbd_animate_work);
	hid_set_drvdata(hdev, kb);

	/* No hidraw, userspace commands would interleave with the driver's. */
	ret = hid_hw_start(hdev, HID_CONNECT_DEFAULT & ~HID_CONNECT_HIDRAW);
	if (ret)
		goto out_drvdata;

	scoped_guard(mutex, &kb->lock) {
		ret = rkbd_cmd(kb, TID_DEFAULT, CLASS_DEVICE, CMD_FIRMWARE,
			       NULL, 2, version);
		if (!ret)
			rkbd_update(kb);
	}
	if (ret) {
		hid_err(hdev, "setup failed: %d\n", ret);
		goto out_stop;
	}
	hid_info(hdev, "firmware %u.%u\n", version[0], version[1]);

	ret = rkbd_leds_register(kb);
	if (ret)
		goto out_release;
	return 0;

out_release:
	rkbd_release(kb);
	cancel_delayed_work_sync(&kb->animate);
out_stop:
	hid_hw_stop(hdev);
out_drvdata:
	hid_set_drvdata(hdev, NULL);
	return ret;
}

static void rkbd_remove(struct hid_device *hdev)
{
	struct rkbd *kb = hid_get_drvdata(hdev);

	if (kb) {
		rkbd_release(kb);
		cancel_delayed_work_sync(&kb->animate);
		rkbd_leds_unregister(kb);
	}
	hid_hw_stop(hdev);
}

static int __maybe_unused rkbd_suspend(struct hid_device *hdev,
				       pm_message_t message)
{
	struct rkbd *kb = hid_get_drvdata(hdev);

	if (kb) {
		scoped_guard(mutex, &kb->lock)
			kb->suspended = true;
		cancel_delayed_work_sync(&kb->animate);
	}
	return 0;
}

/* A failed write must not fail the resume. */
static int __maybe_unused rkbd_resume(struct hid_device *hdev)
{
	struct rkbd *kb = hid_get_drvdata(hdev);

	if (kb) {
		guard(mutex)(&kb->lock);
		kb->suspended = false;
		if (kb->stopped)
			return 0;
		kb->effect_valid = false;
		kb->custom = false;
		kb->shown_valid = false;
		rkbd_update(kb);
	}
	return 0;
}

static const struct hid_device_id rkbd_table[] = {
	{ HID_USB_DEVICE(0x1532, 0x0221) }, /* BlackWidow Chroma V2 */
	{ }
};
MODULE_DEVICE_TABLE(hid, rkbd_table);

static struct hid_driver rkbd_driver = {
	.name = "razer-kbd",
	.id_table = rkbd_table,
	.probe = rkbd_probe,
	.remove = rkbd_remove,
#ifdef CONFIG_PM
	.suspend = rkbd_suspend,
	.resume = rkbd_resume,
	.reset_resume = rkbd_resume,
#endif
};

static int __init rkbd_init(void)
{
	int i, ret;

	for (i = 0; i < ARRAY_SIZE(rkbd_effects); i++) {
		ret = led_trigger_register(&rkbd_effects[i].trigger);
		if (ret)
			goto err;
	}

	ret = hid_register_driver(&rkbd_driver);
	if (!ret)
		return 0;
err:
	while (i--)
		led_trigger_unregister(&rkbd_effects[i].trigger);
	return ret;
}

static void __exit rkbd_exit(void)
{
	int i;

	hid_unregister_driver(&rkbd_driver);
	for (i = 0; i < ARRAY_SIZE(rkbd_effects); i++)
		led_trigger_unregister(&rkbd_effects[i].trigger);
}

module_init(rkbd_init);
module_exit(rkbd_exit);

MODULE_DESCRIPTION("Razer BlackWidow Chroma V2 backlight driver");
MODULE_LICENSE("GPL");
