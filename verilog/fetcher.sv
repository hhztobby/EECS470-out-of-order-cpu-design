`include "sys_defs.svh"
`include "cpuBusIF.svh"
`include "ISA.svh"

module fetcher(
    cpuBusIF sys,
    cpuBusIF bus
);

    localparam int INST_BUFFER_SZ_BITS = $clog2(`INST_BUFFER_SZ + 1);

    ADDR pc, next_pc;

    // Branch stack 
    BR_STK_ENTRY [`BR_STK_SZ-1:0] branch_stk;
    BR_STK_ENTRY [`BR_STK_SZ-1:0] n_branch_stk;

    F_INST [`INST_BUFFER_SZ-1:0] inst_buffer, next_inst_buffer;
    logic [INST_BUFFER_SZ_BITS-1:0] ib_head, next_ib_head, ib_tail, next_ib_tail, temp_ib_head;
    logic [`FETCH_WIDTH-1:0] next_fetch_valids;

    // prediction signals
    ADDR branch_fetch_pc;
    logic [INST_BUFFER_SZ_BITS-1:0] inst_buffer_slots;
    logic [`BR_STK_SZ-1:0] branch_stack_slots;
    logic should_copy_ebr;
    logic first_branch_is_cond, first_branch_is_func_call, first_branch_is_return;
    logic dir_predicted_taken;
    logic first_branch_predicted_taken;
    ADDR  btb_predicted_target_pc, ras_predicted_target_pc;
    ADDR  predicted_taken_addr;
    logic ras_has_space;

    // combinational
    // ADDR current_inst_pc;
    logic [`FETCH_WIDTH-1:0] first_branch, is_branch, before_second_branch_mask, up_to_first_branch_mask;
    B_IDX new_bindex_bus;
    logic [$clog2(`BR_STK_SZ)-1:0] new_bindex;
    BMASK cur_bmask;
    ADDR aligned_pc;

    F_INST [`FETCH_WIDTH-1:0] fetched_insts;

    dirPred directionPredictor(
        .reset(sys.reset),
        .clock(sys.clock),
        .is_dir_mis(bus.br_res_state == BR_RES_MIS),
        .br_res_idx(bus.br_res_idx),
        .mis_inst_pc(bus.br_res_inst_pc),
        .br_res_is_cond(bus.br_res_is_cond),
        .is_actual_taken(bus.br_res_is_taken),
        // fetch
        .should_copy_ebr(should_copy_ebr),
        .fetch_is_cond(first_branch_is_cond),
        .fetch_bindex(new_bindex),
        .fetch_pc(branch_fetch_pc),
        // output
        .is_pred_taken(dir_predicted_taken)
    );

    btb branchTargetBuffer(
        .reset(sys.reset),
        .clock(sys.clock),
        .is_br_resolved_taken(bus.br_res_state != BR_RES_INVALID && bus.br_res_is_taken),
        .br_inst_pc(bus.br_res_inst_pc),
        .br_target_pc(bus.cdb_branch_actual_pc),
        .fetch_pc(branch_fetch_pc),
        .pred_target_pc(btb_predicted_target_pc)
    );

    ras returnAddressStack(
        .reset(sys.reset),
        .clock(sys.clock),
        .is_dir_mis(bus.br_res_state == BR_RES_MIS),
        .br_res_idx(bus.br_res_idx),
        .is_func_call(first_branch_is_func_call),
        .is_return(first_branch_is_return),
        .should_copy_ebr(should_copy_ebr),
        .fetch_pc(branch_fetch_pc),
        .fetch_bindex(new_bindex),
        .pred_target_pc(ras_predicted_target_pc),
        .has_space(ras_has_space)
    );

    always_comb begin
        next_pc = pc;
        next_fetch_valids = '0;
        bus.fetch_read_valids = '0;
        bus.fetch_read_addrs = '0;
        next_ib_head = ib_head;
        next_ib_tail = ib_tail;
        bus.f_insts = '0;
        next_inst_buffer = inst_buffer;
        n_branch_stk = branch_stk; // copy the current branch stack to next
        // fetch
        fetched_insts = '0;
        first_branch = '0;
        inst_buffer_slots = '0;
        branch_stack_slots = '0;
        up_to_first_branch_mask = '0;
        before_second_branch_mask = '0;
        aligned_pc = '0;
        branch_fetch_pc = '0;
        cur_bmask = '0;
        // prediction
        should_copy_ebr = 0;
        new_bindex = 0;
        new_bindex_bus = 0;
        first_branch_predicted_taken = 0;
        first_branch_is_cond = 0;
        first_branch_is_func_call = 0;
        first_branch_is_return = 0;

        // --------------------------- deal with branch resolution ---------------------------
        if (bus.br_res_state == BR_RES_MIS) begin
            next_pc = bus.cdb_branch_actual_pc;
            // clear inst buffer on mispredict
            next_inst_buffer = '0;
            next_ib_head = 0;
            next_ib_tail = 0;
        end else if (bus.br_res_state == BR_RES_HIT) begin
            // clear masks in inst buffer
            for (int i = 0; i < `INST_BUFFER_SZ; i++) begin
                if (inst_buffer[i].valid) begin
                    next_inst_buffer[i].bmask = (next_inst_buffer[i].bmask & ~bus.br_res_idx_bus);
                end
            end
        end
        // if hit, release that entry, clean masks of all other valid
        if (bus.br_res_state == BR_RES_HIT) begin
            for (int i = 0; i < `BR_STK_SZ; i++) begin
                if (n_branch_stk[i].valid) begin
                    if (n_branch_stk[i].b_idx == bus.br_res_idx_bus) begin
                        n_branch_stk[i].valid = 0;
                    end
                    n_branch_stk[i].bmask = (n_branch_stk[i].bmask & ~bus.br_res_idx_bus);
                end
            end
        // if mispredict, clear all entries, including its own
        end else if (bus.br_res_state == BR_RES_MIS) begin
            for (int i = 0; i < `BR_STK_SZ; i++) begin
                if (n_branch_stk[i].valid && (((n_branch_stk[i].bmask & bus.br_res_idx_bus) != 0)) || n_branch_stk[i].b_idx == bus.br_res_idx_bus) begin
                    n_branch_stk[i].valid = 0;
                end
            end
        end

        // output fetched instructions
        temp_ib_head = next_ib_head;
        for (int i = 0; i < `DISPATCH_WIDTH; i++) begin
            if (temp_ib_head != next_ib_tail) begin
                bus.f_insts[i] = next_inst_buffer[temp_ib_head];
                temp_ib_head = (temp_ib_head + 1) % `INST_BUFFER_SZ;
            end
        end

        // current_inst_pc = '0;
        for (int i = 0; i < `ICACHE_READ_PORTS; i++) begin
            bus.fetch_read_valids[i] = 1;
            bus.fetch_read_addrs[i] = ((next_pc + i * 8) & (~32'b111)); // align to 8 bytes
        end
        // receive icache data
        for (int i = 0; i < `ICACHE_READ_PORTS; i++) begin
            if (bus.icache_hits[i]) begin
                next_fetch_valids[i * 2] = 1;
                next_fetch_valids[i * 2 + 1] = 1;
            end
        end
        // misaligned
        if ((next_pc & (32'b111)) != 0) begin
            next_fetch_valids[0] = 0;
        end
        aligned_pc = next_pc & (~32'b111); // align to 8 bytes
        // 1. get all instructions and decode
        // 2. send the first branch for prediction
            // if taken, mask out the rest
            // if not, accept until the next branch (exclusive)
        // 3. check struc hazard
            // if branch stack full, mask out first branch and after
            // mask out instructions according to inst buffer slots
        // 4. assign bmasks and bindex, update inst buffer and fetch_pc
        for (int i = 0; i < `FETCH_WIDTH; i++) begin
            fetched_insts[i].inst = (i[0]) ? bus.icache_fetch_datas[i/2][63:32] : bus.icache_fetch_datas[i/2][31:0];
            casez (fetched_insts[i].inst)
                `RV32_BEQ, `RV32_BNE, `RV32_BLT, `RV32_BGE,
                `RV32_BLTU, `RV32_BGEU: begin
                    fetched_insts[i].is_cond = 1'b1;
                end
                `RV32_JAL: begin
                    fetched_insts[i].is_uncond = 1'b1;
                    // jal with rd = 1 is a function call
                    fetched_insts[i].is_func_call = fetched_insts[i].inst.r.rd == 1;   
                end
                `RV32_JALR: begin
                    fetched_insts[i].is_uncond = 1'b1;
                    fetched_insts[i].is_func_call = fetched_insts[i].inst.r.rd == 1;
                    fetched_insts[i].is_return = fetched_insts[i].inst.r.rs1 == 1 && fetched_insts[i].inst.r.rd == 0;
                end
            endcase
            is_branch[i] = next_fetch_valids[i] && (fetched_insts[i].is_cond || fetched_insts[i].is_uncond);
        end

        // say is_branch = 0110, then first_branch = 0010
        first_branch = is_branch & ~(is_branch - 1);
        // determine if we could indeed fetch this one
        inst_buffer_slots = (next_ib_tail >= next_ib_head) ? (`INST_BUFFER_SZ - next_ib_tail + next_ib_head - 1) : (next_ib_head - next_ib_tail - 1);
        if (next_fetch_valids[0] == 0) begin
            inst_buffer_slots += 1; // misaligned case
        end
        for (int i = 0; i < `FETCH_WIDTH; i++) begin
            if (i >= inst_buffer_slots) begin
                next_fetch_valids[i] = 0;
            end
        end
        for (int i = 0; i < `BR_STK_SZ; i++) begin
            if (!n_branch_stk[i].valid) begin
                branch_stack_slots[i] = 1;
            end
        end
        new_bindex_bus = branch_stack_slots & ~(branch_stack_slots - 1);
        for (int i = 0; i < `BR_STK_SZ; i++) begin
            if (new_bindex_bus[i]) begin
                new_bindex = i;
            end
        end
        // second branch mask, or 0.
        // in our example, 0100
        before_second_branch_mask = is_branch & ~first_branch;
        // leave the second branch only
        // in our example, 0100
        before_second_branch_mask &= ~(before_second_branch_mask - 1);
        // select everything before it
        before_second_branch_mask -= 1;
        next_fetch_valids &= before_second_branch_mask;
        // branch stack hazard
        if (new_bindex_bus == 0) begin
            next_fetch_valids &= (first_branch - 1);
        end
        // make a prediction for the first branch
        for (int i = 0; i < `FETCH_WIDTH; i++) begin
            if (first_branch[i] & next_fetch_valids[i]) begin
                // we got a branch to fetch!
                should_copy_ebr = 1'b1;
                first_branch_is_cond = fetched_insts[i].is_cond;
                first_branch_is_func_call = fetched_insts[i].is_func_call;
                first_branch_is_return = fetched_insts[i].is_return;
                branch_fetch_pc = aligned_pc + i * 4;
                first_branch_predicted_taken = 
                    (first_branch_is_cond && dir_predicted_taken) || 
                    fetched_insts[i].is_uncond;
            end
        end
        up_to_first_branch_mask = (first_branch - 1) | first_branch;
        if (first_branch_predicted_taken) begin
            next_fetch_valids &= up_to_first_branch_mask;
        end
        predicted_taken_addr = first_branch_is_return ? ras_predicted_target_pc : btb_predicted_target_pc;
        // get branch mask, update branch stack
        for (int i = 0; i < `BR_STK_SZ; i++) begin
            if (n_branch_stk[i].valid) begin
                cur_bmask |= n_branch_stk[i].b_idx;
            end
        end
        for (int i = 0; i < `FETCH_WIDTH; i++) begin
            // @TODO: parallelize this... can't think of any easy way
            if (next_fetch_valids[i]) begin
                fetched_insts[i].valid = 1'b1;
                fetched_insts[i].PC = next_pc;
                next_inst_buffer[next_ib_tail] = {
                    1'b1,
                    fetched_insts[i].inst,
                    next_pc,
                    next_pc + 4,
                    fetched_insts[i].is_cond,
                    fetched_insts[i].is_uncond,
                    fetched_insts[i].is_func_call,
                    fetched_insts[i].is_return,
                    first_branch[i] && first_branch_predicted_taken ? predicted_taken_addr : next_pc + 4,
                    cur_bmask,
                    first_branch[i] ? new_bindex_bus : {`BR_STK_SZ{1'b0}}
                };
                if (first_branch_predicted_taken && first_branch[i]) begin
                    next_pc = predicted_taken_addr;
                end else begin
                    next_pc += 4;
                end
                if (first_branch[i]) begin
                    cur_bmask |= new_bindex_bus;
                end
                next_ib_tail = (next_ib_tail + 1) % `INST_BUFFER_SZ;
            end
        end
        // allocate branch stack
        for (int i = 0; i < `BR_STK_SZ; i++) begin
            if (should_copy_ebr & new_bindex_bus[i]) begin
                n_branch_stk[i].valid = 1'b1;
                n_branch_stk[i].b_idx = new_bindex_bus;
                n_branch_stk[i].bmask = cur_bmask;
            end
        end
        for (int i = 0; i < `DISPATCH_WIDTH; i++) begin
            if (bus.f_accepts[i]) begin
                next_ib_head = (next_ib_head + 1) % `INST_BUFFER_SZ;
            end
        end
    end

    always_ff @(posedge sys.clock) begin
        if (sys.reset) begin
            pc <= '0;
            ib_head <= '0;
            ib_tail <= '0;
            inst_buffer <= '0;
            // fetch_valids <= '0;
            branch_stk <= '0;
        end else begin
            pc <= next_pc;
            ib_head <= next_ib_head;
            ib_tail <= next_ib_tail;
            inst_buffer <= next_inst_buffer;
            // fetch_valids <= next_fetch_valids;
            branch_stk <= n_branch_stk;
        end
    end

endmodule
