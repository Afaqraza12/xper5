/*
 * kspatch - on-device symbol patcher for the SOG05 (5.4.210-qgki) KernelSU LKM.
 *
 * Replaces scripts/resolve_symbols.py so the one-click pipeline needs no PC:
 * resolves the fixed list of unexported kernel symbols that the KernelSU LKM
 * imports, converts them from SHN_UNDEF to SHN_ABS using the live KASLR slide,
 *   live_addr = ref_addr + (live_text_base - ref_text_base)
 * and writes the patched .ko next to the input.
 *
 * ref_text_base is the baseline this device's kallsyms was captured at:
 *   _text = 0xffffffed12080000, so ref_text_base = 0xffffffed12000000
 * which matches KIMAGE_TEXT_BASE in the exploit target.h. The 34 symbol
 * reference addresses are baked in below (captured from kallsyms.txt) so the
 * tool needs no external symbol file on the device.
 *
 * Usage: kspatch <in.ko> <out.ko> <live_text_base_hex>
 * Exit: 0 ok, non-zero on error. Prints one line per patched symbol.
 */
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#if defined(__ANDROID__)
#include <elf.h>
#else
/* Minimal ELF64 definitions so this builds on hosts without elf.h (e.g. macOS)
 * for local verification. On Android/NDK the system <elf.h> is used instead. */
#define ELFMAG "\177ELF"
#define SELFMAG 4
#define EI_CLASS 4
#define ELFCLASS64 2
#define EM_AARCH64 183
#define SHT_SYMTAB 2
#define SHN_UNDEF 0
#ifndef SHN_ABS
#define SHN_ABS 0xfff1
#endif
typedef uint16_t Elf64_Half;
typedef uint32_t Elf64_Word;
typedef uint64_t Elf64_Addr;
typedef uint64_t Elf64_Off;
typedef uint64_t Elf64_Xword;
typedef unsigned char Elf64_Ident[16];
typedef Elf64_Half Elf64_Section;
typedef struct __attribute__((packed)) {
  Elf64_Ident e_ident;
  Elf64_Half e_type, e_machine;
  Elf64_Word e_version;
  Elf64_Addr e_entry;
  Elf64_Off e_phoff, e_shoff;
  Elf64_Word e_flags;
  Elf64_Half e_ehsize, e_phentsize, e_phnum, e_shentsize, e_shnum, e_shstrndx;
} Elf64_Ehdr;
typedef struct __attribute__((packed)) {
  Elf64_Word sh_name, sh_type;
  Elf64_Xword sh_flags;
  Elf64_Addr sh_addr;
  Elf64_Off sh_offset, sh_size;
  Elf64_Word sh_link, sh_info;
  Elf64_Xword sh_addralign, sh_entsize;
} Elf64_Shdr;
typedef struct __attribute__((packed)) {
  Elf64_Word st_name;
  unsigned char st_info, st_other;
  Elf64_Section st_shndx;
  Elf64_Addr st_value;
  Elf64_Xword st_size;
} Elf64_Sym;
#endif

#ifndef SHN_ABS
#define SHN_ABS 0xfff1
#endif

/* Baseline the reference addresses below were captured at (kallsyms.txt). */
#define REF_TEXT_BASE 0xffffffed12000000ULL

struct refsym {
  const char *name;
  uint64_t ref; /* absolute address at REF_TEXT_BASE */
};

/* The 34 unexported symbols resolved by scripts/resolve_symbols.py. */
static const struct refsym kRefSyms[] = {
    {"do_mount", 0xffffffed1256d854ULL},
    {"strncpy_from_unsafe_user", 0xffffffed124af990ULL},
    {"task_work_add", 0xffffffed12321e80ULL},
    {"ksys_umount", 0xffffffed1256beb0ULL},
    {"__tracepoint_sys_enter", 0xffffffed14d263f0ULL},
    {"selinux_blob_sizes", 0xffffffed14395ff4ULL},
    {"ns_get_path", 0xffffffed1258a854ULL},
    {"__arm64_sys_setns", 0xffffffed12328cd4ULL},
    {"__arm64_sys_close", 0xffffffed1253ab60ULL},
    {"set_fs_pwd", 0xffffffed12588bbcULL},
    {"__arm64_sys_unshare", 0xffffffed122f2828ULL},
    {"mntns_operations", 0xffffffed1428a780ULL},
    {"put_seccomp_filter", 0xffffffed12409140ULL},
    {"alloc_uid", 0xffffffed123080a4ULL},
    {"free_uid", 0xffffffed12307ffcULL},
    {"ext4_unregister_sysfs", 0xffffffed1266c764ULL},
    {"selinux_state", 0xffffffed14dfc000ULL},
    {"avc_ss_reset", 0xffffffed1274ecdcULL},
    {"selnl_notify_policyload", 0xffffffed127601a0ULL},
    {"selinux_status_update_policyload", 0xffffffed12771390ULL},
    {"hashtab_search", 0xffffffed12761cc8ULL},
    {"hashtab_insert", 0xffffffed12761af0ULL},
    {"ebitmap_set_bit", 0xffffffed1276128cULL},
    {"ebitmap_get_bit", 0xffffffed12761228ULL},
    {"avtab_search_node", 0xffffffed127634a8ULL},
    {"avtab_search_node_next", 0xffffffed127635d0ULL},
    {"avtab_insert_nonunique", 0xffffffed12763150ULL},
    {"avtab_alloc", 0xffffffed1276372cULL},
    {"avtab_destroy", 0xffffffed12763640ULL},
    {"policydb_write", 0xffffffed12766594ULL},
    {"change_pid", 0xffffffed12321494ULL},
    {"tasklist_lock", 0xffffffed14ab5040ULL},
    {"uts_sem", 0xffffffed14bbc700ULL},
    {"selinux_kernel_status_page", 0xffffffed12771244ULL},
};
#define NREF (sizeof(kRefSyms) / sizeof(kRefSyms[0]))

static uint64_t slide;

static const struct refsym *find_ref(const char *name) {
  for (size_t i = 0; i < NREF; i++)
    if (strcmp(kRefSyms[i].name, name) == 0) return &kRefSyms[i];
  return NULL;
}

static void die(const char *msg) {
  fprintf(stderr, "kspatch: %s: %s\n", msg, strerror(errno));
  exit(1);
}

int main(int argc, char **argv) {
  if (argc != 4) {
    fprintf(stderr,
            "usage: %s <in.ko> <out.ko> <live_text_base_hex>\n"
            "  live_text_base: the 'text_base=' value the exploit leaked\n",
            argv[0]);
    return 2;
  }
  const char *in_path = argv[1];
  const char *out_path = argv[2];
  char *endp = NULL;
  unsigned long long live = strtoull(argv[3], &endp, 16);
  if (endp == argv[3] || *endp != '\0' || live < 0xffff000000000000ULL) {
    fprintf(stderr, "kspatch: bad live_text_base '%s'\n", argv[3]);
    return 2;
  }
  slide = (uint64_t)live - REF_TEXT_BASE;
  fprintf(stderr, "kspatch: live=0x%016llx ref=0x%016llx slide=0x%016llx\n",
          (unsigned long long)live, (unsigned long long)REF_TEXT_BASE,
          (unsigned long long)slide);

  int fd = open(in_path, O_RDONLY);
  if (fd < 0) die(in_path);
  struct stat st;
  if (fstat(fd, &st) != 0) die("fstat");
  const size_t sz = (size_t)st.st_size;
  if (sz < sizeof(Elf64_Ehdr)) {
    fprintf(stderr, "kspatch: %s is not an ELF64 object\n", in_path);
    return 1;
  }
  unsigned char *buf = malloc(sz);
  if (!buf) die("malloc");
  if (read(fd, buf, sz) != (ssize_t)sz) die("read");
  close(fd);

  Elf64_Ehdr *eh = (Elf64_Ehdr *)buf;
  if (memcmp(eh->e_ident, ELFMAG, SELFMAG) != 0 ||
      eh->e_ident[EI_CLASS] != ELFCLASS64 ||
      eh->e_machine != EM_AARCH64) {
    fprintf(stderr, "kspatch: %s is not an arm64 ELF64 object\n", in_path);
    return 1;
  }
  Elf64_Shdr *sh = (Elf64_Shdr *)(buf + eh->e_shoff);
  const char *shstr = (const char *)(buf + sh[eh->e_shstrndx].sh_offset);

  size_t patched = 0, matched = 0;
  for (size_t i = 0; i < eh->e_shnum; i++) {
    if (sh[i].sh_type != SHT_SYMTAB) continue;
    Elf64_Sym *sym = (Elf64_Sym *)(buf + sh[i].sh_offset);
    size_t count = sh[i].sh_size / sizeof(Elf64_Sym);
    const char *strtab = (const char *)(buf + sh[sh[i].sh_link].sh_offset);
    (void)shstr;
    for (size_t j = 0; j < count; j++) {
      const char *name = strtab + sym[j].st_name;
      const struct refsym *r = find_ref(name);
      if (!r) continue;
      /* The shipped .ko may arrive either pristine (UND) or already patched to
       * the reference base (ABS at r->ref). Handle both by rebasing onto
       * r->ref + slide so a re-run is idempotent for the same boot. */
      if (sym[j].st_shndx != SHN_UNDEF && sym[j].st_shndx != SHN_ABS) continue;
      matched++;
      uint64_t live_addr = r->ref + slide;
      sym[j].st_value = live_addr;
      sym[j].st_shndx = (Elf64_Section)SHN_ABS;
      patched++;
      printf("  [+] %-36s -> 0x%016llx\n", name,
             (unsigned long long)live_addr);
    }
  }

  fprintf(stderr, "kspatch: matched %zu/%zu expected symbols, patched %zu\n",
          matched, NREF, patched);
  if (matched != NREF) {
    fprintf(stderr,
            "kspatch: WARNING: expected %zu symbols, matched %zu\n", NREF,
            matched);
  }
  if (patched == 0) {
    fprintf(stderr, "kspatch: nothing patched, refusing to write output\n");
    return 1;
  }

  int ofd = open(out_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
  if (ofd < 0) die(out_path);
  if (write(ofd, buf, sz) != (ssize_t)sz) die("write");
  close(ofd);
  free(buf);
  fprintf(stderr, "kspatch: wrote %s (%zu bytes)\n", out_path, sz);
  return 0;
}
