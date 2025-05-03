`include "sys_defs.svh"
`include "ISA.svh"
`include "cpuBusIF.svh"

module issue_to_fu #(
    parameter int FU_CNT = 8, 
    parameter int NUM_ENTRIES = 8,
    parameter int REQS = 8
)(
    input logic [NUM_ENTRIES-1:0] entries_ready,
    input logic [FU_CNT-1:0] fu_avails,
    output logic [FU_CNT-1:0][NUM_ENTRIES-1:0] fu_assigned_entries
);

    logic [REQS-1:0][FU_CNT-1:0] fu_gnt_bus;
    logic [REQS-1:0][NUM_ENTRIES-1:0] entry_gnt_bus;

    psel_gen #(
        .WIDTH(NUM_ENTRIES),
        .REQS(REQS)
    ) entry_psel (
        .req(entries_ready),
        .gnt_bus(entry_gnt_bus)
    );

    psel_gen #(
        .WIDTH(FU_CNT),
        .REQS(REQS)
    ) fu_psel (
        .req(fu_avails),
        .gnt_bus(fu_gnt_bus)
    );

    // fu_gnt_bus[i] is the one-hot mask for the functional unit
    // that gets the i-th request.
    always_comb begin
        fu_assigned_entries = '0;
        for (int i = 0; i < REQS; i++) begin
            for (int j = 0; j < FU_CNT; j++) begin
                if (fu_gnt_bus[i][j]) begin
                    fu_assigned_entries[j] |= entry_gnt_bus[i];
                end
            end
        end
    end

endmodule


module RS_Selector #(
    parameter int NUM_ENTRIES = 8,
    parameter int ALU_CNT = 3,
    parameter int MULT_CNT = 1,
    localparam int BR_CNT = 1
)(
    input RS_ENTRY [NUM_ENTRIES-1:0] rs_entries,
    input logic [NUM_ENTRIES-1:0] entries_ready,
    output logic [ALU_CNT-1:0][NUM_ENTRIES-1:0] assigned_entries_ALU,
    output logic [MULT_CNT-1:0][NUM_ENTRIES-1:0] assigned_entries_MUL,
    output logic [NUM_ENTRIES-1:0] assigned_entries_LOAD,
    output logic [NUM_ENTRIES-1:0] assigned_entries_STORE,
    output logic [BR_CNT-1:0][NUM_ENTRIES-1:0] assigned_entries_BR
);
    localparam logic [ALU_CNT-1:0] alu_avails = '1;
    localparam logic [MULT_CNT-1:0] mul_avails = 'b1;
    // localparam logic [FU_CNT-1:0] mem_avails = 'b1;
    localparam logic [BR_CNT-1:0] br_avails = 'b1;

    logic [NUM_ENTRIES-1:0] entry_ready_ALU, entry_ready_MUL, entry_ready_LOAD, entry_ready_STORE, entry_ready_BR;

    always_comb begin
        for (int i = 0; i < NUM_ENTRIES; i++) begin
            entry_ready_ALU[i] = entries_ready[i] && (rs_entries[i].op == OP_TYPE_ALU);
            entry_ready_MUL[i] = entries_ready[i] && (rs_entries[i].op == OP_TYPE_MUL);
            entry_ready_LOAD[i] = entries_ready[i] && (rs_entries[i].op == OP_TYPE_LOAD);
            entry_ready_STORE[i] = entries_ready[i] && (rs_entries[i].op == OP_TYPE_STORE);
            entry_ready_BR[i]  = entries_ready[i] && (rs_entries[i].op == OP_TYPE_BR || rs_entries[i].op == OP_TYPE_HALT);
        end
    end

    issue_to_fu #(
        .FU_CNT(ALU_CNT),
        .NUM_ENTRIES(NUM_ENTRIES),
        .REQS(ALU_CNT)
    ) alu_issue (
        .entries_ready(entry_ready_ALU),
        .fu_avails(alu_avails),
        .fu_assigned_entries(assigned_entries_ALU)
    );

    issue_to_fu #(
        .FU_CNT(MULT_CNT),
        .NUM_ENTRIES(NUM_ENTRIES),
        .REQS(MULT_CNT) 
    ) mul_issue (
        .entries_ready(entry_ready_MUL),
        .fu_avails(mul_avails),
        .fu_assigned_entries(assigned_entries_MUL)
    );

    issue_to_fu #(
        .FU_CNT(1),
        .NUM_ENTRIES(NUM_ENTRIES),
        .REQS(1) 
    ) load_issue (
        .entries_ready(entry_ready_LOAD),
        .fu_avails(1'b1),
        .fu_assigned_entries(assigned_entries_LOAD)
    );

    issue_to_fu #(
        .FU_CNT(1),
        .NUM_ENTRIES(NUM_ENTRIES),
        .REQS(1) 
    ) store_issue (
        .entries_ready(entry_ready_STORE),
        .fu_avails(1'b1),
        .fu_assigned_entries(assigned_entries_STORE)
    ); 

    issue_to_fu #(
        .FU_CNT(BR_CNT),
        .NUM_ENTRIES(NUM_ENTRIES),
        .REQS(1) 
    ) br_issue (
        .entries_ready(entry_ready_BR),
        .fu_avails(br_avails),
        .fu_assigned_entries(assigned_entries_BR)
    );

endmodule

module rs #(
    parameter int ALU_CNT = 2,
    parameter int MULT_CNT = 1,
    localparam int BR_CNT = 1
)(
    cpuBusIF sys_in,
    cpuBusIF cdb_branch_in,
    cpuBusIF etb_in,
    cpuBusIF rs_dispatch,
    cpuBusIF rs_issue_req,
    cpuBusIF rs_issue_insts,
    cpuBusIF rs_sq
);

    RS_ENTRY [`RS_SZ-1:0] rs_entries;

    logic [`RS_SZ-1:0] requested_issued_entries;
    logic [`RS_SZ-1:0] issued_entries; // forward dec as dispatch relies on this
    /* ----------------------------------------- dispatch logic ----------------------------------------- */
    logic [`RS_SZ-1:0] entries_for_dispatch;
    logic [$clog2(`RS_SZ+1)-1:0] entries_for_dispatch_num;
    always_comb begin
        entries_for_dispatch = '0;
        entries_for_dispatch_num = 0;
        for (int i = 0; i < `RS_SZ; i++) begin
            entries_for_dispatch[i] = 
                rs_entries[i].state == EMPTY || 
                issued_entries[i] || // if issued, we will clear it next cycle and thus can dispatch to it
                (((rs_entries[i].bmask & cdb_branch_in.br_res_idx_bus) != 0) && (cdb_branch_in.br_res_state == BR_RES_MIS)); // if dependent on a mispredicted branch, we will clear it and thus can dispatch to it
        end
        for (int i = 0; i < `RS_SZ; i++) begin
            entries_for_dispatch_num += entries_for_dispatch[i]; // wondering if this could reduce latency...
        end
    end

    assign rs_dispatch.rs_spots = entries_for_dispatch_num > `DISPATCH_WIDTH ? `DISPATCH_WIDTH : entries_for_dispatch_num;
    logic [`DISPATCH_WIDTH-1:0] [`RS_SZ-1:0] entries_dispatch_gnt_bus;
    psel_gen #(
        .WIDTH(`RS_SZ),
        .REQS(`DISPATCH_WIDTH)
    ) dispatch_entry_sel (
        .req(entries_for_dispatch),
        .gnt_bus(entries_dispatch_gnt_bus)
    );

    logic [`DISPATCH_WIDTH-1:0] dispatch_valid;
    logic [`DISPATCH_WIDTH-1:0] [`DISPATCH_WIDTH-1:0] inst_dispatch_gnt_bus;
    always_comb begin
        for (int i = 0; i < `DISPATCH_WIDTH; i++) begin
            dispatch_valid[i] = rs_dispatch.d_rs_packet.insts[i].valid;
        end
    end
    psel_gen #(
        .WIDTH(`DISPATCH_WIDTH),
        .REQS(`DISPATCH_WIDTH)
    ) dispatch_valid_sel (
        .req(dispatch_valid),
        .gnt_bus(inst_dispatch_gnt_bus)
    );

    logic [`RS_SZ-1:0] [`DISPATCH_WIDTH-1:0] inst_dispatched_to_entry; // bit mask for each entry, indicating which inst is dispatched to it
    always_comb begin
        inst_dispatched_to_entry = '0;
        for (int i = 0; i < `DISPATCH_WIDTH; i++) begin // i: request num
            for (int j = 0; j < `RS_SZ; j++) begin // j: instruction index that receives this request
                if (entries_dispatch_gnt_bus[i][j]) begin
                    inst_dispatched_to_entry[j] = inst_dispatch_gnt_bus[i];
                end
            end
        end
    end

    logic [`RS_SZ-1:0] entries_ready;

    function automatic logic getSrcTagpReady(
        input TAG_PLUS tagp, 
        input TAG [`CDB_WIDTH-1:0] cdb_tags
    );
        logic ready = tagp.ready;
        if (tagp.tag == 0) begin
            ready = 1;
        end
        for (int i = 0; i < `CDB_WIDTH; i++) begin
            ready |= (tagp.tag == cdb_tags[i]);
        end
        return ready;
    endfunction

    function automatic logic getEntryReady(
        input RS_ENTRY entry, 
        input BR_RES_STATE br_res_state, 
        input B_IDX br_res_idx_bus,
        input TAG [`CDB_WIDTH-1:0] cdb_tags
    );
        logic ready = 0;
        if (entry.state == EMPTY) begin
            ready = 0;
        end else begin
            // determine branch resolution squash
            if (br_res_state == BR_RES_MIS && ((entry.bmask & br_res_idx_bus) != 0)) begin
                ready = 0;
            end else begin
                ready = getSrcTagpReady(entry.src_tag_1, cdb_tags) && getSrcTagpReady(entry.src_tag_2, cdb_tags);
            end
            if (entry.op == OP_TYPE_LOAD) begin
                ready &= entry.load_can_issue;
            end
        end
        return ready;
    endfunction

    /* ----------------------------------------- issue logic ----------------------------------------- */
    always_comb begin
        entries_ready = '0;
        for (int i = 0; i < `RS_SZ; i++) begin
            entries_ready[i] = getEntryReady(
                rs_entries[i], 
                cdb_branch_in.br_res_state,
                cdb_branch_in.br_res_idx_bus,
                etb_in.etb_tags
            );
        end
    end

    logic [ALU_CNT-1:0][`RS_SZ-1:0] assigned_entries_ALU;
    logic [MULT_CNT-1:0][`RS_SZ-1:0] assigned_entries_MUL;
    logic [`RS_SZ-1:0] assigned_entries_LOAD;
    logic [`RS_SZ-1:0] assigned_entries_STORE;
    logic [BR_CNT-1:0][`RS_SZ-1:0] assigned_entries_BR;
    RS_Selector #(
        .NUM_ENTRIES(`RS_SZ),
        .ALU_CNT(ALU_CNT),
        .MULT_CNT(MULT_CNT)
    ) rs_selector (
        .rs_entries(rs_entries),
        .entries_ready(entries_ready),
        .assigned_entries_ALU(assigned_entries_ALU),
        .assigned_entries_MUL(assigned_entries_MUL),
        .assigned_entries_LOAD(assigned_entries_LOAD),
        .assigned_entries_STORE(assigned_entries_STORE),
        .assigned_entries_BR(assigned_entries_BR)
    );

    function automatic logic getSrcTagInCdb(
        input TAG tag, 
        input TAG [`CDB_WIDTH-1:0] cdb_tags
    );
        logic src_in_cdb = 0;
        for (int i = 0; i < `CDB_WIDTH; i++) begin
            src_in_cdb |= (tag == cdb_tags[i]);
        end
        src_in_cdb &= (tag != 0);
        return src_in_cdb;
    endfunction

    function automatic MEM_SIZE getMemSize(
        input INST inst
    );
        casez (inst)
            `RV32_LB, `RV32_LBU: getMemSize = BYTE;
            `RV32_LH, `RV32_LHU: getMemSize = HALF;
            `RV32_LW: getMemSize = WORD;
            `RV32_SB: getMemSize = BYTE;
            `RV32_SH: getMemSize = HALF;
            `RV32_SW: getMemSize = WORD;
            default: getMemSize = WORD;
        endcase
    endfunction
    function automatic logic getUnsign(input INST inst);
        casez (inst)
            `RV32_LBU, `RV32_LHU: getUnsign = 1;
            default: getUnsign = 0;
        endcase
    endfunction

    // assign instructions to actual functional units
    always_comb begin
        rs_issue_insts.alu_issue_insts = '0;
        rs_issue_insts.mult_issue_insts = '0;
        // mem_inst = '0;
        rs_issue_insts.branch_issue_inst = '0;
        rs_issue_insts.load_issue_inst = '0;
        rs_issue_insts.store_issue_inst = '0;
        
        // ETB: collect all issued single-cycle instructions that uses CDB
        rs_issue_req.alu_req_dst_tags = '0;
        rs_issue_req.store_req_dst_tag = '0;
        rs_issue_req.branch_req_dst_tag = '0;
        requested_issued_entries = '0;
        issued_entries = '0;
        for (int i = 0; i < ALU_CNT; i++) begin
            for (int j = 0; j < `RS_SZ; j++) begin
                if (assigned_entries_ALU[i][j]) begin
                    requested_issued_entries[j] = 1;
                    rs_issue_req.alu_req_dst_tags[i] = rs_entries[j].dst_tag;
                end
            end
        end
        for (int i = 0; i < MULT_CNT; i++) begin
            for (int j = 0; j < `RS_SZ; j++) begin
                if (assigned_entries_MUL[i][j]) begin
                    requested_issued_entries[j] = 1;
                end
            end
        end
        for (int j = 0; j < `RS_SZ; j++) begin
            if (assigned_entries_STORE[j]) begin
                requested_issued_entries[j] = 1;
                rs_issue_req.store_req_dst_tag = rs_entries[j].dst_tag;
            end
        end
        for (int j = 0; j < `RS_SZ; j++) begin
            if (assigned_entries_LOAD[j]) begin
                requested_issued_entries[j] = 1;
            end
        end
        for (int i = 0; i < BR_CNT; i++) begin
            for (int j = 0; j < `RS_SZ; j++) begin
                if (assigned_entries_BR[i][j]) begin
                    requested_issued_entries[j] = 1;
                    rs_issue_req.branch_req_dst_tag = rs_entries[j].dst_tag;
                end
            end
        end
        issued_entries = requested_issued_entries;
        // issue based on cdb arbiter grants
        for (int i = 0; i < ALU_CNT; i++) begin
            for (int j = 0; j < `RS_SZ; j++) begin
                if (assigned_entries_ALU[i][j]) begin
                    if (rs_issue_req.alu_issue_gnts[i]) begin
                        rs_issue_insts.alu_issue_insts[i].valid = 1;
                        rs_issue_insts.alu_issue_insts[i].alu_func = rs_entries[j].inst.alu_func;
                        // set PC
                        rs_issue_insts.alu_issue_insts[i].PC = rs_entries[j].inst.PC;
                        // set NPC
                        rs_issue_insts.alu_issue_insts[i].NPC = rs_entries[j].inst.NPC;
                        rs_issue_insts.alu_issue_insts[i].opa_select = rs_entries[j].inst.opa_select;
                        rs_issue_insts.alu_issue_insts[i].opb_select = rs_entries[j].inst.opb_select;
                        rs_issue_insts.alu_issue_insts[i].inst = rs_entries[j].inst.inst;
                        rs_issue_insts.alu_issue_insts[i].src1 = rs_entries[j].src_tag_1.tag;
                        rs_issue_insts.alu_issue_insts[i].src2 = rs_entries[j].src_tag_2.tag;
                        rs_issue_insts.alu_issue_insts[i].src1_in_cdb = getSrcTagInCdb(rs_entries[j].src_tag_1.tag, etb_in.etb_tags);
                        rs_issue_insts.alu_issue_insts[i].src2_in_cdb = getSrcTagInCdb(rs_entries[j].src_tag_2.tag, etb_in.etb_tags);
                        rs_issue_insts.alu_issue_insts[i].dst = rs_entries[j].dst_tag;
                        rs_issue_insts.alu_issue_insts[i].bmask = (cdb_branch_in.br_res_state == BR_RES_HIT) ? (rs_entries[j].bmask & ~cdb_branch_in.br_res_idx_bus) : rs_entries[j].bmask;
                    end else begin
                        issued_entries[j] = 1'b0;
                    end
                end
            end
        end
        for (int i = 0; i < MULT_CNT; i++) begin
            for (int j = 0; j < `RS_SZ; j++) begin
                if (assigned_entries_MUL[i][j]) begin
                    if (rs_issue_req.mult_issue_gnts[i]) begin
                        rs_issue_insts.mult_issue_insts[i].valid = 1'b1;
                        rs_issue_insts.mult_issue_insts[i].src1 = rs_entries[j].src_tag_1.tag;
                        rs_issue_insts.mult_issue_insts[i].src2 = rs_entries[j].src_tag_2.tag;
                        rs_issue_insts.mult_issue_insts[i].dst = rs_entries[j].dst_tag;
                        rs_issue_insts.mult_issue_insts[i].src1_in_cdb = getSrcTagInCdb(rs_entries[j].src_tag_1.tag, etb_in.etb_tags);
                        rs_issue_insts.mult_issue_insts[i].src2_in_cdb = getSrcTagInCdb(rs_entries[j].src_tag_2.tag, etb_in.etb_tags);
                        rs_issue_insts.mult_issue_insts[i].mult_func = MULT_FUNC'(rs_entries[j].inst.inst.r.funct3);
                        rs_issue_insts.mult_issue_insts[i].bmask = (cdb_branch_in.br_res_state == BR_RES_HIT) ? (rs_entries[j].bmask & ~cdb_branch_in.br_res_idx_bus) : rs_entries[j].bmask;
                    end else begin
                        issued_entries[j] = 1'b0;
                    end
                end
            end
        end
        for (int j = 0; j < `RS_SZ; j++) begin
            if (assigned_entries_LOAD[j]) begin
                if (rs_issue_req.load_issue_gnt) begin
                    rs_issue_insts.load_issue_inst.valid = 1'b1;
                    rs_issue_insts.load_issue_inst.inst = rs_entries[j].inst.inst;
                    rs_issue_insts.load_issue_inst.src1 = rs_entries[j].src_tag_1.tag;
                    rs_issue_insts.load_issue_inst.src2 = rs_entries[j].src_tag_2.tag;
                    rs_issue_insts.load_issue_inst.dst = rs_entries[j].dst_tag;
                    rs_issue_insts.load_issue_inst.src1_in_cdb = getSrcTagInCdb(rs_entries[j].src_tag_1.tag, etb_in.etb_tags);
                    rs_issue_insts.load_issue_inst.src2_in_cdb = getSrcTagInCdb(rs_entries[j].src_tag_2.tag, etb_in.etb_tags);
                    rs_issue_insts.load_issue_inst.st_pos = rs_entries[j].st_pos;
                    rs_issue_insts.load_issue_inst.size = getMemSize(rs_entries[j].inst.inst);
                    rs_issue_insts.load_issue_inst.bmask = (cdb_branch_in.br_res_state == BR_RES_HIT) ? (rs_entries[j].bmask & ~cdb_branch_in.br_res_idx_bus) : rs_entries[j].bmask;
                    rs_issue_insts.load_issue_inst.is_unsigned = getUnsign(rs_entries[j].inst.inst);
                end else begin
                    issued_entries[j] = 1'b0;
                end
            end
        end
        for (int j = 0; j < `RS_SZ; j++) begin
            if (assigned_entries_STORE[j]) begin
                if (rs_issue_req.store_issue_gnt) begin
                    rs_issue_insts.store_issue_inst.valid = 1'b1;
                    rs_issue_insts.store_issue_inst.inst = rs_entries[j].inst.inst;
                    rs_issue_insts.store_issue_inst.src1 = rs_entries[j].src_tag_1.tag;
                    rs_issue_insts.store_issue_inst.src2 = rs_entries[j].src_tag_2.tag;
                    rs_issue_insts.store_issue_inst.dst = rs_entries[j].dst_tag;
                    rs_issue_insts.store_issue_inst.src1_in_cdb = getSrcTagInCdb(rs_entries[j].src_tag_1.tag, etb_in.etb_tags);
                    rs_issue_insts.store_issue_inst.src2_in_cdb = getSrcTagInCdb(rs_entries[j].src_tag_2.tag, etb_in.etb_tags);
                    rs_issue_insts.store_issue_inst.st_pos = rs_entries[j].st_pos;
                    rs_issue_insts.store_issue_inst.size = getMemSize(rs_entries[j].inst.inst);
                    rs_issue_insts.store_issue_inst.bmask = (cdb_branch_in.br_res_state == BR_RES_HIT) ? (rs_entries[j].bmask & ~cdb_branch_in.br_res_idx_bus) : rs_entries[j].bmask;
                end else begin
                    issued_entries[j] = 1'b0;
                end
            end
        end
        for (int j = 0; j < `RS_SZ; j++) begin
            if (assigned_entries_BR[0][j]) begin
                if (rs_issue_req.branch_issue_gnt) begin
                    rs_issue_insts.branch_issue_inst.valid = 1'b1;
                    rs_issue_insts.branch_issue_inst.predicted_addr = rs_entries[j].inst.predicted_addr;
                    // rs_issue_insts.branch_issue_inst.is_predicted_taken = rs_entries[j].inst.is_predicted_taken;
                    rs_issue_insts.branch_issue_inst.bindex = rs_entries[j].bindex;
                    rs_issue_insts.branch_issue_inst.bmask = (cdb_branch_in.br_res_state == BR_RES_HIT) ? (rs_entries[j].bmask & ~cdb_branch_in.br_res_idx_bus) : rs_entries[j].bmask;
                    rs_issue_insts.branch_issue_inst.src1 = rs_entries[j].src_tag_1.tag;
                    rs_issue_insts.branch_issue_inst.src2 = rs_entries[j].src_tag_2.tag;
                    rs_issue_insts.branch_issue_inst.src1_in_cdb = getSrcTagInCdb(rs_entries[j].src_tag_1.tag, etb_in.etb_tags);
                    rs_issue_insts.branch_issue_inst.src2_in_cdb = getSrcTagInCdb(rs_entries[j].src_tag_2.tag, etb_in.etb_tags);
                    rs_issue_insts.branch_issue_inst.dst = rs_entries[j].dst_tag;
                    rs_issue_insts.branch_issue_inst.PC = rs_entries[j].inst.PC;
                    rs_issue_insts.branch_issue_inst.branch_func = rs_entries[j].inst.inst.b.funct3;
                    rs_issue_insts.branch_issue_inst.offset = rs_entries[j].inst.cond_branch ? `RV32_signext_Bimm(rs_entries[j].inst.inst) : (
                        rs_entries[j].inst.uncond_branch ? (
                            rs_entries[j].inst.opb_select == OPB_IS_I_IMM ? `RV32_signext_Iimm(rs_entries[j].inst.inst) : // jalr
                            `RV32_signext_Jimm(rs_entries[j].inst.inst) // jal
                        ) : 0
                    );
                    rs_issue_insts.branch_issue_inst.is_uncond_branch = rs_entries[j].inst.uncond_branch;
                    rs_issue_insts.branch_issue_inst.is_halt = rs_entries[j].inst.halt;
                    rs_issue_insts.branch_issue_inst.is_jalr = rs_entries[j].inst.is_jalr;
                end else begin
                    issued_entries[j] = 1'b0;
                end
            end
        end
    end

    function automatic RS_OP_TYPE getRS_OP_TYPE(input DECODED_INST inst);
        if (inst.cond_branch || inst.uncond_branch) begin
            getRS_OP_TYPE = OP_TYPE_BR;
        end else if (inst.mult) begin
            getRS_OP_TYPE = OP_TYPE_MUL;
        end else if (inst.halt) begin
            getRS_OP_TYPE = OP_TYPE_HALT;
        end else if (inst.rd_mem) begin
            getRS_OP_TYPE = OP_TYPE_LOAD;
        end else if (inst.wr_mem) begin
            getRS_OP_TYPE = OP_TYPE_STORE;
        end else begin
            getRS_OP_TYPE = OP_TYPE_ALU;
        end
    endfunction

    function automatic logic getRS_TAG_READY(input TAG_PLUS tagp, input TAG [`CDB_WIDTH-1:0] cdb_tags);
        logic ready;
        ready = tagp.ready;
        for (int i = 0; i < `CDB_WIDTH; i++) begin
            ready |= (tagp.tag == cdb_tags[i]);
        end
        return ready;
    endfunction

    function automatic TAG_PLUS getRS_TAG_PLUS(input TAG_PLUS tagp, input TAG [`CDB_WIDTH-1:0] cdb_tags);
        TAG_PLUS tag_plus;
        tag_plus.tag = tagp.tag;
        tag_plus.ready = tagp.ready;
        for (int i = 0; i < `CDB_WIDTH; i++) begin
            if (tagp.tag == cdb_tags[i]) begin
                tag_plus.ready = 1'b1;
            end
        end
        if (tagp.tag == 0) begin
            tag_plus.ready = 1'b1;
        end
        return tag_plus;
    endfunction

    always_ff @(posedge sys_in.clock) begin
        if (sys_in.reset) begin
            for (int i = 0; i < `RS_SZ; i++) begin
                rs_entries[i] <= '0;
            end
        end else begin
            // instructions issued last cycle should be cleared here
            for (int i = 0; i < `RS_SZ; i++) begin
                if (inst_dispatched_to_entry[i] > 0) begin
                    for (int j = 0; j < `DISPATCH_WIDTH; j++) begin
                        if (inst_dispatched_to_entry[i][j]) begin
                            rs_entries[i] <= '{
                                rs_dispatch.d_rs_packet.insts[j].inst,
                                DISPATCHED,
                                getRS_OP_TYPE(rs_dispatch.d_rs_packet.insts[j].inst),
                                rs_dispatch.d_rs_packet.insts[j].inst.dst,
                                getRS_TAG_PLUS(rs_dispatch.d_rs_packet.insts[j].inst.src1, etb_in.etb_tags),
                                getRS_TAG_PLUS(rs_dispatch.d_rs_packet.insts[j].inst.src2, etb_in.etb_tags),
                                (cdb_branch_in.br_res_state == BR_RES_HIT) ? 
                                    (rs_dispatch.d_rs_packet.insts[j].bmask & ~cdb_branch_in.br_res_idx_bus) : 
                                    rs_dispatch.d_rs_packet.insts[j].bmask,
                                rs_dispatch.d_rs_packet.insts[j].br_idx,
                                rs_dispatch.d_rs_packet.insts[j].st_pos,
                                rs_sq.can_issue[rs_dispatch.d_rs_packet.insts[j].st_pos]
                            };
                        end
                    end
                end else if (issued_entries[i]) begin // if the entry was issued last cycle and is not dispatched to
                    rs_entries[i].state <= EMPTY;
                end else if ((cdb_branch_in.br_res_state == BR_RES_MIS) && ((rs_entries[i].bmask & cdb_branch_in.br_res_idx_bus) != 0)) begin
                    rs_entries[i].state <= EMPTY;
                end else if (rs_entries[i].state == DISPATCHED) begin
                    rs_entries[i].src_tag_1.ready <= getRS_TAG_READY(rs_entries[i].src_tag_1, etb_in.etb_tags);
                    rs_entries[i].src_tag_2.ready <= getRS_TAG_READY(rs_entries[i].src_tag_2, etb_in.etb_tags);
                    rs_entries[i].load_can_issue <= rs_entries[i].load_can_issue || rs_sq.can_issue[rs_entries[i].st_pos];
                    if (cdb_branch_in.br_res_state == BR_RES_HIT) begin
                        rs_entries[i].bmask <= (rs_entries[i].bmask & ~cdb_branch_in.br_res_idx_bus);
                    end
                end 
            end
        end
    end

endmodule
