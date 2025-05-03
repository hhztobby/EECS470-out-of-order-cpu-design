
`include "sys_defs.svh"
`include "cpuBusIF.svh"

/**
@summary
    - dispatcher module, purely combinational; receives fetched instructions and route them around
    - decodes instruction
    - structural hazard resolution
        - query how many free spots are in ROB, Map Table, RS, etc.
        - determine how many instructions can be dispatched
        - tell those modules how many instructions are actually dispatched
    - early branch resolution
        - manages the branch stack
        - allocate a slot when a branch is dispatched, then inform MT and FL
        - ROB stores an entry for each branch instruction, so no need to let it copy the tail
        - Branch unit in EX will directly inform MT, FL, RS, etc., when a branch gets resolved
        - dispatcher will receive this info as well, to update the branch stack
*/


module dispatcher (
    cpuBusIF sys_in,
    cpuBusIF cdb_branch_in,
    cpuBusIF d_branch_stk_out,
    cpuBusIF d_valid,
    cpuBusIF d_dispatch,
    cpuBusIF disp_sq
);
    logic [$clog2(`SQ_SZ+1)-1:0] rem_sq_slots;
    logic [`SQ_IDX_WIDTH-1:0] cur_sq_tail; 

    logic [`DISPATCH_WIDTH-1:0] [`SQ_IDX_WIDTH-1:0] assigned_st_pos;

    // Decode 
    DECODED_INST [`DISPATCH_WIDTH-1:0] decoded_insts;
    logic [`DISPATCH_WIDTH-1:0] inst_has_dst;
    for (genvar decoder_i = 0; decoder_i < `DISPATCH_WIDTH; decoder_i++) begin
        decoder inst_decoder(
            .inst(d_valid.f_insts[decoder_i].inst),
            .valid(d_valid.f_insts[decoder_i].valid),
            .opa_select(decoded_insts[decoder_i].opa_select),
            .opb_select(decoded_insts[decoder_i].opb_select),
            .alu_func(decoded_insts[decoder_i].alu_func),
            .has_dest(inst_has_dst[decoder_i]),
            .mult(decoded_insts[decoder_i].mult),
            .rd_mem(decoded_insts[decoder_i].rd_mem),
            .wr_mem(decoded_insts[decoder_i].wr_mem),
            .cond_branch(decoded_insts[decoder_i].cond_branch),
            .uncond_branch(decoded_insts[decoder_i].uncond_branch),
            .halt(decoded_insts[decoder_i].halt),
            .illegal(decoded_insts[decoder_i].illegal),
            // .is_jal(decoded_insts[decoder_i].is_jal),
            .is_jalr(decoded_insts[decoder_i].is_jalr)
        );
    end

    logic [`DISPATCH_WIDTH-1:0] available_dispatch_slots;
    
    always_comb begin
        disp_sq.is_store = '0;
        cur_sq_tail = disp_sq.sq_tail_for_disp;
        rem_sq_slots = disp_sq.sq_available_cnt;
        assigned_st_pos = '0;
        // --------------------------- dispatch ---------------------------
        available_dispatch_slots = '0;
        for (int i = 0; i < `DISPATCH_WIDTH; i++) begin
            available_dispatch_slots[i] = 
                d_valid.fl_valid_tags[i] != 0 &&
                d_valid.rob_spots > i && 
                d_valid.rs_spots > i;
        end

        // decide which ones to dispatch
        d_valid.f_accepts = '0;
        // assigned_br_slots_bus = '0;
        for (int i = 0; i < `DISPATCH_WIDTH; i++) begin
            d_valid.f_accepts[i] = available_dispatch_slots[i] && d_valid.f_insts[i].valid && ~decoded_insts[i].illegal;
            if (decoded_insts[i].rd_mem) begin
                assigned_st_pos[i] = cur_sq_tail;
            end
            if (decoded_insts[i].wr_mem) begin
                d_valid.f_accepts[i] &= rem_sq_slots > 0;
                assigned_st_pos[i] = cur_sq_tail;
                cur_sq_tail = (cur_sq_tail + 1) % `SQ_SZ;
                rem_sq_slots = rem_sq_slots - 1;
            end
            if (i > 0) begin
                d_valid.f_accepts[i] &= d_valid.f_accepts[i-1];
            end
        end
        
        // if a branch is mispredicted, then neither can dispatch
        if (cdb_branch_in.br_res_state == BR_RES_MIS) begin
            d_valid.f_accepts = '0;
            // assigned_br_slots_bus = '0;
        end

        d_dispatch.d_rs_packet = '0;
        for (int i = 0; i < `DISPATCH_WIDTH; i++) begin
            if (d_valid.f_accepts[i]) begin
                d_dispatch.d_rs_packet.insts[i] = '{
                    valid: 1,
                    inst: decoded_insts[i],
                    bmask: d_valid.f_insts[i].bmask,
                    br_idx: d_valid.f_insts[i].bindex,
                    st_pos: assigned_st_pos[i]
                };
                d_dispatch.d_rs_packet.insts[i].inst.inst = d_valid.f_insts[i].inst;
                d_dispatch.d_rs_packet.insts[i].inst.PC = d_valid.f_insts[i].PC;
                d_dispatch.d_rs_packet.insts[i].inst.NPC = d_valid.f_insts[i].NPC;
                d_dispatch.d_rs_packet.insts[i].inst.predicted_addr = d_valid.f_insts[i].predicted_addr;
                d_dispatch.d_rs_packet.insts[i].inst.src1 = d_dispatch.mt_src1_tagps[i];
                d_dispatch.d_rs_packet.insts[i].inst.src2 = d_dispatch.mt_src2_tagps[i];
                d_dispatch.d_rs_packet.insts[i].inst.dst = d_valid.fl_valid_tags[i];
                d_dispatch.d_rs_packet.insts[i].inst.dest_reg_idx = inst_has_dst[i] ? d_valid.f_insts[i].inst.r.rd : `ZERO_REG;
            end
        end

        // feedback to different modules
        d_dispatch.d_src1_regs = '0;
        d_dispatch.d_src2_regs = '0;
        d_dispatch.d_dst_regs = '0;
        d_dispatch.d_rob_entries = '0;
        d_branch_stk_out.d_br_stk_idxs = '0;
        d_branch_stk_out.d_br_stk_idx_valids = '0;
        for (int i = 0; i < `DISPATCH_WIDTH; i++) begin
            if (d_valid.f_accepts[i]) begin
                disp_sq.is_store[i] = decoded_insts[i].wr_mem;
                if (decoded_insts[i].cond_branch || decoded_insts[i].wr_mem) begin
                    d_dispatch.d_src1_regs[i] = d_valid.f_insts[i].inst.r.rs1;
                    d_dispatch.d_src2_regs[i] = d_valid.f_insts[i].inst.r.rs2;
                end else if (decoded_insts[i].halt) begin
                    // leave it as 0
                end else begin
                    if (decoded_insts[i].opa_select == OPA_IS_RS1) begin
                        d_dispatch.d_src1_regs[i] = d_valid.f_insts[i].inst.r.rs1;
                    end
                    if (decoded_insts[i].opb_select == OPB_IS_RS2) begin
                        d_dispatch.d_src2_regs[i] = d_valid.f_insts[i].inst.r.rs2;
                    end
                end
                d_dispatch.d_dst_regs[i] = inst_has_dst[i] ? d_valid.f_insts[i].inst.r.rd : `ZERO_REG;
                for (int j = 0; j < `BR_STK_SZ; j++) begin
                    if (d_valid.f_insts[i].bindex[j]) begin
                        d_branch_stk_out.d_br_stk_idxs[i] = j;
                        d_branch_stk_out.d_br_stk_idx_valids[i] = 1;
                    end
                end

                d_dispatch.d_rob_entries[i] = '{
                    rd: d_dispatch.d_dst_regs[i],
                    t_new: d_valid.fl_valid_tags[i],
                    t_old: (inst_has_dst[i] && d_valid.f_insts[i].inst.r.rd != 0) ? d_dispatch.mt_dst_tags[i] : d_valid.fl_valid_tags[i],
                    NPC: d_valid.f_insts[i].NPC,
                    halt: decoded_insts[i].halt,
                    illegal: decoded_insts[i].illegal,
                    valid: 1,
                    store: decoded_insts[i].wr_mem,
                    complete: 0
                };
            end
        end
    end

endmodule
