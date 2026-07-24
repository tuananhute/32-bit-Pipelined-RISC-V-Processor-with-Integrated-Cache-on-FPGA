`timescale 1ns / 1ps

module icache_4way #(
    parameter SET_NUM = 16,
    parameter WAY_NUM = 4
)(
    input  wire        clk,
    input  wire        reset,
    input  wire        flush_icache,

    input  wire [31:0] pc,

    output wire [31:0] instr,
    output wire        miss,

    output reg  [31:0] imem_addr,
    input  wire [31:0] imem_rdata
);

    // =========================================================
    // Cache organization
    //
    // 16 sets
    // 4 ways per set
    // 1 instruction = 4 bytes per cache line
    //
    // Total cache data:
    // 16 × 4 × 4 bytes = 256 bytes
    // =========================================================
    (* ram_style = "block" *)
    reg [31:0] cache_mem
        [0:SET_NUM-1][0:WAY_NUM-1];

    reg [25:0] cache_tag
        [0:SET_NUM-1][0:WAY_NUM-1];

    reg cache_valid
        [0:SET_NUM-1][0:WAY_NUM-1];

    /*
     * lru_order[set][0]             : MRU way
     * lru_order[set][WAY_NUM - 1]   : LRU way
     */
    reg [1:0] lru_order
        [0:SET_NUM-1][0:WAY_NUM-1];

    integer i;
    integer j;
    integer k;
    integer s;
    integer w;

    reg [1:0] used_way;

    reg [1:0] temp_refill [0:WAY_NUM-1];
    reg [1:0] temp_hit    [0:WAY_NUM-1];

    // =========================================================
    // Address decoding for 16 sets
    //
    // pc[1:0]  : byte offset
    // pc[5:2]  : set index, 4 bits
    // pc[31:6] : tag, 26 bits
    // =========================================================

    wire [3:0]  index;
    wire [25:0] tag;

    assign index = pc[5:2];
    assign tag   = pc[31:6];

    // PC that caused the current cache miss
    reg [31:0] miss_pc;

    wire [3:0]  refill_index;
    wire [25:0] refill_tag;

    assign refill_index = miss_pc[5:2];
    assign refill_tag   = miss_pc[31:6];

    // =========================================================
    // Cache hit detection
    // =========================================================

    reg        hit;
    reg [1:0]  hit_way;
    reg [31:0] hit_instr;

    always @(*) begin
        hit       = 1'b0;
        hit_way   = 2'b00;
        hit_instr = 32'h00000013;

        for (i = 0; i < WAY_NUM; i = i + 1) begin
            if (
                cache_valid[index][i] &&
                (cache_tag[index][i] == tag)
            ) begin
                hit       = 1'b1;
                hit_way   = i[1:0];
                hit_instr = cache_mem[index][i];
            end
        end
    end

    // =========================================================
    // Cache controller FSM
    // =========================================================

    localparam IDLE     = 2'd0;
    localparam MEM_REQ  = 2'd1;
    localparam WAIT_MEM = 2'd2;
    localparam REFILL   = 2'd3;

    reg [1:0] state;

    // =========================================================
    // Miss signal
    // =========================================================

    assign miss =
        (!hit) ||
        (state != IDLE);

    // =========================================================
    // Instruction output
    // =========================================================

    assign instr =
        (reset || flush_icache)
        ? 32'h00000013
        : (
            ((state == IDLE) && hit)
            ? hit_instr
            : 32'h00000013
        );

    // =========================================================
    // Cache controller FSM
    // =========================================================

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state     <= IDLE;
            miss_pc   <= 32'b0;
            imem_addr <= 32'b0;
        end
        else begin
            if (flush_icache) begin
                state     <= IDLE;
                miss_pc   <= 32'b0;
                imem_addr <= 32'b0;
            end
            else begin
                case (state)

                    IDLE: begin
                        if (!hit) begin
                            miss_pc   <= pc;
                            imem_addr <= pc;
                            state     <= MEM_REQ;
                        end
                    end

                    MEM_REQ: begin
                        state <= WAIT_MEM;
                    end

                    WAIT_MEM: begin
                        state <= REFILL;
                    end

                    REFILL: begin
                        state <= IDLE;
                    end

                    default: begin
                        state <= IDLE;
                    end

                endcase
            end
        end
    end

    // =========================================================
    // Cache data, valid bits and LRU
    // =========================================================

    always @(posedge clk or posedge reset) begin
        if (reset) begin

            // Clear all 16 sets and all 4 ways
            for (s = 0; s < SET_NUM; s = s + 1) begin
                for (w = 0; w < WAY_NUM; w = w + 1) begin
                    cache_mem[s][w]   <= 32'b0;
                    cache_tag[s][w]   <= 26'b0;
                    cache_valid[s][w] <= 1'b0;

                    lru_order[s][w] <= w[1:0];
                end
            end
        end
        else begin

            // =================================================
            // Invalidate the entire instruction cache
            // =================================================

            if (flush_icache) begin
                for (s = 0; s < SET_NUM; s = s + 1) begin
                    for (w = 0; w < WAY_NUM; w = w + 1) begin
                        cache_valid[s][w] <= 1'b0;
                        lru_order[s][w]   <= w[1:0];
                    end
                end
            end
            else begin

                // =============================================
                // Cache refill
                // =============================================

                if (state == WAIT_MEM) begin

                    // Select the least recently used way
                    used_way =
                        lru_order
                        [refill_index]
                        [WAY_NUM-1];

                    cache_mem
                        [refill_index]
                        [used_way]
                        <= imem_rdata;

                    cache_tag
                        [refill_index]
                        [used_way]
                        <= refill_tag;

                    cache_valid
                        [refill_index]
                        [used_way]
                        <= 1'b1;

                    // Move the refilled way to MRU position
                    temp_refill[0] = used_way;
                    j = 1;

                    for (k = 0; k < WAY_NUM; k = k + 1) begin
                        if (
                            lru_order[refill_index][k]
                            != used_way
                        ) begin
                            temp_refill[j] =
                                lru_order[refill_index][k];

                            j = j + 1;
                        end
                    end

                    for (k = 0; k < WAY_NUM; k = k + 1) begin
                        lru_order[refill_index][k]
                            <= temp_refill[k];
                    end
                end

                // =============================================
                // Update LRU after a cache hit
                // =============================================

                if ((state == IDLE) && hit) begin

                    // Move the hit way to MRU position
                    temp_hit[0] = hit_way;
                    j = 1;

                    for (k = 0; k < WAY_NUM; k = k + 1) begin
                        if (
                            lru_order[index][k]
                            != hit_way
                        ) begin
                            temp_hit[j] =
                                lru_order[index][k];

                            j = j + 1;
                        end
                    end

                    for (k = 0; k < WAY_NUM; k = k + 1) begin
                        lru_order[index][k]
                            <= temp_hit[k];
                    end
                end
            end
        end
    end

endmodule