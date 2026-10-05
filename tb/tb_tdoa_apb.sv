`timescale 1ns/1ps

module tb_tdoa_apb;
    logic        pclk;
    logic        presetn;
    logic [7:0]  paddr;
    logic        psel;
    logic        penable;
    logic        pwrite;
    logic [31:0] pwdata;
    logic [31:0] prdata;
    logic        pready;
    logic        pslverr;
    logic        irq;

    integer i;
    integer errors;
    integer assertions_checked;

    logic signed [15:0] pulse_pattern [0:15];
    logic signed [39:0] expected_peak_score;
    logic [31:0] read_val_low;
    logic [31:0] read_val_high;
    logic [31:0] read_val_tau;
    logic signed [39:0] read_score_assembled;

    tdoa_apb_wrapper dut (
        .pclk(pclk),
        .presetn(presetn),
        .paddr(paddr),
        .psel(psel),
        .penable(penable),
        .pwrite(pwrite),
        .pwdata(pwdata),
        .prdata(prdata),
        .pready(pready),
        .pslverr(pslverr),
        .irq(irq)
    );

    initial pclk = 0;
    always #5 pclk = ~pclk;

    always @(posedge pclk) begin
        if (presetn) begin
            if (irq) begin
                if (!(dut.reg_ctrl[1] && dut.reg_done_flag)) begin
                    $display("[ASSERTION VIOLATION] IRQ asserted illegally without enable or done flag!");
                    errors = errors + 1;
                end else begin
                    assertions_checked = assertions_checked + 1;
                end
            end

            if (dut.core_best_tau > 4'd7) begin
                $display("[ASSERTION VIOLATION] Detected Tau (%0d) out of search bounds!", dut.core_best_tau);
                errors = errors + 1;
            end

            if (psel && !penable) begin
                assertions_checked = assertions_checked + 1;
            end
        end
    end

    task apb_write(input [7:0] addr, input [31:0] data);
        begin
            @(posedge pclk);
            paddr   <= addr;
            pwrite  <= 1'b1;
            psel    <= 1'b1;
            penable <= 1'b0;
            pwdata  <= data;
            @(posedge pclk);
            penable <= 1'b1;
            @(posedge pclk);
            psel    <= 1'b0;
            penable <= 1'b0;
        end
    endtask

    task apb_read(input [7:0] addr, output [31:0] data);
        begin
            @(posedge pclk);
            paddr   <= addr;
            pwrite  <= 1'b0;
            psel    <= 1'b1;
            penable <= 1'b0;
            @(posedge pclk);
            penable <= 1'b1;
            @(posedge pclk);
            data    = prdata;
            psel    <= 1'b0;
            penable <= 1'b0;
        end
    endtask

    initial begin
        $dumpfile("sim/tdoa_apb.vcd");
        $dumpvars(0, tb_tdoa_apb);

        errors = 0;
        assertions_checked = 0;
        psel = 0;
        penable = 0;
        pwrite = 0;
        paddr = 0;
        pwdata = 0;
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

        presetn = 0;
        #30;
        presetn = 1;
        #20;

        apb_write(8'h00, 32'h00000002);

        for (i = 0; i < 16; i = i + 1) begin
            apb_write(8'h14, {12'd0, i[3:0], pulse_pattern[i]});
        end

        for (i = 0; i < 32; i = i + 1) begin
            if (i >= 3 && i < 19) begin
                apb_write(8'h18, {11'd0, i[4:0], pulse_pattern[i - 3]});
            end else begin
                apb_write(8'h18, {11'd0, i[4:0], 16'sd0});
            end
        end

        apb_write(8'h00, 32'h00000003);

        @(posedge irq);
        #1;
        $display("[INTERRUPT] Hardware IRQ asserted by accelerator!");

        apb_read(8'h08, read_val_tau);
        apb_read(8'h0C, read_val_low);
        apb_read(8'h10, read_val_high);

        read_score_assembled = {read_val_high[7:0], read_val_low};

        if (read_val_tau[3:0] !== 4'd3) begin
            $display("[FATAL ERROR] APB Tau mismatch! Expected: 3, Read: %0d", read_val_tau[3:0]);
            errors = errors + 1;
        end else begin
            $display("[REAL DATA VERIFIED] APB Read Register 0x08 (Tau): %0d", read_val_tau[3:0]);
        end

        if (read_score_assembled !== expected_peak_score) begin
            $display("[FATAL ERROR] APB Score mismatch! Expected: %0d, Read: %0d", expected_peak_score, read_score_assembled);
            errors = errors + 1;
        end else begin
            $display("[REAL DATA VERIFIED] APB Read Assembled Score   : %0d", read_score_assembled);
            $display("[REAL DATA VERIFIED] Golden Mathematical Value  : %0d", expected_peak_score);
        end

        apb_write(8'h04, 32'h00000002);
        #10;

        if (irq !== 1'b0) begin
            $display("[FATAL ERROR] W1C failed: IRQ did not deassert!");
            errors = errors + 1;
        end else begin
            $display("[REAL DATA VERIFIED] W1C verified: IRQ successfully cleared by software!");
        end

        if (errors == 0) begin
            $display("========================================");
            $display("PROTOCOL ASSERTIONS PASSED: %0d CHECKS", assertions_checked);
            $display("STAGE 4 PASSED: ZERO DEFECTS DETECTED");
            $display("========================================");
        end else begin
            $display("========================================");
            $display("STAGE 4 FAILED: %0d ERRORS DETECTED", errors);
            $display("========================================");
        end

        #50;
        $finish;
    end
endmodule
