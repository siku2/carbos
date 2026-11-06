// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * Multicolor LED driver for DIMMs with an ENE (ASUS Aura) controller.
 * Hardware effects are private LED triggers. The LEDs are turned off for
 * suspend because the DIMMs stay powered in S3. Register layout from
 * OpenRGB's ENESMBusController.
 */

#include <linux/i2c.h>
#include <linux/led-class-multicolor.h>
#include <linux/leds.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/pci.h>
#include <linux/pm.h>
#include <linux/workqueue.h>

#define ENE_ADDR_FIRST 0x70
#define ENE_ADDR_COUNT 8

#define ENE_CMD_SELECT 0x00
#define ENE_CMD_WRITE 0x01
#define ENE_CMD_READ 0x81

#define ENE_REG_VERSION 0x1000
#define ENE_REG_LED_COUNT 0x1c02
#define ENE_REG_COLORS 0x8160
#define ENE_REG_DIRECT 0x8020
#define ENE_REG_MODE 0x8021
#define ENE_REG_SPEED 0x8022
#define ENE_REG_DIRECTION 0x8023
#define ENE_REG_APPLY 0x80a0

#define ENE_VERSION_LEN 16
#define ENE_MAX_LEDS 10
#define ENE_SPEED_MAX 4

#define ENE_MODE_OFF 0
#define ENE_MODE_STATIC 1
#define ENE_APPLY 0x01

/* The register scale is inverted, 0 is the fastest. */
#define ENE_SPEED_DEFAULT 2

#define ENE_EFFECT_COLOR BIT(0)
#define ENE_EFFECT_DIRECTION BIT(1)

static const char *const ene_versions[] = {
	"AUDA0-E6K5-0101",
};

struct ene_effect {
	struct led_trigger trigger;
	u8 mode;
	u8 flags;
};

struct ene_led {
	struct i2c_client *client;
	struct led_classdev_mc mc;
	struct mc_subled subleds[3];
	/* Serializes the cached state and the register writes. */
	struct mutex lock;
	const struct ene_effect *effect;
	u8 led_count;
	u8 speed;
	bool reverse;
};

static struct i2c_client *ene_clients[ENE_ADDR_COUNT];
static DEFINE_MUTEX(ene_clients_lock);

static struct ene_led *to_ene_led(struct led_classdev *cdev)
{
	return container_of(lcdev_to_mccdev(cdev), struct ene_led, mc);
}

static int ene_read(struct i2c_client *client, u16 reg)
{
	int ret;

	ret = i2c_smbus_write_word_swapped(client, ENE_CMD_SELECT, reg);
	if (ret)
		return ret;
	return i2c_smbus_read_byte_data(client, ENE_CMD_READ);
}

static int ene_write(struct i2c_client *client, u16 reg, u8 val)
{
	int ret;

	ret = i2c_smbus_write_word_swapped(client, ENE_CMD_SELECT, reg);
	if (ret)
		return ret;
	return i2c_smbus_write_byte_data(client, ENE_CMD_WRITE, val);
}

static int ene_off(struct i2c_client *client)
{
	int ret;

	ret = ene_write(client, ENE_REG_MODE, ENE_MODE_OFF);
	if (!ret)
		ret = ene_write(client, ENE_REG_DIRECT, 0);
	if (!ret)
		ret = ene_write(client, ENE_REG_APPLY, ENE_APPLY);
	if (ret)
		dev_err(&client->dev, "failed to turn off LEDs: %d\n", ret);
	return ret;
}

/* The controller stores colors as R, B, G. */
static int ene_write_colors(struct ene_led *led)
{
	u8 rbg[3] = {
		led->subleds[0].brightness,
		led->subleds[2].brightness,
		led->subleds[1].brightness,
	};
	int i, j, ret;

	for (i = 0; i < led->led_count; i++) {
		for (j = 0; j < 3; j++) {
			ret = ene_write(led->client, ENE_REG_COLORS + 3 * i + j,
					rbg[j]);
			if (ret)
				return ret;
		}
	}
	return 0;
}

static int ene_apply(struct ene_led *led)
{
	struct i2c_client *client = led->client;
	unsigned int brightness = led->mc.led_cdev.brightness;
	u8 mode = ENE_MODE_STATIC;
	int ret;

	lockdep_assert_held(&led->lock);

	if (!brightness)
		return ene_off(client);

	if (led->effect)
		mode = led->effect->mode;

	if (!led->effect || led->effect->flags & ENE_EFFECT_COLOR) {
		led_mc_calc_color_components(&led->mc, brightness);
		ret = ene_write_colors(led);
		if (ret)
			goto err;
	}

	ret = ene_write(client, ENE_REG_MODE, mode);
	if (!ret)
		ret = ene_write(client, ENE_REG_SPEED, ENE_SPEED_MAX - led->speed);
	if (!ret)
		ret = ene_write(client, ENE_REG_DIRECTION, led->reverse);
	if (!ret)
		ret = ene_write(client, ENE_REG_DIRECT, 0);
	if (!ret)
		ret = ene_write(client, ENE_REG_APPLY, ENE_APPLY);
	if (!ret)
		return 0;
err:
	dev_err(&client->dev, "failed to set LEDs: %d\n", ret);
	return ret;
}

static int ene_brightness_set(struct led_classdev *cdev,
			      enum led_brightness brightness)
{
	struct ene_led *led = to_ene_led(cdev);

	guard(mutex)(&led->lock);
	return ene_apply(led);
}

static int ene_trigger_activate(struct led_classdev *cdev)
{
	struct ene_led *led = to_ene_led(cdev);

	guard(mutex)(&led->lock);
	led->effect = container_of(cdev->trigger, struct ene_effect, trigger);
	if (!cdev->brightness)
		cdev->brightness = cdev->max_brightness;
	return ene_apply(led);
}

/* The LED core turns the LED off after this, which writes the hardware. */
static void ene_trigger_deactivate(struct led_classdev *cdev)
{
	struct ene_led *led = to_ene_led(cdev);

	guard(mutex)(&led->lock);
	led->effect = NULL;
}

static ssize_t speed_show(struct device *dev, struct device_attribute *attr,
			  char *buf)
{
	struct ene_led *led = to_ene_led(led_trigger_get_led(dev));

	return sysfs_emit(buf, "%u\n", led->speed);
}

static ssize_t speed_store(struct device *dev, struct device_attribute *attr,
			   const char *buf, size_t count)
{
	struct ene_led *led = to_ene_led(led_trigger_get_led(dev));
	u8 speed;
	int ret;

	ret = kstrtou8(buf, 10, &speed);
	if (ret)
		return ret;
	if (speed > ENE_SPEED_MAX)
		return -EINVAL;

	guard(mutex)(&led->lock);
	led->speed = speed;
	ret = ene_apply(led);
	return ret ?: count;
}
static DEVICE_ATTR_RW(speed);

static ssize_t direction_show(struct device *dev,
			      struct device_attribute *attr, char *buf)
{
	struct ene_led *led = to_ene_led(led_trigger_get_led(dev));

	return sysfs_emit(buf, "%s\n", led->reverse ? "reverse" : "forward");
}

static ssize_t direction_store(struct device *dev,
			       struct device_attribute *attr, const char *buf,
			       size_t count)
{
	struct ene_led *led = to_ene_led(led_trigger_get_led(dev));
	bool reverse;
	int ret;

	if (sysfs_streq(buf, "forward"))
		reverse = false;
	else if (sysfs_streq(buf, "reverse"))
		reverse = true;
	else
		return -EINVAL;

	guard(mutex)(&led->lock);
	led->reverse = reverse;
	ret = ene_apply(led);
	return ret ?: count;
}
static DEVICE_ATTR_RW(direction);

static struct attribute *ene_speed_attrs[] = {
	&dev_attr_speed.attr,
	NULL
};
ATTRIBUTE_GROUPS(ene_speed);

static struct attribute *ene_direction_attrs[] = {
	&dev_attr_speed.attr,
	&dev_attr_direction.attr,
	NULL
};
ATTRIBUTE_GROUPS(ene_direction);

static struct led_hw_trigger_type ene_trigger_type;

#define ENE_EFFECT(_name, _mode, _flags) {				\
	.trigger = {							\
		.name = _name,						\
		.activate = ene_trigger_activate,			\
		.deactivate = ene_trigger_deactivate,			\
		.trigger_type = &ene_trigger_type,			\
		.groups = (_flags) & ENE_EFFECT_DIRECTION ?		\
			  ene_direction_groups : ene_speed_groups,	\
	},								\
	.mode = _mode,							\
	.flags = _flags,						\
}

static struct ene_effect ene_effects[] = {
	ENE_EFFECT("breathing", 2, ENE_EFFECT_COLOR),
	ENE_EFFECT("flashing", 3, ENE_EFFECT_COLOR),
	ENE_EFFECT("spectrum-cycle", 4, 0),
	ENE_EFFECT("rainbow", 5, ENE_EFFECT_DIRECTION),
	ENE_EFFECT("spectrum-breathing", 6, 0),
	ENE_EFFECT("chase-fade", 7, ENE_EFFECT_COLOR | ENE_EFFECT_DIRECTION),
	ENE_EFFECT("spectrum-chase-fade", 8, 0),
	ENE_EFFECT("chase", 9, ENE_EFFECT_COLOR | ENE_EFFECT_DIRECTION),
	ENE_EFFECT("spectrum-chase", 10, 0),
	ENE_EFFECT("random-flicker", 13, 0),
};

static int ene_read_version(struct i2c_client *client)
{
	char version[ENE_VERSION_LEN];
	int i, ret;

	for (i = 0; i < ENE_VERSION_LEN - 1; i++) {
		ret = ene_read(client, ENE_REG_VERSION + i);
		if (ret < 0)
			return ret;
		version[i] = ret;
	}
	version[i] = '\0';

	ret = match_string(ene_versions, ARRAY_SIZE(ene_versions), version);
	if (ret < 0) {
		dev_err(&client->dev, "unsupported version '%s'\n", version);
		return -ENODEV;
	}
	return 0;
}

static int ene_probe(struct i2c_client *client)
{
	struct device *dev = &client->dev;
	struct led_classdev *cdev;
	struct ene_led *led;
	int ret;

	led = devm_kzalloc(dev, sizeof(*led), GFP_KERNEL);
	if (!led)
		return -ENOMEM;

	ret = devm_mutex_init(dev, &led->lock);
	if (ret)
		return ret;

	ret = ene_read_version(client);
	if (ret)
		return ret;

	ret = ene_read(client, ENE_REG_LED_COUNT);
	if (ret < 0)
		return ret;
	if (!ret || ret > ENE_MAX_LEDS) {
		dev_err(dev, "unexpected LED count %d\n", ret);
		return -ENODEV;
	}

	led->client = client;
	led->led_count = ret;
	led->speed = ENE_SPEED_DEFAULT;

	led->subleds[0].color_index = LED_COLOR_ID_RED;
	led->subleds[1].color_index = LED_COLOR_ID_GREEN;
	led->subleds[2].color_index = LED_COLOR_ID_BLUE;
	for (int i = 0; i < 3; i++) {
		led->subleds[i].channel = i;
		led->subleds[i].intensity = LED_FULL;
	}

	led->mc.subled_info = led->subleds;
	led->mc.num_colors = 3;

	cdev = &led->mc.led_cdev;
	cdev->name = devm_kasprintf(dev, GFP_KERNEL, "%s:rgb:dram",
				    dev_name(dev));
	if (!cdev->name)
		return -ENOMEM;
	cdev->max_brightness = LED_FULL;
	cdev->brightness_set_blocking = ene_brightness_set;
	cdev->trigger_type = &ene_trigger_type;

	i2c_set_clientdata(client, led);

	scoped_guard(mutex, &led->lock)
		ene_apply(led);

	return devm_led_classdev_multicolor_register(dev, &led->mc);
}

/* A failed write must not block suspend. */
static int ene_suspend(struct device *dev)
{
	struct ene_led *led = i2c_get_clientdata(to_i2c_client(dev));

	guard(mutex)(&led->lock);
	ene_off(led->client);
	return 0;
}

static int ene_resume(struct device *dev)
{
	struct ene_led *led = i2c_get_clientdata(to_i2c_client(dev));

	guard(mutex)(&led->lock);
	ene_apply(led);
	return 0;
}

static DEFINE_SIMPLE_DEV_PM_OPS(ene_pm, ene_suspend, ene_resume);

static const struct i2c_device_id ene_id[] = {
	{ "ene_dram" },
	{ }
};
MODULE_DEVICE_TABLE(i2c, ene_id);

static struct i2c_driver ene_driver = {
	.driver = {
		.name = "ene_dram",
		.pm = pm_sleep_ptr(&ene_pm),
	},
	.probe = ene_probe,
	.id_table = ene_id,
};

/* The DIMM SPD hubs and PMICs share this port, the PMICs at 0x48 to 0x4f. */
static bool ene_adapter_match(struct i2c_adapter *adap)
{
	struct device *parent = adap->dev.parent;
	struct pci_dev *pdev;

	if (!parent || !dev_is_pci(parent))
		return false;

	pdev = to_pci_dev(parent);
	if (pdev->vendor != PCI_VENDOR_ID_AMD ||
	    pdev->device != PCI_DEVICE_ID_AMD_KERNCZ_SMBUS)
		return false;

	return strstarts(adap->name, "SMBus PIIX4 adapter port 0 ");
}

/* ENE controllers echo the offset in registers 0xa0 to 0xaf. */
static int ene_detect(struct i2c_adapter *adap, unsigned short addr)
{
	union i2c_smbus_data data;
	int i;

	for (i = 0; i < 16; i++) {
		if (i2c_smbus_xfer(adap, addr, 0, I2C_SMBUS_READ, 0xa0 + i,
				   I2C_SMBUS_BYTE_DATA, &data) < 0)
			return 0;
		if (data.byte != i)
			return 0;
	}
	return 1;
}

static int ene_find_adapter(struct device *dev, void *data)
{
	struct i2c_adapter *adap = i2c_verify_adapter(dev);
	struct i2c_adapter **found = data;

	if (!adap || !ene_adapter_match(adap))
		return 0;

	*found = i2c_get_adapter(adap->nr);
	return 1;
}

static void ene_scan(struct work_struct *work)
{
	struct i2c_adapter *adap = NULL;
	int i;

	/* Not i2c_for_each_dev(), it deadlocks with i2c_get_adapter(). */
	bus_for_each_dev(&i2c_bus_type, NULL, &adap, ene_find_adapter);
	if (!adap)
		return;

	for (i = 0; i < ENE_ADDR_COUNT; i++) {
		unsigned short addrs[] = { ENE_ADDR_FIRST + i, I2C_CLIENT_END };
		struct i2c_board_info info = { .type = "ene_dram" };
		struct i2c_client *client;

		client = i2c_new_scanned_device(adap, &info, addrs, ene_detect);
		if (IS_ERR(client))
			continue;

		mutex_lock(&ene_clients_lock);
		ene_clients[i] = client;
		mutex_unlock(&ene_clients_lock);
	}

	i2c_put_adapter(adap);
}

static DECLARE_WORK(ene_scan_work, ene_scan);

static int ene_bus_notify(struct notifier_block *nb, unsigned long action,
			  void *data)
{
	struct device *dev = data;
	struct i2c_adapter *adap;
	struct i2c_client *client;
	int i;

	switch (action) {
	case BUS_NOTIFY_ADD_DEVICE:
		adap = i2c_verify_adapter(dev);
		if (adap && ene_adapter_match(adap))
			queue_work(system_long_wq, &ene_scan_work);
		break;
	case BUS_NOTIFY_REMOVED_DEVICE:
		client = i2c_verify_client(dev);
		if (!client)
			break;
		mutex_lock(&ene_clients_lock);
		for (i = 0; i < ENE_ADDR_COUNT; i++)
			if (ene_clients[i] == client)
				ene_clients[i] = NULL;
		mutex_unlock(&ene_clients_lock);
		break;
	}

	return NOTIFY_DONE;
}

static struct notifier_block ene_nb = { .notifier_call = ene_bus_notify };

static void ene_unregister_triggers(int count)
{
	while (count--)
		led_trigger_unregister(&ene_effects[count].trigger);
}

static int __init ene_init(void)
{
	int i, ret;

	for (i = 0; i < ARRAY_SIZE(ene_effects); i++) {
		ret = led_trigger_register(&ene_effects[i].trigger);
		if (ret)
			goto err_triggers;
	}

	ret = i2c_add_driver(&ene_driver);
	if (ret)
		goto err_triggers;

	ret = bus_register_notifier(&i2c_bus_type, &ene_nb);
	if (ret)
		goto err_driver;

	queue_work(system_long_wq, &ene_scan_work);
	return 0;

err_driver:
	i2c_del_driver(&ene_driver);
err_triggers:
	ene_unregister_triggers(i);
	return ret;
}

static void __exit ene_exit(void)
{
	int i;

	bus_unregister_notifier(&i2c_bus_type, &ene_nb);
	cancel_work_sync(&ene_scan_work);

	for (i = 0; i < ENE_ADDR_COUNT; i++)
		if (ene_clients[i])
			i2c_unregister_device(ene_clients[i]);

	i2c_del_driver(&ene_driver);
	ene_unregister_triggers(ARRAY_SIZE(ene_effects));
}

module_init(ene_init);
module_exit(ene_exit);

MODULE_DESCRIPTION("ENE DRAM RGB LED driver");
MODULE_LICENSE("GPL");
