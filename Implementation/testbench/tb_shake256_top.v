`timescale 1ns / 1ps

`include "../rtl/utils/keccak_defs.vh"

`ifndef TV_COUNT
`define TV_COUNT 256
`endif

// Top-level SHAKE256 vector testbench.
// - Reads deterministic vectors from vectors via readmemh.
// - Writes exactly one human-readable report file with PASS/FAIL per message.

module tb_shake256_top;

	localparam integer TV_COUNT = `TV_COUNT;

	reg clk;
	reg rst_n;

	reg start;
	reg absorb_block_valid;
	reg [1087:0] absorb_block_data;
	wire absorb_block_ready;
	reg squeeze_data_ready;
	reg [1087:0] msg_block_in;
	reg [7:0] msg_len_bytes;
	reg [7:0] num_output_blocks;
	reg [15:0] num_input_blocks;
	reg [15:0] num_output_blocks_16;

	wire done;
	wire squeeze_data_valid;
	wire [1087:0] squeeze_data;
	wire [1087:0] pad_block0_out;
	wire [1087:0] pad_block1_out;
	wire needs_second_block;

	reg [7:0] vec_msg_len [0:TV_COUNT-1];
	reg [7:0] vec_num_out_blocks [0:TV_COUNT-1];
	reg [1087:0] vec_msg_block [0:TV_COUNT-1];
	reg [1087:0] vec_exp_out0 [0:TV_COUNT-1];
	reg [1087:0] vec_exp_out1 [0:TV_COUNT-1];

	reg [1087:0] obs_out0;
	reg [1087:0] obs_out1;

	integer case_idx;
	integer byte_idx;
	integer error_count;
	integer timeout_count;
	integer report_fd;
	integer ok;
	reg case_pass;

	reg [8*512-1:0] report_path;
	reg [8*512-1:0] tv_msg_len_path;
	reg [8*512-1:0] tv_num_out_blocks_path;
	reg [8*512-1:0] tv_msg_block_path;
	reg [8*512-1:0] tv_exp_out0_path;
	reg [8*512-1:0] tv_exp_out1_path;

	shake256_sponge u_dut (
		.clk(clk),
		.rst_n(rst_n),
		.absorb_block_valid(absorb_block_valid),
		.absorb_block_data(absorb_block_data),
		.absorb_block_ready(absorb_block_ready),
		.squeeze_data_valid(squeeze_data_valid),
		.squeeze_data(squeeze_data),
		.squeeze_data_ready(squeeze_data_ready),
		.start(start),
		.done(done),
		.num_input_blocks(num_input_blocks),
		.num_output_blocks(num_output_blocks_16)
	);

	shake256_pad_block u_pad (
		.msg_block_in(msg_block_in),
		.msg_len_bytes(msg_len_bytes),
		.pad_block0_out(pad_block0_out),
		.pad_block1_out(pad_block1_out),
		.needs_second_block(needs_second_block)
	);

	initial begin
		clk = 1'b0;
		forever #5 clk = ~clk;
	end

	task wait_for_squeeze_valid;
		output integer found;
		begin
			timeout_count = 0;
			found = 0;
			while ((squeeze_data_valid !== 1'b1) && (timeout_count < 12000)) begin
				@(negedge clk);
				timeout_count = timeout_count + 1;
			end
			if (squeeze_data_valid === 1'b1)
				found = 1;
		end
	endtask

	task wait_for_squeeze_drop;
		output integer dropped;
		begin
			timeout_count = 0;
			dropped = 0;
			while ((squeeze_data_valid === 1'b1) && (timeout_count < 12000)) begin
				@(negedge clk);
				timeout_count = timeout_count + 1;
			end
			if (squeeze_data_valid !== 1'b1)
				dropped = 1;
		end
	endtask

	task wait_for_done;
		output integer found;
		begin
			timeout_count = 0;
			found = 0;
			while ((done !== 1'b1) && (timeout_count < 12000)) begin
				@(negedge clk);
				timeout_count = timeout_count + 1;
			end
			if (done === 1'b1)
				found = 1;
		end
	endtask

	task send_absorb_block;
		input [1087:0] block_data;
		begin
			timeout_count = 0;
			while ((absorb_block_ready !== 1'b1) && (timeout_count < 12000)) begin
				@(negedge clk);
				timeout_count = timeout_count + 1;
			end

			if (absorb_block_ready !== 1'b1) begin
				$display("ERROR: absorb_block_ready timeout");
				case_pass = 1'b0;
				error_count = error_count + 1;
			end else begin
				@(negedge clk);
				absorb_block_data = block_data;
				absorb_block_valid = 1'b1;
				@(negedge clk);
				absorb_block_valid = 1'b0;
				absorb_block_data = 1088'd0;
			end
		end
	endtask

	task write_case_result;
		input integer idx;
		input integer passed;
		begin
			$fwrite(report_fd, "msg: ");
			if (vec_msg_len[idx] == 8'd0) begin
				$fwrite(report_fd, "<empty>");
			end else begin
				for (byte_idx = 0; byte_idx < vec_msg_len[idx]; byte_idx = byte_idx + 1) begin
					$fwrite(report_fd, "%02x", vec_msg_block[idx][(8 * byte_idx) +: 8]);
				end
			end

			$fwrite(report_fd, "\nmsg_length: %0d\n", vec_msg_len[idx]);
			if (passed)
				$fwrite(report_fd, "result: PASS\n\n");
			else
				$fwrite(report_fd, "result: FAIL\n\n");
		end
	endtask

	task run_one_case;
		input integer idx;
		begin
			case_pass = 1'b1;
			obs_out0 = 1088'd0;
			obs_out1 = 1088'd0;

			@(negedge clk);
			msg_block_in = vec_msg_block[idx];
			msg_len_bytes = vec_msg_len[idx];
			num_output_blocks = vec_num_out_blocks[idx];
			#1;
			num_input_blocks = needs_second_block ? 16'd2 : 16'd1;
			num_output_blocks_16 = {8'd0, num_output_blocks};

			start = 1'b1;
			@(negedge clk);
			start = 1'b0;

			send_absorb_block(pad_block0_out);
			if (needs_second_block)
				send_absorb_block(pad_block1_out);

			wait_for_squeeze_valid(ok);
			if (!ok) begin
				$display("ERROR: case %0d first squeeze timeout", idx);
				case_pass = 1'b0;
				error_count = error_count + 1;
			end else begin
				obs_out0 = squeeze_data;
				if (obs_out0 !== vec_exp_out0[idx]) begin
					$display("ERROR: case %0d block0 mismatch", idx);
					case_pass = 1'b0;
					error_count = error_count + 1;
				end
			end

			if (vec_num_out_blocks[idx] == 8'd2) begin
				wait_for_squeeze_drop(ok);
				if (!ok) begin
					$display("ERROR: case %0d squeeze_data_valid did not drop", idx);
					case_pass = 1'b0;
					error_count = error_count + 1;
				end

				wait_for_squeeze_valid(ok);
				if (!ok) begin
					$display("ERROR: case %0d second squeeze timeout", idx);
					case_pass = 1'b0;
					error_count = error_count + 1;
				end else begin
					obs_out1 = squeeze_data;
					if (obs_out1 !== vec_exp_out1[idx]) begin
						$display("ERROR: case %0d block1 mismatch", idx);
						case_pass = 1'b0;
						error_count = error_count + 1;
					end
				end
			end

			wait_for_done(ok);
			if (!ok) begin
				$display("ERROR: case %0d done timeout", idx);
				case_pass = 1'b0;
				error_count = error_count + 1;
			end

			write_case_result(idx, case_pass);
			repeat (2) @(negedge clk);
		end
	endtask

	initial begin
		error_count = 0;

		rst_n = 1'b0;
		start = 1'b0;
		absorb_block_valid = 1'b0;
		absorb_block_data = 1088'd0;
		squeeze_data_ready = 1'b1;
		msg_block_in = 1088'd0;
		msg_len_bytes = 8'd0;
		num_output_blocks = 8'd0;
		num_input_blocks = 16'd0;
		num_output_blocks_16 = 16'd0;

		if (!$value$plusargs("RESULT_FILE=%s", report_path))
			report_path = "../../../../testbench/tb_shake256_top_results.txt";

		report_fd = $fopen(report_path, "w");
		if (report_fd == 0) begin
			$display("ERROR: Cannot open report file %0s", report_path);
			$finish;
		end

		if (!$value$plusargs("TV_MSG_LEN_FILE=%s", tv_msg_len_path))
			tv_msg_len_path = "../../../../vectors/tv_msg_len.mem";
		if (!$value$plusargs("TV_NUM_OUT_BLOCKS_FILE=%s", tv_num_out_blocks_path))
			tv_num_out_blocks_path = "../../../../vectors/tv_num_out_blocks.mem";
		if (!$value$plusargs("TV_MSG_BLOCK_FILE=%s", tv_msg_block_path))
			tv_msg_block_path = "../../../../vectors/tv_msg_block.mem";
		if (!$value$plusargs("TV_EXP_OUT0_FILE=%s", tv_exp_out0_path))
			tv_exp_out0_path = "../../../../vectors/tv_kat_expected_block0.mem";
		if (!$value$plusargs("TV_EXP_OUT1_FILE=%s", tv_exp_out1_path))
			tv_exp_out1_path = "../../../../vectors/tv_kat_expected_block1.mem";

		$display("INFO: report file = %0s", report_path);
		$display("INFO: vector file (len) = %0s", tv_msg_len_path);

		$readmemh(tv_msg_len_path, vec_msg_len);
		$readmemh(tv_num_out_blocks_path, vec_num_out_blocks);
		$readmemh(tv_msg_block_path, vec_msg_block);
		$readmemh(tv_exp_out0_path, vec_exp_out0);
		$readmemh(tv_exp_out1_path, vec_exp_out1);

		repeat (3) @(negedge clk);
		rst_n = 1'b1;
		repeat (2) @(negedge clk);

		$display("=== SHAKE256 TOP Vector Test ===");
		$display("Vector count: %0d", TV_COUNT);

		for (case_idx = 0; case_idx < TV_COUNT; case_idx = case_idx + 1) begin
			if ((case_idx % 50) == 0)
				$display("INFO: running case %0d/%0d", case_idx + 1, TV_COUNT);
			run_one_case(case_idx);
		end

		$fclose(report_fd);

		if (error_count == 0) begin
			$display("=== SHAKE256 TOP FULL-COVERAGE PASS (%0d cases) ===", TV_COUNT);
		end else begin
			$display("=== SHAKE256 TOP FULL-COVERAGE FAIL: %0d error(s) over %0d cases ===", error_count, TV_COUNT);
		end
		$display("INFO: report written to %0s", report_path);

		$finish;
	end

endmodule
