`timescale 1ns / 1ps
`include "sys_defs.svh"

module load_station_test;

	string ttype [] = {"BYTE", "HALF", "WORD", "DOUBLE"};
	string sstate[] = {"IDLE", "WFWD","WSEND", "WCACH", "ARBIT", "COMP"};

	// Declare signals for load_station
	logic clock, reset;
	BR_RES_STATE mis_res_state;
	B_IDX mis_branch_idx;
	DATA opa, opb;
	TAG dst_tag_in;
	BMASK bmask_in;
	logic src_vld;
	SQ_IDX st_pos_in;
	MEM_SIZE mem_size_in;
	logic src_rdy;
	ADDR addr_fwd;
	logic valid_fwd;
	SQ_IDX st_pos_fwd;
	MEM_BLOCK data_fwd_in;
	LOAD_MASK mask_fwd_in;
	ADDR [3:0] cache_addr_out;
	logic [3:0] cache_valid_out;
	MEM_SIZE [3:0] cache_size_out;
	logic [3:0] cache_sent;
	DCACHE_LSQ_STATE cache_state;
	CACHE_TAG cache_alloc_tag;
	MEM_BLOCK cache_hit_data;
	logic cache_broad_valid;
	CACHE_TAG cache_broad_tag;
	MEM_BLOCK cache_broad_data;
	TAG [3:0] arbit_tag_out;
	logic [3:0] arbit_gnt;
	CDB_REG_PACKET [3:0] cdb_reg_packet;
	LOAD_STATION_ENTRY [3:0] dbg_lq;

	// Instantiate load_station
	load_station #(.LOAD_STATION_SIZE(4)) uut (
		.clock(clock),
		.reset(reset),
		.mis_res_state(mis_res_state),
		.mis_branch_idx(mis_branch_idx),
		.opa(opa),
		.opb(opb),
		.dst_tag_in(dst_tag_in),
		.bmask_in(bmask_in),
		.src_vld(src_vld),
		.st_pos_in(st_pos_in),
		.mem_size_in(mem_size_in),
		.src_rdy(src_rdy),
		.addr_fwd(addr_fwd),
		.valid_fwd(valid_fwd),
		.st_pos_fwd(st_pos_fwd),
		.data_fwd_in(data_fwd_in),
		.mask_fwd_in(mask_fwd_in),
		.cache_addr_out(cache_addr_out),
		.cache_valid_out(cache_valid_out),
		.cache_size_out(cache_size_out),
		.cache_sent(cache_sent),
		.cache_state(cache_state),
		.cache_alloc_tag(cache_alloc_tag),
		.cache_hit_data(cache_hit_data),
		.cache_broad_valid(cache_broad_valid),
		.cache_broad_tag(cache_broad_tag),
		.cache_broad_data(cache_broad_data),
		.arbit_tag_out(arbit_tag_out),
		.arbit_gnt(arbit_gnt),
		.cdb_reg_packet(cdb_reg_packet),
		.dbg_lq(dbg_lq)
	);

	// Clock generation
	always #5 clock = ~clock;
	always @(posedge clock) begin
		print_wires();
		#1;
		print_reg();
	end

	// Initialize all input signals
	task initialize_inputs();
		reset = 0;
		mis_res_state = '0;
		mis_branch_idx = '0;
		opa = '0;
		opb = '0;
		dst_tag_in = '0;
		bmask_in = '0;
		src_vld = 0;
		st_pos_in = '0;
		mem_size_in = '0;
		data_fwd_in = '0;
		mask_fwd_in = '0;
		cache_sent = '0;
		cache_state = '0;
		cache_alloc_tag = '0;
		cache_hit_data = '0;
		cache_broad_valid = 0;
		cache_broad_tag = '0;
		cache_broad_data = '0;
		arbit_gnt = '0;
	endtask

	// Print all output signals and load station state
	task print_wires();
		$display("====================================================");
		$display("Time: %0t", $time);
		$display("src_rdy: %b, addr_fwd: %h, valid_fwd: %b, st_pos_fwd: %h", src_rdy, addr_fwd, valid_fwd, st_pos_fwd);
		for (int i = 0; i < 4; i++) begin
			$display("cache_valid_out[%0d]: %b, cache_addr_out[%0d]: %h, cache_size_out[%0d]: %h", 
				i, cache_valid_out[i], i, cache_addr_out[i], i, cache_size_out[i]);
		end
		for (int i = 0; i < 4; i++) begin
			$display("arbit_tag_out[%0d]: %h", i, arbit_tag_out[i]);
		end
		for (int i = 0; i < 4; i++) begin
			$display("cdb_reg_packet[%0d]: %h  %d  %d", 
				i, cdb_reg_packet[i].result, cdb_reg_packet[i].dst_tag_out, cdb_reg_packet[i].dst_bmask);
		end
	endtask
	// Print the internal state of the load station
	task print_reg();
		$display("Load station internal state:");
		$display("Entry\t| State\t| Addr\t\t| Lmsk\t\t| Bmask\t| S_Pos\t| size\t| DATA");
		$display("---------------------------------------------------------------");
		for (int i = 0; i < 4; i++) begin
			$display("%0d\t| %s\t| %h\t| %b\t| %b\t| %d\t| %s\t| %h", 
				i, sstate[dbg_lq[i].state], dbg_lq[i].addr,dbg_lq[i].load_mask, dbg_lq[i].bmask, dbg_lq[i].st_pos, ttype[dbg_lq[i].mem_size], dbg_lq[i].data);
		end
		// $display("---------------------------------------------------------------");
	endtask

	// Testbench logic
	initial begin
		clock = 0;
		reset = 1;
		@(posedge clock);
		@(negedge clock);
		reset = 0;

		$display("### Test case 1:s1 idle go through all state");
    	initialize_inputs();
    	src_vld = 1;
    	opa = 32'h00000001;
    	opb = 32'h00000003;
		dst_tag_in = 12;
    	st_pos_in = 1;
    	bmask_in=4'b1111;
		mem_size_in = WORD;
		
		


		@(negedge clock);
		initialize_inputs();
		// idle input
		// src_vld = 1;
    	// opa = 32'h00000000;
    	// opb = 32'h00001114;
		// dst_tag_in = 15;
    	// st_pos_in = 2;
    	// bmask_in=4'b1110;
		// mem_size_in = WORD;
		
		// fwd input
		data_fwd_in = 64'h1234567890abcdef;
		mask_fwd_in = 8'b11100001;
		cache_sent = 4'b0000;
		cache_state = DCACHE_LSQ_HIT;
		cache_hit_data = 64'hfedcba0987654321;
		@(negedge clock);
		mis_res_state = BR_RES_MIS;
		mis_branch_idx = 4'b0001;
		initialize_inputs();
		cache_sent= 4'b1000;
		cache_state = DCACHE_LSQ_PENDING;
		
		cache_alloc_tag = 1;
		@(negedge clock);

		initialize_inputs();
		cache_broad_valid = 1;
		cache_broad_tag = 1;
		cache_broad_data = 64'hfedcba0987654321;
		@(negedge clock);

		initialize_inputs();
		// ARBIT INPUT
		arbit_gnt = 4'b1001;
		mis_res_state = BR_RES_MIS;
		mis_branch_idx = 4'b0001;
		@(negedge clock);
		initialize_inputs();
		
		
		@(negedge clock);
		initialize_inputs();
		
		// @(negedge clock);
		
		
		#1;
		$finish;
	end

endmodule
