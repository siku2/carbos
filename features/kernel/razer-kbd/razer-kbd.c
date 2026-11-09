// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * Razer BlackWidow Chroma V2 (1532:0221).
 *
 * The keyboard takes 90 byte feature reports on interface 1, the layout
 * openrazer documents. The driver keeps it in driver mode, where the
 * keyboard reports M1-M5 and Fn to the host instead of handling them, and
 * implements the Fn layer.
 *
 * Lighting is one LED for the whole backlight plus one LED per key. The
 * whole backlight runs hardware effects. While a key LED is lit, the driver
 * draws the frame itself, with the lit keys on top. Brightness changes are
 * never stored in the keyboard.
 *
 * A virtual HID LampArray device gives the host the keys as lamps. Outside
 * of autonomous mode its colors replace the backlight under the key LEDs.
 */

#include <linux/fixp-arith.h>
#include <linux/hid.h>
#include <linux/input.h>
#include <linux/led-class-multicolor.h>
#include <linux/leds.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/reboot.h>
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
#define RKBD_BRIGHTNESS_STEP 32

enum {
	STATUS_NEW = 0x00,
	STATUS_BUSY = 0x01,
	STATUS_OK = 0x02,
	STATUS_FAILED = 0x03,
	STATUS_TIMEOUT = 0x04,
	STATUS_UNSUPPORTED = 0x05,
};

#define TID_DEFAULT 0xff
#define TID_MATRIX 0x3f

#define CLASS_DEVICE 0x00
#define CMD_DEVICE_MODE 0x04
#define CMD_FIRMWARE 0x81

/* Mode 0x01 is the bootloader, which erases the firmware on entry. */
#define MODE_NORMAL 0x00
#define MODE_DRIVER 0x03

#define CLASS_LED 0x03
#define CMD_BRIGHTNESS 0x03
#define CMD_GET_BRIGHTNESS 0x83
#define CMD_MATRIX_EFFECT 0x0a
#define CMD_MATRIX_ROW 0x0b

#define NOSTORE 0x00
#define VARSTORE 0x01
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

#define REPORT_VENDOR_KEYS 0x04
#define VENDOR_FN 0x01
#define VENDOR_M1 0x20
#define VENDOR_M_KEYS 5

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
	/* HID keyboard usage, 0 for keys outside the keyboard page. */
	u8 usage;
	u32 x;
	u32 y;
	const char *name;
};

#include "layout.h"

#define RKBD_KEYS ARRAY_SIZE(rkbd_keys)

/* Keys with Fn held. Brightness keys have no code, the driver handles them. */
struct rkbd_fn_key {
	u16 code;
	u16 fn_code;
	int brightness;
};

static const struct rkbd_fn_key rkbd_fn_keys[] = {
	{ KEY_F1, KEY_MUTE },
	{ KEY_F2, KEY_VOLUMEDOWN },
	{ KEY_F3, KEY_VOLUMEUP },
	{ KEY_F5, KEY_PREVIOUSSONG },
	{ KEY_F6, KEY_PLAYPAUSE },
	{ KEY_F7, KEY_NEXTSONG },
	{ KEY_F11, 0, -RKBD_BRIGHTNESS_STEP },
	{ KEY_F12, 0, RKBD_BRIGHTNESS_STEP },
	{ KEY_PAUSE, KEY_SLEEP },
};

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
	struct input_dev *input;
	struct notifier_block reboot_nb;
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

	struct hid_device *lamps;
	bool autonomous;
	u16 lamp_cursor;
	/* Updates collect in lamp_next until the host completes them. */
	u8 lamp_next[RKBD_KEYS][3];
	u8 lamp_color[RKBD_KEYS][3];

	/* Input state, only touched from the HID event path. */
	bool fn;
	u8 m_keys;
	unsigned long fn_pressed;
};

/* Sends a command without waiting for it, the next command queues behind it. */
static int rkbd_send(struct rkbd *kb, u8 tid, u8 class, u8 cmd, const u8 *args,
		     u8 len)
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
	return ret < 0 ? ret : 0;
}

static int rkbd_cmd(struct rkbd *kb, u8 tid, u8 class, u8 cmd, const u8 *args,
		    u8 len, u8 *resp)
{
	u8 *report = kb->buf + 1;
	int i, ret;

	ret = rkbd_send(kb, tid, class, cmd, args, len);
	if (ret)
		return ret;

	for (i = 0; i < RKBD_RETRIES; i++) {
		usleep_range(600, 800);
		ret = hid_hw_raw_request(kb->hdev, 0, kb->buf,
					 RKBD_REPORT_SIZE + 1,
					 HID_FEATURE_REPORT, HID_REQ_GET_REPORT);
		if (ret < 0)
			return ret;
		if (report[0] != STATUS_NEW && report[0] != STATUS_BUSY)
			break;
	}

	switch (report[0]) {
	case STATUS_OK:
		break;
	case STATUS_NEW:
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

static int rkbd_set_mode(struct rkbd *kb, u8 mode)
{
	u8 args[] = { mode, 0x00 };

	if (WARN_ON(mode != MODE_NORMAL && mode != MODE_DRIVER))
		return -EINVAL;
	return rkbd_cmd(kb, TID_MATRIX, CLASS_DEVICE, CMD_DEVICE_MODE, args,
			sizeof(args), NULL);
}

static int rkbd_set_brightness(struct rkbd *kb, u8 brightness)
{
	u8 args[] = { NOSTORE, BACKLIGHT_LED, brightness };

	return rkbd_cmd(kb, TID_DEFAULT, CLASS_LED, CMD_BRIGHTNESS, args,
			sizeof(args), NULL);
}

/* Rows only show with the next custom effect command. */
static int rkbd_clear_frame(struct rkbd *kb)
{
	u8 args[4 + RKBD_ROW_SIZE] = { FRAME_ID, 0, 0, RKBD_COLS - 1 };
	int ret;

	for (args[1] = 0; args[1] < RKBD_ROWS; args[1]++) {
		ret = rkbd_send(kb, TID_MATRIX, CLASS_LED, CMD_MATRIX_ROW, args,
				sizeof(args));
		if (ret)
			return ret;
	}
	return 0;
}

/*
 * Writing the last frame row resets the brightness to the stored one, so
 * frames blink unless it is full. The keyboard then flashes white at power-up
 * and goes dark once it loads the stored black frame in custom mode.
 */
static int rkbd_provision(struct rkbd *kb)
{
	u8 query[] = { VARSTORE, BACKLIGHT_LED, 0 };
	u8 store[] = { EFFECT_CUSTOM, VARSTORE };
	u8 full[] = { VARSTORE, BACKLIGHT_LED, LED_FULL };
	u8 resp[RKBD_ARGS_MAX];
	int ret;

	ret = rkbd_cmd(kb, TID_DEFAULT, CLASS_LED, CMD_GET_BRIGHTNESS, query,
		       sizeof(query), resp);
	if (ret || resp[2] == LED_FULL)
		return ret;

	ret = rkbd_clear_frame(kb);
	if (!ret)
		ret = rkbd_cmd(kb, TID_MATRIX, CLASS_LED, CMD_MATRIX_EFFECT,
			       store, sizeof(store), NULL);
	if (!ret)
		ret = rkbd_cmd(kb, TID_DEFAULT, CLASS_LED, CMD_BRIGHTNESS,
			       full, sizeof(full), NULL);
	if (!ret)
		hid_info(kb->hdev, "stored custom mode at full brightness\n");
	return ret;
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
	return kb->drawing && kb->autonomous && kb->backlight.brightness &&
	       kb->effect;
}

static void rkbd_render_effect(struct rkbd *kb)
{
	unsigned int brightness = kb->backlight.brightness;
	unsigned int row, col, hue, level;
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
}

static u8 *rkbd_cell(struct rkbd *kb, unsigned int key)
{
	return kb->frame[rkbd_keys[key].row] + 3 * rkbd_keys[key].col;
}

static void rkbd_render(struct rkbd *kb)
{
	unsigned int i;

	if (kb->autonomous) {
		rkbd_render_effect(kb);
	} else {
		memset(kb->frame, 0, sizeof(kb->frame));
		for (i = 0; i < RKBD_KEYS; i++)
			memcpy(rkbd_cell(kb, i), kb->lamp_color[i], 3);
	}

	for (i = 0; i < RKBD_KEYS; i++) {
		const struct rkbd_led *key = &kb->keys[i];

		if (key->brightness)
			rkbd_led_rgb(key, key->brightness, rkbd_cell(kb, i));
	}
}

static int rkbd_update_frame(struct rkbd *kb)
{
	u8 args[4 + RKBD_ROW_SIZE] = { FRAME_ID };
	u8 show[] = { EFFECT_CUSTOM, NOSTORE };
	bool entering = !kb->custom, changed = false;
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
		ret = rkbd_send(kb, TID_MATRIX, CLASS_LED, CMD_MATRIX_ROW, args,
				sizeof(args));
		if (ret)
			goto err;
		changed = true;
	}

	if (changed) {
		ret = rkbd_cmd(kb, TID_MATRIX, CLASS_LED, CMD_MATRIX_EFFECT,
			       show, sizeof(show), NULL);
		if (ret)
			goto err;
	}

	/* Entering custom mode drops the brightness. The frame carries it. */
	if (entering) {
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
	bool host = !kb->autonomous;
	bool soft = host || !kb->effect || kb->effect->flags & RKBD_EFFECT_SOFT;
	int ret;

	lockdep_assert_held(&kb->lock);

	if (kb->suspended || kb->stopped)
		return 0;

	kb->drawing = soft && (host || rkbd_overlay(kb));
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

static void rkbd_led_unregister(struct rkbd_led *led)
{
	if (led->registered)
		led_classdev_multicolor_unregister(&led->mc);
	led->registered = false;
}

static void rkbd_leds_unregister(struct rkbd *kb)
{
	unsigned int i;

	for (i = 0; i < RKBD_KEYS; i++)
		rkbd_led_unregister(&kb->keys[i]);
	rkbd_led_unregister(&kb->backlight);
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

enum {
	LAMP_ARRAY_ATTRIBUTES = 1,
	LAMP_ATTRIBUTES_REQUEST,
	LAMP_ATTRIBUTES_RESPONSE,
	LAMP_MULTI_UPDATE,
	LAMP_RANGE_UPDATE,
	LAMP_ARRAY_CONTROL,
};

#define LAMP_KIND_KEYBOARD 1
#define LAMP_PURPOSE_CONTROL BIT(0)
#define LAMP_PURPOSE_BRANDING BIT(2)
#define LAMP_UPDATE_COMPLETE BIT(0)
#define LAMP_MULTI_MAX 8

/* A full frame: six rows and the show command, 8 ms per USB transfer. */
#define LAMP_UPDATE_US 64000
#define RKBD_DEPTH 39000

/* The LampArray layout from the HID Usage Tables, 8 lamps per multi update. */
static const u8 rkbd_lamps_desc[] = {
	0x05, 0x59,			/* Usage Page (Lighting and Illumination) */
	0x09, 0x01,			/* Usage (LampArray) */
	0xa1, 0x01,			/* Collection (Application) */
	0x85, LAMP_ARRAY_ATTRIBUTES,	/*  Report ID */
	0x09, 0x02,			/*  Usage (LampArrayAttributesReport) */
	0xa1, 0x02,			/*  Collection (Logical) */
	0x09, 0x03,			/*   Usage (LampCount) */
	0x15, 0x00,			/*   Logical Minimum (0) */
	0x27, 0xff, 0xff, 0x00, 0x00,	/*   Logical Maximum (65535) */
	0x75, 0x10,			/*   Report Size (16) */
	0x95, 0x01,			/*   Report Count (1) */
	0xb1, 0x03,			/*   Feature (Cnst,Var,Abs) */
	0x09, 0x04,			/*   Usage (BoundingBoxWidthInMicrometers) */
	0x09, 0x05,			/*   Usage (BoundingBoxHeightInMicrometers) */
	0x09, 0x06,			/*   Usage (BoundingBoxDepthInMicrometers) */
	0x09, 0x07,			/*   Usage (LampArrayKind) */
	0x09, 0x08,			/*   Usage (MinUpdateIntervalInMicroseconds) */
	0x15, 0x00,			/*   Logical Minimum (0) */
	0x27, 0xff, 0xff, 0xff, 0x7f,	/*   Logical Maximum (2147483647) */
	0x75, 0x20,			/*   Report Size (32) */
	0x95, 0x05,			/*   Report Count (5) */
	0xb1, 0x03,			/*   Feature (Cnst,Var,Abs) */
	0xc0,				/*  End Collection */
	0x85, LAMP_ATTRIBUTES_REQUEST,	/*  Report ID */
	0x09, 0x20,			/*  Usage (LampAttributesRequestReport) */
	0xa1, 0x02,			/*  Collection (Logical) */
	0x09, 0x21,			/*   Usage (LampId) */
	0x15, 0x00,			/*   Logical Minimum (0) */
	0x27, 0xff, 0xff, 0x00, 0x00,	/*   Logical Maximum (65535) */
	0x75, 0x10,			/*   Report Size (16) */
	0x95, 0x01,			/*   Report Count (1) */
	0xb1, 0x02,			/*   Feature (Data,Var,Abs) */
	0xc0,				/*  End Collection */
	0x85, LAMP_ATTRIBUTES_RESPONSE,	/*  Report ID */
	0x09, 0x22,			/*  Usage (LampAttributesResponseReport) */
	0xa1, 0x02,			/*  Collection (Logical) */
	0x09, 0x21,			/*   Usage (LampId) */
	0x15, 0x00,			/*   Logical Minimum (0) */
	0x27, 0xff, 0xff, 0x00, 0x00,	/*   Logical Maximum (65535) */
	0x75, 0x10,			/*   Report Size (16) */
	0x95, 0x01,			/*   Report Count (1) */
	0xb1, 0x02,			/*   Feature (Data,Var,Abs) */
	0x09, 0x23,			/*   Usage (PositionXInMicrometers) */
	0x09, 0x24,			/*   Usage (PositionYInMicrometers) */
	0x09, 0x25,			/*   Usage (PositionZInMicrometers) */
	0x09, 0x27,			/*   Usage (UpdateLatencyInMicroseconds) */
	0x09, 0x26,			/*   Usage (LampPurposes) */
	0x15, 0x00,			/*   Logical Minimum (0) */
	0x27, 0xff, 0xff, 0xff, 0x7f,	/*   Logical Maximum (2147483647) */
	0x75, 0x20,			/*   Report Size (32) */
	0x95, 0x05,			/*   Report Count (5) */
	0xb1, 0x02,			/*   Feature (Data,Var,Abs) */
	0x09, 0x28,			/*   Usage (RedLevelCount) */
	0x09, 0x29,			/*   Usage (GreenLevelCount) */
	0x09, 0x2a,			/*   Usage (BlueLevelCount) */
	0x09, 0x2b,			/*   Usage (IntensityLevelCount) */
	0x09, 0x2c,			/*   Usage (IsProgrammable) */
	0x09, 0x2d,			/*   Usage (InputBinding) */
	0x15, 0x00,			/*   Logical Minimum (0) */
	0x26, 0xff, 0x00,		/*   Logical Maximum (255) */
	0x75, 0x08,			/*   Report Size (8) */
	0x95, 0x06,			/*   Report Count (6) */
	0xb1, 0x02,			/*   Feature (Data,Var,Abs) */
	0xc0,				/*  End Collection */
	0x85, LAMP_MULTI_UPDATE,	/*  Report ID */
	0x09, 0x50,			/*  Usage (LampMultiUpdateReport) */
	0xa1, 0x02,			/*  Collection (Logical) */
	0x09, 0x03,			/*   Usage (LampCount) */
	0x09, 0x55,			/*   Usage (LampUpdateFlags) */
	0x15, 0x00,			/*   Logical Minimum (0) */
	0x25, 0x08,			/*   Logical Maximum (8) */
	0x75, 0x08,			/*   Report Size (8) */
	0x95, 0x02,			/*   Report Count (2) */
	0xb1, 0x02,			/*   Feature (Data,Var,Abs) */
	0x09, 0x21,			/*   Usage (LampId) */
	0x15, 0x00,			/*   Logical Minimum (0) */
	0x27, 0xff, 0xff, 0x00, 0x00,	/*   Logical Maximum (65535) */
	0x75, 0x10,			/*   Report Size (16) */
	0x95, LAMP_MULTI_MAX,		/*   Report Count (8) */
	0xb1, 0x02,			/*   Feature (Data,Var,Abs) */
	0x09, 0x51, 0x09, 0x52, 0x09, 0x53, 0x09, 0x54, /*   Usage (Red..IntensityUpdateChannel) */
	0x09, 0x51, 0x09, 0x52, 0x09, 0x53, 0x09, 0x54,
	0x09, 0x51, 0x09, 0x52, 0x09, 0x53, 0x09, 0x54,
	0x09, 0x51, 0x09, 0x52, 0x09, 0x53, 0x09, 0x54,
	0x09, 0x51, 0x09, 0x52, 0x09, 0x53, 0x09, 0x54,
	0x09, 0x51, 0x09, 0x52, 0x09, 0x53, 0x09, 0x54,
	0x09, 0x51, 0x09, 0x52, 0x09, 0x53, 0x09, 0x54,
	0x09, 0x51, 0x09, 0x52, 0x09, 0x53, 0x09, 0x54,
	0x15, 0x00,			/*   Logical Minimum (0) */
	0x26, 0xff, 0x00,		/*   Logical Maximum (255) */
	0x75, 0x08,			/*   Report Size (8) */
	0x95, 4 * LAMP_MULTI_MAX,	/*   Report Count (32) */
	0xb1, 0x02,			/*   Feature (Data,Var,Abs) */
	0xc0,				/*  End Collection */
	0x85, LAMP_RANGE_UPDATE,	/*  Report ID */
	0x09, 0x60,			/*  Usage (LampRangeUpdateReport) */
	0xa1, 0x02,			/*  Collection (Logical) */
	0x09, 0x55,			/*   Usage (LampUpdateFlags) */
	0x15, 0x00,			/*   Logical Minimum (0) */
	0x25, 0x08,			/*   Logical Maximum (8) */
	0x75, 0x08,			/*   Report Size (8) */
	0x95, 0x01,			/*   Report Count (1) */
	0xb1, 0x02,			/*   Feature (Data,Var,Abs) */
	0x09, 0x61,			/*   Usage (LampIdStart) */
	0x09, 0x62,			/*   Usage (LampIdEnd) */
	0x15, 0x00,			/*   Logical Minimum (0) */
	0x27, 0xff, 0xff, 0x00, 0x00,	/*   Logical Maximum (65535) */
	0x75, 0x10,			/*   Report Size (16) */
	0x95, 0x02,			/*   Report Count (2) */
	0xb1, 0x02,			/*   Feature (Data,Var,Abs) */
	0x09, 0x51, 0x09, 0x52, 0x09, 0x53, 0x09, 0x54, /*   Usage (Red..IntensityUpdateChannel) */
	0x15, 0x00,			/*   Logical Minimum (0) */
	0x26, 0xff, 0x00,		/*   Logical Maximum (255) */
	0x75, 0x08,			/*   Report Size (8) */
	0x95, 0x04,			/*   Report Count (4) */
	0xb1, 0x02,			/*   Feature (Data,Var,Abs) */
	0xc0,				/*  End Collection */
	0x85, LAMP_ARRAY_CONTROL,	/*  Report ID */
	0x09, 0x70,			/*  Usage (LampArrayControlReport) */
	0xa1, 0x02,			/*  Collection (Logical) */
	0x09, 0x71,			/*   Usage (AutonomousMode) */
	0x15, 0x00,			/*   Logical Minimum (0) */
	0x25, 0x01,			/*   Logical Maximum (1) */
	0x75, 0x08,			/*   Report Size (8) */
	0x95, 0x01,			/*   Report Count (1) */
	0xb1, 0x02,			/*   Feature (Data,Var,Abs) */
	0xc0,				/*  End Collection */
	0xc0,				/* End Collection */
};

struct lamp_array_attributes {
	u8 id;
	__le16 count;
	__le32 width;
	__le32 height;
	__le32 depth;
	__le32 kind;
	__le32 min_interval;
} __packed;

struct lamp_attributes_request {
	u8 id;
	__le16 lamp;
} __packed;

struct lamp_attributes_response {
	u8 id;
	__le16 lamp;
	__le32 x;
	__le32 y;
	__le32 z;
	__le32 latency;
	__le32 purposes;
	u8 red_levels;
	u8 green_levels;
	u8 blue_levels;
	u8 intensity_levels;
	u8 programmable;
	u8 input_binding;
} __packed;

struct lamp_rgbi {
	u8 rgb[3];
	u8 intensity;
} __packed;

struct lamp_multi_update {
	u8 id;
	u8 count;
	u8 flags;
	__le16 lamps[LAMP_MULTI_MAX];
	struct lamp_rgbi colors[LAMP_MULTI_MAX];
} __packed;

struct lamp_range_update {
	u8 id;
	u8 flags;
	__le16 start;
	__le16 end;
	struct lamp_rgbi color;
} __packed;

struct lamp_array_control {
	u8 id;
	u8 autonomous;
} __packed;

static struct rkbd *rkbd_lamps_kb(struct hid_device *lamps)
{
	return hid_get_drvdata(to_hid_device(lamps->dev.parent));
}

static int rkbd_lamps_attributes(struct lamp_array_attributes *rep)
{
	rep->count = cpu_to_le16(RKBD_KEYS);
	rep->width = cpu_to_le32(RKBD_WIDTH);
	rep->height = cpu_to_le32(RKBD_HEIGHT);
	rep->depth = cpu_to_le32(RKBD_DEPTH);
	rep->kind = cpu_to_le32(LAMP_KIND_KEYBOARD);
	rep->min_interval = cpu_to_le32(LAMP_UPDATE_US);
	return sizeof(*rep);
}

static int rkbd_lamps_response(struct rkbd *kb,
			       struct lamp_attributes_response *rep)
{
	const struct rkbd_key *key = &rkbd_keys[kb->lamp_cursor];

	memset(rep, 0, sizeof(*rep));
	rep->lamp = cpu_to_le16(kb->lamp_cursor);
	rep->x = cpu_to_le32(key->x);
	rep->y = cpu_to_le32(key->y);
	rep->latency = cpu_to_le32(LAMP_UPDATE_US);
	rep->purposes = cpu_to_le32(strcmp(key->name, "logo") ?
				    LAMP_PURPOSE_CONTROL :
				    LAMP_PURPOSE_BRANDING);
	rep->red_levels = 255;
	rep->green_levels = 255;
	rep->blue_levels = 255;
	rep->intensity_levels = 1;
	rep->programmable = 1;
	rep->input_binding = key->usage;
	kb->lamp_cursor = (kb->lamp_cursor + 1) % RKBD_KEYS;
	return sizeof(*rep);
}

static void rkbd_lamps_stage(struct rkbd *kb, u16 lamp,
			     const struct lamp_rgbi *color)
{
	int i;

	/* One intensity level, color carries the brightness. */
	for (i = 0; i < 3; i++)
		kb->lamp_next[lamp][i] = color->intensity ? color->rgb[i] : 0;
}

static int rkbd_lamps_commit(struct rkbd *kb, u8 flags)
{
	if (!(flags & LAMP_UPDATE_COMPLETE))
		return 0;
	memcpy(kb->lamp_color, kb->lamp_next, sizeof(kb->lamp_color));
	return kb->autonomous ? 0 : rkbd_update(kb);
}

/* The spec drops reports with lamps out of range without an error. */
static int rkbd_lamps_multi(struct rkbd *kb,
			    const struct lamp_multi_update *rep)
{
	unsigned int i;

	if (rep->count > LAMP_MULTI_MAX)
		return 0;
	for (i = 0; i < rep->count; i++)
		if (le16_to_cpu(rep->lamps[i]) >= RKBD_KEYS)
			return 0;
	for (i = 0; i < rep->count; i++)
		rkbd_lamps_stage(kb, le16_to_cpu(rep->lamps[i]),
				 &rep->colors[i]);
	return rkbd_lamps_commit(kb, rep->flags);
}

static int rkbd_lamps_range(struct rkbd *kb,
			    const struct lamp_range_update *rep)
{
	u16 start = le16_to_cpu(rep->start), end = le16_to_cpu(rep->end);
	unsigned int i;

	if (start > end || end >= RKBD_KEYS)
		return 0;
	for (i = start; i <= end; i++)
		rkbd_lamps_stage(kb, i, &rep->color);
	return rkbd_lamps_commit(kb, rep->flags);
}

static int rkbd_lamps_autonomous(struct rkbd *kb, bool autonomous)
{
	if (autonomous == kb->autonomous)
		return 0;
	kb->autonomous = autonomous;
	/* The host starts from dark lamps. */
	memset(kb->lamp_next, 0, sizeof(kb->lamp_next));
	memset(kb->lamp_color, 0, sizeof(kb->lamp_color));
	return rkbd_update(kb);
}

static int rkbd_lamps_get(struct rkbd *kb, u8 id, u8 *buf, size_t len)
{
	switch (id) {
	case LAMP_ARRAY_ATTRIBUTES:
		if (len < sizeof(struct lamp_array_attributes))
			return -EINVAL;
		return rkbd_lamps_attributes((void *)buf);
	case LAMP_ATTRIBUTES_RESPONSE:
		if (len < sizeof(struct lamp_attributes_response))
			return -EINVAL;
		return rkbd_lamps_response(kb, (void *)buf);
	default:
		return -EINVAL;
	}
}

static int rkbd_lamps_set(struct rkbd *kb, u8 id, const u8 *buf, size_t len)
{
	const struct lamp_attributes_request *request = (const void *)buf;
	const struct lamp_multi_update *multi = (const void *)buf;
	const struct lamp_range_update *range = (const void *)buf;
	const struct lamp_array_control *control = (const void *)buf;
	int ret;

	switch (id) {
	case LAMP_ATTRIBUTES_REQUEST:
		if (len < sizeof(*request))
			return -EINVAL;
		kb->lamp_cursor = le16_to_cpu(request->lamp);
		if (kb->lamp_cursor >= RKBD_KEYS)
			kb->lamp_cursor = 0;
		return sizeof(*request);
	case LAMP_MULTI_UPDATE:
		if (len < sizeof(*multi))
			return -EINVAL;
		ret = rkbd_lamps_multi(kb, multi);
		return ret ?: sizeof(*multi);
	case LAMP_RANGE_UPDATE:
		if (len < sizeof(*range))
			return -EINVAL;
		ret = rkbd_lamps_range(kb, range);
		return ret ?: sizeof(*range);
	case LAMP_ARRAY_CONTROL:
		if (len < sizeof(*control))
			return -EINVAL;
		ret = rkbd_lamps_autonomous(kb, control->autonomous);
		return ret ?: sizeof(*control);
	default:
		return -EINVAL;
	}
}

static int rkbd_lamps_raw_request(struct hid_device *lamps, u8 id, u8 *buf,
				  size_t len, unsigned char type, int request)
{
	struct rkbd *kb = rkbd_lamps_kb(lamps);
	int ret;

	if (type != HID_FEATURE_REPORT || !len)
		return -EINVAL;

	guard(mutex)(&kb->lock);
	if (request == HID_REQ_GET_REPORT)
		ret = rkbd_lamps_get(kb, id, buf, len);
	else if (request == HID_REQ_SET_REPORT)
		ret = rkbd_lamps_set(kb, id, buf, len);
	else
		ret = -EINVAL;
	if (ret > 0)
		buf[0] = id;
	return ret;
}

static int rkbd_lamps_parse(struct hid_device *lamps)
{
	return hid_parse_report(lamps, rkbd_lamps_desc,
				sizeof(rkbd_lamps_desc));
}

static int rkbd_lamps_start(struct hid_device *lamps)
{
	return 0;
}

static void rkbd_lamps_stop(struct hid_device *lamps)
{
}

static int rkbd_lamps_open(struct hid_device *lamps)
{
	return 0;
}

/* A host that goes away hands the lamps back. */
static void rkbd_lamps_close(struct hid_device *lamps)
{
	struct rkbd *kb = rkbd_lamps_kb(lamps);

	guard(mutex)(&kb->lock);
	rkbd_lamps_autonomous(kb, true);
}

static const struct hid_ll_driver rkbd_lamps_driver = {
	.parse = rkbd_lamps_parse,
	.start = rkbd_lamps_start,
	.stop = rkbd_lamps_stop,
	.open = rkbd_lamps_open,
	.close = rkbd_lamps_close,
	.raw_request = rkbd_lamps_raw_request,
};

static int rkbd_lamps_add(struct rkbd *kb)
{
	struct hid_device *lamps;
	int ret;

	lamps = hid_allocate_device();
	if (IS_ERR(lamps))
		return PTR_ERR(lamps);

	lamps->ll_driver = &rkbd_lamps_driver;
	lamps->dev.parent = &kb->hdev->dev;
	lamps->bus = BUS_VIRTUAL;
	lamps->vendor = kb->hdev->vendor;
	lamps->product = kb->hdev->product;
	lamps->version = kb->hdev->version;
	snprintf(lamps->name, sizeof(lamps->name), "%s LampArray",
		 kb->hdev->name);
	strscpy(lamps->uniq, kb->hdev->uniq, sizeof(lamps->uniq));

	ret = hid_add_device(lamps);
	if (ret) {
		hid_destroy_device(lamps);
		return ret;
	}
	kb->lamps = lamps;
	return 0;
}

/* Hands the keyboard back with the backlight off and Fn in its firmware. */
static void rkbd_release(struct rkbd *kb)
{
	int ret;

	guard(mutex)(&kb->lock);
	if (kb->stopped)
		return;
	kb->stopped = true;
	ret = rkbd_set_brightness(kb, 0);
	if (!ret)
		ret = rkbd_set_mode(kb, MODE_NORMAL);
	if (ret && ret != -ENODEV)
		hid_warn(kb->hdev, "failed to hand back the keyboard: %d\n",
			 ret);
}

static int rkbd_reboot_notify(struct notifier_block *nb, unsigned long action,
			      void *data)
{
	struct rkbd *kb = container_of(nb, struct rkbd, reboot_nb);

	/* The firmware setup and the boot menu only read keys in normal mode. */
	rkbd_release(kb);
	cancel_delayed_work_sync(&kb->animate);
	return NOTIFY_DONE;
}

/*
 * Events can queue LED work through the Fn keys, so they stop before the
 * LEDs go.
 */
static void rkbd_teardown(struct rkbd *kb)
{
	if (kb->lamps)
		hid_destroy_device(kb->lamps);
	rkbd_release(kb);
	hid_hw_stop(kb->hdev);
	cancel_delayed_work_sync(&kb->animate);
	rkbd_leds_unregister(kb);
}

static const struct rkbd_fn_key *rkbd_fn_key(u16 code, unsigned int *index)
{
	unsigned int i;

	for (i = 0; i < ARRAY_SIZE(rkbd_fn_keys); i++) {
		if (rkbd_fn_keys[i].code == code) {
			*index = i;
			return &rkbd_fn_keys[i];
		}
	}
	return NULL;
}

static void rkbd_step_brightness(struct rkbd *kb, int step)
{
	struct led_classdev *cdev = &kb->backlight.mc.led_cdev;
	int brightness = clamp_t(int, cdev->brightness + step, 0, LED_FULL);

	/* Safe here, the LED core defers the blocking write to a worker. */
	led_set_brightness(cdev, brightness);
}

static int rkbd_event(struct hid_device *hdev, struct hid_field *field,
		      struct hid_usage *usage, __s32 value)
{
	struct rkbd *kb = hid_get_drvdata(hdev);
	const struct rkbd_fn_key *key;
	unsigned int index;

	if (!kb || usage->type != EV_KEY)
		return 0;

	key = rkbd_fn_key(usage->code, &index);
	if (!key)
		return 0;

	/* A key pressed with Fn is released as the Fn key, even without Fn. */
	if (value) {
		if (!kb->fn)
			return 0;
		set_bit(index, &kb->fn_pressed);
	} else if (!test_and_clear_bit(index, &kb->fn_pressed)) {
		return 0;
	}

	if (key->fn_code)
		input_event(field->hidinput->input, EV_KEY, key->fn_code,
			    value);
	else if (value == 1)
		rkbd_step_brightness(kb, key->brightness);
	return 1;
}

static int rkbd_raw_event(struct hid_device *hdev, struct hid_report *report,
			  u8 *data, int size)
{
	struct rkbd *kb = hid_get_drvdata(hdev);
	u8 m_keys = 0, changed;
	bool fn = false;
	int i;

	if (!kb || size < 2 || data[0] != REPORT_VENDOR_KEYS)
		return 0;

	for (i = 1; i < size; i++) {
		if (data[i] == VENDOR_FN)
			fn = true;
		else if (data[i] >= VENDOR_M1 &&
			 data[i] < VENDOR_M1 + VENDOR_M_KEYS)
			m_keys |= BIT(data[i] - VENDOR_M1);
	}
	kb->fn = fn;

	changed = m_keys ^ kb->m_keys;
	kb->m_keys = m_keys;
	if (kb->input && changed) {
		for (i = 0; i < VENDOR_M_KEYS; i++)
			if (changed & BIT(i))
				input_report_key(kb->input, KEY_MACRO1 + i,
						 m_keys & BIT(i));
		input_sync(kb->input);
	}
	return 1;
}

static int rkbd_input_configured(struct hid_device *hdev, struct hid_input *hi)
{
	struct rkbd *kb = hid_get_drvdata(hdev);
	unsigned int i;

	if (!kb || kb->input)
		return 0;

	kb->input = hi->input;
	__set_bit(EV_KEY, hi->input->evbit);
	for (i = 0; i < VENDOR_M_KEYS; i++)
		__set_bit(KEY_MACRO1 + i, hi->input->keybit);
	for (i = 0; i < ARRAY_SIZE(rkbd_fn_keys); i++)
		if (rkbd_fn_keys[i].fn_code)
			__set_bit(rkbd_fn_keys[i].fn_code, hi->input->keybit);
	return 0;
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
	kb->autonomous = true;
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
			ret = rkbd_provision(kb);
		if (!ret)
			ret = rkbd_set_mode(kb, MODE_DRIVER);
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
		goto out_teardown;

	kb->reboot_nb.notifier_call = rkbd_reboot_notify;
	ret = register_reboot_notifier(&kb->reboot_nb);
	if (ret)
		goto out_teardown;

	ret = rkbd_lamps_add(kb);
	if (ret)
		hid_warn(hdev, "no LampArray device: %d\n", ret);
	return 0;

out_teardown:
	rkbd_teardown(kb);
	goto out_drvdata;
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
		unregister_reboot_notifier(&kb->reboot_nb);
		rkbd_teardown(kb);
	} else {
		hid_hw_stop(hdev);
	}
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
		/* A reset puts the keyboard back in normal mode. */
		if (rkbd_set_mode(kb, MODE_DRIVER))
			hid_warn(hdev, "failed to enter driver mode\n");
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
	.event = rkbd_event,
	.raw_event = rkbd_raw_event,
	.input_configured = rkbd_input_configured,
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

MODULE_DESCRIPTION("Razer BlackWidow Chroma V2 driver");
MODULE_LICENSE("GPL");
