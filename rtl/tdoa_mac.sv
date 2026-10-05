`timescale 1ns/1ps

module tdoa_mac (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               clr_acc,
    input  logic               mac_en,
    input  logic signed [15:0] sample_a,
    input  logic signed [15:0] sample_b,
    output logic signed [39:0] acc_out,
    output logic               valid_out
);

    logic signed [31:0] mul_reg;
    logic               stage1_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mul_reg      <= 32'sd0;
            stage1_valid <= 1'b0;
        end else if (mac_en) begin
            mul_reg      <= sample_a * sample_b;
            stage1_valid <= 1'b1;
        end else begin
            stage1_valid <= 1'b0;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_out   <= 40'sd0;
            valid_out <= 1'b0;
        end else if (clr_acc) begin
            acc_out   <= 40'sd0;
            valid_out <= 1'b0;
        end else if (stage1_valid) begin
            acc_out   <= acc_out + {{8{mul_reg[31]}}, mul_reg};
            valid_out <= 1'b1;
        end else begin
            valid_out <= 1'b0;
        end
    end

endmodule
