#!/usr/bin/env python3
"""
resolve_symbols.py - Resolves unexported kernel symbols in kernelsu.ko
by converting them from SHN_UNDEF to SHN_ABS using live kallsyms addresses.
"""
import struct
import sys
import os
import gzip

SHN_UNDEF = 0
SHN_ABS = 0xfff1
SHT_SYMTAB = 2

def resolve_symbols(ko_path, kallsyms_path, symvers_path="Module.symvers"):
    print(f"[*] Resolving symbols for {ko_path} using {kallsyms_path}...")
    if not os.path.exists(ko_path):
        print(f"[-] Error: {ko_path} not found!")
        return False
    if not os.path.exists(kallsyms_path):
        print(f"[-] Error: {kallsyms_path} not found!")
        return False

    exported = set()
    if symvers_path and os.path.exists(symvers_path):
        with open(symvers_path, "r") as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) >= 2:
                    exported.add(parts[1])
        print(f"[*] Loaded {len(exported)} exported symbols from {symvers_path} (preserved as SHN_UNDEF)")

    kallsyms = {}
    opener = gzip.open(kallsyms_path, "rt") if kallsyms_path.endswith(".gz") else open(kallsyms_path, "r")
    with opener as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) >= 3:
                name = parts[2]
                addr = int(parts[0], 16)
                if name not in kallsyms:
                    kallsyms[name] = addr

    ref_kallsyms = {}
    ref_path = "kallsyms.txt" if os.path.exists("kallsyms.txt") else ("kallsyms.gz" if os.path.exists("kallsyms.gz") else None)
    if ref_path and os.path.abspath(ref_path) != os.path.abspath(kallsyms_path):
        ref_opener = gzip.open(ref_path, "rt") if ref_path.endswith(".gz") else open(ref_path, "r")
        with ref_opener as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) >= 3:
                    if parts[2] not in ref_kallsyms:
                        ref_kallsyms[parts[2]] = int(parts[0], 16)

    kaslr_slide = 0
    if "_text" in kallsyms and "_text" in ref_kallsyms:
        kaslr_slide = kallsyms["_text"] - ref_kallsyms["_text"]
        print(f"[*] Detected live KASLR slide: 0x{kaslr_slide:x} (live _text: 0x{kallsyms['_text']:016x}, ref _text: 0x{ref_kallsyms['_text']:016x})")

    with open(ko_path, "rb") as f:
        data = bytearray(f.read())

    # Read ELF header (64-bit ELF)
    e_shoff = struct.unpack_from("<Q", data, 40)[0]
    e_shentsize = struct.unpack_from("<H", data, 58)[0]
    e_shnum = struct.unpack_from("<H", data, 60)[0]
    e_shstrndx = struct.unpack_from("<H", data, 62)[0]

    # Find .symtab and its associated string table (.strtab)
    symtab_offset = 0
    symtab_size = 0
    symtab_entsize = 0
    strtab_offset = 0

    for i in range(e_shnum):
        shdr = e_shoff + i * e_shentsize
        sh_type = struct.unpack_from("<I", data, shdr + 4)[0]
        sh_offset = struct.unpack_from("<Q", data, shdr + 24)[0]
        sh_size = struct.unpack_from("<Q", data, shdr + 32)[0]
        sh_link = struct.unpack_from("<I", data, shdr + 40)[0]
        sh_entsize = struct.unpack_from("<Q", data, shdr + 56)[0]

        if sh_type == SHT_SYMTAB:
            symtab_offset = sh_offset
            symtab_size = sh_size
            symtab_entsize = sh_entsize or 24
            link_shdr = e_shoff + sh_link * e_shentsize
            strtab_offset = struct.unpack_from("<Q", data, link_shdr + 24)[0]
            break

    if not symtab_offset or not strtab_offset:
        print("[-] Error: .symtab or .strtab not found in ELF!")
        return False

    def get_str(idx):
        end = data.find(b"\x00", strtab_offset + idx)
        return data[strtab_offset + idx:end].decode("latin-1")

    num_syms = symtab_size // symtab_entsize
    resolved_count = 0
    still_undef = []

    for i in range(num_syms):
        sym_offset = symtab_offset + i * symtab_entsize
        st_name, st_info, st_other, st_shndx, st_value, st_size = struct.unpack_from("<IBBHQQ", data, sym_offset)

        if st_name != 0:
            name = get_str(st_name)
            if name in exported:
                # Keep exported symbols as SHN_UNDEF with value=0 for kernel loader dynamic resolution
                if st_shndx != SHN_UNDEF or st_value != 0:
                    struct.pack_into("<IBBHQQ", data, sym_offset, st_name, st_info, st_other, SHN_UNDEF, 0, st_size)
                still_undef.append(name)
            elif (st_shndx == SHN_UNDEF or st_shndx == SHN_ABS):
                addr = None
                if name in kallsyms and kallsyms[name] != 0:
                    addr = kallsyms[name]
                elif name in ref_kallsyms and kaslr_slide != 0:
                    addr = ref_kallsyms[name] + kaslr_slide

                if addr is not None:
                    struct.pack_into("<IBBHQQ", data, sym_offset, st_name, st_info, st_other, SHN_ABS, addr, st_size)
                    resolved_count += 1
                    print(f"  [+] Resolved unexported {name} -> 0x{addr:016x} (SHN_ABS)")
                elif st_shndx == SHN_UNDEF:
                    still_undef.append(name)

    print(f"[*] Successfully resolved {resolved_count} unexported symbols to SHN_ABS!")
    if still_undef:
        print(f"[*] Remaining {len(still_undef)} undefined symbols (resolved via kernel export table at insmod):")
        for u in still_undef[:15]:
            print(f"    - {u}")

    with open(ko_path, "wb") as f:
        f.write(data)

    print(f"[SUCCESS] {ko_path} patched with absolute symbol addresses.")
    return True

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: resolve_symbols.py <kernelsu.ko> <kallsyms.txt> [Module.symvers]")
        sys.exit(1)
    symvers = sys.argv[3] if len(sys.argv) > 3 else "Module.symvers"
    resolve_symbols(sys.argv[1], sys.argv[2], symvers)
