task automatic decode_simulate ( // exactly the same as decoder
    input INST  inst,
    input logic valid, // when low, ignore inst. Output will look like a NOP

    output ALU_OPA_SELECT opa_select,
    output ALU_OPB_SELECT opb_select,
    output logic          has_dest, // if there is a destination register
    output ALU_FUNC       alu_func,
    output logic          mult, /*rd_mem, wr_mem, */cond_branch, uncond_branch,
    // output logic          csr_op, // used for CSR operations, we only use this as a cheap way to get the return code out
    output logic          halt,   // non-zero on a halt
    output logic          illegal // non-zero on an illegal instruction
);
    logic rd_mem, wr_mem; // make them internal as we currently don't deal with mem
    logic csr_op; // still don't know what this is for...
    // Note: I recommend using an IDE's code folding feature on this block
    begin
        // Default control values (looks like a NOP)
        // See sys_defs.svh for the constants used here
        opa_select    = OPA_IS_RS1;
        opb_select    = OPB_IS_RS2;
        alu_func      = ALU_ADD;
        has_dest      = `FALSE;
        csr_op        = `FALSE;
        mult          = `FALSE;
        rd_mem        = `FALSE;
        wr_mem        = `FALSE;
        cond_branch   = `FALSE;
        uncond_branch = `FALSE;
        halt          = `FALSE;
        illegal       = `FALSE;

        if (valid) begin
            casez (inst)
                `RV32_LUI: begin
                    has_dest   = `TRUE;
                    opa_select = OPA_IS_ZERO;
                    opb_select = OPB_IS_U_IMM;
                end
                `RV32_AUIPC: begin
                    has_dest   = `TRUE;
                    opa_select = OPA_IS_PC;
                    opb_select = OPB_IS_U_IMM;
                end
                `RV32_JAL: begin
                    has_dest      = `TRUE;
                    opa_select    = OPA_IS_PC;
                    opb_select    = OPB_IS_J_IMM;
                    uncond_branch = `TRUE;
                end
                `RV32_JALR: begin
                    has_dest      = `TRUE;
                    opa_select    = OPA_IS_RS1;
                    opb_select    = OPB_IS_I_IMM;
                    uncond_branch = `TRUE;
                end
                `RV32_BEQ, `RV32_BNE, `RV32_BLT, `RV32_BGE,
                `RV32_BLTU, `RV32_BGEU: begin
                    opa_select  = OPA_IS_PC;
                    opb_select  = OPB_IS_B_IMM;
                    cond_branch = `TRUE;
                    // stage_ex uses inst.b.funct3 as the branch function
                end
                `RV32_MUL, `RV32_MULH, `RV32_MULHSU, `RV32_MULHU: begin
                    has_dest   = `TRUE;
                    mult       = `TRUE;
                    // stage_ex uses inst.r.funct3 as the mult function
                end
                `RV32_LB, `RV32_LH, `RV32_LW,
                `RV32_LBU, `RV32_LHU: begin
                    has_dest   = `TRUE;
                    opb_select = OPB_IS_I_IMM;
                    rd_mem     = `TRUE;
                    // stage_ex uses inst.r.funct3 as the load size and signedness
                end
                `RV32_SB, `RV32_SH, `RV32_SW: begin
                    opb_select = OPB_IS_S_IMM;
                    wr_mem     = `TRUE;
                    // stage_ex uses inst.r.funct3 as the store size
                end
                `RV32_ADDI: begin
                    has_dest   = `TRUE;
                    opb_select = OPB_IS_I_IMM;
                end
                `RV32_SLTI: begin
                    has_dest   = `TRUE;
                    opb_select = OPB_IS_I_IMM;
                    alu_func   = ALU_SLT;
                end
                `RV32_SLTIU: begin
                    has_dest   = `TRUE;
                    opb_select = OPB_IS_I_IMM;
                    alu_func   = ALU_SLTU;
                end
                `RV32_ANDI: begin
                    has_dest   = `TRUE;
                    opb_select = OPB_IS_I_IMM;
                    alu_func   = ALU_AND;
                end
                `RV32_ORI: begin
                    has_dest   = `TRUE;
                    opb_select = OPB_IS_I_IMM;
                    alu_func   = ALU_OR;
                end
                `RV32_XORI: begin
                    has_dest   = `TRUE;
                    opb_select = OPB_IS_I_IMM;
                    alu_func   = ALU_XOR;
                end
                `RV32_SLLI: begin
                    has_dest   = `TRUE;
                    opb_select = OPB_IS_I_IMM;
                    alu_func   = ALU_SLL;
                end
                `RV32_SRLI: begin
                    has_dest   = `TRUE;
                    opb_select = OPB_IS_I_IMM;
                    alu_func   = ALU_SRL;
                end
                `RV32_SRAI: begin
                    has_dest   = `TRUE;
                    opb_select = OPB_IS_I_IMM;
                    alu_func   = ALU_SRA;
                end
                `RV32_ADD: begin
                    has_dest   = `TRUE;
                end
                `RV32_SUB: begin
                    has_dest   = `TRUE;
                    alu_func   = ALU_SUB;
                end
                `RV32_SLT: begin
                    has_dest   = `TRUE;
                    alu_func   = ALU_SLT;
                end
                `RV32_SLTU: begin
                    has_dest   = `TRUE;
                    alu_func   = ALU_SLTU;
                end
                `RV32_AND: begin
                    has_dest   = `TRUE;
                    alu_func   = ALU_AND;
                end
                `RV32_OR: begin
                    has_dest   = `TRUE;
                    alu_func   = ALU_OR;
                end
                `RV32_XOR: begin
                    has_dest   = `TRUE;
                    alu_func   = ALU_XOR;
                end
                `RV32_SLL: begin
                    has_dest   = `TRUE;
                    alu_func   = ALU_SLL;
                end
                `RV32_SRL: begin
                    has_dest   = `TRUE;
                    alu_func   = ALU_SRL;
                end
                `RV32_SRA: begin
                    has_dest   = `TRUE;
                    alu_func   = ALU_SRA;
                end
                `RV32_CSRRW, `RV32_CSRRS, `RV32_CSRRC: begin
                    csr_op = `TRUE;
                end
                `WFI: begin
                    halt = `TRUE;
                end
                default: begin
                    illegal = `TRUE;
                end
            endcase // casez (inst)
        end // if (valid)
    end
endtask

task automatic dispatch_simulate(
    ref BR_STK_ENTRY [`BR_STK_SZ-1:0] branch_stk,
    input logic clock, reset,
    F_INST [`N-1:0] f_inst,
    TAG_PLUS [`N-1:0][1:0] src_tags_from_mt,
    TAG [`N-1:0] dst_tags_from_mt,
    TAG [`N-1:0] free_tags_from_fl,
    TAG [`N-1:0] free_spots_num_from_rob,
    [$clog2(`N+1)-1:0] free_spots_num_from_rs,
    B_IDX resolved_branch,
    BR_RES_STATE br_res_state,
    output logic [`N-1:0] f_accept,
    REG_IDX [`N-1:0][1:0] src_regs_to_mt,
    REG_IDX [`N-1:0] dst_regs_to_mt,
    TAG [`N-1:0] new_dst_tags_to_mt,
    logic [`N-1:0] [$clog2(`BR_STK_SZ)-1:0] dispatch_br_stk_idx,
    logic [`N-1:0] dispatch_br_stk_idx_valid,
    ROB_ENTRY [`N-1:0] rob_entry_to_rob,
    D_RS_PACKET d_rs_packet
);
begin
    DECODED_INST [`N-1:0] decoded_insts;
    logic [`N-1:0] has_dest;
    int i = 0, j = 0, k = 0;
    int fl_spots = 0, available_spots = 0;
    int branch_stk_spot_indices[`N];
    int branch_stack_spot_num = 0;
// zero initialize all combinational
    f_accept = '0;
    src_regs_to_mt = '0;
    dst_regs_to_mt = '0;
    new_dst_tags_to_mt = '0;
    dispatch_br_stk_idx = '0;
    dispatch_br_stk_idx_valid = '0;
    rob_entry_to_rob = '0;
    d_rs_packet = '0;
// decode instructions
    for (i = 0; i < `N; i++) begin
        decode_simulate(
            f_inst[i].inst,
            f_inst[i].valid,
            decoded_insts[i].opa_select,
            decoded_insts[i].opb_select,
            has_dest[i],
            decoded_insts[i].alu_func,
            decoded_insts[i].mult,
            decoded_insts[i].cond_branch,
            decoded_insts[i].uncond_branch,
            decoded_insts[i].halt,
            decoded_insts[i].illegal
        );
        decoded_insts[i].inst = f_inst[i].inst;
        decoded_insts[i].PC = f_inst[i].PC;
        decoded_insts[i].NPC = f_inst[i].NPC;
        decoded_insts[i].src1 = src_tags_from_mt[i][0];
        decoded_insts[i].src2 = src_tags_from_mt[i][1];
        decoded_insts[i].dst = free_tags_from_fl[i];
        decoded_insts[i].dest_reg_idx = has_dest[i] ? f_inst[i].inst.r.rd : 0;
    end
// update branch stack from resolution
    if (br_res_state == BR_RES_MIS) begin
        for (i = 0; i < `BR_STK_SZ; i++) begin
            if (branch_stk[i].valid && (branch_stk[i].bmask & resolved_branch) != 0) begin
                branch_stk[i].valid = 0;
            end
        end
        return; // return immediately if mispredict
    end else if (br_res_state == BR_RES_HIT) begin
        for (i = 0; i < `BR_STK_SZ; i++) begin
            if (branch_stk[i].valid) begin
                branch_stk[i].bmask &= ~resolved_branch;
            end
            if (branch_stk[i].b_idx == resolved_branch) begin
                branch_stk[i].valid = 0;
            end
        end
    end
// check spots
    for (i = 0; i < `N; i++) begin
        if (f_inst[i].valid) begin
            available_spots++;
        end
        if (free_tags_from_fl[i] != 0) begin
            fl_spots++;
        end
    end
    available_spots = (fl_spots < free_spots_num_from_rob) ? (
        (fl_spots < free_spots_num_from_rs) ? fl_spots : free_spots_num_from_rs
    ) : (
        (free_spots_num_from_rob < free_spots_num_from_rs) ? free_spots_num_from_rob : free_spots_num_from_rs
    );
`ifdef OUTPUT_TEST
    $display("simulator: dispatch available_spots: %0d", available_spots);
// branch stack validities in a bit vector
    $display("simulator: branch_stk.valid: %0b%0b%0b%0b", branch_stk[3].valid, branch_stk[2].valid, branch_stk[1].valid, branch_stk[0].valid);
`endif
    /*$min(
        fl_spots,
        free_spots_num_from_rob,
        free_spots_num_from_rs
    );*/
// grab spots from branch stack
    for (i = 0; i < `N; i++) begin
        branch_stk_spot_indices[i] = -1;
    end
    for (i = 0; i < `BR_STK_SZ; i++) begin
        if (~branch_stk[i].valid) begin
            branch_stack_spot_num++;
        end
        if (branch_stack_spot_num == `N) begin
            break;
        end
    end
    // select branch indices, one last and one first
    for (i = 0; i < `BR_STK_SZ; i++) begin
        if (~branch_stk[i].valid) begin
            branch_stk_spot_indices[1] = i;
            break;
        end
    end
    for (i = `BR_STK_SZ - 1; i >= 0; i--) begin
        if (~branch_stk[i].valid) begin
            branch_stk_spot_indices[0] = i;
            break;
        end
    end
    
`ifdef OUTPUT_TEST
    $display("simulator: initial branch_stack_spot_num: %0d", branch_stack_spot_num);
    $display("simulator: initial branch_stk_spot_indices[0]: %0d, [1]: %0d", branch_stk_spot_indices[0], branch_stk_spot_indices[1]);
`endif
// find accepted instructions and allocate branch stack entries
    for (i = 0, j = 0; i < `N; i++) begin
        if (f_inst[i].valid) begin
            if (available_spots > i) begin
                for (k = 0; k < `BR_STK_SZ; k++) begin
                    if (branch_stk[k].valid) begin
                        d_rs_packet.insts[i].bmask |= branch_stk[k].b_idx;
                    end
                end
                if (decoded_insts[i].cond_branch) begin
                    if (j < branch_stack_spot_num) begin
                        f_accept[i] = 1;
                        dispatch_br_stk_idx[i] = branch_stk_spot_indices[j];
                        dispatch_br_stk_idx_valid[i] = 1;
                        d_rs_packet.insts[i].br_idx = (1 << branch_stk_spot_indices[j]);
                        branch_stk[branch_stk_spot_indices[j]].valid = 1;
                        branch_stk[branch_stk_spot_indices[j]].b_idx = (1 << branch_stk_spot_indices[j]);
                        d_rs_packet.insts[i].bmask |= d_rs_packet.insts[i].br_idx;
                        branch_stk[branch_stk_spot_indices[j]].bmask = d_rs_packet.insts[i].bmask;
                        j++;
                        continue;
                    end
                end else begin
                    f_accept[i] = 1;
                    continue;
                end
            end
        end
        break;
    end
`ifdef OUTPUT_TEST
    for (i = 0; i < `BR_STK_SZ; i++) begin
        $display("simulator: branch_stk[%0d]: valid = %0b, bmask = %0b, b_idx = %0b", i, branch_stk[i].valid, branch_stk[i].bmask, branch_stk[i].b_idx);
    end
// finst validities
    $display("simulator: f_inst_valid[0]: %0b, [1]: %0b", f_inst[0].valid, f_inst[1].valid);
// instruction cond branches
    $display("simulator: f_inst_cond_branch[0]: %0b, [1]: %0b", decoded_insts[0].cond_branch, decoded_insts[1].cond_branch);
    $display("simulator: f_accept: %0b", f_accept);
`endif
// assemble outputs
    for (i = 0; i < `N; i++) begin
        if (f_accept[i]) begin
            d_rs_packet.insts[i].valid = 1;
            d_rs_packet.insts[i].inst = decoded_insts[i];
            // d_rs_packet.insts[i].bmask and br_idx set above
            src_regs_to_mt[i][0] = f_inst[i].inst.r.rs1;
            src_regs_to_mt[i][1] = f_inst[i].inst.r.rs2;
            dst_regs_to_mt[i] = has_dest[i] ? f_inst[i].inst.r.rd : 0;
            new_dst_tags_to_mt[i] = free_tags_from_fl[i];
            rob_entry_to_rob[i] = '{
                rd: has_dest[i] ? f_inst[i].inst.r.rd : 0,
                t_new: free_tags_from_fl[i],
                t_old: has_dest[i] ? dst_tags_from_mt[i] : free_tags_from_fl[i],
                NPC: f_inst[i].NPC,
                halt: decoded_insts[i].halt,
                illegal: decoded_insts[i].illegal,
                valid: 1,
                complete: 0
            };
        end
    end
end
endtask

/*
dispatcher dispatch (
        .clock(clock),
        .reset(reset),
        .f_inst(f_inst),
        .src_tags_from_mt(src_tags_from_mt),
        .dst_tags_from_mt(dst_tags_from_mt),
        .free_tags_from_fl(free_tags_from_fl),
        .free_spots_num_from_rob(free_spots_num_from_rob),
        .free_spots_num_from_rs(rs_spots),
        .resolved_branch(br_res_idx),
        .br_res_state(br_res_state),
        // output
        .f_accept(f_accept),
        .src_regs_to_mt(src_regs_to_mt),
        .dst_regs_to_mt(dst_regs_to_mt),
        .new_dst_tags_to_mt(new_dst_tags_to_mt),
        .dispatch_br_stk_idx(dispatch_br_stk_idx),
        .dispatch_br_stk_idx_valid(dispatch_br_stk_idx_valid),
        .rob_entry_to_rob(rob_entry_to_rob),
        .d_rs_packet(d_rs_packet)
`ifdef DEBUG_SYN
        , .branch_stk(branch_stk)
`endif
    );
*/

/*
module dispatcher (
    input logic clock, reset, 
    // f_inst[0] is earlier in program order than f_inst[1]
    input F_INST [`N-1:0] f_inst,
    // which ones do we accept for dispatching
    output logic [`N-1:0] f_accept,

    // pass N*2 src arch reg, expecting N*2 physical regs (tags)
    output REG_IDX [`N-1:0][1:0] src_regs_to_mt,
    // use tag_plus as they may be ready
    input TAG_PLUS [`N-1:0][1:0] src_tags_from_mt,
    // pass N dest arch reg, expecting N pr
    // which will be passed to ROB as T_old
    output REG_IDX [`N-1:0] dst_regs_to_mt,
    input TAG [`N-1:0] dst_tags_from_mt,
    // update the tag mapping in Map Table, grabbed from free list
    output TAG [`N-1:0] new_dst_tags_to_mt,
    // EBR: which branch stack is allocated
    // shared with fl
    // output logic [`N-1:0] [$clog2(`BR_STK_SZ)-1:0] br_stk_idx_to_mt,
    // output logic [`N-1:0] br_stk_idx_valid_to_mt, //

    // query how many free PRs are there
    input TAG [`N-1:0] free_tags_from_fl, // 0 means no more available PR
    // output logic [`N-1:0] used_spots_to_fl, // use f_accept instead

    // EBR: which branch stack is allocated
    output logic [`N-1:0] [$clog2(`BR_STK_SZ)-1:0] dispatch_br_stk_idx,
    output logic [`N-1:0] dispatch_br_stk_idx_valid,
    
    input logic [$clog2(`N+1)-1:0] free_spots_num_from_rob,
    // output logic [`N-1:0] used_spots_to_rob, // use f_accept instead
    output ROB_ENTRY [`N-1:0] rob_entry_to_rob,

    input [$clog2(`N+1)-1:0] free_spots_num_from_rs,
    output D_RS_PACKET d_rs_packet,

    input B_IDX resolved_branch,
    input BR_RES_STATE br_res_state // branch result: a hit or a mispredict
    `ifdef DEBUG_SYN
    , output BR_STK_ENTRY [`BR_STK_SZ-1:0] branch_stk
    `endif
);
*/