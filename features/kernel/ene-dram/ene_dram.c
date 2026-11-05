// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * Turns off the LEDs of DIMMs with an ENE (ASUS Aura) controller and keeps
 * them off across suspend. Register layout from OpenRGB's ENESMBusController.
 */

#include <linux/i2c.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/pci.h>
#include <linux/pm.h>
#include <linux/workqueue.h>

#define ENE_ADDR_FIRST 0x70
#define ENE_ADDR_COUNT 8

#define ENE_CMD_SELECT 0x00
#define ENE_CMD_WRITE 0x01

#define ENE_REG_DIRECT 0x8020
#define ENE_REG_MODE 0x8021
#define ENE_REG_APPLY 0x80a0

#define ENE_MODE_OFF 0x00
#define ENE_APPLY 0x01

static struct i2c_client *ene_clients[ENE_ADDR_COUNT];
static DEFINE_MUTEX(ene_clients_lock);

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

/* Stay bound after a failed write so the PM callbacks still retry. */
static int ene_probe(struct i2c_client *client)
{
	ene_off(client);
	return 0;
}

/* A failed write must not block suspend. */
static int ene_pm_off(struct device *dev)
{
	ene_off(to_i2c_client(dev));
	return 0;
}

static DEFINE_SIMPLE_DEV_PM_OPS(ene_pm, ene_pm_off, ene_pm_off);

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

static int __init ene_init(void)
{
	int ret;

	ret = i2c_add_driver(&ene_driver);
	if (ret)
		return ret;

	ret = bus_register_notifier(&i2c_bus_type, &ene_nb);
	if (ret) {
		i2c_del_driver(&ene_driver);
		return ret;
	}

	queue_work(system_long_wq, &ene_scan_work);
	return 0;
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
}

module_init(ene_init);
module_exit(ene_exit);

MODULE_DESCRIPTION("Keep ENE DRAM RGB LEDs off");
MODULE_LICENSE("GPL");
