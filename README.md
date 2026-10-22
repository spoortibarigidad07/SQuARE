# SQuARE — Sub-Quad-Precision Neural Acceleration in a RISC-V Edge-AI SoC

**Manuscript status:** *SQuARE — Sub-Quad-Precision Neural Acceleration in a RISC-V Edge-AI SoC* is under review in the **Journal of Systems Architecture**.

SQuARE integrates a RISC-V SoC control plane, CNN inference pipeline, and a programmable mixed-format arithmetic fabric for resource-constrained edge intelligence.

## System architecture

```text
RISC-V CPU / Wishbone control plane
              |
     MMIO peripheral bridge
              |
     SQuARE MAC peripheral
              |
        SPARX MAC engine
          /         \
Posit4/FP4/FP2    Parallel FP2
 shared 32-bit     bounded-exact
 accumulator       signed 16-bit saturation
```

The MAC peripheral presents `req`, `we`, `addr`, `wdata`, `rdata`, and `ack` signals. A system Wishbone adapter implements address decoding and bus-to-peripheral translation.

## Precision modes

| mode[1:0] | Datapath | Accumulator semantics |
|---|---|---|
| 00 | Posit(4,1) | signed 32-bit wrapping |
| 01 | FP4 E2M1 | signed 32-bit wrapping |
| 10 | FP2 element-level | signed 32-bit wrapping |
| 11 | FP2 two-lane E1M0/E0M1 | signed 16-bit saturating |

The selected mode and fractional precision are held constant through a dot product. Separate zero sidebands accompany two-bit FP2 operands. The paired FP2 path forms lane-product sums before saturation so opposing contributions can cancel.

## Register map

32-bit registers, byte offsets, active-low reset.

| Address | Name | Fields |
|---|---|---|
| 0x00 | CONFIG | mode[1:0], fractional bits[6:2], pair format[7] |
| 0x04 | OPERANDS | A[3:0], B[7:4] |
| 0x08 | PAIR | a0, a1, w0, w1 (2 bits each) |
| 0x0C | ZERO | a0, a1, w0, w1 zero sidebands |
| 0x10 | COMMAND | issue[0], clear[1] |
| 0x14 | RESULT | selected signed accumulator |
| 0x18 | STATUS | valid, shared-valid, pair-valid, overflow, NaR |
| 0x1C | PAIR_Q8 | sign-extended 8-bit result window |

Write CONFIG and operands, clear between independent dot products, then issue the MAC operation and read RESULT after the valid indication.

## Security and data handling

Accelerator access control belongs at the CPU/peripheral boundary. Authentication and control-plane separation are distinct from inference-result privacy. Formal differential privacy requires an explicit statistical mechanism and privacy accounting.

## Source and verification organization

The complete integrated RTL source package contains `rtl/compute`, `rtl/optimized`, `rtl/soc_legacy`, the `square_mac_peripheral` module, reference testbenches and arithmetic golden vectors. Verification includes format decoding, numerical accumulation, overflow/cancellation, clear/issue sequencing, interface readback and device-specific hardware synthesis.

This repository documents the programmable arithmetic and integration interfaces of the SQuARE design.

## Precision-specialized CNN and systolic architectures

SQuARE includes an output-stationary systolic array and drop-in convolution PE
implementations with six fixed-format profiles: Posit(4,1), FP4 E2M1, FP2 E1M0,
FP2 E0M1, dual-lane FP2 E1M0, and dual-lane FP2 E0M1. Numeric products
use Q8.8 scaling; dual FP2 lanes sum before saturating accumulation.

The parameterized processing elements and arrays are in
[`rtl/cnn_transprecision/`](rtl/cnn_transprecision/). The precision-selectable
convolution overlays for MNIST and CIFAR-10 are in the
[`overlays/`](rtl/cnn_transprecision/overlays/) subdirectory.

**Operand encoding:** FPGA memories feeding these low-precision PEs must contain
the corresponding FP4, Posit4, or FP2 codes. Signed INT8 memory contents must be
converted/requantized before use. Details of operand packing, systolic input
skew, accumulator semantics, and layer integration are specified in
[`SQUARE_CNN_TRANSPRECISION.md`](docs/SQUARE_CNN_TRANSPRECISION.md).

```bash
python tests/cnn_transprecision/check_arithmetic.py
python tests/cnn_transprecision/check_structure.py
bash scripts/run_square_cnn_tests.sh  # requires iverilog and vvp
```
