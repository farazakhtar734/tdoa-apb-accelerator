`timescale 1ns/1ps

module tdoa_correlator (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               start,
    input  logic               wr_en_x,
    input  logic [3:0]         wr_addr_x,
    input  logic signed [15:0] wr_data_x,
    input  logic               wr_en_y,
    input  logic [4:0]         wr_addr_y,
    input  logic signed [15:0] wr_data_y,
    output logic signed [39:0] best_score,
    output logic [3:0]         best_tau,
    output logic               done,
    output logic               busy
);

    typedef enum logic [2:0] {
        IDLE,
        INIT_LAG,
        STREAM,
        PIPE_WAIT1,
        PIPE_WAIT2,
        UPDATE_PEAK,
        FINISHED
    } state_t;

    state_t state;

    logic signed [15:0] ram_x [0:15];
    logic signed [15:0] ram_y [0:31];

    always_ff @(posedge clk) begin
        if (wr_en_x) ram_x[wr_addr_x] <= wr_data_x;
    end

    always_ff @(posedge clk) begin
        if (wr_en_y) ram_y[wr_addr_y] <= wr_data_y;
    end

    logic [3:0] tau_cnt;
    logic [4:0] sample_idx;
    logic       clr_acc;
    logic       mac_en;
    logic signed [15:0] mac_sample_a;
    logic signed [15:0] mac_sample_b;
    logic signed [39:0] mac_acc_out;
    logic               mac_valid_out;

    tdoa_mac u_mac (
        .clk(clk),
        .rst_n(rst_n),
        .clr_acc(clr_acc),
        .mac_en(mac_en),
        .sample_a(mac_sample_a),
        .sample_b(mac_sample_b),
        .acc_out(mac_acc_out),
        .valid_out(mac_valid_out)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            tau_cnt      <= 4'd0;
            sample_idx   <= 5'd0;
            clr_acc      <= 1'b0;
            mac_en       <= 1'b0;
            mac_sample_a <= 16'sd0;
            mac_sample_b <= 16'sd0;
            best_score   <= -40'sh4000000000;
            best_tau     <= 4'd0;
            done         <= 1'b0;
            busy         <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        busy       <= 1'b1;
                        tau_cnt    <= 4'd0;
                        best_score <= -40'sh4000000000;
                        best_tau   <= 4'd0;
                        state      <= INIT_LAG;
                    end else begin
                        busy <= 1'b0;
                    end
                end

                INIT_LAG: begin
                    clr_acc    <= 1'b1;
                    sample_idx <= 5'd0;
                    state      <= STREAM;
                end

                STREAM: begin
                    clr_acc      <= 1'b0;
                    mac_en       <= 1'b1;
                    mac_sample_a <= ram_x[sample_idx[3:0]];
                    mac_sample_b <= ram_y[sample_idx + tau_cnt];

                    if (sample_idx == 5'd15) begin
                        state <= PIPE_WAIT1;
                    end else begin
                        sample_idx <= sample_idx + 1'b1;
                    end
                end

                PIPE_WAIT1: begin
                    mac_en <= 1'b0;
                    state  <= PIPE_WAIT2;
                end

                PIPE_WAIT2: begin
                    state <= UPDATE_PEAK;
                end

                UPDATE_PEAK: begin
                    if (mac_acc_out > best_score) begin
                        best_score <= mac_acc_out;
                        best_tau   <= tau_cnt;
                    end

                    if (tau_cnt == 4'd7) begin
                        state <= FINISHED;
                    end else begin
                        tau_cnt <= tau_cnt + 1'b1;
                        state   <= INIT_LAG;
                    end
                end

                FINISHED: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
