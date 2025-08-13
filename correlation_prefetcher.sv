module correlation_prefetcher #(
    parameter TABLE_SIZE = 8  // Number of correlation entries (must be power of 2)
)(
    input  logic clk,
    input  logic reset,

    // From cache
    input  memory_io_req32  cache_req,
    output memory_io_rsp32  cache_rsp,

    // To memory
    output memory_io_req32  mem_req,
    input  memory_io_rsp32  mem_rsp
);

    typedef enum logic [1:0] {
        IDLE,
        WAIT_CACHE_RESP,
        WAIT_PREFETCH_RESP
    } state_t;

    typedef struct packed {
        logic        valid;
        logic [31:0] tag;
        logic [31:0] next_addr;
    } corr_entry_t;

    state_t state;
    corr_entry_t [TABLE_SIZE-1:0] corr_table;
    corr_entry_t curr_entry;
    logic [31:0] prev_addr;
    logic prev_valid;

    memory_io_req32 pending_cache_req;
    logic pending_cache_valid;

    memory_io_req32 next_prefetch_req;
    logic next_prefetch_valid;

    localparam ENTRY_BITS = $clog2(TABLE_SIZE);

    assign curr_entry = corr_table[pending_cache_req.addr[ENTRY_BITS-1:0]];

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            mem_req <= '0;
            cache_rsp <= '0;
            pending_cache_req <= '0;
            pending_cache_valid <= 0;
            next_prefetch_req <= '0;
            next_prefetch_valid <= 0;
            corr_table <= '{default:0};
            prev_addr <= 0;
            prev_valid <= 0;
        end else begin
            cache_rsp <= '0;
            case (state)
                IDLE: begin
                    if (cache_req.valid) begin
                        mem_req <= cache_req;
                        pending_cache_req <= cache_req;
                        pending_cache_valid <= 1;
                        state <= WAIT_CACHE_RESP;
                    end else if (next_prefetch_valid) begin
                        mem_req <= next_prefetch_req;
                        state <= WAIT_PREFETCH_RESP;
                    end else begin
                        mem_req <= '0;
                    end
                end

                WAIT_CACHE_RESP: begin
                    mem_req <= '0;
                    if (mem_rsp.valid && mem_rsp.addr == pending_cache_req.addr) begin
                        cache_rsp <= mem_rsp;
                        cache_rsp.valid <= 1;
                        pending_cache_valid <= 0;

                        if (prev_valid) begin
                            corr_table[prev_addr[ENTRY_BITS-1:0]] <= '{
                                valid: 1'b1,
                                tag: prev_addr,
                                next_addr: pending_cache_req.addr
                            };
                        end

                        if (curr_entry.valid && curr_entry.tag == pending_cache_req.addr) begin
                            next_prefetch_req <= '{
                                addr: curr_entry.next_addr,
                                data: 0,
                                do_read: 4'b1,
                                do_write: 4'b0,
                                valid: 1'b1,
                                dummy: 3'b0,
                                user_tag: 0
                            };
                            next_prefetch_valid <= 1;
                        end else begin
                            next_prefetch_valid <= 0;
                        end

                        // Store current address for next correlation
                        prev_addr <= pending_cache_req.addr;
                        prev_valid <= 1;
                        
                        state <= IDLE;
                    end
                end

                WAIT_PREFETCH_RESP: begin
                    mem_req.valid <= '0;
                    if (cache_req.valid && (cache_req.addr != mem_req.addr || cache_req.do_write != 0)) begin
                        mem_req <= cache_req;
                        pending_cache_req <= cache_req;
                        state <= WAIT_CACHE_RESP;
                    end else if (mem_rsp.valid) begin
                        cache_rsp <= mem_rsp;
                        cache_rsp.valid <= 1;
                        next_prefetch_valid <= 0;
                        state <= IDLE;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end
endmodule
