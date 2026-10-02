"""Run sanity_check_meminfo, arm_memblock_init and paging_init from a tuna vmlinux in Unicorn.

SMC and cp15 cache operations are stubbed; every other function is the real image code.
"""
import struct

from elftools.elf.elffile import ELFFile
from unicorn import (UC_ARCH_ARM, UC_HOOK_CODE, UC_HOOK_INTR, UC_HOOK_MEM_UNMAPPED, UC_MODE_ARM,
                     Uc, UcError)
from unicorn.arm_const import (UC_CPU_ARM_CORTEX_A9,UC_ARM_REG_CP_REG, UC_ARM_REG_CPSR, UC_ARM_REG_LR, UC_ARM_REG_PC,
                               UC_ARM_REG_R0, UC_ARM_REG_SP)


def run(vmlinux, banks, sctlr=0x10C5387D, stackfill=None):
    syms = {}
    with open(vmlinux, 'rb') as f:
        elf = ELFFile(f)
        for s in elf.get_section_by_name('.symtab').iter_symbols():
            syms[s.name] = s['st_value']
        uc = Uc(UC_ARCH_ARM, UC_MODE_ARM)
        uc.ctl_set_cpu_model(UC_CPU_ARM_CORTEX_A9)
        pages = set()

        def mapp(addr, size=0x1000):
            a = addr & ~0xFFFFF
            e = (addr + size + 0xFFFFF) & ~0xFFFFF
            while a < e:
                if a not in pages:
                    uc.mem_map(a, 0x100000)
                    pages.add(a)
                a += 0x100000

        alloc = [s for s in elf.iter_sections() if s['sh_flags'] & 2 and s['sh_addr'] and s['sh_size']]
        for sec in alloc:
            mapp(sec['sh_addr'], sec['sh_size'])
        for sec in alloc:
            if sec['sh_type'] == 'SHT_PROGBITS':
                uc.mem_write(sec['sh_addr'], sec.data())
    mapp(0xC0004000, 0x4000)
    mapp(0xD0000000, 0x20000)
    mapp(0xC0E00000, 0x100000)
    uc.hook_add(UC_HOOK_MEM_UNMAPPED, lambda uc, a, ad, sz, v, u: (mapp(ad, sz), True)[1])

    def W(a, v):
        uc.mem_write(a, struct.pack('<I', v & 0xFFFFFFFF))

    def R(a):
        return struct.unpack('<I', uc.mem_read(a, 4))[0]

    # head.S-style 1 MiB section maps of the kernel image, virtual and identity
    for i in range(0xB0):
        W(0xC0004000 + (0xC00 + i) * 4, (0x80000000 + i * 0x100000) | 0x10C0E)
        W(0xC0004000 + (0x800 + i) * 4, (0x80000000 + i * 0x100000) | 0x10C0E)
    W(syms['cr_alignment'], sctlr)
    W(syms['cr_no_alignment'], sctlr)
    uc.reg_write(UC_ARM_REG_CP_REG, (15, 0, 0, 1, 0, 0, 0, sctlr & ~0x1005))
    mi = syms['meminfo']
    W(mi, len(banks))
    for i, (s, z) in enumerate(banks):
        W(mi + 4 + 12 * i, s)
        W(mi + 8 + 12 * i, z)
        W(mi + 12 + 12 * i, 0)

    log = []
    stubs = {}

    def ret(uc, val=None):
        if val is not None:
            uc.reg_write(UC_ARM_REG_R0, val)
        uc.reg_write(UC_ARM_REG_PC, uc.reg_read(UC_ARM_REG_LR))

    def cstr(a):
        s = b''
        while uc.mem_read(a, 1)[0]:
            s += bytes([uc.mem_read(a, 1)[0]])
            a += 1
        return s.decode('latin1')

    def stub(name, fn):
        if name in syms:
            stubs[syms[name]] = fn

    stub('cpu_architecture', lambda uc: ret(uc, 9))
    stub('printk', lambda uc: (log.append(('printk', cstr(uc.reg_read(UC_ARM_REG_R0)))), ret(uc, 0)))
    stub('__bug', lambda uc: (log.append(('BUG',)), uc.emu_stop()))
    stub('panic', lambda uc: (log.append(('PANIC', cstr(uc.reg_read(UC_ARM_REG_R0)))), uc.emu_stop()))
    for n in ('dump_stack', 'warn_slowpath_null', 'warn_slowpath_fmt', '__dump_stack'):
        stub(n, lambda uc: ret(uc, 0))
    flush_stub = 0xC0E08000
    for i in range(12):  # struct cpu_cache_fns: every method returns immediately
        W(syms['cpu_cache'] + 4 * i, flush_stub)
    stubs[flush_stub] = lambda uc: ret(uc, 0)

    def h_code(uc, addr, size, ud):
        if addr in stubs:
            stubs[addr](uc)

    uc.hook_add(UC_HOOK_CODE, h_code)

    def h_intr(uc, n, u):
        if n == 13:  # SMC to the secure monitor: return 0
            uc.reg_write(UC_ARM_REG_R0, 0)
            return
        log.append(('INTR', n, hex(uc.reg_read(UC_ARM_REG_PC))))
        uc.emu_stop()

    uc.hook_add(UC_HOOK_INTR, h_intr)
    uc.mem_write(0xC0E0C000, b'\x00\x00\xa0\xe1')  # nop landing pad

    def call(name, args=()):
        for i, a in enumerate(args):
            uc.reg_write(UC_ARM_REG_R0 + i, a)
        uc.reg_write(UC_ARM_REG_SP, 0xD0018000)
        uc.reg_write(UC_ARM_REG_LR, 0xC0E0C000)
        uc.reg_write(UC_ARM_REG_CPSR, 0x13)
        if stackfill is not None:
            uc.mem_write(0xD0010000, stackfill * (0x8000 // len(stackfill)))
        try:
            uc.emu_start(syms[name], 0xC0E0C000, count=50000000)
            log.append(('END', name, hex(uc.reg_read(UC_ARM_REG_PC))))
        except UcError as e:
            log.append(('UCERR', name, str(e), hex(uc.reg_read(UC_ARM_REG_PC))))

    mdesc = syms['__mach_desc_TUNA']
    call('sanity_check_meminfo')
    call('arm_memblock_init', (mi, mdesc))
    call('paging_init', (mdesc,))
    return uc, syms, log, R, mapp
