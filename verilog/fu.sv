`include "sys_defs.svh"
`include "cpuBusIF.svh"

module arbiter #(
localparam REQ_CNT = `NUM_FU_ALU+`NUM_FU_MULT+`NUM_FU_BR+`NUM_FU_LOAD_OUT+`NUM_FU_STORE) (
    input clock,reset, 
    input TAG [`NUM_FU_ALU-1:0] alu_req_tags,
    input TAG [`NUM_FU_MULT-1:0] mult_req_tags,
    input TAG [`NUM_FU_BR-1:0] branch_req_tags,
    input TAG [`NUM_FU_LOAD_OUT-1:0] load_req_tags,
    input TAG [`NUM_FU_STORE-1:0] store_req_tags,

    // output to issue and fu
    output logic [`NUM_FU_ALU-1:0] alu_gnt,
    output logic [`NUM_FU_MULT-1:0] mult_gnt,
    output logic [`NUM_FU_BR-1:0] branch_gnt,
    output logic [`NUM_FU_LOAD_OUT-1:0] load_gnt,
    output logic [`NUM_FU_STORE-1:0] store_gnt,


    output logic [`CDB_WIDTH-1:0][REQ_CNT-1:0] gnt_bus_reg, 
    output logic [`CDB_WIDTH-1:0][REQ_CNT-1:0] gnt_bus_current_stage// the arbit result in the same cycle

);
    // localparam REQ_CNT = ALU_CNT+`NUM_FU_MULT+`NUM_FU_BR;
    logic [REQ_CNT-1:0] req;
    logic [REQ_CNT-1:0] gnt_result;
    logic [`CDB_WIDTH-1:0][REQ_CNT-1:0] gnt_bus;

    assign {load_gnt,store_gnt,mult_gnt,alu_gnt,branch_gnt} = gnt_result;
    assign gnt_bus_current_stage = gnt_bus;

    always_comb begin
        req = '0;
        req[0] = branch_req_tags[0] != 0;
        for (int i = 0; i < `NUM_FU_ALU; i=i+1) begin
            req[`NUM_FU_BR+i] = (alu_req_tags[i] != 0);
        end
        for (int i = 0; i < `NUM_FU_MULT; i=i+1) begin
            req[`NUM_FU_ALU+`NUM_FU_BR+i] = (mult_req_tags[i] != 0);
        end
        for (int i = 0; i < `NUM_FU_STORE; i=i+1) begin
            req[`NUM_FU_MULT+`NUM_FU_ALU+`NUM_FU_BR+i] = (store_req_tags[i] != 0);
        end
        for (int i=0; i<`NUM_FU_LOAD_OUT; i=i+1) begin
            req[`NUM_FU_MULT+`NUM_FU_ALU+`NUM_FU_BR+`NUM_FU_STORE+i] = (load_req_tags[i] != 0);
        end

    end

    logic empty;
    psel_gen #(
        .WIDTH(REQ_CNT),
        .REQS(`CDB_WIDTH)
    ) psel (
        .req(req),
        .gnt(gnt_result),
        .gnt_bus(gnt_bus)
    );

    always_ff @(posedge clock) begin
        if(reset) begin
            gnt_bus_reg <= 0;
        end
        else begin 
            gnt_bus_reg <= gnt_bus;
        end
    end
endmodule // arbiter


//#(parameter ALU_CNT = 2, MULT_CNT= 1, `NUM_FU_BR=1, LD_CNT_IN=1,LD_CNT_OUT=4, ST_CNT=1)
module fu (
    cpuBusIF sys_in,
    cpuBusIF cdb_branch_in,
    cpuBusIF cdb_issue_select,
    cpuBusIF fu_receive,
    cpuBusIF etb_out,
    cpuBusIF cdb_branch_out,
    cpuBusIF cdb_wb,
    cpuBusIF fu_sq_fwd,
    cpuBusIF fu_sq_store,
    cpuBusIF fu_cache
); 
    CDB_REG_PACKET  [`NUM_FU_OUT-1:0]       tmp_all_fu_packet; // this is a wire before select
    BR_RES_STATE                        tmp_cdb_branch_res_stat;
    B_IDX                               tmp_cdb_branch_idx;
    ADDR                                tmp_cdb_branch_target;
    logic                               tmp_cdb_branch_is_taken;
    logic                               tmp_cdb_branch_is_cond;
    TAG [ `CDB_WIDTH-1:0] etb_tag_regs, n_etb_tag_regs;              
    
    // Arbiter signals
    // GNT signals from arbiter, directly output to issue
    // logic [ALU_CNT-1:0] alu_gnt;
    logic [`NUM_FU_MULT-1:0] mult_gnt;
    // logic [`NUM_FU_BR-1:0] branch_gnt;
    // request signal from mult, others from input
    TAG [`NUM_FU_MULT-1:0] mult_request_tags_cdb;
    TAG [`NUM_FU_LOAD_OUT-1:0] load_request_tags_cdb;
    logic [`NUM_FU_LOAD_OUT-1:0] load_gnt;
    // the cdb register is the gnt bus. 
    logic [`CDB_WIDTH-1:0][`NUM_FU_OUT-1:0] gnt_bus,gnt_bus_current_stage; // mult, alu, branch
    logic has_branch;

    genvar i;
    generate
        for (i = 0; i < `NUM_FU_ALU; i++) begin : alu_units
            alu alu_inst (
                .opa(fu_receive.alu_ex_insts[i].data1),
                .opb(fu_receive.alu_ex_insts[i].data2),
                .alu_func(fu_receive.alu_ex_insts[i].func),
                .valid_in(fu_receive.alu_ex_insts[i].valid),
                .dst_tag_in(fu_receive.alu_ex_insts[i].dst_tag),
                .src_bmask(fu_receive.alu_ex_insts[i].bmask),
                .cdb_reg_packet(tmp_all_fu_packet[`NUM_FU_BR+i]),
                .mis_res_state(cdb_branch_in.br_res_state),
                .mis_branch_idx(cdb_branch_in.br_res_idx_bus)
            );
        end
    endgenerate
    // Instantiate MULT modules
    generate
        for (i = 0; i < `NUM_FU_MULT; i++) begin : mult_units
            mult mult_inst (
                .reset(sys_in.reset),
                .clock(sys_in.clock),
                .rs1(fu_receive.mult_ex_insts[i].data1),
                .rs2(fu_receive.mult_ex_insts[i].data2),
                .func(fu_receive.mult_ex_insts[i].func[2:0]),
                .src_vld(fu_receive.mult_ex_insts[i].valid),
                .src_rdy(cdb_issue_select.mult_unit_readies[i]),
                .src_dest_tag(fu_receive.mult_ex_insts[i].dst_tag),
                .src_bmask(fu_receive.mult_ex_insts[i].bmask),
                .cdb_reg_packet(tmp_all_fu_packet[`NUM_FU_BR+`NUM_FU_ALU+i]),
                .cdb_raise_hand_tag(mult_request_tags_cdb[i]),
                .cdb_arbit_gnt(mult_gnt[i]),
                .mis_res_state(cdb_branch_in.br_res_state),
                .mis_branch_idx(cdb_branch_in.br_res_idx_bus)
            );
        end
    endgenerate

    // Instantiate BRANCH module
    branch branch_inst (
        .rs1(fu_receive.branch_ex_inst.data1),
        .rs2(fu_receive.branch_ex_inst.data2),
        .func(fu_receive.branch_ex_inst.branch_func),
        .predict_addr(fu_receive.branch_ex_inst.predicted_addr),
        .dst_tag_in(fu_receive.branch_ex_inst.dst_tag),
        .src_bmask(fu_receive.branch_ex_inst.bmask),
        .branch_idx(fu_receive.branch_ex_inst.bindex),
        .valid_in(fu_receive.branch_ex_inst.valid),
        .PC(fu_receive.branch_ex_inst.PC),
        .offset(fu_receive.branch_ex_inst.offset),
        .mis_res_state(cdb_branch_in.br_res_state),
        .mis_branch_idx(cdb_branch_in.br_res_idx_bus),
        .is_halt(fu_receive.branch_ex_inst.is_halt),
        .is_uncond_branch(fu_receive.branch_ex_inst.is_uncond_branch),
        // .is_jal(fu_receive.branch_ex_inst.is_jal),
        .is_jalr(fu_receive.branch_ex_inst.is_jalr),
        .cdb_reg_packet(tmp_all_fu_packet[0]),
        .branch_target_true_addr_out(tmp_cdb_branch_target),
        .branch_result_state_out(tmp_cdb_branch_res_stat),
        .branch_idx_out(tmp_cdb_branch_idx),
        .is_branch_taken_out(tmp_cdb_branch_is_taken)
    );

    load_station load_station_non_blocking_inst (
        .clock(sys_in.clock),
        .reset(sys_in.reset),
        .mis_res_state(cdb_branch_in.br_res_state),
        .mis_branch_idx(cdb_branch_in.br_res_idx_bus),

        .opa(fu_receive.load_ex_inst.opa),
        .opb(fu_receive.load_ex_inst.opb),
        .dst_tag_in(fu_receive.load_ex_inst.dst_tag),
        .bmask_in(fu_receive.load_ex_inst.bmask),
        .src_vld(fu_receive.load_ex_inst.valid),
        .st_pos_in(fu_receive.load_ex_inst.st_pos),
        .mem_size_in(fu_receive.load_ex_inst.size),
        .is_unsigned(fu_receive.load_ex_inst.is_unsigned),

        .src_rdy(cdb_issue_select.load_unit_ready),

        // forward to sq
        .addr_fwd(fu_sq_fwd.fwd_addr),
        .valid_fwd(fu_sq_fwd.fwd_valid),
        .st_pos_fwd(fu_sq_fwd.fwd_pos),
        // .mem_size_fwd(mem_size_fwd),
        .data_fwd_in(fu_sq_fwd.fwd_data_return),
        .mask_fwd_in(fu_sq_fwd.fwd_data_return_mask),

        // ports with cache
        .cache_addr_out     (fu_cache.load_arbit_addr),
        .cache_valid_out    (fu_cache.load_arbit_valid),
        .cache_size_out     (fu_cache.load_arbit_size),

        .cache_sent         (fu_cache.load_arbit_sent),
        .cache_state        (fu_cache.load_arbit_state),
        .cache_alloc_tag    (fu_cache.load_arbit_alloc_tag),
        .cache_hit_data     (fu_cache.load_arbit_hit_data),
        .cache_broad_valid  (fu_cache.load_arbit_broad_valid),
        .cache_broad_tag    (fu_cache.load_arbit_broad_tag),
        .cache_broad_data   (fu_cache.load_arbit_broad_data),

        // arbit
        .arbit_tag_out(load_request_tags_cdb),
        .arbit_gnt(load_gnt),
        // output to cdb
        .cdb_reg_packet(tmp_all_fu_packet[`NUM_FU_OUT-1-:`NUM_FU_LOAD_OUT])
        
    );

    // Instantiate store unit
    store_unit store_unit_inst (
        .st_data_in(fu_receive.st_ex_inst.data_in),
        .opa(fu_receive.st_ex_inst.opa),
        .opb(fu_receive.st_ex_inst.opb),
        .dst_tag_in(fu_receive.st_ex_inst.dst_tag),
        .src_bmask(fu_receive.st_ex_inst.bmask),
        .st_valid_in(fu_receive.st_ex_inst.valid),
        .st_pos_in(fu_receive.st_ex_inst.st_pos),
        .st_size_in(fu_receive.st_ex_inst.size),

        .st_data_out(fu_sq_store.st_sq_data),
        .st_addr_out(fu_sq_store.st_sq_addr),
        .st_size_out(fu_sq_store.st_sq_size),
        .st_pos_out(fu_sq_store.st_sq_pos),
        .st_valid_out(fu_sq_store.st_sq_valid),
        .cdb_reg_packet(tmp_all_fu_packet[`NUM_FU_OUT-1-`NUM_FU_LOAD_OUT-:`NUM_FU_STORE]),

        .mis_res_state(cdb_branch_in.br_res_state),
        .mis_branch_idx(cdb_branch_in.br_res_idx_bus)
    );



    // Instantiate arbiter
    arbiter arbiter_inst (
        .clock(sys_in.clock),
        .reset(sys_in.reset),
        .alu_req_tags(cdb_issue_select.alu_req_dst_tags),
        .mult_req_tags(mult_request_tags_cdb),
        .branch_req_tags(cdb_issue_select.branch_req_dst_tag),
        .load_req_tags(load_request_tags_cdb),
        .store_req_tags(cdb_issue_select.store_req_dst_tag),

        .alu_gnt(cdb_issue_select.alu_issue_gnts),
        .mult_gnt(mult_gnt),
        .branch_gnt(cdb_issue_select.branch_issue_gnt),
        .load_gnt(load_gnt),
        .store_gnt(cdb_issue_select.store_issue_gnt),
        .gnt_bus_reg(gnt_bus),
        .gnt_bus_current_stage(gnt_bus_current_stage)
    );

    assign tmp_cdb_branch_is_cond = (fu_receive.branch_ex_inst.valid 
        && ~fu_receive.branch_ex_inst.is_uncond_branch
        && ~fu_receive.branch_ex_inst.is_halt
    );

    // first determine which fu to choose by gnt_bus
    CDB_REG_PACKET [`CDB_WIDTH-1:0] tmp_cdb_reg_out;
    always_comb begin
        tmp_cdb_reg_out = '0;
        has_branch = 0;
        for(int i=0;i< `CDB_WIDTH;i=i+1) begin
            if(gnt_bus[i]!=0) begin
                for (int j = 0; j < `NUM_FU_OUT; j=j+1) begin
                    if (gnt_bus[i][j]) begin
                        tmp_cdb_reg_out[i] = tmp_all_fu_packet[j];
                    end
                end
            end
            else tmp_cdb_reg_out[i].dst_tag_out = 0;
            // then assign the tag and bmask to etb
            etb_out.etb_tags[i]=etb_tag_regs[i];
            etb_out.etb_bmasks[i]=tmp_cdb_reg_out[i].dst_bmask;
            etb_out.etb_datas[i]=tmp_cdb_reg_out[i].result;
            has_branch |=gnt_bus[i][0];
        end
        
    end

    // save tags based on the information of arbiter in arbit stage. 
    always_comb begin
        n_etb_tag_regs = '0;
        for (int i = 0; i < `CDB_WIDTH; i++) begin
            if (gnt_bus_current_stage[i][0]) begin
                n_etb_tag_regs[i] = cdb_issue_select.branch_req_dst_tag;
            end else begin
                for (int j = 0; j < `NUM_FU_ALU; j++) begin
                    if (gnt_bus_current_stage[i][j+1]) begin
                        n_etb_tag_regs[i] = cdb_issue_select.alu_req_dst_tags[j];
                    end
                end
                for (int j = 0; j < `NUM_FU_MULT; j++) begin
                    if (gnt_bus_current_stage[i][j+`NUM_FU_ALU+1]) begin
                        n_etb_tag_regs[i] = mult_request_tags_cdb[j];
                    end
                end
                for (int j = 0; j < `NUM_FU_STORE; j++) begin
                    if (gnt_bus_current_stage[i][j+`NUM_FU_ALU+`NUM_FU_MULT+1]) begin
                        n_etb_tag_regs[i] = cdb_issue_select.store_req_dst_tag;
                    end
                end
                for (int j = 0; j < `NUM_FU_LOAD_OUT; j++) begin
                    if (gnt_bus_current_stage[i][j+`NUM_FU_STORE+`NUM_FU_ALU+`NUM_FU_MULT+1]) begin
                        n_etb_tag_regs[i] = load_request_tags_cdb[j];
                    end
                end
            end
        end
    end

    logic [$clog2(`BR_STK_SZ)-1:0] n_br_res_idx;
    always_comb begin
        n_br_res_idx = '0;
        for (int j = 0; j < `BR_STK_SZ; j++) begin
            if (tmp_cdb_branch_idx[j]) begin
                n_br_res_idx = j;
            end
        end
    end

    // Fill cdb_reg based on arbiter selection
    always_ff @(posedge sys_in.clock) begin
        if (sys_in.reset) begin
            cdb_wb.cdb_reg_packets <= 0;
            cdb_branch_out.br_res_state <= BR_RES_INVALID;
            etb_tag_regs <= 0;
            cdb_branch_out.br_res_idx_bus <= 0;
            cdb_branch_out.br_res_idx<= 0;
            cdb_branch_out.cdb_branch_actual_pc <= 0;
            cdb_branch_out.br_res_inst_pc <= 0;
            cdb_branch_out.br_res_is_taken <= 0;
        end else begin
            cdb_wb.cdb_reg_packets <= tmp_cdb_reg_out;
            if(has_branch) begin
                cdb_branch_out.br_res_state <= tmp_cdb_branch_res_stat;
                cdb_branch_out.br_res_idx_bus <= tmp_cdb_branch_idx;
                cdb_branch_out.br_res_idx <= n_br_res_idx;
                cdb_branch_out.cdb_branch_actual_pc <= tmp_cdb_branch_target;
                cdb_branch_out.br_res_inst_pc <= fu_receive.branch_ex_inst.PC;
                cdb_branch_out.br_res_is_taken <= tmp_cdb_branch_is_taken;
                cdb_branch_out.br_res_is_cond <= tmp_cdb_branch_is_cond;
            end else  begin
                cdb_branch_out.br_res_state <= BR_RES_INVALID;
                cdb_branch_out.br_res_idx <= 0;
                cdb_branch_out.br_res_is_cond <= 0;
            end
            etb_tag_regs <= n_etb_tag_regs;
        end
    end
endmodule
