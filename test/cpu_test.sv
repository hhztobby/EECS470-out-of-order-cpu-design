/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  cpu_test.sv                                         //
//                                                                     //
//  Description :  Testbench module for the VeriSimpleV processor.     //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`include "sys_defs.svh"

// P4 TODO: Add your own debugging framework. Basic printing of data structures
//          is an absolute necessity for the project. You can use C functions 
//          like in test/pipeline_print.c or just do everything in verilog.
//          Be careful about running out of space on CAEN printing lots of state
//          for longer programs (alexnet, outer_product, etc.)

// These link to the pipeline_print.c file in this directory, and are used below to print
// detailed output to the pipeline_output_file, initialized by open_pipeline_output_file()
import "DPI-C" function string decode_inst(int inst);
import "DPI-C" function void open_output_file(string pred_file, string pf_file, string rob_file, string rs_file, string fl_file, string mt_file, string bu_file);
import "DPI-C" function void close_output_file();
import "DPI-C" function void print_cycle(int clock_count);
`define TB_MAX_CYCLES 500000


module testbench;
    // string inputs for loading memory and output files
    // run like: cd build && ./simv +MEMORY=../programs/mem/<my_program>.mem +OUTPUT=../output/<my_program>
    // this testbench will generate 4 output files based on the output
    // named OUTPUT.{out cpi, wb, ppln} for the memory, cpi, writeback, and pipeline outputs.
    string program_memory_file, output_name;
    string out_outfile, cpi_outfile, writeback_outfile;//, pipeline_outfile;
    int out_fileno, cpi_fileno, wb_fileno; // verilog uses integer file handles with $fopen and $fclose

    // variables used in the testbench
    logic        clock;
    logic        reset;
    logic [31:0] clock_count; // also used for terminating infinite loops
    logic [31:0] instr_count;

    MEM_BLOCK inst_mem_block;

// cpu signals
    // -------------------------- inputs --------------------------
    // F_INST [`N-1:0] finsts;
    // -------------------------- outputs --------------------------
    // logic [`N-1:0] faccepts;
    // logic is_mispredict;
    // ADDR branch_target_pc;
    // ADDR pc, tmp_pc;
    COMMIT_PACKET [`RETIRE_WIDTH-1:0] committed_insts;
    logic dcache_writeback_clear;
    logic [`DCACHE_LINES-1:0][$bits(MEM_BLOCK)-1:0] dcache_mem;
    DCACHE_TAG [`DCACHE_LINES-1:0] dcache_tags;

    EXCEPTION_CODE error_status = NO_ERROR;  


    MEM_TAG                                   mem_transac_tag;
    MEM_BLOCK                                 mem_read_data;
    MEM_TAG                                   mem_read_data_tag;
    ADDR                                      cache_mem_addr;
    MEM_COMMAND                               cache_mem_command;
    MEM_BLOCK                                 cache_mem_write_data;
    cpu dut (
        // inputs
        .clock(clock),
        .reset(reset),
        .mem_transac_tag(mem_transac_tag),
        .mem_read_data(mem_read_data),
        .mem_read_data_tag(mem_read_data_tag),
        .cache_mem_addr(cache_mem_addr),
        .cache_mem_command(cache_mem_command),
        .cache_mem_write_data(cache_mem_write_data),
        .retired_insts(committed_insts),
        .dcache_writeback_clear(dcache_writeback_clear),
        .dcache_mem_out(dcache_mem),
        .dcache_tags_out(dcache_tags)
    );


    // Instantiate the Data Memory
    mem memory (
        // Inputs
        .clock            (clock),
        .proc2mem_command (cache_mem_command),
        .proc2mem_addr    (cache_mem_addr),
        .proc2mem_data    (cache_mem_write_data),
        // Outputs
        .mem2proc_transaction_tag (mem_transac_tag),
        .mem2proc_data            (mem_read_data),
        .mem2proc_data_tag        (mem_read_data_tag)
    );

    // Generate System Clock
    always begin
        #(`CLOCK_PERIOD/2.0);
        clock = ~clock;
    end


    initial begin
        $display("\n---- Starting CPU Testbench ----\n");
        // dump the entire module
        // $dumpfile("cpu_test.vcd");
        // I want to look into integrated_inst.fu_module, how to dump?
        // $dumpvars(0);

        // set paramterized strings, see comment at start of module
        if ($value$plusargs("MEMORY=%s", program_memory_file)) begin
            $display("Using memory file  : %s", program_memory_file);
        end else begin
            $display("Did not receive '+MEMORY=' argument. Exiting.\n");
            $finish;
        end
        if ($value$plusargs("OUTPUT=%s", output_name)) begin
            $display("Using output files : %s.{out, cpi, wb, ppln}", output_name);
            out_outfile       = {output_name,".out"}; // this is how you concatenate strings in verilog
            cpi_outfile       = {output_name,".cpi"};
            writeback_outfile = {output_name,".wb"};
            //pipeline_outfile  = {output_name,".ppln"};
        end else begin
            $display("\nDid not receive '+OUTPUT=' argument. Exiting.\n");
            $finish;
        end

        clock = 1'b0;
        reset = 1'b0;

        $display("\n  %16t : Asserting Reset", $realtime);
        reset = 1'b1;

        @(posedge clock);
        @(posedge clock);

        $display("  %16t : Loading Unified Memory", $realtime);
        // load the compiled program's hex data into the memory module
        $readmemh(program_memory_file, memory.unified_memory);
        // print memory.unified_memory to the console
        /*for (int i = 0; i < 20; i = i + 1) begin
            $display("mem[%0d] = %x", i*8, memory.unified_memory[i]);
        end*/

        @(posedge clock);
        @(posedge clock);
        #1; // This reset is at an odd time to avoid the pos & neg clock edges
        $display("  %16t : Deasserting Reset", $realtime);
        reset = 1'b0;

        wb_fileno = $fopen(writeback_outfile);
        $fdisplay(wb_fileno, "Register writeback output (hexadecimal)");

        // Open pipeline output file AFTER throwing the reset otherwise the reset state is displayed
        // open_pipeline_output_file(pipeline_outfile);
        // print_header();

        open_output_file("pred.txt", "pf.txt", "rob.txt", "rs.txt", "fl.txt", "mt.txt", "bu.txt");
        out_fileno = $fopen(out_outfile);

        $display("  %16t : Running Processor", $realtime);
    end


    always @(negedge clock) begin
        if (reset) begin
            // Count the number of cycles and number of instructions committed
            clock_count = 0;
            instr_count = 0;
            // finsts = 0;
        end else begin
            #2; // wait a short time to avoid a clock edge

            clock_count = clock_count + 1;

            if (clock_count % 10000 == 0) begin
                $display("  %16t : %d cycles", $realtime, clock_count);
            end

            output_reg_writeback_and_maybe_halt();

            // stop the processor
            if ((error_status != NO_ERROR && dcache_writeback_clear) || clock_count > `TB_MAX_CYCLES) begin

                $display("  %16t : Processor Finished", $realtime);

                // close the writeback and pipeline output files
                close_output_file();
                $fclose(wb_fileno);

                // display the final memory and status
                show_final_mem_and_status(error_status);
                // output the final CPI
                output_cpi_file();

                $display("\n---- Finished CPU Testbench ----\n");

                #100 $finish;
            end
        end // if(reset)
    end


    // Task to output register writeback data and potentially halt the processor.
    task output_reg_writeback_and_maybe_halt;
        ADDR pc;
        DATA inst;
        MEM_BLOCK block;
        if (error_status != NO_ERROR) begin 
            return;
        end
        for (int n = 0; n < `RETIRE_WIDTH; ++n) begin
            if (committed_insts[n].valid) begin
                // update the count for every committed instruction
                instr_count = instr_count + 1;

                pc = committed_insts[n].NPC - 4;
                block = memory.unified_memory[pc[31:3]];
                inst = block.word_level[pc[2]];
                // print the committed instructions to the writeback output file
                if (committed_insts[n].reg_idx == `ZERO_REG) begin
                    $fdisplay(wb_fileno, "PC %4x:%-8s| ---", pc, decode_inst(inst));
                end else begin
                    $fdisplay(wb_fileno, "PC %4x:%-8s| r%02d=%-8x",
                              pc,
                              decode_inst(inst),
                              committed_insts[n].reg_idx,
                              committed_insts[n].data);
                end

                // exit if we have an illegal instruction or a halt
                if (committed_insts[n].illegal) begin
                    error_status = ILLEGAL_INST;
                    break;
                end else if(committed_insts[n].halt) begin
                    error_status = HALTED_ON_WFI;
                    break;
                end
            end // if valid
        end
    endtask // task output_reg_writeback_and_maybe_halt


    // Task to output the final CPI and # of elapsed clock edges`
    task output_cpi_file;
        real cpi;
        begin
            cpi = $itor(clock_count) / instr_count; // must convert int to real
            cpi_fileno = $fopen(cpi_outfile);
            $fdisplay(cpi_fileno, "@@@  %0d cycles / %0d instrs = %f CPI",
                      clock_count, instr_count, cpi);
            $fdisplay(cpi_fileno, "@@@  %4.2f ns total time to execute",
                      clock_count * `CLOCK_PERIOD);
            $fclose(cpi_fileno);
        end
    endtask // task output_cpi_file


    // Show contents of Unified Memory in both hex and decimal
    // Also output the final processor status
    task show_final_mem_and_status;
        input EXCEPTION_CODE final_status;
        int showing_data;
        begin
            $fdisplay(out_fileno, "\nFinal memory state and exit status:\n");
            $fdisplay(out_fileno, "@@@ Unified Memory contents hex on left, decimal on right: ");
            $fdisplay(out_fileno, "@@@");
            showing_data = 0;
            for (int k = 0; k <= `MEM_64BIT_LINES - 1; k = k+1) begin
                if ((dcache_tags[k[4:0]].valid && 
                    dcache_tags[k[4:0]].tag == k[12:5])) begin
                    if (dcache_mem[k[4:0]] != 0) begin
                        $fdisplay(out_fileno, "@@@ mem[%5d] = %x : %0d", k*8, dcache_mem[k[4:0]],
                                                                    dcache_mem[k[4:0]]);
                        showing_data = 1;
                    end else if (showing_data != 0) begin
                        $fdisplay(out_fileno, "@@@");
                        showing_data = 0;
                    end
                end else if (memory.unified_memory[k] != 0) begin
                    $fdisplay(out_fileno, "@@@ mem[%5d] = %x : %0d", k*8, memory.unified_memory[k],
                                                                memory.unified_memory[k]);
                    showing_data = 1;
                end else if (showing_data != 0) begin
                    $fdisplay(out_fileno, "@@@");
                    showing_data = 0;
                end
            end
            $fdisplay(out_fileno, "@@@");

            case (final_status)
                LOAD_ACCESS_FAULT: $fdisplay(out_fileno, "@@@ System halted on memory error");
                HALTED_ON_WFI:     $fdisplay(out_fileno, "@@@ System halted on WFI instruction");
                ILLEGAL_INST:      $fdisplay(out_fileno, "@@@ System halted on illegal instruction");
                default:           $fdisplay(out_fileno, "@@@ System halted on unknown error code %x", final_status);
            endcase
            $fdisplay(out_fileno, "@@@");
            $fclose(out_fileno);
        end
    endtask // task show_final_mem_and_status



    // OPTIONAL: Print our your data here
    // It will go to the $program.log file
    task print_custom_data;
        //$display("%3d: YOUR DATA HERE", 
        //    clock_count-1
        //);
    endtask


endmodule // module testbench
