`include "sys_defs.svh"
`include "cpuBusIF.svh"

module rob (
    cpuBusIF sys_in,
    cpuBusIF d_branch_stk_in,
    cpuBusIF etb_in,
    cpuBusIF rob_dispatch,
    cpuBusIF rob_complete,
    cpuBusIF rob_retire,
    cpuBusIF cdb_branch_in,
    cpuBusIF rob_sq_retire
);

// variable defined
ROB_ENTRY [`ROB_SIZE-1:0]            rob; 
ROB_ENTRY [`ROB_SIZE-1:0]            next_rob;  
logic     [$clog2(`ROB_SIZE)-1:0]    head, tail;                     // tail always point to the next spot
logic     [$clog2(`ROB_SIZE)-1:0]    next_head, next_tail;           // tail always point to the next spot
logic     [$clog2(`ROB_SIZE):0]      count,next_count,tmp_count;
logic     [$clog2(`RETIRE_WIDTH+1)-1:0]                     retire_cnt;

logic     [`BR_STK_SZ-1:0][$clog2(`ROB_SIZE)-1:0]     tail_stack;
logic     [`BR_STK_SZ-1:0][$clog2(`ROB_SIZE)-1:0]    next_tail_stack;

logic halt_retired, n_halt_retired;

// combinational logics
logic [$clog2(`ROB_SIZE):0] retire_iteration_count;
logic [$clog2(`ROB_SIZE)-1:0] tmp_head;
logic [`RETIRE_WIDTH-1:0] is_complete, is_store, can_retire;
logic [`RETIRE_WIDTH-1:0] first_store, second_store;
logic [`RETIRE_WIDTH-1:0] is_halt, first_halt;

assign tmp_count = count - retire_cnt;
assign rob_dispatch.rob_spots = cdb_branch_in.br_res_state == BR_RES_MIS ? 0: ((`ROB_SIZE-tmp_count-1 >= `DISPATCH_WIDTH)? `DISPATCH_WIDTH : (`ROB_SIZE-tmp_count-1));

always_comb begin
    rob_retire.retire_old_tags = '0;
    next_rob = rob;
    next_head = head;
    next_tail = tail;
    next_count = count;
    retire_cnt = '0;
    rob_retire.retire_packets = 0;
    rob_sq_retire.retire_store = 0;
    // rob_retire.retire_new_dst_tags = 0;
    next_tail_stack=tail_stack;
    n_halt_retired = halt_retired;
    // --------- branch mis predict ---------
    if (cdb_branch_in.br_res_state == BR_RES_MIS) begin
        next_tail=tail_stack[cdb_branch_in.br_res_idx];
        next_count = (next_tail >= next_head) ? next_tail - next_head : `ROB_SIZE - next_head + next_tail;
    end 
    // --------- retire   ---------
    tmp_head = next_head;
    retire_iteration_count = next_count;
    for (int i = 0; i < `RETIRE_WIDTH; i++) begin
        is_complete[i] = rob[tmp_head].complete && (tmp_head != next_tail || retire_iteration_count == `ROB_SIZE);
        is_store[i] = rob[tmp_head].store;
        is_halt[i] = rob[tmp_head].halt;
        tmp_head = (tmp_head + 1) % `ROB_SIZE;
        retire_iteration_count = retire_iteration_count - 1;
        if (i > 0) begin
            is_complete[i] = is_complete[i] && is_complete[i-1];
        end
    end
    first_store = is_store & ~(is_store - 1);
    second_store = is_store & ~(first_store);
    second_store = second_store & ~(second_store - 1);
    can_retire = is_complete;
    if (halt_retired) begin
        can_retire = '0;
    end
    if (first_store) begin
        can_retire &= (second_store - 1);
    end
    first_halt = is_halt & ~(is_halt - 1);
    can_retire &= (first_halt - 1) | first_halt;
    for (int i = 0; i < `RETIRE_WIDTH; i++) begin
        if (first_store[i] && can_retire[i]) begin
            rob_sq_retire.retire_store = 1;
        end
    end
    
    if (~rob_sq_retire.retire_store_success) begin
        // mask out everything after first store
        can_retire &= (first_store - 1);
    end
    
    for(int i=0; i< `RETIRE_WIDTH; i++) begin
        // retire the oldest instruction
        if (can_retire[i]) begin // 
            n_halt_retired |= rob[next_head].halt;
            next_rob[next_head].complete=0;
            next_rob[next_head].t_new=0;
            rob_retire.retire_packets[i] = {rob[next_head].NPC,
                                rob_retire.retire_prf_datas[i],
                                rob[next_head].rd,
                                rob[next_head].halt,
                                rob[next_head].illegal,
                                rob[next_head].valid};
            rob_retire.retire_old_tags[i] = rob[next_head].t_old;
            next_head = (next_head == `ROB_SIZE-1) ? 0 : next_head + 1;
            next_count=next_count-1;
            retire_cnt = retire_cnt + 1;
        end
    end

    for(int i=0; i< `RETIRE_WIDTH; i++) begin
        rob_retire.retire_new_dst_tags[i] = {rob[(head+i)%`ROB_SIZE].t_new};
    end
    // --------- complete ---------
    // search the CDB tag in the ROB
    for (int i=0; i < `ROB_SIZE; i++) begin
        for (int j = 0; j < `CDB_WIDTH; j++) begin
            if (rob[i].t_new == etb_in.etb_tags[j] && etb_in.etb_tags[j] !== 0) begin
                next_rob[i].complete = 1;
                // next_rob[i].data = etb_in.etb_datas[j];
            end
        end
    end

    // --------- dispatch ---------
    for(int i=0; i< `DISPATCH_WIDTH; i++) begin
        if(rob_dispatch.f_accepts[i] == 1) begin
            next_rob[next_tail] = rob_dispatch.d_rob_entries[i];
            next_tail = (next_tail == `ROB_SIZE-1) ? 0 : next_tail+1;
            next_count = next_count + 1;

            if(d_branch_stk_in.d_br_stk_idx_valids[i]) next_tail_stack[d_branch_stk_in.d_br_stk_idxs[i]]=next_tail;
        end
    end
end

always_ff @(posedge sys_in.clock) begin 
    if (sys_in.reset) begin
        head <= 0;
        tail <= 0;
        count <= 0;
        tail_stack <= 0;
        rob <= '0; 
        halt_retired <= 0;
    end
    else begin
        rob <= next_rob;
        head <= next_head;
        tail <= next_tail;
        count <= next_count;
        tail_stack <= next_tail_stack;
        halt_retired <= n_halt_retired;
    end
end

endmodule // rob
