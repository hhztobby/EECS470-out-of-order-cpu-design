`ifndef IF_SIMULATOR_SV
`define IF_SIMULATOR_SV

// `define RV32_BEQ       `RV32_Stype(`RV32_BRANCH, 3'b000)
// `define RV32_Stype(op, funct3)         {{7{1'b?}},{5{1'b?}},{5{1'b?}},``funct3``,{5{1'b?}},``op``}
// `define RV32_BRANCH   7'b1100011
function automatic INST generate_beq(input logic [4:0] rs1, input logic [4:0] rs2, input logic [12:0] imm);
// format: | imm[12] | imm[10:5] |  rs2  |  rs1  |  funct3 | imm[4:1] | imm[11] | opcode |
    begin
        return {
            imm[12], imm[10:5], rs2, rs1, 3'b000, imm[4:1], imm[11], `RV32_BRANCH
        };
    end
endfunction

function automatic INST generate_add(input logic [4:0] rs1, input logic [4:0] rs2, input logic [4:0] rd);
// format: | funct7 | rs2 | rs1 | funct3 | rd | opcode |
    begin
        return {
            7'b0000000, rs2, rs1, 3'b000, rd, `RV32_OP
        };
    end
endfunction

function automatic INST generate_addi(input logic [4:0] rs1, input logic [4:0] rd, input logic [12:0] imm);
// format: | imm[11:0] | rs1 | funct3 | rd | opcode |
    begin
        return {
            imm[11:0], rs1, 3'b000, rd, `RV32_OP_IMM
        };
    end
endfunction

function automatic INST generate_mult(input logic [4:0] rs1, input logic [4:0] rs2, input logic [4:0] rd);
// format: | funct7 | rs2 | rs1 | funct3 | rd | opcode |
    begin
        return {
            7'b0000001, rs2, rs1, `MD_MUL_FUN3, rd, `RV32_OP
        };
    end
endfunction

function automatic INST generate_random_inst();
    begin
        int num = $urandom_range(0, 3);
        int rnd0 = $urandom_range(0, 31), rnd1 = $urandom_range(0, 31), rnd2 = $urandom_range(0, 31), rnd_imm = $urandom_range(0, 4095);
    `ifdef OUTPUT_TEST
        case (num)
            0: $display("Generating ADD instruction");
            1: $display("Generating ADDI instruction");
            2: $display("Generating MULT instruction");
            3: $display("Generating BEQ instruction");
            default: $display("Generating INVALID instruction");
        endcase
    `endif
        // randomly selects between add, addi, mult, and beq
        case (num)
            0: return generate_add(rnd0, rnd1, rnd2);
            1: return generate_addi(rnd0, rnd1, rnd_imm);
            2: return generate_mult(rnd0, rnd1, rnd2);
            3: return generate_beq(rnd0, rnd1, rnd_imm);
            default: return '0;
        endcase
    end
endfunction

`endif