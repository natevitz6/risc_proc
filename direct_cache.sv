`include "system.sv"
`include "memory_io.sv"

module direct_cache #(
    parameter CACHE_SIZE = 64
)(
    input clk,
    input reset,
    // Core interface
    input memory_io_req32  core_req,
    output memory_io_rsp32 core_rsp,
    // Memory interface
    output memory_io_req32 mem_req,
    input memory_io_rsp32  mem_rsp
);
int hits;
int miss;
localparam INDEX_BITS = $clog2(CACHE_SIZE);
localparam TAG_BITS = `word_address_size - INDEX_BITS;

typedef struct packed {
    logic valid;
    logic [TAG_BITS-1:0] tag;
    logic [31:0] data;
} cache_entry_t;

cache_entry_t [CACHE_SIZE-1:0] cache;
logic [TAG_BITS-1:0] current_tag, prefetch_tag;
logic [INDEX_BITS-1:0] current_index, prefetch_index;

// State machine
typedef enum logic [1:0] {IDLE, FETCH} state_t;
state_t state;
memory_io_req32 saved_req;

// Address decomposition
assign current_tag = (state == IDLE) ? core_req.addr[`word_address_size-1 : INDEX_BITS] : saved_req.addr[`word_address_size-1 : INDEX_BITS];
assign current_index = (state == IDLE) ? core_req.addr[INDEX_BITS-1 : 0] : saved_req.addr[INDEX_BITS-1 : 0];

assign prefetch_tag   = mem_rsp.addr[`word_address_size-1 : INDEX_BITS];
assign prefetch_index = mem_rsp.addr[INDEX_BITS-1 : 0];

// Hit detection
logic hit;
assign hit = cache[current_index].valid && 
            (cache[current_index].tag == current_tag);

always_ff @(posedge clk) begin     
    if(reset) begin
        state <= IDLE;
        miss <= 0;
        hits <= 0;
        foreach(cache[i]) cache[i].valid <= 0;
    end else begin
        core_rsp <= 0;
        core_rsp.ready <= 1;
        mem_req <= 0;

        case(state)
            IDLE: begin
                if(mem_rsp.valid && mem_rsp.addr != saved_req.addr && !core_req.valid) begin
                    // Prefetch response while cache is idle and no active request
                    cache[prefetch_index].valid <= 1'b1;
                    cache[prefetch_index].tag <= prefetch_tag;
                    cache[prefetch_index].data <= mem_rsp.data;
                end

                if(core_req.valid) begin
                    saved_req <= core_req;
                    if(core_req.do_read != 0) begin
                        if (hit) begin
                            hits <= hits + 1;
                            core_rsp.data <= cache[current_index].data;
                            core_rsp.valid <= 1'b1;
                        end else begin
                            miss <= miss + 1;
                            state <= FETCH;
                            mem_req <= core_req;
                            core_rsp.ready <= 0;
                        end
                    end else if(core_req.do_write != 0) begin
                        cache[current_index].valid <= 1'b1;
                        cache[current_index].tag <= current_tag;
                        cache[current_index].data <= core_req.data;
                        mem_req <= core_req;
                        state <= FETCH;
                    end
                end
            end

            FETCH: begin
                mem_req.valid <= 0;
                core_rsp.ready <= 0;

                if(mem_rsp.valid) begin
                    if (mem_rsp.addr == saved_req.addr) begin
                        if (saved_req.do_read != 0) begin
                            cache[current_index].valid <= 1'b1;
                            cache[current_index].tag <= current_tag;
                            cache[current_index].data <= mem_rsp.data;
                        end
                        core_rsp <= mem_rsp;
                        core_rsp.user_tag <= saved_req.user_tag;
                        state <= IDLE;
                    end else begin
                        // Prefetch response during fetch (ignore if not needed)
                        cache[prefetch_index].valid <= 1'b1;
                        cache[prefetch_index].tag <= prefetch_tag;
                        cache[prefetch_index].data <= mem_rsp.data;
                    end
                end
            end

            default: begin
                state <= IDLE;
            end
        endcase
    end
end
endmodule