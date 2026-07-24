`timescale 1ns / 1ps

module IF_stage (
    input  wire        clk,
    input  wire        reset,

    // Hazard control
    input  wire        stall_F,
    input  wire        stall_D,
    input  wire        flush_D,

    // I-cache control
    input  wire        stall_icache,
    input  wire        miss_in,

    // Branch, JAL, JALR redirect từ EX
    input  wire [31:0] pc_branch,
    input  wire        pc_control,

    // Instruction cache interface
    output wire [31:0] pc_out,
    input  wire [31:0] instr_in,

    // IF/ID pipeline outputs
    output reg  [31:0] instr_out,
    output reg  [31:0] next_pc_out
);

    reg [31:0] pc;

    wire [31:0] pc_plus4;

    assign pc_plus4 = pc + 32'd4;
    assign pc_out   = pc;

    //////////////////////////////////////////////////////
    // PC REGISTER
    //////////////////////////////////////////////////////
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            pc <= 32'h0000_0000;
        end

        // Branch/JAL/JALR có ưu tiên cao nhất
        else if (pc_control) begin
            pc <= pc_branch;
        end

        // Giữ PC tại địa chỉ đang cache miss
        else if (
            stall_F       ||
            stall_icache  ||
            miss_in
        ) begin
            pc <= pc;
        end

        else begin
            pc <= pc_plus4;
        end
    end

    //////////////////////////////////////////////////////
    // IF/ID PIPELINE REGISTER
    //////////////////////////////////////////////////////
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            instr_out   <= 32'h0000_0013;
            next_pc_out <= 32'h0000_0000;
        end

        // Flush do branch/JAL/JALR
        else if (flush_D) begin
            instr_out   <= 32'h0000_0013;
            next_pc_out <= 32'h0000_0000;
        end

        // Data hazard hoặc D-cache stall:
        // phải giữ nguyên lệnh hiện tại ở ID
        else if (stall_D) begin
            instr_out   <= instr_out;
            next_pc_out <= next_pc_out;
        end

        // I-cache miss:
        // không giữ lệnh cũ mà chèn NOP vào ID
        else if (stall_icache || miss_in) begin
            instr_out   <= 32'h0000_0013;
            next_pc_out <= pc;
        end

        // I-cache hit:
        // lấy lệnh thật vào IF/ID
        else begin
            instr_out   <= instr_in;
            next_pc_out <= pc;
        end
    end

endmodule