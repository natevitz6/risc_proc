`ifndef _RISCV32_VECTOR_SV
`define _RISCV32_VECTOR_SV

`include "riscv32_common.sv"

// Enum for supported vector operations (expand as needed)
typedef enum logic [3:0] {
    VOP_NONE   = 4'd0,
    VOP_VADD   = 4'd1,
    VOP_VSUB   = 4'd2,
    VOP_VAND   = 4'd3,
    VOP_VOR    = 4'd4,
    VOP_VXOR   = 4'd5,
    VOP_VLOAD  = 4'd6,
    VOP_VSTORE = 4'd7
    // Add more as needed
} vec_op_t;

// Typedefs for funct3 and funct7 fields
typedef enum logic [2:0] {
    VF3_ADD_SUB = 3'b000,
    VF3_AND     = 3'b100,
    VF3_OR      = 3'b101,
    VF3_XOR     = 3'b110
    // Add more as needed
} vec_funct3_t;

typedef enum logic [6:0] {
    VF7_VADD    = 7'b0000000,
    VF7_VSUB    = 7'b0000101,
    VF7_LOGICAL = 7'b0000110
    // Add more as needed
} vec_funct7_t;

typedef enum logic [6:0] {
    VOPCODE_VECTOR_ALU   = 7'b1010111,
    VOPCODE_VECTOR_LOAD  = 7'b0000111,
    VOPCODE_VECTOR_STORE = 7'b0100111
    // Add more as needed
} vec_opcode_t;

typedef logic [4:0] vec_reg_t;

module riscv32_vector #(
    parameter int VLEN = 128,
    parameter int VREGS = 32,
    parameter int ELEM_WIDTH = 32
) (
    input  logic clk,
    input  logic reset,
    // Interface to core
    input  logic        vec_inst_valid,
    input  logic [31:0] vec_inst,
    input  logic [31:0] rs1_data,
    input  logic [31:0] rs2_data,
    output logic        vec_ready,
    output logic [VLEN-1:0] vec_result,
    // Unified memory interface
    output memory_io_req  data_mem_req,
    input  memory_io_rsp  data_mem_rsp
);

    // Vector register file
    logic [VLEN-1:0] vregfile [VREGS-1:0];

    // Control and configuration registers
    logic [31:0] vl;   // Vector length
    logic [2:0] sew;   // Selected element width

    // Decoded instruction fields
    vec_opcode_t  vec_opcode;
    vec_reg_t     vd, vs1, vs2;
    vec_funct3_t  vec_funct3;
    vec_funct7_t  vec_funct7;
    vec_op_t      vec_op;

    // ALU result (combinational)
    logic [VLEN-1:0] alu_result;

    // FSM for memory handshaking
    typedef enum logic [1:0] {
        VEC_IDLE,
        VEC_MEM_REQ,
        VEC_MEM_WAIT
    } vec_mem_state_t;
    vec_mem_state_t mem_state, mem_state_next;

    // Memory request struct
    memory_io_req mem_req_reg;

    // Decode logic for vector instructions
    always_comb begin
        // Extract fields and cast to enums
        vec_opcode  = vec_opcode_t'(vec_inst[6:0]);
        vd          = vec_inst[11:7];
        vec_funct3  = vec_funct3_t'(vec_inst[14:12]);
        vs1         = vec_inst[19:15];
        vs2         = vec_inst[24:20];
        vec_funct7  = vec_funct7_t'(vec_inst[31:25]);

        vec_op = VOP_NONE;

        if (vec_opcode == VOPCODE_VECTOR_ALU) begin
            case (vec_funct3)
                VF3_ADD_SUB: begin
                    if (vec_funct7 == VF7_VADD) vec_op = VOP_VADD;
                    else if (vec_funct7 == VF7_VSUB) vec_op = VOP_VSUB;
                end
                VF3_AND:     if (vec_funct7 == VF7_LOGICAL) vec_op = VOP_VAND;
                VF3_OR:      if (vec_funct7 == VF7_LOGICAL) vec_op = VOP_VOR;
                VF3_XOR:     if (vec_funct7 == VF7_LOGICAL) vec_op = VOP_VXOR;
                default:     vec_op = VOP_NONE;
            endcase
        end else if (vec_opcode == VOPCODE_VECTOR_LOAD) begin
            vec_op = VOP_VLOAD;
        end else if (vec_opcode == VOPCODE_VECTOR_STORE) begin
            vec_op = VOP_VSTORE;
        end

        // Combinational ALU logic
        alu_result = '0;
        case (vec_op)
            VOP_VADD: for (int i = 0; i < VLEN/ELEM_WIDTH; i++)
                alu_result[i*ELEM_WIDTH +: ELEM_WIDTH] = vregfile[vs1][i*ELEM_WIDTH +: ELEM_WIDTH] +
                                                        vregfile[vs2][i*ELEM_WIDTH +: ELEM_WIDTH];
            VOP_VSUB: for (int i = 0; i < VLEN/ELEM_WIDTH; i++)
                alu_result[i*ELEM_WIDTH +: ELEM_WIDTH] = vregfile[vs1][i*ELEM_WIDTH +: ELEM_WIDTH] -
                                                        vregfile[vs2][i*ELEM_WIDTH +: ELEM_WIDTH];
            VOP_VAND: for (int i = 0; i < VLEN/ELEM_WIDTH; i++)
                alu_result[i*ELEM_WIDTH +: ELEM_WIDTH] = vregfile[vs1][i*ELEM_WIDTH +: ELEM_WIDTH] &
                                                        vregfile[vs2][i*ELEM_WIDTH +: ELEM_WIDTH];
            VOP_VOR: for (int i = 0; i < VLEN/ELEM_WIDTH; i++)
                alu_result[i*ELEM_WIDTH +: ELEM_WIDTH] = vregfile[vs1][i*ELEM_WIDTH +: ELEM_WIDTH] |
                                                        vregfile[vs2][i*ELEM_WIDTH +: ELEM_WIDTH];
            VOP_VXOR: for (int i = 0; i < VLEN/ELEM_WIDTH; i++)
                alu_result[i*ELEM_WIDTH +: ELEM_WIDTH] = vregfile[vs1][i*ELEM_WIDTH +: ELEM_WIDTH] ^
                                                        vregfile[vs2][i*ELEM_WIDTH +: ELEM_WIDTH];
            default: alu_result = '0;
        endcase

        // Default memory request struct
        mem_req_reg = memory_io_no_req;

        // FSM next-state logic
        mem_state_next = mem_state;
        case (mem_state)
            VEC_IDLE: begin
                if (vec_inst_valid && vec_op == VOP_VLOAD)
                    mem_state_next = VEC_MEM_REQ;
                else if (vec_inst_valid && vec_op == VOP_VSTORE)
                    mem_state_next = VEC_MEM_REQ;
            end
            VEC_MEM_REQ: begin
                mem_state_next = VEC_MEM_WAIT;
            end
            VEC_MEM_WAIT: begin
                if (data_mem_rsp.valid && data_mem_rsp.is_vector && vec_op == VOP_VLOAD)
                    mem_state_next = VEC_IDLE;
                else if (vec_op == VOP_VSTORE)
                    mem_state_next = VEC_IDLE;
            end
            default: mem_state_next = VEC_IDLE;
        endcase

        // Fill memory request struct for vector operations
        if (mem_state == VEC_MEM_REQ && vec_op == VOP_VLOAD) begin
            mem_req_reg.valid       = 1'b1;
            mem_req_reg.addr        = rs1_data;
            mem_req_reg.do_read     = 4'b1111;
            mem_req_reg.do_write    = 4'b0000;
            mem_req_reg.is_vector   = 1'b1;
            mem_req_reg.vector_data = '0;
            mem_req_reg.data        = 32'b0;
        end else if (mem_state == VEC_MEM_REQ && vec_op == VOP_VSTORE) begin
            mem_req_reg.valid       = 1'b1;
            mem_req_reg.addr        = rs1_data;
            mem_req_reg.do_read     = 4'b0000;
            mem_req_reg.do_write    = 4'b1111;
            mem_req_reg.is_vector   = 1'b1;
            mem_req_reg.vector_data = vregfile[vs2];
            mem_req_reg.data        = 32'b0;
        end
    end

    // Write-back logic (clocked)
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            vec_ready      <= 1'b0;
            vec_result     <= '0;
            mem_state      <= VEC_IDLE;
        end else begin
            mem_state      <= mem_state_next;
            vec_ready      <= 1'b0;

            if (vec_inst_valid) begin
                // ALU operations: ready immediately
                if (vec_op inside {VOP_VADD, VOP_VSUB, VOP_VAND, VOP_VOR, VOP_VXOR}) begin
                    vregfile[vd] <= alu_result;
                    vec_result   <= alu_result;
                    vec_ready    <= 1'b1;
                end
            end

            // Vector load FSM
            if (mem_state == VEC_MEM_WAIT && vec_op == VOP_VLOAD && data_mem_rsp.valid && data_mem_rsp.is_vector) begin
                vregfile[vd]  <= data_mem_rsp.vector_data;
                vec_result    <= data_mem_rsp.vector_data;
                vec_ready     <= 1'b1;
            end

            // Vector store FSM
            if (mem_state == VEC_MEM_WAIT && vec_op == VOP_VSTORE) begin
                vec_ready     <= 1'b1; // Ready after store request
            end
        end
    end

    // Assign memory request output
    assign data_mem_req = mem_req_reg;

endmodule

`endif