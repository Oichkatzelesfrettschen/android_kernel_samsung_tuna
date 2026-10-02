"""usage: one.py LABEL TREE -- emulate TREE (relative to /srv/scratch/tuna-kernel-thinlto) and
store the post-paging_init RAM words in r2_LABEL.pkl in the current directory."""
import pickle
import struct
import sys

import emu2

P = '/srv/scratch/tuna-kernel-thinlto/'
label, path = sys.argv[1], sys.argv[2]
uc, syms, log, R, mapp = emu2.run(P + path + '/vmlinux', [(0x80000000, 0x3FC00000)])
end = syms['_end']
lo = (end + 0xFFFFF) & ~0xFFFFF
words = {}
for rb, re_, _p in list(uc.mem_regions()):
    for base in range(rb, re_ + 1, 0x100000):
        if base >= 0xD0000000 or base < 0xC0000000 or 0xC0008000 <= base < lo:
            continue
        data = bytes(uc.mem_read(base, 0x100000))
        if not any(data):
            continue
        for i, w in enumerate(struct.unpack('<%dI' % (len(data) // 4), data)):
            if w:
                words[base + 4 * i] = w
info = {n: R(syms[n]) for n in ('max_low_pfn', 'max_pfn', 'high_memory', 'empty_zero_page', 'top_pmd', 'mem_map')
        if n in syms}
with open('r2_%s.pkl' % label, 'wb') as f:
    pickle.dump((log, words, info, end), f)
print(label, [x for x in log if x[0] != 'printk'], len(words), {k: hex(v) for k, v in info.items()})
