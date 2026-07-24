module main_memory (
    input clk,
    input reset,

    input mem_read,
    input mem_write,

    input [31:0] addr,
    input [31:0] wdata,

    output reg [31:0] rdata,
    output ready
);
(* ram_style = "block" *)
reg [31:0] data_mem [0:255];

initial begin
    $readmemh("data.mem", data_mem);
end

wire [7:0] word_addr = addr[9:2];

reg reading;
reg ready_read;

wire [7:0] burst_base;
reg [1:0] burst_cnt;
reg wait_read_drop;

reg writing;
reg wait_write_drop;

//////////////////////////////////////////////////
// READY
//////////////////////////////////////////////////
assign ready =

    //////////////////////////////////////
    // WRITE ACTIVE
    //////////////////////////////////////
    (writing && mem_write)

    ||

    //////////////////////////////////////
    // READ ACTIVE
    //////////////////////////////////////
    (ready_read && mem_read);

  assign burst_base = {word_addr[7:2], 2'b00};

always @(posedge clk) begin

    if(reset) begin

        reading <= 1'b0;
        ready_read <= 1'b0;
        burst_cnt <= 2'd0;

        wait_read_drop <= 1'b0;

        rdata <= 32'd0;

        writing <= 1'b0;
        wait_write_drop <= 1'b0;
    end

    else begin

        ////////////////////////////////////////
        // DELAY READY 1 PHASE
        ////////////////////////////////////////
        ready_read <= reading;

        ////////////////////////////////////////
        // RELEASE READ LOCK
        ////////////////////////////////////////
        if(wait_read_drop && !mem_read)
            wait_read_drop <= 1'b0;

        ////////////////////////////////////////
        // RELEASE WRITE LOCK
        ////////////////////////////////////////
        if(wait_write_drop && !mem_write)
            wait_write_drop <= 1'b0;

        ////////////////////////////////////////
        // START WRITE
        ////////////////////////////////////////
        if(mem_write &&
           !writing &&
           !wait_write_drop &&
           !reading) begin

            writing <= 1'b1;
        end

        ////////////////////////////////////////
        // WRITE ACTIVE
        ////////////////////////////////////////
        else if(writing) begin

            ////////////////////////////////////
            // WRITE DATA
            ////////////////////////////////////
            if(mem_write) begin

                data_mem[word_addr] <= wdata;
            end

            ////////////////////////////////////
            // END WRITE
            ////////////////////////////////////
            else begin

                writing <= 1'b0;

                wait_write_drop <= 1'b1;
            end
        end

        ////////////////////////////////////////
        // START READ BURST
        ////////////////////////////////////////
        else if(mem_read &&
                !reading &&
                !wait_read_drop &&
                !writing) begin

            reading <= 1'b1;

            burst_cnt <= 2'd0;
        end

        ////////////////////////////////////////
        // READ ACTIVE
        ////////////////////////////////////////
        else if(reading) begin

            ////////////////////////////////////
            // READ DATA
            ////////////////////////////////////
            if(mem_read) begin

                rdata <=
                    data_mem[burst_base + burst_cnt];

                //////////////////////////////////
                // LAST WORD
                //////////////////////////////////
                if(burst_cnt == 2'd3) begin

                    reading <= 1'b0;

                    wait_read_drop <= 1'b1;
                end
                else begin

                    burst_cnt <= burst_cnt + 1'b1;
                end
            end

            ////////////////////////////////////
            // END READ
            ////////////////////////////////////
            else begin

                reading <= 1'b0;

                wait_read_drop <= 1'b1;
            end
        end
    end
end

endmodule