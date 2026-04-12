`timescale 1ns / 1ps

`include "../../rtl/utils/keccak_defs.vh"

// Testbench for SHAKE256 Keccak Permutation Pipeline
// Test: Simple permutation of empty state

module tb_shake256_pipeline;

    reg clk;
    reg rst_n;
    reg [`KECCAK_STATE_WIDTH-1:0] state_in;
    reg in_valid;
    wire [`KECCAK_STATE_WIDTH-1:0] state_out;
    wire out_valid;
    
    integer error_count;
    integer cycle_count;

    localparam [63:0] ZERO_STATE_LANE0_EXPECT = 64'hf1258f7940e1dde7;
    
    // Instantiate permutation pipeline
    keccak_permutation_pipeline u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .state_in(state_in),
        .out_valid(out_valid),
        .state_out(state_out)
    );
    
    // Clock generation
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;  // 10ns period
    end
    
    // Test sequence
    initial begin
        error_count = 0;
        cycle_count = 0;
        
        // Reset
        rst_n = 1'b0;
        in_valid = 1'b0;
        state_in = {`KECCAK_STATE_WIDTH{1'b0}};
        #20;
        
        rst_n = 1'b1;
        #20;
        
        // Test 1: Empty state (all zeros)
        $display("Test 1: Permute all-zero state");
        state_in = {`KECCAK_STATE_WIDTH{1'b0}};
        in_valid = 1'b1;
        #10;
        in_valid = 1'b0;
        
        // Wait for permutation to complete (iterative core: ~24 cycles)
        while (!out_valid && cycle_count < 100) begin
            cycle_count = cycle_count + 1;
            #10;
        end
        
        if (!out_valid) begin
            $display("ERROR: Permutation did not complete!");
            error_count = error_count + 1;
        end else begin
            $display("Permutation completed after %d cycles", cycle_count);
            $display("Output state[63:0] = 0x%016x", state_out[63:0]);

            if (state_out[63:0] !== ZERO_STATE_LANE0_EXPECT) begin
                $display("ERROR: Zero-state lane[0] mismatch. exp=0x%016x", ZERO_STATE_LANE0_EXPECT);
                error_count = error_count + 1;
            end

            if ((cycle_count < 20) || (cycle_count > 40)) begin
                $display("ERROR: Unexpected latency for iterative core (%0d cycles)", cycle_count);
                error_count = error_count + 1;
            end
        end
        
        #50;
        
        // Test 2: Non-zero state (test pattern)
        $display("\nTest 2: Permute test pattern state");
        cycle_count = 0;
        state_in = {`KECCAK_STATE_WIDTH{1'b1}};
        state_in[63:0] = 64'hdeadbeefcafebabe;
        in_valid = 1'b1;
        #10;
        in_valid = 1'b0;
        
        while (!out_valid && cycle_count < 100) begin
            cycle_count = cycle_count + 1;
            #10;
        end
        
        if (!out_valid) begin
            $display("ERROR: Permutation did not complete!");
            error_count = error_count + 1;
        end else begin
            $display("Permutation completed after %d cycles", cycle_count);
            $display("Output state[63:0] = 0x%016x", state_out[63:0]);
        end
        
        #50;
        
        // Summary
        if (error_count == 0) begin
            $display("\n=== All tests PASSED ===");
        end else begin
            $display("\n=== FAILED: %d errors ===", error_count);
        end
        
        $finish;
    end

endmodule
