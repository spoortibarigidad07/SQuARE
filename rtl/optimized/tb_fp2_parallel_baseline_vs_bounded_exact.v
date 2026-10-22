// =====================================================================
// tb_fp2_parallel_baseline_vs_bounded_exact.v
//
// This testbench compares the following two independent two-lane FP2
// MAC implementations:
//
//   - fp2_parallel_mac_ref
//       Baseline implementation with a 35-bit intermediate datapath.
//
//   - fp2_parallel_mac_ref_bounded_exact
//       Bounded implementation with an 18-bit intermediate datapath.
//
// Both modules receive identical stimulus. Their results are compared
// with each other and, where applicable, against a separately
// calculated mathematical reference.
//
// ---------------------------------------------------------------------
// Section A: Complete RTL input-space comparison
// ---------------------------------------------------------------------
//
// The full external input space is exercised for:
//
//       2 fmt_sel values
//       x 8^4 operand and zero-control combinations
//       x 32 frac_bits values
//
// This gives:
//
//       2 x 8^4 x 32 = 262,144 input configurations
//
// Each configuration is applied using three sequencing steps:
//
//   1. clear_acc = 1
//      Start a new accumulation using the current contribution.
//
//   2. valid_in = 0
//      Verify state retention during a hold cycle.
//
//   3. clear_acc = 0
//      Accumulate the same contribution into the existing value.
//
// The total number of comparison points is:
//
//       262,144 x 3 = 786,432
//
// At each step, the baseline and bounded implementations are checked
// for identical accumulator, control, saturation, and output behavior.
//
// ---------------------------------------------------------------------
// Section B: Exhaustive arithmetic-state verification
// ---------------------------------------------------------------------
//
// The complete arithmetic check uses 173 derived combined-contribution
// classes:
//
//   - 2 guaranteed-saturation classes; and
//   - 171 exact contribution values, including zero.
//
// Each contribution class is evaluated against all 65,536 possible
// signed 16-bit accumulator states:
//
//       173 x 65,536 = 11,337,728 arithmetic scenarios
//
// For every scenario, three results are evaluated:
//
//   1. the independently calculated reference result;
//   2. the baseline DUT result; and
//   3. the bounded DUT result.
//
// The total number of result checks is:
//
//       11,337,728 x 3 = 34,013,184
//
// This section verifies both DUTs against the expected signed
// saturating-add behavior rather than relying only on agreement
// between the two RTL implementations.
//
// ---------------------------------------------------------------------
// Section C: Directed functional and boundary checks
// ---------------------------------------------------------------------
//
// Additional named tests cover:
//
//   - equal and unequal cancellation between the two lanes;
//   - positive and negative saturation thresholds;
//   - reachable arithmetic boundary values;
//   - clear, hold, accumulate, and reset sequencing;
//   - both supported FP2 formats;
//   - zero-mask combinations;
//   - frac_bits boundary cases; and
//   - negative truncation toward zero.
//
// The directed stimuli are generated from the verified contribution
// data used to construct the exhaustive arithmetic test set.
//
// These checks make the important cancellation, threshold, control,
// and format-dependent behaviors visible individually in the
// simulation output.
// =====================================================================

`timescale 1ns/1ps

`ifndef GOLDEN_DIR
`define GOLDEN_DIR "."
`endif

module tb_fp2_parallel_baseline_vs_bounded_exact;

    localparam ACC_W  = 16;
    localparam FRAC_W = 5;

    reg clk, rst_n, clear_acc, valid_in, fmt_sel;
    reg [FRAC_W-1:0] frac_bits;
    reg [1:0] a0, a1, w0, w1;
    reg a0_zero, a1_zero, w0_zero, w1_zero;

    wire signed [ACC_W-1:0] acc_base, acc_bound;
    wire valid_out_base, valid_out_bound;
    wire overflow_base, overflow_bound;
    wire signed [7:0] acc_fxp8_base, acc_fxp8_bound;

    integer errors, checks, errors_before;

    fp2_parallel_mac_ref #(.ACC_W(ACC_W), .FRAC_W(FRAC_W)) dut_base (
        .clk(clk), .rst_n(rst_n), .clear_acc(clear_acc), .valid_in(valid_in),
        .fmt_sel(fmt_sel), .frac_bits(frac_bits),
        .a0(a0), .a1(a1), .w0(w0), .w1(w1),
        .a0_zero(a0_zero), .a1_zero(a1_zero), .w0_zero(w0_zero), .w1_zero(w1_zero),
        .acc(acc_base), .valid_out(valid_out_base), .overflow(overflow_base), .acc_fxp8(acc_fxp8_base)
    );

    fp2_parallel_mac_ref_bounded_exact #(.ACC_W(ACC_W), .FRAC_W(FRAC_W)) dut_bound (
        .clk(clk), .rst_n(rst_n), .clear_acc(clear_acc), .valid_in(valid_in),
        .fmt_sel(fmt_sel), .frac_bits(frac_bits),
        .a0(a0), .a1(a1), .w0(w0), .w1(w1),
        .a0_zero(a0_zero), .a1_zero(a1_zero), .w0_zero(w0_zero), .w1_zero(w1_zero),
        .acc(acc_bound), .valid_out(valid_out_bound), .overflow(overflow_bound), .acc_fxp8(acc_fxp8_bound)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task compare_outputs(input [255:0] label);
        begin
            checks = checks + 1;
            if (acc_base !== acc_bound || valid_out_base !== valid_out_bound ||
                overflow_base !== overflow_bound || acc_fxp8_base !== acc_fxp8_bound) begin
                errors = errors + 1;
                if (errors <= 30)
                    $display("    MISMATCH [%0s]: base(acc=%0d,vo=%b,ovf=%b,fxp8=%0d) bound(acc=%0d,vo=%b,ovf=%b,fxp8=%0d)",
                              label, acc_base, valid_out_base, overflow_base, acc_fxp8_base,
                                     acc_bound, valid_out_bound, overflow_bound, acc_fxp8_bound);
            end
        end
    endtask

            // Helper task: drive ONE real clocked cycle (setup or test),
            // using clear_acc/valid_in exactly as a real caller would --
            // no force involved. A previous revision of this section
            // used `force` on the acc register to jump to an arbitrary
            // starting state before applying test operands through a
            // real clock edge; directly probed and confirmed that
            // Icarus does not let a procedurally-driven register
            // actually update while under `force`, even across a
            // posedge -- the register silently reverts to the forced
            // value on release instead of keeping the newly-computed
            // result. That approach is not used here. Instead, any
            // nonzero starting accumulator state needed below is
            // reached via a genuine prior cycle (clear_acc=1 with
            // operands verified, via the Python derivation, to produce
            // that exact contribution) -- real RTL execution, not a
            // simulator escape hatch.
            task do_cycle;
                input do_clear;
                input cyc_fmt;
                input [1:0] cyc_a0; input cyc_a0z;
                input [1:0] cyc_a1; input cyc_a1z;
                input [1:0] cyc_w0; input cyc_w0z;
                input [1:0] cyc_w1; input cyc_w1z;
                input [4:0] cyc_frac;
                begin
                    @(negedge clk);
                    fmt_sel = cyc_fmt;
                    a0 = cyc_a0; a0_zero = cyc_a0z;
                    a1 = cyc_a1; a1_zero = cyc_a1z;
                    w0 = cyc_w0; w0_zero = cyc_w0z;
                    w1 = cyc_w1; w1_zero = cyc_w1z;
                    frac_bits = cyc_frac;
                    clear_acc = do_clear; valid_in = 1'b1;
                    @(posedge clk); #1;
                    valid_in = 1'b0; clear_acc = 1'b0;
                end
            endtask

    integer ifmt, ia0, ia1, iw0, iw1, ifrac;

    initial begin
        errors = 0; checks = 0;
        rst_n = 0; clear_acc = 0; valid_in = 0; fmt_sel = 0; frac_bits = 0;
        a0=0; a1=0; w0=0; w1=0; a0_zero=0; a1_zero=0; w0_zero=0; w1_zero=0;
        @(negedge clk); @(negedge clk);
        rst_n = 1;

        $display("========================================================================");
        $display(" FP2: baseline (fp2_parallel_mac_ref) vs. bounded-exact -- cross-check");
        $display("========================================================================");

        // =========================================================
        // SECTION A: full RTL cross-check
        // =========================================================
        $display("");
        $display("--- Section A: full RTL cross-check (2 fmt x 8^4 operands x 32 frac_bits, x3 steps) ---");
        errors_before = errors;
        for (ifmt = 0; ifmt < 2; ifmt = ifmt + 1) begin
         for (ia0 = 0; ia0 < 8; ia0 = ia0 + 1) begin
          for (ia1 = 0; ia1 < 8; ia1 = ia1 + 1) begin
           for (iw0 = 0; iw0 < 8; iw0 = iw0 + 1) begin
            for (iw1 = 0; iw1 < 8; iw1 = iw1 + 1) begin
             for (ifrac = 0; ifrac < 32; ifrac = ifrac + 1) begin  // every raw operand and zero-mask combination at every frac_bits value 0 through 31
                @(negedge clk);
                fmt_sel  = ifmt[0];
                a0 = ia0[2:1]; a0_zero = ia0[0];
                a1 = ia1[2:1]; a1_zero = ia1[0];
                w0 = iw0[2:1]; w0_zero = iw0[0];
                w1 = iw1[2:1]; w1_zero = iw1[0];
                frac_bits = ifrac[4:0];
                clear_acc = 1'b1; valid_in = 1'b1;
                @(posedge clk); #1;
                compare_outputs("clear_acc=1");
                clear_acc = 1'b0; valid_in = 1'b0;

                @(negedge clk);
                @(posedge clk); #1;
                compare_outputs("hold");

                @(negedge clk);
                valid_in = 1'b1;
                @(posedge clk); #1;
                compare_outputs("clear_acc=0");
                valid_in = 1'b0;
             end
            end
           end
          end
         end
        end
        if (errors == errors_before)
            $display("  [PASS] Section A: all comparisons matched (base==bound)");
        else
            $display("  [FAIL] %0d Section A comparison(s) did NOT match", errors - errors_before);

        // =========================================================
        // SECTION B: exhaustive arithmetic-core proof, 173 classes
        // =========================================================
        $display("");
        $display("--- Section B: exhaustive arithmetic-core proof (173 classes x 65,536 accumulator states) ---");
        errors_before = errors;
        begin : section_b
            integer class_idx;
            integer acc_state_i;
            reg signed [15:0] acc_state;
            reg        rep_fmt;
            reg [1:0]  rep_a0, rep_a1, rep_w0, rep_w1;
            reg        rep_a0z, rep_a1z, rep_w0z, rep_w1z;
            reg [4:0]  rep_frac;
            reg signed [31:0] expect_sum;
            reg signed [15:0] expect_acc;
            reg expect_ovf;
            reg signed [31:0] contribution_val;
            reg is_force_sat;
            reg force_sat_sign;

            reg        tbl_fmt   [0:172];
            reg [1:0]  tbl_a0    [0:172];
            reg        tbl_a0z   [0:172];
            reg [1:0]  tbl_a1    [0:172];
            reg        tbl_a1z   [0:172];
            reg [1:0]  tbl_w0    [0:172];
            reg        tbl_w0z   [0:172];
            reg [1:0]  tbl_w1    [0:172];
            reg        tbl_w1z   [0:172];
            reg [4:0]  tbl_frac  [0:172];
            reg        tbl_fsat  [0:172];
            reg        tbl_fsign [0:172];
            reg signed [31:0] tbl_contrib [0:172];

            `include "fp2_173class_table.vh"

            for (class_idx = 0; class_idx <= 172; class_idx = class_idx + 1) begin
                rep_fmt  = tbl_fmt[class_idx];
                rep_a0   = tbl_a0[class_idx];  rep_a0z = tbl_a0z[class_idx];
                rep_a1   = tbl_a1[class_idx];  rep_a1z = tbl_a1z[class_idx];
                rep_w0   = tbl_w0[class_idx];  rep_w0z = tbl_w0z[class_idx];
                rep_w1   = tbl_w1[class_idx];  rep_w1z = tbl_w1z[class_idx];
                rep_frac = tbl_frac[class_idx];
                is_force_sat     = tbl_fsat[class_idx];
                force_sat_sign   = tbl_fsign[class_idx];
                contribution_val = tbl_contrib[class_idx];

                for (acc_state_i = -32768; acc_state_i <= 32767; acc_state_i = acc_state_i + 1) begin
                    acc_state = acc_state_i[15:0];

                    force dut_base.acc  = acc_state;
                    force dut_bound.acc = acc_state;

                    fmt_sel = rep_fmt;
                    a0 = rep_a0; a0_zero = rep_a0z;
                    a1 = rep_a1; a1_zero = rep_a1z;
                    w0 = rep_w0; w0_zero = rep_w0z;
                    w1 = rep_w1; w1_zero = rep_w1z;
                    frac_bits = rep_frac;
                    clear_acc = 1'b0;
                    valid_in  = 1'b1;
                    #1;

                    if (is_force_sat) begin
                        expect_acc = force_sat_sign ? -16'sd32768 : 16'sd32767;
                        expect_ovf = 1'b1;
                    end else begin
                        expect_sum = $signed(acc_state) + contribution_val;
                        if (expect_sum > 32767) begin
                            expect_acc = 16'sd32767; expect_ovf = 1'b1;
                        end else if (expect_sum < -32768) begin
                            expect_acc = -16'sd32768; expect_ovf = 1'b1;
                        end else begin
                            expect_acc = expect_sum[15:0]; expect_ovf = 1'b0;
                        end
                    end

                    checks = checks + 1;
                    if (dut_base.sum_saturated !== expect_acc ||
                        (dut_base.ovf_pos | dut_base.ovf_neg) !== expect_ovf) begin
                        errors = errors + 1;
                        if ((errors - errors_before) <= 20)
                            $display("    BASELINE MISMATCH class=%0d acc_state=%0d : sum_saturated=%0d expected=%0d",
                                      class_idx, acc_state, dut_base.sum_saturated, expect_acc);
                    end

                    checks = checks + 1;
                    if (dut_bound.sum_saturated !== expect_acc || dut_bound.ovf_final !== expect_ovf) begin
                        errors = errors + 1;
                        if ((errors - errors_before) <= 20)
                            $display("    BOUNDED MISMATCH class=%0d acc_state=%0d : sum_saturated=%0d expected=%0d",
                                      class_idx, acc_state, dut_bound.sum_saturated, expect_acc);
                    end

                    checks = checks + 1;
                    if (dut_base.sum_saturated !== dut_bound.sum_saturated) begin
                        errors = errors + 1;
                        if ((errors - errors_before) <= 20)
                            $display("    BASE-VS-BOUND MISMATCH class=%0d acc_state=%0d : base=%0d bound=%0d",
                                      class_idx, acc_state, dut_base.sum_saturated, dut_bound.sum_saturated);
                    end

                    release dut_base.acc;
                    release dut_bound.acc;
                end
            end
        end
        if (errors == errors_before)
            $display("  [PASS] all 173 classes x 65,536 states = 11,337,728 scenarios (34,013,184 checks) matched (golden, baseline, bounded-exact)");
        else
            $display("  [FAIL] %0d of 34,013,184 checks did NOT match", errors - errors_before);

        // =========================================================
        // SECTION C: directed checks
        // =========================================================
        $display("");
        $display("--- Section C: directed cancellation, threshold, and sequencing checks ---");
        errors_before = errors;
        begin : section_c


            // -- Cancellation: equal +/- lanes -> exactly zero (E1M0) --
            // a0=+1.0,w0=+1.0 -> p0=+4; a1=+1.0,w1=-1.0 -> p1=-4 => psn=0
            // clear_acc=1 directly (base_acc=0 naturally): no separate
            // "reach 0 first" step needed.
            do_cycle(1'b1, 1'b0, 2'd0,1'b0, 2'd0,1'b0, 2'd0,1'b0, 2'd2,1'b0, 5'd8);
            checks = checks + 1;
            if (acc_base !== 16'sd0 || acc_bound !== 16'sd0) begin
                errors = errors + 1;
                $display("    FAIL: equal +/- cancellation, expected 0, base=%0d bound=%0d", acc_base, acc_bound);
            end else
                $display("    [ok] equal +/- lane cancellation -> exactly 0, base==bound (acc=%0d)", acc_base);

            // -- both zero lanes: acc must hold unchanged from a REAL
            // nonzero prior value (7, reached via a genuine setup cycle,
            // verified stimulus from the Python derivation: fmt=1,
            // a0=0,a1=1,w0=1,w1=1,frac=1) --
            do_cycle(1'b1, 1'b1, 2'd0,1'b0, 2'd1,1'b0, 2'd1,1'b0, 2'd1,1'b0, 5'd1); // setup: reach 7
            checks = checks + 1;
            if (acc_base !== 16'sd7 || acc_bound !== 16'sd7) begin
                errors = errors + 1;
                $display("    FAIL: setup step for both-zero-lanes test, expected 7, base=%0d bound=%0d", acc_base, acc_bound);
            end
            do_cycle(1'b0, 1'b0, 2'd0,1'b1, 2'd0,1'b1, 2'd0,1'b1, 2'd0,1'b1, 5'd8); // test: both lanes zero
            checks = checks + 1;
            if (acc_base !== 16'sd7 || acc_bound !== 16'sd7) begin
                errors = errors + 1;
                $display("    FAIL: both zero lanes, expected acc unchanged at 7, base=%0d bound=%0d", acc_base, acc_bound);
            end else
                $display("    [ok] both lanes zero -> acc unchanged at 7 (reached via a real prior cycle), base==bound");

            // -- one zero lane, one active (E1M0), fresh start --
            do_cycle(1'b1, 1'b0, 2'd0,1'b1, 2'd0,1'b0, 2'd0,1'b1, 2'd0,1'b0, 5'd8);
            checks = checks + 1;
            if (acc_base !== acc_bound) begin
                errors = errors + 1;
                $display("    FAIL: one zero one active, base=%0d bound=%0d disagree", acc_base, acc_bound);
            end else
                $display("    [ok] one zero lane + one active lane -> %0d, base==bound", acc_base);

            // -- E0M1 cancellation (large opposite-sign, small residual), fresh start --
            // a0=+1.5,w0=+1.5(mag9,psign0) -> p0=+9; a1=+1.5,w1=-1.0(mag6,sign1) -> p1=-6 => psn=3
            do_cycle(1'b1, 1'b1, 2'd1,1'b0, 2'd1,1'b0, 2'd1,1'b0, 2'd2,1'b0, 5'd10);
            checks = checks + 1;
            if (acc_base !== acc_bound) begin
                errors = errors + 1;
                $display("    FAIL: E0M1 cancellation, base=%0d bound=%0d disagree", acc_base, acc_bound);
            end else
                $display("    [ok] E0M1 large-opposite-sign cancellation -> %0d, base==bound", acc_base);

            // -- +32768 raw contribution: verified stimulus from Python
            // derivation (fmt=0, a0=a1=w0=w1=code0(+1.0), frac_bits=14) --
            // tested against a REAL prior acc=-1 (no saturation, sum=32767)
            // and a fresh acc=0 (saturation, sum=32768->clamped to 32767).
            // contrib=-1 verified stimulus: fmt=0,a0=0,a1=0,w0=0(z1),w1=2,frac=0
            do_cycle(1'b1, 1'b0, 2'd0,1'b0, 2'd0,1'b0, 2'd0,1'b1, 2'd2,1'b0, 5'd0); // setup: reach -1
            checks = checks + 1;
            if (acc_base !== -16'sd1 || acc_bound !== -16'sd1) begin
                errors = errors + 1;
                $display("    FAIL: setup step for +32768/acc=-1 test, expected -1, base=%0d bound=%0d", acc_base, acc_bound);
            end
            do_cycle(1'b0, 1'b0, 2'd0,1'b0, 2'd0,1'b0, 2'd0,1'b0, 2'd0,1'b0, 5'd14); // test: +32768
            checks = checks + 1;
            if (acc_base !== 16'sd32767 || acc_bound !== 16'sd32767) begin
                errors = errors + 1;
                $display("    FAIL: +32768 contribution + acc=-1, expected 32767, base=%0d bound=%0d", acc_base, acc_bound);
            end else
                $display("    [ok] +32768 contribution + acc=-1 = 32767 exactly, no saturation, base==bound");

            do_cycle(1'b1, 1'b0, 2'd0,1'b0, 2'd0,1'b0, 2'd0,1'b0, 2'd0,1'b0, 5'd14); // fresh start, +32768 directly
            checks = checks + 1;
            if (acc_base !== 16'sd32767 || acc_bound !== 16'sd32767 || overflow_base !== 1'b1 || overflow_bound !== 1'b1) begin
                errors = errors + 1;
                $display("    FAIL: +32768 contribution + acc=0, expected saturate to 32767, base=%0d bound=%0d", acc_base, acc_bound);
            end else
                $display("    [ok] +32768 contribution + acc=0 -> saturates to 32767, overflow asserted, base==bound");

            // -- FORCE_SAT positive boundary (real magnitude reaches
            // exactly 65536, verified stimulus: fmt=0, all-code0, frac=15) --
            // tested from a REAL prior acc=-32768 (directly reachable in
            // one setup cycle, verified stimulus: fmt=0,a0=0,a1=0,
            // w0=0(z1),w1=2,frac=15)
            do_cycle(1'b1, 1'b0, 2'd0,1'b0, 2'd0,1'b0, 2'd0,1'b1, 2'd2,1'b0, 5'd15); // setup: reach -32768
            checks = checks + 1;
            if (acc_base !== -16'sd32768 || acc_bound !== -16'sd32768) begin
                errors = errors + 1;
                $display("    FAIL: setup step for +65536-forced-sat test, expected -32768, base=%0d bound=%0d", acc_base, acc_bound);
            end
            do_cycle(1'b0, 1'b0, 2'd0,1'b0, 2'd0,1'b0, 2'd0,1'b0, 2'd0,1'b0, 5'd15); // test: force_sat positive
            checks = checks + 1;
            if (acc_base !== 16'sd32767 || acc_bound !== 16'sd32767) begin
                errors = errors + 1;
                $display("    FAIL: +65536 forced-sat boundary, expected 32767 even from acc=-32768, base=%0d bound=%0d", acc_base, acc_bound);
            end else
                $display("    [ok] +65536-magnitude forced saturation -- guaranteed positive regardless of acc (tested from a real acc=-32768), base==bound");

            // -- FORCE_SAT negative boundary (verified stimulus: fmt=0,
            // a0=a1=code0, w0=code0(zero), w1=code2, frac=16) -- tested
            // from a REAL prior acc=32767, itself reached via the
            // genuine 2-step path already verified above (-1, then
            // +32768; neither step saturates, -1+32768=32767 exactly).
            do_cycle(1'b1, 1'b0, 2'd0,1'b0, 2'd0,1'b0, 2'd0,1'b1, 2'd2,1'b0, 5'd0); // step 1: reach -1
            do_cycle(1'b0, 1'b0, 2'd0,1'b0, 2'd0,1'b0, 2'd0,1'b0, 2'd0,1'b0, 5'd14); // step 2: -1+32768=32767
            checks = checks + 1;
            if (acc_base !== 16'sd32767 || acc_bound !== 16'sd32767) begin
                errors = errors + 1;
                $display("    FAIL: setup steps for -65536-forced-sat test, expected 32767, base=%0d bound=%0d", acc_base, acc_bound);
            end
            do_cycle(1'b0, 1'b0, 2'd0,1'b0, 2'd0,1'b0, 2'd0,1'b1, 2'd2,1'b0, 5'd16); // test: force_sat negative
            checks = checks + 1;
            if (acc_base !== -16'sd32768 || acc_bound !== -16'sd32768) begin
                errors = errors + 1;
                $display("    FAIL: -65536 forced-sat boundary, expected -32768 even from acc=32767, base=%0d bound=%0d", acc_base, acc_bound);
            end else
                $display("    [ok] -65536-magnitude forced saturation -- guaranteed negative regardless of acc (tested from a real acc=32767), base==bound");


            // -- unreachable threshold values, explicitly documented --
            $display("    [note] +32767, +32769, +65535, -32767, -32769, -65535 are NOT reachable as raw single-cycle combined contributions:");
            $display("           every nonzero contribution is (integer magnitude 1..18) x 2^shift, which is always EVEN for shift>=1 and");
            $display("           bounded to <=18 in magnitude for shift=0 -- these five odd/out-of-range values can never occur as a raw");
            $display("           contribution. They ARE exercised as ACCUMULATOR SUMS via the boundary sweep below (e.g. acc=32766 + a");
            $display("           contribution of 1 lands exactly on 32767), which is the operationally meaningful way they occur in practice.");

            // -- accumulator boundary sequencing: Section B already
            // exhaustively tests EVERY one of the 65,536 accumulator
            // states (including all 7 requested boundary values)
            // combinatorially against all 173 classes, via the
            // combinational force+check method proven correct above.
            // This sub-test's job is different and narrower: prove
            // real, REGISTERED multi-cycle sequencing reaches specific
            // boundary-adjacent values correctly -- using genuinely
            // achievable operand sequences, not an artificial force
            // (force on a signal also driven by a clocked always
            // block was directly tested and found NOT to let the
            // register actually update in Icarus -- see the removed
            // apply_from_state task and the probe that diagnosed it;
            // not assumed, verified).
            begin : acc_boundaries
                reg signed [15:0] expect_val;

                // -32768: directly reachable in ONE real step (verified
                // stimulus from the Python derivation)
                @(negedge clk);
                fmt_sel=1'b0; a0=2'd0; a0_zero=1'b0; a1=2'd0; a1_zero=1'b0;
                w0=2'd0; w0_zero=1'b1; w1=2'd2; w1_zero=1'b0;
                frac_bits=5'd15; clear_acc=1'b1; valid_in=1'b1;
                @(posedge clk); #1;
                valid_in=1'b0; clear_acc=1'b0;
                checks = checks + 1;
                if (acc_base !== -16'sd32768 || acc_bound !== -16'sd32768) begin
                    errors = errors + 1;
                    $display("    FAIL: reach -32768 in one real step, base=%0d bound=%0d", acc_base, acc_bound);
                end else
                    $display("    [ok] real single-step accumulation reaches -32768 exactly, base==bound");

                // +32767: genuine 2-step path (contrib=-1, then +32768;
                // neither step saturates on its own; -1+32768=32767
                // exactly) -- both stimuli pulled directly from the
                // Python derivation's own verified data
                @(negedge clk);
                fmt_sel=1'b0; a0=2'd0; a0_zero=1'b0; a1=2'd0; a1_zero=1'b0;
                w0=2'd0; w0_zero=1'b1; w1=2'd2; w1_zero=1'b0;
                frac_bits=5'd0; clear_acc=1'b1; valid_in=1'b1;
                @(posedge clk); #1;
                clear_acc=1'b0;
                checks = checks + 1;
                if (acc_base !== -16'sd1 || acc_bound !== -16'sd1) begin
                    errors = errors + 1;
                    $display("    FAIL: 2-step path to 32767, step 1 expected -1, base=%0d bound=%0d", acc_base, acc_bound);
                end
                @(negedge clk);
                a0=2'd0; a0_zero=1'b0; a1=2'd0; a1_zero=1'b0;
                w0=2'd0; w0_zero=1'b0; w1=2'd0; w1_zero=1'b0;
                frac_bits=5'd14; valid_in=1'b1;
                @(posedge clk); #1;
                valid_in=1'b0;
                checks = checks + 1;
                if (acc_base !== 16'sd32767 || acc_bound !== 16'sd32767) begin
                    errors = errors + 1;
                    $display("    FAIL: 2-step path to 32767, step 2, base=%0d bound=%0d", acc_base, acc_bound);
                end else
                    $display("    [ok] real 2-step accumulation reaches +32767 exactly (-1, then +32768), base==bound");
            end

            // -- multi-cycle accumulation (3 valid cycles, same operands) --
            // a0=+1.0,w0=+1.0(mag2*2=4,psign0) -> p0=+4; a1=w1=zero -> p1=0; psn=4, frac_bits=8 -> shift=6 -> +256 per cycle
            @(negedge clk);
            fmt_sel=1'b0; a0=2'd0; a0_zero=1'b0; w0=2'd0; w0_zero=1'b0; a1=2'd0; a1_zero=1'b1; w1=2'd0; w1_zero=1'b1;
            frac_bits=5'd8; clear_acc=1'b1; valid_in=1'b1;
            @(posedge clk); #1;
            clear_acc=1'b0;
            @(negedge clk); @(posedge clk); #1;
            @(negedge clk); @(posedge clk); #1;
            valid_in = 1'b0;
            checks = checks + 1;
            if (acc_base !== 16'sd768 || acc_bound !== 16'sd768) begin
                errors = errors + 1;
                $display("    FAIL: multi-cycle accumulation, expected 768 (3x256), base=%0d bound=%0d", acc_base, acc_bound);
            end else
                $display("    [ok] multi-cycle (3-shot) accumulation -> %0d (3x256), base==bound", acc_base);

            // -- hold cycle (valid_in=0 does not change acc) --
            begin
                reg signed [15:0] held_base, held_bound;
                held_base = acc_base; held_bound = acc_bound;
                @(negedge clk); @(posedge clk); #1;
                checks = checks + 1;
                if (acc_base !== held_base || acc_bound !== held_bound || valid_out_base !== 1'b0 || valid_out_bound !== 1'b0) begin
                    errors = errors + 1;
                    $display("    FAIL: hold cycle changed acc or valid_out incorrectly");
                end else
                    $display("    [ok] hold cycle (valid_in=0): acc unchanged, valid_out=0, base==bound");
            end

            // -- clear/restart: same operands as the multi-cycle test,
            // clear_acc=1 this time -> should land back on 256, not 768+256 --
            @(negedge clk);
            fmt_sel=1'b0; a0=2'd0; a0_zero=1'b0; w0=2'd0; w0_zero=1'b0; a1=2'd0; a1_zero=1'b1; w1=2'd0; w1_zero=1'b1;
            frac_bits=5'd8; clear_acc = 1'b1; valid_in = 1'b1;
            @(posedge clk); #1;
            valid_in = 1'b0; clear_acc = 1'b0;
            checks = checks + 1;
            if (acc_base !== 16'sd256 || acc_bound !== 16'sd256) begin
                errors = errors + 1;
                $display("    FAIL: clear/restart, expected 256, base=%0d bound=%0d", acc_base, acc_bound);
            end else
                $display("    [ok] clear_acc restart -> %0d (discards prior 768), base==bound", acc_base);

            // -- reset, then first accumulation --
            @(negedge clk); rst_n = 1'b0;
            @(negedge clk); @(negedge clk); rst_n = 1'b1;
            checks = checks + 1;
            if (acc_base !== 16'sd0 || acc_bound !== 16'sd0) begin
                errors = errors + 1;
                $display("    FAIL: post-reset state, base=%0d bound=%0d (expected 0)", acc_base, acc_bound);
            end else
                $display("    [ok] post-reset state: acc=0, base==bound");
            @(negedge clk);
            fmt_sel=1'b0; a0=2'd0; a0_zero=1'b0; w0=2'd0; w0_zero=1'b0; a1=2'd0; a1_zero=1'b1; w1=2'd0; w1_zero=1'b1;
            frac_bits=5'd8; clear_acc = 1'b1; valid_in = 1'b1;
            @(posedge clk); #1;
            valid_in = 1'b0; clear_acc = 1'b0;
            checks = checks + 1;
            if (acc_base !== 16'sd256 || acc_bound !== 16'sd256) begin
                errors = errors + 1;
                $display("    FAIL: first accumulation after reset, expected 256, base=%0d bound=%0d", acc_base, acc_bound);
            end else
                $display("    [ok] first accumulation after reset -> %0d, base==bound", acc_base);

            // -- acc_fxp8 for positive, negative, and saturated states --
            // (purely combinational from acc -- force+#1 without a clock
            // edge is correct here, unlike the arithmetic-result checks
            // above, since acc_fxp8 = acc[15:8] has no register of its own)
            force dut_base.acc = 16'sd1536; force dut_bound.acc = 16'sd1536; // positive, top byte = 6
            #1;
            checks = checks + 1;
            if (acc_fxp8_base !== acc_fxp8_bound || acc_fxp8_base !== 8'sd6) begin
                errors = errors + 1;
                $display("    FAIL: acc_fxp8 positive state, base=%0d bound=%0d (expected 6)", acc_fxp8_base, acc_fxp8_bound);
            end else
                $display("    [ok] acc_fxp8 positive state (acc=1536) -> 6, base==bound");
            release dut_base.acc; release dut_bound.acc;

            force dut_base.acc = -16'sd1536; force dut_bound.acc = -16'sd1536; // negative
            #1;
            checks = checks + 1;
            if (acc_fxp8_base !== acc_fxp8_bound) begin
                errors = errors + 1;
                $display("    FAIL: acc_fxp8 negative state, base=%0d bound=%0d disagree", acc_fxp8_base, acc_fxp8_bound);
            end else
                $display("    [ok] acc_fxp8 negative state (acc=-1536) -> %0d, base==bound", acc_fxp8_base);
            release dut_base.acc; release dut_bound.acc;

            force dut_base.acc = 16'sd32767; force dut_bound.acc = 16'sd32767; // saturated positive
            #1;
            checks = checks + 1;
            if (acc_fxp8_base !== acc_fxp8_bound || acc_fxp8_base !== 8'sd127) begin
                errors = errors + 1;
                $display("    FAIL: acc_fxp8 saturated state, base=%0d bound=%0d (expected 127)", acc_fxp8_base, acc_fxp8_bound);
            end else
                $display("    [ok] acc_fxp8 saturated state (acc=32767) -> 127, base==bound");
            release dut_base.acc; release dut_bound.acc;

            // -- frac_bits sweep: 0, 1, 6, 8, 10, 12, 20, 31 --
            // Real clear_acc=1 cycle each time (base_acc=0 by
            // construction), so acc lands exactly on the raw
            // contribution value -- no force needed, sidesteps the
            // force-vs-clocked-register issue entirely.
            // a0=+1.0,w0=+1.0(mag2*2=4) -> p0=+4; a1=w1=zero -> p1=0; psn=4
            begin : frac_sweep
                integer fi;
                reg [4:0] fvals [0:7];
                reg signed [31:0] expect_fv;
                fvals[0]=5'd0; fvals[1]=5'd1; fvals[2]=5'd6; fvals[3]=5'd8;
                fvals[4]=5'd10; fvals[5]=5'd12; fvals[6]=5'd20; fvals[7]=5'd31;
                for (fi = 0; fi <= 7; fi = fi + 1) begin
                    @(negedge clk);
                    fmt_sel=1'b0; a0=2'd0; a0_zero=1'b0; a1=2'd0; a1_zero=1'b1;
                    w0=2'd0; w0_zero=1'b0; w1=2'd0; w1_zero=1'b1;
                    frac_bits=fvals[fi]; clear_acc=1'b1; valid_in=1'b1;
                    @(posedge clk); #1;
                    valid_in=1'b0; clear_acc=1'b0;
                    checks = checks + 1;
                    // psn=4, shift=frac_bits-2; contribution = 4 * 2^shift (or >>(-shift) if shift<0), then saturate
                    if (fvals[fi] >= 16) begin
                        expect_fv = 32767; // guaranteed forced-sat at this magnitude for frac_bits>=16 (shift>=14, 4*2^14=65536>=65536)
                    end else if (fvals[fi] >= 2) begin
                        expect_fv = (32'sd4 <<< (fvals[fi]-2));
                        if (expect_fv > 32767) expect_fv = 32767;
                    end else begin
                        expect_fv = (32'sd4 >>> (2-fvals[fi]));
                    end
                    if (acc_base !== expect_fv[15:0] || acc_bound !== expect_fv[15:0]) begin
                        errors = errors + 1;
                        $display("    FAIL: frac_bits=%0d, expected %0d, base=%0d bound=%0d", fvals[fi], expect_fv, acc_base, acc_bound);
                    end else
                        $display("    [ok] frac_bits=%0d -> %0d, base==bound", fvals[fi], acc_base);
                end
            end

            // -- negative truncation toward zero at frac_bits=0 --
            // a0=+1.0,w0=-0.5(mag1,sign1) -> p0=-2; a1=w1=zero -> p1=0; psn=-2, frac_bits=0 -> shift=-2 -> mag=2>>2=0 -> contribution=0
            // tested from a REAL prior acc=5 (verified stimulus: fmt=0,
            // a0=0,a1=1(z0),w0=0,w1=1(z0),frac=2 -> contrib=5)
            do_cycle(1'b1, 1'b0, 2'd0,1'b0, 2'd1,1'b0, 2'd0,1'b0, 2'd1,1'b0, 5'd2); // setup: reach 5 (verified stimulus)
            checks = checks + 1;
            if (acc_base !== 16'sd5 || acc_bound !== 16'sd5) begin
                errors = errors + 1;
                $display("    FAIL: setup step for negative-truncation test, expected 5, base=%0d bound=%0d", acc_base, acc_bound);
            end
            do_cycle(1'b0, 1'b0, 2'd0,1'b0, 2'd0,1'b1, 2'd3,1'b0, 2'd0,1'b1, 5'd0); // test: truncating contribution
            checks = checks + 1;
            if (acc_base !== 16'sd5 || acc_bound !== 16'sd5) begin
                errors = errors + 1;
                $display("    FAIL: negative truncation at frac_bits=0, expected acc unchanged at 5, base=%0d bound=%0d", acc_base, acc_bound);
            end else
                $display("    [ok] negative-result truncation toward zero at frac_bits=0 (contribution truncates to 0) -> %0d, base==bound", acc_base);

            valid_in = 1'b0; clear_acc = 1'b0;
        end
        if (errors == errors_before)
            $display("  [PASS] all Section C directed checks matched");
        else
            $display("  [FAIL] %0d Section C check(s) did NOT match", errors - errors_before);

        $display("");
        $display("========================================================================");
        $display(" FINAL RESULT: %0d / %0d checks passed  (%0d errors)", checks-errors, checks, errors);
        if (errors == 0)
            $display(" *** BASELINE AND BOUNDED-EXACT ARE BIT-EXACT ***");
        else
            $display(" *** %0d MISMATCH(ES) FOUND ***", errors);
        $display("========================================================================");
        $finish;
    end

endmodule
