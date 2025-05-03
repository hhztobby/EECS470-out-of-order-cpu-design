`include "sys_defs.svh"
`include "ISA.svh"
`include "cpuBusIF.svh"

/**
@note: see cpuBusIF.svh for all our ports
*/

module cpu (
// -------------------------- inputs --------------------------
    input logic clock, reset, 
    input MEM_TAG                                   mem_transac_tag,
    input MEM_BLOCK                                 mem_read_data,
    input MEM_TAG                                   mem_read_data_tag,
// -------------------------- outputs --------------------------
    output ADDR                                     cache_mem_addr,
    output MEM_COMMAND                              cache_mem_command,
    output MEM_BLOCK                                cache_mem_write_data,
    output COMMIT_PACKET [`RETIRE_WIDTH-1:0]                   retired_insts,
    output logic                                    dcache_writeback_clear,
    output logic [`DCACHE_LINES-1:0][$bits(MEM_BLOCK)-1:0] dcache_mem_out,
    output DCACHE_TAG [`DCACHE_LINES-1:0] dcache_tags_out
);

/**
    Interface and modports provide a pub-sub way to wire modules together;
        - interface signals are the database
        - modules publish and receive data through modports
*/
    cpuBusIF cpuBus (
        .reset(reset), 
        .clock(clock),
        .mem_transac_tag(mem_transac_tag),
        .mem_read_data(mem_read_data),
        .mem_read_data_tag(mem_read_data_tag),
        .cache_mem_addr(cache_mem_addr),
        .cache_mem_command(cache_mem_command),
        .cache_mem_write_data(cache_mem_write_data),
        .retire_packets(retired_insts)
    );

    fetcher fetch(
        .sys(cpuBus.sys_in),
        .bus(cpuBus.fetch)
    );

    icache instCache(
        .sys(cpuBus.sys_in),
        .bus(cpuBus.icache)
    );

    cache_controller ccontroller(
        .sys(cpuBus.sys_in),
        .bus(cpuBus.cache_control)
    );

    dispatcher dispatch (
        .sys_in(cpuBus.sys_in),
        .cdb_branch_in(cpuBus.cdb_branch_in),
        .d_branch_stk_out(cpuBus.d_branch_stk_out),
        .d_valid(cpuBus.d_valid),
        .d_dispatch(cpuBus.d_dispatch),
        .disp_sq(cpuBus.disp_sq)
    );

    rs #(
        .ALU_CNT(`NUM_FU_ALU),
        .MULT_CNT(`NUM_FU_MULT)
    ) rs_module (
        .sys_in(cpuBus.sys_in),
        .cdb_branch_in(cpuBus.cdb_branch_in),
        .etb_in(cpuBus.etb_in),
        .rs_dispatch(cpuBus.rs_dispatch),
        .rs_issue_req(cpuBus.rs_issue_req),
        .rs_issue_insts(cpuBus.rs_issue_insts),
        .rs_sq(cpuBus.rs_sq)
    );

    map_table #(
        .BR_STACK_SIZE(`BR_STK_SZ),
        .PR_COUNT(`PR_CNT),
        .ARCH_COUNT(`AR_CNT)
    ) map_table (
        .sys_in(cpuBus.sys_in),
        .d_branch_stk_in(cpuBus.d_branch_stk_in),
        .etb_in(cpuBus.etb_in),
        .cdb_branch_in(cpuBus.cdb_branch_in),
        .mt_dispatch(cpuBus.mt_dispatch)
    );

    freelist #(
        .BR_STACK_SIZE(`BR_STK_SZ),
        .PR_COUNT(`PR_CNT),
        .ARCH_COUNT(`AR_CNT)
    ) fl (
        // inputs
        .sys_in(cpuBus.sys_in),
        .d_branch_stk_in(cpuBus.d_branch_stk_in),
        .cdb_branch_in(cpuBus.cdb_branch_in),
        .fl_dispatch(cpuBus.fl_dispatch),
        .fl_retire(cpuBus.fl_retire)
    );

    isReg #(
        .ALU_CNT(`NUM_FU_ALU),
        .MULT_CNT(`NUM_FU_MULT)
    ) issueRegister (
        .sys_in(cpuBus.sys_in),
        .etb_in(cpuBus.etb_in),
        .cdb_branch_in(cpuBus.cdb_branch_in),
        .sreg_issue(cpuBus.sreg_issue),
        .sreg_issue_data_read(cpuBus.sreg_issue_data_read),
        .sreg_execute(cpuBus.sreg_execute)
    );

    TAG [`NUM_FU * 2 + `RETIRE_WIDTH - 1: 0] prf_read_tags;
    DATA [`NUM_FU * 2 + `RETIRE_WIDTH - 1: 0] prf_read_datas;
    logic [`CDB_WIDTH - 1: 0] cdb_prf_valids;
    TAG [`CDB_WIDTH - 1: 0] cdb_prf_dst_tags;
    DATA [`CDB_WIDTH - 1: 0] cdb_prf_dst_datas;
    always_comb begin
        prf_read_tags = {cpuBus.retire_new_dst_tags, cpuBus.issue_src2_read_tags, cpuBus.issue_src1_read_tags};
        cpuBus.prf_issue_src1_datas = prf_read_datas[`NUM_FU - 1 : 0];
        cpuBus.prf_issue_src2_datas = prf_read_datas[`NUM_FU * 2 - 1 : `NUM_FU];
        cpuBus.retire_prf_datas = prf_read_datas[`NUM_FU * 2 + `RETIRE_WIDTH - 1 : `NUM_FU * 2];
        for (int i = 0; i < `CDB_WIDTH; i++) begin
            cdb_prf_valids[i] = cpuBus.cdb_reg_packets[i].dst_tag_out != 0;
            cdb_prf_dst_tags[i] = cpuBus.cdb_reg_packets[i].dst_tag_out;
            cdb_prf_dst_datas[i] = cpuBus.cdb_reg_packets[i].result;
        end
    end

    regMem #(
        .WIDTH(32),
        .DEPTH(`PR_CNT),
        .READ_PORTS(`PRF_READ_PORT_CNT),
        .BYPASS_EN(1),
        .WRITE_PORTS(`PRF_WRITE_PORT_CNT)
    ) regFile (
        .clock(clock),
        .reset(reset),
        .re({`PRF_READ_PORT_CNT{1'b1}}),
        .raddr(prf_read_tags),
        .rdata(prf_read_datas),
        .we(cdb_prf_valids),
        .waddr(cdb_prf_dst_tags),
        .wdata(cdb_prf_dst_datas)
    );

    fu fu_module (
        .sys_in(cpuBus.sys_in),
        .cdb_branch_in(cpuBus.cdb_branch_in),
        .cdb_issue_select(cpuBus.cdb_issue_select),
        .fu_receive(cpuBus.fu_receive),
        .etb_out(cpuBus.etb_out),
        .cdb_branch_out(cpuBus.cdb_branch_out),
        .cdb_wb(cpuBus.cdb_wb),
        .fu_sq_store(cpuBus.fu_sq_store),
        .fu_cache(cpuBus.fu_cache),
        .fu_sq_fwd(cpuBus.fu_sq_fwd)
    );

    sq sq_module(
        .sys_in(cpuBus.sys_in),
        .sq_disp(cpuBus.sq_disp),
        .sq_rs(cpuBus.sq_rs),
        .sq_fu_store(cpuBus.sq_fu_store),
        .cdb_branch_in(cpuBus.cdb_branch_in),
        .sq_fu_fwd(cpuBus.sq_fu_fwd),
        .sq_rob_retire(cpuBus.sq_rob_retire),
        .sq_cache(cpuBus.sq_cache)
    );

    cache_arbit cache_arbiter(
        .arbit_dcache(cpuBus.arbit_dcache),
        .arbit_load(cpuBus.arbit_load),
        .arbit_store(cpuBus.arbit_store)
    );

    dcache data_cache (
        .sys(cpuBus.sys_in),
        .bus(cpuBus.dcache),
        .writeback_clear(dcache_writeback_clear),
        .dcache_mem_out(dcache_mem_out),
        .dcache_tags_out(dcache_tags_out)
    );

    rob rob_module (
        .sys_in(cpuBus.sys_in),
        .d_branch_stk_in(cpuBus.d_branch_stk_in),
        .etb_in(cpuBus.etb_in),
        .rob_dispatch(cpuBus.rob_dispatch),
        .rob_complete(cpuBus.rob_complete),
        .rob_retire(cpuBus.rob_retire),
        .cdb_branch_in(cpuBus.cdb_branch_in),
        .rob_sq_retire(cpuBus.rob_sq_retire)
    );

endmodule
