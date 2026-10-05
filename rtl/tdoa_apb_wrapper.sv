`timescale 1ns/1ps

module tdoa_apb_wrapper (
    input  logic        pclk,
    input  logic        presetn,
    input  logic [7:0]  paddr,
    input  logic        psel,
    input  logic        penable,
    input  logic        pwrite,
    input  logic [31:0] pwdata,
    output logic [31:0] prdata,
    output logic        pready,
    output logic        pslverr,
    output logic        irq
);

    assign pready  = 1'b1;
    assign pslverr = 1'b0;

    logic        start_pulse;
    logic        wr_en_x;
    logic [3:0]  wr_addr_x;
    logic signed [15:0] wr_data_x;
    logic        wr_en_y;
    logic [4:0]  wr_addr_y;
    logic signed [15:0] wr_data_y;

    logic signed [39:0] core_best_score;
    logic [3:0]         core_best_tau;
    logic               core_done;
    logic               core_busy;

    logic [1:0] reg_ctrl;
    logic       reg_done_flag;

    wire [31:0] score_low_word  = core_best_score[31:0];
    wire [7:0]  score_high_byte = core_best_score[39:32];

    tdoa_correlator u_correlator (
        .clk(pclk),
        .rst_n(presetn),
        .start(start_pulse),
        .wr_en_x(wr_en_x),
        .wr_addr_x(wr_addr_x),
        .wr_data_x(wr_data_x),
        .wr_en_y(wr_en_y),
        .wr_addr_y(wr_addr_y),
        .wr_data_y(wr_data_y),
        .best_score(core_best_score),
        .best_tau(core_best_tau),
        .done(core_done),
        .busy(core_busy)
    );

    wire apb_write_fire = psel && penable && pwrite && pready;
    wire apb_read_fire  = psel && !pwrite;

    assign irq = reg_ctrl[1] & reg_done_flag;

    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            reg_ctrl      <= 2'b00;
            reg_done_flag <= 1'b0;
            start_pulse   <= 1'b0;
            wr_en_x       <= 1'b0;
            wr_addr_x     <= 4'd0;
            wr_data_x     <= 16'sd0;
            wr_en_y       <= 1'b0;
            wr_addr_y     <= 5'd0;
            wr_data_y     <= 16'sd0;
        end else begin
            start_pulse <= 1'b0;
            wr_en_x     <= 1'b0;
            wr_en_y     <= 1'b0;

            if (core_done) begin
                reg_done_flag <= 1'b1;
            end

            if (apb_write_fire) begin
                case (paddr[7:0])
                    8'h00: begin
                        reg_ctrl[1] <= pwdata[1];
                        if (pwdata[0]) begin
                            start_pulse <= 1'b1;
                        end
                    end

                    8'h04: begin
                        if (pwdata[1]) begin
                            reg_done_flag <= 1'b0;
                        end
                    end

                    8'h14: begin
                        wr_en_x   <= 1'b1;
                        wr_addr_x <= pwdata[19:16];
                        wr_data_x <= pwdata[15:0];
                    end

                    8'h18: begin
                        wr_en_y   <= 1'b1;
                        wr_addr_y <= pwdata[20:16];
                        wr_data_y <= pwdata[15:0];
                    end

                    default: ;
                endcase
            end
        end
    end

    always_comb begin
        prdata = 32'd0;
        if (apb_read_fire) begin
            case (paddr[7:0])
                8'h00: prdata = {30'd0, reg_ctrl};
                8'h04: prdata = {30'd0, reg_done_flag, core_busy};
                8'h08: prdata = {28'd0, core_best_tau};
                8'h0C: prdata = score_low_word;
                8'h10: prdata = {{24{score_high_byte[7]}}, score_high_byte};
                default: prdata = 32'd0;
            endcase
        end
    end

endmodule
