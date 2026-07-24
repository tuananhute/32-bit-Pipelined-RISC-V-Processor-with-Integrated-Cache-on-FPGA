module data_cache_2way_fast (
    input clk,
    input reset,

    // CPU
    input [31:0] addr,
    input [31:0] wdata,
    input mem_read,
    input mem_write,
    output [31:0] rdata,
    output ready,

    // MEMORY
    output mem_read_out,
    output mem_write_out,
    output [31:0] mem_addr,
    output [31:0] mem_wdata,
    input [31:0] mem_rdata,
    input mem_ready,

    input cacheable,

    // Coherence control from fabric
    input         coherence_block,
    input         snoop_req,
    input         snoop_invalidate,
    input  [31:0] snoop_addr,
    output        snoop_ready,
    output        snoop_hit,
    output        snoop_dirty,
    output [127:0] snoop_line,

    // Dirty-filter update pulse to fabric
    output reg        dirty_filter_update,
    output reg [31:0] dirty_filter_update_addr,
    output reg        dirty_filter_update_value
);

parameter SETS = 16;

localparam IDLE      = 2'd0,
           WRITEBACK = 2'd1,
           REFILL    = 2'd2;

reg [1:0] state;
reg [1:0] cnt;

reg valid [0:SETS-1][0:1];
reg dirty [0:SETS-1][0:1];
reg [23:0] tag [0:SETS-1][0:1];
(* ram_style = "block" *)
reg [31:0] data [0:SETS-1][0:1][0:3];
reg lru [0:SETS-1];

reg [31:0] cache_mem_addr;
reg [31:0] cache_mem_wdata;
reg [31:0] rdata_reg;

integer i, j, k;

wire request = mem_read || mem_write;
wire bypass  = !cacheable;

wire [3:0]  index       = addr[7:4];
wire [1:0]  word_offset = addr[3:2];
wire [23:0] addr_tag    = addr[31:8];

wire hit0 = valid[index][0] && (tag[index][0] == addr_tag);
wire hit1 = valid[index][1] && (tag[index][1] == addr_tag);
wire hit  = cacheable && (hit0 || hit1);
wire way  = hit0 ? 1'b0 : hit1 ? 1'b1 : 1'b0;

wire replace_way =
    !valid[index][0] ? 1'b0 :
    !valid[index][1] ? 1'b1 :
    lru[index];

// ============================================================
// Snoop port
// ============================================================
wire [3:0]  snoop_index = snoop_addr[7:4];
wire [23:0] snoop_tag   = snoop_addr[31:8];

wire snoop_hit0 = valid[snoop_index][0] &&
                  (tag[snoop_index][0] == snoop_tag);
wire snoop_hit1 = valid[snoop_index][1] &&
                  (tag[snoop_index][1] == snoop_tag);
wire snoop_way  = snoop_hit0 ? 1'b0 :
                  snoop_hit1 ? 1'b1 : 1'b0;

assign snoop_ready = (state == IDLE);
assign snoop_hit   = snoop_req && snoop_ready &&
                     (snoop_hit0 || snoop_hit1);
assign snoop_dirty = snoop_hit ? dirty[snoop_index][snoop_way] : 1'b0;
assign snoop_line  = snoop_hit ? {
    data[snoop_index][snoop_way][3],
    data[snoop_index][snoop_way][2],
    data[snoop_index][snoop_way][1],
    data[snoop_index][snoop_way][0]
} : 128'd0;

// ============================================================
// Miss registers
// ============================================================
wire miss_now = cacheable && request && !hit;

reg [31:0] miss_addr;
reg        miss_mem_write;
reg        miss_mem_read;
reg [31:0] miss_wdata;
reg [1:0]  miss_word_offset;
reg        replace_way_m;

always @(posedge clk or posedge reset) begin
    if (reset) begin
        miss_addr        <= 32'd0;
        miss_mem_write   <= 1'b0;
        miss_mem_read    <= 1'b0;
        miss_wdata       <= 32'd0;
        miss_word_offset <= 2'd0;
        replace_way_m    <= 1'b0;
    end
    else if ((state == IDLE) && !coherence_block && miss_now) begin
        miss_addr        <= {addr[31:4], 4'b0000};
        miss_mem_write   <= mem_write;
        miss_mem_read    <= mem_read;
        miss_wdata       <= wdata;
        miss_word_offset <= word_offset;
        replace_way_m    <= replace_way;
    end
end

wire [3:0]  index_m = miss_addr[7:4];
wire [23:0] tag_m   = miss_addr[31:8];

// ============================================================
// Memory interface
// ============================================================
assign mem_read_out  = bypass ? mem_read  : (state == REFILL);
assign mem_write_out = bypass ? mem_write : (state == WRITEBACK);
assign mem_addr      = bypass ? addr      : cache_mem_addr;
assign mem_wdata     = bypass ? wdata     : cache_mem_wdata;

// MMIO/uncached accesses remain usable while DMA blocks cacheable RAM.
wire cache_block_idle = coherence_block && (state == IDLE);

wire cache_ready =
    ((state == IDLE) && !miss_now) ||
    ((state == REFILL) && miss_mem_read && mem_ready &&
     (cnt == miss_word_offset));

assign ready = bypass ? mem_ready :
               cache_block_idle ? 1'b0 : cache_ready;

wire [31:0] cache_rdata =
    ((state == IDLE) && hit && mem_read) ?
        data[index][way][word_offset] :
    ((state == REFILL) && miss_mem_read && mem_ready &&
     (cnt == miss_word_offset)) ?
        mem_rdata : rdata_reg;

assign rdata = bypass ? mem_rdata : cache_rdata;

// ============================================================
// Cache FSM
// ============================================================
always @(posedge clk or posedge reset) begin
    if (reset) begin
        state <= IDLE;
        cnt <= 2'd0;
        rdata_reg <= 32'd0;
        cache_mem_addr  <= 32'd0;
        cache_mem_wdata <= 32'd0;

        dirty_filter_update       <= 1'b0;
        dirty_filter_update_addr  <= 32'd0;
        dirty_filter_update_value <= 1'b0;

        for (i = 0; i < SETS; i = i + 1) begin
            lru[i] <= 1'b0;
            for (j = 0; j < 2; j = j + 1) begin
                valid[i][j] <= 1'b0;
                dirty[i][j] <= 1'b0;
                tag[i][j]   <= 24'd0;
                for (k = 0; k < 4; k = k + 1)
                    data[i][j][k] <= 32'd0;
            end
        end
    end
    else begin
        dirty_filter_update <= 1'b0;

        if ((state == IDLE) && snoop_req && snoop_invalidate) begin
            if (snoop_hit0 || snoop_hit1) begin
                valid[snoop_index][snoop_way] <= 1'b0;
                dirty[snoop_index][snoop_way] <= 1'b0;
            end

            dirty_filter_update       <= 1'b1;
            dirty_filter_update_addr  <= {snoop_addr[31:4], 4'b0000};
            dirty_filter_update_value <= 1'b0;
        end
        else begin
            case (state)
                IDLE: begin
                    if (!coherence_block && request && cacheable) begin
                        if (hit) begin
                            if (mem_read)
                                rdata_reg <= data[index][way][word_offset];

                            if (mem_write) begin
                                data[index][way][word_offset] <= wdata;
                                dirty[index][way] <= 1'b1;

                                dirty_filter_update       <= 1'b1;
                                dirty_filter_update_addr  <= {addr[31:4], 4'b0000};
                                dirty_filter_update_value <= 1'b1;
                            end

                            lru[index] <= ~way;
                        end
                        else begin
                            cnt <= 2'd0;
                            if (valid[index][replace_way] &&
                                dirty[index][replace_way])
                                state <= WRITEBACK;
                            else
                                state <= REFILL;
                        end
                    end
                end

                WRITEBACK: begin
                    cache_mem_addr <= {
                        tag[index_m][replace_way_m],
                        index_m,
                        cnt,
                        2'b00
                    };
                    cache_mem_wdata <= data[index_m][replace_way_m][cnt];

                    if (mem_ready) begin
                        if (cnt == 2'd3) begin
                            dirty_filter_update       <= 1'b1;
                            dirty_filter_update_addr  <= {
                                tag[index_m][replace_way_m],
                                index_m,
                                4'b0000
                            };
                            dirty_filter_update_value <= 1'b0;

                            cnt <= 2'd0;
                            state <= REFILL;
                        end
                        else begin
                            cnt <= cnt + 1'b1;
                        end
                    end
                end

                REFILL: begin
                    cache_mem_addr <= miss_addr + {cnt, 2'b00};

                    if (mem_ready) begin
                        data[index_m][replace_way_m][cnt] <= mem_rdata;

                        if (cnt == miss_word_offset)
                            rdata_reg <= mem_rdata;

                        if (cnt == 2'd3) begin
                            tag[index_m][replace_way_m]   <= tag_m;
                            valid[index_m][replace_way_m] <= 1'b1;

                            if (miss_mem_write) begin
                                data[index_m][replace_way_m][miss_word_offset]
                                    <= miss_wdata;
                                dirty[index_m][replace_way_m] <= 1'b1;

                                dirty_filter_update       <= 1'b1;
                                dirty_filter_update_addr  <= miss_addr;
                                dirty_filter_update_value <= 1'b1;
                            end
                            else begin
                                dirty[index_m][replace_way_m] <= 1'b0;
                            end

                            lru[index_m] <= ~replace_way_m;
                            state <= IDLE;
                        end
                        else begin
                            cnt <= cnt + 1'b1;
                        end
                    end
                end
            endcase
        end
    end
end

endmodule
