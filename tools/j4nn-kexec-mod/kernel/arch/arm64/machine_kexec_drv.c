/*
 * kexec_mod_arm64: Kexec driver for ARM64.
 *
 * Copyright (C) 2021 Fabian Mastenbroek.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

#define MODULE_NAME "kexec_mod_arm64"
#define pr_fmt(fmt) MODULE_NAME ": " fmt

#include <linux/module.h>

#include "machine_kexec_compat.h"
#include "idmap.h"

MODULE_LICENSE("GPL v2");
MODULE_AUTHOR("Fabian Mastenbroek <mail.fabianm@gmail.com>");
MODULE_DESCRIPTION("Kexec backport as Kernel Module for ARM64");
MODULE_VERSION("1.1");

#include <linux/io.h>
#include <linux/kobject.h>
#include <linux/sysfs.h>

static int detect_el2 = 0;
module_param(detect_el2, int, 0);
MODULE_PARM_DESC(detect_el2,
		 "Attempt to detect EL2 mode (default = 1)");

static int shim_hyp = 0;
module_param(shim_hyp, int, 0);
MODULE_PARM_DESC(shim_hyp,
		 "Shim the HYP_SOFT_RESTART call for EL2 mode (default = 0)");

static ssize_t kexec_debug_log_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	void __iomem *mb = ioremap_cache(0xffce0000, 0x1000);
	u64 magic, step, target, dtb, pages, sctlr_orig, sctlr_new, cur_el;
	ssize_t ret;

	if (!mb)
		return sprintf(buf, "[-] Failed to ioremap_cache 0xffce0000\n");

	magic      = readq(mb);
	step       = readq(mb + 8);
	target     = readq(mb + 16);
	dtb        = readq(mb + 24);
	pages      = readq(mb + 32);
	sctlr_orig = readq(mb + 40);
	sctlr_new  = readq(mb + 48);
	cur_el     = readq(mb + 56);

	ret = sprintf(buf,
		"=== KEXEC HARDWARE MAILBOX (0xffce0000) ===\n"
		"Magic:        0x%llx (%s)\n"
		"Step:         %llu (%s)\n"
		"CurrentEL:    0x%llx (EL%llu)\n"
		"SCTLR Orig:   0x%llx\n"
		"SCTLR New:    0x%llx\n"
		"Target Entry: 0x%llx\n"
		"DTB Address:  0x%llx\n"
		"Pages Copied: %llu (0x%llx bytes)\n"
		"===========================================\n",
		magic, (magic == 0x4b455845435f4c47ULL) ? "VALID KEXEC_LG" : "INVALID / UNWRITTEN",
		step, (step == 10) ? "Step 10: Relocation code entry reached (identity map active)" :
		      (step == 11) ? "Step 11: CurrentEL read" :
		      (step == 12) ? "Step 12: SCTLR_EL1 read" :
		      (step == 13) ? "Step 13: New SCTLR_EL1 computed (MMU-off bits calculated)" :
		      (step == 14) ? "Step 14: Immediately BEFORE msr SCTLR_EL1 (turning MMU off)" :
		      (step == 15) ? "Step 15: Immediately AFTER msr SCTLR_EL1" :
		      (step == 16) ? "Step 16: Immediately AFTER isb (barrier finished)" :
		      (step == 17) ? "Step 17: Relocation copy loop entered" :
		      (step == 18) ? "Step 18: Relocation copy loop finished" :
		      (step == 19) ? "Step 19: Immediately BEFORE br x17 (jump to new kernel/purgatory)" :
		      (step == 777) ? "Step 777: CALIBRATION TEST PATTERN (survived reboot!)" : "Unknown",
		cur_el, (cur_el >> 2) & 3,
		sctlr_orig, sctlr_new,
		target, dtb, pages, pages * 4096);

	iounmap(mb);
	return ret;
}

static ssize_t kexec_debug_log_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count)
{
	void __iomem *mb = ioremap_cache(0xffce0000, 0x1000);
	if (mb) {
		writeq(0x4b455845435f4c47ULL, mb);
		writeq(777, mb + 8);
		iounmap(mb);
		pr_info("kexec_debug: wrote test pattern to 0xffce0000\n");
	}
	return count;
}

static struct kobj_attribute kexec_debug_log_attr = __ATTR_RW(kexec_debug_log);

static int __init
kexecmod_arm64_init(void)
{
	int err;

	/* Load compatibility layer */
	if ((err = machine_kexec_compat_load(detect_el2, shim_hyp)) != 0) {
		pr_err("Failed to load: %d\n", err);
		return err;
	}

	/* Build identity map for MMU */
	if ((err = kexec_idmap_setup()) != 0) {
		pr_err("Failed to setup idmap: %d\n", err);
		machine_kexec_compat_unload();
		return err;
	}

	/* Expose hardware mailbox to sysfs */
	if (sysfs_create_file(kernel_kobj, &kexec_debug_log_attr.attr) != 0) {
		pr_warn("Failed to create /sys/kernel/kexec_debug_log\n");
	}

	return 0;
}

module_init(kexecmod_arm64_init)

static void __exit
kexecmod_arm64_exit(void)
{
	sysfs_remove_file(kernel_kobj, &kexec_debug_log_attr.attr);
	kexec_idmap_free();

	/* Unload compatibility layer */
	machine_kexec_compat_unload();
}

module_exit(kexecmod_arm64_exit);
