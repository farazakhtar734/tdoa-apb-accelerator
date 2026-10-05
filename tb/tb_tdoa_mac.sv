`timescale 1ns/1ps

module tb_tdoa_mac;
    logic               clk;
    logic               rst_n;
    logic               clr_acc;
    logic               mac_en;
    logic signed [15:0] sample_a;
    logic signed [15:0] sample_b;
    logic signed [39:0] acc_out;
    logic               valid_out;

    integer errors;
    integer i;

    logic signed [39:0] golden_acc;
    logic signed [15:0] test_vectors_a [0:7];
    logic signed [15:0] test_vectors_b [0:7];

    tdoa_mac dut (
        .clk(clk),
        .rst_n(rst_n),
        .clr_acc(clr_acc),
        .mac_en(mac_en),
        .sample_a(sample_a),
        .sample_b(sample_b),
        .acc_out(acc_out),
        .valid_out(valid_out)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("sim/tdoa_mac.vcd");
        $dumpvars(0, tb_tdoa_mac);

        errors = 0;
        golden_acc = 40'sd0;
        clr_acc = 0;
        mac_en = 0;
        sample_a = 16'sd0;
        sample_b = 16'sd0;

        test_vectors_a[0] = 16'sd16384;  test_vectors_b[0] = 16'sd16384;
        test_vectors_a[1] = -16'sd8192;  test_vectors_b[1] = 16'sd16384;
        test_vectors_a[2] = 16'sd32767;  test_vectors_b[2] = 16'sd1000;
        test_vectors_a[3] = -16'sd16000; test_vectors_b[3] = -16'sd2000;
        test_vectors_a[4] = 16'sd500;    test_vectors_b[4] = -16'sd12000;
        test_vectors_a[5] = 16'sd24000;  test_vectors_b[5] = 16'sd1200;
        test_vectors_a[6] = -16'sd32000; test_vectors_b[6] = 16'sd500;
        test_vectors_a[7] = 16'sd1234;   test_vectors_b[7] = 16'sd4321;

        rst_n = 0;
        #25;
        rst_n = 1;
        #20;

        @(posedge clk);
        clr_acc <= 1'b1;
        @(posedge clk);
        clr_acc <= 1'b0;

        for (i = 0; i < 8; i = i + 1) begin
            @(posedge clk);
            mac_en   <= 1'b1;
            sample_a <= test_vectors_a[i];
            sample_b <= test_vectors_b[i];
            golden_acc = golden_acc + (test_vectors_a[i] * test_vectors_b[i]);
        end

        @(posedge clk);
        mac_en   <= 1'b0;
        sample_a <= 16'sd0;
        sample_b <= 16'sd0;

        @(posedge clk);
        @(posedge clk);
        #1;

        if (acc_out !== golden_acc) begin
            $display("[FATAL ERROR] Mathematical mismatch! Expected: %0d, Got: %0d", golden_acc, acc_out);
            errors = errors + 1;
        end else begin
            $display("[REAL DATA VERIFIED] Actual Accumulator Output = %0d", acc_out);
            $display("[REAL DATA VERIFIED] Reference Model Output    = %0d", golden_acc);
        end

        if (errors == 0) begin
            $display("========================================");
            $display("STAGE 1 PASSED: 0 ERRORS DETECTED");
            $display("========================================");
        end else begin
            $display("========================================");
            $display("STAGE 1 FAILED: %0d ERRORS DETECTED", errors);
            $display("========================================");
        end

        #20;
        $finish;
    end
endmodule
