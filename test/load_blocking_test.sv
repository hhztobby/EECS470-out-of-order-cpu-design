`timescale 1ns/1ps
`include "sys_defs.svh"

module load_station_test;

	// Testbench signals
	logic clock, reset;
	logic src_vld, arbit_gnt_in, cache_hit_in;
	DATA opa, opb;
	B_IDX mis_branch_idx;
	BR_RES_STATE mis_res_state;
	MEM_BLOCK data_fwd_in, cache_data_in;
	LOAD_MASK mask_fwd_in;
	TAG tag_in;
  BMASK bmask_in;
	MEM_SIZE mem_size_in;

	// Outputs
	logic src_rdy, valid_fwd;
	ADDR addr_fwd, Dmem_addr;
	SQ_IDX sq_pos_fwd,st_pos_in;
  MEM_SIZE Dmem_size,mem_size_fwd;
	TAG arbit_tag_out;
	CDB_REG_PACKET cdb_reg_packet;
  //debug
  LOAD_STATION_ENTRY lu_dbg;


	// Instantiate the DUT (Device Under Test)
	load_station dut (
		.clock(clock),
		.reset(reset),
		.src_vld(src_vld),
		.opa(opa),
		.opb(opb),
		.tag_in(tag_in),
		.bmask_in(bmask_in),
		.st_pos_in(st_pos_in),
		.mem_size_in(mem_size_in),
		.src_rdy(src_rdy),
		.valid_fwd(valid_fwd),
		.addr_fwd(addr_fwd),
		.sq_pos_fwd(sq_pos_fwd),
		.mem_size_fwd(mem_size_fwd),
		.data_fwd_in(data_fwd_in),
		.mask_fwd_in(mask_fwd_in),
		.Dmem_addr(Dmem_addr),
		.Dmem_size(Dmem_size),
		.cache_hit_in(cache_hit_in),
		.cache_data_in(cache_data_in),
		.arbit_tag_out(arbit_tag_out),
		.arbit_gnt_in(arbit_gnt_in),
		.cdb_reg_packet(cdb_reg_packet),
    .mis_res_state(mis_res_state),
    .mis_branch_idx(mis_branch_idx),
    .lu_dbg(lu_dbg)
	);
  // Clock generation
  always #5 clock = ~clock;
  string ttype[]={"BYTE","HALF","WORD","DOUBLE"};
  string sstate[]={"IDLE","WAIT_FWD","WAIT_CACHE","WAIT_ARBIT","COMPLETE"};
  // Test sequence
  initial begin
    // Initialize signals
    $dumpfile("station.vcd");
    $dumpvars(0,load_station_test);
    initialize_inputs();
    clock = 0;
    reset = 1;
    @(posedge clock);
    @(negedge clock);
    reset = 0;

    // Test case 1: Basic operation
    $display("### Test case 1:s1 idle go through all state");
    initialize_inputs();
    src_vld = 1;
    opa = 32'h00000000;
    opb = 32'h00000004;
    st_pos_in = 3;
    bmask_in=4'b1111;


    mem_size_in = WORD;
    tag_in = 5'd6;
    
    @(negedge clock);
    initialize_inputs();
    src_vld = 1;
    opa = 32'h00000000;
    opb = 32'h00000004;
    st_pos_in = 3;
    bmask_in=4'b1111;
    mis_res_state = BR_RES_MIS;
    mis_branch_idx = 4'b0001;
    @(negedge clock);
    mis_res_state = BR_RES_INVALID;
    mis_branch_idx = 4'b0001;
    @(negedge clock);

    // // state 2: wait for fwd
    // $display("### Test case 1:s2 wait for fwd");
    // initialize_inputs();
    // src_vld = 1;
    // data_fwd_in = 64'h0706_0504_0302_010a;
    // mask_fwd_in = 8'b11100000;
    // cache_hit_in = 0;
    
    // @(negedge clock);

    // // state 4: wait for arbit
    // $display("### Test case 1:s4 wait for arbit");
    // initialize_inputs();
    // // src_vld = 1;
    // cache_hit_in = 1;
    // cache_data_in = 64'h7060_5040_3020_10a0;
    // @(negedge clock);
    // arbit_gnt_in = 1;
    // @(negedge clock);
    // // @(negedge clock);

    $finish;


    
  end

  always @(posedge clock) begin
      print_wires();
      #1;
      print_reg();
  end


// write a task to initialize all input signals
task initialize_inputs();
    src_vld = 0;
    arbit_gnt_in = 0;
    cache_hit_in = 0;
    opa = '0;
    opb = '0;
    bmask_in = '0;
    mis_branch_idx = 0;
    mis_res_state = BR_RES_INVALID;
    data_fwd_in = '0;
    cache_data_in = '0;
    mask_fwd_in = '0;
    tag_in = '0;
    mem_size_in = '0;
    st_pos_in = '0;
endtask
// write a task to beautifully print all the output signals and load station itself
task print_wires();
    $display("====================================================");
    $display("Time: %0t", $time);
    $display("all hit: %b", dut.fwd_all_hit);
    $display("To issue reg");
    $display("  src_rdy       : %b", src_rdy);
    $display("To SQ");
    $display("  valid_fwd     : %b", valid_fwd);
    $display("  addr_fwd      : %h", addr_fwd);
    $display("  sq_pos_fwd    : %h", sq_pos_fwd);
    $display("  mem_size_fwd  : %s", ttype[mem_size_fwd]);
    $display("To cache");
    $display("  Dmem_command  : %h", dut.Dmem_command);
    $display("  Dmem_addr     : %h", Dmem_addr);
    $display("  Dmem_size     : %s", ttype[Dmem_size]);
    $display("To arbit");
    $display("  arbit_tag_out : %h", arbit_tag_out);
    $display("To CDB reg");
    $display("  cdb_reg_packet: %h %d %b", cdb_reg_packet.result, cdb_reg_packet.dst_tag_out, cdb_reg_packet.valid_out);
    $display("-------------------------------------------");
endtask

// write a task to beautifully print reg
task print_reg();
    $display("Load station reg");
    $display("  current_state : %s", sstate[dut.current_state]);
    $display("  lu.valid      : %b", lu_dbg.valid);
    $display("  lu.tag        : %d", lu_dbg.tag);
    $display("  lu.addr       : %h", lu_dbg.addr);
    $display("  lu.data       : %h", lu_dbg.data);
    $display("  lu.load_mask  : %b", lu_dbg.load_mask);
    $display("  lu.bmask      : %b", lu_dbg.bmask);
    $display("  lu.sq_pos     : %h", lu_dbg.sq_pos);
    $display("  lu.mem_size   : %s \n\n", ttype[lu_dbg.mem_size]);

endtask

endmodule
