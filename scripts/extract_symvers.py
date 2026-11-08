#!/usr/bin/env python3
"""
extract_symvers.py - Generates Module.symvers for Sony Xperia 5 III (SOG05)
Kernel: 5.4.210-qgki-g55a0c74ba38a
"""
import struct
import sys
import os

KERNEL_PATH = "/Users/afaqraza/kernel"
KALLSYMS_PATH = "kallsyms.txt"
OUTPUT_PATH = "Module.symvers"

def main():
    if not os.path.exists(KERNEL_PATH):
        print(f"Error: {KERNEL_PATH} not found.")
        sys.exit(1)
    if not os.path.exists(KALLSYMS_PATH):
        print(f"Error: {KALLSYMS_PATH} not found.")
        sys.exit(1)

    print(f"[*] Reading kernel image from {KERNEL_PATH}...")
    with open(KERNEL_PATH, "rb") as f:
        kernel_data = f.read()

    print(f"[*] Parsing kallsyms from {KALLSYMS_PATH}...")
    with open(KALLSYMS_PATH, "r") as f:
        lines = f.readlines()

    # Identify bounds from kallsyms
    ksymtab_symbols = []
    ksymtab_gpl_symbols = []

    in_normal = False
    in_gpl = False

    for line in lines:
        parts = line.strip().split()
        if len(parts) < 3:
            continue
        addr_str, stype, name = parts[0], parts[1], parts[2]
        
        if name == "__start___ksymtab":
            in_normal = True
            continue
        elif name == "__stop___ksymtab":
            in_normal = False
            in_gpl = True
            continue
        elif name == "__stop___ksymtab_gpl":
            in_gpl = False
            continue

        if in_normal and name.startswith("__ksymtab_"):
            sym = name[len("__ksymtab_"):]
            ksymtab_symbols.append(sym)
        elif in_gpl and name.startswith("__ksymtab_"):
            sym = name[len("__ksymtab_"):]
            ksymtab_gpl_symbols.append(sym)

    print(f"[+] Found {len(ksymtab_symbols)} standard exported symbols.")
    print(f"[+] Found {len(ksymtab_gpl_symbols)} GPL exported symbols.")

    # File offsets calculated from live virtual addresses:
    # _text: 0xffffffed12080000
    # __start___kcrctab: 0xffffffed144cd8f8 -> file offset 0x244d8f8
    # __start___kcrctab_gpl: 0xffffffed144d4cb8 -> file offset 0x2454cb8
    normal_crc_off = 0x244d8f8
    gpl_crc_off = 0x2454cb8

    symvers_lines = []

    # Process standard symbols
    for i, sym in enumerate(ksymtab_symbols):
        pos = normal_crc_off + i * 4
        crc = struct.unpack("<I", kernel_data[pos:pos+4])[0]
        symvers_lines.append(f"0x{crc:08x}\t{sym}\tvmlinux\tEXPORT_SYMBOL\n")

    # Process GPL symbols
    for i, sym in enumerate(ksymtab_gpl_symbols):
        pos = gpl_crc_off + i * 4
        crc = struct.unpack("<I", kernel_data[pos:pos+4])[0]
        symvers_lines.append(f"0x{crc:08x}\t{sym}\tvmlinux\tEXPORT_SYMBOL_GPL\n")

    print(f"[*] Writing {len(symvers_lines)} total symbol versions to {OUTPUT_PATH}...")
    with open(OUTPUT_PATH, "w") as f:
        f.writelines(symvers_lines)

    print(f"[SUCCESS] {OUTPUT_PATH} generated successfully! Size: {os.path.getsize(OUTPUT_PATH)} bytes")

if __name__ == "__main__":
    main()

