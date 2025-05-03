`include "sys_defs.svh"



// 例：在 fu_tb.sv 或公共包文件里定义


module fu_tb;
    // Parameters
    parameter ALU_CNT = 2;
    parameter MULT_CNT = 1;
    parameter BR_CNT = 1;

    // Testbench signals
    logic clock, reset;

    // ALU inputs
    logic    [ALU_CNT-1:0] alu_valid_in;
    ALU_FUNC [ALU_CNT-1:0] alu_func;
    DATA     [ALU_CNT-1:0] alu_data1, alu_data2;
    BMASK    [ALU_CNT-1:0] alu_bmask;
    TAG      [ALU_CNT-1:0] alu_dst_tag;
    logic    [ALU_CNT-1:0] alu_request_cdb;
    
    // ALU outputs
    logic    [ALU_CNT-1:0] alu_valid_back;

    // MULT inputs
    logic    [MULT_CNT-1:0] mult_valid_in;
    MULT_FUNC[MULT_CNT-1:0] mult_func;
    DATA     [MULT_CNT-1:0] mult_data1, mult_data2;
    BMASK    [MULT_CNT-1:0] mult_bmask;
    TAG      [MULT_CNT-1:0] mult_dst_tag;
    
    // MULT outputs
    logic    [MULT_CNT-1:0] mult_rdy;

    // Branch inputs
    logic   branch_valid_in;
    ADDR    branch_predict_addr;
    B_IDX   branch_idx;
    BMASK   branch_bmask;
    DATA    branch_data1, branch_data2;
    TAG     branch_dst_tag;
    ADDR    PC;
    logic   [2:0] branch_func;
    DATA    branch_offset;
    logic   is_uncond_branch, is_halt;
    logic   branch_request_cdb;
    // Branch outputs
    logic   branch_valid_back;

    // Misprediction control signals
    BR_RES_STATE mis_res_state;
    B_IDX        mis_branch_idx;

    // cdb tag bus
    TAG   [1:0]  etb_tag;
    BMASK [1:0]  etb_bmask;
    TAG   [1:0]  issue_read_tag;
    DATA  [1:0]  bypass_data_to_issue;

    // cdb reg
    CDB_REG_PACKET [1:0] cdb_reg_out;
    BR_RES_STATE cdb_branch_res_state;
    B_IDX cdb_branch_idx;
    ADDR cdb_branch_true_addr;  
    TAG  cdb_branch_dst_tag;

    // debug signal
    logic [1:0][3:0] dbg_gnt_bus_reg;
    logic [63:0]     product01, product12, product23;


    // Instantiate FU
    fu #(
        .ALU_CNT(ALU_CNT),
        .MULT_CNT(MULT_CNT),
        .BR_CNT(BR_CNT)
    ) dut (
        // implement the port
        .clock(clock),
        .reset(reset),

        // ALU connections
        .alu_valid_in(alu_valid_in),
        .alu_func(alu_func),
        .alu_data1(alu_data1),
        .alu_data2(alu_data2),
        .alu_bmask(alu_bmask),
        .alu_dst_tag(alu_dst_tag),
        .alu_request_cdb(alu_request_cdb),
        .alu_valid_back(alu_valid_back),

        // MULT connections
        .mult_valid_in(mult_valid_in),
        .mult_func(mult_func),
        .mult_data1(mult_data1),
        .mult_data2(mult_data2),
        .mult_bmask(mult_bmask),
        .mult_dst_tag(mult_dst_tag),
        .mult_rdy(mult_rdy),

        // Branch connections
        .branch_valid_in(branch_valid_in),
        .branch_predict_addr(branch_predict_addr),
        .branch_idx(branch_idx),
        .branch_bmask(branch_bmask),
        .branch_data1(branch_data1),
        .branch_data2(branch_data2),
        .branch_dst_tag(branch_dst_tag),
        .PC(PC),
        .branch_func(branch_func),
        .branch_offset(branch_offset),
        .is_uncond_branch(is_uncond_branch),
        .is_halt(is_halt),
        .branch_valid_back(branch_valid_back),
        .branch_request_cdb(branch_request_cdb),
        .mis_res_state(mis_res_state),
        .mis_branch_idx(mis_branch_idx),

        // cdb output
        .etb_tag(etb_tag),
        .etb_bmask(etb_bmask),
        .bypass_data_to_issue(bypass_data_to_issue),
        .cdb_reg_out(cdb_reg_out),
        .cdb_branch_res_state(cdb_branch_res_state),
        .cdb_branch_idx(cdb_branch_idx),
        .cdb_branch_true_addr(cdb_branch_true_addr),
        .cdb_branch_dst_tag(cdb_branch_dst_tag),

        //debug signal
        .dbg_gnt_bus_reg(dbg_gnt_bus_reg),
        .dbg_mult_product_stage01(product01),
        .dbg_mult_product_stage12(product12),
        .dbg_mult_product_stage23(product23)

    );

    // Clock generation
    always #5 clock = ~clock;
    // output(comb): alu_valid_back, mult_valid_back, branch_valid_back;

    always @(posedge clock ) begin
        $display("###########-----------time:[%0t] ", $time);
        print_cdb_comb();
        print_cdb_ff();
    end

    task print_cdb_comb;
        // 可以自由调整显示格式、进制等
        $display("-----etb port------");
        // help me print the etb tag, mask, data into a table like format, we have two etb ports in total, with table head in one line and one set of etb each line
        $display("etb \t tag \t mask \t data");
        $display("etb:0 \t %0d \t %b \t %h", etb_tag[0], etb_bmask[0], bypass_data_to_issue[0]);
        $display("etb:1 \t %0d \t %b \t %h", etb_tag[1], etb_bmask[1], bypass_data_to_issue[1]);
    endtask
    task print_cdb_ff;
        // 打印 cdb_reg_out 数组的每一路
        #1;
        $display("-----MULT middle stage-----");
        $display("01: %h \t 12: %h \t 23: %h", product01, product12, product23);

        $display("MAAB----arbiter bus reg------");
        $display("%b \n%b", dbg_gnt_bus_reg[0], dbg_gnt_bus_reg[1]);

        $display("-----cdb_reg_port------");
        $display("cdb \t result \t tag \t bmask \t valid_out");
        for (int i = 0; i < 2; i++) 
            $display("cdb:%0d \t %h \t %0d \t %b \t %b", i, cdb_reg_out[i].result, cdb_reg_out[i].dst_tag_out, cdb_reg_out[i].dst_bmask, cdb_reg_out[i].valid_out);

        $display("----- branch broadcast packet -----");
        $display("  branch_res_state = %s", cdb_branch_res_state);
        $display("  branch_idx       = %d ", cdb_branch_idx);
        $display("  branch_true_addr = %0d ", cdb_branch_true_addr);
        $display("  branch_dst_tag   = %0d ", cdb_branch_dst_tag);
        $display("--------------------------------------------------\n\n");
    endtask
    task initiate ;
        alu_valid_in = '0;
        alu_func = '0;
        alu_data1 = '0;
        alu_data2 = '0;
        alu_bmask = '0;
        alu_dst_tag = '0;
        alu_request_cdb = '0;

        mult_valid_in = '0;
        mult_func = '0;
        mult_data1 = '0;
        mult_data2 = '0;
        mult_bmask = '0;
        mult_dst_tag = '0;

        branch_valid_in = 0;
        branch_predict_addr = '0;
        branch_idx = '0;
        branch_bmask = '0;
        branch_data1 = '0;
        branch_data2 = '0;
        branch_dst_tag = '0;
        PC = '0;
        branch_func = '0;
        branch_offset = '0;
        is_uncond_branch = 0;
        is_halt = 0;
        branch_request_cdb = 0;

        mis_res_state = BR_RES_INVALID;
        mis_branch_idx = '0;
    endtask
    // Testbench stimulus
    initial begin
        // Initialize all the input signals
        clock = 0;
        reset = 1;
        initiate();
        
        @(negedge clock);//@(posedge clock);
        #1;
        reset = 0;
/*
        // Test case 1: ALU operation example

        @(negedge clock);
        alu_request_cdb = 2'b11;
        branch_request_cdb = 1'b0;
        $display("!!!!!!!! Test 1: 2 alus requested, wishing to receive 2 alu gnt");
        #1;
        $display("alu_valid_back: %b   ----- should be 11", alu_valid_back);
            


        @(negedge clock); // modify input at negedge clock
        alu_request_cdb = 2'b00;
        alu_valid_in = 2'b11;
        alu_func[0]  = ALU_ADD;
        alu_func[1]  = ALU_ADD;
        alu_data1 = {32'h1, 32'h4}; // alu[1:0]
        alu_data2 = {32'h2, 32'h3}; // psel first [1], the [0]
        alu_bmask[0] = 0;
        alu_bmask[1] = 0;
        alu_dst_tag = {6'd1, 6'd2};

        $display("!!!!!!!! Test 1: 2 alu data inputed. ");
        @(posedge clock);
        

        
        // Test case 2: 2 alu 1 branch, gnt 1 alu 1 branch (priority)
        // MULT ALU ALU BRANCH (psel)
        @(negedge clock);
        alu_request_cdb = 2'b11;
        branch_request_cdb = 1'b1;
        $display("!!!!!!!! Test 2: 2 alu and 1 branch req. gnt should be 0101");

        @(posedge clock);

        $display("!!!!!!!! Test 2: 1 alu and 1 branch data inputed");
        $display("!!!!!!!! Begin Test 3: req 1alu and 1branch");
        @(negedge clock); // modify input at negedge clock
        alu_request_cdb = 2'b01;
        branch_request_cdb = 1'b1;
        alu_valid_in = 2'b10;
        alu_func[0]  = ALU_ADD;
        alu_func[1]  = ALU_ADD;
        alu_data1 = {32'h1, 32'h0}; // alu[1:0]
        alu_data2 = {32'h2, 32'h0}; // psel first [1], the [0]
        alu_bmask[0] = 4'b0101;
        alu_bmask[1] = 4'b1010;
        alu_dst_tag  = {6'd1, 6'd2};

        branch_valid_in     = 1;
        branch_predict_addr = 32'd15;
        branch_idx          = 4'b1000;
        branch_bmask        = 4'b0001;
        branch_data1        = 32'd3;
        branch_data2        = 32'd3;
        branch_dst_tag      = 3;
        PC                  = 1155;
        branch_func         = 0;     // equal
        branch_offset       = 8; // PC + offset
        is_uncond_branch    = 0;
        is_halt             = 0;

        @(posedge clock);
        @(negedge clock);

        
        // Testcase 3:
        $display("!!!!!!! Testcase 3: Mispredict input");
        @(negedge clock); // modify input at negedge clock
        mis_res_state = BR_RES_MIS;
        mis_branch_idx = 4'b0001;

        alu_valid_in = 2'b01;
        alu_func[0]  = ALU_ADD;
        alu_data1 = {32'h0, 32'h4}; // alu[1:0]
        alu_data2 = {32'h0, 32'h3}; // psel first [1], the [0]
        alu_bmask[0] = 4'b0001;

        alu_dst_tag  = {6'd0, 6'd2};

        branch_valid_in     = 1;
        branch_predict_addr = 32'd15;
        branch_idx          = 4'b0001;
        branch_bmask        = 4'b0011;
        branch_data1        = 32'd3;
        branch_data2        = 32'd3;
        branch_dst_tag      = 6'd3;
        PC                  = 32'd3;
        branch_func         = 0;     // equal
        branch_offset       = 32'd8; // PC + 4 + offset
        is_uncond_branch    = 0;
        is_halt             = 0;

        @(negedge clock);
*/
        // Testcase 4:
        @(negedge clock);
        initiate();
        
        mult_valid_in = '1;
        mult_func = '0;
        mult_data1 = 10;
        mult_data2 = 16;
        mult_bmask = 4'b1111;
        mult_dst_tag = 15;

        
        @(negedge clock);
        initiate();
        @(negedge clock);
        $display("Begin of test 4: 2 alu and 1 Mult req. gnt should be 1010");
        alu_request_cdb = 2'b01;
        @(negedge clock);
        $display("Testcase 4: 2 alu and 1 Mult");
        alu_request_cdb = 2'b00;
        mis_res_state = BR_RES_HIT;
        branch_idx = 4'b0001;

        alu_valid_in = 2'b01;
        alu_func[0]  = ALU_ADD;
        alu_func[1]  = ALU_ADD;
        alu_data1 = {32'h1, 32'h4}; // alu[1:0]
        alu_data2 = {32'h2, 32'h3}; // psel first [1], the [0]
        alu_bmask[0] = 4'b0001;
        alu_bmask[1] = 4'b0001;
        alu_dst_tag  = {6'd1, 6'd2};

        @(negedge clock);

        $finish;
    end

endmodule