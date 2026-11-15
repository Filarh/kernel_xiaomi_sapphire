/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Copyright (c) 2017, 2019-2020 The Linux Foundation. All rights reserved.
 * Copyright (c) 2022, Qualcomm Innovation Center, Inc. All rights reserved.
 */
#ifndef __BATTERY_H
#define __BATTERY_H

struct charger_param {
	u32 fcc_step_delay_ms;
	u32 fcc_step_size_ua;
	u32 fcc_step_start_ua;
	u32 smb_version;
	u32 hvdcp2_max_icl_ua;
	u32 hvdcp3_max_icl_ua;
	u32 qc4_max_icl_ua;
	u32 forced_main_fcc;
	int (*iio_read)(struct device *dev, int iio_chan, int *val);
	int (*iio_write)(struct device *dev, int iio_chan, int val);
};

int qcom_batt_init(struct device *dev, struct charger_param *param);
void qcom_batt_deinit(void);

/* Xiaomi */
#include <linux/notifier.h>

enum qpnp_smb5_notifier_events {
	QPNP_SMB5_NONE_EVENT,
	QPNP_SMB5_USB_PLUGIN_EVENT,
	QPNP_SMB5_THERMAL_LEVEL_EVENT,
	QPNP_SMB5_SMART_CHG_EVENT,
	QPNP_SMB5_SMART_BATT_EVENT,
	QPNP_SMB5_NIGHT_CHARGING_EVENT,
};

extern struct srcu_notifier_head qpnp_smb5_notifier;
extern int plugin_val;

void set_fv_ageing(int val);
int get_fv_ageing(void);
void set_blank_status(int val);
int qg_batt_get_capacity(void);
int qg_batt_get_voltage(void);
int cid_set_prop_typec_power_role(int val);
int smblib_enable_ship_mode(int enable);
void set_smb5_rdy(void);
bool is_smb5_rdy(void);
int qpnp_smb5_reg_notifier(struct notifier_block *nb);
int qpnp_smb5_unreg_notifier(struct notifier_block *nb);
int qpnp_smb5_notifier_call_chain(unsigned long event, int val);
#endif /* __BATTERY_H */
