`timescale 1ns / 1ps

module ID_stage (
    input  wire        clk,
    input  wire        reset,

    // ==================================================
    // INPUT TỪ IF/ID
    // ==================================================
    input  wire [31:0] instr_in,
    input  wire [31:0] pc_in,

    // ==================================================
    // HAZARD CONTROL
    // ==================================================
    input  wire        stall_D,
    input  wire        flush_E,

    // ==================================================
    // WRITE BACK
    // ==================================================
    input  wire        reg_write_wb,
    input  wire [4:0]  rd_wb,
    input  wire [31:0] write_data_wb,

    // ==================================================
    // OUTPUT CHO HAZARD UNIT
    // ==================================================
    output wire [4:0]  rs1_out,
    output wire [4:0]  rs2_out,

    // Register index của lệnh đang ở EX
    output reg  [4:0]  rs1_E_out,
    output reg  [4:0]  rs2_E_out,

    // ==================================================
    // OUTPUT SANG ID/EX
    // ==================================================
    output reg  [31:0] rs1_data_out,
    output reg  [31:0] rs2_data_out,
    output reg  [31:0] imm_out,
    output reg  [4:0]  rd_out,

    output reg  [3:0]  alu_ctrl_out,
    output reg         reg_write_out,
    output reg         alu_src_out,

    output reg  [31:0] pc_out,

    // J-type
    output reg         is_jal_out,
    output reg         is_jalr_out,

    // U-type
    output reg         is_lui_out,
    output reg         is_auipc_out,

    // Load/store
    output reg  [2:0]  load_type_out,
    output reg  [1:0]  store_type_out,
    output reg         mem_write_out,
    output reg         mem_read_out,

    // Write-back select
    output reg  [1:0]  wb_sel_out,

    // Branch
    output reg         is_branch_out,
    output reg  [2:0]  branch_type_out
);

    //////////////////////////////////////////////////////
    // INSTRUCTION FIELDS
    //////////////////////////////////////////////////////
    wire [6:0] opcode;
    wire [4:0] rs1;
    wire [4:0] rs2;
    wire [4:0] rd;
    wire [2:0] funct3;
    wire [6:0] funct7;

    assign opcode = instr_in[6:0];
    assign rs1    = instr_in[19:15];
    assign rs2    = instr_in[24:20];
    assign rd     = instr_in[11:7];
    assign funct3 = instr_in[14:12];
    assign funct7 = instr_in[31:25];

    assign rs1_out = rs1;
    assign rs2_out = rs2;

    //////////////////////////////////////////////////////
    // REGISTER FILE
    //////////////////////////////////////////////////////
    reg [31:0] regfile [0:31];

    integer i;

    // Khởi tạo phục vụ simulation:
    // x0 = 0, x1 = 1, ..., x31 = 31
    initial begin
        for (i = 0; i < 32; i = i + 1) begin
            regfile[i] = i;
        end
    end

    //////////////////////////////////////////////////////
    // WRITE REGISTER FILE
    //////////////////////////////////////////////////////
    always @(posedge clk) begin
        if (reg_write_wb && (rd_wb != 5'd0)) begin
            regfile[rd_wb] <= write_data_wb;
        end
    end

    //////////////////////////////////////////////////////
    // REGISTER FILE READ + WB BYPASS
    //////////////////////////////////////////////////////
    wire [31:0] rs1_data;
    wire [31:0] rs2_data;

    assign rs1_data =
        (rs1 == 5'd0)
            ? 32'b0
            : ((reg_write_wb &&
                (rd_wb != 5'd0) &&
                (rd_wb == rs1))
                ? write_data_wb
                : regfile[rs1]);

    assign rs2_data =
        (rs2 == 5'd0)
            ? 32'b0
            : ((reg_write_wb &&
                (rd_wb != 5'd0) &&
                (rd_wb == rs2))
                ? write_data_wb
                : regfile[rs2]);

    //////////////////////////////////////////////////////
    // IMMEDIATE GENERATION
    //////////////////////////////////////////////////////

    // I-type, Load, JALR
    wire [31:0] imm_i;

    assign imm_i = {
        {20{instr_in[31]}},
        instr_in[31:20]
    };

    // S-type
    wire [31:0] imm_s;

    assign imm_s = {
        {20{instr_in[31]}},
        instr_in[31:25],
        instr_in[11:7]
    };

    // B-type
    wire [31:0] imm_b;

    assign imm_b = {
        {19{instr_in[31]}},
        instr_in[31],
        instr_in[7],
        instr_in[30:25],
        instr_in[11:8],
        1'b0
    };

    // J-type
    wire [31:0] imm_j;

    assign imm_j = {
        {11{instr_in[31]}},
        instr_in[31],
        instr_in[19:12],
        instr_in[20],
        instr_in[30:21],
        1'b0
    };

    // Shift amount
    wire [31:0] imm_shamt;

    assign imm_shamt = {
        27'b0,
        instr_in[24:20]
    };

    // U-type
    wire [31:0] imm_u;

    assign imm_u = {
        instr_in[31:12],
        12'b0
    };

    //////////////////////////////////////////////////////
    // INTERNAL CONTROL SIGNALS
    //////////////////////////////////////////////////////
    reg [3:0] alu_ctrl;
    reg       reg_write;
    reg       alu_src;

    reg       is_jal;
    reg       is_jalr;

    reg       is_lui;
    reg       is_auipc;

    reg       is_shift;

    reg [2:0] load_type;
    reg [1:0] store_type;

    reg       mem_write;
    reg       mem_read;

    reg [1:0] wb_sel;

    reg       is_branch;
    reg [2:0] branch_type;

    //////////////////////////////////////////////////////
    // MAIN DECODER
    //////////////////////////////////////////////////////
    always @(*) begin
        // Mặc định tương đương NOP
        alu_ctrl   = 4'b0000;
        reg_write  = 1'b0;
        alu_src    = 1'b0;

        is_jal     = 1'b0;
        is_jalr    = 1'b0;

        is_lui     = 1'b0;
        is_auipc   = 1'b0;

        is_shift   = 1'b0;

        load_type  = 3'b000;
        store_type = 2'b00;

        mem_write  = 1'b0;
        mem_read   = 1'b0;

        wb_sel     = 2'b00;

        is_branch  = 1'b0;
        branch_type = 3'b000;

        case (opcode)

            //////////////////////////////////////////////////
            // LUI
            // rd = U-immediate
            //////////////////////////////////////////////////
            7'b0110111: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                alu_ctrl  = 4'b0000;
                wb_sel    = 2'b00;
                is_lui    = 1'b1;
            end

            //////////////////////////////////////////////////
            // AUIPC
            // rd = PC + U-immediate
            //////////////////////////////////////////////////
            7'b0010111: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                alu_ctrl  = 4'b0000;
                wb_sel    = 2'b00;
                is_auipc  = 1'b1;
            end

            //////////////////////////////////////////////////
            // R-TYPE
            //////////////////////////////////////////////////
            7'b0110011: begin
                case (funct3)
                    // ADD / SUB
                    3'b000: begin
                        reg_write = 1'b1;

                        if (funct7 == 7'b0100000)
                            alu_ctrl = 4'b0001;
                        else
                            alu_ctrl = 4'b0000;
                    end

                    // SLL
                    3'b001: begin
                        reg_write = 1'b1;
                        alu_ctrl  = 4'b0101;
                    end

                    // SLT
                    3'b010: begin
                        reg_write = 1'b1;
                        alu_ctrl  = 4'b1000;
                    end

                    // SLTU
                    3'b011: begin
                        reg_write = 1'b1;
                        alu_ctrl  = 4'b1001;
                    end

                    // XOR
                    3'b100: begin
                        reg_write = 1'b1;
                        alu_ctrl  = 4'b0010;
                    end

                    // SRL / SRA
                    3'b101: begin
                        reg_write = 1'b1;

                        if (funct7 == 7'b0100000)
                            alu_ctrl = 4'b0111;
                        else
                            alu_ctrl = 4'b0110;
                    end

                    // OR
                    3'b110: begin
                        reg_write = 1'b1;
                        alu_ctrl  = 4'b0011;
                    end

                    // AND
                    3'b111: begin
                        reg_write = 1'b1;
                        alu_ctrl  = 4'b0100;
                    end

                    default: begin
                        reg_write = 1'b0;
                    end
                endcase
            end

            //////////////////////////////////////////////////
            // I-TYPE ALU
            //////////////////////////////////////////////////
            7'b0010011: begin
                case (funct3)
                    // ADDI
                    3'b000: begin
                        reg_write = 1'b1;
                        alu_src   = 1'b1;
                        alu_ctrl  = 4'b0000;
                    end

                    // SLLI
                    3'b001: begin
                        reg_write = 1'b1;
                        alu_src   = 1'b1;
                        alu_ctrl  = 4'b0101;
                        is_shift  = 1'b1;
                    end

                    // SLTI
                    3'b010: begin
                        reg_write = 1'b1;
                        alu_src   = 1'b1;
                        alu_ctrl  = 4'b1000;
                    end

                    // SLTIU
                    3'b011: begin
                        reg_write = 1'b1;
                        alu_src   = 1'b1;
                        alu_ctrl  = 4'b1001;
                    end

                    // XORI
                    3'b100: begin
                        reg_write = 1'b1;
                        alu_src   = 1'b1;
                        alu_ctrl  = 4'b0010;
                    end

                    // SRLI / SRAI
                    3'b101: begin
                        reg_write = 1'b1;
                        alu_src   = 1'b1;
                        is_shift  = 1'b1;

                        if (funct7 == 7'b0100000)
                            alu_ctrl = 4'b0111;
                        else
                            alu_ctrl = 4'b0110;
                    end

                    // ORI
                    3'b110: begin
                        reg_write = 1'b1;
                        alu_src   = 1'b1;
                        alu_ctrl  = 4'b0011;
                    end

                    // ANDI
                    3'b111: begin
                        reg_write = 1'b1;
                        alu_src   = 1'b1;
                        alu_ctrl  = 4'b0100;
                    end

                    default: begin
                        reg_write = 1'b0;
                        alu_src   = 1'b0;
                    end
                endcase
            end

            //////////////////////////////////////////////////
            // LOAD
            //////////////////////////////////////////////////
            7'b0000011: begin
                case (funct3)
                    // LB
                    3'b000: begin
                        reg_write = 1'b1;
                        alu_src   = 1'b1;
                        alu_ctrl  = 4'b0000;
                        mem_read  = 1'b1;
                        wb_sel    = 2'b01;
                        load_type = 3'b000;
                    end

                    // LH
                    3'b001: begin
                        reg_write = 1'b1;
                        alu_src   = 1'b1;
                        alu_ctrl  = 4'b0000;
                        mem_read  = 1'b1;
                        wb_sel    = 2'b01;
                        load_type = 3'b001;
                    end

                    // LW
                    3'b010: begin
                        reg_write = 1'b1;
                        alu_src   = 1'b1;
                        alu_ctrl  = 4'b0000;
                        mem_read  = 1'b1;
                        wb_sel    = 2'b01;
                        load_type = 3'b010;
                    end

                    // LBU
                    3'b100: begin
                        reg_write = 1'b1;
                        alu_src   = 1'b1;
                        alu_ctrl  = 4'b0000;
                        mem_read  = 1'b1;
                        wb_sel    = 2'b01;
                        load_type = 3'b100;
                    end

                    // LHU
                    3'b101: begin
                        reg_write = 1'b1;
                        alu_src   = 1'b1;
                        alu_ctrl  = 4'b0000;
                        mem_read  = 1'b1;
                        wb_sel    = 2'b01;
                        load_type = 3'b101;
                    end

                    default: begin
                        reg_write = 1'b0;
                        mem_read  = 1'b0;
                    end
                endcase
            end

            //////////////////////////////////////////////////
            // STORE
            //////////////////////////////////////////////////
            7'b0100011: begin
                case (funct3)
                    // SB
                    3'b000: begin
                        alu_src    = 1'b1;
                        alu_ctrl   = 4'b0000;
                        mem_write  = 1'b1;
                        store_type = 2'b00;
                    end

                    // SH
                    3'b001: begin
                        alu_src    = 1'b1;
                        alu_ctrl   = 4'b0000;
                        mem_write  = 1'b1;
                        store_type = 2'b01;
                    end

                    // SW
                    3'b010: begin
                        alu_src    = 1'b1;
                        alu_ctrl   = 4'b0000;
                        mem_write  = 1'b1;
                        store_type = 2'b10;
                    end

                    default: begin
                        mem_write = 1'b0;
                    end
                endcase
            end

            //////////////////////////////////////////////////
            // BRANCH
            //////////////////////////////////////////////////
            7'b1100011: begin
                case (funct3)
                    // BEQ
                    3'b000: begin
                        is_branch   = 1'b1;
                        branch_type = 3'b000;
                    end

                    // BNE
                    3'b001: begin
                        is_branch   = 1'b1;
                        branch_type = 3'b001;
                    end

                    // BLT
                    3'b100: begin
                        is_branch   = 1'b1;
                        branch_type = 3'b100;
                    end

                    // BGE
                    3'b101: begin
                        is_branch   = 1'b1;
                        branch_type = 3'b101;
                    end

                    // BLTU
                    3'b110: begin
                        is_branch   = 1'b1;
                        branch_type = 3'b110;
                    end

                    // BGEU
                    3'b111: begin
                        is_branch   = 1'b1;
                        branch_type = 3'b111;
                    end

                    default: begin
                        is_branch = 1'b0;
                    end
                endcase
            end

            //////////////////////////////////////////////////
            // JAL
            //////////////////////////////////////////////////
            7'b1101111: begin
                reg_write = 1'b1;
                is_jal    = 1'b1;
                wb_sel    = 2'b10;
            end

            //////////////////////////////////////////////////
            // JALR
            //////////////////////////////////////////////////
            7'b1100111: begin
                if (funct3 == 3'b000) begin
                    reg_write = 1'b1;
                    alu_src   = 1'b1;
                    alu_ctrl  = 4'b0000;
                    is_jalr   = 1'b1;
                    wb_sel    = 2'b10;
                end
            end

            //////////////////////////////////////////////////
            // Không hỗ trợ opcode khác
            // Tự động hoạt động như NOP
            //////////////////////////////////////////////////
            default: begin
                reg_write = 1'b0;
                mem_write = 1'b0;
                mem_read  = 1'b0;
                is_branch = 1'b0;
                is_jal    = 1'b0;
                is_jalr   = 1'b0;
            end
        endcase
    end

    //////////////////////////////////////////////////////
    // ID/EX PIPELINE REGISTER
    //////////////////////////////////////////////////////
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            rs1_data_out    <= 32'b0;
            rs2_data_out    <= 32'b0;
            imm_out         <= 32'b0;
            rd_out          <= 5'b0;

            alu_ctrl_out    <= 4'b0;
            reg_write_out   <= 1'b0;
            alu_src_out     <= 1'b0;

            pc_out          <= 32'b0;

            is_jal_out      <= 1'b0;
            is_jalr_out     <= 1'b0;
            is_lui_out      <= 1'b0;
            is_auipc_out    <= 1'b0;

            load_type_out   <= 3'b0;
            store_type_out  <= 2'b0;

            mem_write_out   <= 1'b0;
            mem_read_out    <= 1'b0;

            wb_sel_out      <= 2'b0;

            rs1_E_out       <= 5'b0;
            rs2_E_out       <= 5'b0;

            is_branch_out   <= 1'b0;
            branch_type_out <= 3'b0;
        end

        // Flush ID/EX: chèn NOP vào EX
        else if (flush_E) begin
            rs1_data_out    <= 32'b0;
            rs2_data_out    <= 32'b0;
            imm_out         <= 32'b0;
            rd_out          <= 5'b0;

            alu_ctrl_out    <= 4'b0;
            reg_write_out   <= 1'b0;
            alu_src_out     <= 1'b0;

            pc_out          <= 32'b0;

            is_jal_out      <= 1'b0;
            is_jalr_out     <= 1'b0;
            is_lui_out      <= 1'b0;
            is_auipc_out    <= 1'b0;

            load_type_out   <= 3'b0;
            store_type_out  <= 2'b0;

            mem_write_out   <= 1'b0;
            mem_read_out    <= 1'b0;

            wb_sel_out      <= 2'b0;

            rs1_E_out       <= 5'b0;
            rs2_E_out       <= 5'b0;

            is_branch_out   <= 1'b0;
            branch_type_out <= 3'b0;
        end

        // Không stall thì nạp lệnh mới vào ID/EX
        else if (!stall_D) begin
            rs1_data_out <= rs1_data;
            rs2_data_out <= rs2_data;

            rs1_E_out <= rs1;
            rs2_E_out <= rs2;

            //////////////////////////////////////////////////
            // Immediate selection
            //////////////////////////////////////////////////
            if (is_jal) begin
                imm_out <= imm_j;
            end
            else if (is_branch) begin
                imm_out <= imm_b;
            end
            else if (is_lui || is_auipc) begin
                imm_out <= imm_u;
            end
            else if (is_shift) begin
                imm_out <= imm_shamt;
            end
            else if (opcode == 7'b0100011) begin
                imm_out <= imm_s;
            end
            else begin
                imm_out <= imm_i;
            end

            rd_out        <= rd;
            alu_ctrl_out  <= alu_ctrl;
            reg_write_out <= reg_write;
            alu_src_out   <= alu_src;

            pc_out <= pc_in;

            is_jal_out   <= is_jal;
            is_jalr_out  <= is_jalr;
            is_lui_out   <= is_lui;
            is_auipc_out <= is_auipc;

            load_type_out  <= load_type;
            store_type_out <= store_type;

            mem_write_out <= mem_write;
            mem_read_out  <= mem_read;

            wb_sel_out <= wb_sel;

            is_branch_out   <= is_branch;
            branch_type_out <= branch_type;
        end
    end

endmodule