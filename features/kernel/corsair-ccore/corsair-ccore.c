// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * Corsair iCUE Commander Core (1b1c:0c32), the controller of the iCUE ELITE
 * CAPELLIX AIO coolers.
 *
 * The device speaks Corsair's Bragi protocol, a file system over HID. In SELF
 * mode it runs a stored cooling configuration and a rainbow. In HOST mode the
 * host owns the pump, the fans and the LEDs. A firmware watchdog returns the
 * device to SELF after about 30 s without traffic.
 *
 * The driver keeps the device in HOST while bound and runs the stored cooling
 * configuration itself, so the defaults match SELF. It never writes device
 * storage.
 */

#include <linux/completion.h>
#include <linux/hid.h>
#include <linux/hwmon.h>
#include <linux/hwmon-sysfs.h>
#include <linux/led-class-multicolor.h>
#include <linux/leds.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/spinlock.h>
#include <linux/unaligned.h>
#include <linux/workqueue.h>

#define CCORE_USAGE_COMMANDS 0xff420001

#define CCORE_REPORT_SIZE 64
#define CCORE_ARGS_MAX (CCORE_REPORT_SIZE - 2)
#define CCORE_DATA_OFFSET 3
#define CCORE_READ_CHUNK (CCORE_REPORT_SIZE - CCORE_DATA_OFFSET)
#define CCORE_WRITE_FIRST_CHUNK (CCORE_ARGS_MAX - 5)
#define CCORE_WRITE_CHUNK (CCORE_ARGS_MAX - 1)

#define CCORE_TIMEOUT_MS 500
#define CCORE_TICK_MS 1000
#define CCORE_FRAME_MS 40
#define CCORE_TEMP_ERRORS_MAX 3

#define CCORE_CHANNELS 7
#define CCORE_CURVE_POINTS 7
#define CCORE_PORT_LEDS 34
#define CCORE_MAX_LEDS 238

enum {
	CMD_SET_PROPERTY = 0x01,
	CMD_GET_PROPERTY = 0x02,
	CMD_UNBIND = 0x05,
	CMD_WRITE = 0x06,
	CMD_WRITE_CONT = 0x07,
	CMD_READ = 0x08,
	CMD_OPEN = 0x0d,
};

enum {
	STATUS_INVALID_STATE = 0x03,
	STATUS_INVALID_ADDRESS = 0x06,
};

#define PROP_MODE 0x03
#define MODE_SELF 1
#define MODE_HOST 2

/* Files, not to be confused with the buffers they are opened in. */
enum {
	FILE_RPM = 0x17,
	FILE_DUTY = 0x18,
	FILE_FAN_STATUS = 0x1a,
	FILE_LED_COUNT = 0x20,
	FILE_TEMP = 0x21,
	FILE_COLORS = 0x22,
	FILE_FIXED_DUTY = 28001,
	FILE_CURVES = 28002,
};

#define BUF_COLORS 0
#define BUF_DATA 1

#define FAN_ABSENT 0x01
#define LED_PORT_CONNECTED 0x02

#define FIXED_DUTY_SIZE (3 + 2 * CCORE_CHANNELS)
#define CURVE_SIZE (2 + 4 * CCORE_CURVE_POINTS)
#define CURVES_SIZE (3 + CURVE_SIZE * CCORE_CHANNELS)

#define RAINBOW_HUE_MAX 1536
#define RAINBOW_SPEEDS 5
#define RAINBOW_SPEED_DEFAULT 2

static const u16 rainbow_step[RAINBOW_SPEEDS] = { 4, 8, 16, 24, 36 };

static unsigned short pump_min = 50;
module_param(pump_min, ushort, 0444);
MODULE_PARM_DESC(pump_min, "Minimum pump duty in percent, 50 to 100");

static const char *const fan_labels[CCORE_CHANNELS] = {
	"Pump", "Fan 1", "Fan 2", "Fan 3", "Fan 4", "Fan 5", "Fan 6",
};

struct ccore_point {
	long temp;
	u8 pwm;
};

struct ccore_channel {
	/* 1 manual, 2 curve */
	u8 enable;
	u8 pwm;
	struct ccore_point points[CCORE_CURVE_POINTS];
	/* Last duty sent in percent, 0xff if unknown. */
	u8 sent;
};

struct ccore;

struct ccore_led {
	struct ccore *cc;
	struct led_classdev_mc mc;
	struct mc_subled subleds[3];
	u16 first;
	u16 count;
	bool rainbow;
	u8 speed;
	bool reverse;
	unsigned int phase;
	bool registered;
};

struct ccore {
	struct hid_device *hdev;
	struct device *hwmon;

	/* Serializes device I/O and all state below. */
	struct mutex lock;
	struct delayed_work tick;
	struct delayed_work animate;
	bool removing;
	bool host;
	bool colors_open;

	/* Reply matching, protected by rx_lock. */
	spinlock_t rx_lock;
	struct completion rx_done;
	bool rx_pending;
	u8 rx_cmd;
	u8 rx[CCORE_REPORT_SIZE];
	u8 *tx;

	u8 fan_status[CCORE_CHANNELS];
	u16 rpm[CCORE_CHANNELS];
	long temp;
	unsigned int temp_errors;
	struct ccore_channel channels[CCORE_CHANNELS];

	struct ccore_led leds[CCORE_CHANNELS];
	u16 led_total;
	bool frame_sent;
	u8 frame[2 + 3 * CCORE_MAX_LEDS];
	u8 last_frame[2 + 3 * CCORE_MAX_LEDS];
};

static int ccore_xfer(struct ccore *cc, u8 cmd, const u8 *args, size_t len,
		      u8 *resp)
{
	unsigned long flags;
	int ret;

	lockdep_assert_held(&cc->lock);

	if (len > CCORE_ARGS_MAX)
		return -EINVAL;

	memset(cc->tx, 0, CCORE_REPORT_SIZE + 1);
	cc->tx[1] = 0x08;
	cc->tx[2] = cmd;
	memcpy(cc->tx + 3, args, len);

	reinit_completion(&cc->rx_done);
	spin_lock_irqsave(&cc->rx_lock, flags);
	cc->rx_cmd = cmd;
	cc->rx_pending = true;
	spin_unlock_irqrestore(&cc->rx_lock, flags);

	ret = hid_hw_output_report(cc->hdev, cc->tx, CCORE_REPORT_SIZE + 1);
	if (ret < 0)
		goto out;

	if (!wait_for_completion_timeout(&cc->rx_done,
					 msecs_to_jiffies(CCORE_TIMEOUT_MS))) {
		ret = -ETIMEDOUT;
		goto out;
	}

	if (resp)
		memcpy(resp, cc->rx, CCORE_REPORT_SIZE);
	/* A positive return value is the device status. */
	ret = cc->rx[2];

out:
	spin_lock_irqsave(&cc->rx_lock, flags);
	cc->rx_pending = false;
	spin_unlock_irqrestore(&cc->rx_lock, flags);
	return ret;
}

static int ccore_set_mode(struct ccore *cc, u8 mode)
{
	u8 args[] = { PROP_MODE, 0x00, mode };

	return ccore_xfer(cc, CMD_SET_PROPERTY, args, sizeof(args), NULL);
}

static int ccore_unbind(struct ccore *cc, u8 buf)
{
	u8 args[] = { buf, 0x01 };

	return ccore_xfer(cc, CMD_UNBIND, args, sizeof(args), NULL);
}

static int ccore_open(struct ccore *cc, u8 buf, u16 file)
{
	u8 args[] = { buf, file & 0xff, file >> 8 };

	ccore_unbind(cc, buf);
	return ccore_xfer(cc, CMD_OPEN, args, sizeof(args), NULL);
}

static int ccore_write_stream(struct ccore *cc, u8 buf, const u8 *data,
			      size_t len)
{
	u8 args[CCORE_ARGS_MAX];
	size_t off, n;
	int ret;

	n = min_t(size_t, len, CCORE_WRITE_FIRST_CHUNK);
	args[0] = buf;
	put_unaligned_le32(len, args + 1);
	memcpy(args + 5, data, n);
	ret = ccore_xfer(cc, CMD_WRITE, args, 5 + n, NULL);

	for (off = n; !ret && off < len; off += n) {
		n = min_t(size_t, len - off, CCORE_WRITE_CHUNK);
		args[0] = buf;
		memcpy(args + 1, data + off, n);
		ret = ccore_xfer(cc, CMD_WRITE_CONT, args, 1 + n, NULL);
	}
	return ret;
}

/* Reads the start of a file into out, which holds at least size bytes. */
static int ccore_read_file(struct ccore *cc, u16 file, u8 *out, size_t size)
{
	u8 buf = BUF_DATA, resp[CCORE_REPORT_SIZE];
	size_t off, n;
	int ret;

	ret = ccore_open(cc, buf, file);
	for (off = 0; !ret && off < size; off += n) {
		ret = ccore_xfer(cc, CMD_READ, &buf, 1, resp);
		n = min_t(size_t, size - off, CCORE_READ_CHUNK);
		memcpy(out + off, resp + CCORE_DATA_OFFSET, n);
	}
	ccore_unbind(cc, buf);
	return ret;
}

static int ccore_write_file(struct ccore *cc, u16 file, const u8 *data,
			    size_t len)
{
	int ret;

	ret = ccore_open(cc, BUF_DATA, file);
	if (!ret)
		ret = ccore_write_stream(cc, BUF_DATA, data, len);
	ccore_unbind(cc, BUF_DATA);
	return ret;
}

/* Live files start with a 2 byte type and a 1 byte count. */
static const u8 *ccore_items(const u8 *data, u8 *count)
{
	*count = min_t(u8, data[2], CCORE_CHANNELS);
	return data + 3;
}

static void ccore_hue_to_rgb(unsigned int hue, unsigned int brightness,
			     u8 *rgb)
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

static void ccore_render(struct ccore *cc)
{
	u8 *rgb = cc->frame + 2;
	unsigned int i, j, hue;

	cc->frame[0] = 0x12;
	cc->frame[1] = 0x00;
	memset(rgb, 0, 3 * cc->led_total);

	for (i = 0; i < CCORE_CHANNELS; i++) {
		struct ccore_led *led = &cc->leds[i];
		unsigned int brightness = led->mc.led_cdev.brightness;
		u8 *p = rgb + 3 * led->first;

		if (!led->registered || !brightness)
			continue;

		if (!led->rainbow) {
			led_mc_calc_color_components(&led->mc, brightness);
			for (j = 0; j < led->count; j++, p += 3) {
				p[0] = led->subleds[0].brightness;
				p[1] = led->subleds[1].brightness;
				p[2] = led->subleds[2].brightness;
			}
			continue;
		}

		for (j = 0; j < led->count; j++, p += 3) {
			hue = led->phase + j * RAINBOW_HUE_MAX / led->count;
			ccore_hue_to_rgb(hue % RAINBOW_HUE_MAX, brightness, p);
		}
	}
}

static void ccore_lost_host(struct ccore *cc)
{
	cc->host = false;
	cc->colors_open = false;
}

static int ccore_write_frame(struct ccore *cc, bool force)
{
	size_t len = 2 + 3 * cc->led_total;
	int ret;

	lockdep_assert_held(&cc->lock);

	if (!cc->host || !cc->led_total)
		return 0;

	ccore_render(cc);
	if (!force && cc->frame_sent && !memcmp(cc->frame, cc->last_frame, len))
		return 0;

	if (!cc->colors_open) {
		ret = ccore_open(cc, BUF_COLORS, FILE_COLORS);
		if (ret)
			goto err;
		cc->colors_open = true;
	}

	ret = ccore_write_stream(cc, BUF_COLORS, cc->frame, len);
	if (ret)
		goto err;

	memcpy(cc->last_frame, cc->frame, len);
	cc->frame_sent = true;
	return 0;

err:
	cc->colors_open = false;
	if (ret == STATUS_INVALID_STATE)
		ccore_lost_host(cc);
	return ret;
}

static bool ccore_animating(struct ccore *cc)
{
	int i;

	for (i = 0; i < CCORE_CHANNELS; i++)
		if (cc->leds[i].registered && cc->leds[i].rainbow &&
		    cc->leds[i].mc.led_cdev.brightness)
			return true;
	return false;
}

static void ccore_schedule_frame(struct ccore *cc)
{
	if (!cc->removing && ccore_animating(cc))
		mod_delayed_work(system_dfl_wq, &cc->animate,
				 msecs_to_jiffies(CCORE_FRAME_MS));
}

static void ccore_animate_work(struct work_struct *work)
{
	struct ccore *cc = container_of(to_delayed_work(work), struct ccore,
					animate);
	int i;

	guard(mutex)(&cc->lock);

	for (i = 0; i < CCORE_CHANNELS; i++) {
		struct ccore_led *led = &cc->leds[i];
		unsigned int step = rainbow_step[led->speed];

		if (!led->rainbow)
			continue;
		if (led->reverse)
			step = RAINBOW_HUE_MAX - step;
		led->phase = (led->phase + step) % RAINBOW_HUE_MAX;
	}

	ccore_write_frame(cc, false);
	ccore_schedule_frame(cc);
}

static u8 ccore_curve_pwm(const struct ccore_channel *ch, long temp)
{
	const struct ccore_point *p = ch->points;
	int i;

	if (temp <= p[0].temp)
		return p[0].pwm;

	for (i = 1; i < CCORE_CURVE_POINTS; i++) {
		if (temp > p[i].temp)
			continue;
		if (p[i].temp == p[i - 1].temp)
			return p[i].pwm;
		return p[i - 1].pwm + (p[i].pwm - p[i - 1].pwm) *
			(temp - p[i - 1].temp) / (p[i].temp - p[i - 1].temp);
	}
	return p[CCORE_CURVE_POINTS - 1].pwm;
}

static u8 ccore_duty(struct ccore *cc, int i)
{
	struct ccore_channel *ch = &cc->channels[i];
	u8 pwm = ch->pwm;

	if (ch->enable == 2)
		pwm = cc->temp_errors < CCORE_TEMP_ERRORS_MAX ?
		      ccore_curve_pwm(ch, cc->temp) : 255;

	pwm = DIV_ROUND_CLOSEST(pwm * 100, 255);
	if (i == 0)
		pwm = max_t(u8, pwm, pump_min);
	return pwm;
}

static int ccore_apply_duties(struct ccore *cc)
{
	u8 data[3 + 4 * CCORE_CHANNELS] = { 0x07, 0x00 };
	u8 duty[CCORE_CHANNELS];
	int i, n = 0, ret;

	for (i = 0; i < CCORE_CHANNELS; i++) {
		if (cc->fan_status[i] == FAN_ABSENT)
			continue;
		duty[i] = ccore_duty(cc, i);
		if (duty[i] == cc->channels[i].sent)
			continue;
		data[3 + 4 * n] = i;
		data[4 + 4 * n] = 0;
		put_unaligned_le16(duty[i], data + 5 + 4 * n);
		n++;
	}
	if (!n)
		return 0;
	data[2] = n;

	ret = ccore_write_file(cc, FILE_DUTY, data, 3 + 4 * n);
	if (ret)
		return ret;

	for (i = 0; i < n; i++)
		cc->channels[data[3 + 4 * i]].sent = duty[data[3 + 4 * i]];
	return 0;
}

static int ccore_read_sensors(struct ccore *cc)
{
	u8 data[CCORE_READ_CHUNK], count;
	const u8 *items;
	int i, ret;
	s16 temp;

	ret = ccore_read_file(cc, FILE_RPM, data, sizeof(data));
	if (ret)
		return ret;
	items = ccore_items(data, &count);
	for (i = 0; i < count; i++)
		cc->rpm[i] = get_unaligned_le16(items + 2 * i);

	ret = ccore_read_file(cc, FILE_TEMP, data, sizeof(data));
	if (ret)
		return ret;
	items = ccore_items(data, &count);
	temp = get_unaligned_le16(items + 1);
	if (count && !items[0] && temp > 0 && temp < 1000) {
		cc->temp = temp * 100;
		cc->temp_errors = 0;
	} else {
		cc->temp_errors++;
	}
	return 0;
}

static int ccore_enter_host(struct ccore *cc)
{
	int i, ret;

	ret = ccore_set_mode(cc, MODE_HOST);
	if (ret)
		return ret;

	cc->host = true;
	cc->colors_open = false;
	for (i = 0; i < CCORE_CHANNELS; i++)
		cc->channels[i].sent = 0xff;
	return 0;
}

static void ccore_tick_work(struct work_struct *work)
{
	struct ccore *cc = container_of(to_delayed_work(work), struct ccore,
					tick);
	bool entered = false;
	int ret;

	guard(mutex)(&cc->lock);

	if (cc->removing)
		return;

	if (!cc->host) {
		ret = ccore_enter_host(cc);
		if (ret)
			goto out;
		entered = true;
	}

	ret = ccore_read_sensors(cc);
	if (ret)
		cc->temp_errors++;
	if (ret != STATUS_INVALID_STATE)
		ret = ccore_apply_duties(cc);
	if (ret == STATUS_INVALID_STATE)
		ccore_lost_host(cc);
	else if (entered)
		ccore_write_frame(cc, true);

out:
	if (ret)
		hid_warn_ratelimited(cc->hdev, "update failed: %d\n", ret);
	queue_delayed_work(system_dfl_wq, &cc->tick,
			   msecs_to_jiffies(CCORE_TICK_MS));
}

static int ccore_read_config(struct ccore *cc)
{
	u8 data[CURVES_SIZE], count;
	const u8 *items;
	unsigned int pump_leds;
	int i, j, ret;

	ret = ccore_read_file(cc, FILE_FAN_STATUS, data, CCORE_READ_CHUNK);
	if (ret)
		return ret;
	items = ccore_items(data, &count);
	for (i = 0; i < CCORE_CHANNELS; i++)
		cc->fan_status[i] = i < count ? items[i] : FAN_ABSENT;

	ret = ccore_read_file(cc, FILE_LED_COUNT, data, CCORE_READ_CHUNK);
	if (ret)
		return ret;
	items = ccore_items(data, &count);
	pump_leds = count ? get_unaligned_le16(items + 2) : 0;
	for (i = 0; i < count; i++) {
		struct ccore_led *led = &cc->leds[i];

		if (get_unaligned_le16(items + 4 * i) != LED_PORT_CONNECTED)
			continue;
		/* Each fan port has a fixed slot after the pump LEDs. */
		led->first = i ? pump_leds + CCORE_PORT_LEDS * (i - 1) : 0;
		led->count = get_unaligned_le16(items + 4 * i + 2);
		if ((i && led->count > CCORE_PORT_LEDS) ||
		    led->first + led->count > CCORE_MAX_LEDS)
			return -EINVAL;
		cc->led_total = led->first + led->count;
	}

	/* The stored cooling configuration that SELF mode runs. */
	ret = ccore_read_file(cc, FILE_FIXED_DUTY, data, FIXED_DUTY_SIZE);
	if (ret)
		return ret;
	items = ccore_items(data, &count);
	for (i = 0; i < count; i++) {
		u16 fixed = get_unaligned_le16(items + 2 * i);

		cc->channels[i].enable = fixed ? 1 : 2;
		cc->channels[i].pwm = DIV_ROUND_CLOSEST(min_t(u16, fixed, 100) * 255, 100);
	}

	ret = ccore_read_file(cc, FILE_CURVES, data, CURVES_SIZE);
	if (ret)
		return ret;
	items = ccore_items(data, &count);
	for (i = 0; i < count; i++) {
		const u8 *curve = items + CURVE_SIZE * i;
		u8 points = min_t(u8, curve[1], CCORE_CURVE_POINTS);
		struct ccore_point *p = cc->channels[i].points;

		if (!points) {
			cc->channels[i].enable = 1;
			continue;
		}
		for (j = 0; j < CCORE_CURVE_POINTS; j++) {
			const u8 *point = curve + 2 + 4 * min(j, points - 1);

			p[j].temp = get_unaligned_le16(point) * 100;
			p[j].pwm = DIV_ROUND_CLOSEST(min_t(u16, get_unaligned_le16(point + 2), 100) * 255, 100);
		}
	}
	return 0;
}

static umode_t ccore_is_visible(const void *data, enum hwmon_sensor_types type,
				u32 attr, int channel)
{
	const struct ccore *cc = data;

	switch (type) {
	case hwmon_temp:
		return 0444;
	case hwmon_fan:
		return cc->fan_status[channel] == FAN_ABSENT ? 0 : 0444;
	case hwmon_pwm:
		return cc->fan_status[channel] == FAN_ABSENT ? 0 : 0644;
	default:
		return 0;
	}
}

static int ccore_read(struct device *dev, enum hwmon_sensor_types type,
		      u32 attr, int channel, long *val)
{
	struct ccore *cc = dev_get_drvdata(dev);

	guard(mutex)(&cc->lock);

	switch (type) {
	case hwmon_temp:
		if (cc->temp_errors >= CCORE_TEMP_ERRORS_MAX)
			return -ENODATA;
		*val = cc->temp;
		return 0;
	case hwmon_fan:
		*val = cc->rpm[channel];
		return 0;
	case hwmon_pwm:
		if (attr == hwmon_pwm_enable)
			*val = cc->channels[channel].enable;
		else
			*val = DIV_ROUND_CLOSEST(ccore_duty(cc, channel) * 255, 100);
		return 0;
	default:
		return -EOPNOTSUPP;
	}
}

static int ccore_write(struct device *dev, enum hwmon_sensor_types type,
		       u32 attr, int channel, long val)
{
	struct ccore *cc = dev_get_drvdata(dev);
	struct ccore_channel *ch = &cc->channels[channel];

	guard(mutex)(&cc->lock);

	if (attr == hwmon_pwm_enable) {
		if (val != 1 && val != 2)
			return -EINVAL;
		ch->enable = val;
	} else {
		if (val < 0 || val > 255)
			return -EINVAL;
		ch->pwm = val;
		ch->enable = 1;
	}

	return cc->host ? ccore_apply_duties(cc) : 0;
}

static int ccore_read_string(struct device *dev, enum hwmon_sensor_types type,
			     u32 attr, int channel, const char **str)
{
	*str = type == hwmon_temp ? "Coolant" : fan_labels[channel];
	return 0;
}

static const struct hwmon_ops ccore_hwmon_ops = {
	.is_visible = ccore_is_visible,
	.read = ccore_read,
	.write = ccore_write,
	.read_string = ccore_read_string,
};

#define CCORE_FAN (HWMON_F_INPUT | HWMON_F_LABEL)
#define CCORE_PWM (HWMON_PWM_INPUT | HWMON_PWM_ENABLE)

static const struct hwmon_channel_info *const ccore_info[] = {
	HWMON_CHANNEL_INFO(temp, HWMON_T_INPUT | HWMON_T_LABEL),
	HWMON_CHANNEL_INFO(fan, CCORE_FAN, CCORE_FAN, CCORE_FAN, CCORE_FAN,
			   CCORE_FAN, CCORE_FAN, CCORE_FAN),
	HWMON_CHANNEL_INFO(pwm, CCORE_PWM, CCORE_PWM, CCORE_PWM, CCORE_PWM,
			   CCORE_PWM, CCORE_PWM, CCORE_PWM),
	NULL
};

static const struct hwmon_chip_info ccore_chip_info = {
	.ops = &ccore_hwmon_ops,
	.info = ccore_info,
};

static ssize_t auto_point_temp_show(struct device *dev,
				    struct device_attribute *attr, char *buf)
{
	struct sensor_device_attribute_2 *sattr = to_sensor_dev_attr_2(attr);
	struct ccore *cc = dev_get_drvdata(dev);

	guard(mutex)(&cc->lock);
	return sysfs_emit(buf, "%ld\n",
			  cc->channels[sattr->nr].points[sattr->index].temp);
}

static ssize_t auto_point_temp_store(struct device *dev,
				     struct device_attribute *attr,
				     const char *buf, size_t count)
{
	struct sensor_device_attribute_2 *sattr = to_sensor_dev_attr_2(attr);
	struct ccore *cc = dev_get_drvdata(dev);
	long val;
	int ret;

	ret = kstrtol(buf, 10, &val);
	if (ret)
		return ret;
	if (val < 0 || val > 100000)
		return -EINVAL;

	guard(mutex)(&cc->lock);
	cc->channels[sattr->nr].points[sattr->index].temp = val;
	return count;
}

static ssize_t auto_point_pwm_show(struct device *dev,
				   struct device_attribute *attr, char *buf)
{
	struct sensor_device_attribute_2 *sattr = to_sensor_dev_attr_2(attr);
	struct ccore *cc = dev_get_drvdata(dev);

	guard(mutex)(&cc->lock);
	return sysfs_emit(buf, "%u\n",
			  cc->channels[sattr->nr].points[sattr->index].pwm);
}

static ssize_t auto_point_pwm_store(struct device *dev,
				    struct device_attribute *attr,
				    const char *buf, size_t count)
{
	struct sensor_device_attribute_2 *sattr = to_sensor_dev_attr_2(attr);
	struct ccore *cc = dev_get_drvdata(dev);
	u8 val;
	int ret;

	ret = kstrtou8(buf, 10, &val);
	if (ret)
		return ret;

	guard(mutex)(&cc->lock);
	cc->channels[sattr->nr].points[sattr->index].pwm = val;
	return count;
}

#define CCORE_POINT(ch, pt)						\
	static SENSOR_DEVICE_ATTR_2_RW(pwm##ch##_auto_point##pt##_temp,	\
				       auto_point_temp, ch - 1, pt - 1);	\
	static SENSOR_DEVICE_ATTR_2_RW(pwm##ch##_auto_point##pt##_pwm,	\
				       auto_point_pwm, ch - 1, pt - 1)

#define CCORE_POINTS(ch)						\
	CCORE_POINT(ch, 1); CCORE_POINT(ch, 2); CCORE_POINT(ch, 3);	\
	CCORE_POINT(ch, 4); CCORE_POINT(ch, 5); CCORE_POINT(ch, 6);	\
	CCORE_POINT(ch, 7)

#define CCORE_POINT_ATTRS(ch, pt)					\
	&sensor_dev_attr_pwm##ch##_auto_point##pt##_temp.dev_attr.attr,	\
	&sensor_dev_attr_pwm##ch##_auto_point##pt##_pwm.dev_attr.attr

#define CCORE_POINTS_ATTRS(ch)						\
	CCORE_POINT_ATTRS(ch, 1), CCORE_POINT_ATTRS(ch, 2),		\
	CCORE_POINT_ATTRS(ch, 3), CCORE_POINT_ATTRS(ch, 4),		\
	CCORE_POINT_ATTRS(ch, 5), CCORE_POINT_ATTRS(ch, 6),		\
	CCORE_POINT_ATTRS(ch, 7)

CCORE_POINTS(1);
CCORE_POINTS(2);
CCORE_POINTS(3);
CCORE_POINTS(4);
CCORE_POINTS(5);
CCORE_POINTS(6);
CCORE_POINTS(7);

static struct attribute *ccore_curve_attrs[] = {
	CCORE_POINTS_ATTRS(1),
	CCORE_POINTS_ATTRS(2),
	CCORE_POINTS_ATTRS(3),
	CCORE_POINTS_ATTRS(4),
	CCORE_POINTS_ATTRS(5),
	CCORE_POINTS_ATTRS(6),
	CCORE_POINTS_ATTRS(7),
	NULL
};

static umode_t ccore_curve_visible(struct kobject *kobj, struct attribute *attr,
				   int n)
{
	struct ccore *cc = dev_get_drvdata(kobj_to_dev(kobj));
	int channel = n / (2 * CCORE_CURVE_POINTS);

	return cc->fan_status[channel] == FAN_ABSENT ? 0 : attr->mode;
}

static const struct attribute_group ccore_curve_group = {
	.attrs = ccore_curve_attrs,
	.is_visible = ccore_curve_visible,
};

static const struct attribute_group *ccore_groups[] = {
	&ccore_curve_group,
	NULL
};

static struct ccore_led *to_ccore_led(struct led_classdev *cdev)
{
	return container_of(lcdev_to_mccdev(cdev), struct ccore_led, mc);
}

static int ccore_led_set(struct led_classdev *cdev,
			 enum led_brightness brightness)
{
	struct ccore_led *led = to_ccore_led(cdev);
	struct ccore *cc = led->cc;
	int ret;

	guard(mutex)(&cc->lock);
	ret = ccore_write_frame(cc, false);
	ccore_schedule_frame(cc);
	return ret > 0 ? -EIO : ret;
}

static int ccore_rainbow_activate(struct led_classdev *cdev)
{
	struct ccore_led *led = to_ccore_led(cdev);
	struct ccore *cc = led->cc;

	guard(mutex)(&cc->lock);
	led->rainbow = true;
	if (!cdev->brightness)
		cdev->brightness = cdev->max_brightness;
	ccore_write_frame(cc, false);
	ccore_schedule_frame(cc);
	return 0;
}

/* The LED core turns the LED off after this, which writes the frame. */
static void ccore_rainbow_deactivate(struct led_classdev *cdev)
{
	struct ccore_led *led = to_ccore_led(cdev);

	guard(mutex)(&led->cc->lock);
	led->rainbow = false;
}

static ssize_t speed_show(struct device *dev, struct device_attribute *attr,
			  char *buf)
{
	struct ccore_led *led = to_ccore_led(led_trigger_get_led(dev));

	return sysfs_emit(buf, "%u\n", led->speed);
}

static ssize_t speed_store(struct device *dev, struct device_attribute *attr,
			   const char *buf, size_t count)
{
	struct ccore_led *led = to_ccore_led(led_trigger_get_led(dev));
	u8 speed;
	int ret;

	ret = kstrtou8(buf, 10, &speed);
	if (ret)
		return ret;
	if (speed >= RAINBOW_SPEEDS)
		return -EINVAL;

	guard(mutex)(&led->cc->lock);
	led->speed = speed;
	return count;
}
static DEVICE_ATTR_RW(speed);

static ssize_t direction_show(struct device *dev,
			      struct device_attribute *attr, char *buf)
{
	struct ccore_led *led = to_ccore_led(led_trigger_get_led(dev));

	return sysfs_emit(buf, "%s\n", led->reverse ? "reverse" : "forward");
}

static ssize_t direction_store(struct device *dev,
			       struct device_attribute *attr, const char *buf,
			       size_t count)
{
	struct ccore_led *led = to_ccore_led(led_trigger_get_led(dev));
	bool reverse;

	if (sysfs_streq(buf, "forward"))
		reverse = false;
	else if (sysfs_streq(buf, "reverse"))
		reverse = true;
	else
		return -EINVAL;

	guard(mutex)(&led->cc->lock);
	led->reverse = reverse;
	return count;
}
static DEVICE_ATTR_RW(direction);

static struct attribute *ccore_rainbow_attrs[] = {
	&dev_attr_speed.attr,
	&dev_attr_direction.attr,
	NULL
};
ATTRIBUTE_GROUPS(ccore_rainbow);

static struct led_hw_trigger_type ccore_trigger_type;

static struct led_trigger ccore_rainbow = {
	.name = "rainbow",
	.activate = ccore_rainbow_activate,
	.deactivate = ccore_rainbow_deactivate,
	.trigger_type = &ccore_trigger_type,
	.groups = ccore_rainbow_groups,
};

static void ccore_leds_unregister(struct ccore *cc)
{
	int i;

	for (i = 0; i < CCORE_CHANNELS; i++)
		if (cc->leds[i].registered)
			led_classdev_multicolor_unregister(&cc->leds[i].mc);
}

static int ccore_leds_register(struct ccore *cc)
{
	struct device *dev = &cc->hdev->dev;
	struct led_classdev *cdev;
	int i, j, ret;

	for (i = 0; i < CCORE_CHANNELS; i++) {
		struct ccore_led *led = &cc->leds[i];

		if (!led->count)
			continue;

		led->cc = cc;
		led->speed = RAINBOW_SPEED_DEFAULT;
		led->subleds[0].color_index = LED_COLOR_ID_RED;
		led->subleds[1].color_index = LED_COLOR_ID_GREEN;
		led->subleds[2].color_index = LED_COLOR_ID_BLUE;
		for (j = 0; j < 3; j++) {
			led->subleds[j].channel = j;
			led->subleds[j].intensity = LED_FULL;
		}
		led->mc.subled_info = led->subleds;
		led->mc.num_colors = 3;

		cdev = &led->mc.led_cdev;
		if (i)
			cdev->name = devm_kasprintf(dev, GFP_KERNEL,
						    "%s:rgb:fan-%d",
						    dev_name(dev), i);
		else
			cdev->name = devm_kasprintf(dev, GFP_KERNEL,
						    "%s:rgb:pump",
						    dev_name(dev));
		if (!cdev->name) {
			ret = -ENOMEM;
			goto err;
		}
		cdev->max_brightness = LED_FULL;
		cdev->brightness_set_blocking = ccore_led_set;
		cdev->trigger_type = &ccore_trigger_type;
		cdev->flags = LED_RETAIN_AT_SHUTDOWN;

		ret = led_classdev_multicolor_register(dev, &led->mc);
		if (ret)
			goto err;
		led->registered = true;
	}
	return 0;

err:
	ccore_leds_unregister(cc);
	return ret;
}

static int ccore_raw_event(struct hid_device *hdev, struct hid_report *report,
			   u8 *data, int size)
{
	struct ccore *cc = hid_get_drvdata(hdev);
	unsigned long flags;

	if (!cc || size < 3)
		return 0;

	spin_lock_irqsave(&cc->rx_lock, flags);
	if (cc->rx_pending && data[1] == cc->rx_cmd) {
		memcpy(cc->rx, data, min_t(int, size, CCORE_REPORT_SIZE));
		cc->rx_pending = false;
		complete(&cc->rx_done);
	}
	spin_unlock_irqrestore(&cc->rx_lock, flags);
	return 0;
}

static void ccore_stop(struct ccore *cc)
{
	scoped_guard(mutex, &cc->lock)
		cc->removing = true;
	cancel_delayed_work_sync(&cc->tick);
	cancel_delayed_work_sync(&cc->animate);
}

/* Hands cooling and lighting back to the firmware. */
static void ccore_release(struct ccore *cc)
{
	guard(mutex)(&cc->lock);
	ccore_set_mode(cc, MODE_SELF);
	ccore_lost_host(cc);
}

static void ccore_start(struct ccore *cc)
{
	scoped_guard(mutex, &cc->lock)
		cc->removing = false;
	mod_delayed_work(system_dfl_wq, &cc->tick, 0);
	scoped_guard(mutex, &cc->lock)
		ccore_schedule_frame(cc);
}

static int ccore_probe(struct hid_device *hdev, const struct hid_device_id *id)
{
	struct ccore *cc;
	int ret;

	ret = hid_parse(hdev);
	if (ret)
		return ret;

	/* The second interface only carries notifications. */
	if (!hdev->maxcollection ||
	    hdev->collection[0].usage != CCORE_USAGE_COMMANDS)
		return hid_hw_start(hdev, HID_CONNECT_HIDRAW);

	cc = devm_kzalloc(&hdev->dev, sizeof(*cc), GFP_KERNEL);
	if (!cc)
		return -ENOMEM;

	cc->tx = devm_kzalloc(&hdev->dev, CCORE_REPORT_SIZE + 1, GFP_KERNEL);
	if (!cc->tx)
		return -ENOMEM;

	cc->hdev = hdev;
	spin_lock_init(&cc->rx_lock);
	init_completion(&cc->rx_done);
	INIT_DELAYED_WORK(&cc->tick, ccore_tick_work);
	INIT_DELAYED_WORK(&cc->animate, ccore_animate_work);
	ret = devm_mutex_init(&hdev->dev, &cc->lock);
	if (ret)
		return ret;

	pump_min = clamp_t(unsigned short, pump_min, 50, 100);

	ret = hid_hw_start(hdev, HID_CONNECT_HIDRAW);
	if (ret)
		return ret;

	ret = hid_hw_open(hdev);
	if (ret)
		goto out_stop;

	hid_set_drvdata(hdev, cc);
	hid_device_io_start(hdev);

	scoped_guard(mutex, &cc->lock) {
		ret = ccore_enter_host(cc);
		if (!ret)
			ret = ccore_read_config(cc);
	}
	if (ret) {
		hid_err(hdev, "setup failed: %d\n", ret);
		ret = ret > 0 ? -EIO : ret;
		goto out_release;
	}

	cc->hwmon = hwmon_device_register_with_info(&hdev->dev, "corsairccore",
						    cc, &ccore_chip_info,
						    ccore_groups);
	if (IS_ERR(cc->hwmon)) {
		ret = PTR_ERR(cc->hwmon);
		goto out_release;
	}

	ret = ccore_leds_register(cc);
	if (ret)
		goto out_hwmon;

	ccore_start(cc);
	return 0;

out_hwmon:
	hwmon_device_unregister(cc->hwmon);
out_release:
	ccore_release(cc);
	hid_device_io_stop(hdev);
	hid_set_drvdata(hdev, NULL);
	hid_hw_close(hdev);
out_stop:
	hid_hw_stop(hdev);
	return ret;
}

static void ccore_remove(struct hid_device *hdev)
{
	struct ccore *cc = hid_get_drvdata(hdev);

	if (!cc) {
		hid_hw_stop(hdev);
		return;
	}

	ccore_stop(cc);
	hwmon_device_unregister(cc->hwmon);
	ccore_leds_unregister(cc);
	ccore_release(cc);
	hid_hw_close(hdev);
	hid_hw_stop(hdev);
}

static int __maybe_unused ccore_suspend(struct hid_device *hdev,
					pm_message_t message)
{
	struct ccore *cc = hid_get_drvdata(hdev);

	if (cc) {
		ccore_stop(cc);
		ccore_release(cc);
	}
	return 0;
}

static int __maybe_unused ccore_resume(struct hid_device *hdev)
{
	struct ccore *cc = hid_get_drvdata(hdev);

	if (cc)
		ccore_start(cc);
	return 0;
}

static const struct hid_device_id ccore_table[] = {
	{ HID_USB_DEVICE(0x1b1c, 0x0c32) }, /* iCUE COMMANDER Core */
	{ }
};
MODULE_DEVICE_TABLE(hid, ccore_table);

static struct hid_driver ccore_driver = {
	.name = "corsair-ccore",
	.id_table = ccore_table,
	.probe = ccore_probe,
	.remove = ccore_remove,
	.raw_event = ccore_raw_event,
#ifdef CONFIG_PM
	.suspend = ccore_suspend,
	.resume = ccore_resume,
	.reset_resume = ccore_resume,
#endif
};

static int __init ccore_init(void)
{
	int ret;

	ret = led_trigger_register(&ccore_rainbow);
	if (ret)
		return ret;

	ret = hid_register_driver(&ccore_driver);
	if (ret)
		led_trigger_unregister(&ccore_rainbow);
	return ret;
}

static void __exit ccore_exit(void)
{
	hid_unregister_driver(&ccore_driver);
	led_trigger_unregister(&ccore_rainbow);
}

module_init(ccore_init);
module_exit(ccore_exit);

MODULE_DESCRIPTION("Corsair iCUE Commander Core driver");
MODULE_LICENSE("GPL");
