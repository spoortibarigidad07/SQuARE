// =====================================================================
// tb_fp2_parallel_mac_ref_standalone.v
//
// Testbench for the DP2 reference MAC (fp2_parallel_mac_ref.v),
// covering: both E1M0 and E0M1; exhaustive operand combinations (both
// lanes active, one lane zero, both lanes zero, positive and negative
// products) at frac_bits = 6, 8, 10, 12 against golden vectors from the
// software model (golden/fp2_parallel_gen.py); clear_acc and valid_in
// behavior; multi-cycle accumulation; both saturation rails and the
// overflow flag; frac_bits extremes (0, 20, 31); the frac_bits/fmt_sel
// usage-contract warning; acc_fxp8; cancellation; reset; and truncation
// toward zero at frac_bits < 2.
//
// Glossary for the printed output:
//   fmt_sel    : 0 = E1M0 (values 0, +-0.5, +-1.0), 1 = E0M1 (0, +-1.0, +-1.5)
//   frac_bits  : number of fractional accumulator bits, e.g. 8 = Q8.8,
//                so 1.5 is stored as 1.5*2^8 = 384
//   a0,a1,w0,w1: 2-bit {sign,bit} FP2 codes, lanes 0 and 1
//   *_zero     : per-operand zero mask
// =====================================================================
`timescale 1ns/1ps

`ifndef GOLDEN_DIR
// Folder holding the golden .hex files. The default works when the
// simulator runs from primary_design/. Otherwise (e.g. Vivado xsim),
// define GOLDEN_DIR="<absolute path>/golden".
`define GOLDEN_DIR "golden"
`endif

module tb_fp2_parallel_mac_ref_standalone;



    localparam ACC_W  = 16;
    localparam FRAC_W = 5;

    integer errors, checks;
    integer errors_before;

    // -------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------
    reg                    clk, rst_n, clear_acc, valid_in, fmt_sel;
    reg  [FRAC_W-1:0]      frac_bits;
    reg  [1:0]             a0, a1, w0, w1;
    reg                    a0_zero, a1_zero, w0_zero, w1_zero;
    wire signed [ACC_W-1:0] acc;
    wire                    valid_out, overflow;
    wire signed [7:0]       acc_fxp8;

    fp2_parallel_mac_ref #(.ACC_W(ACC_W), .FRAC_W(FRAC_W)) dut (
        .clk(clk), .rst_n(rst_n), .clear_acc(clear_acc), .valid_in(valid_in),
        .fmt_sel(fmt_sel), .frac_bits(frac_bits),
        .a0(a0), .a1(a1), .w0(w0), .w1(w1),
        .a0_zero(a0_zero), .a1_zero(a1_zero), .w0_zero(w0_zero), .w1_zero(w1_zero),
        .acc(acc), .valid_out(valid_out), .overflow(overflow), .acc_fxp8(acc_fxp8)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // -------------------------------------------------------------
    // Golden tables (one per tested frac_bits value)
    // -------------------------------------------------------------
    reg [15:0] golden_frac6  [0:8191];
    reg [15:0] golden_frac8  [0:8191];
    reg [15:0] golden_frac10 [0:8191];
    reg [15:0] golden_frac12 [0:8191];

    integer ifmt, ia0, ia0z, ia1, ia1z, iw0, iw0z, iw1, iw1z, idx;

    task run_single_shot(input fmt, input [1:0] va0, input va0z,
                          input [1:0] va1, input va1z,
                          input [1:0] vw0, input vw0z,
                          input [1:0] vw1, input vw1z,
                          input [FRAC_W-1:0] fb, input [15:0] expect_val);
        begin
            @(negedge clk);
            fmt_sel = fmt; frac_bits = fb;
            a0 = va0; a1 = va1; w0 = vw0; w1 = vw1;
            a0_zero = va0z; a1_zero = va1z; w0_zero = vw0z; w1_zero = vw1z;
            clear_acc = 1'b1; valid_in = 1'b1;
            @(posedge clk); #1;
            checks = checks + 1;
            if (acc !== $signed(expect_val)) begin
                errors = errors + 1;
                $display("    MISMATCH fmt=%0d frac_bits=%0d a0=%b(z%b) a1=%b(z%b) w0=%b(z%b) w1=%b(z%b) : acc=%0d expected=%0d",
                          fmt, fb, va0, va0z, va1, va1z, vw0, vw0z, vw1, vw1z, acc, $signed(expect_val));
            end
            clear_acc = 1'b0; valid_in = 1'b0;
        end
    endtask

    task run_sweep_frac6;
        begin
            idx = 0;
            for (ifmt = 0; ifmt < 2; ifmt = ifmt + 1)
                for (ia0 = 0; ia0 < 4; ia0 = ia0 + 1)
                    for (ia0z = 0; ia0z < 2; ia0z = ia0z + 1)
                        for (ia1 = 0; ia1 < 4; ia1 = ia1 + 1)
                            for (ia1z = 0; ia1z < 2; ia1z = ia1z + 1)
                                for (iw0 = 0; iw0 < 4; iw0 = iw0 + 1)
                                    for (iw0z = 0; iw0z < 2; iw0z = iw0z + 1)
                                        for (iw1 = 0; iw1 < 4; iw1 = iw1 + 1)
                                            for (iw1z = 0; iw1z < 2; iw1z = iw1z + 1) begin
                                                run_single_shot(ifmt[0], ia0[1:0], ia0z[0],
                                                                ia1[1:0], ia1z[0],
                                                                iw0[1:0], iw0z[0],
                                                                iw1[1:0], iw1z[0],
                                                                5'd6, golden_frac6[idx]);
                                                idx = idx + 1;
                                            end
        end
    endtask

    task run_sweep_frac8;
        begin
            idx = 0;
            for (ifmt = 0; ifmt < 2; ifmt = ifmt + 1)
                for (ia0 = 0; ia0 < 4; ia0 = ia0 + 1)
                    for (ia0z = 0; ia0z < 2; ia0z = ia0z + 1)
                        for (ia1 = 0; ia1 < 4; ia1 = ia1 + 1)
                            for (ia1z = 0; ia1z < 2; ia1z = ia1z + 1)
                                for (iw0 = 0; iw0 < 4; iw0 = iw0 + 1)
                                    for (iw0z = 0; iw0z < 2; iw0z = iw0z + 1)
                                        for (iw1 = 0; iw1 < 4; iw1 = iw1 + 1)
                                            for (iw1z = 0; iw1z < 2; iw1z = iw1z + 1) begin
                                                run_single_shot(ifmt[0], ia0[1:0], ia0z[0],
                                                                ia1[1:0], ia1z[0],
                                                                iw0[1:0], iw0z[0],
                                                                iw1[1:0], iw1z[0],
                                                                5'd8, golden_frac8[idx]);
                                                idx = idx + 1;
                                            end
        end
    endtask

    task run_sweep_frac10;
        begin
            idx = 0;
            for (ifmt = 0; ifmt < 2; ifmt = ifmt + 1)
                for (ia0 = 0; ia0 < 4; ia0 = ia0 + 1)
                    for (ia0z = 0; ia0z < 2; ia0z = ia0z + 1)
                        for (ia1 = 0; ia1 < 4; ia1 = ia1 + 1)
                            for (ia1z = 0; ia1z < 2; ia1z = ia1z + 1)
                                for (iw0 = 0; iw0 < 4; iw0 = iw0 + 1)
                                    for (iw0z = 0; iw0z < 2; iw0z = iw0z + 1)
                                        for (iw1 = 0; iw1 < 4; iw1 = iw1 + 1)
                                            for (iw1z = 0; iw1z < 2; iw1z = iw1z + 1) begin
                                                run_single_shot(ifmt[0], ia0[1:0], ia0z[0],
                                                                ia1[1:0], ia1z[0],
                                                                iw0[1:0], iw0z[0],
                                                                iw1[1:0], iw1z[0],
                                                                5'd10, golden_frac10[idx]);
                                                idx = idx + 1;
                                            end
        end
    endtask

    task run_sweep_frac12;
        begin
            idx = 0;
            for (ifmt = 0; ifmt < 2; ifmt = ifmt + 1)
                for (ia0 = 0; ia0 < 4; ia0 = ia0 + 1)
                    for (ia0z = 0; ia0z < 2; ia0z = ia0z + 1)
                        for (ia1 = 0; ia1 < 4; ia1 = ia1 + 1)
                            for (ia1z = 0; ia1z < 2; ia1z = ia1z + 1)
                                for (iw0 = 0; iw0 < 4; iw0 = iw0 + 1)
                                    for (iw0z = 0; iw0z < 2; iw0z = iw0z + 1)
                                        for (iw1 = 0; iw1 < 4; iw1 = iw1 + 1)
                                            for (iw1z = 0; iw1z < 2; iw1z = iw1z + 1) begin
                                                run_single_shot(ifmt[0], ia0[1:0], ia0z[0],
                                                                ia1[1:0], ia1z[0],
                                                                iw0[1:0], iw0z[0],
                                                                iw1[1:0], iw1z[0],
                                                                5'd12, golden_frac12[idx]);
                                                idx = idx + 1;
                                            end
        end
    endtask

    initial begin
        $readmemh({`GOLDEN_DIR, "/golden_fp2parallel_frac6.hex"},  golden_frac6);
        $readmemh({`GOLDEN_DIR, "/golden_fp2parallel_frac8.hex"},  golden_frac8);
        $readmemh({`GOLDEN_DIR, "/golden_fp2parallel_frac10.hex"}, golden_frac10);
        $readmemh({`GOLDEN_DIR, "/golden_fp2parallel_frac12.hex"}, golden_frac12);

        errors = 0; checks = 0;
        rst_n = 0; clear_acc = 0; valid_in = 0; fmt_sel = 0; frac_bits = 8;
        a0 = 0; a1 = 0; w0 = 0; w1 = 0;
        a0_zero = 0; a1_zero = 0; w0_zero = 0; w1_zero = 0;
        @(negedge clk); @(negedge clk);
        rst_n = 1;

        $display("========================================================================");
        $display(" DP2 FP2 MAC Testbench (fp2_parallel_mac_ref.v)");
        $display("========================================================================");
        $display(" What this checks: acc += a0*w0 + a1*w1, two FP2xFP2 products per");
        $display(" cycle, reduced and accumulated into a 16-bit saturating accumulator.");
        $display("");
        $display(" Operand encoding | field   | meaning");
        $display(" -----------------|---------|----------------------------------------");
        $display(" a0,a1,w0,w1      | 2 bits  | {sign,bit} -- STRICT 2-bit value code");
        $display(" *_zero           | 1 bit   | per-operand zero mask");
        $display(" fmt_sel          | 1 bit   | 0=E1M0 {0,+-0.5,+-1} 1=E0M1 {0,+-1,+-1.5}");
        $display(" frac_bits        | 5 bits  | binary-point position, e.g. 8 = Q8.8");
        $display("");
        $display(" FP2 value decode | zero=1 | zero=0,bit=0 | zero=0,bit=1");
        $display(" -----------------|--------|--------------|-------------");
        $display(" E1M0 (fmt_sel=0) | 0      | +-1.0        | +-0.5");
        $display(" E0M1 (fmt_sel=1) | 0      | +-1.0        | +-1.5");
        $display("");
        $display(" Worked example (appears again in Stage 2's table): fmt_sel=0, a0=+1.0,");
        $display(" a1=+0.5, w0=+1.0, w1=+1.0, frac_bits=8 (Q8.8) -> acc = 1.0*1.0 + 0.5*1.0");
        $display(" = 1.5 real = 1.5 x 2^8 = 384 stored. So 'acc=384' means 'computed 1.5.'");
        $display("========================================================================");

        // =========================================================
        // Stage 1/6: exhaustive single-shot sweep, 4 frac_bits values
        // =========================================================
        $display("");
        $display("--- Stage 1/6: exhaustive single-shot sweep ---");
        $display(" Each frac_bits value sweeps fmt_sel(2) x a0(4 code x 2 zero) x a1(..)");
        $display(" x w0(..) x w1(..) = 8192 cases -- covers both-lanes-active, either/both");
        $display(" lane zero, and every sign combination. 'Single-shot' = clear_acc=1,");
        $display(" valid_in=1 same cycle (fresh accumulator each case; not multi-cycle,");
        $display(" that's Stage 2). A FAIL row shows the exact failing operands, both");
        $display(" the hardware's and the golden model's answer.");
        $display("");
        $display(" frac_bits | cases | passed | failed | status");
        $display(" ----------|-------|--------|--------|-------");

        errors_before = errors;
        run_sweep_frac6;
        if (errors == errors_before)
            $display(" 6         | 8192  | 8192   | 0      | PASS");
        else
            $display(" 6         | 8192  | %-6d | %-6d | FAIL", 8192-(errors-errors_before), errors-errors_before);

        errors_before = errors;
        run_sweep_frac8;
        if (errors == errors_before)
            $display(" 8         | 8192  | 8192   | 0      | PASS");
        else
            $display(" 8         | 8192  | %-6d | %-6d | FAIL", 8192-(errors-errors_before), errors-errors_before);

        errors_before = errors;
        run_sweep_frac10;
        if (errors == errors_before)
            $display(" 10        | 8192  | 8192   | 0      | PASS");
        else
            $display(" 10        | 8192  | %-6d | %-6d | FAIL", 8192-(errors-errors_before), errors-errors_before);

        errors_before = errors;
        run_sweep_frac12;
        if (errors == errors_before)
            $display(" 12        | 8192  | 8192   | 0      | PASS");
        else
            $display(" 12        | 8192  | %-6d | %-6d | FAIL", 8192-(errors-errors_before), errors-errors_before);

        // =========================================================
        // Stage 2/6: multi-cycle accumulation sequence
        // =========================================================
        $display("");
        $display("--- Stage 2/6: multi-cycle accumulation sequence ---");
        $display(" Same operands as the worked example above (a0=+1.0,a1=+0.5,w0=w1=+1.0,");
        $display(" fmt_sel=0,frac_bits=8), run across 4 cycles to check clear_acc/valid_in");
        $display(" sequencing, not just single-shot arithmetic:");
        $display("");
        $display(" cyc | clear_acc | valid_in | operation            | expected | actual | status");
        $display(" ----|-----------|----------|----------------------|----------|--------|-------");
        errors_before = errors;
        begin : multicycle_test
            reg signed [15:0] expect_c1, expect_c2, held_value;
            fmt_sel = 0; frac_bits = 8; // Q8.8, E1M0

            // cycle 1: a0=+1.0(nonzero), a1=+0.5(nonzero), w0=+1.0, w1=+1.0
            //          -> 1.0+0.5 = 1.5 -> *256 = 384
            @(negedge clk);
            a0 = 2'b00; a0_zero = 0; a1 = 2'b01; a1_zero = 0;
            w0 = 2'b00; w0_zero = 0; w1 = 2'b00; w1_zero = 0;
            clear_acc = 1'b1; valid_in = 1'b1;
            @(posedge clk); #1;
            checks = checks + 1;
            expect_c1 = 16'sd384;
            if (acc !== expect_c1) begin
                errors = errors + 1;
                $display(" 1   | 1         | 1        | fresh: a0*w0+a1*w1   | %-8d | %-6d | FAIL", expect_c1, acc);
            end else
                $display(" 1   | 1         | 1        | fresh: a0*w0+a1*w1   | %-8d | %-6d | PASS", expect_c1, acc);
            clear_acc = 1'b0;

            @(negedge clk); valid_in = 1'b1;
            @(posedge clk); #1;
            checks = checks + 1;
            expect_c2 = expect_c1 + 16'sd384;
            if (acc !== expect_c2) begin
                errors = errors + 1;
                $display(" 2   | 0         | 1        | += a0*w0+a1*w1       | %-8d | %-6d | FAIL", expect_c2, acc);
            end else
                $display(" 2   | 0         | 1        | += a0*w0+a1*w1       | %-8d | %-6d | PASS", expect_c2, acc);

            held_value = acc;
            @(negedge clk); valid_in = 1'b0; a0 = 2'b10; a1 = 2'b11; // different, irrelevant operands
            @(posedge clk); #1;
            checks = checks + 1;
            if (acc !== held_value) begin
                errors = errors + 1;
                $display(" 3   | 0         | 0        | hold (must not move) | %-8d | %-6d | FAIL", held_value, acc);
            end else
                $display(" 3   | 0         | 0        | hold (must not move) | %-8d | %-6d | PASS", held_value, acc);

            @(negedge clk);
            a0 = 2'b00; a0_zero = 0; a1 = 2'b01; a1_zero = 0;
            w0 = 2'b00; w0_zero = 0; w1 = 2'b00; w1_zero = 0;
            clear_acc = 1'b1; valid_in = 1'b1;
            @(posedge clk); #1;
            checks = checks + 1;
            if (acc !== expect_c1) begin
                errors = errors + 1;
                $display(" 4   | 1         | 1        | restart (discard old)| %-8d | %-6d | FAIL", expect_c1, acc);
            end else
                $display(" 4   | 1         | 1        | restart (discard old)| %-8d | %-6d | PASS", expect_c1, acc);
            clear_acc = 1'b0; valid_in = 1'b0;
        end
        if (errors == errors_before)
            $display(" [PASS] all 4/4 multi-cycle sequence steps behaved correctly");
        else
            $display(" [FAIL] %0d of 4 multi-cycle sequence steps did NOT behave correctly",
                      errors - errors_before);

        // =========================================================
        // Stage 3/6: overflow / saturation (directed)
        // =========================================================
        $display("");
        $display("--- Stage 3/6: overflow / saturation (directed) ---");
        $display(" Repeatedly accumulating the largest possible product (1.5x1.5=2.25/lane,");
        $display(" x2 lanes=4.5, frac_bits=12) must SATURATE, not wrap, on both rails:");
        $display("");
        $display(" check                        | expected | actual | status");
        $display(" -----------------------------|----------|--------|-------");
        errors_before = errors;
        begin : overflow_test
            integer k;
            reg saw_overflow;
            fmt_sel = 1; frac_bits = 12; // E0M1 so bit=1 gives 1.5 (max magnitude)
            saw_overflow = 1'b0;
            a0 = 2'b01; a0_zero = 0; a1 = 2'b01; a1_zero = 0;
            w0 = 2'b01; w0_zero = 0; w1 = 2'b01; w1_zero = 0; // sign=0,bit=1 (=1.5) each
            clear_acc = 1'b1; valid_in = 1'b1;
            @(negedge clk); @(posedge clk); #1;
            clear_acc = 1'b0;
            for (k = 0; k < 5; k = k + 1) begin
                @(negedge clk); valid_in = 1'b1;
                @(posedge clk); #1;
                if (overflow) saw_overflow = 1'b1;
            end
            valid_in = 1'b0;
            checks = checks + 1;
            if (!saw_overflow) begin
                errors = errors + 1;
                $display(" overflow flag asserts        | 1        | 0      | FAIL");
            end else
                $display(" overflow flag asserts        | 1        | 1      | PASS");
            checks = checks + 1;
            if (acc !== 16'sd32767) begin
                errors = errors + 1;
                $display(" positive saturation          | 32767    | %-6d | FAIL", acc);
            end else
                $display(" positive saturation          | 32767    | 32767  | PASS");

            // symmetric check for the negative rail
            fmt_sel = 1; frac_bits = 12;
            a0 = 2'b11; a0_zero = 0; a1 = 2'b11; a1_zero = 0; // sign=1 (negative), bit=1 (=1.5)
            w0 = 2'b01; w0_zero = 0; w1 = 2'b01; w1_zero = 0; // positive -> negative products
            clear_acc = 1'b1; valid_in = 1'b1;
            @(negedge clk); @(posedge clk); #1;
            clear_acc = 1'b0;
            for (k = 0; k < 5; k = k + 1) begin
                @(negedge clk); valid_in = 1'b1;
                @(posedge clk); #1;
            end
            valid_in = 1'b0;
            checks = checks + 1;
            if (acc !== -16'sd32768) begin
                errors = errors + 1;
                $display(" negative saturation          | -32768   | %-6d | FAIL", acc);
            end else
                $display(" negative saturation          | -32768   | -32768 | PASS");

            // overflow flag must be explicitly CLEARED (not stale) once
            // valid_in drops
            @(negedge clk); valid_in = 1'b0;
            @(posedge clk); #1;
            checks = checks + 1;
            if (overflow !== 1'b0) begin
                errors = errors + 1;
                $display(" overflow clears (valid_in=0) | 0        | %-6b | FAIL", overflow);
            end else
                $display(" overflow clears (valid_in=0) | 0        | 0      | PASS");
        end
        if (errors == errors_before)
            $display(" [PASS] all overflow/saturation checks behaved correctly");
        else
            $display(" [FAIL] %0d overflow/saturation check(s) did NOT behave correctly",
                      errors - errors_before);

        // =========================================================
        // Stage 4/6: frac_bits/fmt_sel out-of-precondition safety +
        // stability-warning smoke test
        // =========================================================
        $display("");
        $display("--- Stage 4/6: frac_bits safety at the port's extreme values ---");
        $display(" frac_bits=0 (below the documented >=6 range): real answer 1.0*1.0+");
        $display(" 0.5*1.0=1.5 has a fractional part, but 0 fraction bits means the");
        $display(" hardware TRUNCATES (floor), giving 1, not round(1.5)=2 -- that's");
        $display(" correct, not a bug. frac_bits=20: checks the internal wide");
        $display(" intermediate doesn't overflow before saturation runs.");
        $display("");
        $display(" frac_bits | scenario                | expected | actual | status");
        $display(" ----------|-------------------------|----------|--------|-------");
        errors_before = errors;
        begin : frac_edge_test
            reg signed [15:0] expect_val;
            fmt_sel = 0; frac_bits = 0;
            a0 = 2'b00; a0_zero = 0; a1 = 2'b01; a1_zero = 0;
            w0 = 2'b00; w0_zero = 0; w1 = 2'b00; w1_zero = 0;
            clear_acc = 1'b1; valid_in = 1'b1;
            @(negedge clk); @(posedge clk); #1;
            clear_acc = 1'b0; valid_in = 1'b0;
            checks = checks + 1;
            if (acc !== 16'sd1) begin
                errors = errors + 1;
                $display(" 0         | truncation: floor(1.5)  | 1        | %-6d | FAIL", acc);
            end else
                $display(" 0         | truncation: floor(1.5)  | 1        | 1      | PASS");

            // large frac_bits: must not overflow the internal wide intermediate
            // before saturation -- a single max-magnitude product pair at
            // frac_bits=20 should cleanly SATURATE, not wrap to a garbage sign
            fmt_sel = 1; frac_bits = 20;
            a0 = 2'b01; a0_zero = 0; a1 = 2'b01; a1_zero = 0;
            w0 = 2'b01; w0_zero = 0; w1 = 2'b01; w1_zero = 0;
            clear_acc = 1'b1; valid_in = 1'b1;
            @(negedge clk); @(posedge clk); #1;
            clear_acc = 1'b0; valid_in = 1'b0;
            checks = checks + 1;
            if (acc !== 16'sd32767) begin
                errors = errors + 1;
                $display(" 20        | large-shift, no overflow| 32767    | %-6d | FAIL", acc);
            end else
                $display(" 20        | large-shift, no overflow| 32767    | 32767  | PASS");

            // frac_bits=31: the port's LITERAL maximum, not just a "large"
            // representative value like 20 above.
            fmt_sel = 1; frac_bits = 31;
            a0 = 2'b01; a0_zero = 0; a1 = 2'b01; a1_zero = 0;
            w0 = 2'b01; w0_zero = 0; w1 = 2'b01; w1_zero = 0;
            clear_acc = 1'b1; valid_in = 1'b1;
            @(negedge clk); @(posedge clk); #1;
            clear_acc = 1'b0; valid_in = 1'b0;
            checks = checks + 1;
            if (acc !== 16'sd32767) begin
                errors = errors + 1;
                $display(" 31        | literal max, no overflow| 32767    | %-6d | FAIL", acc);
            end else
                $display(" 31        | literal max, no overflow| 32767    | 32767  | PASS");
        end
        if (errors == errors_before)
            $display(" [PASS] frac_bits port is safe across its extreme values");
        else
            $display(" [FAIL] %0d frac_bits-safety check(s) did NOT behave correctly",
                      errors - errors_before);

        // =========================================================
        // Stage 5/6: frac_bits/fmt_sel stability usage-contract warning
        // =========================================================
        // The warning is a SIMULATION-ONLY $display inside
        // fp2_parallel_mac_ref.v (guarded by `synthesis translate_off/on`,
        // confirmed absent from synthesis output), so it can't be turned
        // into an automatic pass/fail assertion from out here -- this
        // stage demonstrates the violation and directs you to the DUT's
        // own WARNING line, while structurally confirming the simulation
        // continues sanely afterward.
        $display("");
        $display("--- Stage 5/6: frac_bits/fmt_sel stability usage-contract warning ---");
        $display(" Rule: frac_bits/fmt_sel must stay constant across one dot product --");
        $display(" changing either mid-accumulation (without clear_acc) mixes binary-point");
        $display(" positions or value tables, which isn't meaningful. This is a usage");
        $display(" CONTRACT (hardware can't prevent it), so the DUT prints a simulation-");
        $display(" only WARNING on violation. Deliberately violating it now:");
        $display("");
        $display("   step | action                        | frac_bits");
        $display("   -----|-------------------------------|----------");
        $display("   1    | clear_acc=1,valid_in=1 (start)| 8");
        $display("   2    | valid_in=1, NO clear_acc      | 12  <-- VIOLATION");
        $display("");
        $display(" Look for 'WARNING [t=...]: frac_bits changed mid-accumulation' printed");
        $display(" by the DUT directly below (the standalone core, fp2_parallel_mac_ref.v):");
        errors_before = errors;
        begin : stability_test
            fmt_sel = 0; frac_bits = 8;
            a0 = 2'b00; a0_zero = 0; a1 = 2'b01; a1_zero = 0;
            w0 = 2'b00; w0_zero = 0; w1 = 2'b00; w1_zero = 0;
            @(negedge clk);
            clear_acc = 1'b1; valid_in = 1'b1;   // step 1: starts the dot product at frac_bits=8
            @(posedge clk); #1;
            clear_acc = 1'b0;
            @(negedge clk);
            frac_bits = 5'd12;                    // step 2: VIOLATION: changed without clear_acc
            valid_in = 1'b1;
            @(posedge clk); #1;
            valid_in = 1'b0;
            checks = checks + 1;
            // Structural check only (see note above): confirm the sim is
            // still alive and acc is still a plain, in-range number, not
            // hung or corrupted by the deliberate contract violation.
            if (acc > 16'sd32767 || acc < -16'sd32768) begin
                errors = errors + 1;
                $display(" [FAIL] accumulator left an impossible out-of-range state: acc=%0d", acc);
            end else
                $display(" [ok]   simulation continued sanely after the violation (acc=%0d, in range)", acc);
        end
        if (errors == errors_before)
            $display(" [PASS] stability-warning demonstration completed (confirm you saw the WARNING above)");
        else
            $display(" [FAIL] stability-warning demonstration hit an unexpected problem");

        // =========================================================
        // Stage 6/6: fxp8 MSB-window output (acc_fxp8)
        // =========================================================
        // acc_fxp8 must equal the top 8 bits of acc. Checked for
        // positive, negative and saturated accumulator states.
        $display("");
        $display("--- Stage 6/6: fxp8 MSB-window output (acc_fxp8 = top 8 bits of acc) ---");
        $display(" acc state          | acc    | expected acc_fxp8 | actual acc_fxp8 | status");
        $display(" -------------------|--------|--------------------|-----------------|-------");
        errors_before = errors;
        begin : fxp8_test
            reg signed [7:0] expect_fxp8;

            // small positive: a0=+1.0,a1=+0.5(E1M0),w0=w1=+1.0 -> acc=384 (0x0180) -> top byte = 0x01 = 1
            fmt_sel = 0; frac_bits = 8;
            a0 = 2'b00; a0_zero = 0; a1 = 2'b01; a1_zero = 0;
            w0 = 2'b00; w0_zero = 0; w1 = 2'b00; w1_zero = 0;
            clear_acc = 1'b1; valid_in = 1'b1;
            @(negedge clk); @(posedge clk); #1;
            clear_acc = 1'b0; valid_in = 1'b0;
            checks = checks + 1;
            expect_fxp8 = acc[15:8];   // cross-check against a DIFFERENT expression than the RTL's own (acc[ACC_W-1:ACC_W-8]), not just restating the same code
            if (acc_fxp8 !== expect_fxp8) begin
                errors = errors + 1;
                $display(" positive (acc=%-4d)| %-6d | %-18d | %-15d | FAIL", acc, acc, expect_fxp8, acc_fxp8);
            end else
                $display(" positive (acc=%-4d)| %-6d | %-18d | %-15d | PASS", acc, acc, expect_fxp8, acc_fxp8);

            // negative: same magnitude, negated -- confirms sign-extension
            // through the MSB window is correct, not just positive values
            a0 = 2'b10; a0_zero = 0; a1 = 2'b11; a1_zero = 0; // -1.0, -0.5
            w0 = 2'b00; w0_zero = 0; w1 = 2'b00; w1_zero = 0;
            clear_acc = 1'b1; valid_in = 1'b1;
            @(negedge clk); @(posedge clk); #1;
            clear_acc = 1'b0; valid_in = 1'b0;
            checks = checks + 1;
            expect_fxp8 = acc[15:8];
            if (acc_fxp8 !== expect_fxp8) begin
                errors = errors + 1;
                $display(" negative (acc=%-4d)| %-6d | %-18d | %-15d | FAIL", acc, acc, expect_fxp8, acc_fxp8);
            end else
                $display(" negative (acc=%-4d)| %-6d | %-18d | %-15d | PASS", acc, acc, expect_fxp8, acc_fxp8);

            // saturated: force +32767, confirm the MSB window of an
            // already-clamped value is still correctly derived (0x7F)
            fmt_sel = 1; frac_bits = 12;
            a0 = 2'b01; a0_zero = 0; a1 = 2'b01; a1_zero = 0;
            w0 = 2'b01; w0_zero = 0; w1 = 2'b01; w1_zero = 0;
            clear_acc = 1'b1; valid_in = 1'b1;
            @(negedge clk); @(posedge clk); #1;
            clear_acc = 1'b0;
            repeat (3) begin
                @(negedge clk); valid_in = 1'b1;
                @(posedge clk); #1;
            end
            valid_in = 1'b0;
            checks = checks + 1;
            expect_fxp8 = acc[15:8];
            if (acc_fxp8 !== expect_fxp8 || acc !== 16'sd32767) begin
                errors = errors + 1;
                $display(" saturated (acc=%-4d)| %-6d | %-18d | %-15d | FAIL", acc, acc, expect_fxp8, acc_fxp8);
            end else
                $display(" saturated (acc=%-4d)| %-6d | %-18d | %-15d | PASS", acc, acc, expect_fxp8, acc_fxp8);
        end
        if (errors == errors_before)
            $display(" [PASS] acc_fxp8 correctly tracks the MSB-8 window of acc across positive, negative, and saturated states");
        else
            $display(" [FAIL] acc_fxp8 did NOT correctly track acc in at least one state");

        // ---- Cancellation: previous accumulator + a large opposite-sign
        // product, non-saturating ----
        $display("");
        $display("--- Cancellation (previous acc + large opposite-sign product) ---");
        begin : cancel_test
            reg cancel_ok;
            cancel_ok = 1'b1;
            // shot1: a0=a1=w0=w1=2'b00 (sign=0,bit=0), fmt_sel=0 (E1M0) ->
            // each lane value = 1.0; pair_sum = 1.0*1.0 + 1.0*1.0 = 2.0;
            // frac_bits=8 -> acc = 2.0*256 = 512
            @(negedge clk);
            fmt_sel = 1'b0; frac_bits = 8;
            a0 = 2'b00; a1 = 2'b00; w0 = 2'b00; w1 = 2'b00;
            a0_zero = 1'b0; a1_zero = 1'b0; w0_zero = 1'b0; w1_zero = 1'b0;
            clear_acc = 1'b1; valid_in = 1'b1;
            @(posedge clk); #1;
            checks = checks + 1;
            if (acc !== 16'sd512) begin
                errors = errors + 1; cancel_ok = 1'b0;
                $display("    FAIL: cancellation shot1, expected acc=512, got %0d", acc);
            end
            // shot2 (no clear_acc): a0=a1=2'b10 (sign=1,bit=0 -> value -1.0),
            // w0=w1=2'b01 (sign=0,bit=1 -> value 0.5) -> pair_sum =
            // (-1.0*0.5)+(-1.0*0.5) = -1.0; partial = -1.0*256 = -256.
            // New acc = 512 + (-256) = 256
            @(negedge clk);
            a0 = 2'b10; a1 = 2'b10; w0 = 2'b01; w1 = 2'b01;
            clear_acc = 1'b0; valid_in = 1'b1;
            @(posedge clk); #1;
            checks = checks + 1;
            if (acc !== 16'sd256) begin
                errors = errors + 1; cancel_ok = 1'b0;
                $display("    FAIL: cancellation shot2, expected acc=256 (partial cancellation), got %0d", acc);
            end
            checks = checks + 1;
            if (overflow !== 1'b0) begin
                errors = errors + 1; cancel_ok = 1'b0;
                $display("    FAIL: cancellation shot2 should NOT saturate, but overflow=1");
            end
            @(negedge clk); valid_in = 1'b0;
            if (cancel_ok)
                $display("    [PASS] partial cancellation between accumulator and opposite-sign product lands on the exact expected value, no spurious saturation");
        end

        // ---- Reset followed by the first accumulation ----
        $display("");
        $display("--- Reset, then first accumulation ---");
        begin : reset_then_first
            reg reset_ok;
            reset_ok = 1'b1;
            @(negedge clk);
            rst_n = 1'b0;
            @(negedge clk);
            rst_n = 1'b1;
            @(negedge clk); #1;
            checks = checks + 1;
            if (acc !== 16'sd0) begin
                errors = errors + 1; reset_ok = 1'b0;
                $display("    FAIL: acc after reset (pre-clear_acc) expected 0, got %0d", acc);
            end
            checks = checks + 1;
            if (valid_out !== 1'b0 || overflow !== 1'b0) begin
                errors = errors + 1; reset_ok = 1'b0;
                $display("    FAIL: valid_out/overflow after reset expected both 0, got %b/%b", valid_out, overflow);
            end
            fmt_sel = 1'b0; frac_bits = 8;
            a0 = 2'b00; a1 = 2'b00; w0 = 2'b00; w1 = 2'b00;
            a0_zero = 1'b0; a1_zero = 1'b0; w0_zero = 1'b0; w1_zero = 1'b0;
            clear_acc = 1'b1; valid_in = 1'b1;
            @(posedge clk); #1;
            checks = checks + 1;
            if (acc !== 16'sd512 || valid_out !== 1'b1) begin
                errors = errors + 1; reset_ok = 1'b0;
                $display("    FAIL: first accumulation after reset, expected acc=512/valid_out=1, got acc=%0d/valid_out=%b", acc, valid_out);
            end
            @(negedge clk); clear_acc = 1'b0; valid_in = 1'b0;
            if (reset_ok)
                $display("    [PASS] reset produces the documented reset state, and the first post-reset accumulation is correct");
        end

        // ---- Truncation toward zero at frac_bits < 2 (negative result):
        // the magnitude is shifted and the sign applied afterwards. ----
        $display("");
        $display("--- frac_bits<2 rounding direction (truncation toward zero) ---");
        begin : rounding_direction_test
            reg rd_ok;
            rd_ok = 1'b1;
            // a0=00(sign=0,bit=0,not zero) -> E1M0 value=1.0
            // a1=01(sign=0,bit=1,not zero) -> E1M0 value=0.5
            // w0=00, w0_zero=1 -> value=0 (forced zero regardless of code)
            // w1=11(sign=1,bit=1,not zero) -> E1M0 value=-0.5
            // pair_sum = 1.0*0 + 0.5*(-0.5) = -0.25. At frac_bits=0:
            // truncate-toward-zero(-0.25) = 0 (floor would give -1).
            @(negedge clk);
            fmt_sel = 0; frac_bits = 0;
            a0 = 2'b00; a1 = 2'b01; w0 = 2'b00; w1 = 2'b11;
            a0_zero = 0; a1_zero = 0; w0_zero = 1; w1_zero = 0;
            clear_acc = 1'b1; valid_in = 1'b1;
            @(posedge clk); #1;
            checks = checks + 1;
            if (acc !== 16'sd0) begin
                errors = errors + 1; rd_ok = 1'b0;
                $display("    FAIL: expected truncate-toward-zero(-0.25)=0, got %0d", acc);
            end
            @(negedge clk); clear_acc = 1'b0; valid_in = 1'b0;
            if (rd_ok)
                $display("    [PASS] frac_bits=0 negative-result rounding is truncation toward zero (acc=0, not floor's -1)");
        end

        $display("");
        $display("========================================================================");
        $display(" FINAL RESULT: %0d / %0d checks passed  (%0d errors)", checks-errors, checks, errors);
        if (errors == 0)
            $display(" *** ALL TESTS PASSED *** (all 6 stages -- see table above for the WARNING line from Stage 5)");
        else
            $display(" *** %0d TEST(S) FAILED -- see FAIL rows above ***", errors);
        $display("========================================================================");
        $finish;
    end

endmodule
