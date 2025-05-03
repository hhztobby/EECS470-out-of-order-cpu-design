`include "sys_defs.svh"
`include "cpuBusIF.svh"

module icache(
    cpuBusIF sys,
    cpuBusIF bus
);

    localparam int PF_BUFFER_INDEX_BITS = $clog2(`ICACHE_PF_BUFFER_SZ);

    ICACHE_TAG [`ICACHE_LINES-1:0] icache_tags, next_icache_tags;
    PF_ENTRY   [`ICACHE_PF_BUFFER_SZ-1:0] pf_buffer, next_pf_buffer;

    // use to direct the mem transac tag on next cycle
    logic [PF_BUFFER_INDEX_BITS-1:0] last_request_pf_index, request_pf_index;
    logic last_mem_req_valid, mem_req_valid;
    ADDR  last_mem_req_addr, mem_req_addr;
    ADDR  prefetch_mem_addr, next_prefetch_mem_addr;

    // fetch combinational signals
    logic [`ICACHE_READ_PORTS-1:0] cache_hits, pf_hits, hits, pf_sent_reqs, pf_want_reqs;
    logic [`ICACHE_READ_PORTS-1:0] [PF_BUFFER_INDEX_BITS-1:0] pf_indices; 
    logic [`ICACHE_READ_PORTS-1:0] first_not_hit, first_struc_not_hit;
    logic [`ICACHE_PF_BUFFER_SZ-1:0] pf_buffer_empty_bits, pf_buffer_want_req_bits;
    // logic got_a_complete_miss;
    // memDP signals
    logic     [1:0] [`ICACHE_INDEX_BITS-2:0] memDP_read_indices;
    MEM_BLOCK [1:0] memDP_read_data;
    logic     [1:0] memDP_write_valid;
    logic [1:0] [`ICACHE_INDEX_BITS-2:0] memDP_write_indices;
    MEM_BLOCK [1:0] memDP_write_data;
    logic [`ICACHE_PF_BUFFER_SZ-1:0] pf_has_hit_bits;

    genvar k;
    generate
        for (k = 0; k < 2; k++) begin : icache_banks
            memDP #(
                .WIDTH     ($bits(MEM_BLOCK)),
                .DEPTH     (`ICACHE_LINES / 2),
                .READ_PORTS(1),
                .BYPASS_EN (0))
            icache_mem_bank (
                .clock(sys.clock),
                .reset(sys.reset),
                .re   (1'b1),
                .raddr(memDP_read_indices[k]),
                .rdata(memDP_read_data[k]),
                .we   (memDP_write_valid[k]),
                .waddr(memDP_write_indices[k]),
                .wdata(memDP_write_data[k])
            );
        end
    endgenerate

    // this is accessed on negedge, so we use value in reg
    assign bus.icache_mem_addr = last_mem_req_addr;
    assign bus.icache_mem_command = last_mem_req_valid ? MEM_LOAD : MEM_NONE;

    always_comb begin
        cache_hits  = '0;
        pf_hits     = '0;
        next_icache_tags = icache_tags;
        next_pf_buffer   = pf_buffer;
        bus.icache_hits = '0;
        bus.icache_fetch_datas = '0;
        hits = '0;
        pf_indices = '0;
        first_not_hit = '0;
        first_struc_not_hit = '0;
        pf_want_reqs = '0;
        pf_sent_reqs = '0;

        mem_req_valid = '0;
        mem_req_addr = '0;
        request_pf_index = '0;

        next_prefetch_mem_addr = prefetch_mem_addr;

        pf_buffer_empty_bits = '0;
        pf_buffer_want_req_bits = '0;

        memDP_read_indices = '0;
        memDP_write_indices = '0;
        memDP_write_valid = '0;
        memDP_write_data = '0;
        pf_has_hit_bits = '0;

        // receive the memory info
        if (bus.mem_read_data_tag != 0) begin
            for (int i = 0; i < `ICACHE_PF_BUFFER_SZ; i++) begin
                if (next_pf_buffer[i].state == PF_STATE_SENT_REQ && next_pf_buffer[i].transac_tag == bus.mem_read_data_tag) begin
                    next_pf_buffer[i].state = PF_STATE_HAS_DATA;
                    next_pf_buffer[i].data  = bus.mem_read_data;
                end
            end
        end
        if (bus.transac_tag_icache != 0 && last_mem_req_valid) begin
            next_pf_buffer[last_request_pf_index].state = PF_STATE_SENT_REQ;
            next_pf_buffer[last_request_pf_index].transac_tag = bus.transac_tag_icache;
        end

        for (int i = 0; i < `ICACHE_READ_PORTS; i++) begin
            memDP_read_indices[bus.fetch_read_addrs[i][3]] = bus.fetch_read_addrs[i][7:4];
            // // index: [3 + 5 - 1: 3], tag: [15: 3 + 5]
            cache_hits[i] = bus.fetch_read_valids[i] && icache_tags[bus.fetch_read_addrs[i][7:3]].valid &&
                icache_tags[bus.fetch_read_addrs[i][7:3]].tag == bus.fetch_read_addrs[i][15:8];
            for (int j = 0; j < `ICACHE_PF_BUFFER_SZ; j++) begin
                if (next_pf_buffer[j].addr == {bus.fetch_read_addrs[i][31:3], 3'b0}) begin
                    if (next_pf_buffer[j].state == PF_STATE_HAS_DATA || next_pf_buffer[j].state == PF_STATE_HIT) begin
                        pf_hits[i] = bus.fetch_read_valids[i];
                    end else if (next_pf_buffer[j].state == PF_STATE_WANT_REQ) begin
                        pf_want_reqs[i] = 1'b1;
                    end else if (next_pf_buffer[j].state == PF_STATE_SENT_REQ) begin
                        pf_sent_reqs[i] = 1'b1;
                    end
                    if (next_pf_buffer[j].state != PF_STATE_EMPTY) begin
                        pf_indices[i] = j;
                    end
                end
            end
            if (pf_hits[i]) begin
                next_pf_buffer[pf_indices[i]].state = PF_STATE_HIT;
            end
            hits[i] = pf_hits[i] || (cache_hits[i]);
            if (hits[i]) begin
                bus.icache_fetch_datas[i] = cache_hits[i] ? memDP_read_data[bus.fetch_read_addrs[i][3]] : next_pf_buffer[pf_indices[i]].data;
            end
        end

        first_not_hit = ~(pf_hits | cache_hits);
        first_not_hit &= ~(first_not_hit - 1'b1);
        // fetch up to the last hit
        for (int i = 1; i < `ICACHE_READ_PORTS; i++) begin
            hits[i] &= hits[i-1];
        end
        bus.icache_hits = hits;

        // then determine if we are going to request the first non-hit one
            // if not sent, sent immediately
            // else, continue from currenct prefetching
        for (int i = 0; i < `ICACHE_READ_PORTS; i++) begin
            if (first_not_hit[i]) begin
                if (!pf_want_reqs[i] && !pf_sent_reqs[i]) begin
                    next_pf_buffer = '0;
                    next_pf_buffer[0].state = PF_STATE_WANT_REQ;
                    next_pf_buffer[0].addr = {bus.fetch_read_addrs[i][31:3], 3'b0};
                    next_prefetch_mem_addr = {bus.fetch_read_addrs[i][31:3], 3'b0} + 8;
                end
                if (!pf_sent_reqs[i]) begin
                    mem_req_valid = 1'b1;
                    mem_req_addr = {bus.fetch_read_addrs[i][31:3], 3'b0};
                    request_pf_index = pf_want_reqs[i] ? pf_indices[i] : 0;
                end
            end
        end

        // write things into memDP,
        // and immediately free one entry if hit
        for (int i = 0; i < `ICACHE_PF_BUFFER_SZ; i++) begin
            if (next_pf_buffer[i].state == PF_STATE_HIT) begin
                pf_has_hit_bits[i] = 1'b1;
            end
        end

        pf_has_hit_bits &= ~(pf_has_hit_bits - 1'b1);
        for (int i = 0; i < `ICACHE_PF_BUFFER_SZ; i++) begin
            if (pf_has_hit_bits[i]) begin
                memDP_write_valid[next_pf_buffer[i].addr[3]] = 1'b1;
                memDP_write_indices[next_pf_buffer[i].addr[3]] = next_pf_buffer[i].addr[7:4];
                memDP_write_data[next_pf_buffer[i].addr[3]] = next_pf_buffer[i].data;
                next_pf_buffer[i].state = PF_STATE_EMPTY;
                next_icache_tags[next_pf_buffer[i].addr[7:3]].valid = 1'b1;
                next_icache_tags[next_pf_buffer[i].addr[7:3]].tag = next_pf_buffer[i].addr[15:8];
            end
        end

        // allocate prefetch entry
        for (int i = 0; i < `ICACHE_PF_BUFFER_SZ; i++) begin
            if (next_pf_buffer[i].state == PF_STATE_EMPTY) begin
                pf_buffer_empty_bits[i] = 1'b1;
            end
        end
        pf_buffer_empty_bits &= ~(pf_buffer_empty_bits - 1'b1);
        if (next_icache_tags[next_prefetch_mem_addr[7:3]].valid && next_icache_tags[next_prefetch_mem_addr[7:3]].tag == next_prefetch_mem_addr[15:8]) begin
            next_prefetch_mem_addr = next_prefetch_mem_addr + 8;
        end else if (pf_buffer_empty_bits != '0) begin
            for (int i = 0; i < `ICACHE_PF_BUFFER_SZ; i++) begin
                if (pf_buffer_empty_bits[i]) begin
                    next_pf_buffer[i].state = PF_STATE_WANT_REQ;
                    next_pf_buffer[i].addr = next_prefetch_mem_addr;
                    next_prefetch_mem_addr += 8;
                end
            end
        end

        // send mem request if not already
        if (!mem_req_valid) begin
            for (int i = 0; i < `ICACHE_PF_BUFFER_SZ; i++) begin
                pf_buffer_want_req_bits[i] = next_pf_buffer[i].state == PF_STATE_WANT_REQ;
            end
            pf_buffer_want_req_bits &= ~(pf_buffer_want_req_bits - 1'b1);
            for (int i = 0; i < `ICACHE_PF_BUFFER_SZ; i++) begin
                if (pf_buffer_want_req_bits[i]) begin
                    request_pf_index = i;
                    mem_req_valid = 1'b1;
                    mem_req_addr = next_pf_buffer[i].addr;
                end
            end
        end
    end

    always_ff @(posedge sys.clock) begin
        if (sys.reset) begin
            icache_tags <= '0;
            pf_buffer <= '0;
            last_request_pf_index <= 0;
            last_mem_req_valid <= 0;
            last_mem_req_addr <= 0;
            prefetch_mem_addr <= 0;
        end else begin
            icache_tags <= next_icache_tags;
            pf_buffer <= next_pf_buffer;
            last_request_pf_index <= request_pf_index;
            last_mem_req_valid <= mem_req_valid;
            last_mem_req_addr <= mem_req_addr;
            prefetch_mem_addr <= next_prefetch_mem_addr;
        end
    end

endmodule
