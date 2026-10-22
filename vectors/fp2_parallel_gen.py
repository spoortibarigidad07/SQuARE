#!/usr/bin/env python3
"""
fp2_parallel_gen.py

Independent (from the RTL) golden reference model for the two-lane
parallel FP2xFP2 MAC (fp2_parallel_mac_ref.v).

Operand encoding: STRICTLY 2 bits per FP2 value, {sign, bit}, plus a
SEPARATE 1-bit zero control per lane (not part of the 2-bit value --
see fp2_to_fp3.v for why a 2-bit code has no room left for a zero
state of its own).

Decode (shared fmt_sel applies to ALL FOUR value operands in a given
check):
  zero=1                     -> 0.0
  zero=0, fmt_sel=0 (E1M0): bit=0 -> 1.0   bit=1 -> 0.5
  zero=0, fmt_sel=1 (E0M1): bit=0 -> 1.0   bit=1 -> 1.5

pair_sum = decode(a0)*decode(w0) + decode(a1)*decode(w1)
partial_fxp = round(pair_sum * 2**frac_bits)   (always an exact integer:
  values are multiples of 0.5, so pair_sum is always a multiple of 0.25,
  and frac_bits>=2 means 2**frac_bits is a multiple of 4; for
  frac_bits<2 this is handled as an exact division instead, still
  always exact since 0.25 * 2**frac_bits stays a multiple of 1/4 * 2^k)

Saturating accumulate into a signed ACC_W-bit accumulator.
"""

ACC_W = 16
SAT_MAX = (1 << (ACC_W - 1)) - 1   #  32767
SAT_MIN = -(1 << (ACC_W - 1))      # -32768


def decode_lane(sign, bit, zero, fmt_sel):
    if zero:
        return 0.0
    if fmt_sel == 0:  # E1M0
        mag = 0.5 if bit else 1.0
    else:              # E0M1
        mag = 1.5 if bit else 1.0
    return -mag if sign else mag


def pair_sum(a0, a1, w0, w1, a0z, a1z, w0z, w1z, fmt_sel):
    # a0,a1,w0,w1 here are each a 2-bit integer 0..3 = {sign,bit}
    def split(code):
        return (code >> 1) & 1, code & 1
    sa0, ba0 = split(a0); sa1, ba1 = split(a1)
    sw0, bw0 = split(w0); sw1, bw1 = split(w1)
    va0 = decode_lane(sa0, ba0, a0z, fmt_sel)
    va1 = decode_lane(sa1, ba1, a1z, fmt_sel)
    vw0 = decode_lane(sw0, bw0, w0z, fmt_sel)
    vw1 = decode_lane(sw1, bw1, w1z, fmt_sel)
    return va0 * vw0 + va1 * vw1


def saturate(value_int):
    if value_int > SAT_MAX:
        return SAT_MAX, True
    if value_int < SAT_MIN:
        return SAT_MIN, True
    return value_int, False


def to_hex16(signed_int):
    return format(signed_int & 0xFFFF, '04x')


def gen_single_shot(frac_bits):
    """Exhaustive: fmt_sel(2) x [a0(2bit)xa0_zero(2)] x [a1..] x [w0..] x [w1..]
    = 2 x 8 x 8 x 8 x 8 = 8192 lines (same total as before -- each
    operand's 8 states are now (2-bit code=4) x (zero=2) instead of a
    single 3-bit code 0..7, but it's the same 8 states either way),
    single-shot (clear_acc=1,valid_in=1 from a zeroed accumulator)."""
    lines = []
    ovf_lines = []
    for fmt_sel in range(2):
        for a0 in range(4):
            for a0z in range(2):
                for a1 in range(4):
                    for a1z in range(2):
                        for w0 in range(4):
                            for w0z in range(2):
                                for w1 in range(4):
                                    for w1z in range(2):
                                        s = pair_sum(a0, a1, w0, w1, a0z, a1z, w0z, w1z, fmt_sel)
                                        partial_fxp = round(s * (2 ** frac_bits))
                                        sat_val, ovf = saturate(partial_fxp)
                                        lines.append(to_hex16(sat_val))
                                        ovf_lines.append('1' if ovf else '0')
    return lines, ovf_lines


if __name__ == '__main__':
    for frac_bits in (6, 8, 10, 12):
        vals, ovfs = gen_single_shot(frac_bits)
        with open(f'golden_fp2parallel_frac{frac_bits}.hex', 'w') as f:
            f.write('\n'.join(vals) + '\n')
        with open(f'golden_fp2parallel_frac{frac_bits}_ovf.hex', 'w') as f:
            f.write('\n'.join(ovfs) + '\n')
        print(f"frac_bits={frac_bits}: {len(vals)} entries "
              f"({sum(1 for o in ovfs if o=='1')} saturate)")

    print("\nNote: single-shot (one MAC from a cleared accumulator) never")
    print("saturates at these frac_bits values. Max |pair_sum| = 4.5")
    print("(both lanes at max magnitude 1.5, same sign: 1.5*1.5 + 1.5*1.5")
    print("= 2.25 + 2.25 = 4.5 -- an earlier version of this note incorrectly")
    print("said 3.0, corrected here). At frac_bits=12 (the largest tested")
    print("value): 4.5 * 2^12 = 18432, still well inside +-32767. Overflow/")
    print("saturation is only reachable via repeated accumulation across")
    print("many cycles, which is why tb_fp2_parallel_mac.v has a dedicated")
    print("DIRECTED overflow test rather than relying on this exhaustive sweep.")
