// =====================================================================
// tb_posit4_mac_ref_v2_standalone.v
//
// Testbench for the Posit(4,1) reference MAC (posit4_mac_ref_v2.v),
// 16-bit saturating accumulator. Golden vectors come from the software
// model (golden/golden_gen_lean.py).
//
// Output: (1) decode table, (2) 16-row representative table at
// frac_bits=8 (one row per Posit(4,1) code, paired with itself; rows
// that saturate are labeled, e.g. 16*16 = 256 -> 65536 clamps to 32767),
// (3) exhaustive 256-case sweep at frac_bits=8, (4) the same sweep at
// frac_bits 6, 10, 12, (5) directed saturation test (both rails) and
// overflow-clears-on-valid_in=0 check, then sticky NaR, frac_bits
// extremes, cancellation, reset and clear_acc-without-valid_in checks.
// =====================================================================
`timescale 1ns/1ps

`ifndef GOLDEN_DIR
// Folder holding the golden .hex files. The default works when the
// simulator runs from primary_design/. Otherwise (e.g. Vivado xsim),
// define GOLDEN_DIR="<absolute path>/golden".
`define GOLDEN_DIR "golden"
`endif

module tb_posit4_mac_ref_v2_standalone;



    localparam ACC_W  = 16;   // 16-bit accumulator
    localparam FRAC_W = 5;

    reg clk, rst_n, clear_acc, valid_in;
    reg [FRAC_W-1:0] frac_bits;
    reg [3:0] a, b;
    wire signed [ACC_W-1:0] acc;
    wire valid_out, nar_flag, overflow;

    integer errors, checks, errors_before;

    posit4_mac_ref_v2 #(.ACC_W(ACC_W), .FRAC_W(FRAC_W)) dut (
        .clk(clk), .rst_n(rst_n), .clear_acc(clear_acc), .valid_in(valid_in),
        .frac_bits(frac_bits), .a(a), .b(b),
        .acc(acc), .valid_out(valid_out), .nar_flag(nar_flag), .overflow(overflow)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    reg [15:0] golden_posit4_fxp16_frac6  [0:255];
    reg [15:0] golden_posit4_fxp16_frac8  [0:255];
    reg [15:0] golden_posit4_fxp16_frac10 [0:255];
    reg [15:0] golden_posit4_fxp16_frac12 [0:255];
    reg        golden_posit4_nar [0:255];
    integer ia, ib, idx;

    // Human-readable decode string per 4-bit code, used only for
    // printing (independent of the RTL decode table).
    reg [8*8-1:0] posit4_str [0:15];
    initial begin
        posit4_str[0]  = "0";
        posit4_str[1]  = "0.0625";
        posit4_str[2]  = "0.25";
        posit4_str[3]  = "0.5";
        posit4_str[4]  = "1";
        posit4_str[5]  = "2";
        posit4_str[6]  = "4";
        posit4_str[7]  = "16";
        posit4_str[8]  = "NaR";
        posit4_str[9]  = "-16";
        posit4_str[10] = "-4";
        posit4_str[11] = "-2";
        posit4_str[12] = "-1";
        posit4_str[13] = "-0.5";
        posit4_str[14] = "-0.25";
        posit4_str[15] = "-0.0625";
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

    // Same as run_one, but also prints a formatted table row -- used
    // only for the 16 representative (a=b) cases at the default
    // frac_bits=8, so the table stays readable; the exhaustive sweep
    // below calls run_one (silent) for all 256, INCLUDING these same
    // 16, so nothing is skipped.
    task run_one_shown(input [3:0] va, input [3:0] vb, input [15:0] expect_val);
        begin
            @(negedge clk);
            a = va; b = vb; frac_bits = 5'd8;
            clear_acc = 1'b1; valid_in = 1'b1;
            @(posedge clk); #1;
            checks = checks + 1;
            if (acc !== $signed(expect_val)) begin
                errors = errors + 1;
                $display("  %4b | %-8s| %4b | %-8s| %-14s| %-14d| %-14d| FAIL <<<",
                          va, posit4_str[va], vb, posit4_str[vb],
                          (va==4'b1000 || vb==4'b1000) ? "(NaR->skip)" : (overflow ? "(SATURATED)" : ""),
                          $signed(expect_val), acc);
            end else begin
                $display("  %4b | %-8s| %4b | %-8s| %-14s| %-14d| %-14d| PASS",
                          va, posit4_str[va], vb, posit4_str[vb],
                          (va==4'b1000 || vb==4'b1000) ? "(NaR->skip)" : (overflow ? "(SATURATED)" : ""),
                          $signed(expect_val), acc);
            end
            clear_acc = 1'b0; valid_in = 1'b0;
        end
    endtask

    initial begin
        $readmemh({`GOLDEN_DIR, "/golden_posit4_fxp16_frac6.hex"},  golden_posit4_fxp16_frac6);
        $readmemh({`GOLDEN_DIR, "/golden_posit4_fxp16_frac8.hex"},  golden_posit4_fxp16_frac8);
        $readmemh({`GOLDEN_DIR, "/golden_posit4_fxp16_frac10.hex"}, golden_posit4_fxp16_frac10);
        $readmemh({`GOLDEN_DIR, "/golden_posit4_fxp16_frac12.hex"}, golden_posit4_fxp16_frac12);
        $readmemb({`GOLDEN_DIR, "/golden_posit4_nar.hex"}, golden_posit4_nar);

        errors = 0; checks = 0;
        rst_n = 0; clear_acc = 0; valid_in = 0; a = 0; b = 0; frac_bits = 5'd8;
        @(negedge clk); @(negedge clk);
        rst_n = 1;

        $display("========================================================================");
        $display(" Standalone Posit(4,1) MAC Testbench (posit4_mac_ref_v2.v)");
        $display("========================================================================");
        $display(" What this checks: posit4_mac_ref_v2.v -- decode, product and 16-bit");
        $display(" SATURATING accumulation -- at this width, several single-shot Posit4");
        $display(" products already exceed +-32767 (e.g. 16*16=256 real x 2^8=65536 at");
        $display(" frac_bits=8), so saturation is load-bearing here, not decorative.");
        $display("");
        $display(" Posit(4, es=1) decode table (every finite value is an exact power of");
        $display(" two, so multiply = exponent add, no real multiplier in hardware):");
        $display("   code | value    | code | value");
        $display("   -----|----------|------|--------");
        $display("   0000 | 0        | 1000 | NaR");
        $display("   0001 | 0.0625   | 1001 | -16");
        $display("   0010 | 0.25     | 1010 | -4");
        $display("   0011 | 0.5      | 1011 | -2");
        $display("   0100 | 1        | 1100 | -1");
        $display("   0101 | 2        | 1101 | -0.5");
        $display("   0110 | 4        | 1110 | -0.25");
        $display("   0111 | 16       | 1111 | -0.0625");
        $display("");
        $display(" Accumulator: signed 16-bit, Q8.8 by default (LSB = 2^-frac_bits),");
        $display(" saturates at +32767/-32768 rather than wrapping.");
        $display("========================================================================");

        // -----------------------------------------------------------
        // Representative table: one row per code, paired with itself
        // (a=b), so every representable value appears at least once.
        // -----------------------------------------------------------
        $display("");
        $display("--- Representative cases (a=b, one row per Posit4 code) ---");
        $display("  a    | a val   | b    | b val   | note          | expected acc  | actual acc    | status");
        $display("  -----|---------|------|---------|---------------|---------------|---------------|-------");

        errors_before = errors;
        for (ia = 0; ia < 16; ia = ia + 1)
            run_one_shown(ia[3:0], ia[3:0], golden_posit4_fxp16_frac8[ia*17]);
        if (errors == errors_before)
            $display("  [PASS] all 16/16 representative cases matched");
        else
            $display("  [FAIL] %0d of 16 representative cases did NOT match", errors - errors_before);

        // -----------------------------------------------------------
        // Full exhaustive sweep (all 256 a,b combinations) at
        // frac_bits=8, checked against the SATURATING fxp16 golden
        // model (some cases legitimately saturate at this width --
        // that's the point of Sec. above).
        // -----------------------------------------------------------
        $display("");
        $display("--- Full exhaustive sweep at frac_bits=8: all 16 x 16 = 256 combinations ---");
        errors_before = errors;
        idx = 0;
        for (ia = 0; ia < 16; ia = ia + 1)
            for (ib = 0; ib < 16; ib = ib + 1) begin
                run_one(ia[3:0], ib[3:0], 5'd8, golden_posit4_fxp16_frac8[idx]);
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
        // model (golden_gen.py's gen_posit4_fxp16, NOT just "trust the
        // Verilog"). More cases saturate at higher frac_bits -- also
        // expected, and correctly modeled independently.
        // -----------------------------------------------------------
        $display("");
        $display("--- Adaptive frac_bits sweep: same 256 combinations, 3 more precisions ---");
        $display(" frac_bits | cases | passed | failed | status");
        $display(" ----------|-------|--------|--------|-------");

        errors_before = errors;
        idx = 0;
        for (ia = 0; ia < 16; ia = ia + 1)
            for (ib = 0; ib < 16; ib = ib + 1) begin
                run_one(ia[3:0], ib[3:0], 5'd6, golden_posit4_fxp16_frac6[idx]);
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
                run_one(ia[3:0], ib[3:0], 5'd10, golden_posit4_fxp16_frac10[idx]);
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
                run_one(ia[3:0], ib[3:0], 5'd12, golden_posit4_fxp16_frac12[idx]);
                idx = idx + 1;
            end
        if (errors == errors_before)
            $display(" 12        | 256   | 256    | 0      | PASS");
        else
            $display(" 12        | 256   | %-6d | %-6d | FAIL", 256-(errors-errors_before), errors-errors_before);

        // -----------------------------------------------------------
        // Directed saturation test, both rails, plus the
        // overflow-flag-clears-on-valid_in=0 check.
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
            // largest positive product (16*16=256) repeated a few times
            // at frac_bits=12 (256*4096=1048576, far beyond +-32767)
            a = 4'b0111; b = 4'b0111; frac_bits = 5'd12;
            clear_acc = 1'b1; valid_in = 1'b1;
            @(negedge clk); @(posedge clk); #1;
            clear_acc = 1'b0;
            for (k = 0; k < 3; k = k + 1) begin
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

            // negative rail: largest-magnitude negative x positive
            a = 4'b1001; b = 4'b0111; frac_bits = 5'd12; // -16 * 16
            clear_acc = 1'b1; valid_in = 1'b1;
            @(negedge clk); @(posedge clk); #1;
            clear_acc = 1'b0;
            for (k = 0; k < 3; k = k + 1) begin
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

            // overflow flag must clear when valid_in drops
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
        // Sticky NaR flag: step-by-step state table
        // -----------------------------------------------------------
        $display("");
        $display("--- Sticky NaR flag behavior ---");
        $display(" Posit has a 'Not-a-Real' (NaR) code (1000) for invalid results. When");
        $display(" either operand is NaR, the hardware must: (1) skip accumulating a");
        $display(" meaningless product, and (2) latch a sticky nar_flag so a caller can");
        $display(" detect it happened, even on a later cycle.");
        $display("");
        $display("  step | a    | b    | a is NaR? | nar_flag | acc  | meaning");
        $display("  -----|------|------|-----------|----------|------|-----------------------");
        errors_before = errors;
        begin : sticky_nar_test
            checks = checks + 1;
            @(negedge clk);
            a = 4'b1000; b = 4'b0100; frac_bits = 5'd8; // a = NaR
            clear_acc = 1'b1; valid_in = 1'b1;
            @(posedge clk); #1;
            $display("  1    | 1000 | 0100 | YES       | %-8b | %-4d | flag SET the instant NaR appears",
                      nar_flag, acc);
            if (nar_flag !== 1'b1) begin
                errors = errors + 1;
                $display("  [FAIL] flag not set on the cycle a NaR value appeared");
            end
            clear_acc = 1'b0; valid_in = 1'b0;
        end
        if (errors == errors_before)
            $display("  [PASS] sticky NaR flag check passed");
        else
            $display("  [FAIL] sticky NaR flag check did NOT pass");

        // ---- frac_bits port extremes: the exhaustive sweeps above use
        // frac_bits 6, 8, 10, 12 only ----
        $display("");
        $display("--- frac_bits port edge-value safety (0 and 20) ---");
        begin : frac_edge
            reg fe_ok;
            fe_ok = 1'b1;
            // frac_bits=0: a=b=0011 (value 0.5 each, exp=-1 each) ->
            // product = 0.25, exp_p = -2, combined_shift = -2+0 = -2
            // (right shift by 2 of a single set bit) -> truncates to 0.
            @(negedge clk);
            a = 4'b0011; b = 4'b0011; frac_bits = 0;
            clear_acc = 1'b1; valid_in = 1'b1;
            @(posedge clk); #1;
            checks = checks + 1;
            if (acc !== 16'sd0) begin
                errors = errors + 1; fe_ok = 1'b0;
                $display("    FAIL: frac_bits=0 truncation case, expected 0, got %0d", acc);
            end
            @(negedge clk); clear_acc = 1'b0; valid_in = 1'b0;

            // frac_bits=20: a=b=0111 (value 16 each, exp=4 each) ->
            // product = 256, exp_p = 8, combined_shift = 8+20 = 28,
            // magnitude = 1<<28 -- vastly exceeds int16 range, must
            // saturate cleanly (not silently wrap the internal 48-bit
            // sum).
            @(negedge clk);
            a = 4'b0111; b = 4'b0111; frac_bits = 20;
            clear_acc = 1'b1; valid_in = 1'b1;
            @(posedge clk); #1;
            checks = checks + 1;
            if (acc !== 16'sd32767) begin
                errors = errors + 1; fe_ok = 1'b0;
                $display("    FAIL: frac_bits=20 large-shift case, expected saturate to 32767, got %0d", acc);
            end
            @(negedge clk); clear_acc = 1'b0; valid_in = 1'b0;

            // frac_bits=31: the port's LITERAL maximum (FRAC_W=5 -> 0..31),
            // not just a "large" representative value like 20 above. Same
            // stimulus, combined_shift = 8+31 = 39 -- must also saturate
            // cleanly, exercising the actual shift-control boundary.
            @(negedge clk);
            a = 4'b0111; b = 4'b0111; frac_bits = 31;
            clear_acc = 1'b1; valid_in = 1'b1;
            @(posedge clk); #1;
            checks = checks + 1;
            if (acc !== 16'sd32767) begin
                errors = errors + 1; fe_ok = 1'b0;
                $display("    FAIL: frac_bits=31 (literal max) case, expected saturate to 32767, got %0d", acc);
            end
            @(negedge clk); clear_acc = 1'b0; valid_in = 1'b0;

            if (fe_ok)
                $display("    [PASS] frac_bits port is safe across its extreme values (0, 20, and the literal max 31)");
        end

        // ---- Cancellation: previous accumulator + a large opposite-sign
        // product, non-saturating (distinct from the saturation tests
        // above, which push toward the rails; this checks a partial,
        // in-range cancellation lands on the exact expected value) ----
        $display("");
        $display("--- Cancellation (previous acc + large opposite-sign product) ---");
        begin : cancel_test
            reg cancel_ok;
            cancel_ok = 1'b1;
            // shot1: a=0101(=2,exp=1) x b=0101(=2,exp=1) -> product=4, exp_p=2;
            // frac_bits=8 -> combined_shift=10, magnitude=1<<10=1024
            @(negedge clk);
            frac_bits = 8;
            a = 4'b0101; b = 4'b0101;
            clear_acc = 1'b1; valid_in = 1'b1;
            @(posedge clk); #1;
            checks = checks + 1;
            if (acc !== 16'sd1024) begin
                errors = errors + 1; cancel_ok = 1'b0;
                $display("    FAIL: cancellation shot1, expected acc=1024, got %0d", acc);
            end
            // shot2 (no clear_acc): a=1101(=-0.5,exp=-1,sign=1) x b=0111(=16,exp=4)
            // -> product=-8, exp_p=3; combined_shift=11, magnitude=1<<11=2048,
            // sign=1 -> partial=-2048. New acc = 1024 + (-2048) = -1024
            @(negedge clk);
            a = 4'b1101; b = 4'b0111;
            clear_acc = 1'b0; valid_in = 1'b1;
            @(posedge clk); #1;
            checks = checks + 1;
            if (acc !== -16'sd1024) begin
                errors = errors + 1; cancel_ok = 1'b0;
                $display("    FAIL: cancellation shot2, expected acc=-1024 (partial cancellation), got %0d", acc);
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
            // Immediately after reset, before any clear_acc: acc, valid_out,
            // overflow, nar_flag must all read their reset values.
            checks = checks + 1;
            if (acc !== 16'sd0) begin
                errors = errors + 1; reset_ok = 1'b0;
                $display("    FAIL: acc after reset (pre-clear_acc) expected 0, got %0d", acc);
            end
            checks = checks + 1;
            if (valid_out !== 1'b0 || overflow !== 1'b0 || nar_flag !== 1'b0) begin
                errors = errors + 1; reset_ok = 1'b0;
                $display("    FAIL: valid_out/overflow/nar_flag after reset expected all 0, got %b/%b/%b",
                          valid_out, overflow, nar_flag);
            end
            // First accumulation after reset: a=0101(=2) x b=0101(=2) -> exp_p=2,
            // frac_bits=8 -> magnitude=1<<10=1024, same known-good value as the
            // cancellation test's shot1 -- confirms no residual state survived reset.
            frac_bits = 8;
            a = 4'b0101; b = 4'b0101;
            clear_acc = 1'b1; valid_in = 1'b1;
            @(posedge clk); #1;
            checks = checks + 1;
            if (acc !== 16'sd1024 || valid_out !== 1'b1) begin
                errors = errors + 1; reset_ok = 1'b0;
                $display("    FAIL: first accumulation after reset, expected acc=1024/valid_out=1, got acc=%0d/valid_out=%b", acc, valid_out);
            end
            @(negedge clk); clear_acc = 1'b0; valid_in = 1'b0;
            if (reset_ok)
                $display("    [PASS] reset produces the documented reset state, and the first post-reset accumulation is correct");
        end

        // ---- clear_acc asserted WITHOUT valid_in: neither nar_flag nor
        // acc may change (clear acts only together with valid_in). ----
        $display("");
        $display("--- clear_acc asserted WITHOUT valid_in (nar_flag and acc must hold) ---");
        begin : clear_acc_alone_test
            reg ca_ok;
            reg signed [ACC_W-1:0] acc_before;
            ca_ok = 1'b1;

            // First, get into a NaR-sticky state with a known acc value.
            @(negedge clk);
            a = 4'b1000; b = 4'b0100; frac_bits = 8; // a = NaR
            clear_acc = 1'b1; valid_in = 1'b1;
            @(posedge clk); #1;
            checks = checks + 1;
            if (nar_flag !== 1'b1) begin
                errors = errors + 1; ca_ok = 1'b0;
                $display("    FAIL: setup step, expected nar_flag=1 after a NaR operand, got %b", nar_flag);
            end
            acc_before = acc;
            @(negedge clk); valid_in = 1'b0;

            // Now assert clear_acc ALONE (valid_in=0): neither nar_flag
            // nor acc may change.
            clear_acc = 1'b1; valid_in = 1'b0;
            @(posedge clk); #1;
            checks = checks + 1;
            if (nar_flag !== 1'b1) begin
                errors = errors + 1; ca_ok = 1'b0;
                $display("    FAIL: clear_acc alone (valid_in=0) should leave nar_flag_r UNCHANGED (still 1), got nar_flag=%b", nar_flag);
            end
            checks = checks + 1;
            if (acc !== acc_before) begin
                errors = errors + 1; ca_ok = 1'b0;
                $display("    FAIL: clear_acc alone (valid_in=0) should NOT change acc, expected %0d, got %0d", acc_before, acc);
            end
            @(negedge clk); clear_acc = 1'b0;

            // Confirm clear_acc+valid_in TOGETHER (the documented,
            // usage contract) clears nar_flag.
            clear_acc = 1'b1; valid_in = 1'b1;
            a = 4'b0101; b = 4'b0101; frac_bits = 8; // ordinary, non-NaR operands
            @(posedge clk); #1;
            checks = checks + 1;
            if (nar_flag !== 1'b0) begin
                errors = errors + 1; ca_ok = 1'b0;
                $display("    FAIL: clear_acc+valid_in together should still clear nar_flag_r, got nar_flag=%b", nar_flag);
            end
            @(negedge clk); clear_acc = 1'b0; valid_in = 1'b0;

            if (ca_ok)
                $display("    [PASS] nar_flag_r and acc now stay in sync: clear_acc alone (valid_in=0) changes neither; clear_acc+valid_in together still clears nar_flag_r exactly as before");
        end

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
