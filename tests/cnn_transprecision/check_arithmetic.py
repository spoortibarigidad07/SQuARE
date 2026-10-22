#!/usr/bin/env python3
"""Independent exhaustive arithmetic oracle for the SQuARE low-precision PE."""
from fractions import Fraction

# Representation values, not bit-level RTL internals.
posit = [Fraction(0), Fraction(1,16), Fraction(1,4), Fraction(1,2),
         Fraction(1), Fraction(2), Fraction(4), Fraction(16), None,
         Fraction(-16), Fraction(-4), Fraction(-2), Fraction(-1),
         Fraction(-1,2), Fraction(-1,4), Fraction(-1,16)]

def fp4_value(x):
    s = -1 if x & 8 else 1
    e = (x >> 1) & 3
    m = x & 1
    return s * (Fraction(m, 2) if e == 0 else Fraction(2+m, 2) * 2 ** (e-1))

def fp2_value(code, zero, fmt):
    if zero:
        return Fraction(0)
    s = -1 if code & 2 else 1
    b = code & 1
    return s * (Fraction(1, 1) if not b else
                Fraction(3,2) if fmt else Fraction(1,2))

def oracle(fmt, a, b, fp2_fmt=0):
    if fmt == 0:
        if posit[a & 15] is None or posit[b & 15] is None:
            return 0, 1
        q = posit[a & 15] * posit[b & 15]
    elif fmt == 1:
        q = fp4_value(a & 15) * fp4_value(b & 15)
    elif fmt == 2:
        q = fp2_value(a & 3, bool(a & 16), fp2_fmt) * fp2_value(b & 3, bool(b & 16), fp2_fmt)
    else:
        q = sum(fp2_value((a >> (2*i)) & 3, bool(a & (16 << i)), fp2_fmt)
                * fp2_value((b >> (2*i)) & 3, bool(b & (16 << i)), fp2_fmt) for i in range(2))
    scaled = q * 256
    assert scaled.denominator == 1
    return int(scaled), 0

assert oracle(0,0x04,0x05) == (512,0)
assert oracle(0,0x08,0x04) == (0,1)
assert oracle(1,0x02,0x03) == (384,0)
assert oracle(2,0,0) == (256,0)
assert oracle(3,0x04,0x08) == (128,0)
assert oracle(3,0x04,0x08,1) == (-128,0)
assert oracle(3,0x34,0x08) == (0,0)
assert all(oracle(0,a,b)[1] == (a == 8 or b == 8) for a in range(16) for b in range(16))
assert all(-65536 <= oracle(0,a,b)[0] <= 65536 for a in range(16) for b in range(16))
assert all(-9216 <= oracle(1,a,b)[0] <= 9216 for a in range(16) for b in range(16))
assert all(-1152 <= oracle(3,a,b,fmt)[0] <= 1152
           for fmt in (0,1) for a in range(64) for b in range(64))
A = [[4,5],[2,12]]
B = [[4,3],[5,4]]
assert [[sum(oracle(0,A[r][k],B[k][c])[0] for k in range(2))
          for c in range(2)] for r in range(2)] == [[1280,640],[-448,-224]]
print('PASS: software arithmetic oracle, 2x2 matrix reference, saturation bounds')
