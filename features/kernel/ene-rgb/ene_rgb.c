// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * Multicolor LED driver for ENE (ASUS Aura) controllers on DIMMs and GPUs.
 * Hardware effects are private LED triggers. Register layout from OpenRGB's
 * ENESMBusController.
 */

#include <linux/i2c.h>
#include <linux/led-class-multicolor.h>
#include <linux/leds.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/pci.h>
#include <linux/pm.h>
#include <linux/workqueue.h>

#define ENE_CMD_SELECT 0x00
#define ENE_CMD_WRITE 0x01
#define ENE_CMD_READ 0x81

#define ENE_REG_VERSION 0x1000
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

struct ene_variant {
	const char *function;
	const char *version;
	u16 led_count_reg;
	/* DIMMs stay powered in S3, so their LEDs would stay lit. */
	bool off_in_suspend;
};

static const struct ene_variant ene_dram = {
	.function = "dram",
	.version = "AUDA0-E6K5-0101",
	.led_count_reg = 0x1c02,
	.off_in_suspend = true,
};

static const struct ene_variant ene_gpu = {
	.function = "gpu",
	.version = "AUMA0-E6K5-0107",
	.led_count_reg = 0x1c03,
};

struct ene_effect {
	struct led_trigger trigger;
	u8 mode;
	u8 flags;
};

struct ene_led {
	struct i2c_client *client;
	const struct ene_variant *variant;
	struct led_classdev_mc mc;
	struct mc_subled subleds[3];
	/* Serializes the cached state and the register writes. */
	struct mutex lock;
	const struct ene_effect *effect;
	u8 led_count;
	u8 speed;
	bool reverse;
	bool suspended;
};

static struct ene_led *to_ene_led(struct led_classdev *cdev)
{
	return container_of(lcdev_to_mccdev(cdev), struct ene_led, mc);
}

/* No other transfer may run between the register select and the access. */
static int ene_access(struct i2c_client *client, u16 reg, char read_write,
		      u8 command, union i2c_smbus_data *data)
{
	struct i2c_adapter *adap = client->adapter;
	union i2c_smbus_data select = { .word = swab16(reg) };
	int ret;

	i2c_lock_bus(adap, I2C_LOCK_SEGMENT);
	ret = __i2c_smbus_xfer(adap, client->addr, client->flags,
			       I2C_SMBUS_WRITE, ENE_CMD_SELECT,
			       I2C_SMBUS_WORD_DATA, &select);
	if (!ret)
		ret = __i2c_smbus_xfer(adap, client->addr, client->flags,
				       read_write, command,
				       I2C_SMBUS_BYTE_DATA, data);
	i2c_unlock_bus(adap, I2C_LOCK_SEGMENT);
	return ret;
}

static int ene_read(struct i2c_client *client, u16 reg)
{
	union i2c_smbus_data data;
	int ret;

	ret = ene_access(client, reg, I2C_SMBUS_READ, ENE_CMD_READ, &data);
	return ret ?: data.byte;
}

static int ene_write(struct i2c_client *client, u16 reg, u8 val)
{
	union i2c_smbus_data data = { .byte = val };

	return ene_access(client, reg, I2C_SMBUS_WRITE, ENE_CMD_WRITE, &data);
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

static int ene_apply(struct ene_led *led, unsigned int brightness)
{
	struct i2c_client *client = led->client;
	u8 mode = ENE_MODE_STATIC;
	int ret;

	lockdep_assert_held(&led->lock);

	/* Generic triggers keep running while the device is suspended. */
	if (led->suspended)
		return 0;

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
	return ene_apply(led, brightness);
}

static int ene_trigger_activate(struct led_classdev *cdev)
{
	struct ene_led *led = to_ene_led(cdev);
	int ret;

	guard(mutex)(&led->lock);
	led->effect = container_of(cdev->trigger, struct ene_effect, trigger);
	if (!cdev->brightness)
		cdev->brightness = cdev->max_brightness;
	ret = ene_apply(led, cdev->brightness);
	/* The LED core does not call deactivate after a failed activate. */
	if (ret)
		led->effect = NULL;
	return ret;
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
	ret = ene_apply(led, led->mc.led_cdev.brightness);
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
	ret = ene_apply(led, led->mc.led_cdev.brightness);
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

static int ene_check_version(struct i2c_client *client,
			     const struct ene_variant *variant)
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

	if (strcmp(version, variant->version)) {
		dev_err(&client->dev, "unsupported version '%s'\n", version);
		return -ENODEV;
	}
	return 0;
}

static int ene_probe(struct i2c_client *client)
{
	const struct ene_variant *variant = i2c_get_match_data(client);
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

	ret = ene_check_version(client, variant);
	if (ret)
		return ret;

	ret = ene_read(client, variant->led_count_reg);
	if (ret < 0)
		return ret;
	if (!ret || ret > ENE_MAX_LEDS) {
		dev_err(dev, "unexpected LED count %d\n", ret);
		return -ENODEV;
	}

	led->client = client;
	led->variant = variant;
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
	cdev->name = devm_kasprintf(dev, GFP_KERNEL, "%s:rgb:%s",
				    dev_name(dev), variant->function);
	if (!cdev->name)
		return -ENOMEM;
	cdev->max_brightness = LED_FULL;
	cdev->brightness_set_blocking = ene_brightness_set;
	cdev->trigger_type = &ene_trigger_type;

	i2c_set_clientdata(client, led);

	scoped_guard(mutex, &led->lock)
		ene_apply(led, LED_OFF);

	return devm_led_classdev_multicolor_register(dev, &led->mc);
}

/* A failed write must not block suspend. */
static int ene_suspend(struct device *dev)
{
	struct ene_led *led = i2c_get_clientdata(to_i2c_client(dev));

	guard(mutex)(&led->lock);
	if (led->variant->off_in_suspend)
		ene_off(led->client);
	led->suspended = true;
	return 0;
}

static int ene_resume(struct device *dev)
{
	struct ene_led *led = i2c_get_clientdata(to_i2c_client(dev));

	guard(mutex)(&led->lock);
	led->suspended = false;
	/* The GPU keeps its state in S3 and its bus fails right after resume. */
	if (led->variant->off_in_suspend)
		ene_apply(led, led->mc.led_cdev.brightness);
	return 0;
}

static DEFINE_SIMPLE_DEV_PM_OPS(ene_pm, ene_suspend, ene_resume);

static const struct i2c_device_id ene_id[] = {
	{ "ene_dram", (kernel_ulong_t)&ene_dram },
	{ "ene_gpu", (kernel_ulong_t)&ene_gpu },
	{ }
};
MODULE_DEVICE_TABLE(i2c, ene_id);

static struct i2c_driver ene_driver = {
	.driver = {
		.name = "ene_rgb",
		.pm = pm_sleep_ptr(&ene_pm),
	},
	.probe = ene_probe,
	.id_table = ene_id,
};

/* The DIMM SPD hubs and PMICs share this port, the PMICs at 0x48 to 0x4f. */
static bool ene_dram_match(struct i2c_adapter *adap)
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

static const struct pci_device_id ene_gpu_ids[] = {
	{ PCI_DEVICE_SUB(PCI_VENDOR_ID_ATI, 0x744c, PCI_VENDOR_ID_ASUSTEK, 0x0506) },
	{ }
};

/* Not the SMU buses, their transfers go through the SMU and race with suspend. */
static bool ene_gpu_match(struct i2c_adapter *adap)
{
	struct device *parent = adap->dev.parent;

	if (!parent || !dev_is_pci(parent))
		return false;

	return pci_match_id(ene_gpu_ids, to_pci_dev(parent)) &&
	       !strcmp(adap->name, "AMDGPU DM i2c OEM bus");
}

struct ene_bus {
	bool (*match)(struct i2c_adapter *adap);
	const char *type;
	unsigned short first_addr;
	unsigned short addr_count;
};

static const struct ene_bus ene_buses[] = {
	{ ene_dram_match, "ene_dram", 0x70, 8 },
	{ ene_gpu_match, "ene_gpu", 0x67, 1 },
};

static DEFINE_MUTEX(ene_exiting_lock);
static bool ene_exiting;

static bool ene_adapter_match(struct i2c_adapter *adap)
{
	int i;

	for (i = 0; i < ARRAY_SIZE(ene_buses); i++)
		if (ene_buses[i].match(adap))
			return true;
	return false;
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

struct ene_find {
	const struct ene_bus *bus;
	struct i2c_adapter *adap;
};

static int ene_find_adapter(struct device *dev, void *data)
{
	struct i2c_adapter *adap = i2c_verify_adapter(dev);
	struct ene_find *find = data;

	if (!adap || !find->bus->match(adap))
		return 0;

	find->adap = i2c_get_adapter(adap->nr);
	return 1;
}

/*
 * The clients stay with the adapter, which removes them. A module reload
 * binds to them again through the id table.
 */
static void ene_scan_bus(const struct ene_bus *bus)
{
	struct ene_find find = { .bus = bus };
	struct i2c_adapter *check;
	int i;

	/* Not i2c_for_each_dev(), it deadlocks with i2c_get_adapter(). */
	bus_for_each_dev(&i2c_bus_type, NULL, &find, ene_find_adapter);
	if (!find.adap)
		return;

	for (i = 0; i < bus->addr_count; i++) {
		unsigned short addrs[] = { bus->first_addr + i, I2C_CLIENT_END };
		struct i2c_board_info info = { };

		/* Stop once the adapter is being deleted. */
		check = i2c_get_adapter(find.adap->nr);
		if (!check)
			break;
		i2c_put_adapter(check);

		strscpy(info.type, bus->type);
		i2c_new_scanned_device(find.adap, &info, addrs, ene_detect);
	}

	i2c_put_adapter(find.adap);
}

static void ene_scan(struct work_struct *work)
{
	int i;

	for (i = 0; i < ARRAY_SIZE(ene_buses); i++)
		ene_scan_bus(&ene_buses[i]);
}

static DECLARE_WORK(ene_scan_work, ene_scan);

static int ene_bus_notify(struct notifier_block *nb, unsigned long action,
			  void *data)
{
	struct i2c_adapter *adap = i2c_verify_adapter(data);

	if (action != BUS_NOTIFY_ADD_DEVICE || !adap || !ene_adapter_match(adap))
		return NOTIFY_DONE;

	guard(mutex)(&ene_exiting_lock);
	if (!ene_exiting)
		queue_work(system_freezable_wq, &ene_scan_work);
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

	queue_work(system_freezable_wq, &ene_scan_work);
	return 0;

err_driver:
	i2c_del_driver(&ene_driver);
err_triggers:
	ene_unregister_triggers(i);
	return ret;
}

static void __exit ene_exit(void)
{
	scoped_guard(mutex, &ene_exiting_lock)
		ene_exiting = true;
	cancel_work_sync(&ene_scan_work);

	bus_unregister_notifier(&i2c_bus_type, &ene_nb);
	i2c_del_driver(&ene_driver);
	ene_unregister_triggers(ARRAY_SIZE(ene_effects));
}

module_init(ene_init);
module_exit(ene_exit);

MODULE_DESCRIPTION("ENE (ASUS Aura) RGB LED driver");
MODULE_LICENSE("GPL");
