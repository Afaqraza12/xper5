/*
 * Identity paging setup for kexec_mod.
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

#include <linux/mm.h>
#include <linux/vmalloc.h>
#include <linux/slab.h>
#include <asm/pgtable.h>
#include <asm/mmu_context.h>
#include "../../kexec_compat.h"

extern unsigned long empty_zero_page[PAGE_SIZE / sizeof(unsigned long)];

static void my_cpu_set_reserved_ttbr0(void)
{
	unsigned long rpd = find_symbol_via_kprobe("reserved_pg_dir");
	unsigned long pa = rpd ? virt_to_phys((void *)rpd) : virt_to_phys(empty_zero_page);
	unsigned long ttbr = phys_to_ttbr(pa);

	write_sysreg(ttbr, ttbr0_el1);
	isb();
}

#include "idmap.h"

#ifdef CONFIG_ARM64_64K_PAGES
#define IDMAP_BLOCK_SHIFT	PAGE_SHIFT
#define IDMAP_BLOCK_SIZE	PAGE_SIZE
#define IDMAP_TABLE_SHIFT	PMD_SHIFT
#else
#define IDMAP_BLOCK_SHIFT	SECTION_SHIFT
#define IDMAP_BLOCK_SIZE	SECTION_SIZE
#define IDMAP_TABLE_SHIFT	PUD_SHIFT
#endif

#define block_index(addr) (((addr) >> IDMAP_BLOCK_SHIFT) & (PTRS_PER_PTE - 1))
#define block_align(addr) (((addr) >> IDMAP_BLOCK_SHIFT) << IDMAP_BLOCK_SHIFT)

/*
 * Initial memory map attributes.
 */
#ifndef CONFIG_SMP
#define PTE_FLAGS	PTE_TYPE_PAGE | PTE_AF
#define PMD_FLAGS	PMD_TYPE_SECT | PMD_SECT_AF
#else
#define PTE_FLAGS	PTE_TYPE_PAGE | PTE_AF | PTE_SHARED
#define PMD_FLAGS	PMD_TYPE_SECT | PMD_SECT_AF | PMD_SECT_S
#endif

#ifdef CONFIG_ARM64_64K_PAGES
#define MM_MMUFLAGS	PTE_ATTRINDX(MT_NORMAL) | PTE_FLAGS
#else
#define MM_MMUFLAGS	PMD_ATTRINDX(MT_NORMAL) | PMD_FLAGS
#endif

pgd_t *kexec_idmap_pg_dir = NULL;
pte_t *kexec_idmap_pt = NULL;
static pte_t *pmd_table_for_pdx[PTRS_PER_PGD];

extern void __cpu_soft_restart(unsigned el2_switch,
	unsigned long entry, unsigned long arg0, unsigned long arg1,
	unsigned long arg2);

int kexec_idmap_setup(void)
{
	int i;
	unsigned long pa, pdx;
	pte_t *pmd, *next_pmd;
	void *ptrs[4];

	kexec_idmap_pg_dir = (pgd_t *)get_zeroed_page(GFP_KERNEL);
	if (!kexec_idmap_pg_dir) {
		pr_err("Failed to allocate kexec_idmap_pg_dir\n");
		return -ENOMEM;
	}

	/* Allocate 4 pages for PMD tables to guarantee no overflow */
	kexec_idmap_pt = (pte_t *)alloc_pages_exact(4 * PAGE_SIZE, GFP_KERNEL | __GFP_ZERO);
	if (!kexec_idmap_pt) {
		pr_err("Failed to allocate kexec_idmap_pt\n");
		free_page((unsigned long)kexec_idmap_pg_dir);
		kexec_idmap_pg_dir = NULL;
		return -ENOMEM;
	}

	memset(pmd_table_for_pdx, 0, sizeof(pmd_table_for_pdx));
	next_pmd = kexec_idmap_pt;

	ptrs[0] = kexec_idmap_pg_dir;
	ptrs[1] = kexec_idmap_pt;
	ptrs[2] = kexec_idmap_pt + PTRS_PER_PTE;
	ptrs[3] = (void *)__cpu_soft_restart;

	for (i = 0; i < sizeof(ptrs) / sizeof(ptrs[0]); i++) {
		pa = kexec_pa_symbol(ptrs[i]);
		pdx = pgd_index(pa);

		if (pmd_table_for_pdx[pdx]) {
			pmd = pmd_table_for_pdx[pdx];
		} else {
			pr_info("Created new idmap page table for 0x%lx\n", pa);

			pmd = next_pmd;
			next_pmd += PTRS_PER_PTE;
			pmd_table_for_pdx[pdx] = pmd;
			kexec_idmap_pg_dir[pdx] = __pgd(kexec_pa_symbol(pmd) | PMD_TYPE_TABLE);
		}

		pmd[block_index(pa)] = __pte(block_align(pa) | MM_MMUFLAGS);
	}

	return 0;
}

void kexec_idmap_free(void)
{
	if (kexec_idmap_pt) {
		free_pages_exact(kexec_idmap_pt, 4 * PAGE_SIZE);
		kexec_idmap_pt = NULL;
	}
	if (kexec_idmap_pg_dir) {
		free_page((unsigned long)kexec_idmap_pg_dir);
		kexec_idmap_pg_dir = NULL;
	}
}

void kexec_idmap_install(void)
{
	my_cpu_set_reserved_ttbr0();
	flush_tlb_all();
	cpu_set_idmap_tcr_t0sz();

	if (kexec_idmap_pg_dir)
		cpu_do_switch_mm(kexec_pa_symbol(kexec_idmap_pg_dir), &init_mm);
}

/**
 * Resolve the physical address of the specified pointer.
 * We cannot use __pa_symbol for symbols defined in our kernel module, so we need to walk
 * the page manually.
 */
phys_addr_t kexec_pa_symbol(void *ptr)
{
	unsigned long va = (unsigned long) ptr;
	unsigned long page_offset = va & ~PAGE_MASK;
	struct page *p;

	if (is_vmalloc_addr(ptr)) {
		p = vmalloc_to_page(ptr);
		if (p)
			return (phys_addr_t)(page_to_phys(p) | page_offset);
	}
	return (phys_addr_t)(virt_to_phys(ptr));
}
