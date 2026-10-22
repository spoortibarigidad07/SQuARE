#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v iverilog >/dev/null; then
  echo 'iverilog required for RTL simulation' >&2
  exit 127
fi
mkdir -p "$ROOT/build/cnn_transprecision"
RTL=(
 "$ROOT/rtl/compute/posit4_es1_pp.v"
 "$ROOT/rtl/compute/fp4_e2m1_pp.v"
 "$ROOT/rtl/compute/fp2_pp.v"
 "$ROOT/rtl/cnn_transprecision/square_lowp_product.sv"
 "$ROOT/rtl/cnn_transprecision/square_cnn_processing_element.sv"
 "$ROOT/rtl/cnn_transprecision/square_systolic_pe.sv"
 "$ROOT/rtl/cnn_transprecision/square_systolic_array.sv"
 "$ROOT/rtl/cnn_transprecision/square_systolic_variants.sv"
)
for test in tb_square_lowp_product tb_square_systolic; do
  iverilog -g2012 -s "$test" -o "$ROOT/build/cnn_transprecision/$test.vvp" \
    "${RTL[@]}" "$ROOT/tests/cnn_transprecision/$test.sv"
  vvp "$ROOT/build/cnn_transprecision/$test.vvp"
done
