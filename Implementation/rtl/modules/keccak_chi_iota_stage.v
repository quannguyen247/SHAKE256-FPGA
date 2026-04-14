`timescale 1ns / 1ps

`include "../utils/keccak_defs.vh"

(* keep_hierarchy = "yes" *)
module keccak_chi_iota_stage (
    state_in,
    round_const,
    state_out
);
    input [`KECCAK_STATE_WIDTH-1:0] state_in;
    input [63:0] round_const;
    output [`KECCAK_STATE_WIDTH-1:0] state_out;

    reg [`KECCAK_STATE_WIDTH-1:0] state_out_reg;

    reg [63:0] a [0:24];
    reg [63:0] b [0:24];
    integer x;
    integer y;
    integer i;

    always @(*) begin
        state_out_reg = {`KECCAK_STATE_WIDTH{1'b0}};

        for (i = 0; i < 25; i = i + 1) begin
            b[i] = state_in[(i * 64) +: 64];
            a[i] = 64'h0;
        end

        for (y = 0; y < 5; y = y + 1) begin
            for (x = 0; x < 5; x = x + 1) begin
                a[x + (5 * y)] = b[x + (5 * y)] ^ ((~b[((x + 1) % 5) + (5 * y)]) & b[((x + 2) % 5) + (5 * y)]);
            end
        end

        a[0] = a[0] ^ round_const;

        for (i = 0; i < 25; i = i + 1) begin
            state_out_reg[(i * 64) +: 64] = a[i];
        end
    end

    assign state_out = state_out_reg;

endmodule
