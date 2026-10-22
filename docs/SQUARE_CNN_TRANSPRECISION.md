# SQuARE mixed-precision CNN datapath

**SQuARE — Sub-Quad-Precision Neural Acceleration in a RISC-V Edge-AI SoC**

The SQuARE CNN datapath supports precision-specialized multiply/accumulate
processing elements using the existing SPARX partial-product primitives:
Posit(4,1), FP4 E2M1, FP2 E1M0/E0M1 and independent two-lane FP2 (DP2).
These numeric blocks can be placed into both the original CNN parallel-PE
convolution structure and an output-stationary 2D systolic array.

## Compute architecture

```
 RISC-V control and existing CNN controller
                    |
        convolution operand stream
                    |
      precision-encoded operand lanes
                    |
  +------------------------------------+
  | PE MAC variant selector (elaboration)|
  | Posit4   | FP4 | FP2 | FP2 x2 (DP2)|
  +------------------------------------+
                    |
         Q8.8 signed product
                    |
        accumulator / reduction
                    |
     postprocess / quantizer / BRAM
```

In the legacy CNN convolution paths, a PE is **combinational** and the CNN
controller reduces products into `acc`. In the clocked systolic array, each PE
contains its **own accumulator** and forwards input operands to the right and
down. This distinction prevents accidentally adding extra pipeline cycles to
legacy controllers that were designed to see combinational PE products.

## Encoded operand fields

Operands are `logic [7:0]` in all architectures, with the following convention.

| Mode | FORMAT | `a[7:0]` / `b[7:0]` | Numeric behavior |
|---|---:|---|---|
| Posit(4,1) | 0 | `[3:0]` is the four-bit Posit code | Powers-of-two (plus 0/NaR), Q8.8 product |
| FP4 E2M1 | 1 | `[3:0]` is `{sign, exponent[1:0], mantissa}` | Full E2M1/subnormal values, Q8.8 product |
| FP2 | 2 | `[1:0]` is `{sign, bit}`, `[4]` marks zero | E1M0 or E0M1, one product |
| DP2 | 3 | `[1:0]` lane0, `[3:2]` lane1, `[4]` zero0, `[5]` zero1 | Two independent FP2 products per PE/cycle |

The same encoding applies to weight and activation buses. `FP2_FORMAT=0` is
E1M0, `FP2_FORMAT=1` is E0M1. The FP2 encoding uses a **separate zero bit**;
none of the four 2-bit sign/magnitude codes implicitly represents zero.
`[7:6]` are reserved in all formats. The DP2 pair is **independent lanes**, not
the SPARX packed-pair C-flag operand encoding.

**Important representation contract:** The legacy CNN memories use signed INT8
weights/activations and some inter-layer outputs are 4-bit ReLU6 integers.
They are *not* format-encoded FP4/Posit4/FP2 numbers. Loading them unchanged
into the low-precision PE would reinterpret raw bits, **not quantize** data.
Precision-specific ROM images, activation conversion/requantization, scaling,
and bias/batch-norm recalibration are required to obtain meaningful end-to-end
CNN inference. The low-precision product datapath itself does not imply model
accuracy or numerical equivalence with the INT8 pipeline.

## Systolic array (`rtl/cnn_transprecision/`)

A PE (r,c) accepts A from the left and B from the top, performs one Q8.8
product per valid lane pair, updates its local signed accumulator, and forwards
A rightward and B downward on the next cycle. A valid pulse is emitted per
accepted non-NaR product. For output-stationary matrix multiplication, the
controller performs edge skewing:

- A row r receives element `A[r,k]` at clock `k+r`.
- B column c receives element `B[k,c]` at clock `k+c`.
- PE(r,c) sees the matching pair at clock `k+r+c`.

`acc_flat[(r*COLS+c)*ACC_W +: ACC_W]` is the resulting C[r,c]. The array
has configurable `ROWS`, `COLS`, `FORMAT`, `FP2_FORMAT`, `ACC_W` and `SATURATE`.
Fixed-format wrappers are available:

- `square_systolic_posit4`, `square_systolic_fp4_e2m1` (32-bit wrapping)
- `square_systolic_fp2_e1m0`, `square_systolic_fp2_e0m1` (32-bit wrapping)
- `square_systolic_dp2_e1m0`, `square_systolic_dp2_e0m1` (16-bit saturating)

Clear is synchronous and may coincide with the first valid MAC, which becomes
the first contribution in a new dot product. At the end of a transaction,
insert bubbles of at least `ROWS + COLS` clocks before reusing `clear` to avoid
mixing in-flight cells from different transactions. `nar_seen` is sticky until
clear and Posit NaR contributions are skipped. `overflow` is a one-cycle flag
that indicates out-of-range arithmetic, even for wrapping mode.

## Existing RISC-V/CNN hierarchy integration

Drop-in module overlays are under `rtl/cnn_transprecision/overlays/`:

| Existing controller | Overlay | PE count |
|---|---|---:|
| MNIST Conv2D_1 | `overlays/MNIST/Conv2D_1.sv` | 9 |
| CIFAR-10 Conv2D_1 | `overlays/CIFAR_10/Conv2D_1.sv` | 27 |
| CIFAR-10 Conv2D_2 | `overlays/CIFAR_10/Conv2D_2.sv` | 288 |
| CIFAR-10 Conv2D_3 | `overlays/CIFAR_10/Conv2D_3.sv` | 576 |

Each overlay retains its original module name and external ports so the
CNN engine and RISC-V SoC can instantiate it by name. **Exclude** the matching
`rtl/soc_legacy/.../Conv2D_X/Design.sv` file from the compile sources when
adding an overlay, or duplicate module-definition errors will occur. Supply
module parameters `SQUARE_FORMAT` and `SQUARE_FP2_FORMAT` at the top-level CNN
instance or at elaboration. The overlays reconcile PE array depths with each
convolution's actual dot-product length and widen PE products to 32 bits.

The other convolution and dense controller paths still operate on their original
representation and need format adapters at layer boundaries. The existing SoC
and authentication control plane are unchanged by PE selection.

## Numeric scaling and accumulator behavior

All primitive products use the fixed global **Q8.8** scale (a numeric value of 1.0 corresponds to 256 integer counts). The parallel CNN PE exposes 32-bit Q8.8 products,
while the systolic PE accumulates those products into `ACC_W` bits. DP2 sums
its two products **before** accumulator saturation. Posit4 maximum finite
magnitude is 16; a 16x16 product requires 65536 raw Q8.8 counts, so 16-bit
legacy PE products cannot represent the full Posit range. The overlays use
32-bit products for this reason.

Bias addition, post-accumulation scale shifts, batch norm, and output
quantization must be configured for the precision-specific layer outputs.
Do not treat 32-bit Q8.8 products as the original signed INT8 products.

## Verification and compilation

`tests/cnn_transprecision/` contains product-encoding checks and a 2x2
Posit4 output-stationary matrix multiplication exercise. Run using Icarus
Verilog and vvp:

```bash
bash scripts/run_square_cnn_tests.sh
```

Use `python scripts/square_cnn_sources.py --dataset CIFAR_10 --format fp4`
to emit compute/overlay source paths; the normal SoC build additionally
includes CPU, CNN controllers, BRAM wrappers, security modules and vendor IP.

This is a structural and numerical architecture specification; device PPA,
frequency, and CNN classification accuracy depend on the selected FPGA,
precision-specific trained parameters, tool versions and firmware.
