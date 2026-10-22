# Integration boundaries

## Control plane
The pipeline CPU speaks a Wishbone-style interface. The arithmetic subsystem exposes a compact `req/we/addr/wdata/rdata/ack` port. A parent integration fabric supplies address decoding, clock/reset synchronization and Wishbone signal translation. No CPU instructions or accelerator MMIO base address are assumed by the standalone MAC peripheral.

## Computation
The mixed-format arithmetic path uses signed scaled partial products for Posit4, FP4 and single-lane FP2. Parallel FP2 uses a distinct 16-bit saturating accumulator and keeps lane-product cancellation before saturation. The two accumulation semantics are intentionally not conflated.

## Security and privacy
A security domain mediates authorization and controls when accelerator commands are accessible. Randomized output masking must not be treated as a differential privacy mechanism without a formally defined privacy budget and output distribution.

## Pipeline protocol
Configuration and operand registers are stable at least through issue, and mode/format remain stable across a dot product. Write `CMD.clear` before the first operation, write `CMD.issue` for each operand pair, and read result/status after the engine reports a valid result. The interface is single-clock and assumes synchronous master handshakes.
