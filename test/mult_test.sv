`include "sys_defs.svh"

module testbench;
    logic clock, reset;
    DATA rs1, rs2;
    MULT_FUNC func;
    logic src_vld, src_rdy;
    logic cdb_arbit_gnt;
    logic cdb_raise_hand;
    TAG src_dest_tag;
    BMASK src_bmask;
    BR_RES_STATE mis_res_state;
    B_IDX mis_branch_idx;

    // CDB output
    CDB_REG_PACKET cdb_reg_packet;

    // 用于存储最终结果以做比较
    DATA final_result;
    DATA expected_result;

    // 例化待测的 4-stage mult 模块
    mult uut (
        .clock(clock),
        .reset(reset),
        .rs1(rs1),
        .rs2(rs2),
        .func(func),
        .src_vld(src_vld),
        .src_rdy(src_rdy),
        .src_dest_tag(src_dest_tag),
        .src_bmask(src_bmask),
        .cdb_reg_packet(cdb_reg_packet),
        .cdb_raise_hand(cdb_raise_hand),
        .cdb_arbit_gnt(cdb_arbit_gnt),
        .mis_res_state(mis_res_state),
        .mis_branch_idx(mis_branch_idx)
    );

    // 时钟
    always #5 clock = ~clock;

    // 每周期显示各阶段寄存器
    task display_stage_regs;
    #1;
        $display("\n------------ Pipeline State at Time %0t ------------", $time);
        $display("Stage0: src_vld=%b, src_rdy=%b, product_sum=%h, dst_vld=%b",
                 uut.stage0.src_vld, uut.stage0.src_rdy, uut.stage0.product_sum, uut.stage0.dst_vld);
        $display("Stage1: src_vld=%b, src_rdy=%b, product_sum=%h, dst_vld=%b",
                 uut.stage1.src_vld, uut.stage1.src_rdy, uut.stage1.product_sum, uut.stage1.dst_vld);
        $display("Stage2: src_vld=%b, src_rdy=%b, product_sum=%h, dst_vld=%b",
                 uut.stage2.src_vld, uut.stage2.src_rdy, uut.stage2.product_sum, uut.stage2.dst_vld);
        $display("Stage3: src_vld=%b, src_rdy=%b, product_sum=%h, dst_vld=%b",
                 uut.stage3.src_vld, uut.stage3.src_rdy, uut.stage3.product_sum, uut.stage3.dst_vld);
        $display("CDB: result=%h, valid_out=%b, cdb_raise_hand=%b, cdb_arbit_gnt=%b",
                 cdb_reg_packet.result, cdb_reg_packet.valid_out, cdb_raise_hand, cdb_arbit_gnt);
    endtask

    // 每周期显示各阶段的 product_sum
    always @(posedge clock) begin
        display_stage_regs();
    end

    // 测试过程
    initial begin
        clock = 0;
        reset = 1;
        src_vld = 0;
        cdb_arbit_gnt = 1;
        rs1 = 0;
        rs2 = 0;
        func = M_MUL;
        src_dest_tag = 0;
        src_bmask = 0;
        mis_res_state = BR_RES_INVALID;
        mis_branch_idx = 0;

        // 复位
        repeat (2) @(negedge clock);
        reset = 0;
        repeat (2)@(negedge clock);
        $finish;
        // 测试1：基础乘法
        @(negedge clock);
        src_vld      = 1;
        rs1          = 64'h3;
        rs2          = 64'h4;
        func         = M_MUL;
        src_dest_tag = 1;
        expected_result = 64'hC;

        @(negedge clock);
        src_vld = 0;
        repeat (4) @(negedge clock);
        final_result = cdb_reg_packet.result;
        if (final_result !== expected_result)
            $display("Test1 Failed: Expected=%h, Got=%h", expected_result, final_result);
        else
            $display("Test1 Passed!");

        // 测试2：若干周期无输入
        repeat (4) @(negedge clock); // 空闲4周期
        if (cdb_reg_packet.result !== 64'h0)
            $display("Test2 Check: result changed unexpectedly=%h", cdb_reg_packet.result);

        // 测试3：cdb_arbit_gnt 抖动
        @(negedge clock);
        src_vld  = 1;
        rs1      = 64'h5;
        rs2      = 64'h6;
        func     = M_MUL;
        src_dest_tag = 2;
        expected_result = 64'h1E;
        cdb_arbit_gnt = 0; // 试图阻塞
        @(negedge clock);
        src_vld  = 0;
        cdb_arbit_gnt = 1;
        repeat (6) @(negedge clock);
        final_result = cdb_reg_packet.result;
        if (final_result !== expected_result)
            $display("Test3 Failed: Expected=%h, Got=%h", expected_result, final_result);
        else
            $display("Test3 Passed!");

        // 测试4：BR_RES_MIS 与 bmask
        @(negedge clock);
        src_vld      = 1;
        rs1          = 64'h7;
        rs2          = 64'h8;
        func         = M_MUL;
        src_dest_tag = 3;
        src_bmask    = 4'b0010; // 当前指令依赖某分支
        mis_res_state = BR_RES_MIS;
        mis_branch_idx = 1;    // 命中 bmask[1]
        // 预期结果将被取消
        @(negedge clock);
        src_vld       = 0;
        mis_res_state = BR_RES_INVALID;
        repeat (5) @(negedge clock);
        final_result = cdb_reg_packet.result;
        if (final_result !== 64'h0)
            $display("Test4 Failed: Unexpected result=%h", final_result);
        else
            $display("Test4 Passed!");

        // 测试5：多次正常操作
        @(negedge clock);
        src_vld      = 1;
        rs1          = 64'h9;
        rs2          = 64'hA;
        func         = M_MUL;
        src_dest_tag = 4;
        src_bmask    = 0;
        expected_result = 64'h5A;
        @(negedge clock);
        src_vld = 0;
        repeat (4) @(negedge clock);
        final_result = cdb_reg_packet.result;
        if (final_result !== expected_result)
            $display("Test5 Failed: Expected=%h, Got=%h", expected_result, final_result);
        else
            $display("Test5 Passed!");

        // 结束
        $finish;
    end
endmodule

