/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  regfile.sv                                          //
//                                                                     //
//  Description :  This module creates the Regfile used by the ID and  //
//                 WB Stages of the Pipeline.                          //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`include "sys_defs.svh"

// P4 TODO: update this with the new parameters from sys_defs
// namely: PHYS_REG_SZ_P6 or PHYS_REG_SZ_R10K

module regfile (
    input         clock, // system clock
    // note: no system reset, register values must be written before they can be read
    input TAG [`PRF_READ_PORT_CNT-1:0] read_tags,
    input TAG     [`PRF_WRITE_PORT_CNT-1:0] write_tags,
    input DATA    [`PRF_WRITE_PORT_CNT-1:0] write_datas,
    output DATA [`PRF_READ_PORT_CNT-1:0] read_datas
);

    // Intermediate data before accounting for register 0
    DATA [`PRF_READ_PORT_CNT-1:0] rdatas;
    // Don't read or write when dealing with register 0
    logic [`PRF_READ_PORT_CNT-1:0] rEnables;
    logic [`PRF_WRITE_PORT_CNT-1:0] wEnables;

    // Technically we only need 31 registers since reg 0 is hard wired to 0
    // But since we're not grading area, just set size to 32 to make interface
    // easier and avoid having to subtract 1 from all addresses
    regMem #(
        .WIDTH     ($bits(DATA)), // 32-bit registers
        .DEPTH     (`PR_CNT), // 64 for mips r10k
        .READ_PORTS(`PRF_READ_PORT_CNT),
        .BYPASS_EN (1), // Allow internal forwarding
        .WRITE_PORTS(`PRF_WRITE_PORT_CNT)
    )
    regfile_mem (
        .clock(clock),
        .reset(1'b0),   // must be written before read
        .re   (rEnables),
        .raddr(read_tags),
        .rdata(rdatas),
        .we   (wEnables),
        .waddr(write_tags),
        .wdata(write_datas)
    );

    always_comb begin
        for (int i = 0; i < `PRF_READ_PORT_CNT; i++) begin
            if (read_tags[i] == `ZERO_REG) begin
                read_datas[i] = '0;
                rEnables[i] = 1'b0;
            end else begin
                rEnables[i] = 1'b1;
                read_datas[i] = rdatas[i];
            end
        end
    end

    // Write port
    // Can't write to zero register
    // assign we = write_en && (write_idx != `ZERO_REG);
    always_comb begin
        for (int i = 0; i < `PRF_WRITE_PORT_CNT; i++) begin
            wEnables[i] = write_tags != 0;
        end
    end

endmodule // regfile
