# Clang 22 non-LTO hang before console_init: arch/arm/mm/mmu.o pair analysis

Scope: static analysis and host-side emulation of commit a001a3b (Galaxy Nexus tuna, OMAP4460, Cortex-A9
SMP, Linux 3.0.101, ARM mode, `.config` shared by all trees). No device was touched and no tree was rebuilt.
The commit lives on `research/tuna-decompressor-watchdog`; line and address references below are to that
commit and to the Clang non-LTO tree `tuna-w8-clang22-nonlto-wdt-bffe45d`.

## Finding

The code `mmu.o` generates for the boot path is semantically equal to GCC's. The Clang and GCC images, and
every hanging and booting hybrid tested, reach a bit-identical RAM state after `sanity_check_meminfo()`,
`arm_memblock_init()` and `paging_init()` (including `tuna_reserve`, `tuna_map_io`, `bootmem_init` and
`free_area_init_node`). The hang therefore sits in something the architectural memory state does not
capture: instruction addresses and timing against live TLB/cache state, an event after `paging_init()`, or
hardware behavior while page tables are in flux. No source-level miscompile was found, so no fix exists.

Confidence: high that the `mmu.c` data path is equivalent (observed; E1 reproduces from the scripts in
`docs/clang-nonlto-mmu-pair-emu/`); low (about 30 percent for the top-ranked hypothesis) on which hardware
or layout mechanism turns the equal state into a hang.

## Tools used and why

| Tool | Use |
| --- | --- |
| `llvm-objdump -dr`, `llvm-nm`, `llvm-readelf -S/-r` | Disassembly, relocations and section maps of `mmu.o` and vmlinux for both compilers. |
| Unicorn 2.1.4 (Cortex-A9 model) + pyelftools | Run the real `sanity_check_meminfo`, `arm_memblock_init`, `paging_init` from each vmlinux ELF and diff the resulting RAM. This replaces reading register-allocation noise with a semantic diff. |
| `clang -fsyntax-only -Wuninitialized -Wsometimes-uninitialized -Wconditional-uninitialized` on every `arch/arm/mm/*.c` compile line | Screen for uninitialized-stack candidates. No warning outside `include/linux/capability.h`. |
| `diff` on normalized `llvm-objdump` text | Compare the assembler objects between IAS and GNU as. |

Not used: ghidra/retdec/radiff2/diffoscope (the emulator gave a stronger semantic comparison than a
decompiler side-by-side), pahole/dwarfdump (objects carry no DWARF; struct offsets were checked against the
disassembly instead).

## Evidence

E1. Post-init RAM equality (observed, reproducible with `one.py` + `diff_states.py`). The emulator loads
each vmlinux, seeds `meminfo` (one bank at 0x80000000, size 0x3fc00000, split at `vmalloc_min` into lowmem
plus highmem), runs the three setup_arch functions with the real `__mach_desc_TUNA` (reserve and map_io
execute; SMC and cp15 cache ops are stubbed), then diffs swapper_pg_dir, every allocated page table, the
vectors page, `mem_map`, bootmem and `contig_page_data`, masking words that point into the kernel image.
Real ATAG banks are not modeled.

| Pair | Verdict on device | Differing words outside the image |
| --- | --- | --- |
| full Clang vs h13-mmu (Clang, GCC mmu.o) | hang vs boot | 0 of 1262897 |
| i5-amm (GCC + Clang arch/arm/mm/*) vs i4-akern | hang vs boot | 0 of 1258417 |
| i5-amm vs h16-allgcc-but-mmu | hang vs boot | 0 of 1258417 |
| full Clang vs full GCC | hang vs boot | 10785, all `struct page.flags` 0x40000000 on pages the differing `_end` moves between reserved and free; expected |

The printk sequence is identical in all runs. `empty_zero_page`, `top_pmd`, `max_low_pfn`, `max_pfn` and
`high_memory` match.

E2. Store and maintenance order (observed with an event-logging variant of the harness that is not retained
here). Clang and GCC `mmu.o` produce the same ordered sequence of 4100 stores into swapper_pg_dir, the same
2051 `mcr c7,c10,1` cleans, 388 `dsb`, one `mcr c8,c3,0`, one `mcr c7,c1,6` and one `isb`. The set of
pgd/PTE cache lines left dirty at the end is identical (511 lines: zeroed vector and table pages that
`flush_cache_all()` cleans).

E3. Stack-garbage independence (observed, `fill.py`). Filling the stack with 0x00, 0xff, 0xa5 and 0x5a
before each call yields one RAM hash on the Clang image, which excludes an uninitialized stack read in the
early mm path.

E4. Alignment (observed with a memory-hook variant, not retained). Zero unaligned loads or stores in the
emulated path in either compiler, so the `ldrd`/`strd`/`ldm`/`stm` forms Clang emits (`ldrd` at mmu.o+0x6e0,
0xa1c, 0xb80; `strd` at 0xf64) do not fault.

E5. Assembler objects (observed). Normalized disassembly of `cache-v7.o`, `proc-v7.o`, `tlb-v7.o`,
`abort-ev7.o`, `pabort-v7.o` differs only in constant materialization: `movw r4,#0x3ff` / `movw r7,#0x7fff`
(`v7_flush_dcache_all`) and `movw r10,#0xc08/#0xc09` (`__v7_setup`) against literal-pool `ldr`, plus a
`.word` versus `.short/.byte` rendering of a string. Instruction semantics match.

## Hazard-class audit of mmu.c

| Class | Result |
| --- | --- |
| asm without `"memory"` clobber around page-table stores | Source hazard exists: `flush_pmd_entry()`/`clean_pmd_entry()` (arch/arm/include/asm/tlbflush.h:517-538) declare only `"cc"`, and `get_cr()` (asm/system.h:193) is a non-volatile asm. Clang keeps every store ahead of its `mcr` in this build (mmu.o+0x680, 0x6c4, 0x734, 0xc44, 0xe8c, 0xf68), and E2 confirms equal order. Not the trigger here; a latent risk for any other Clang object. |
| Store order to pmd/pte vs maintenance | Equal (E2). |
| UB (pmd[1] pair writes, `__va`/`__pa` arithmetic, pmd/u32 aliasing) | `pmd_clear` writes pmd[0], pmd[1] with two `str` (prepare_page_table 0x668-0x674, devicemaps_init 0xc28-0xc30); `early_pte_alloc` uses one `strd` (0xf64). All writes land inside the 16 KiB pgd or the 4 KiB tables (E1). Loop bounds (0xBF000000 module boundary, VMALLOC_END wrap to 0) recomputed from the disassembly equal the source. |
| Struct layout and enum size | `membank` stride 12, `memblock.memory.regions` at +0x10, `cache_policies` stride 28, `mem_type` stride 16 appear in the disassembly exactly as the headers define them. |
| `__init`/`__initdata` on shared symbols | `mmu.o` places the same symbol classes in `.init.text`, `.init.data`, `.init.rodata`, `.init.setup` for both compilers; `get_mem_type` and `phys_mem_access_prot` sit in `.text`. Clang inlines the non-init `alloc_init_pud` into `create_mapping`, as GCC does. |
| Weak symbols | None in mmu.c or init.c. |
| C-to-asm calls outside AAPCS | `cpu_v7_set_pte_ext` (r3 only), `__memzero` (r2,r3,ip,lr) and `__aeabi_memmove4` (branch to `memmove`) preserve r4-r11; Clang keeps live values in r4-r7 across them and E1 shows correct results. Clang emits `bl mcount` (old ABI, CONFIG_OLD_MCOUNT) only in `get_mem_type` and `phys_mem_access_prot`; `mcount_exit` reloads lr from `[fp,#-4]` (a saved r10 in an AAPCS frame) but returns through the popped pc, so the value is dead. A build without `-pg` still hangs, which agrees. |
| Globals cached or elided | `top_pmd`, `vectors_page`, `pkmap_page_table`, `empty_zero_page`, `pgprot_user/kernel` are stored once each (mmu.o+0x774, 0x78c, 0x7c0, 0xa10, 0xa24) and E1 shows the values. |

Position-independence note (observed): both compilers emit PIC access (Clang `R_ARM_GOT_PREL` x21, GCC
`R_ARM_GOT32` x17). `.got` sits inside `.text` (vmlinux.lds.S:136) and vmlinux carries no `.rel.got`; the
link asserts `SIZEOF(.rel.got) == 0`. Static GOT entries are absolute link-time addresses, valid once the
kernel runs at 0xc0xxxxxx.

## What the device data implies

Observed: a hang needs Clang `mmu.o` plus at least one other Clang object in `arch/arm/mm`, while E1 shows
the outputs of those objects equal to the GCC ones in the modeled path. The remaining differences between a
hanging and a booting pair are code addresses (mmu.o `.text` grows by 0x18 bytes under GCC, which moves
every later `.text` symbol by 0x20: `cpu_v7_set_pte_ext` c008a96c vs c008a98c, `v7_flush_kern_cache_all`
c008a378 vs c008a398 in full Clang vs h13-mmu), instruction mix and timing, and any event not modeled
(SMC, cp15 side effects, real ATAG banks, cache and TLB contents).

The page-table transition that runs while executing from the section being rewritten is the natural place
for such a coupling: `map_lowmem()` replaces the head.S mapping of the kernel (0x11c0e = TEX1 C B S,
AP=11) with the `MT_MEMORY` mapping (0x1140e, AP=01) for the very section that holds `create_mapping`,
`alloc_init_section` and the `.init.text` of `mmu.o`, and no TLB invalidate follows until
`devicemaps_init()` ends (`mcr c8,c3,0` at mmu.o+0xcb0).

## Ranked hypotheses per pending device group

All four groups share the same lead mechanism (timing or address coupling, since state is equal). The
ranking uses proximity to the moment page tables are in flux and to `mmu.o` code, so a result in the
"wrong" order is itself evidence for a layout effect and against a code-path effect.

1. `{asm objects}` (proc-v7, cache-v7, tlb-v7, abort-ev7, pabort-v7). Pair: mmu.o `alloc_init_pte` (0xeac)
   -> `cpu_v7_set_pte_ext` (proc-v7.S), and `devicemaps_init` (mmu.o+0xcac..0xccc) ->
   `v7_flush_kern_cache_all` via `cpu_cache+4`. These are the only mm objects that run between the pmd
   rewrite and the TLB invalidate, and the Clang forms change code size (cache-v7.o 165 vs 167 lines,
   proc-v7.o 164 vs 168) and so the shift of every later symbol. A hang here favors instruction-fetch or
   maintenance timing across the AP rewrite. Prediction if true: this group hangs alone with Clang mmu.o.
2. `{init.o}`. Pair: mmu.o `paging_init` (0x7a0 `bl bootmem_init`) and `arm_mm_memblock_reserve` (called
   from init.o). init.o is the largest early consumer of state mmu.o produced (`meminfo`, `memblock`,
   `mem_map` layout). E1 makes a data-flow cause unlikely; a hang here would point to timing or stack-depth
   layout in `bootmem_init`. Prediction if true: hang appears when init.o is Clang even with GCC asm objects.
3. `{flush, ioremap, highmem, dma-mapping, fault-armv}`. Pair: mmu.o `paging_init` ->
   `__flush_dcache_page` (mmu.o+0x7c8; flush.o reads `empty_zero_page`, `pgprot_kernel`, `top_pmd`), and
   mmu.o `get_mem_type` (+0x0, the only Clang function in `.text` with `mcount`) -> ioremap.o (runs from
   tuna map_io/SRAM init). E1 already exercises `__flush_dcache_page` and the map_io ioremap path with equal
   results. Prediction if true: hang only when flush.o and ioremap.o are both Clang.
4. `{rest}` (alignment, cache-l2x0, context, copypage-v6, extable, fault, idmap, iomap, mmap, pgd,
   proc-syms, vmregion). These run only after a fault or after console_init, except `fault.o` and
   `extable.o` when an early abort occurs. A hang here means an early abort loops silently while vectors are
   unmapped; the group least likely to matter unless the first three are clean.

Reading the four results together:
- one group hangs, others boot: the mechanism lives in that group's code and its window with `mmu.o`;
  inspect its Clang and GCC instruction sequences at the reported pair.
- several groups hang: layout or total-size dependence. A pad test then discriminates.

## Experiments that discriminate (not run: each needs a build or the device)

1. Layout probe. From the booting `h16-allgcc-but-mmu` (GCC + Clang mmu.o), insert an `.init.text` or
   `.text` pad of 0x4, 0x20, 0x100 and 0x1000 bytes ahead of `proc-v7.o`. A hang that appears at some pad
   size and disappears at another proves address or timing dependence and closes every semantic hypothesis.
2. Attribute probe. In the hanging full-Clang tree, add `local_flush_tlb_all()` plus `dsb; isb` after
   `map_lowmem()` in mmu.c and swap only the rebuilt `mmu.o` in. Boot proves the unsynchronized AP rewrite
   of the running section is the coupling (the architecturally required sequence is break-before-make with
   invalidate; the current code depends on the TLB not refilling the entry).
3. Barrier hardening (source hazard from the audit). Add `"memory"` to the `asm` in `flush_pmd_entry`,
   `clean_pmd_entry` and `get_cr`, and to the TLB/cache maintenance asm, then rebuild only the
   `arch/arm/mm` objects with Clang. This removes the one source-level hazard the audit found; E2 shows it
   is not the trigger in this build.

## Reproduce

```sh
PYTHON=${PYTHON:-python3}
cd docs/clang-nonlto-mmu-pair-emu
# one image; writes r2_LABEL.pkl in the current directory
$PYTHON one.py clang tuna-w8-clang22-nonlto-wdt-bffe45d
$PYTHON one.py h13 hybrid/h13-mmu
$PYTHON diff_states.py clang h13
# stack-fill independence
$PYTHON fill.py tuna-w8-clang22-nonlto-wdt-bffe45d a5a5a5a5
```

`one.py` and `fill.py` take a tree path relative to `/srv/scratch/tuna-kernel-thinlto/`. Requires
Unicorn 2.x and pyelftools.
