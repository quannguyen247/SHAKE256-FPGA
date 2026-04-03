`timescale 1ns / 1ps

`include "../../rtl/utils/keccak_defs.vh"

// Testbench for Keccak Round Function
module tb_keccak_round;

    reg [`KECCAK_STATE_WIDTH-1:0] state_in;
    reg [4:0] round_idx;
    wire [`KECCAK_STATE_WIDTH-1:0] state_out;
    
    integer i;
    integer error_count;
    
    // Instantiate single Keccak round
    keccak_round u_dut (
        .state_in(state_in),
        .round_idx(round_idx),
        .state_out(state_out)
    );
    
    // Test sequence
    initial begin
        error_count = 0;
        
        $display("=== Keccak Round Testbench ===\n");
        
        // Test 1: All-zero state through round 0
        $display("Test 1: Zero state through round 0");
        state_in = {`KECCAK_STATE_WIDTH{1'b0}};
        round_idx = 5'd0;
        #10;
        $display("  Input:  state = 0x%032x", state_in[1087:0]);
        $display("  Output: state = 0x%032x", state_out[1087:0]);
        
        // After permutation of all-zero, should still be mostly zero except for RC
        // Lane[0] should be XORed with RC[0] = 0x0000000000000001
        if (state_out[63:0] !== 64'h0000000000000001) begin
            $display("  ERROR: Round 0 lane[0] != 0x0000000000000001");
            error_count = error_count + 1;
        end else begin
            $display("  PASS: Lane[0] = 0x%016x (RC[0])", state_out[63:0]);
        end
        
        #20;
        
        // Test 2: Test pattern state
        $display("\nTest 2: Test pattern state through round 0");
        state_in = {`KECCAK_STATE_WIDTH{1'b0}};
        state_in[63:0] = 64'hdeadbeefcafebabe;
        state_in[127:64] = 64'h0123456789abcdef;
        round_idx = 5'd0;
        #10;
        $display("  Input lane[0]:  0x%016x", state_in[63:0]);
        $display("  Input lane[1]:  0x%016x", state_in[127:64]);
        $display("  Output lane[0]: 0x%016x", state_out[63:0]);
        $display("  Output lane[1]: 0x%016x", state_out[127:64]);
        
        // State should change
        if (state_out[63:0] == state_in[63:0] && state_out[127:64] == state_in[127:64]) begin
            $display("  WARNING: Output unchanged (might be pass-through)");
        end else begin
            $display("  PASS: State changed as expected");
        end
        
        #20;
        
        // Test 3: Different round constants
        $display("\nTest 3: Round constant verification");
        state_in = {`KECCAK_STATE_WIDTH{1'b0}};
        for (i = 0; i < 24; i = i + 1) begin
            round_idx = i[4:0];
            #10;
            $display("  Round %2d: lane[0] = 0x%016x", i, state_out[63:0]);
        end
        
        #20;
        
        // Summary
        if (error_count == 0) begin
            $display("\n=== All tests PASSED ===\n");
        end else begin
            $display("\n=== FAILED: %d errors ===\n", error_count);
        end
        
        $finish;
    end

endmodule
