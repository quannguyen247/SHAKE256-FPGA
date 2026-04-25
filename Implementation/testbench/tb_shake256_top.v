`timescale 1ns / 1ps

module tb_shake256_top;

    localparam integer BLK_WIDTH = 32;
    localparam integer TIMEOUT_CYCLES = 1836; 
    localparam integer MAX_BUFFER = 1024; 

    reg clk, rst_n, start, absorb_block_valid, squeeze_data_ready;
    reg [7:0] msg_len_bytes;
    reg [BLK_WIDTH-1:0] num_input_blocks, num_output_blocks;
    reg [1087:0] absorb_block_data, msg_block_in;
    
    wire done, absorb_block_ready, squeeze_data_valid, need_block2;
    wire [1087:0] squeeze_data, pad_block0_out, pad_block1_out;

    reg [5455:0] vec_all [0:MAX_BUFFER-1]; 
    reg [1087:0] exp_outs [0:3]; 
    reg [639:0] line_buffer;            
    
    integer tv_count_actual, case_idx, error_count, report_fd, spec_fd, status, b; 
    reg timeout_flag, case_pass;

    shake256_sponge #(
        .BLOCK_WIDTH(BLK_WIDTH)
    ) u_dut (
        .clk(clk), .rst_n(rst_n),
        .absorb_valid(absorb_block_valid), .absorb_in(absorb_block_data), .absorb_ready(absorb_block_ready),
        .squeeze_ready(squeeze_data_ready), .squeeze_valid(squeeze_data_valid), .squeeze_out(squeeze_data),
        .start(start), .done(done),
        .input_blocks(num_input_blocks), .output_blocks(num_output_blocks)
    );

    shake256_pad_block u_pad (
        .msg_block_in(msg_block_in), .msg_len_bytes(msg_len_bytes),
        .pad_block0_out(pad_block0_out), .pad_block1_out(pad_block1_out),
        .need_block2(need_block2)
    );

    initial begin 
        clk = 1'b0; 
        forever #2.5 clk = ~clk; 
    end 

    task safe_wait(input integer mode); 
    begin   
        timeout_flag = 1'b0;
        fork : wait_block
            begin
                case(mode)
                    0: wait(absorb_block_ready == 1'b1);
                    1: wait(squeeze_data_valid == 1'b1);
                    2: wait(squeeze_data_valid == 1'b0);
                    3: wait(done == 1'b1);
                endcase
                disable wait_block;
            end
            begin
                repeat(TIMEOUT_CYCLES) @(posedge clk);
                timeout_flag = 1'b1;
                disable wait_block;
            end
        join
    end
    endtask

    task write_case_result(input integer idx, input integer passed);
    begin
        if (report_fd != 0) begin
            $fwrite(report_fd, "Case %0d - msg_len: %0d, blocks: %0d | %s\n", 
                    idx, vec_all[idx][7:0], vec_all[idx][15:8], 
                    passed ? "PASS" : "FAIL");
        end
    end
    endtask

    task run_one_case(input integer idx);
    begin : execute_case 
        @(negedge clk); #1; 
        rst_n = 1'b0;
        start = 1'b0; 
        absorb_block_valid = 1'b0;
        repeat(5) @(negedge clk); #1; 
        rst_n = 1'b1;
        repeat(2) @(negedge clk); #1; 
        case_pass = 1'b1;

        msg_len_bytes       = vec_all[idx][7:0];
        num_output_blocks   = vec_all[idx][15:8];
        msg_block_in        = vec_all[idx][1103:16];
        exp_outs[0]         = vec_all[idx][2191:1104];
        exp_outs[1]         = vec_all[idx][3279:2192];
        exp_outs[2]         = vec_all[idx][4367:3280];
        exp_outs[3]         = vec_all[idx][5455:4368];
        
        #1; 
        num_input_blocks = need_block2 ? 2 : 1;

        @(negedge clk); #1; start = 1'b1; 
        @(negedge clk); #1; start = 1'b0;

        for (b = 0; b <= need_block2; b = b + 1) begin
            safe_wait(0); 
            if (timeout_flag) begin 
                $display("[%0t] FAIL: Case %0d - Absorb Timeout", $time, idx);
                if (case_pass) begin 
                    error_count = error_count + 1; 
                    case_pass = 1'b0; 
                end
                write_case_result(idx, 0);
                disable execute_case; 
            end
            @(negedge clk); #1; 
            absorb_block_valid = 1'b1; 
            absorb_block_data = (b == 0) ? pad_block0_out : pad_block1_out;
            @(negedge clk); #1; 
            absorb_block_valid = 1'b0; 
        end

        for (b = 0; b < num_output_blocks; b = b + 1) begin
            safe_wait(1); 
            if (timeout_flag) begin 
                $display("[%0t] FAIL: Case %0d - Squeeze Timeout", $time, idx);
                if (case_pass) begin 
                    error_count = error_count + 1; 
                    case_pass = 1'b0; 
                end
                write_case_result(idx, 0);
                disable execute_case; 
            end
            
            if (squeeze_data !== exp_outs[b]) begin 
                $display("[%0t] FAIL: Case %0d - Block %0d Error", $time, idx, b);
                if (case_pass) begin 
                    error_count = error_count + 1; 
                    case_pass = 1'b0; 
                end
            end

            if (b < num_output_blocks - 1) safe_wait(2); 
        end

        safe_wait(3);
        if (timeout_flag) begin 
            $display("[%0t] FAIL: Case %0d - Done Timeout", $time, idx);
            if (case_pass) begin 
                error_count = error_count + 1; 
                case_pass = 1'b0; 
            end
            write_case_result(idx, 0);
            disable execute_case;
        end

        write_case_result(idx, case_pass);
        repeat(2) @(negedge clk); 
    end
    endtask

    initial begin
        error_count = 0; rst_n = 0; start = 0; absorb_block_valid = 0; 
        squeeze_data_ready = 1'b1;

        report_fd = $fopen("C:/Users/Quan/Desktop/SHAKE256-FPGA/Implementation/testbench/result.log", "w");
        spec_fd = $fopen("C:/Users/Quan/Desktop/SHAKE256-FPGA/Implementation/vectors/tv_spec.txt", "r");
        
        if (spec_fd == 0) begin 
            $display("ERROR: Cannot open tv_spec.txt"); 
            $finish; 
        end
        status = $fgets(line_buffer, spec_fd);
        status = $sscanf(line_buffer, "tv_count=%d", tv_count_actual);
        $fclose(spec_fd);

        if (tv_count_actual > MAX_BUFFER) begin 
            $display("ERROR: tv_count exceeds MAX_BUFFER"); 
            $finish; 
        end
        $readmemh("C:/Users/Quan/Desktop/SHAKE256-FPGA/Implementation/vectors/tv_all.mem", vec_all);

        #100;
        @(negedge clk); #1; 
        rst_n = 1'b1; 
        repeat(5) @(negedge clk);

        for (case_idx = 0; case_idx < tv_count_actual; case_idx = case_idx + 1) begin
            run_one_case(case_idx);
        end

        $display(">>> SHAKE256 PASSED: %0d/%0d CASES (%0d ERRORS)", 
            (tv_count_actual - error_count), tv_count_actual, error_count);
        
        if (report_fd != 0) $fclose(report_fd);
        #100; 
        
        $finish;
    end

endmodule