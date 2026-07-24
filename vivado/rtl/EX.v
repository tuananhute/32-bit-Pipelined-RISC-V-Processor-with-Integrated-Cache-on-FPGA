`timescale 1ns / 1ps

module EX_stage (
    input  wire        clk,
    input  wire        reset,
    input  wire        stall_global,

    // ==================================================
    // INPUT TỪ ID/EX
    // ==================================================
    input  wire [31:0] rs1_data_in,
    input  wire [31:0] rs2_data_in,
    input  wire [31:0] imm_in,
    input  wire [4:0]  rd_in,
    input  wire [3:0]  alu_ctrl_in,
    input  wire        reg_write_in,

    input  wire [2:0]  load_type_in,
    input  wire [1:0]  store_type_in,

    input  wire        alu_src_in,
    input  wire [31:0] pc_in,

    input  wire        is_jal_in,
    input  wire        is_jalr_in,

    // U-type
    input  wire        is_lui_in,
    input  wire        is_auipc_in,

    input  wire        mem_write_in,
    input  wire        mem_read_in,

    input  wire        is_branch_in,
    input  wire [2:0]  branch_type_in,

    input  wire [1:0]  wb_sel_in,

    // ==================================================
    // FORWARDING CONTROL
    // ==================================================
    input  wire [1:0]  forwardA,
    input  wire [1:0]  forwardB,

    // ==================================================
    // FORWARD DATA TỪ MEM
    // ==================================================
    input  wire [31:0] alu_result_M,
    input  wire [31:0] mem_data_M,
    input  wire [31:0] pc_plus4_M,
    input  wire [1:0]  wb_sel_M,

    // ==================================================
    // FORWARD DATA TỪ WB
    // ==================================================
    input  wire [31:0] write_data_W,

    // ==================================================
    // OUTPUT SANG EX/MEM
    // ==================================================
    output reg  [31:0] alu_result_out,
    output reg  [31:0] rs2_data_out,
    output reg  [4:0]  rd_out,
    output reg         reg_write_out,
    output reg  [31:0] pc_plus4_out,

    output reg  [2:0]  load_type_out,
    output reg  [1:0]  store_type_out,

    output reg         mem_write_out,
    output reg         mem_read_out,

    output reg  [1:0]  wb_sel_out,

    // ==================================================
    // PC REDIRECT COMBINATIONAL
    // ==================================================
    output wire [31:0] pc_target_out,
    output wire        pc_src_out,

    output reg         branch_taken_E
);

    //////////////////////////////////////////////////////
    // PC + 4
    //////////////////////////////////////////////////////
    wire [31:0] pc_plus4;

    assign pc_plus4 = pc_in + 32'd4;

    //////////////////////////////////////////////////////
    // FORWARD DATA FROM MEM
    //////////////////////////////////////////////////////
    reg [31:0] forward_data_M;

    always @(*) begin
        case (wb_sel_M)
            2'b00: begin
                // ALU, LUI, AUIPC
                forward_data_M = alu_result_M;
            end

            2'b01: begin
                // LOAD
                forward_data_M = mem_data_M;
            end

            2'b10: begin
                // JAL, JALR
                forward_data_M = pc_plus4_M;
            end

            default: begin
                forward_data_M = alu_result_M;
            end
        endcase
    end

    //////////////////////////////////////////////////////
    // FORWARD SELECT FOR RS1
    //////////////////////////////////////////////////////
    reg [31:0] rs1_final;

    always @(*) begin
        case (forwardA)
            2'b00: begin
                rs1_final = rs1_data_in;
            end

            2'b10: begin
                rs1_final = forward_data_M;
            end

            2'b01: begin
                rs1_final = write_data_W;
            end

            default: begin
                rs1_final = rs1_data_in;
            end
        endcase
    end

    //////////////////////////////////////////////////////
    // FORWARD SELECT FOR RS2
    //////////////////////////////////////////////////////
    reg [31:0] rs2_final;

    always @(*) begin
        case (forwardB)
            2'b00: begin
                rs2_final = rs2_data_in;
            end

            2'b10: begin
                rs2_final = forward_data_M;
            end

            2'b01: begin
                rs2_final = write_data_W;
            end

            default: begin
                rs2_final = rs2_data_in;
            end
        endcase
    end

    //////////////////////////////////////////////////////
    // ALU OPERAND A
    //
    // LUI   : A = 0
    // AUIPC : A = PC
    // JAL   : A = PC
    // Other : A = rs1
    //////////////////////////////////////////////////////
    wire [31:0] operand_A;

    assign operand_A =
        is_lui_in
            ? 32'b0
            : ((is_auipc_in || is_jal_in)
                ? pc_in
                : rs1_final);

    //////////////////////////////////////////////////////
    // ALU OPERAND B
    //
    // I-type, Load, Store : B = immediate
    // LUI, AUIPC, JAL     : B = immediate
    // R-type              : B = rs2
    //////////////////////////////////////////////////////
    wire [31:0] operand_B;

    assign operand_B =
        (alu_src_in ||
         is_lui_in ||
         is_auipc_in ||
         is_jal_in)
            ? imm_in
            : rs2_final;

    //////////////////////////////////////////////////////
    // ALU
    //////////////////////////////////////////////////////
    reg [31:0] alu_result;

    always @(*) begin
        case (alu_ctrl_in)
            4'b0000: begin
                alu_result = operand_A + operand_B;
            end

            4'b0001: begin
                alu_result = operand_A - operand_B;
            end

            4'b0010: begin
                alu_result = operand_A ^ operand_B;
            end

            4'b0011: begin
                alu_result = operand_A | operand_B;
            end

            4'b0100: begin
                alu_result = operand_A & operand_B;
            end

            4'b0101: begin
                alu_result = operand_A << operand_B[4:0];
            end

            4'b0110: begin
                alu_result = operand_A >> operand_B[4:0];
            end

            4'b0111: begin
                alu_result =
                    $signed(operand_A) >>> operand_B[4:0];
            end

            4'b1000: begin
                alu_result =
                    ($signed(operand_A) <
                     $signed(operand_B))
                        ? 32'd1
                        : 32'd0;
            end

            4'b1001: begin
                alu_result =
                    (operand_A < operand_B)
                        ? 32'd1
                        : 32'd0;
            end

            default: begin
                alu_result = 32'b0;
            end
        endcase
    end

    //////////////////////////////////////////////////////
    // BRANCH COMPARATOR
    //////////////////////////////////////////////////////
    always @(*) begin
        branch_taken_E = 1'b0;

        if (is_branch_in) begin
            case (branch_type_in)
                // BEQ
                3'b000: begin
                    branch_taken_E =
                        (rs1_final == rs2_final);
                end

                // BNE
                3'b001: begin
                    branch_taken_E =
                        (rs1_final != rs2_final);
                end

                // BLT
                3'b100: begin
                    branch_taken_E =
                        ($signed(rs1_final) <
                         $signed(rs2_final));
                end

                // BGE
                3'b101: begin
                    branch_taken_E =
                        ($signed(rs1_final) >=
                         $signed(rs2_final));
                end

                // BLTU
                3'b110: begin
                    branch_taken_E =
                        (rs1_final < rs2_final);
                end

                // BGEU
                3'b111: begin
                    branch_taken_E =
                        (rs1_final >= rs2_final);
                end

                default: begin
                    branch_taken_E = 1'b0;
                end
            endcase
        end
    end

    //////////////////////////////////////////////////////
    // PC TARGET
    //////////////////////////////////////////////////////
    wire [31:0] branch_target;
    wire [31:0] jal_target;
    wire [31:0] jalr_target;

    assign branch_target = pc_in + imm_in;
    assign jal_target    = pc_in + imm_in;

    assign jalr_target =
        (rs1_final + imm_in) & 32'hFFFF_FFFE;

    //////////////////////////////////////////////////////
    // PC REDIRECT SELECT
    //////////////////////////////////////////////////////
    assign pc_target_out =
        is_jal_in
            ? jal_target
            : (is_jalr_in
                ? jalr_target
                : ((is_branch_in && branch_taken_E)
                    ? branch_target
                    : pc_in));

    assign pc_src_out =
        is_jal_in ||
        is_jalr_in ||
        (is_branch_in && branch_taken_E);

    //////////////////////////////////////////////////////
    // EX/MEM PIPELINE REGISTER
    //////////////////////////////////////////////////////
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            alu_result_out <= 32'b0;
            rs2_data_out   <= 32'b0;
            rd_out         <= 5'b0;
            reg_write_out  <= 1'b0;
            pc_plus4_out   <= 32'b0;

            load_type_out  <= 3'b0;
            store_type_out <= 2'b0;

            mem_write_out  <= 1'b0;
            mem_read_out   <= 1'b0;

            wb_sel_out     <= 2'b0;
        end
        else if (!stall_global) begin
            alu_result_out <= alu_result;

            // Dữ liệu để SB, SH, SW ghi xuống memory
            rs2_data_out   <= rs2_final;

            rd_out         <= rd_in;
            reg_write_out  <= reg_write_in;
            pc_plus4_out   <= pc_plus4;

            load_type_out  <= load_type_in;
            store_type_out <= store_type_in;

            mem_write_out  <= mem_write_in;
            mem_read_out   <= mem_read_in;

            wb_sel_out     <= wb_sel_in;
        end
    end

endmodule