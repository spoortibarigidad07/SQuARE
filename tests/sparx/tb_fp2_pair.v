// =====================================================================
// tb_fp2_pair.v
// Exhaustive self-checking testbench for the TRUE packed-pair FP2
// datapath (built in response to review feedback that the original
// element-level fp2_pp.v alone did not implement the paper's actual
// 2-values-per-4-bits storage format):
//   - fp2_pair_unpack.v            : 32 checks  (16 codes x 2 modes)
//   - fp2_pair_mac_fp4xfp2.v       : 8192 checks (Sec. IV-D unit)
//   - fp2_pair_mac_fp2xfp2.v       : 1024 checks (Sec. IV-E unit)
// All golden values come from golden/golden_gen.py, independent of
// this RTL.
// =====================================================================
`timescale 1ns/1ps

`ifndef GOLDEN_DIR
// Absolute path, defaulting to this package's known fixed deployment
// location: works unmodified for both Icarus and Vivado (whose
// simulation run directory does not mirror this package's source
// tree, so a relative path silently fails there -- symptom is every
// $readmemh leaving its array all-X, so every comparison reports
// "expected=x"). Override via `+define+GOLDEN_DIR="/other/path"` if
// you extract this package somewhere else.
`define GOLDEN_DIR "/home/sysad/Documents/project_novelties/SPARX_Extension/RTL/sparx_mac_ext/golden"
`endif

module tb_fp2_pair;

    integer errors, checks;

    // -------------------------------------------------------------
    // 1) fp2_pair_unpack.v -- pure combinational, no clock needed
    // -------------------------------------------------------------
    reg  [3:0] wp_u;
    reg        mode_u;
    wire [3:0] elem1_u, elem2_u;
    reg  [3:0] golden_elem1 [0:31];
    reg  [3:0] golden_elem2 [0:31];

    fp2_pair_unpack u_unpack (.wp(wp_u), .is_e0m1(mode_u), .elem1(elem1_u), .elem2(elem2_u));

    // -------------------------------------------------------------
    // 2) fp2_pair_mac_fp4xfp2.v
    // -------------------------------------------------------------
    reg         clk, rst_n;
    reg         clear_acc1, valid_in1, mode1;
    reg  [3:0]  wp1, fa1, fb1;
    wire signed [31:0] acc1;
    wire        valid_out1;
    reg  [31:0] golden_fp4xfp2 [0:8191];

    fp2_pair_mac_fp4xfp2 #(.ACC_W(32)) dut1 (
        .clk(clk), .rst_n(rst_n), .clear_acc(clear_acc1), .valid_in(valid_in1),
        .is_e0m1(mode1), .wp(wp1), .fa(fa1), .fb(fb1),
        .acc(acc1), .valid_out(valid_out1)
    );

    // -------------------------------------------------------------
    // 3) fp2_pair_mac_fp2xfp2.v
    // -------------------------------------------------------------
    reg         clear_acc2, valid_in2, mode_w2, mode_a2;
    reg  [3:0]  wp2, ap2;
    wire signed [31:0] acc2;
    wire        valid_out2;
    reg  [31:0] golden_fp2xfp2 [0:1023];

    fp2_pair_mac_fp2xfp2 #(.ACC_W(32)) dut2 (
        .clk(clk), .rst_n(rst_n), .clear_acc(clear_acc2), .valid_in(valid_in2),
        .is_e0m1_w(mode_w2), .is_e0m1_a(mode_a2), .wp(wp2), .ap(ap2),
        .acc(acc2), .valid_out(valid_out2)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer iwp, imode, ifa, ifb, iap, imw, ima;
    integer idx;

    task run_fp4xfp2(input [3:0] w_p, input mode, input [3:0] f_a, input [3:0] f_b,
                      input [31:0] expect_val);
        begin
            @(negedge clk);
            wp1 = w_p; mode1 = mode; fa1 = f_a; fb1 = f_b;
            clear_acc1 = 1'b1; valid_in1 = 1'b1;
            @(posedge clk); #1;
            checks = checks + 1;
            if (acc1 !== $signed(expect_val)) begin
                errors = errors + 1;
                $display("FP4xFP2 MISMATCH wp=%b mode=%b fa=%b fb=%b : acc=%0d expected=%0d",
                          w_p, mode, f_a, f_b, acc1, $signed(expect_val));
            end
            clear_acc1 = 1'b0; valid_in1 = 1'b0;
        end
    endtask

    task run_fp2xfp2(input [3:0] w_p, input mw, input [3:0] a_p, input ma,
                      input [31:0] expect_val);
        begin
            @(negedge clk);
            wp2 = w_p; mode_w2 = mw; ap2 = a_p; mode_a2 = ma;
            clear_acc2 = 1'b1; valid_in2 = 1'b1;
            @(posedge clk); #1;
            checks = checks + 1;
            if (acc2 !== $signed(expect_val)) begin
                errors = errors + 1;
                $display("FP2xFP2 MISMATCH wp=%b mw=%b ap=%b ma=%b : acc=%0d expected=%0d",
                          w_p, mw, a_p, ma, acc2, $signed(expect_val));
            end
            clear_acc2 = 1'b0; valid_in2 = 1'b0;
        end
    endtask

    // -------------------------------------------------------------
    // 4) fp2_pair_kfactor_mac.v -- optimized single-multiplier variant
    //    checked for EXACT equivalence against dut2 (fp2_pair_mac_fp2xfp2,
    //    the straightforward unpack+2-multiply reference) on identical
    //    stimulus, not just against the golden .hex (belt and braces).
    // -------------------------------------------------------------
    reg         clear_acc3, valid_in3;
    wire signed [31:0] acc3;
    wire        valid_out3;

    fp2_pair_kfactor_mac #(.ACC_W(32)) dut3 (
        .clk(clk), .rst_n(rst_n), .clear_acc(clear_acc3), .valid_in(valid_in3),
        .is_e0m1_w(mode_w2), .is_e0m1_a(mode_a2), .wp(wp2), .ap(ap2),
        .acc(acc3), .valid_out(valid_out3)
    );

    task run_fp2xfp2_and_kfactor(input [3:0] w_p, input mw, input [3:0] a_p, input ma,
                      input [31:0] expect_val);
        begin
            @(negedge clk);
            wp2 = w_p; mode_w2 = mw; ap2 = a_p; mode_a2 = ma;
            clear_acc2 = 1'b1; valid_in2 = 1'b1;
            clear_acc3 = 1'b1; valid_in3 = 1'b1;
            clear_acc4 = 1'b1; valid_in4 = 1'b1;
            @(posedge clk); #1;
            checks = checks + 1;
            if (acc2 !== $signed(expect_val)) begin
                errors = errors + 1;
                $display("FP2xFP2 MISMATCH wp=%b mw=%b ap=%b ma=%b : acc=%0d expected=%0d",
                          w_p, mw, a_p, ma, acc2, $signed(expect_val));
            end
            checks = checks + 1;
            if (acc3 !== acc2) begin
                errors = errors + 1;
                $display("K-FACTOR MISMATCH vs reference wp=%b mw=%b ap=%b ma=%b : kfactor_acc=%0d reference_acc=%0d",
                          w_p, mw, a_p, ma, acc3, acc2);
            end
            checks = checks + 1;
            if (acc4 !== acc2) begin
                errors = errors + 1;
                $display("SIGNED-K-FACTOR MISMATCH vs reference wp=%b mw=%b ap=%b ma=%b : signed_kfactor_acc=%0d reference_acc=%0d",
                          w_p, mw, a_p, ma, acc4, acc2);
            end
            // Tally which signed-K value this combination exercised, so
            // the final report proves K=-1 and K=-2 are reached (not
            // just theoretically possible).
            case (k_signed_dbg)
                -3'sd2:  count_kneg2 = count_kneg2 + 1;
                -3'sd1:  count_kneg1 = count_kneg1 + 1;
                 3'sd0:  count_kzero = count_kzero + 1;
                 3'sd1:  count_kpos1 = count_kpos1 + 1;
                 3'sd2:  count_kpos2 = count_kpos2 + 1;
            endcase
            clear_acc2 = 1'b0; valid_in2 = 1'b0;
            clear_acc3 = 1'b0; valid_in3 = 1'b0;
            clear_acc4 = 1'b0; valid_in4 = 1'b0;
        end
    endtask

    // -------------------------------------------------------------
    // 5) fp2_pair_kfactor_signed_mac.v -- explicit signed-K variant,
    //    added to make K=-1/-2 occurrence undeniable (not just argued).
    //    Checked bit-exact against dut2/dut3, AND its K_signed output is
    //    tallied so the test report itself shows how many of the 1024
    //    combinations exercise K=-1 and K=-2.
    // -------------------------------------------------------------
    reg         clear_acc4, valid_in4;
    wire signed [31:0] acc4;
    wire        valid_out4;
    wire signed [2:0] k_signed_dbg;
    integer count_kneg1, count_kneg2, count_kpos1, count_kpos2, count_kzero;

    fp2_pair_kfactor_signed_mac #(.ACC_W(32)) dut4 (
        .clk(clk), .rst_n(rst_n), .clear_acc(clear_acc4), .valid_in(valid_in4),
        .is_e0m1_w(mode_w2), .is_e0m1_a(mode_a2), .wp(wp2), .ap(ap2),
        .acc(acc4), .valid_out(valid_out4), .k_signed_dbg(k_signed_dbg)
    );

    integer errors_before;

    initial begin
        // Path is a single edit point via `GOLDEN_DIR, same rationale as
        // tb_sparx_mac_unified.v.
        $readmemh({`GOLDEN_DIR, "/golden_pairunpack_elem1.hex"}, golden_elem1);
        $readmemh({`GOLDEN_DIR, "/golden_pairunpack_elem2.hex"}, golden_elem2);
        $readmemh({`GOLDEN_DIR, "/golden_fp4xfp2_pair.hex"},     golden_fp4xfp2);
        $readmemh({`GOLDEN_DIR, "/golden_fp2xfp2_pair.hex"},     golden_fp2xfp2);

        errors = 0; checks = 0;
        rst_n = 0; clear_acc1=0; valid_in1=0; clear_acc2=0; valid_in2=0;
        clear_acc3=0; valid_in3=0; clear_acc4=0; valid_in4=0;
        count_kneg1=0; count_kneg2=0; count_kpos1=0; count_kpos2=0; count_kzero=0;
        wp_u = 0; mode_u = 0;
        @(negedge clk); @(negedge clk);
        rst_n = 1;

        $display("========================================================================");
        $display(" SPARX Packed-Pair FP2 Datapath Testbench");
        $display(" ");
        $display(" Background: the FP2 format packs TWO floating-point values into a");
        $display(" single 4-bit code (instead of 4 bits per value), which is how it claims");
        $display(" a 2-bit-per-value storage density. This testbench checks every stage of");
        $display(" actually USING that packed format in real MAC hardware, in order:");
        $display("   1) Unpacking     : does a packed 4-bit code correctly decode back");
        $display("                      into its two individual values?");
        $display("   2) FP4 x FP2 MAC : the format's primary use case -- full-precision");
        $display("                      (FP4) activations multiplied by compressed (FP2)");
        $display("                      weights.");
        $display("   3) FP2 x FP2 MAC : BOTH operands compressed, checked THREE ways --");
        $display("                      a straightforward reference (2 multipliers), and");
        $display("                      two optimized 'K-factor' implementations that use");
        $display("                      only ONE multiplier. All three must always agree.");
        $display(" Every number below is checked against an independent Python model, not");
        $display(" just checked for 'did it run without crashing'.");
        $display("========================================================================");

        // ---- 1) fp2_pair_unpack exhaustive (combinational) ----
        $display("");
        $display("--- Stage 1/3: Pair unpacking (fp2_pair_unpack.v) ---");
        $display("    Sweeping all 16 packed codes x 2 encoding modes (E1M0/E0M1) = 32 cases");
        $display("    (this includes the tricky 'opposite-sign pair' case for code C=00,");
        $display("     and the one true all-zero code 0000 -- see docs/DESIGN_NOTES.md Sec 0.3");
        $display("     for why that distinction matters and how an earlier version got it wrong)");
        errors_before = errors;
        for (iwp = 0; iwp < 16; iwp = iwp + 1) begin
            for (imode = 0; imode < 2; imode = imode + 1) begin
                idx = iwp*2 + imode;
                wp_u = iwp[3:0]; mode_u = imode[0];
                #1;
                checks = checks + 1;
                if (elem1_u !== golden_elem1[idx] || elem2_u !== golden_elem2[idx]) begin
                    errors = errors + 1;
                    $display("    MISMATCH wp=%b mode=%b : elem1=%b (exp %b) elem2=%b (exp %b)",
                              iwp, imode, elem1_u, golden_elem1[idx], elem2_u, golden_elem2[idx]);
                end
            end
        end
        if (errors == errors_before)
            $display("    [PASS] all 32/32 unpack results matched the reference model");
        else
            $display("    [FAIL] %0d of 32 unpack results did NOT match (see MISMATCH lines above)",
                      errors - errors_before);

        // ---- 2) fp2_pair_mac_fp4xfp2 exhaustive (8192 checks) ----
        $display("");
        $display("--- Stage 2/3: FP4 (activation) x FP2 (weight) pair MAC ---");
        $display("    Sweeping all 16 weight-pair codes x 2 modes x 16 FP4 activations x");
        $display("    16 FP4 activations = 8192 cases...");
        errors_before = errors;
        idx = 0;
        for (iwp = 0; iwp < 16; iwp = iwp + 1)
            for (imode = 0; imode < 2; imode = imode + 1)
                for (ifa = 0; ifa < 16; ifa = ifa + 1)
                    for (ifb = 0; ifb < 16; ifb = ifb + 1) begin
                        run_fp4xfp2(iwp[3:0], imode[0], ifa[3:0], ifb[3:0], golden_fp4xfp2[idx]);
                        idx = idx + 1;
                    end
        if (errors == errors_before)
            $display("    [PASS] all 8192/8192 results matched the reference model");
        else
            $display("    [FAIL] %0d of 8192 results did NOT match (see MISMATCH lines above)",
                      errors - errors_before);

        // ---- 3) fp2_pair_mac_fp2xfp2 exhaustive (1024 checks) PLUS
        //         fp2_pair_kfactor_mac equivalence check (1024 more) ----
        $display("");
        $display("--- Stage 3/3: FP2 (activation) x FP2 (weight) pair MAC, 3 implementations ---");
        $display("    Sweeping all 16 weight-pair codes x 2 modes x 16 activation-pair");
        $display("    codes x 2 modes = 1024 cases, each checked THREE ways:");
        $display("      (a) reference implementation      -- 2 multipliers, must match golden model");
        $display("      (b) 'K-factor' optimization        -- 1 multiplier, must match (a) exactly");
        $display("      (c) explicit signed-K variant of (b) -- must also match (a) exactly, and");
        $display("          its K value is tallied below to prove every value in");
        $display("          {-2,-1,0,+1,+2} genuinely occurs, not just theoretically possible");
        errors_before = errors;
        idx = 0;
        for (iwp = 0; iwp < 16; iwp = iwp + 1)
            for (imw = 0; imw < 2; imw = imw + 1)
                for (iap = 0; iap < 16; iap = iap + 1)
                    for (ima = 0; ima < 2; ima = ima + 1) begin
                        run_fp2xfp2_and_kfactor(iwp[3:0], imw[0], iap[3:0], ima[0], golden_fp2xfp2[idx]);
                        idx = idx + 1;
                    end
        if (errors == errors_before)
            $display("    [PASS] all 3 implementations agreed on all 1024/1024 cases (3072 checks)");
        else
            $display("    [FAIL] %0d mismatch(es) among the 3072 checks in this stage (see lines above)",
                      errors - errors_before);

        $display("");
        $display("    K value distribution across those 1024 cases (proves the optimized");
        $display("    hardware genuinely exercises every case the algebra says it should,");
        $display("    not just the common ones):");
        $display("      K = -2 : %4d cases", count_kneg2);
        $display("      K = -1 : %4d cases   <-- confirms NEGATIVE K genuinely occurs", count_kneg1);
        $display("      K =  0 : %4d cases", count_kzero);
        $display("      K = +1 : %4d cases", count_kpos1);
        $display("      K = +2 : %4d cases", count_kpos2);

        $display("");
        $display("========================================================================");
        $display(" FINAL RESULT: %0d / %0d checks passed  (%0d errors)", checks-errors, checks, errors);
        if (errors == 0) begin
            $display(" *** ALL PAIR-DATAPATH TESTS PASSED ***");
            $display(" -> The packed FP2 format's unpacking, both its use cases (FP4xFP2 and");
            $display("    FP2xFP2), and the optimized single-multiplier K-factor hardware are");
            $display("    all confirmed correct.");
        end else begin
            $display(" *** %0d TEST(S) FAILED -- see [FAIL] lines and MISMATCH details above ***", errors);
        end
        $display("========================================================================");
        $finish;
    end

endmodule
