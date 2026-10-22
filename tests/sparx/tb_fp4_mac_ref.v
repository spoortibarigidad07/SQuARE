// =====================================================================
// tb_fp4_mac_ref.v
//
// Testbench for the standalone fp4_mac_ref.v, now ACC_W=16 by default
// (adaptive fxp16, matching this package's other adaptive modules)
// with saturating accumulation. Uses the NEW saturating
// golden_fp4_fxp16_frac*.hex vectors (different from the plain
// golden_fp4.hex / golden_fp4_frac*.hex files, which stay
// non-saturating 32-bit and back sparx_mac_unified.v's shared
// accumulator, unaffected by this change).
//
// Output structure matches tb_posit4_mac_ref.v: (1) decode table,
// (2) 16-row representative table at frac_bits=8 (some now saturate,
// labeled), (3) full exhaustive 256-case sweep at frac_bits=8,
// (4) the same sweep at frac_bits in {6,10,12}, (5) directed
// saturation test (both rails, overflow-clears check).
// =====================================================================
`timescale 1ns/1ps

`ifndef GOLDEN_DIR
// See tb_posit4_mac_ref.v for the full rationale: absolute path,
// works unmodified for both Icarus and Vivado, no sim-source-adding
// or macro-override needed in Vivado with this default.
`define GOLDEN_DIR "/home/sysad/Documents/project_novelties/SPARX_Extension/RTL/sparx_mac_ext/golden"
`endif

module tb_fp4_mac_ref;

    localparam ACC_W  = 16;   // matches the module's new adaptive-fxp16 default
    localparam FRAC_W = 5;

    reg clk, rst_n, clear_acc, valid_in;
    reg [FRAC_W-1:0] frac_bits;
    reg [3:0] a, b;
    wire signed [ACC_W-1:0] acc;
    wire valid_out, overflow;
    wire signed [7:0] acc_fxp8;

    integer errors, checks, errors_before;

    fp4_mac_ref #(.ACC_W(ACC_W), .FRAC_W(FRAC_W)) dut (
        .clk(clk), .rst_n(rst_n), .clear_acc(clear_acc), .valid_in(valid_in),
        .frac_bits(frac_bits), .a(a), .b(b),
        .acc(acc), .valid_out(valid_out), .overflow(overflow), .acc_fxp8(acc_fxp8)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    reg [15:0] golden_fp4_fxp16_frac6  [0:255];
    reg [15:0] golden_fp4_fxp16_frac8  [0:255];
    reg [15:0] golden_fp4_fxp16_frac10 [0:255];
    reg [15:0] golden_fp4_fxp16_frac12 [0:255];
    integer ia, ib, idx;

    // Human-readable decode string per 4-bit FP4 (E2M1) code, purely
    // for display -- independent restatement of docs/DESIGN_NOTES.md
    // Sec. 1.2's table, not used by the RTL itself.
    reg [8*6-1:0] fp4_str [0:15];
    initial begin
        fp4_str[0]  = "0";
        fp4_str[1]  = "0.5";
        fp4_str[2]  = "1";
        fp4_str[3]  = "1.5";
        fp4_str[4]  = "2";
        fp4_str[5]  = "3";
        fp4_str[6]  = "4";
        fp4_str[7]  = "6";
        fp4_str[8]  = "-0";
        fp4_str[9]  = "-0.5";
        fp4_str[10] = "-1";
        fp4_str[11] = "-1.5";
        fp4_str[12] = "-2";
        fp4_str[13] = "-3";
        fp4_str[14] = "-4";
        fp4_str[15] = "-6";
    end

    task run_one(input [3:0] va, input [3:0] vb, input [FRAC_W-1:0] fb, input [15:0] expect_val);
        begin
            @(negedge clk);
            a = va; b = vb; frac_bits = fb;
            clear_acc = 1'b1; valid_in = 1'b1;
            @(posedge clk); #1;
            checks = checks + 1;
            if (acc !== $signed(expect_val)) begin
                errors = errors + 1;
                $display("    MISMATCH a=%b b=%b frac_bits=%0d : acc=%0d expected=%0d", va, vb, fb, acc, $signed(expect_val));
            end
            clear_acc = 1'b0; valid_in = 1'b0;
        end
    endtask

    task run_one_shown(input [3:0] va, input [3:0] vb, input [15:0] expect_val);
        begin
            @(negedge clk);
            a = va; b = vb; frac_bits = 5'd8;
            clear_acc = 1'b1; valid_in = 1'b1;
            @(posedge clk); #1;
            checks = checks + 1;
            if (acc !== $signed(expect_val)) begin
                errors = errors + 1;
                $display("  %4b | %-6s| %4b | %-6s| %-13s| %-14d| %-14d| FAIL <<<",
                          va, fp4_str[va], vb, fp4_str[vb], overflow ? "(SATURATED)" : "", $signed(expect_val), acc);
            end else begin
                $display("  %4b | %-6s| %4b | %-6s| %-13s| %-14d| %-14d| PASS",
                          va, fp4_str[va], vb, fp4_str[vb], overflow ? "(SATURATED)" : "", $signed(expect_val), acc);
            end
            clear_acc = 1'b0; valid_in = 1'b0;
        end
    endtask

    initial begin
        $readmemh({`GOLDEN_DIR, "/golden_fp4_fxp16_frac6.hex"},  golden_fp4_fxp16_frac6);
        $readmemh({`GOLDEN_DIR, "/golden_fp4_fxp16_frac8.hex"},  golden_fp4_fxp16_frac8);
        $readmemh({`GOLDEN_DIR, "/golden_fp4_fxp16_frac10.hex"}, golden_fp4_fxp16_frac10);
        $readmemh({`GOLDEN_DIR, "/golden_fp4_fxp16_frac12.hex"}, golden_fp4_fxp16_frac12);

        errors = 0; checks = 0;
        rst_n = 0; clear_acc = 0; valid_in = 0; a = 0; b = 0; frac_bits = 5'd8;
        @(negedge clk); @(negedge clk);
        rst_n = 1;

        $display("========================================================================");
        $display(" Standalone FP4 (E2M1) MAC Testbench (fp4_mac_ref.v)");
        $display("========================================================================");
        $display(" What this checks: fp4_mac_ref.v = fp4_e2m1_pp.v (partial-product");
        $display(" decode+multiply) + a dedicated accumulator register, ACC_W=16 by default");
        $display(" (adaptive fxp16, matching this package's other adaptive modules) with");
        $display(" SATURATING accumulation -- at frac_bits=12, 56/256 exhaustive single-shot");
        $display(" products already exceed +-32767, so saturation is load-bearing here.");
        $display("");
        $display(" FP4 (E2M1, bias=1) decode table -- code = {sign, e[1:0], m}:");
        $display("   code | value | code | value");
        $display("   -----|-------|------|------");
        $display("   0000 | 0     | 1000 | -0");
        $display("   0001 | 0.5   | 1001 | -0.5");
        $display("   0010 | 1     | 1010 | -1");
        $display("   0011 | 1.5   | 1011 | -1.5");
        $display("   0100 | 2     | 1100 | -2");
        $display("   0101 | 3     | 1101 | -3");
        $display("   0110 | 4     | 1110 | -4");
        $display("   0111 | 6     | 1111 | -6");
        $display("");
        $display(" Internally represented as SIG x 2^pow_exp (SIG in {0,1,2,3} exact");
        $display(" integer), so every product is computed with zero rounding error.");
        $display(" Accumulator: signed 16-bit, Q8.8 by default (LSB = 2^-frac_bits),");
        $display(" saturates at +32767/-32768 rather than wrapping.");
        $display("========================================================================");

        // -----------------------------------------------------------
        // Representative table: one row per code, paired with itself.
        // -----------------------------------------------------------
        $display("");
        $display("--- Representative cases (a=b, one row per FP4 code) ---");
        $display("  a    | a val | b    | b val | note         | expected acc  | actual acc    | status");
        $display("  -----|-------|------|-------|--------------|---------------|---------------|-------");

        errors_before = errors;
        for (ia = 0; ia < 16; ia = ia + 1)
            run_one_shown(ia[3:0], ia[3:0], golden_fp4_fxp16_frac8[ia*17]);
        if (errors == errors_before)
            $display("  [PASS] all 16/16 representative cases matched");
        else
            $display("  [FAIL] %0d of 16 representative cases did NOT match", errors - errors_before);

        // -----------------------------------------------------------
        // Full exhaustive sweep at frac_bits=8, checked against the
        // SATURATING fxp16 golden model.
        // -----------------------------------------------------------
        $display("");
        $display("--- Full exhaustive sweep at frac_bits=8: all 16 x 16 = 256 combinations ---");
        errors_before = errors;
        idx = 0;
        for (ia = 0; ia < 16; ia = ia + 1)
            for (ib = 0; ib < 16; ib = ib + 1) begin
                run_one(ia[3:0], ib[3:0], 5'd8, golden_fp4_fxp16_frac8[idx]);
                idx = idx + 1;
            end
        if (errors == errors_before) begin
            $display("  [PASS] all 256/256 combinations matched (the 16 shown above are");
            $display("         included in this count, not separate from it)");
        end else
            $display("  [FAIL] %0d of 256 did NOT match (see MISMATCH lines above)", errors - errors_before);

        // -----------------------------------------------------------
        // Adaptive frac_bits sweep, same 256-case exhaustiveness,
        // checked against an independently computed SATURATING golden
        // model (golden_gen.py's gen_fp4_fxp16).
        // -----------------------------------------------------------
        $display("");
        $display("--- Adaptive frac_bits sweep: same 256 combinations, 3 more precisions ---");
        $display(" frac_bits | cases | passed | failed | status");
        $display(" ----------|-------|--------|--------|-------");

        errors_before = errors;
        idx = 0;
        for (ia = 0; ia < 16; ia = ia + 1)
            for (ib = 0; ib < 16; ib = ib + 1) begin
                run_one(ia[3:0], ib[3:0], 5'd6, golden_fp4_fxp16_frac6[idx]);
                idx = idx + 1;
            end
        if (errors == errors_before)
            $display(" 6         | 256   | 256    | 0      | PASS");
        else
            $display(" 6         | 256   | %-6d | %-6d | FAIL", 256-(errors-errors_before), errors-errors_before);

        errors_before = errors;
        idx = 0;
        for (ia = 0; ia < 16; ia = ia + 1)
            for (ib = 0; ib < 16; ib = ib + 1) begin
                run_one(ia[3:0], ib[3:0], 5'd10, golden_fp4_fxp16_frac10[idx]);
                idx = idx + 1;
            end
        if (errors == errors_before)
            $display(" 10        | 256   | 256    | 0      | PASS");
        else
            $display(" 10        | 256   | %-6d | %-6d | FAIL", 256-(errors-errors_before), errors-errors_before);

        errors_before = errors;
        idx = 0;
        for (ia = 0; ia < 16; ia = ia + 1)
            for (ib = 0; ib < 16; ib = ib + 1) begin
                run_one(ia[3:0], ib[3:0], 5'd12, golden_fp4_fxp16_frac12[idx]);
                idx = idx + 1;
            end
        if (errors == errors_before)
            $display(" 12        | 256   | 256    | 0      | PASS");
        else
            $display(" 12        | 256   | %-6d | %-6d | FAIL", 256-(errors-errors_before), errors-errors_before);

        // -----------------------------------------------------------
        // Directed saturation test, both rails, plus the
        // overflow-flag-clears-on-valid_in=0 regression check.
        // -----------------------------------------------------------
        $display("");
        $display("--- Directed saturation test (both rails) ---");
        $display(" check                        | expected | actual | status");
        $display(" -----------------------------|----------|--------|-------");
        errors_before = errors;
        begin : saturation_test
            integer k;
            reg saw_overflow;
            saw_overflow = 1'b0;
            // largest positive product (6*6=36) repeated a few times
            // at frac_bits=12 (36*4096=147456, far beyond +-32767)
            a = 4'b0111; b = 4'b0111; frac_bits = 5'd12;
            clear_acc = 1'b1; valid_in = 1'b1;
            @(negedge clk); @(posedge clk); #1;
            clear_acc = 1'b0;
            for (k = 0; k < 2; k = k + 1) begin
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

            // negative rail
            a = 4'b1111; b = 4'b0111; frac_bits = 5'd12; // -6 * 6
            clear_acc = 1'b1; valid_in = 1'b1;
            @(negedge clk); @(posedge clk); #1;
            clear_acc = 1'b0;
            for (k = 0; k < 2; k = k + 1) begin
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
            $display(" [PASS] all saturation checks behaved correctly");
        else
            $display(" [FAIL] %0d saturation check(s) did NOT behave correctly", errors - errors_before);

        // -----------------------------------------------------------
        // fxp8 MSB-window output (acc_fxp8), same rationale as
        // tb_fp2_parallel_mac.v's Stage 7 -- FP4 adopts the same
        // fxp8-MSB-window recommendation as FP2 (see fp4_mac_ref.v's
        // header for why). acc (unchanged) stays full-precision;
        // acc_fxp8 is the new, additional derived output, checked
        // across positive, negative, and saturated acc states.
        // -----------------------------------------------------------
        $display("");
        $display("--- fxp8 MSB-window output (acc_fxp8 = top 8 bits of acc) ---");
        $display(" acc state            | acc    | expected acc_fxp8 | actual acc_fxp8 | status");
        $display(" ---------------------|--------|--------------------|-----------------|-------");
        errors_before = errors;
        begin : fxp8_test
            reg signed [7:0] expect_fxp8;

            // positive: a=6,b=1 -> 6 real, *256(frac_bits=8) = 1536
            a = 4'b0111; b = 4'b0010; frac_bits = 5'd8;
            clear_acc = 1'b1; valid_in = 1'b1;
            @(negedge clk); @(posedge clk); #1;
            clear_acc = 1'b0; valid_in = 1'b0;
            checks = checks + 1;
            expect_fxp8 = acc[15:8];
            if (acc_fxp8 !== expect_fxp8) begin
                errors = errors + 1;
                $display(" positive (acc=%-6d)| %-6d | %-18d | %-15d | FAIL", acc, acc, expect_fxp8, acc_fxp8);
            end else
                $display(" positive (acc=%-6d)| %-6d | %-18d | %-15d | PASS", acc, acc, expect_fxp8, acc_fxp8);

            // negative: a=-6,b=1 -> -6 real, *256 = -1536
            a = 4'b1111; b = 4'b0010; frac_bits = 5'd8;
            clear_acc = 1'b1; valid_in = 1'b1;
            @(negedge clk); @(posedge clk); #1;
            clear_acc = 1'b0; valid_in = 1'b0;
            checks = checks + 1;
            expect_fxp8 = acc[15:8];
            if (acc_fxp8 !== expect_fxp8) begin
                errors = errors + 1;
                $display(" negative (acc=%-6d)| %-6d | %-18d | %-15d | FAIL", acc, acc, expect_fxp8, acc_fxp8);
            end else
                $display(" negative (acc=%-6d)| %-6d | %-18d | %-15d | PASS", acc, acc, expect_fxp8, acc_fxp8);

            // saturated: 6*6=36 repeated at frac_bits=12 -> far beyond +-32767
            a = 4'b0111; b = 4'b0111; frac_bits = 5'd12;
            clear_acc = 1'b1; valid_in = 1'b1;
            @(negedge clk); @(posedge clk); #1;
            clear_acc = 1'b0;
            repeat (2) begin
                @(negedge clk); valid_in = 1'b1;
                @(posedge clk); #1;
            end
            valid_in = 1'b0;
            checks = checks + 1;
            expect_fxp8 = acc[15:8];
            if (acc_fxp8 !== expect_fxp8 || acc !== 16'sd32767) begin
                errors = errors + 1;
                $display(" saturated (acc=%-6d)| %-6d | %-18d | %-15d | FAIL", acc, acc, expect_fxp8, acc_fxp8);
            end else
                $display(" saturated (acc=%-6d)| %-6d | %-18d | %-15d | PASS", acc, acc, expect_fxp8, acc_fxp8);
        end
        if (errors == errors_before)
            $display(" [PASS] acc_fxp8 correctly tracks the MSB-8 window of acc across positive, negative, and saturated states");
        else
            $display(" [FAIL] acc_fxp8 did NOT correctly track acc in at least one state");

        $display("");
        $display("========================================================================");
        $display(" FINAL RESULT: %0d / %0d checks passed  (%0d errors)", checks-errors, checks, errors);
        if (errors == 0)
            $display(" *** ALL TESTS PASSED ***");
        else
            $display(" *** %0d TEST(S) FAILED ***", errors);
        $display("========================================================================");
        $finish;
    end

endmodule
