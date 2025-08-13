module block_delay #(
    parameter int N = 4  // Delay in cycles
) (
    input logic clk,
    input logic reset,

    input  memory_io_req  from_core,
    output memory_io_rsp  to_core,

    output memory_io_req  to_memory,
    input  memory_io_rsp  from_memory
);

    typedef struct packed {
        memory_io_req req;
        int delay_count;
    } delayed_req_t;

    // Internal state
    delayed_req_t req_reg;
    logic req_pending;

    // Default outputs
    assign to_core = from_memory.valid ? from_memory : memory_io_no_rsp;
    assign to_memory = (req_pending && req_reg.delay_count == 0) ? req_reg.req : memory_io_no_req;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            req_reg <= '{req: memory_io_no_req, delay_count: 0};
            req_pending <= 0;
        end else begin
            if (from_core.valid) begin
                req_reg <= '{req: from_core, delay_count: N};
                req_pending <= 1;
            end else if (req_pending) begin
                if (req_reg.delay_count > 0) begin
                    req_reg.delay_count <= req_reg.delay_count - 1;
                end else begin
                    req_pending <= 0;
                end
            end
        end
    end

endmodule
