`ifndef CPU_BUS_IF_SVH
`define CPU_BUS_IF_SVH

`include "sys_defs.svh"

interface cpuBusIF #(
    localparam  int     DISPATCH_WIDTH_BITS = $clog2(`DISPATCH_WIDTH),
    localparam  int     BR_STK_IDX_BITS = $clog2(`BR_STK_SZ),
    localparam  int     FU_CNT = `NUM_FU_ALU + `NUM_FU_MULT + 3  // +3 for branch, load, and store
) (
    input       logic                               reset, clock,
    input  MEM_TAG                                  mem_transac_tag,
    input  MEM_BLOCK                                mem_read_data,
    input  MEM_TAG                                  mem_read_data_tag,
    output ADDR                                     cache_mem_addr,
    output MEM_COMMAND                              cache_mem_command,
    output MEM_BLOCK                                cache_mem_write_data,
    output      COMMIT_PACKET   [`RETIRE_WIDTH-1:0] retire_packets
);
// ------------------------ fetch signals ------------------------
    // ADDR                                                             PC;
    F_INST          [`FETCH_WIDTH-1:0]                               f_insts;
// ------------------------ branch signals ------------------------
    logic           [`DISPATCH_WIDTH-1:0] [BR_STK_IDX_BITS-1:0]      d_br_stk_idxs;
    logic           [`DISPATCH_WIDTH-1:0]                            d_br_stk_idx_valids;
    BR_RES_STATE                                                     br_res_state;
    B_IDX                                                            br_res_idx_bus;
    logic           [BR_STK_IDX_BITS-1:0]                            br_res_idx;
// ------------------------ dispatch signals --------------------
// dispatch in
    TAG_PLUS        [`DISPATCH_WIDTH-1:0]                            mt_src1_tagps;
    TAG_PLUS        [`DISPATCH_WIDTH-1:0]                            mt_src2_tagps;
    TAG             [`DISPATCH_WIDTH-1:0]                            mt_dst_tags;
    TAG             [`DISPATCH_WIDTH-1:0]                            fl_valid_tags;
    logic           [`DISPATCH_WIDTH-1:0]                            rob_spots;
    logic           [`DISPATCH_WIDTH-1:0]                            rs_spots;
// dispatch out
    logic           [`DISPATCH_WIDTH-1:0]                            f_accepts;
    // currently the same as f_accept
    // logic [`DISPATCH_WIDTH-1:0] d_valids;
    REG_IDX         [`DISPATCH_WIDTH-1:0]                            d_src1_regs;
    REG_IDX         [`DISPATCH_WIDTH-1:0]                            d_src2_regs;
    REG_IDX         [`DISPATCH_WIDTH-1:0]                            d_dst_regs;
    // TAG             [`DISPATCH_WIDTH-1:0]                            d_new_dst_tags;
    ROB_ENTRY       [`DISPATCH_WIDTH-1:0]                            d_rob_entries;
    D_RS_PACKET                                                      d_rs_packet;
// ------------------------ issue signals --------------------
    // rs -> cdb
    TAG             [`NUM_FU_ALU-1:0]                               alu_req_dst_tags;
    TAG                                                             branch_req_dst_tag;
    TAG                                                             store_req_dst_tag;
    // cdb -> rs
    logic           [`NUM_FU_ALU-1:0]                               alu_issue_gnts;
    logic                                                           branch_issue_gnt;
    logic                                                           store_issue_gnt;
    // sreg -> rs
    logic           [`NUM_FU_MULT-1:0]                               mult_issue_gnts;
    logic                                                            load_issue_gnt;
    ISS_INST_ALU    [`NUM_FU_ALU-1:0]                                alu_issue_insts;
    ISS_INST_MUL    [`NUM_FU_MULT-1:0]                               mult_issue_insts;
    ISS_INST_BR                                                      branch_issue_inst;
    ISS_INST_MEM                                                     load_issue_inst;
    ISS_INST_MEM                                                     store_issue_inst;
// ------------------------ issue data signals --------------------
    TAG             [FU_CNT-1:0]                                     issue_src1_read_tags;
    TAG             [FU_CNT-1:0]                                     issue_src2_read_tags;
    DATA            [FU_CNT-1:0]                                     prf_issue_src1_datas;
    DATA            [FU_CNT-1:0]                                     prf_issue_src2_datas;
    // the rest data are from etb_tags and etb_datas
// ------------------------ execute signals --------------------
    EX_INST_ARITH   [`NUM_FU_ALU-1:0]                                alu_ex_insts;
    // actually for mult, this is "issue"
    EX_INST_ARITH   [`NUM_FU_MULT-1:0]                              mult_ex_insts;
    EX_INST_BRANCH                                                  branch_ex_inst;
    EX_INST_MEM                                                     load_ex_inst;
    EX_INST_MEM                                                     st_ex_inst;
    logic           [`NUM_FU_MULT-1:0]                              mult_unit_readies;
    logic                                                           load_unit_ready;
// ------------------------ cdb signals ------------------------
    TAG             [`CDB_WIDTH-1:0]                                 etb_tags;
    BMASK           [`CDB_WIDTH-1:0]                                 etb_bmasks;
    DATA            [`CDB_WIDTH-1:0]                                 etb_datas;
    CDB_REG_PACKET  [`CDB_WIDTH-1:0]                                 cdb_reg_packets;
    ADDR                                                             cdb_branch_actual_pc;
    ADDR                                                             br_res_inst_pc;
    logic                                                            br_res_is_cond;
    logic                                                            br_res_is_taken;
// ------------------------ rob signals ------------------------
    // dispatch related are declared in dispatch signals
    // retire
    TAG             [`RETIRE_WIDTH-1:0]                              retire_old_tags;
    TAG             [`RETIRE_WIDTH-1:0]                              retire_new_dst_tags;
    DATA            [`RETIRE_WIDTH-1:0]                              retire_prf_datas;
// ------------------------ load store signals ----------------
    MEM_COMMAND                                                     lsq_dcache_req_command;
    // note: this address is NOT ALIGNED
    ADDR                                                            lsq_dcache_req_addr; 
    MEM_BLOCK                                                       lsq_dcache_write_data;
    MEM_SIZE                                                        lsq_dcache_req_data_size;
// ------------------------ cache signals ------------------------
    ADDR                                                            icache_mem_addr;
    MEM_COMMAND                                                     icache_mem_command;
    ADDR                                                            dcache_mem_addr;
    MEM_COMMAND                                                     dcache_mem_command;
    MEM_BLOCK                                                       dcache_mem_write_data;
    MEM_TAG                                                         transac_tag_icache;
    MEM_TAG                                                         transac_tag_dcache;
    logic           [`ICACHE_READ_PORTS-1:0]                        fetch_read_valids;
    ADDR            [`ICACHE_READ_PORTS-1:0]                        fetch_read_addrs;
    logic           [`ICACHE_READ_PORTS-1:0]                        icache_hits;
    MEM_BLOCK       [`ICACHE_READ_PORTS-1:0]                        icache_fetch_datas;
    // to lsq
    DCACHE_LSQ_STATE                                                dcache_lsq_req_state;
    // only valid when req state is pending
    logic           [$clog2(`MSHR_SIZE)-1:0]                        dcache_lsq_alloc_mshr_tag;
    // only valid when req state is got data
    MEM_BLOCK                                                       dcache_lsq_hit_data;
    logic          [`MSHR_SIZE-1:0]                                 dcache_lsq_broadcast_valid;
    logic           [$clog2(`MSHR_SIZE)-1:0]                        dcache_lsq_broadcast_mshr_tag;
    MEM_BLOCK                                                       dcache_lsq_broadcast_data;

// ------------------------ dcache arbiter signals ------------------------
    // load request
    ADDR            [`STATION_SIZE-1:0] 							load_arbit_addr;
    logic 			[`STATION_SIZE-1:0] 							load_arbit_valid;
    MEM_SIZE 		[`STATION_SIZE-1:0] 							load_arbit_size;
    logic 			[`STATION_SIZE-1:0] 							load_arbit_sent;
    DCACHE_LSQ_STATE 												load_arbit_state;
    CACHE_TAG 														load_arbit_alloc_tag;
    MEM_BLOCK 														load_arbit_hit_data;
    logic 															load_arbit_broad_valid;
    CACHE_TAG 														load_arbit_broad_tag;
    MEM_BLOCK 														load_arbit_broad_data;

	// store request
	ADDR 															store_arbit_addr;
	logic 															store_arbit_valid;
	MEM_SIZE 														store_arbit_size;
	MEM_BLOCK 														store_arbit_data;
	logic 															store_arbit_sent;
	DCACHE_LSQ_STATE 												store_arbit_state;

// ----------------------- store queue signals ----------------------------
    // with rob for retire
    logic 								                            retire_store;
    logic 								                            retire_store_success;
    // with load station: fwd
    ADDR    														fwd_addr;
    logic   														fwd_valid;
    SQ_IDX															fwd_pos;
    MEM_BLOCK 														fwd_data_return;
    LOAD_MASK														fwd_data_return_mask;
    // with store unit 
	logic 															st_sq_valid;
	MEM_BLOCK 														st_sq_data;
	ADDR 															st_sq_addr;
	MEM_SIZE 														st_sq_size;
	SQ_IDX															st_sq_pos;
	logic [$clog2(`SQ_SZ+1)-1:0]									sq_available_cnt;
	SQ_IDX															sq_tail_for_disp;
	logic [`DISPATCH_WIDTH-1:0]										is_store;
	logic [`SQ_SZ-1:0]												can_issue;

// ------------------------ system signal ports ------------------------
    modport sys_in(
        input reset,
        input clock
    );
// ------------------------ icache modports ------------------------
    modport icache(
    // memory inputs
        input  transac_tag_icache,
        input  mem_read_data,
        input  mem_read_data_tag,
    // fetch inputs
        input  fetch_read_valids,
        input  fetch_read_addrs,
    // request to memory
        output icache_mem_addr,
        output icache_mem_command,
    // feedback to fetch
        output icache_hits,
        output icache_fetch_datas
    );

    modport dcache(
        input  transac_tag_dcache,
        input  mem_read_data,
        input  mem_read_data_tag,
        output dcache_mem_addr,
        output dcache_mem_command,
        output dcache_mem_write_data,
        // lsq
        input  lsq_dcache_req_command,
        input  lsq_dcache_req_addr,
        input  lsq_dcache_write_data,
        input  lsq_dcache_req_data_size,
        // feedback to lsq
        output dcache_lsq_req_state,
        output dcache_lsq_alloc_mshr_tag,
        output dcache_lsq_hit_data,
        output dcache_lsq_broadcast_valid,
        output dcache_lsq_broadcast_mshr_tag,
        output dcache_lsq_broadcast_data
    );
// ------------------------ cache controller modports ------------------------
    modport cache_control(
        // cache requests
        // input  mem_read_data,
        // input  mem_read_data_tag, // allow cache to access these
        input  icache_mem_addr,
        input  icache_mem_command,
        input  dcache_mem_addr,
        input  dcache_mem_command,
        input  dcache_mem_write_data,
        // memory feedbacks
        input  mem_transac_tag,
        // feedback to cache
        output transac_tag_icache,
        output transac_tag_dcache,
        // input to memory
        output cache_mem_addr,
        output cache_mem_command,
        output cache_mem_write_data
    );
// ------------------------ fetch modports ------------------------
    modport fetch (
        // pc control
        input  br_res_state,
        input  cdb_branch_actual_pc,
        // branch prediction
        input  br_res_idx,
        input  br_res_idx_bus,
        input  br_res_inst_pc,
        input  br_res_is_cond,
        input  br_res_is_taken,
        // icache and fetch
        output fetch_read_valids,
        output fetch_read_addrs,
        input  icache_hits,
        input  icache_fetch_datas,
        // fetch and dispatch
        input  f_accepts,
        output f_insts
    );
// ------------------------ dispatch modports ------------------------
    modport d_branch_stk_out(
        output  d_br_stk_idxs,
        output  d_br_stk_idx_valids
    );
    modport d_branch_stk_in(
        input   d_br_stk_idxs,
        input   d_br_stk_idx_valids
    );
    // data needs to determine dispatch availabilities
    modport d_valid(
        input   f_insts,
        input   fl_valid_tags,
        input   rs_spots,
        input   rob_spots,
        output  f_accepts
    );
    modport d_dispatch(
        // map table
        input   mt_src1_tagps,
        input   mt_src2_tagps,
        input   mt_dst_tags,
        output  d_src1_regs,
        output  d_src2_regs,
        output  d_dst_regs,
        // output  d_new_dst_tags, // directly use fl_valid_tags + dispatch_valids
        // free list - none, all in d_valid_data
        // rs
        output  d_rs_packet,
        // rob
        output  d_rob_entries,
        // branch
        output  d_br_stk_idxs,
        output  d_br_stk_idx_valids
    );
// ------------------------ map table modports ------------------------
    modport mt_dispatch(
        input   d_src1_regs,
        input   d_src2_regs,
        input   d_dst_regs,
        output  mt_src1_tagps,
        output  mt_src2_tagps,
        output  mt_dst_tags,
        input   f_accepts,
        input   fl_valid_tags
    );
// ------------------------ free list modports ------------------------
    modport fl_dispatch(
        output  fl_valid_tags,
        input   f_accepts
    );
    modport fl_retire(
        input  retire_old_tags
    );
// ------------------------ rs modports ------------------------
    modport rs_dispatch(
        output  rs_spots,
        input   d_rs_packet
    );
    modport rs_issue_req(
        output  alu_req_dst_tags,
        output  branch_req_dst_tag,
        output  store_req_dst_tag,
        input   alu_issue_gnts,
        input   mult_issue_gnts,
        input   load_issue_gnt,
        input   store_issue_gnt,
        input   branch_issue_gnt
    );
    modport rs_issue_insts(
        output  alu_issue_insts,
        output  mult_issue_insts,
        output  branch_issue_inst,
        output  load_issue_inst,
        output  store_issue_inst
    );
// ------------------------ issue reg modports ------------------------
    modport sreg_issue(
        input   mult_unit_readies,
        output  mult_issue_gnts,
        input   load_unit_ready,
        output  load_issue_gnt,
        input   alu_issue_insts,
        input   mult_issue_insts,
        input   branch_issue_inst,
        input   load_issue_inst,
        input   store_issue_inst
    );
    // issue reg data access
    modport sreg_issue_data_read(
        output  issue_src1_read_tags,
        output  issue_src2_read_tags,
        input   prf_issue_src1_datas,
        input   prf_issue_src2_datas,
        output  etb_tags,
        input   etb_datas
    );
    modport sreg_execute(
        output   alu_ex_insts,
        output   mult_ex_insts,
        output   branch_ex_inst,
        output   load_ex_inst,
        output   st_ex_inst
        // MEM INSTRUCTIONS
    );
// ------------------------ fu modports ------------------------
    // fu receive instructions for execute
    modport fu_receive(
        input   alu_ex_insts,
        input   mult_ex_insts,
        input   branch_ex_inst,
        input   load_ex_inst,
        input   st_ex_inst
    );
// ------------------------ cdb modports ------------------------
    // mult issue req is an internal signal
    modport cdb_issue_select(
        input   alu_req_dst_tags,
        input   branch_req_dst_tag,
        input   store_req_dst_tag,
        // mult and load req are internal signals. 
        output  alu_issue_gnts,
        output  mult_unit_readies,
        output  branch_issue_gnt,
        output  load_unit_ready,
        output  store_issue_gnt
    );
    modport etb_out(
        output  etb_tags,
        output  etb_bmasks,
        output  etb_datas
    );
    modport etb_in(
        input   etb_tags,
        input   etb_bmasks,
        input   etb_datas
    );
    modport cdb_wb(
        output  cdb_reg_packets
    );
    modport cdb_branch_out(
        output  cdb_branch_actual_pc,
        output  br_res_state,
        output  br_res_idx,
        output  br_res_idx_bus,
        output  br_res_inst_pc,
        // output  br_res_predicted_taken,
        output  br_res_is_cond,
        output  br_res_is_taken
    );
    modport cdb_branch_in(
        input   br_res_state,
        input   br_res_idx,
        input   br_res_idx_bus
    );
// ------------------------ prf modports ------------------------
    /*modport prf_read(
        input   issue_src1_read_tags,
        input   issue_src2_read_tags,
        output  prf_issue_src1_datas,
        output  prf_issue_src2_datas,
        input   retire_prf_dst_tags,
        input   retire_prf_datas
    );
    modport prf_write(
        input   cdb_reg_packets
    );*/
// ------------------------ rob modports ------------------------
    modport rob_dispatch(
        output  rob_spots,
        input   d_rob_entries,
        input   f_accepts
    );
    modport rob_complete(
        input   etb_tags,
        input   etb_bmasks
    );
    modport rob_retire(
        output  retire_old_tags,
        output  retire_new_dst_tags,
        input   retire_prf_datas,
        output  retire_packets
    );
	modport rob_sq_retire(
		output  retire_store,
		input   retire_store_success
	);
	

// ---------------------- cache arbiter ports------------------
	modport arbit_dcache(
		output  lsq_dcache_req_command,
		output  lsq_dcache_req_addr,
		output  lsq_dcache_write_data,
		output  lsq_dcache_req_data_size,
		input dcache_lsq_req_state,
		input dcache_lsq_alloc_mshr_tag,
		input dcache_lsq_hit_data,
		input dcache_lsq_broadcast_valid,
		input dcache_lsq_broadcast_mshr_tag,
		input dcache_lsq_broadcast_data
	);

	modport arbit_load(
		input  load_arbit_addr,
		input  load_arbit_valid,
		input  load_arbit_size,
		output   load_arbit_sent,
		output   load_arbit_state,
		output   load_arbit_alloc_tag,
		output   load_arbit_hit_data,
		output   load_arbit_broad_valid,
		output   load_arbit_broad_tag,
		output   load_arbit_broad_data
	);

	modport arbit_store(
		input  store_arbit_addr,
		input  store_arbit_valid,
		input  store_arbit_size,
		input  store_arbit_data,
		output   store_arbit_sent,
		output   store_arbit_state
	);

// ------------------------ sq modports----------------------
	modport sq_cache(
		output store_arbit_addr,
		output store_arbit_valid,
		output store_arbit_size,
		output store_arbit_data,
		input  store_arbit_sent,
		input  store_arbit_state
	);
	// sq to fu(load) fwd
	modport sq_fu_fwd(
		input 	fwd_addr,
		input 	fwd_valid,
		input 	fwd_pos,
		output 	fwd_data_return,
		output 	fwd_data_return_mask
	);
	// sq to fu get store data
	modport sq_fu_store(
		input 	st_sq_valid,
		input 	st_sq_data,
		input 	st_sq_addr,
		input 	st_sq_size,
		input 	st_sq_pos
	);
	modport sq_rob_retire(
		input  retire_store,
		output  retire_store_success
	);

	modport sq_disp(
		input  is_store,
		output sq_available_cnt,
		output sq_tail_for_disp,

		input  d_br_stk_idxs,
		input  d_br_stk_idx_valids
	);

	modport disp_sq(
		input sq_available_cnt,
		input sq_tail_for_disp,
		output is_store
	);

	modport sq_rs(
		output can_issue
	);
	modport rs_sq(
		input can_issue
	);
	
// ------------------------ fu-to-sq modports --------------------------
	modport fu_sq_fwd(
		output   fwd_addr,
		output   fwd_valid,
		output   fwd_pos,
		input  fwd_data_return,
		input  fwd_data_return_mask
	);

	modport fu_sq_store(
		output   st_sq_valid,
		output   st_sq_data,
		output   st_sq_addr,
		output   st_sq_size,
		output   st_sq_pos
	);

// ------------------------ fu(load)-to-cache modports ------------------------
	modport fu_cache(
		output  load_arbit_addr,
		output  load_arbit_valid,
		output  load_arbit_size,
		input   load_arbit_sent,
		input   load_arbit_state,
		input   load_arbit_alloc_tag,
		input   load_arbit_hit_data,
		input   load_arbit_broad_valid,
		input   load_arbit_broad_tag,
		input   load_arbit_broad_data
	);

endinterface

`endif
