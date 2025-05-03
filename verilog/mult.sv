
`include "sys_defs.svh"

// This is a pipelined multiplier that multiplies two 64-bit integers and
// returns the low 64 bits of the result.
// This is not an ideal multiplier but is sufficient to allow a faster clock
// period than straight multiplication.

module mult (
    input clock, reset,
    input DATA rs1,rs2,
    input MULT_FUNC func,
    input logic src_vld,
    output logic src_rdy,
    input TAG src_dest_tag,
    input BMASK src_bmask,

    // output package, targeting the CDB register. 
    output CDB_REG_PACKET cdb_reg_packet,
    // output TAG early_tag_out,

    // output logic rst_valid,// if choosen by cdb, must be valid
    
    // if choosen by cdb, must be valid

    // CDB arbiter raise hand
    output TAG cdb_raise_hand_tag,
    input  logic cdb_arbit_gnt, // this is the result of cdb arbiter. 

    // branch mispredict control
    input   BR_RES_STATE                        mis_res_state,
    input   B_IDX                               mis_branch_idx
);
    logic [`MULT_STAGES:0] [63:0]  product_sum;
    logic [`MULT_STAGES:0] [63:0]  next_mplier;
    // it seems to be 64 bits. 
    logic [`MULT_STAGES:0] [63:0]  next_mcand;
    MULT_FUNC [`MULT_STAGES:0] next_func;
    logic [63:0]  mcand, mplier;

    logic  [`MULT_STAGES:0] dst_vld;
    logic [`MULT_STAGES:0] rdy;
    TAG [`MULT_STAGES:0] dst_dest_tag; 

    BMASK [`MULT_STAGES:0] dst_bmask;
    assign cdb_reg_packet.result = (next_func[`MULT_STAGES] == M_MUL) ? product_sum[`MULT_STAGES][31:0] : product_sum[`MULT_STAGES][63:32];
    assign cdb_reg_packet.dst_bmask = dst_bmask[`MULT_STAGES];
    assign cdb_reg_packet.dst_tag_out = dst_dest_tag[`MULT_STAGES];
    assign cdb_reg_packet.valid_out= dst_vld[`MULT_STAGES];
    logic squash;
    BMASK tmp_bmask;
    always_comb begin
        squash =0;
        // for different br res state, we need to modify the bmask
        case (mis_res_state)
            BR_RES_HIT: tmp_bmask =dst_bmask[`MULT_STAGES-2] & ~(mis_branch_idx);
            BR_RES_MIS: begin
                // don't use clog2, use for loop to decode the idx
                for (int i = 0; i < `BR_STK_SZ; i++) begin
                    if (mis_branch_idx[i]) begin
                        squash = dst_bmask[`MULT_STAGES-2][i];
                    end
                end
            end
            // BR_RES_MIS:squash= src_bmask[$clog2(mis_branch_idx)];// 1 in the bmask means this instruction depends on the mispredicted branch
            default: tmp_bmask = dst_bmask[`MULT_STAGES-2];
        endcase
        cdb_raise_hand_tag = dst_vld[`MULT_STAGES-2] ? dst_dest_tag[`MULT_STAGES-2] : 0;
        if(squash==1)cdb_raise_hand_tag=0;
    end

    // Sign-extend the multiplier inputs based on the operation
    always_comb begin
        case (func)
            M_MUL, M_MULH, M_MULHSU: mcand = {{(32){rs1[31]}}, rs1};
            default:                 mcand = {32'b0, rs1};
        endcase
        case (func)
            M_MUL, M_MULH: mplier = {{(32){rs2[31]}}, rs2};
            default:       mplier = {32'b0, rs2};
        endcase
    end

    assign next_mplier[0]=mplier;
    assign next_mcand[0]=mcand;
    assign next_func[0]=func;
    assign dst_vld[0]=src_vld;
    assign product_sum[0]=64'b0;
    assign src_rdy = rdy[0];
    assign dst_dest_tag[0]=src_dest_tag;
    assign dst_bmask[0]=src_bmask;
    genvar i;
    for(i=0;i<`MULT_STAGES-3;i++)begin
        mult_stage mult_stage (
            .clock(clock),
            .reset(reset),
            .prev_sum(product_sum[i]),
            .mplier(next_mplier[i]),
            .mcand(next_mcand[i]),
            .func(next_func[i]),
            .product_sum(product_sum[i+1]),
            .next_mplier(next_mplier[i+1]),
            .next_mcand(next_mcand[i+1]),
            .next_func(next_func[i+1]),
            .src_vld(dst_vld[i]),
            .dst_rdy(rdy[i+1]),
            .dst_vld(dst_vld[i+1]),
            .src_rdy(rdy[i]),
            .src_dest_tag(dst_dest_tag[i]),
            .dst_dest_tag(dst_dest_tag[i+1]),
            .src_bmask(dst_bmask[i]),
            .dst_bmask(dst_bmask[i+1]),
            .mis_res_state(mis_res_state),
            .mis_branch_idx(mis_branch_idx)
        );
    end

    mult_stage mult_last3 (
        .clock(clock),
        .reset(reset),
        .prev_sum(product_sum[`MULT_STAGES-3]),
        .mplier(next_mplier[`MULT_STAGES-3]),
        .mcand(next_mcand[`MULT_STAGES-3]),
        .func(next_func[`MULT_STAGES-3]),
        .product_sum(product_sum[`MULT_STAGES-2]),
        .next_mplier(next_mplier[`MULT_STAGES-2]),
        .next_mcand(next_mcand[`MULT_STAGES-2]),
        .next_func(next_func[`MULT_STAGES-2]),
        .src_vld(dst_vld[`MULT_STAGES-3]),
        .dst_rdy(rdy[`MULT_STAGES-2]&& cdb_arbit_gnt),
        .dst_vld(dst_vld[`MULT_STAGES-2]),
        .src_rdy(rdy[`MULT_STAGES-3]),
        .src_dest_tag(dst_dest_tag[`MULT_STAGES-3]),
        .dst_dest_tag(dst_dest_tag[`MULT_STAGES-2]),
        .src_bmask(dst_bmask[`MULT_STAGES-3]),
        .dst_bmask(dst_bmask[`MULT_STAGES-2]),
        .mis_res_state(mis_res_state),
        .mis_branch_idx(mis_branch_idx)
    );

    mult_stage mult_last2 (
        .clock(clock),
        .reset(reset|| !cdb_arbit_gnt),
        .prev_sum(product_sum[`MULT_STAGES-2]),
        .mplier(next_mplier[`MULT_STAGES-2]),
        .mcand(next_mcand[`MULT_STAGES-2]),
        .func(next_func[`MULT_STAGES-2]),
        .product_sum(product_sum[`MULT_STAGES-1]),
        .next_mplier(next_mplier[`MULT_STAGES-1]),
        .next_mcand(next_mcand[`MULT_STAGES-1]),
        .next_func(next_func[`MULT_STAGES-1]),
        .src_vld(dst_vld[`MULT_STAGES-2]),
        .dst_rdy(rdy[`MULT_STAGES-1]),
        .dst_vld(dst_vld[`MULT_STAGES-1]),
        .src_rdy(rdy[`MULT_STAGES-2]),
        .src_dest_tag(dst_dest_tag[`MULT_STAGES-2]),
        .dst_dest_tag(dst_dest_tag[`MULT_STAGES-1]),
        .src_bmask(dst_bmask[`MULT_STAGES-2]),
        .dst_bmask(dst_bmask[`MULT_STAGES-1]),
        .mis_res_state(mis_res_state),
        .mis_branch_idx(mis_branch_idx)
    );

    mult_stage_comb_out mult_last1 (
        .clock(clock),
        .reset(reset),
        .prev_sum(product_sum[`MULT_STAGES-1]),
        .mplier(next_mplier[`MULT_STAGES-1]),
        .mcand(next_mcand[`MULT_STAGES-1]),
        .func(next_func[`MULT_STAGES-1]),
        .product_sum(product_sum[`MULT_STAGES]),
        .next_mplier(next_mplier[`MULT_STAGES]),
        .next_mcand(next_mcand[`MULT_STAGES]),
        .next_func(next_func[`MULT_STAGES]),
        .src_vld(dst_vld[`MULT_STAGES-1] ),
        .dst_rdy(1'b1),
        .dst_vld(dst_vld[`MULT_STAGES]),
        .src_rdy(rdy[`MULT_STAGES-1]),
        .src_dest_tag(dst_dest_tag[`MULT_STAGES-1]),
        .dst_dest_tag(dst_dest_tag[`MULT_STAGES]),
        .src_bmask(dst_bmask[`MULT_STAGES-1]),
        .dst_bmask(dst_bmask[`MULT_STAGES]),
        .mis_res_state(mis_res_state),
        .mis_branch_idx(mis_branch_idx)
    );



endmodule // mult

module mult_stage_comb_out (
    
    input clock, reset, 
    // ports for mult itself
    input logic [63:0] prev_sum, mplier, mcand,
    output logic [63:0] product_sum, next_mplier, next_mcand,

    // ports for control
    input logic src_vld, dst_rdy,
    output logic dst_vld, src_rdy,

    // ports for pass on
    input TAG src_dest_tag, 
    output TAG dst_dest_tag,
    input MULT_FUNC func,
    output MULT_FUNC next_func,

    // ports for mispredict control
    input BMASK src_bmask,
    output BMASK dst_bmask, 
    input   BR_RES_STATE                        mis_res_state,
    input   B_IDX                               mis_branch_idx

);

    parameter SHIFT = 64/`MULT_STAGES;

    logic [63:0] partial_product, shifted_mplier, shifted_mcand;
    BMASK tmp_bmask;
    logic squash;
    assign partial_product = mplier[SHIFT-1:0] * mcand;

    assign shifted_mplier = {SHIFT'('b0), mplier[63:SHIFT]};
    assign shifted_mcand = {mcand[63-SHIFT:0], SHIFT'('b0)};
    
    assign src_rdy = 1;

    always_comb begin
        squash =0;
        tmp_bmask = 0;
        // for different br res state, we need to modify the bmask
        case (mis_res_state)
            BR_RES_HIT: tmp_bmask =src_bmask & ~(mis_branch_idx);
            BR_RES_MIS: begin
                // don't use clog2, use for loop to decode the idx
                for (int i = 0; i < `BR_STK_SZ; i++) begin
                    if (mis_branch_idx[i]) begin
                        squash = src_bmask[i];
                    end
                end
                tmp_bmask = src_bmask;
            end
            default: tmp_bmask = src_bmask;
        endcase
    end

    always_comb begin
        product_sum     = prev_sum + partial_product;
        next_mplier     = shifted_mplier;
        next_mcand      = shifted_mcand;
        next_func       = func;
        dst_dest_tag    = squash? 0 : src_dest_tag;
            
        dst_bmask       = tmp_bmask;
    end

    always_comb begin
        if (reset||squash) begin
            dst_vld = 0;
            
        end else begin
            dst_vld = 1;
        end
    end

endmodule // mult_stage


module mult_stage (
    
    input clock, reset, 
    // ports for mult itself
    input logic [63:0] prev_sum, mplier, mcand,
    output logic [63:0] product_sum, next_mplier, next_mcand,

    // ports for control
    input logic src_vld, dst_rdy,
    output logic dst_vld, src_rdy,

    // ports for pass on
    input TAG src_dest_tag, 
    output TAG dst_dest_tag,
    input MULT_FUNC func,
    output MULT_FUNC next_func,

    // ports for mispredict control
    input BMASK src_bmask,
    output BMASK dst_bmask, 
    input   BR_RES_STATE                        mis_res_state,
    input   B_IDX                               mis_branch_idx

);

    parameter SHIFT = 64/`MULT_STAGES;

    logic [63:0] partial_product, shifted_mplier, shifted_mcand;
    BMASK tmp_bmask,chosen_bmask;
    logic squash;
    assign partial_product = mplier[SHIFT-1:0] * mcand;

    assign shifted_mplier = {SHIFT'('b0), mplier[63:SHIFT]};
    assign shifted_mcand = {mcand[63-SHIFT:0], SHIFT'('b0)};

    assign src_rdy = !dst_vld || dst_rdy;

    always_comb begin
        squash = 0;
        tmp_bmask = 0;
        chosen_bmask=src_rdy? src_bmask :dst_bmask;
        // for different br res state, we need to modify the bmask
        case (mis_res_state)
            BR_RES_HIT: tmp_bmask =chosen_bmask & ~(mis_branch_idx);
            BR_RES_MIS: begin
                // don't use clog2, use for loop to decode the idx
                for (int i = 0; i < `BR_STK_SZ; i++) begin
                    if (mis_branch_idx[i]) begin
                        squash = chosen_bmask[i];
                    end
                end
                tmp_bmask = chosen_bmask;
            end
            default: tmp_bmask = chosen_bmask;
        endcase
    end

    always_ff @(posedge clock) begin
        if (reset||squash) begin
            dst_vld <= 0;

            product_sum <= 0;
            next_mplier <= 0;
            next_mcand  <= 0;
            next_func   <= M_MUL;
            dst_dest_tag <= 0;
            dst_bmask <= 0;
        end else begin
            dst_vld <= !src_rdy || (src_vld && src_rdy);
            dst_bmask <= tmp_bmask;
            if(src_rdy && src_vld) begin
                product_sum <= prev_sum + partial_product;
                next_mplier <= shifted_mplier;
                next_mcand  <= shifted_mcand;
                next_func   <= func;
                dst_dest_tag <= squash? 0 : src_dest_tag;
            end
        end
    end

endmodule // mult_stage
