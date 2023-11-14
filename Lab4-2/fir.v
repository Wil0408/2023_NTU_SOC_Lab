`define AXIL_IDLE 3'b000
`define AXIL_RADDR 3'b010
`define AXIL_RDATA 3'b011
`define AXIL_WADDR 3'b100
`define AXIL_WDATA 3'b101
`define AXIS_IDLE 3'b000
`define AXIS_WRITE 3'b100
`define AXIS_FIRST 3'b001
`define AXIS_COMPUTING 3'b010
`define AXIS_OUTPUT 3'b011

module fir 
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 11
)
(
    output  wire                     awready,
    output  wire                     wready,
    input   wire                     awvalid,
    input   wire [(pADDR_WIDTH-1):0] awaddr,
    input   wire                     wvalid,
    input   wire [(pDATA_WIDTH-1):0] wdata,

    output  wire                     arready,
    input   wire                     rready,
    input   wire                     arvalid,
    input   wire [(pADDR_WIDTH-1):0] araddr,
    output  wire                     rvalid,
    output  wire [(pDATA_WIDTH-1):0] rdata,    

    // data input(AXI-Stream)
    input   wire                     ss_tvalid, 
    input   wire [(pDATA_WIDTH-1):0] ss_tdata, 
    input   wire                     ss_tlast, 
    output  wire                     ss_tready, 

    // data output(AXI-Stream)
    input   wire                     sm_tready, 
    output  wire                     sm_tvalid, 
    output  wire [(pDATA_WIDTH-1):0] sm_tdata, 
    output  wire                     sm_tlast, 
    
    // bram for tap RAM
    output  wire [3:0]               tap_WE,
    output  wire                     tap_EN,
    output  wire [(pDATA_WIDTH-1):0] tap_Di,
    output  wire [(pADDR_WIDTH-1):0] tap_A,
    input   wire [(pDATA_WIDTH-1):0] tap_Do,

    // bram for data RAM
    output  wire [3:0]               data_WE,
    output  wire                     data_EN,
    output  wire [(pDATA_WIDTH-1):0] data_Di,
    output  wire [(pADDR_WIDTH-1):0] data_A,
    input   wire [(pDATA_WIDTH-1):0] data_Do,

    input   wire                     axis_clk,
    input   wire                     axis_rst_n
);

    // write your code here!
    integer i;

    reg [2:0] AXIL_state, next_AXIL_state;
    reg [31:0] ap_config_reg;
    reg [31:0] data_length_config_reg;
    reg [3:0] tap_WE_reg, data_WE_reg;
    // reg [31:0] tap_config_reg [0:Tape_Num-1];

    assign tap_EN = 1;
    assign tap_WE = (AXIL_state == `AXIL_WDATA && awaddr >= 32'h0020)? 4'b1111:0;
    assign tap_Di = wdata;
    assign tap_A = (AXIL_state==`AXIL_WDATA && AXIS_state==`AXIS_IDLE)? awaddr-32'h0020 : (AXIL_state==`AXIL_RADDR && AXIS_state==`AXIS_IDLE)? araddr-32'h0020 : (fir_compute_count<<2);

    assign data_EN = 1;
    assign data_WE = (AXIS_state==`AXIS_IDLE || AXIS_state==`AXIS_WRITE)? 4'b1111:0;
    assign data_Di = (AXIS_state == `AXIS_IDLE)? 0 : ss_tdata;  // reset to 0 when AXIS_state == `AXIS_IDLE
    assign data_A = (AXIS_state==`AXIS_COMPUTING)? (data_index<<2) : (first_data_index<<2);

    reg [2:0] AXIS_state, next_AXIS_state;
    reg [3:0] fir_compute_count;
    reg [3:0] first_data_index;
    wire [3:0] data_index;
    reg ss_tready_reg, sm_tvalid_reg;
    reg data_reset_done;
    reg last_output;
    reg signed [31:0] accumulate;

    assign ss_tready = ss_tready_reg;
    assign sm_tvalid = sm_tvalid_reg;
    assign sm_tdata = accumulate;
    assign sm_tlast  = last_output;
    assign data_index = (first_data_index >= fir_compute_count)? (first_data_index - fir_compute_count) : 11-(fir_compute_count - first_data_index);
    
	// ================================================= AXI_lite =================================================
    // AR
	assign arready = (AXIL_state == `AXIL_RADDR) ? 1 : 0;
    // AW
	assign awready = (AXIL_state == `AXIL_WADDR) ? 1 : 0;
	// R
    // assign rdata  = (AXIL_state == `AXIL_RDATA) ? (araddr == 32'h0000)? ap_config_reg: (araddr == 32'h00010)? data_length_config_reg : (araddr >= 32'h0020)? tap_config_reg[(araddr-32'h0020)>>2]:0 : 0;
    assign rdata  = (AXIL_state == `AXIL_RDATA) ? (araddr == 32'h0000)? ap_config_reg: (araddr == 32'h00010)? data_length_config_reg : (araddr >= 32'h0020)? tap_Do:0 : 0;
	assign rvalid = (AXIL_state == `AXIL_RDATA) ? 1 : 0;
	// W
	assign wready = (AXIL_state == `AXIL_WDATA) ? 1 : 0;
    // ================================================= AXI_lite =================================================

    // ================================================= AXI_stream =================================================
    always@(posedge axis_clk, negedge axis_rst_n) begin
		if (!axis_rst_n) begin
            last_output <= 0;
            data_reset_done <= 0;
            ss_tready_reg <= 0;
            sm_tvalid_reg <= 0;
            first_data_index <= 10;
            fir_compute_count <= 0;
            accumulate <= 0;
		end 
        else begin 
            case(AXIS_state)
                `AXIS_IDLE:begin
                    ss_tready_reg <= 0;
                    sm_tvalid_reg <= 0;
                    first_data_index <= data_reset_done?  first_data_index : first_data_index-1;
                    data_reset_done <= (data_reset_done==1)? 1:(first_data_index==1)? 1:0;
                end
                `AXIS_WRITE:begin
                    ss_tready_reg <= 1;
                    sm_tvalid_reg <= 0;
                end
                `AXIS_FIRST:begin
                    ss_tready_reg <= 0;
                    sm_tvalid_reg <= 0;
                    fir_compute_count <= 1;
                end
                `AXIS_COMPUTING:begin
                    ss_tready_reg <= 0;
                    sm_tvalid_reg <= (fir_compute_count==11)? 1:0;
                    fir_compute_count <= (fir_compute_count==11)? 0 : fir_compute_count+1;
                    accumulate <= accumulate + $signed(tap_Do) * $signed(data_Do);
                end
                `AXIS_OUTPUT:begin
                    ss_tready_reg <= 0;
                    sm_tvalid_reg <= (next_AXIS_state==`AXIS_IDLE)? 0:1;                   
                    first_data_index <= (sm_tready==1)? (first_data_index==10)? 0 : first_data_index+1 : first_data_index;
                    accumulate <= (next_AXIS_state==`AXIS_IDLE)? 0:accumulate;
                    last_output <= (ss_tlast==1)? 1:0;
                end
            endcase
		end
	end

    always@(*)begin
        case(AXIS_state)
            `AXIS_IDLE:begin
                // next_AXIS_state = (ss_tvalid==1)? (ap_config_reg[0]==1)? `AXIS_WRITE:`AXIS_IDLE : `AXIS_IDLE;
                next_AXIS_state = (ss_tvalid==1)? `AXIS_WRITE: `AXIS_IDLE;
            end
            `AXIS_WRITE:begin
                next_AXIS_state = `AXIS_FIRST;
            end
            `AXIS_FIRST:begin
                next_AXIS_state = `AXIS_COMPUTING;
            end
            `AXIS_COMPUTING:begin
                next_AXIS_state = (fir_compute_count==11)? `AXIS_OUTPUT:`AXIS_COMPUTING;
            end
            `AXIS_OUTPUT:begin
                next_AXIS_state = (sm_tready==1)? (last_output==1)? `AXIS_IDLE:`AXIS_IDLE : `AXIS_OUTPUT;
            end
        endcase
    end

    always @(posedge axis_clk, negedge axis_rst_n) begin
        if(!axis_rst_n)begin
            AXIS_state <= `AXIS_IDLE;
        end
        else begin
            AXIS_state <= next_AXIS_state;
        end
    end
    // ================================================= AXI_stream =================================================

    // ================================================= AXI_lite =================================================
    always @(posedge  axis_clk) begin
		if (!axis_rst_n) begin
			ap_config_reg <= 32'h0000_0004;  // ap_idle (bit[2]) = 1, other bit = 0
            data_length_config_reg <= 0;
		end else begin
			if (AXIL_state == `AXIL_WDATA) begin
                if (awaddr == 32'h0000)begin
                    ap_config_reg[0] <= wdata[0];  // ap_strart 
                    ap_config_reg[6] <= wdata[6];  // ss_tlast
                    // other bit is read only, can't be overwritten
                end
                else if(awaddr == 32'h0010)begin
                    data_length_config_reg <= wdata;   
                end
            end
            else if (AXIL_state == `AXIL_RDATA) begin
                ap_config_reg[1] <= (awaddr == 32'h0000)? 0:ap_config_reg[1];  // ap_done is reset when address 0x00 is read
            end
            else begin
                ap_config_reg[0] <= (ap_config_reg[0]==0)? 0:(AXIS_state == `AXIS_IDLE)? 1:0;  // ap_start, reset when start AXI_stream data transfer
                // ap_config_reg[1] <= (ap_config_reg[1]==1)? 1:(last_output==1 && AXIS_state==`AXIS_OUTPUT)? 1:0;  // ap_done
                // ap_config_reg[2] <= (ap_config_reg[2]==1)? (ap_config_reg[0]==1)? 0:1 : (ss_tlast==1 && AXIS_state==`AXIS_IDLE)? 1:0;  // ap_idle
                ap_config_reg[1] <= (ap_config_reg[1]==1)? 1:(ap_config_reg[6]==1 && AXIS_state==`AXIS_IDLE)? 1:0;  // ap_done
                ap_config_reg[2] <= (ap_config_reg[2]==1)? (ap_config_reg[0]==1)? 0:1 : (ap_config_reg[6]==1 && AXIS_state==`AXIS_IDLE)? 1:0;  // ap_idle
                ap_config_reg[4] <= (AXIS_state==`AXIS_IDLE)? 1:0;  // ready to accept x[n] 
                ap_config_reg[5] <= (AXIS_state==`AXIS_OUTPUT)? 1:0; // y[n] ready to be read
            end
		end
	end

    always@(*)begin
        case(AXIL_state)
            `AXIL_IDLE:begin
                next_AXIL_state = (awvalid)? `AXIL_WADDR : (arvalid)? `AXIL_RADDR :  `AXIL_IDLE;
            end
            `AXIL_RADDR:begin
                next_AXIL_state = (arvalid && arready)? `AXIL_RDATA : `AXIL_RADDR;
            end
            `AXIL_RDATA:begin
                next_AXIL_state = (rready && rvalid)? `AXIL_IDLE : `AXIL_RDATA;
            end
            `AXIL_WADDR:begin
                next_AXIL_state = (awvalid && awready)? `AXIL_WDATA : `AXIL_WADDR; 
            end
            `AXIL_WDATA:begin
                next_AXIL_state = (wready && wvalid)? `AXIL_IDLE : `AXIL_WDATA;
            end
        endcase
    end

    always @(posedge axis_clk, negedge axis_rst_n) begin
        if(!axis_rst_n)begin
            AXIL_state <= `AXIL_IDLE;
        end
        else begin
            AXIL_state <= next_AXIL_state;
        end
    end
    // ================================================= AXI_lite =================================================
endmodule