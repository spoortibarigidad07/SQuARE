#!/usr/bin/env python3
"""
golden_gen_lean.py

Golden reference model, independent of the RTL, for the Posit(4,1) and
FP4-E2M1 reference MACs. Writes the files read by
tb_posit4_mac_ref_v2_standalone.v and tb_fp4_mac_ref_v2_standalone.v:

    golden_posit4_fxp16_frac{6,8,10,12}.hex   (exhaustive 16x16, sat16)
    golden_fp4_fxp16_frac{6,8,10,12}.hex      (exhaustive 16x16, sat16)
    golden_posit4_nar.hex                     (NaR flag per operand pair)

Products are formed exactly, scaled to frac_bits with truncation toward
zero, and saturated to 16 bits.
"""

# ---------------------------------------------------------------
# Posit(4, es=1) decode table: code -> (is_zero, is_nar, sign, magnitude)
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


def fp4_decode(code):
    """FP4 (E2M1, bias=1), OCP MX E2M1 value set."""
    sign = (code >> 3) & 1
    e = (code >> 1) & 0b11
    m = code & 1
    if e == 0:
        val = 0.5 * m                 # subnormal
    else:
        val = (1.0 + 0.5 * m) * (2 ** (e - 1))
    return (-1.0 if sign else 1.0) * val


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


GLOBAL_FRAC_BITS = 8
SCALE = 1 << GLOBAL_FRAC_BITS  # 256

def rescale_from_q8(partial_q8, frac_bits):
    """Rescale a non-negative Q8 magnitude to frac_bits; a right shift
    of the magnitude truncates toward zero, as the hardware does."""
    shift = frac_bits - 8
    if shift >= 0:
        return partial_q8 << shift
    else:
        return partial_q8 >> (-shift)


def gen_posit4_fxp16(frac_bits):
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


def gen_posit4_nar_flags():
    """NaR flag per operand pair, read via $readmemb in
    tb_posit4_mac_ref_v2_standalone.v."""
    lines_nar = []
    for a in range(16):
        for b in range(16):
            _, na, _ = posit4_decode(a)
            _, nb, _ = posit4_decode(b)
            lines_nar.append('1' if (na or nb) else '0')
    return lines_nar


if __name__ == '__main__':
    for frac_bits in (6, 8, 10, 12):
        with open(f'golden_posit4_fxp16_frac{frac_bits}.hex', 'w') as f:
            f.write('\n'.join(gen_posit4_fxp16(frac_bits)) + '\n')
        with open(f'golden_fp4_fxp16_frac{frac_bits}.hex', 'w') as f:
            f.write('\n'.join(gen_fp4_fxp16(frac_bits)) + '\n')

    with open('golden_posit4_nar.hex', 'w') as f:
        f.write('\n'.join(gen_posit4_nar_flags()) + '\n')

    print("Wrote golden_posit4_fxp16_frac{6,8,10,12}.hex, "
          "golden_fp4_fxp16_frac{6,8,10,12}.hex, and golden_posit4_nar.hex")
