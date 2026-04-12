`timescale 1ns / 1ps

`include "../utils/keccak_defs.vh"

(* keep_hierarchy = "yes" *)
module keccak_round (
    state_in,
    round_idx,
    state_out
);
    input  [`KECCAK_STATE_WIDTH-1:0] state_in;
    input  [4:0] round_idx;
    output [`KECCAK_STATE_WIDTH-1:0] state_out;

    reg [`KECCAK_STATE_WIDTH-1:0] state_out;

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

    // Canonical Rho offsets r[x,y] from Keccak-f[1600], indexed by lane x+5*y.
    // This table must match FIPS 202 / XKCP exactly for bit-accurate outputs.
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

    function [63:0] round_constant;
        input [4:0] idx;
        begin
            case (idx)
                5'd0:  round_constant = 64'h0000000000000001;
                5'd1:  round_constant = 64'h0000000000008082;
                5'd2:  round_constant = 64'h800000000000808a;
                5'd3:  round_constant = 64'h8000000080008000;
                5'd4:  round_constant = 64'h000000000000808b;
                5'd5:  round_constant = 64'h0000000080000001;
                5'd6:  round_constant = 64'h8000000080008081;
                5'd7:  round_constant = 64'h8000000000008009;
                5'd8:  round_constant = 64'h000000000000008a;
                5'd9:  round_constant = 64'h0000000000000088;
                5'd10: round_constant = 64'h0000000080008009;
                5'd11: round_constant = 64'h000000008000000a;
                5'd12: round_constant = 64'h000000008000808b;
                5'd13: round_constant = 64'h800000000000008b;
                5'd14: round_constant = 64'h8000000000008089;
                5'd15: round_constant = 64'h8000000000008003;
                5'd16: round_constant = 64'h8000000000008002;
                5'd17: round_constant = 64'h8000000000000080;
                5'd18: round_constant = 64'h000000000000800a;
                5'd19: round_constant = 64'h800000008000000a;
                5'd20: round_constant = 64'h8000000080008081;
                5'd21: round_constant = 64'h8000000000008080;
                5'd22: round_constant = 64'h0000000080000001;
                5'd23: round_constant = 64'h8000000080008008;
                default: round_constant = 64'h0;
            endcase
        end
    endfunction

    always @* begin
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

        // Rho+Pi combined step
        // Pi permutation: A'[x,y] = A[x + 3*y (mod 5), x (mod 5)]
        // Rho rotation: Apply offset before storing to B
        for (y = 0; y < 5; y = y + 1) begin
            for (x = 0; x < 5; x = x + 1) begin
                // Source position after Pi: (x + 3*y mod 5, x mod 5)
                // x mod 5 = x since x in [0,4]
                src_x = (x + 3 * y) % 5;
                src_y = x;
                src_idx = src_x + (5 * src_y);
                // Apply Rho rotation to source lane
                b[x + (5 * y)] = rotl64(a[src_idx], rho_offset(src_idx));
            end
        end

        for (y = 0; y < 5; y = y + 1) begin
            for (x = 0; x < 5; x = x + 1) begin
                a[x + (5 * y)] = b[x + (5 * y)] ^ ((~b[((x + 1) % 5) + (5 * y)]) & b[((x + 2) % 5) + (5 * y)]);
            end
        end

        a[0] = a[0] ^ round_constant(round_idx);

        for (i = 0; i < 25; i = i + 1) begin
            state_out[(i * 64) +: 64] = a[i];
        end
    end

endmodule