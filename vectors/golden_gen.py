#!/usr/bin/env python3
"""
golden_gen.py
Independent (from the RTL) golden-reference model for:
  - Posit(4, es=1)
  - FP4 (E2M1, bias=1)
  - FP2 (E1M0 / E0M1, element-level, shared exponent X factored out)

Generates exhaustive a x b (16 x 16 = 256) expected accumulator values
(single multiply-accumulate from a cleared accumulator) at a common
global fixed-point scale of 2^GLOBAL_FRAC_BITS, matching the RTL's
shared 32-bit accumulator convention in sparx_mac_unified.v.

Output: golden_<fmt>.hex  (256 lines, 8 hex digits, two's complement)
        golden_posit4_nar.hex (256 lines, 0/1 -- NaR flag expected)
"""

GLOBAL_FRAC_BITS = 8
SCALE = 1 << GLOBAL_FRAC_BITS  # 256

# ---------------------------------------------------------------
# Posit(4, es=1) decode: returns (is_zero, is_nar, sign(+1/-1), value)
# ---------------------------------------------------------------
_POSIT4_TABLE = {
    0b0000: (True,  False,  1, 0.0),
    0b0001: (False, False,  1, 0.0625),
    0b0010: (False, False,  1, 0.25),
    0b0011: (False, False,  1, 0.5),
    0b0100: (False, False,  1, 1.0),
    0b0101: (False, False,  1, 2.0),
    0b0110: (False, False,  1, 4.0),
    0b0111: (False, False,  1, 16.0),
    0b1000: (False, True,   0, 0.0),
    0b1001: (False, False, -1, 16.0),
    0b1010: (False, False, -1, 4.0),
    0b1011: (False, False, -1, 2.0),
    0b1100: (False, False, -1, 1.0),
    0b1101: (False, False, -1, 0.5),
    0b1110: (False, False, -1, 0.25),
    0b1111: (False, False, -1, 0.0625),
}

def posit4_decode(code):
    is_zero, is_nar, sign, mag = _POSIT4_TABLE[code]
    return is_zero, is_nar, sign * mag

# ---------------------------------------------------------------
# FP4 (E2M1, bias=1) decode: value = f(sign,e[1:0],m)
# ---------------------------------------------------------------
def fp4_decode(code):
    sign = (code >> 3) & 1
    e = (code >> 1) & 0b11
    m = code & 1
    if e == 0:
        val = 0.5 * m                 # subnormal
    else:
        val = (1.0 + 0.5 * m) * (2 ** (e - 1))
    return (-1.0 if sign else 1.0) * val

# ---------------------------------------------------------------
# FP2 element-level decode (shared scale X excluded, see fp2_mac.v)
# code = {sign, mode, zero, b}
# ---------------------------------------------------------------
def fp2_decode(code):
    sign = (code >> 3) & 1
    mode = (code >> 2) & 1     # 0 = E1M0, 1 = E0M1
    zero = (code >> 1) & 1
    b = code & 1
    if zero:
        mag = 0.0
    elif mode == 0:
        mag = 0.5 if b else 1.0
    else:
        mag = 1.5 if b else 1.0
    return (-1.0 if sign else 1.0) * mag

# ---------------------------------------------------------------
def to_hex32(signed_int):
    return format(signed_int & 0xFFFFFFFF, '08x')

def to_hex16(signed_int):
    return format(signed_int & 0xFFFF, '04x')

SAT16_MAX = (1 << 15) - 1   #  32767
SAT16_MIN = -(1 << 15)      # -32768

def saturate16(value_int):
    if value_int > SAT16_MAX:
        return SAT16_MAX, True
    if value_int < SAT16_MIN:
        return SAT16_MIN, True
    return value_int, False

def gen_posit4():
    lines_val, lines_nar = [], []
    for a in range(16):
        for b in range(16):
            za, na, va = posit4_decode(a)
            zb, nb, vb = posit4_decode(b)
            nar = na or nb
            if nar:
                acc = 0
            else:
                acc = round((va * vb) * SCALE)
            lines_val.append(to_hex32(acc))
            lines_nar.append('1' if nar else '0')
    return lines_val, lines_nar

def gen_fp4():
    lines = []
    for a in range(16):
        for b in range(16):
            va = fp4_decode(a)
            vb = fp4_decode(b)
            acc = round((va * vb) * SCALE)
            lines.append(to_hex32(acc))
    return lines

def rescale_from_q8(partial_q8, frac_bits):
    """Independent restatement of the RTL's adaptive-rescale logic in
    posit4_mac_ref.v / fp4_mac_ref.v: both partial-product generators
    always emit a value already scaled to fixed Q8.8 (GLOBAL_FRAC_BITS=8
    baked into each primitive, left unchanged); the wrapper then
    re-scales that fixed value to whatever frac_bits was requested via
    `rescale_shift = frac_bits - 8`, left-shifting (more precision) or
    right-shifting (less -- TRUNCATING, no rounding, consistent with
    the rest of this package) accordingly. partial_q8 here is always
    a non-negative magnitude (sign applied separately), matching the
    RTL's unsigned `partial` -- so a plain Python `>>` exactly matches
    the hardware's truncating right-shift with no negative-number
    subtlety to worry about."""
    shift = frac_bits - 8
    if shift >= 0:
        return partial_q8 << shift
    else:
        return partial_q8 >> (-shift)

def gen_posit4_adaptive(frac_bits):
    """Exhaustive 16x16 sweep at a specific adaptive frac_bits value,
    for tb_posit4_mac_ref.v's adaptive-precision checks."""
    lines_val = []
    for a in range(16):
        for b in range(16):
            za, na, va = posit4_decode(a)
            zb, nb, vb = posit4_decode(b)
            nar = na or nb
            if nar:
                acc = 0
            else:
                partial_q8 = round(abs(va * vb) * SCALE)
                sign = -1 if (va * vb) < 0 else 1
                acc = sign * rescale_from_q8(partial_q8, frac_bits)
            lines_val.append(to_hex32(acc))
    return lines_val

def gen_fp4_adaptive(frac_bits):
    """Exhaustive 16x16 sweep at a specific adaptive frac_bits value,
    for tb_fp4_mac_ref.v's adaptive-precision checks."""
    lines_val = []
    for a in range(16):
        for b in range(16):
            va = fp4_decode(a)
            vb = fp4_decode(b)
            partial_q8 = round(abs(va * vb) * SCALE)
            sign = -1 if (va * vb) < 0 else 1
            acc = sign * rescale_from_q8(partial_q8, frac_bits)
            lines_val.append(to_hex32(acc))
    return lines_val

def gen_posit4_fxp16(frac_bits):
    """Same computation as gen_posit4_adaptive, but SATURATED to a
    16-bit signed range and written as 4-hex-digit lines -- for
    posit4_mac_ref.v's new ACC_W=16 default. At frac_bits>=8, several
    single-shot products already exceed +-32767 (e.g. 16*16=256 real,
    times 2^8=65536 at frac_bits=8 alone) -- this is NOT a rare edge
    case at fxp16 width, so saturation (matching fp2_parallel_mac_ref.v's
    precedent) is load-bearing here, not decorative."""
    lines_val = []
    for a in range(16):
        for b in range(16):
            za, na, va = posit4_decode(a)
            zb, nb, vb = posit4_decode(b)
            nar = na or nb
            if nar:
                acc = 0
            else:
                partial_q8 = round(abs(va * vb) * SCALE)
                sign = -1 if (va * vb) < 0 else 1
                raw = sign * rescale_from_q8(partial_q8, frac_bits)
                acc, _ = saturate16(raw)
            lines_val.append(to_hex16(acc))
    return lines_val

def gen_fp4_fxp16(frac_bits):
    """Same as gen_posit4_fxp16 but for FP4 (no NaR concept)."""
    lines_val = []
    for a in range(16):
        for b in range(16):
            va = fp4_decode(a)
            vb = fp4_decode(b)
            partial_q8 = round(abs(va * vb) * SCALE)
            sign = -1 if (va * vb) < 0 else 1
            raw = sign * rescale_from_q8(partial_q8, frac_bits)
            acc, _ = saturate16(raw)
            lines_val.append(to_hex16(acc))
    return lines_val

def gen_fp2():
    lines = []
    for a in range(16):
        for b in range(16):
            va = fp2_decode(a)
            vb = fp2_decode(b)
            acc = round((va * vb) * SCALE)
            lines.append(to_hex32(acc))
    return lines

def gen_fp2_adaptive(frac_bits):
    """Exhaustive 16x16 sweep at a specific adaptive frac_bits value,
    for the FP2-element path inside tb_sparx_mac_unified.v -- same
    rescale-from-Q8.8 approach as gen_posit4_adaptive/gen_fp4_adaptive,
    since fp2_pp.v also bakes GLOBAL_FRAC_BITS=8 in internally."""
    lines_val = []
    for a in range(16):
        for b in range(16):
            va = fp2_decode(a)
            vb = fp2_decode(b)
            partial_q8 = round(abs(va * vb) * SCALE)
            sign = -1 if (va * vb) < 0 else 1
            acc = sign * rescale_from_q8(partial_q8, frac_bits)
            lines_val.append(to_hex32(acc))
    return lines_val

if __name__ == '__main__':
    posit_vals, posit_nar = gen_posit4()
    with open('golden_posit4.hex', 'w') as f:
        f.write('\n'.join(posit_vals) + '\n')
    with open('golden_posit4_nar.hex', 'w') as f:
        f.write('\n'.join(posit_nar) + '\n')

    with open('golden_fp4.hex', 'w') as f:
        f.write('\n'.join(gen_fp4()) + '\n')

    # Adaptive frac_bits golden vectors for tb_posit4_mac_ref.v and
    # tb_fp4_mac_ref.v (frac_bits=8 is covered by the plain files above
    # already, since rescale_shift=0 there is a no-op -- these three
    # additional values are the ones that actually exercise the new
    # adaptive rescale logic, matching the set already used to test
    # fp2_parallel_mac_ref.v for consistency).
    for frac_bits in (6, 10, 12):
        with open(f'golden_posit4_frac{frac_bits}.hex', 'w') as f:
            f.write('\n'.join(gen_posit4_adaptive(frac_bits)) + '\n')
        with open(f'golden_fp4_frac{frac_bits}.hex', 'w') as f:
            f.write('\n'.join(gen_fp4_adaptive(frac_bits)) + '\n')

    # Saturating fxp16 golden vectors (posit4_mac_ref.v / fp4_mac_ref.v's
    # new ACC_W=16 default), all 4 tested frac_bits values -- these are
    # DIFFERENT from the files above, which stay non-saturating 32-bit
    # and back the shared sparx_mac_unified.v accumulator, unaffected
    # by this change.
    for frac_bits in (6, 8, 10, 12):
        with open(f'golden_posit4_fxp16_frac{frac_bits}.hex', 'w') as f:
            f.write('\n'.join(gen_posit4_fxp16(frac_bits)) + '\n')
        with open(f'golden_fp4_fxp16_frac{frac_bits}.hex', 'w') as f:
            f.write('\n'.join(gen_fp4_fxp16(frac_bits)) + '\n')

    with open('golden_fp2.hex', 'w') as f:
        f.write('\n'.join(gen_fp2()) + '\n')

    for frac_bits in (6, 12):
        with open(f'golden_fp2_frac{frac_bits}.hex', 'w') as f:
            f.write('\n'.join(gen_fp2_adaptive(frac_bits)) + '\n')

    print("Golden vectors generated: 256 entries each for posit4 / fp4 / fp2")
    print("  plus adaptive-frac_bits sweeps (6,10,12) for posit4 / fp4")
    print("Sample posit4 (a=7,b=7 -> 16*16=256):", posit_vals[7*16+7], "expect", to_hex32(256*SCALE))
    print("Sample fp4    (a=1111 -> 6, b=1111 -> 6 -> 36):", gen_fp4()[15*16+15], "expect", to_hex32(36*SCALE))

    # -----------------------------------------------------------------
    # Golden model for the TRUE packed-pair FP2 datapath
    # (fp2_pair_unpack.v, fp2_pair_mac_fp4xfp2.v, fp2_pair_mac_fp2xfp2.v)
    # -----------------------------------------------------------------

    def fp2_pair_decode(wp, mode):
        """CORRECTED decode of a packed FP2 pair, per direct visual
        inspection of the rendered Table I/II (see docs/DESIGN_NOTES.md
        Sec. 0.3). C=00 is used for TWO different conditions:
          code == 0b0000        -> true "both zero"
          C=00, code != 0b0000  -> opposite-sign pair (F, -F)
        Returns (v1, v2) as signed floats (element-level, X excluded)."""
        s = (wp >> 3) & 1
        em = (wp >> 2) & 1
        c = wp & 0b11
        if mode == 0:      # E1M0: bit=0 -> 1.0, bit=1 -> 0.5
            mag_val = 0.5 if em else 1.0
        else:               # E0M1: bit=0 -> 1.0, bit=1 -> 1.5
            mag_val = 1.5 if em else 1.0
        F = (-1.0 if s else 1.0) * mag_val
        if c == 0b00:
            if wp == 0b0000:
                return 0.0, 0.0
            else:
                return F, -F
        elif c == 0b01:
            return 0.0, F
        elif c == 0b10:
            return F, 0.0
        else:
            return F, F

    def gen_pair_unpack():
        """Golden model for fp2_pair_unpack.v, corrected to match the
        actual rendered Table I (see docs/DESIGN_NOTES.md Sec. 0.3)."""
        elem1_lines, elem2_lines = [], []
        for wp in range(16):
            for mode in range(2):
                s = (wp >> 3) & 1
                em = (wp >> 2) & 1
                c = wp & 0b11
                is_true_zero = (wp == 0b0000)
                is_opposite_pair = (c == 0b00) and not is_true_zero

                zero1 = 1 if (is_true_zero or c == 0b01) else 0
                zero2 = 1 if (is_true_zero or c == 0b10) else 0
                sign2 = (1 - s) if is_opposite_pair else s  # flip if opposite pair

                elem1 = (s << 3) | (mode << 2) | (zero1 << 1) | em
                elem2 = (sign2 << 3) | (mode << 2) | (zero2 << 1) | em
                elem1_lines.append(format(elem1, '01x'))
                elem2_lines.append(format(elem2, '01x'))
        return elem1_lines, elem2_lines

    def gen_fp4xfp2_pair():
        lines = []
        for wp in range(16):
            for mode in range(2):
                v1, v2 = fp2_pair_decode(wp, mode)
                for fa in range(16):
                    for fb in range(16):
                        psum = fp4_decode(fa) * v1 + fp4_decode(fb) * v2
                        lines.append(to_hex32(round(psum * SCALE)))
        return lines

    def gen_fp2xfp2_pair():
        lines = []
        for wp in range(16):
            for mode_w in range(2):
                w1, w2 = fp2_pair_decode(wp, mode_w)
                for ap in range(16):
                    for mode_a in range(2):
                        a1, a2 = fp2_pair_decode(ap, mode_a)
                        psum = a1 * w1 + a2 * w2
                        lines.append(to_hex32(round(psum * SCALE)))
        return lines

    e1, e2 = gen_pair_unpack()
    with open('golden_pairunpack_elem1.hex', 'w') as f:
        f.write('\n'.join(e1) + '\n')
    with open('golden_pairunpack_elem2.hex', 'w') as f:
        f.write('\n'.join(e2) + '\n')

    fp4xfp2_lines = gen_fp4xfp2_pair()
    with open('golden_fp4xfp2_pair.hex', 'w') as f:
        f.write('\n'.join(fp4xfp2_lines) + '\n')

    fp2xfp2_lines = gen_fp2xfp2_pair()
    with open('golden_fp2xfp2_pair.hex', 'w') as f:
        f.write('\n'.join(fp2xfp2_lines) + '\n')

    print("Pair-unpack golden: %d entries" % len(e1))
    print("FP4xFP2 pair-MAC golden: %d entries" % len(fp4xfp2_lines))
    print("FP2xFP2 pair-MAC golden: %d entries" % len(fp2xfp2_lines))
