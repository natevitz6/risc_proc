module stride_prefetcher (
    input  logic clk,
    input  logic reset,

    // From cache
    input  memory_io_req32  cache_req,
    output memory_io_rsp32  cache_rsp,

    // To memory
    output memory_io_req32  mem_req,
    input  memory_io_rsp32  mem_rsp
);

`include "riscv32_common.sv"

    typedef enum logic [1:0] {
        IDLE,
        WAIT_CACHE_RESP,
        WAIT_PREFETCH_RESP
    } state_t;

    state_t state;

    memory_io_req32 pending_cache_req;
    logic pending_cache_valid;

    memory_io_req32 next_prefetch_req;
    logic next_prefetch_valid;
    
    logic [31:0] last_addr;
    ext_operand stride;
    assign stride = pending_cache_req.addr - last_addr;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            mem_req <= '0;
            cache_rsp <= '0;
            pending_cache_req <= '0;
            pending_cache_valid <= 0;
            next_prefetch_req <= '0;
            next_prefetch_valid <= 0;
            last_addr <= 0;
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
                      next_prefetch_req <= '0;

                      // Only learn stride and prefetch if it was a read
                      if (pending_cache_req.do_read != 0) begin
                          last_addr <= pending_cache_req.addr;

                          if (last_addr != 0) begin

                              if (stride[32] == 1'b0)
                                  next_prefetch_req.addr <= pending_cache_req.addr + stride[31:0];
                              else
                                  next_prefetch_req.addr <= pending_cache_req.addr - stride[31:0];

                              next_prefetch_req.do_read <= 1;
                              next_prefetch_req.valid <= 1;
                              next_prefetch_req.data <= 0;
                              next_prefetch_req.user_tag <= 0;
                              next_prefetch_valid <= 1;
                          end
                      end

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

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule
