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
	void __iomem *mb = ioremap_cache(0xffc00000, 0x1000);
	u64 magic, step, target, dtb, pages;
	ssize_t ret;

	if (!mb)
		return sprintf(buf, "[-] Failed to ioremap_cache 0xffc00000\n");

	magic  = readq(mb);
	step   = readq(mb + 8);
	target = readq(mb + 16);
	dtb    = readq(mb + 24);
	pages  = readq(mb + 32);

	ret = sprintf(buf,
		"=== KEXEC HARDWARE MAILBOX (0xffc00000) ===\n"
		"Magic:        0x%llx (%s)\n"
		"Step:         %llu (%s)\n"
		"Target Entry: 0x%llx\n"
		"DTB Address:  0x%llx\n"
		"Pages Copied: %llu (0x%llx bytes)\n"
		"===========================================\n",
		magic, (magic == 0x4b455845435f4c47ULL) ? "VALID KEXEC_LG" : "INVALID / UNWRITTEN",
		step, (step == 1) ? "Entry reached" :
		      (step == 2) ? "MMU disabled" :
		      (step == 3) ? "Relocating pages" :
		      (step == 4) ? "Relocation finished" :
		      (step == 5) ? "Jumped to new kernel!" : "Unknown",
		target, dtb, pages, pages * 4096);

	iounmap(mb);
	return ret;
}

static struct kobj_attribute kexec_debug_log_attr = __ATTR_RO(kexec_debug_log);

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
