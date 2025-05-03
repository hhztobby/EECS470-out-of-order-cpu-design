`timescale 1ns/1ps
`include "sys_defs.svh"
// `include "cpuBusIF.svh"

module sq_test;
	logic clock, reset;
	logic st_valid, retire_first;

	// 与 sq.sv 相匹配的端口信号
	logic [1:0]               is_store, is_branch;
	logic [1:0][$clog2(`BR_STK_SZ)-1:0] d_branch_idx;
	logic [3:0]               can_issue;
	BR_RES_STATE                     mis_res_state;
	logic [$clog2(`BR_STK_SZ)-1:0] mis_branch_idx;

	MEM_BLOCK  st_data;
	ADDR  st_addr;
	MEM_SIZE  st_size;
	logic [1:0]   st_pos;

	ADDR  load_addr;
	logic         load_valid;
	MEM_SIZE   load_size;
	logic [1:0]   load_pos;
	MEM_BLOCK  load_data_return;
	LOAD_MASK  load_data_return_mask;

	logic [2:0]   sq_available_cnt; // SQ_SZ=4 => clog2(4+1)=3
	logic [1:0]   sq_tail_for_disp;

	MEM_COMMAND   Dmem_command;
	MEM_SIZE      Dmem_size;
	ADDR          Dmem_addr;
	MEM_BLOCK     Dmem_store_data;
	string ttype[]={"BYTE","HALF","WORD","DOUBLE"};

	sq #(
		.SQ_SZ(4)
	) sq_inst (
		.clock(clock),
		.reset(reset),
		.sq_available_cnt(sq_available_cnt),
		.sq_tail_for_disp(sq_tail_for_disp),
		.is_store(is_store),
		.is_branch(is_branch),
		.d_branch_idx(d_branch_idx),
		.can_issue(can_issue),
		.st_valid(st_valid),
		.st_data(st_data),
		.st_addr(st_addr),
		.st_size(st_size),
		.st_pos(st_pos),
		.mis_res_state(mis_res_state),
		.mis_branch_idx(mis_branch_idx),
		.load_addr(load_addr),
		.load_valid(load_valid),
		.load_size(load_size),
		.load_pos(load_pos),
		.load_data_return(load_data_return),
		.load_data_return_mask(load_data_return_mask),
		.retire_first(retire_first),
		.Dmem_command(Dmem_command),
		.Dmem_size(Dmem_size),
		.Dmem_addr(Dmem_addr),
		.Dmem_store_data(Dmem_store_data)
	);

	always #5 clock = ~clock;
	initial begin
		clock = 0;
		@(negedge clock);
		reset = 1;
		init_inputs();
		@(negedge clock);
		@(negedge clock);
		reset=0;
		/*
		// Test 1: blank, see dispatch output
		$display("!!!!!!!!!!!!Test 1: blank");
		init_inputs();
		@(negedge clock);
		*/
		// Test 2: store
		$display("***Test 2: dispatch 4 stores");
		init_inputs();
		is_store=2'b11;
		@(negedge clock);
		init_inputs();
		is_store=2'b10;
		@(negedge clock);
		
		$display("!!!Test 2.11: issue 1 store");
		init_inputs();
		st_valid = 1;
		st_addr = 64'h0000_0000_0001_0004;
		st_data = 64'h0001_0001_0E01_0E11;
		st_size = WORD;
		st_pos = 2'b00;
		@(negedge clock);

		$display("!!!Test 2.12: issue 2 store");
		init_inputs();
		st_valid = 1;
		st_addr = 64'h0000_0000_0001_0005;
		st_data = 64'h0202_0202_0202_02E2;
		st_size = BYTE;
		st_pos = 2'b01;
		@(negedge clock);
		$display("!!!Test 2.13: issue 3 store");
		init_inputs();
		st_valid = 1;
		st_addr = 64'h0000_0000_0001_0006;
		st_data = 64'h0003_0003_0003_0AC3;
		st_size = HALF;
		st_pos = 2'b10;
		@(negedge clock);

		$display("!!!Test 3.1: forwarding");
		init_inputs();
		load_valid = 1;
		load_addr = 64'h0000_0000_0001_0004;
		load_size = WORD;
		load_pos = 2'b00;
		@(negedge clock);

		$display("!!!Test 3.2: forwarding");
		init_inputs();
		load_valid = 1;
		load_addr = 64'h0000_0000_0001_0004;
		load_size = WORD;
		load_pos = 2'b01;
		@(negedge clock);
		$display("!!!Test 3.3: forwarding");
		init_inputs();
		load_valid = 1;
		load_addr = 64'h0000_0000_0001_0004;
		load_size = WORD;
		load_pos = 2'b10;
		@(negedge clock);

		// Test 4: retire
		$display("***Test 4: retire 1 stores");
		init_inputs();
		retire_first = 1;
		@(negedge clock);


		$finish;
	end

	always @(posedge clock) begin
		if(!reset)begin
			print_wire();
			#1;
			print_reg();
		end
	end

	task init_inputs();
		st_valid = 0;
		retire_first = 0;
		is_store = 0;
		is_branch = 0;
		d_branch_idx = 0;
		mis_res_state = BR_RES_INVALID;
		mis_branch_idx = 0;
		st_data = 64'hDEAD_BEEF_DEAD_BEEF;
		st_addr = 64'h0000_0000_0000_0004;
		st_size = BYTE;
		st_pos = 2'b00;
		load_addr = 64'h0000_0000_0000_0004;
		load_valid = 0;
		load_size = HALF;
		load_pos = 2'b00;
	endtask

	task print_wire();
		$display("\n####   Time=%0t       ###############################", $time);
		// display the output to dispatch
		$display("To dispatch:");
		$display("d_available cnt=%d ", sq_available_cnt);
		$display("d_tail_for_disp=%d ", sq_tail_for_disp);
		$display("------------------");

		$display("To memory:\nDmem_command=%0s \nDmem_size=%0s \nDmem_addr=%h \nDmem_store_data=%h\n-----------------\n",
			Dmem_command,
			ttype[Dmem_size],
			Dmem_addr,
			Dmem_store_data
		);
		$display("To load station:\nload_input_addr=%h \nload_data_return=%h \nload_data_return_mask=%b\n-------------\n", 
				load_addr,
				load_data_return, 
				load_data_return_mask);
		$display("To issue:\ncan_issue=%b\n--------------\n",can_issue);
	endtask

	task print_reg();
		$display("----------------------------------------------------------------------");
		$display("| Index\t| cal\t| Data\t\t\t| Addr\t\t| Size\t| h/t |");
		$display("----------------------------------------------------------------------");
		for (int i = 0; i < sq_inst.SQ_SZ; i++) begin
			$display("  %0d\t  %b\t  %h\t  %h\t  %s\t  %s\t",
				i,
				sq_inst.sq[i].addr_calculated,
				sq_inst.sq[i].data_store,
				sq_inst.sq[i].addr,
				ttype[sq_inst.sq[i].size],
				(i == sq_inst.head&&i == sq_inst.tail)?"ht":(i == sq_inst.head) ? "h" : (i == sq_inst.tail) ? "t" : " "
			);
		end
		$display("----------------------------------------------------------------------");
		// display the count
		$display("count=%0d", sq_inst.count);
		
	endtask
endmodule
