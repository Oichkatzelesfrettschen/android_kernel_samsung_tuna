"""usage: fill.py TREE HEXPATTERN -- hash post-paging_init RAM with the stack pre-filled."""
import hashlib
import struct
import sys

import emu2

P = '/srv/scratch/tuna-kernel-thinlto/'
path, fill = sys.argv[1], bytes.fromhex(sys.argv[2])
uc, syms, log, R, _ = emu2.run(P + path + '/vmlinux', [(0x80000000, 0x3FC00000)], stackfill=fill)
end = syms['_end']
lo = (end + 0xFFFFF) & ~0xFFFFF
h = hashlib.md5()
for rb, re_, _p in sorted(uc.mem_regions()):
    for base in range(rb, re_ + 1, 0x100000):
        if base >= 0xD0000000 or base < 0xC0000000 or 0xC0008000 <= base < lo:
            continue
        arr = struct.unpack('<%dI' % 0x40000, bytes(uc.mem_read(base, 0x100000)))
        h.update(struct.pack('<%dI' % len(arr), *[0xDEADBEEF if 0xC0008000 <= w < end + 0x2000 else w for w in arr]))
print(path, sys.argv[2], h.hexdigest(), [x for x in log if x[0] in ('UCERR', 'INTR', 'BUG')])
