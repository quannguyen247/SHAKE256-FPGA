`timescale 1ns / 1ps

`include "../utils/keccak_defs.vh"

(* keep_hierarchy = "yes" *)
module keccak_theta_rho_pi_stage (
    state_in,
    state_out
);
    input [`KECCAK_STATE_WIDTH-1:0] state_in;
    output [`KECCAK_STATE_WIDTH-1:0] state_out;

    reg [`KECCAK_STATE_WIDTH-1:0] state_out_reg;

    reg [63:0] a [0:24];
    reg [63:0] b [0:24];
    reg [63:0] c [0:4];
    reg [63:0] d [0:4];
    integer x;
    integer y;
    integer i;
    integer src_x;
    integer src_y;
    integer src_idx;

    function [63:0] rotl64;
        input [63:0] value;
        input [5:0] amount;
        begin
            if (amount == 0)
                rotl64 = value;
            else
                rotl64 = (value << amount) | (value >> (64 - amount));
        end
    endfunction

    function [5:0] rho_offset;
        input [4:0] lane;
        begin
            case (lane)
                5'd0:  rho_offset = 6'd0;
                5'd1:  rho_offset = 6'd1;
                5'd2:  rho_offset = 6'd62;
                5'd3:  rho_offset = 6'd28;
                5'd4:  rho_offset = 6'd27;
                5'd5:  rho_offset = 6'd36;
                5'd6:  rho_offset = 6'd44;
                5'd7:  rho_offset = 6'd6;
                5'd8:  rho_offset = 6'd55;
                5'd9:  rho_offset = 6'd20;
                5'd10: rho_offset = 6'd3;
                5'd11: rho_offset = 6'd10;
                5'd12: rho_offset = 6'd43;
                5'd13: rho_offset = 6'd25;
                5'd14: rho_offset = 6'd39;
                5'd15: rho_offset = 6'd41;
                5'd16: rho_offset = 6'd45;
                5'd17: rho_offset = 6'd15;
                5'd18: rho_offset = 6'd21;
                5'd19: rho_offset = 6'd8;
                5'd20: rho_offset = 6'd18;
                5'd21: rho_offset = 6'd2;
                5'd22: rho_offset = 6'd61;
                5'd23: rho_offset = 6'd56;
                5'd24: rho_offset = 6'd14;
                default: rho_offset = 6'd0;
            endcase
        end
    endfunction

    always @(*) begin
        state_out_reg = {`KECCAK_STATE_WIDTH{1'b0}};

        for (i = 0; i < 25; i = i + 1) begin
            a[i] = state_in[(i * 64) +: 64];
            b[i] = 64'h0;
        end

        for (x = 0; x < 5; x = x + 1) begin
            c[x] = a[x] ^ a[x + 5] ^ a[x + 10] ^ a[x + 15] ^ a[x + 20];
        end

        for (x = 0; x < 5; x = x + 1) begin
            d[x] = c[(x + 4) % 5] ^ rotl64(c[(x + 1) % 5], 6'd1);
        end

        for (y = 0; y < 5; y = y + 1) begin
            for (x = 0; x < 5; x = x + 1) begin
                a[x + (5 * y)] = a[x + (5 * y)] ^ d[x];
            end
        end

        for (y = 0; y < 5; y = y + 1) begin
            for (x = 0; x < 5; x = x + 1) begin
                src_x = (x + 3 * y) % 5;
                src_y = x;
                src_idx = src_x + (5 * src_y);
                b[x + (5 * y)] = rotl64(a[src_idx], rho_offset(src_idx));
            end
        end

        for (i = 0; i < 25; i = i + 1) begin
            state_out_reg[(i * 64) +: 64] = b[i];
        end
    end

    assign state_out = state_out_reg;

endmodule
