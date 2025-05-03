/**
    Issue Register, i.e., issue_execution_register
        - Informs RS what instructions can be issued (through alu avails, etc.)
        - After cdb arbiter grants one-clcye functions like ALU, 
            accept granted instructions
        - Meanwhile, read data from either CDB Register (internal forward from EX), 
            or PRF (internal forward from Complete, or just normally).
            Selection is based on if the src tag matches the CDB tag broadcast by CDB arbiter
*/

`include "sys_defs.svh"
`include "ISA.svh"
`include "cpuBusIF.svh"

module isReg #(
    parameter ALU_CNT = 2, MULT_CNT= 1/*, BR_CNT = 1*/
) (
    cpuBusIF sys_in,
    cpuBusIF etb_in,
    cpuBusIF cdb_branch_in,
    cpuBusIF sreg_issue,
    cpuBusIF sreg_issue_data_read,
    cpuBusIF sreg_execute
);

    ISS_INST_ALU    [ALU_CNT-1:0]       alu_inst_reg, n_alu_inst_reg;
    ISS_INST_MUL    [MULT_CNT-1:0]      mult_inst_reg, n_mult_inst_reg;
    ISS_INST_BR                         branch_inst_reg, n_branch_inst_reg;
    ISS_INST_MEM                        load_inst_reg, n_load_inst_reg;
    ISS_INST_MEM                        store_inst_reg, n_store_inst_reg;

    DATA            [ALU_CNT-1:0]       alu_data1_reg, n_alu_data1_reg, alu_src_data1;
    DATA            [ALU_CNT-1:0]       alu_data2_reg, n_alu_data2_reg, alu_src_data2;
    DATA            [MULT_CNT-1:0]      mult_data1_reg, n_mult_data1_reg;
    DATA            [MULT_CNT-1:0]      mult_data2_reg, n_mult_data2_reg;
    DATA                                branch_data1_reg, branch_data2_reg, n_branch_data1_reg, n_branch_data2_reg;
    DATA                                load_data1_reg, load_data2_reg, n_load_data1_reg, n_load_data2_reg;
    DATA                                store_data1_reg, store_data2_reg, n_store_data1_reg, n_store_data2_reg;
    // specifically for data to store
    DATA                                store_data_reg, n_store_data_reg;
    function automatic logic getSrcTagInCdb(
        input TAG tag, 
        input TAG [`CDB_WIDTH-1:0] cdb_tags
    );
        logic src_in_cdb = 0;
        for (int i = 0; i < `CDB_WIDTH; i++) begin
            src_in_cdb |= (tag == cdb_tags[i]);
        end
        src_in_cdb &= (tag != 0);
        // $display("src_in_cdb is %0b", src_in_cdb);
        return src_in_cdb;
    endfunction

    always_comb begin
        // zero initialize all combination internal signals
        n_alu_inst_reg = '0;
        n_mult_inst_reg = '0;
        n_branch_inst_reg = '0;
        n_load_inst_reg = '0;
        n_store_inst_reg = '0;
        n_alu_data1_reg = '0;
        n_alu_data2_reg = '0;
        n_mult_data1_reg = mult_data1_reg;
        n_mult_data2_reg = mult_data2_reg;
        n_branch_data1_reg = '0;
        n_branch_data2_reg = '0;
        n_load_data1_reg = load_data1_reg;
        n_load_data2_reg = load_data2_reg;
        n_store_data1_reg = '0;
        n_store_data2_reg = '0;
        n_store_data_reg = '0;
        // zero initialize all combinational outputs
        sreg_execute.alu_ex_insts = '0;
        sreg_execute.mult_ex_insts = '0;
        sreg_execute.branch_ex_inst = '0; 
        sreg_execute.load_ex_inst = '0;
        sreg_execute.st_ex_inst = '0;
        alu_src_data1 = '0;
        alu_src_data2 = '0;

        for (int i = 0; i < ALU_CNT; i++) begin
            if (sreg_issue.alu_issue_insts[i].valid) begin
                n_alu_inst_reg[i] = sreg_issue.alu_issue_insts[i];
            end
        end
        // for multiply, condition is ready or reg empty (iss mul inst not valid)
        for (int i = 0; i < MULT_CNT; i++) begin
            sreg_issue.mult_issue_gnts[i] = sreg_issue.mult_unit_readies[i] || !mult_inst_reg[i].valid;
            if (sreg_issue.mult_issue_gnts[i]) begin
                n_mult_inst_reg[i] = sreg_issue.mult_issue_insts[i];
            end
        end
        // same for load
        sreg_issue.load_issue_gnt = sreg_issue.load_unit_ready || !load_inst_reg.valid;
        if (sreg_issue.load_issue_gnt) begin
            n_load_inst_reg = sreg_issue.load_issue_inst;
        end
        if (sreg_issue.store_issue_inst.valid) begin
            n_store_inst_reg = sreg_issue.store_issue_inst;
        end
        if (sreg_issue.branch_issue_inst.valid) begin
            n_branch_inst_reg = sreg_issue.branch_issue_inst;
        end

        // clear read tags
        sreg_issue_data_read.issue_src1_read_tags = '0;
        sreg_issue_data_read.issue_src2_read_tags = '0;
        // read data
        for (int i = 0; i < ALU_CNT; i++) begin
            if (sreg_issue.alu_issue_insts[i].valid) begin
                if (n_alu_inst_reg[i].src1_in_cdb) begin
                    for (int j = 0; j < `CDB_WIDTH; j++) begin
                        if (n_alu_inst_reg[i].src1 == etb_in.etb_tags[j]) begin
                            alu_src_data1[i] = etb_in.etb_datas[j];
                        end
                    end
                end else begin
                    sreg_issue_data_read.issue_src1_read_tags[i] = sreg_issue.alu_issue_insts[i].src1;
                    alu_src_data1[i] = sreg_issue_data_read.prf_issue_src1_datas[i];
                end
                // select operation
                case (n_alu_inst_reg[i].opa_select)
                    OPA_IS_RS1:  n_alu_data1_reg[i] = alu_src_data1[i];
                    OPA_IS_NPC:  n_alu_data1_reg[i] = n_alu_inst_reg[i].NPC;
                    OPA_IS_PC:   n_alu_data1_reg[i] = n_alu_inst_reg[i].PC;
                    OPA_IS_ZERO: n_alu_data1_reg[i] = 0;
                    default:     n_alu_data1_reg[i] = 32'hdeadface; // dead face
                endcase

                if (n_alu_inst_reg[i].src2_in_cdb) begin
                    for (int j = 0; j < `CDB_WIDTH; j++) begin
                        if (n_alu_inst_reg[i].src2 == etb_in.etb_tags[j]) begin
                            alu_src_data2[i] = etb_in.etb_datas[j];
                        end
                    end
                end else begin
                    sreg_issue_data_read.issue_src2_read_tags[i] = sreg_issue.alu_issue_insts[i].src2;
                    alu_src_data2[i] = sreg_issue_data_read.prf_issue_src2_datas[i];
                end
                case (n_alu_inst_reg[i].opb_select)
                    OPB_IS_RS2:   n_alu_data2_reg[i] = alu_src_data2[i];
                    OPB_IS_I_IMM: n_alu_data2_reg[i] = `RV32_signext_Iimm(n_alu_inst_reg[i].inst);
                    OPB_IS_S_IMM: n_alu_data2_reg[i] = `RV32_signext_Simm(n_alu_inst_reg[i].inst);
                    OPB_IS_B_IMM: n_alu_data2_reg[i] = `RV32_signext_Bimm(n_alu_inst_reg[i].inst);
                    OPB_IS_U_IMM: n_alu_data2_reg[i] = `RV32_signext_Uimm(n_alu_inst_reg[i].inst);
                    OPB_IS_J_IMM: n_alu_data2_reg[i] = `RV32_signext_Jimm(n_alu_inst_reg[i].inst);
                    default:      n_alu_data2_reg[i] = 32'hfacefeed; // face feed
                endcase
            end
        end
        for (int i = 0; i < MULT_CNT; i++) begin
            if (sreg_issue.mult_issue_gnts[i]) begin
                if (n_mult_inst_reg[i].src1_in_cdb) begin
                    for (int j = 0; j < `CDB_WIDTH; j++) begin
                        if (n_mult_inst_reg[i].src1 == etb_in.etb_tags[j]) begin
                            n_mult_data1_reg[i] = etb_in.etb_datas[j];
                        end
                    end
                end else begin
                    sreg_issue_data_read.issue_src1_read_tags[ALU_CNT + i] = sreg_issue.mult_issue_insts[i].src1;
                    n_mult_data1_reg[i] = sreg_issue_data_read.prf_issue_src1_datas[ALU_CNT + i];
                end
                if (n_mult_inst_reg[i].src2_in_cdb) begin
                    for (int j = 0; j < `CDB_WIDTH; j++) begin
                        if (n_mult_inst_reg[i].src2 == etb_in.etb_tags[j]) begin
                            n_mult_data2_reg[i] = etb_in.etb_datas[j];
                        end
                    end
                end else begin
                    sreg_issue_data_read.issue_src2_read_tags[ALU_CNT + i] = sreg_issue.mult_issue_insts[i].src2;
                    n_mult_data2_reg[i] = sreg_issue_data_read.prf_issue_src2_datas[ALU_CNT + i];
                end
            end else begin
                n_mult_inst_reg[i] = mult_inst_reg[i];
                // deal with branch resolution
                if ((cdb_branch_in.br_res_state == BR_RES_MIS) && ((n_mult_inst_reg[i].bmask & cdb_branch_in.br_res_idx_bus) != 0)) begin
                    n_mult_inst_reg[i].valid = 0;
                end else if (cdb_branch_in.br_res_state == BR_RES_HIT) begin
                    n_mult_inst_reg[i].bmask &= ~cdb_branch_in.br_res_idx_bus;
                end
            end
        end
        // load
        if (sreg_issue.load_issue_gnt) begin
            if (sreg_issue.load_issue_inst.src1_in_cdb) begin
                for (int j = 0; j < `CDB_WIDTH; j++) begin
                    if (sreg_issue.load_issue_inst.src1 == etb_in.etb_tags[j]) begin
                        n_load_data1_reg = etb_in.etb_datas[j];
                    end
                end
            end else begin
                sreg_issue_data_read.issue_src1_read_tags[ALU_CNT + MULT_CNT] = sreg_issue.load_issue_inst.src1;
                n_load_data1_reg = sreg_issue_data_read.prf_issue_src1_datas[ALU_CNT + MULT_CNT];
            end
            n_load_data2_reg = `RV32_signext_Iimm(sreg_issue.load_issue_inst.inst);
        end else begin
            n_load_inst_reg = load_inst_reg;
            // deal with branch resolution
            if ((cdb_branch_in.br_res_state == BR_RES_MIS) && ((n_load_inst_reg.bmask & cdb_branch_in.br_res_idx_bus) != 0)) begin
                n_load_inst_reg.valid = 0;
            end else if (cdb_branch_in.br_res_state == BR_RES_HIT) begin
                n_load_inst_reg.bmask &= ~cdb_branch_in.br_res_idx_bus;
            end
        end
        // store
        if (sreg_issue.store_issue_inst.valid) begin
            if (sreg_issue.store_issue_inst.src1_in_cdb) begin
                for (int j = 0; j < `CDB_WIDTH; j++) begin
                    if (sreg_issue.store_issue_inst.src1 == etb_in.etb_tags[j]) begin
                        n_store_data1_reg = etb_in.etb_datas[j];
                    end
                end
            end else begin
                sreg_issue_data_read.issue_src1_read_tags[ALU_CNT + MULT_CNT + 1] = sreg_issue.store_issue_inst.src1;
                n_store_data1_reg = sreg_issue_data_read.prf_issue_src1_datas[ALU_CNT + MULT_CNT + 1];
            end
            n_store_data2_reg = `RV32_signext_Simm(sreg_issue.store_issue_inst.inst);
            if (sreg_issue.store_issue_inst.src2_in_cdb) begin
                for (int j = 0; j < `CDB_WIDTH; j++) begin
                    if (sreg_issue.store_issue_inst.src2 == etb_in.etb_tags[j]) begin
                        n_store_data_reg = etb_in.etb_datas[j];
                    end
                end
            end else begin
                sreg_issue_data_read.issue_src2_read_tags[ALU_CNT + MULT_CNT + 1] = sreg_issue.store_issue_inst.src2;
                n_store_data_reg = sreg_issue_data_read.prf_issue_src2_datas[ALU_CNT + MULT_CNT + 1];
            end
        end
        if (sreg_issue.branch_issue_inst.valid) begin
            if (n_branch_inst_reg.src1_in_cdb) begin
                for (int j = 0; j < `CDB_WIDTH; j++) begin
                    if (n_branch_inst_reg.src1 == etb_in.etb_tags[j]) begin
                        n_branch_data1_reg = etb_in.etb_datas[j];
                    end
                end
            end else begin
                sreg_issue_data_read.issue_src1_read_tags[ALU_CNT + MULT_CNT + 2] = sreg_issue.branch_issue_inst.src1;
                n_branch_data1_reg = sreg_issue_data_read.prf_issue_src1_datas[ALU_CNT + MULT_CNT + 2];
            end
            if (n_branch_inst_reg.src2_in_cdb) begin
                for (int j = 0; j < `CDB_WIDTH; j++) begin
                    if (n_branch_inst_reg.src2 == etb_in.etb_tags[j]) begin
                        n_branch_data2_reg = etb_in.etb_datas[j];
                    end
                end
            end else begin
                sreg_issue_data_read.issue_src2_read_tags[ALU_CNT + MULT_CNT + 2] = sreg_issue.branch_issue_inst.src2;
                n_branch_data2_reg = sreg_issue_data_read.prf_issue_src2_datas[ALU_CNT + MULT_CNT + 2];
            end
        end
        // issue for execution
        // need to deal with ebr
        for (int i = 0; i < ALU_CNT; i++) begin
            if ((cdb_branch_in.br_res_state == BR_RES_MIS) && ((alu_inst_reg[i].bmask & cdb_branch_in.br_res_idx_bus) != 0)) begin
            end else if (alu_inst_reg[i].valid) begin
                // assemble outputs to alu
                sreg_execute.alu_ex_insts[i] = {
                    1'b1,
                    alu_data1_reg[i],
                    alu_data2_reg[i],
                    alu_inst_reg[i].bmask,
                    alu_inst_reg[i].dst,
                    alu_inst_reg[i].alu_func
                };
            end
            //end
        end
        for (int i = 0; i < MULT_CNT; i++) begin
            // check mult ready in mult unit
            // if (sreg_issue.mult_unit_readies[i]) begin
                if ((cdb_branch_in.br_res_state == BR_RES_MIS) && ((mult_inst_reg[i].bmask & cdb_branch_in.br_res_idx_bus) != 0)) begin
                end else if (mult_inst_reg[i].valid) begin
                    // assemble outputs to mult
                    sreg_execute.mult_ex_insts[i] = {
                        1'b1,
                        mult_data1_reg[i],
                        mult_data2_reg[i],
                        mult_inst_reg[i].bmask,
                        mult_inst_reg[i].dst,
                        {1'b1, mult_inst_reg[i].mult_func}
                    };              
                end
            // end
        end
        if (sreg_issue.load_unit_ready) begin
            if ((cdb_branch_in.br_res_state == BR_RES_MIS) && ((load_inst_reg.bmask & cdb_branch_in.br_res_idx_bus) != 0)) begin
            end else if (load_inst_reg.valid) begin
                sreg_execute.load_ex_inst = {
                    32'b0,// dummy data
                    load_data1_reg,
                    load_data2_reg,
                    load_inst_reg.dst,
                    load_inst_reg.bmask,
                    1'b1,
                    load_inst_reg.size,
                    load_inst_reg.st_pos,
                    load_inst_reg.is_unsigned
                };
            end
        end
        // store
        if ((cdb_branch_in.br_res_state == BR_RES_MIS) && ((store_inst_reg.bmask & cdb_branch_in.br_res_idx_bus) != 0)) begin
        end else if (store_inst_reg.valid) begin
            sreg_execute.st_ex_inst = {
                store_data_reg,
                store_data1_reg,
                store_data2_reg,
                store_inst_reg.dst,
                store_inst_reg.bmask,
                1'b1,
                store_inst_reg.size,
                store_inst_reg.st_pos,
                1'b0 // dummy unsignedness
            };
        end

        if ((cdb_branch_in.br_res_state == BR_RES_MIS) && ((branch_inst_reg.bmask & cdb_branch_in.br_res_idx_bus) != 0)) begin
        end else if (branch_inst_reg.valid) begin
            sreg_execute.branch_ex_inst = {
                1'b1,
                branch_inst_reg.predicted_addr,
                branch_inst_reg.bindex,
                branch_inst_reg.bmask,
                branch_data1_reg,
                branch_data2_reg,
                branch_inst_reg.dst,
                branch_inst_reg.PC,
                branch_inst_reg.branch_func,
                branch_inst_reg.offset,
                branch_inst_reg.is_uncond_branch,
                branch_inst_reg.is_halt,
                // branch_inst_reg.is_jal,
                branch_inst_reg.is_jalr
            };
        end
        //end
    end

    always_ff @(posedge sys_in.clock) begin
        if (sys_in.reset) begin
            alu_inst_reg <= '0;
            mult_inst_reg <= '0;
            branch_inst_reg <= '0;
            alu_data1_reg <= '0;
            alu_data2_reg <= '0;
            mult_data1_reg <= '0;
            mult_data2_reg <= '0;
            branch_data1_reg <= '0;
            branch_data2_reg <= '0;
            load_inst_reg <= '0;
            store_inst_reg <= '0;
            load_data1_reg <= '0;
            load_data2_reg <= '0;
            store_data1_reg <= '0;
            store_data2_reg <= '0;
            store_data_reg <= '0;
        end else begin
            alu_inst_reg <= n_alu_inst_reg;
            mult_inst_reg <= n_mult_inst_reg;
            branch_inst_reg <= n_branch_inst_reg;
            alu_data1_reg <= n_alu_data1_reg;
            alu_data2_reg <= n_alu_data2_reg;
            mult_data1_reg <= n_mult_data1_reg;
            mult_data2_reg <= n_mult_data2_reg;
            branch_data1_reg <= n_branch_data1_reg;
            branch_data2_reg <= n_branch_data2_reg;
            load_inst_reg <= n_load_inst_reg;
            store_inst_reg <= n_store_inst_reg;
            load_data1_reg <= n_load_data1_reg;
            load_data2_reg <= n_load_data2_reg;
            store_data1_reg <= n_store_data1_reg;
            store_data2_reg <= n_store_data2_reg;
            store_data_reg <= n_store_data_reg;
        end
    end

endmodule