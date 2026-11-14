/*
 * kexec for arm64
 *
 * Copyright (C) Linaro.
 * Copyright (C) Huawei Futurewei Technologies.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 */

#include <linux/kexec.h>
#include <linux/linkage.h>

#include <asm/assembler.h>
#include <asm/kexec.h>
#include <asm/page.h>
#include <asm/sysreg.h>

/*
 * arm64_relocate_new_kernel - Put a 2nd stage image in place and boot it.
 *
 * The memory that the old kernel occupies may be overwritten when coping the
 * new image to its final location.  To assure that the
 * arm64_relocate_new_kernel routine which does that copy is not overwritten,
 * all code and data needed by arm64_relocate_new_kernel must be between the
 * symbols arm64_relocate_new_kernel and arm64_relocate_new_kernel_end.  The
 * machine_kexec() routine will copy arm64_relocate_new_kernel to the kexec
 * control_code_page, a special page which has been set up to be preserved
 * during the copy operation.
 */
ENTRY(arm64_relocate_new_kernel)

	/* 
	 * Disable MMU and caches first!
	 * Once SCTLR_EL1.M = 0, virtual address translation is disabled (VA == PA).
	 * Any memory access will directly hit physical memory.
	 */
	mrs	x9, CurrentEL
	cmp	x9, #CurrentEL_EL2
	b.eq	1f

	/* EL1: Disable MMU and caches in sctlr_el1 */
	mrs	x9, sctlr_el1
	movz	x10, #0x100f
	movk	x10, #0x0020, lsl #16
	bic	x9, x9, x10
	msr	sctlr_el1, x9
	isb
	b	2f

1:
	/* EL2: Disable MMU and caches in sctlr_el2 */
	mrs	x9, sctlr_el2
	movz	x10, #0x100f
	movk	x10, #0x0020, lsl #16
	bic	x9, x9, x10
	msr	sctlr_el2, x9
	isb

2:
	/* 
	 * Hardware Mailbox at physical 0xffc00000 (ramoops buffer, persists across resets)
	 * Offset 0:  Magic "KEXEC_LG" (0x4b455845435f4c47)
	 * Offset 8:  Step marker (1=Entry & MMU off, 3=Copying, 4=Done, 5=Jumping)
	 * Offset 16: Target entry address (x17)
	 * Offset 24: DTB address (x18)
	 * Offset 32: Page copy count
	 */
	movz	x25, #0x0000
	movk	x25, #0xffc0, lsl #16		/* x25 = 0xffc00000 (mailbox) */

	movz	x26, #0x4c47
	movk	x26, #0x435f, lsl #16
	movk	x26, #0x5845, lsl #32
	movk	x26, #0x4b45, lsl #48
	str	x26, [x25]			/* Magic = KEXEC_LG */

	mov	x26, #1
	str	x26, [x25, #8]			/* Step = 1 (Entry & MMU disabled) */

	/* Setup the list loop variables. */
	mov	x18, x2				/* x18 = dtb address */
	mov	x17, x1				/* x17 = kimage_start */
	mov	x16, x0				/* x16 = kimage_head */
	raw_dcache_line_size x15, x0		/* x15 = dcache line size */
	mov	x14, xzr			/* x14 = entry ptr */
	mov	x13, xzr			/* x13 = copy dest */

	str	x17, [x25, #16]			/* Save target entry */
	str	x18, [x25, #24]			/* Save DTB address */
	mov	x27, xzr			/* Pages copied counter = 0 */
	str	x27, [x25, #32]

	/* Check if the new image needs relocation. */
	tbnz	x16, IND_DONE_BIT, .Ldone

	mov	x26, #3
	str	x26, [x25, #8]			/* Step = 3 (Relocating pages) */

.Lloop:
	and	x12, x16, PAGE_MASK		/* x12 = addr */

	/* Test the entry flags. */
.Ltest_source:
	tbz	x16, IND_SOURCE_BIT, .Ltest_indirection

	/*
	 * Direct copy page in physical memory.
	 * NOTE: dc ivac is deliberately omitted because caches and MMU are already
	 * disabled (SCTLR_EL1.C = 0, M = 0), and dc ivac traps to Gunyah EL2 hypervisor.
	 */
	mov	x20, x13
	mov	x21, x12
	copy_page x20, x21, x0, x1, x2, x3, x4, x5, x6, x7

	add	x27, x27, #1
	str	x27, [x25, #32]			/* Update page copy counter */

	/* dest += PAGE_SIZE */
	add	x13, x13, PAGE_SIZE
	b	.Lnext

.Ltest_indirection:
	tbz	x16, IND_INDIRECTION_BIT, .Ltest_destination

	/* ptr = addr */
	mov	x14, x12
	b	.Lnext

.Ltest_destination:
	tbz	x16, IND_DESTINATION_BIT, .Lnext

	/* dest = addr */
	mov	x13, x12

.Lnext:
	/* entry = *ptr++ */
	ldr	x16, [x14], #8

	/* while (!(entry & DONE)) */
	tbz	x16, IND_DONE_BIT, .Lloop

.Ldone:
	mov	x26, #4
	str	x26, [x25, #8]			/* Step = 4 (Relocation finished) */

	/* wait for writes from copy_page to finish */
	dsb	sy
	ic	iallu
	dsb	sy
	isb

	mov	x26, #5
	str	x26, [x25, #8]			/* Step = 5 (Jumping to new kernel!) */

	/* Start new image. */
	mov	x0, x18
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	br	x17

ENDPROC(arm64_relocate_new_kernel)

.ltorg

.align 3	/* To keep the 64-bit values below naturally aligned. */

.Lcopy_end:
.org	KEXEC_CONTROL_PAGE_SIZE

/*
 * arm64_relocate_new_kernel_size - Number of bytes to copy to the
 * control_code_page.
 */
.globl arm64_relocate_new_kernel_size
arm64_relocate_new_kernel_size:
	.quad	.Lcopy_end - arm64_relocate_new_kernel