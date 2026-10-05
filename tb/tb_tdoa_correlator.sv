`timescale 1ns/1ps

module tb_tdoa_correlator;
    logic               clk;
    logic               rst_n;
    logic               start;
    logic               wr_en_x;
    logic [3:0]         wr_addr_x;
    logic signed [15:0] wr_data_x;
    logic               wr_en_y;
    logic [4:0]         wr_addr_y;
    logic signed [15:0] wr_data_y;
    logic signed [39:0] best_score;
    logic [3:0]         best_tau;
    logic               done;
    logic               busy;

    integer i;
    integer errors;
    logic signed [15:0] pulse_pattern [0:15];
    logic signed [39:0] expected_peak_score;

    tdoa_correlator dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .wr_en_x(wr_en_x),
        .wr_addr_x(wr_addr_x),
        .wr_data_x(wr_data_x),
        .wr_en_y(wr_en_y),
        .wr_addr_y(wr_addr_y),
        .wr_data_y(wr_data_y),
        .best_score(best_score),
        .best_tau(best_tau),
        .done(done),
        .busy(busy)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("sim/tdoa_correlator.vcd");
        $dumpvars(0, tb_tdoa_correlator);

        errors = 0;
        start = 0;
        wr_en_x = 0;
        wr_addr_x = 0;
        wr_data_x = 0;
        wr_en_y = 0;
        wr_addr_y = 0;
        wr_data_y = 0;
        expected_peak_score = 40'sd0;

        pulse_pattern[0]  = 16'sd1000;
        pulse_pattern[1]  = 16'sd3000;
        pulse_pattern[2]  = 16'sd7000;
        pulse_pattern[3]  = 16'sd15000;
        pulse_pattern[4]  = 16'sd28000;
        pulse_pattern[5]  = 16'sd32000;
        pulse_pattern[6]  = 16'sd24000;
        pulse_pattern[7]  = 16'sd12000;
        pulse_pattern[8]  = -16'sd8000;
        pulse_pattern[9]  = -16'sd16000;
        pulse_pattern[10] = -16'sd22000;
        pulse_pattern[11] = -16'sd18000;
        pulse_pattern[12] = -16'sd10000;
        pulse_pattern[13] = -16'sd4000;
        pulse_pattern[14] = 16'sd1000;
        pulse_pattern[15] = 16'sd500;

        for (i = 0; i < 16; i = i + 1) begin
            expected_peak_score = expected_peak_score + (pulse_pattern[i] * pulse_pattern[i]);
        end

        rst_n = 0;
        #20;
        rst_n = 1;
        #20;

        for (i = 0; i < 16; i = i + 1) begin
            @(posedge clk);
            wr_en_x   <= 1'b1;
            wr_addr_x <= i[3:0];
            wr_data_x <= pulse_pattern[i];
        end
        @(posedge clk);
        wr_en_x <= 1'b0;

        for (i = 0; i < 32; i = i + 1) begin
            @(posedge clk);
            wr_en_y   <= 1'b1;
            wr_addr_y <= i[4:0];
            if (i >= 3 && i < 19) begin
                wr_data_y <= pulse_pattern[i - 3];
            end else begin
                wr_data_y <= 16'sd0;
            end
        end
        @(posedge clk);
        wr_en_y <= 1'b0;

        #20;
        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        @(posedge done);
        #1;

        if (best_tau !== 4'd3) begin
            $display("[FATAL ERROR] Peak detection mismatch! Expected Tau: 3, Detected Tau: %0d", best_tau);
            errors = errors + 1;
        end else begin
            $display("[REAL DATA VERIFIED] Time Delay (Tau) Detected = %0d sample intervals", best_tau);
        end

        if (best_score !== expected_peak_score) begin
            $display("[FATAL ERROR] Score mismatch! Expected: %0d, Detected: %0d", expected_peak_score, best_score);
            errors = errors + 1;
        end else begin
            $display("[REAL DATA VERIFIED] Peak Correlation Score   = %0d", best_score);
            $display("[REAL DATA VERIFIED] Golden Autocorrelation    = %0d", expected_peak_score);
        end

        if (errors == 0) begin
            $display("========================================");
            $display("STAGE 2 PASSED: 0 ERRORS DETECTED");
            $display("========================================");
        end else begin
            $display("========================================");
            $display("STAGE 2 FAILED: %0d ERRORS DETECTED", errors);
            $display("========================================");
        end

        #50;
        $finish;
    end
endmodule
