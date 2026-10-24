# Std. Ref. baselines: specification

This document specifies the format-matched standard-reference (Std. Ref.) MAC
units used for the comparisons in Tables 1–3 of the manuscript, and how they
differ from the proposed SQuARE units. The Std. Ref. units are in
`rtl/compute/` and the proposed units in `rtl/optimized/`. Everything stated
here can be checked directly against the source files.

## 1. Units compared

| Format | Std. Ref. module | Proposed module |
|---|---|---|
| Posit(4,1) | `rtl/compute/posit4_mac_ref_v2.v` | `rtl/optimized/posit4_mac_ref_v2_bounded.v` |
| FP4-E2M1 | `rtl/compute/fp4_mac_ref_v2.v` | `rtl/optimized/fp4_mac_ref_v2_bounded_exact.v` |
| DP2 (dual-product FP2, E1M0/E0M1) | `rtl/compute/fp2_parallel_mac_ref.v` | `rtl/optimized/fp2_parallel_mac_ref_bounded_exact.v` |

Both members of each pair use the same operand decoder (`posit4_es1_decode.v`,
`fp4_e2m1_decode.v`, `fp2_to_fp3.v`; the copies in `rtl/compute/` and
`rtl/optimized/` differ only in comments) and have identical ports and
parameters.

## 2. What is identical in each pair

| Property | Value (both Std. Ref. and proposed) |
|---|---|
| Operand formats | Posit(4,1); FP4-E2M1 (bias 1); FP2 E1M0 / E0M1 selected by `fmt_sel`, with a separate zero mask per operand |
| Product generation | Exact. Posit(4,1): sign XOR and exponent addition (every nonzero value is a power of two, so no multiplier). FP4-E2M1: 2-bit × 2-bit significand product (0..9) plus exponent addition. DP2: two products of 2-bit magnitudes, summed **before** alignment so that cancellation between them is preserved |
| Accumulator | One signed 16-bit fixed-point register (FXP16), runtime fractional position `F = frac_bits` (0..31) |
| Alignment | Single shift by (product exponent + F); DP2 uses (F − 2). Negative shifts truncate toward zero (the magnitude is shifted, then the sign is applied) |
| Accumulation semantics | `acc ← sat16(A + trunc(p · 2^F))`, with A = 0 on `clear_acc`. Saturating to [−32768, +32767], never wrapping |
| Special values | Posit zero contributes 0; NaR contributes 0 and sets a sticky `nar_flag`, cleared by `clear_acc` |
| Pipeline depth | One register stage. Combinational decode → align → add → saturate, then the registered accumulator. Latency 1 cycle, throughput 1 MAC (DP2: 2 products) per cycle |
| Registered state | `acc` (16 bits), `valid_out`, `overflow`, plus `nar_flag` for Posit(4,1) |
| Status outputs | `overflow` (this cycle saturated), `valid_out`, `acc_fxp8 = acc[15:8]` (FP4, DP2) |
| Reset | Asynchronous active-low `rst_n` |

Because the numerical semantics are identical, the proposed units are
**bit-exact and cycle-exact** with their Std. Ref. counterparts.

## 3. The only difference: width of the contribution/sum datapath

The Std. Ref. units form each aligned contribution **exactly at full width**,
add it to the sign-extended accumulator, and only then saturate. The
intermediate is wide enough to hold the largest possible aligned contribution
exactly:

| Format | Shift range | Largest aligned magnitude | Signed bits required | Std. Ref. intermediate (RTL) | Proposed intermediate |
|---|---|---|---|---|---|
| Posit(4,1) | −8 .. 39 | 2^39 | 41 | 48 bits (includes margin) | 18 bits |
| FP4-E2M1 | −2 .. 33 | 9 · 2^33 | 38 | 38 bits | 18 bits |
| DP2 | −2 .. 29 | 18 · 2^29 | 35 | 35 bits | 18 bits |

The proposed units use the fact that any contribution with magnitude ≥ 2^16
saturates the 16-bit accumulator for **every** possible prior accumulator value.
Such contributions are detected directly from the shift amount (and, for FP4
and DP2, the product magnitude), and the result selects the saturation rail by
sign without computing the wide value. All other contributions are below 2^16
and are added exactly in an 18-bit datapath:

- **Posit(4,1):** saturation is guaranteed when `exp_p + F ≥ 16`.
- **FP4-E2M1:** saturation is guaranteed when `shift ≥ 16`, or `shift = 15` and
  `sig_prod ≥ 2`, or `shift = 14` and `sig_prod ≥ 4`, or `shift = 13` and
  `sig_prod = 9`.
- **DP2:** saturation is guaranteed when the pair sum S ≠ 0 and
  `|S| · 2^(F−2) ≥ 2^16`. The test is applied to the pair sum, not to either
  product alone, so cancellation is preserved.

## 4. Implementation conditions (Tables 1 and 2)

The Std. Ref. and proposed units are implemented under the same device,
implementation, timing, and power-analysis conditions:

- **FPGA (Table 1):** Xilinx Vivado, Virtex-7 XC7VX485T-2 (VC707). The same
  clock constraint is used for every design; only the clock period differs.
- **ASIC (Table 2):** Cadence Genus 20.11 and Innovus 20.14, 45 nm
  standard-cell library, 1.0 V, TT, 25 °C, 250 MHz constraint for all designs.
- **Power:** switching activity from VGG-16/CIFAR-100 operand sequences
  (Vivado power analysis on FPGA; gate-level VCD/SAIF on ASIC).
