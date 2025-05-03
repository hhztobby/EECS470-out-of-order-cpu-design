`include "sys_defs.svh"
`include "cpuBusIF.svh"

module dcache_test;

    logic reset, clock;

    cpuBusIF bus(
    );

    dcache dut(
        bus.sys_in,
        bus.icache
    );

    mem memory (
        // Inputs
        .clock            (clock),
        .proc2mem_command (),
        .proc2mem_addr    (),
        .proc2mem_data    (),
// `ifndef CACHE_MODE
//         .proc2mem_size    (proc2mem_size),
// `endif
        // Outputs
        .mem2proc_transaction_tag (),
        .mem2proc_data            (),
        .mem2proc_data_tag        ()
    );

    initial begin
        $finish;
    end
endmodule