"""usage: diff_states.py A B -- compare r2_A.pkl and r2_B.pkl outside the kernel image,
masking words that point into the image."""
import pickle
import sys


def load(k):
    with open('r2_%s.pkl' % k, 'rb') as f:
        return pickle.load(f)


a, b = sys.argv[1:3]
la, wa, _ia, ea = load(a)
lb, wb, _ib, eb = load(b)
lo = max(ea, eb) + 0x1000


def m(w, e):
    return 0xDEADBEEF if 0xC0008000 <= w < e + 0x2000 else w


ks = {x for x in set(wa) | set(wb) if x >= lo or 0xC0004000 <= x < 0xC0008000}
d = sorted((x, m(wa.get(x, 0), ea), m(wb.get(x, 0), eb)) for x in ks if m(wa.get(x, 0), ea) != m(wb.get(x, 0), eb))
print(a, 'vs', b, 'considered', len(ks), 'diff words', len(d), 'log equal', la == lb)
for x, p, q in d[:12]:
    print('  %08x %08x %08x' % (x, p, q))
