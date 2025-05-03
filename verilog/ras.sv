`include "sys_defs.svh"
`include "cpuBusIF.svh"

module ras(
    input logic clock, reset,
    input logic is_dir_mis,
    input logic [$clog2(`BR_STK_SZ)-1:0] br_res_idx,
    input logic is_func_call,
    input logic is_return,
    input logic should_copy_ebr,
    input ADDR fetch_pc,
    input logic [$clog2(`BR_STK_SZ)-1:0] fetch_bindex,
    output ADDR pred_target_pc,
    output logic has_space
);

    localparam int RAS_SIZE_BIT_NUM = $clog2(`RAS_SIZE + 1);

    ADDR [`RAS_SIZE-1:0] stack, next_stack;
    logic [RAS_SIZE_BIT_NUM-1:0] top, next_top;
    ADDR [`BR_STK_SZ-1:0] [`RAS_SIZE-1:0] stack_copies, next_stack_copies;
    logic [`BR_STK_SZ-1:0] [RAS_SIZE_BIT_NUM:0] top_copies, next_top_copies;

    always_comb begin
        next_stack = stack;
        next_top = top;
        next_stack_copies = stack_copies;
        next_top_copies = top_copies;
        pred_target_pc = fetch_pc + 4;

        has_space = top < (`RAS_SIZE - 1);
        // branch resolution
        if (is_dir_mis) begin
            next_stack = stack_copies[br_res_idx];
            next_top = top_copies[br_res_idx];
        end
        // prediction
        if (is_func_call && next_top < `RAS_SIZE) begin
            next_stack[next_top] = fetch_pc + 4;
            next_top = next_top + 1;
        end else if (is_return && next_top > 0) begin
            pred_target_pc = next_stack[next_top - 1];
            next_top = next_top - 1;
        end
        if (should_copy_ebr) begin
            next_stack_copies[fetch_bindex] = next_stack;
            next_top_copies[fetch_bindex] = next_top;
        end
    end

    always_ff @(posedge clock) begin
        if (reset) begin
            stack <= '0;
            top <= 0;
            stack_copies <= '0;
            top_copies <= '0;
        end else begin
            stack <= next_stack;
            top <= next_top;
            stack_copies <= next_stack_copies;
            top_copies <= next_top_copies;
        end
    end

endmodule
