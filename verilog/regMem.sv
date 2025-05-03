// memory system for physical register file
// adapted from memDP.sv

`include "sys_defs.svh"

module regMem
  #(parameter WIDTH      = 32,
    parameter DEPTH      = 32,
    parameter READ_PORTS = 10,
    parameter BYPASS_EN  = 0,  // 0: Read data will update at positive edge
                               // 1: Read data will update combinationally if
                               //    write to same address
    parameter WRITE_PORTS = 2
   )
   (// ------------------------------------------------------------ //
    //                      Clock and Reset                         //
    // ------------------------------------------------------------ //
    input                                            clock,
    input                                            reset,

    // ------------------------------------------------------------ //
    //                      Read interface                          //
    // ------------------------------------------------------------ //
    input        [READ_PORTS-1:0]                    re,     // Read enable
    input        [READ_PORTS-1:0][$clog2(DEPTH)-1:0] raddr,  // Read address
    output logic [READ_PORTS-1:0][WIDTH        -1:0] rdata,  // Read data

    // ------------------------------------------------------------ //
    //                      Write interface                         //
    // ------------------------------------------------------------ //
    input        [WRITE_PORTS-1:0]                     we,     // Write enable
    input        [WRITE_PORTS-1:0][$clog2(DEPTH)-1:0]  waddr,  // Write address
    input        [WRITE_PORTS-1:0][WIDTH        -1:0]  wdata   // Write data
   );

logic [DEPTH-1:0][WIDTH-1:0]  memData;
genvar i;

///////////////////////////////////////////////////////////////////
////////////////////////// Read Logic /////////////////////////////
///////////////////////////////////////////////////////////////////

generate
    for (i = 0; i < READ_PORTS; i++) begin
        always_comb begin
             rdata[i] = re[i] ? memData[raddr[i]] : '0;
            if (BYPASS_EN != 0) begin : bypass_path
                for (int j = 0; j < WRITE_PORTS; j++) begin
                    if (re[i] && we[j] && (raddr[i] == waddr[j]))
                        rdata[i] = wdata[j];
                end
            end
        end
    end
endgenerate
 
///////////////////////////////////////////////////////////////////
////////////////////////// Write Logic ////////////////////////////
///////////////////////////////////////////////////////////////////

always_ff @(posedge clock) begin
    if (reset) begin
        memData        <= '0;
    end /*else if (we) begin
        memData[waddr] <= wdata;*/
        else begin
        for (int j = 0; j < WRITE_PORTS; j++) begin
            if (we[j])
                memData[waddr[j]] <= wdata[j];
        end
    end
end


// debug

`ifdef OUTPUT_REGMEM
always_ff @(posedge clock) begin
    for (int i = 0; i < WRITE_PORTS; i++) begin
        if (we[i]) begin
            $display("[regMem] write request [%0d], addr = %0d, input data = %0d", i, waddr[i], wdata[i]);
        end
    end
    for (int i = 0; i < READ_PORTS; i++) begin
        if (re[i]) begin
            $display("[regMem] read request [%0d], addr = %0d, output data = %0d", i, raddr[i], rdata[i]);
        end
    end
    if (BYPASS_EN) begin
        // display bypass data
        for (int i = 0; i < READ_PORTS; i++) begin
            if (re[i]) begin
                for (int j = 0; j < WRITE_PORTS; j++) begin
                    if (we[j] && (raddr[i] == waddr[j])) begin
                        $display("[regMem] bypass data: addr = %0d, output data = %0d", raddr[i], rdata[i]);
                    end
                end
            end
        end
    end
end
`endif

///////////////////////////////////////////////////////////////////
////////////////////////// Assertions /////////////////////////////
///////////////////////////////////////////////////////////////////

`ifdef GEN_ASSERT
    logic [DEPTH-1:0] valid;
    
    // Track which entries are valid
    always_ff @(posedge clock) begin
        if      (reset) valid        <= '0;
        else if (we)    valid[waddr] <= 1'b1;       
    end

    // ---------- Verify Write Interface ---------- 
    clocking cb_read @(posedge clock);
        property waddr_valid;
            we |-> waddr < DEPTH;
        endproperty
    endclocking

    validWaddr:    assert property(cb_read.waddr_valid);
    
    // ---------- Verify Read Interface ---------- 
    generate
        for (i = 0; i < READ_PORTS; i++) begin
            clocking cb_write @(posedge clock);
                property raddr_valid;
                    re[i] |-> raddr[i] < DEPTH;
                endproperty

                property read_valid_data;
                    re[i] |-> valid[raddr[i]];
                endproperty
            endclocking

            validRaddr:    assert property(cb_write.raddr_valid);
            validRdData:   assert property(cb_write.read_valid_data);
        end
    endgenerate
`endif

endmodule
