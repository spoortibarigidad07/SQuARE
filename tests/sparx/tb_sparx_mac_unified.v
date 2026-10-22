// =====================================================================
// tb_sparx_mac_unified.v
// Exhaustive (16 x 16 = 256 combinations, x3 formats = 768 checks)
// self-checking testbench for sparx_mac_unified.v, comparing every
// result against the independent Python golden model in golden/.
// Also covers (Section 5): the same 3-format exhaustive sweep repeated
// at 2 additional frac_bits values, checked against an independently
// computed adaptive golden model, proving frac_bits is a genuine
// runtime input shared across all three formats, not a fixed Q8.8
// format with a decorative port.
// =====================================================================
`timescale 1ns/1ps

`ifndef GOLDEN_DIR
// Absolute path, defaulting to this package's known fixed deployment
// location: works unmodified for both Icarus and Vivado (whose
// simulation run directory does not mirror this package's source
// tree, so a relative path silently fails there -- see
// tb_posit4_mac_ref.v for the full symptom description). Override via
// `+define+GOLDEN_DIR="/other/path"` if you extract this package
// somewhere else.
`define GOLDEN_DIR "/home/sysad/Documents/project_novelties/SPARX_Extension/RTL/sparx_mac_ext/golden"
`endif

module tb_sparx_mac_unified;

    localparam FRAC_W = 5;

    reg         clk, rst_n, clear_acc, valid_in;
    reg  [1:0]  mode_sel;
    reg  [FRAC_W-1:0] frac_bits;
    reg  [3:0]  a, b;
    wire signed [31:0] acc;
    wire        valid_out;
    wire        nar_flag;

    integer errors;
    integer checks;

    reg [31:0] golden_posit4   [0:255];
    reg [31:0] golden_fp4      [0:255];
    reg [31:0] golden_fp2      [0:255];
    reg        golden_posit4_nar [0:255];
    reg [31:0] golden_posit4_frac6  [0:255];
    reg [31:0] golden_posit4_frac12 [0:255];
    reg [31:0] golden_fp4_frac6     [0:255];
    reg [31:0] golden_fp4_frac12    [0:255];
    reg [31:0] golden_fp2_frac6     [0:255];
    reg [31:0] golden_fp2_frac12    [0:255];

    sparx_mac_unified #(.ACC_W(32), .FRAC_W(FRAC_W)) dut (
        .clk(clk), .rst_n(rst_n), .clear_acc(clear_acc), .valid_in(valid_in),
        .mode_sel(mode_sel), .frac_bits(frac_bits), .a(a), .b(b),
        .acc(acc), .valid_out(valid_out), .nar_flag(nar_flag)
    );

    // 10 ns clock
    initial clk = 0;
    always #5 clk = ~clk;

    integer ia, ib;
    reg [31:0] expected;
    reg        expect_nar;

    task run_one(input [1:0] mode, input [3:0] av, input [3:0] bv,
                 input [FRAC_W-1:0] fb, input [31:0] exp_val, input exp_nar);
        begin
            @(negedge clk);
            mode_sel  = mode;
            a         = av;
            b         = bv;
            frac_bits = fb;
            clear_acc = 1'b1;
            valid_in  = 1'b1;
            @(posedge clk);
            #1; // allow clocked update to settle
            checks = checks + 1;
            if (acc !== $signed(exp_val)) begin
                errors = errors + 1;
                $display("MISMATCH mode=%0d a=%b b=%b frac_bits=%0d : acc=%0d (0x%08h) expected=%0d (0x%08h)",
                          mode, av, bv, fb, acc, acc, $signed(exp_val), exp_val);
            end
            if (mode == 2'b00 && (nar_flag !== exp_nar)) begin
                errors = errors + 1;
                $display("NAR-FLAG MISMATCH a=%b b=%b : nar_flag=%b expected=%b",
                          av, bv, nar_flag, exp_nar);
            end
            clear_acc = 1'b0;
            valid_in  = 1'b0;
        end
    endtask

    integer errors_before;   // snapshot used to compute each section's own error count

    initial begin
        // Path is a single edit point via `GOLDEN_DIR (defined at the top
        // of this file), an absolute path by default -- see the header
        // comment above for the rationale.
        $readmemh({`GOLDEN_DIR, "/golden_posit4.hex"}, golden_posit4);
        $readmemh({`GOLDEN_DIR, "/golden_fp4.hex"},    golden_fp4);
        $readmemh({`GOLDEN_DIR, "/golden_fp2.hex"},    golden_fp2);
        $readmemb({`GOLDEN_DIR, "/golden_posit4_nar.hex"}, golden_posit4_nar);
        $readmemh({`GOLDEN_DIR, "/golden_posit4_frac6.hex"},  golden_posit4_frac6);
        $readmemh({`GOLDEN_DIR, "/golden_posit4_frac12.hex"}, golden_posit4_frac12);
        $readmemh({`GOLDEN_DIR, "/golden_fp4_frac6.hex"},     golden_fp4_frac6);
        $readmemh({`GOLDEN_DIR, "/golden_fp4_frac12.hex"},    golden_fp4_frac12);
        $readmemh({`GOLDEN_DIR, "/golden_fp2_frac6.hex"},     golden_fp2_frac6);
        $readmemh({`GOLDEN_DIR, "/golden_fp2_frac12.hex"},    golden_fp2_frac12);

        errors = 0;
        checks = 0;
        rst_n = 0; clear_acc = 0; valid_in = 0; mode_sel = 0; a = 0; b = 0; frac_bits = 5'd8;
        @(negedge clk); @(negedge clk);
        rst_n = 1;

        $display("========================================================================");
        $display(" SPARX Unified MAC Testbench");
        $display(" ");
        $display(" This one physical MAC (sparx_mac_unified.v) supports three different");
        $display(" low-bit number formats, selected at runtime by mode_sel. Below, EVERY");
        $display(" one of the 256 possible (a,b) 4-bit operand combinations is fed to the");
        $display(" hardware for each format, and the hardware's answer is compared against");
        $display(" an independent Python reference model (golden/golden_gen.py) -- not just");
        $display(" checked for 'did it run', but bit-for-bit checked against what the");
        $display(" correct answer actually is. A single mismatch anywhere means real bug.");
        $display("========================================================================");

        // ---- Posit(4,1) exhaustive, frac_bits=8 (Q8.8) ----
        $display("");
        $display("--- Section 1/5: Posit(4, es=1) format, frac_bits=8 (Q8.8) ---");
        $display("    Sweeping all 16 x 16 = 256 operand combinations...");
        errors_before = errors;
        for (ia = 0; ia < 16; ia = ia + 1)
            for (ib = 0; ib < 16; ib = ib + 1)
                run_one(2'b00, ia[3:0], ib[3:0], 5'd8,
                        golden_posit4[ia*16+ib], golden_posit4_nar[ia*16+ib]);
        if (errors == errors_before)
            $display("    [PASS] all 256/256 Posit(4,1) results matched the reference model");
        else
            $display("    [FAIL] %0d of 256 Posit(4,1) results did NOT match (see MISMATCH lines above)",
                      errors - errors_before);

        // ---- FP4 (E2M1) exhaustive, frac_bits=8 (Q8.8) ----
        $display("");
        $display("--- Section 2/5: FP4 (E2M1) format, frac_bits=8 (Q8.8) ---");
        $display("    Sweeping all 16 x 16 = 256 operand combinations...");
        errors_before = errors;
        for (ia = 0; ia < 16; ia = ia + 1)
            for (ib = 0; ib < 16; ib = ib + 1)
                run_one(2'b01, ia[3:0], ib[3:0], 5'd8, golden_fp4[ia*16+ib], 1'b0);
        if (errors == errors_before)
            $display("    [PASS] all 256/256 FP4(E2M1) results matched the reference model");
        else
            $display("    [FAIL] %0d of 256 FP4(E2M1) results did NOT match (see MISMATCH lines above)",
                      errors - errors_before);

        // ---- FP2 exhaustive, frac_bits=8 (Q8.8) ----
        $display("");
        $display("--- Section 3/5: FP2 (element-level) format, frac_bits=8 (Q8.8) ---");
        $display("    Sweeping all 16 x 16 = 256 operand combinations...");
        errors_before = errors;
        for (ia = 0; ia < 16; ia = ia + 1)
            for (ib = 0; ib < 16; ib = ib + 1)
                run_one(2'b10, ia[3:0], ib[3:0], 5'd8, golden_fp2[ia*16+ib], 1'b0);
        if (errors == errors_before)
            $display("    [PASS] all 256/256 FP2(element) results matched the reference model");
        else
            $display("    [FAIL] %0d of 256 FP2(element) results did NOT match (see MISMATCH lines above)",
                      errors - errors_before);

        // ---- NEW: adaptive frac_bits sweep, all 3 formats, 2 more
        // precisions -- proves frac_bits is a genuine runtime input
        // shared across all three formats through this top's single
        // rescale-after-mux stage, not a fixed Q8.8 format with a
        // decorative port. Checked against an independently computed
        // golden model (golden_gen.py's rescale_from_q8).
        // -----------------------------------------------------------
        $display("");
        $display("--- Section 4/5: adaptive frac_bits sweep (all 3 formats x 2 more precisions) ---");
        $display(" format  | frac_bits | cases | passed | failed | status");
        $display(" --------|-----------|-------|--------|--------|-------");

        errors_before = errors;
        for (ia = 0; ia < 16; ia = ia + 1)
            for (ib = 0; ib < 16; ib = ib + 1)
                run_one(2'b00, ia[3:0], ib[3:0], 5'd6, golden_posit4_frac6[ia*16+ib], golden_posit4_nar[ia*16+ib]);
        if (errors == errors_before)
            $display(" posit4  | 6         | 256   | 256    | 0      | PASS");
        else
            $display(" posit4  | 6         | 256   | %-6d | %-6d | FAIL", 256-(errors-errors_before), errors-errors_before);

        errors_before = errors;
        for (ia = 0; ia < 16; ia = ia + 1)
            for (ib = 0; ib < 16; ib = ib + 1)
                run_one(2'b00, ia[3:0], ib[3:0], 5'd12, golden_posit4_frac12[ia*16+ib], golden_posit4_nar[ia*16+ib]);
        if (errors == errors_before)
            $display(" posit4  | 12        | 256   | 256    | 0      | PASS");
        else
            $display(" posit4  | 12        | 256   | %-6d | %-6d | FAIL", 256-(errors-errors_before), errors-errors_before);

        errors_before = errors;
        for (ia = 0; ia < 16; ia = ia + 1)
            for (ib = 0; ib < 16; ib = ib + 1)
                run_one(2'b01, ia[3:0], ib[3:0], 5'd6, golden_fp4_frac6[ia*16+ib], 1'b0);
        if (errors == errors_before)
            $display(" fp4     | 6         | 256   | 256    | 0      | PASS");
        else
            $display(" fp4     | 6         | 256   | %-6d | %-6d | FAIL", 256-(errors-errors_before), errors-errors_before);

        errors_before = errors;
        for (ia = 0; ia < 16; ia = ia + 1)
            for (ib = 0; ib < 16; ib = ib + 1)
                run_one(2'b01, ia[3:0], ib[3:0], 5'd12, golden_fp4_frac12[ia*16+ib], 1'b0);
        if (errors == errors_before)
            $display(" fp4     | 12        | 256   | 256    | 0      | PASS");
        else
            $display(" fp4     | 12        | 256   | %-6d | %-6d | FAIL", 256-(errors-errors_before), errors-errors_before);

        errors_before = errors;
        for (ia = 0; ia < 16; ia = ia + 1)
            for (ib = 0; ib < 16; ib = ib + 1)
                run_one(2'b10, ia[3:0], ib[3:0], 5'd6, golden_fp2_frac6[ia*16+ib], 1'b0);
        if (errors == errors_before)
            $display(" fp2     | 6         | 256   | 256    | 0      | PASS");
        else
            $display(" fp2     | 6         | 256   | %-6d | %-6d | FAIL", 256-(errors-errors_before), errors-errors_before);

        errors_before = errors;
        for (ia = 0; ia < 16; ia = ia + 1)
            for (ib = 0; ib < 16; ib = ib + 1)
                run_one(2'b10, ia[3:0], ib[3:0], 5'd12, golden_fp2_frac12[ia*16+ib], 1'b0);
        if (errors == errors_before)
            $display(" fp2     | 12        | 256   | 256    | 0      | PASS");
        else
            $display(" fp2     | 12        | 256   | %-6d | %-6d | FAIL", 256-(errors-errors_before), errors-errors_before);

        // ---- Directed test: nar_flag must be STICKY, not combinational ----
        // (regression test for a real bug caught in review: an earlier
        // revision drove nar_flag with a bare `assign` off the current-
        // cycle NaR detect, so it silently dropped the instant a
        // non-NaR operand followed. This checks it holds across
        // subsequent valid, non-NaR cycles until the next clear_acc.)
        $display("");
        $display("--- Section 5/5: 'sticky NaR flag' + partial-zero-on-NaR directed test (5 checks, not exhaustive) ---");
        $display("    Posit(4,1) has a special 'Not-a-Real' (NaR) code. When the hardware");
        $display("    sees it, a flag should latch HIGH and STAY high until the next new");
        $display("    dot-product starts -- not just blip for one clock cycle. This checks");
        $display("    exactly that sequence of events (a bug an earlier design review found,");
        $display("    since fixed):");
        errors_before = errors;
        begin : sticky_nar_test
            checks = checks + 1;
            @(negedge clk);
            mode_sel = 2'b00; a = 4'b1000; b = 4'b0100; frac_bits = 5'd8; // a = NaR
            clear_acc = 1'b1; valid_in = 1'b1;
            @(posedge clk); #1;
            if (nar_flag !== 1'b1) begin
                errors = errors + 1;
                $display("    [FAIL] flag not set on the cycle a NaR value appeared");
            end else
                $display("    [ok]   step 1/4: flag correctly SET the instant a NaR value appeared");
            // Additional check, added alongside the original 4 sticky-flag
            // steps: posit4_es1_pp.v now forces its own `partial` output
            // to zero on NaR, not just relying on the top-level's
            // do_accumulate gating to skip a possibly-meaningless value.
            // Checked here via hierarchical access to the internal
            // partial-product wire, confirming the fix at its source.
            checks = checks + 1;
            if (dut.pp_posit !== {32{1'b0}}) begin
                errors = errors + 1;
                $display("    [FAIL] posit4_es1_pp.v's own `partial` output was NOT zero on NaR (dut.pp_posit=%0d) -- standalone-use safety regression", dut.pp_posit);
            end else
                $display("    [ok]   posit4_es1_pp.v's own `partial` output is correctly zero at the source when NaR occurs (standalone-use safety)");
            clear_acc = 1'b0;
            // apply several subsequent valid, non-NaR cycles: flag must stay set
            mode_sel = 2'b00; a = 4'b0100; b = 4'b0100; // 1 x 1, no NaR
            @(negedge clk); valid_in = 1'b1; @(posedge clk); #1;
            checks = checks + 1;
            if (nar_flag !== 1'b1) begin
                errors = errors + 1;
                $display("    [FAIL] flag did not stay set across a subsequent valid, non-NaR cycle");
            end else
                $display("    [ok]   step 2/4: flag correctly STAYED set on the next (non-NaR) cycle");
            @(negedge clk); valid_in = 1'b1; @(posedge clk); #1;
            checks = checks + 1;
            if (nar_flag !== 1'b1) begin
                errors = errors + 1;
                $display("    [FAIL] flag dropped before a new dot-product was started");
            end else
                $display("    [ok]   step 3/4: flag still held after a second non-NaR cycle");
            // now start a fresh dot product: flag must clear
            @(negedge clk); clear_acc = 1'b1; valid_in = 1'b1; @(posedge clk); #1;
            checks = checks + 1;
            if (nar_flag !== 1'b0) begin
                errors = errors + 1;
                $display("    [FAIL] flag did not clear when a new dot-product (clear_acc) started");
            end else
                $display("    [ok]   step 4/4: flag correctly CLEARED when a new dot-product started");
            clear_acc = 1'b0; valid_in = 1'b0;
        end
        if (errors == errors_before)
            $display("    [PASS] all 5/5 sticky-NaR-flag + partial-zero checks behaved correctly");
        else
            $display("    [FAIL] %0d of 5 sticky-NaR-flag + partial-zero checks did NOT behave correctly",
                      errors - errors_before);

        $display("");
        $display("========================================================================");
        $display(" FINAL RESULT: %0d / %0d checks passed  (%0d errors)", checks-errors, checks, errors);
        if (errors == 0) begin
            $display(" *** ALL TESTS PASSED ***");
            $display(" -> Posit(4,1), FP4(E2M1), and FP2(element) are each verified correct");
            $display("    across every possible 4-bit operand combination, and the sticky");
            $display("    NaR-flag behavior is confirmed working.");
        end else begin
            $display(" *** %0d TEST(S) FAILED -- see [FAIL] lines and MISMATCH details above ***", errors);
        end
        $display("========================================================================");
        $finish;
    end

endmodule
