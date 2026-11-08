# kspatch

On-device replacement for `scripts/resolve_symbols.py`.

The one-click pipeline previously needed a PC only for one step: rebasing the 34
unexported kernel symbols in `kernelsu.ko` onto the live KASLR slide.

```
live_addr = ref_addr + (live_text_base - REF_TEXT_BASE)
REF_TEXT_BASE = 0xffffffed12000000   (_text = 0xffffffed12080000)
```

The 34 `ref_addr` values are baked into `kspatch.c` from this device's
`kallsyms.txt`, so the tool needs **no** external symbol files on the phone.

## Verified

Output was diffed against `resolve_symbols.py` for
`live_text_base = 0xffffffe936a00000` and the resulting `.symtab` is
byte-identical (`llvm-nm` diff empty). 34/34 symbols matched.

Handles both inputs:
- pristine `.ko` (symbols `SHN_UNDEF`) -> converted to `SHN_ABS`
- already-patched `.ko` (symbols `SHN_ABS` at ref base) -> rebased onto the slide

## Build

Android (NDK r27+):

```sh
$NDK/toolchains/llvm/prebuilt/*/bin/aarch64-linux-android31-clang \
    -O2 -static -o kspatch kspatch.c
```

Host check (macOS, no elf.h needed):

```sh
clang -O2 -o kspatch kspatch.c
```

## Usage

```sh
kspatch <in.ko> <out.ko> <live_text_base_hex>
# e.g.
kspatch kernelsu.ko /data/local/tmp/kernelsu_live.ko ffffffe936a00000
```

Exit 0 on success; prints one line per patched symbol to stdout and a summary to
stderr. Refuses to write if nothing matched.
