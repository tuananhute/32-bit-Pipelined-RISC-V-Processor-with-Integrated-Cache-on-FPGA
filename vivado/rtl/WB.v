`timescale 1ns / 1ps

module WB_stage (
    input  wire        reset,

    // Input từ MEM/WB
    input  wire [31:0] mem_data_in,
    input  wire [31:0] alu_result_in,
    input  wire [31:0] pc_plus4_in,
    input  wire [4:0]  rd_in,
    input  wire        reg_write_in,
    input  wire [1:0]  wb_sel_in,

    // Output về Register File
    output reg  [31:0] write_data_out,
    output reg  [4:0]  rd_out,
    output reg         reg_write_out
);

    always @(*) begin
        // Giá trị mặc định để tránh latch
        write_data_out = 32'b0;
        rd_out         = 5'b0;
        reg_write_out  = 1'b0;

        if (!reset) begin
            rd_out         = rd_in;
            reg_write_out  = reg_write_in;

            case (wb_sel_in)
                // R-type, I-type, LUI, AUIPC
                2'b00: begin
                    write_data_out = alu_result_in;
                end

                // LB, LH, LW, LBU, LHU
                2'b01: begin
                    write_data_out = mem_data_in;
                end

                // JAL, JALR
                2'b10: begin
                    write_data_out = pc_plus4_in;
                end

                // Không sử dụng
                default: begin
                    write_data_out = 32'b0;
                end
            endcase
        end
    end

endmodule