// SPDX-FileCopyrightText: 2020 Efabless Corporation
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// SPDX-License-Identifier: Apache-2.0

`default_nettype none
/*
 *-------------------------------------------------------------
 *
 * user_proj_example
 *
 * This is an example of a (trivially simple) user project,
 * showing how the user project can connect to the logic
 * analyzer, the wishbone bus, and the I/O pads.
 *
 * This project generates an integer count, which is output
 * on the user area GPIO pads (digital output only).  The
 * wishbone connection allows the project to be controlled
 * (start and stop) from the management SoC program.
 *
 * See the testbenches in directory "mprj_counter" for the
 * example programs that drive this user project.  The three
 * testbenches are "io_ports", "la_test1", and "la_test2".
 *
 *-------------------------------------------------------------
 */

module user_proj_example #(
    parameter BITS = 32,
    parameter DELAYS=10
)(
`ifdef USE_POWER_PINS
    inout vccd1,	// User area 1 1.8V supply
    inout vssd1,	// User area 1 digital ground
`endif

    // Wishbone Slave ports (WB MI A)
    input wb_clk_i,
    input wb_rst_i,
    input wbs_stb_i, // address and data valid
    input wbs_cyc_i,
    input wbs_we_i,  // = 1 for write, = 0 for read
    input [3:0] wbs_sel_i,
    input [31:0] wbs_dat_i,
    input [31:0] wbs_adr_i,
    output wbs_ack_o,  // ready
    output [31:0] wbs_dat_o,

    // Logic Analyzer Signals
    input  [127:0] la_data_in,
    output [127:0] la_data_out,
    input  [127:0] la_oenb,

    // IOs
    input  [`MPRJ_IO_PADS-1:0] io_in,
    output [`MPRJ_IO_PADS-1:0] io_out,
    output [`MPRJ_IO_PADS-1:0] io_oeb,

    // IRQ
    output [2:0] irq
);
    wire [`MPRJ_IO_PADS-1:0] io_in;
    wire [`MPRJ_IO_PADS-1:0] io_out;
    wire [`MPRJ_IO_PADS-1:0] io_oeb;

    wire clk;
    wire rst;
    assign clk = wb_clk_i;
    assign rst = wb_rst_i;
    
    assign wbs_ack_o = (verilog_addr_hit)? axi_ack:bram_delay_ready; 
    assign wbs_dat_o = (verilog_addr_hit)? axi_rdata:bram_Do_reg;

    wire c_addr_hit, verilog_addr_hit;
    wire is_axi_stream, is_axi_lite;
    wire bram_EN;
    wire [31:0] bram_Do;
    reg [31:0] bram_Do_reg;
    
    assign c_addr_hit = (wbs_adr_i[31:20] == 12'h380)?1'b1:1'b0;
    assign verilog_addr_hit = (wbs_adr_i[31:20] == 12'h300)?1'b1:1'b0;
    assign is_axi_lite = verilog_addr_hit & (wbs_adr_i[7:0]<=8'h7f ? 1'b1:1'b0);
    assign is_axi_stream = verilog_addr_hit & (wbs_adr_i[7:0]>=8'h80 ? 1'b1:1'b0);
    assign bram_EN = wbs_cyc_i && wbs_stb_i && c_addr_hit;

    wire [3:0] tap_WE, data_WE;
    wire tap_EN, data_EN;
    wire [11:0] tap_A, data_A;
    wire [31:0] tap_Di, tap_Do, data_Di, data_Do;

    reg axi_ack;
    reg [31:0] axi_rdata;

    reg awvalid, wvalid, rready, arvalid;
    reg [11:0] awaddr, araddr;
    reg [31:0] wdata;

    wire awready, wready, arready, rvalid;
    wire [31:0] rdata;

    reg ss_tvalid, ss_tlast, sm_tready;
    reg [31:0] ss_tdata;

    wire ss_tready, sm_tvalid, sm_tlast;
    wire [31:0] sm_tdata;
    always @(*) begin
        axi_ack = 0;
        axi_rdata = 32'b0;

        awvalid = 0;
        wvalid = 0;
        rready = 0;
        arvalid = 0;
        awaddr = 12'b0;
        wdata = 32'b0;
        araddr = 12'b0;
 
        ss_tvalid = 0;
        ss_tlast = 0;  // todo
        sm_tready = 0;
        ss_tdata = 32'b0;
        if(verilog_addr_hit)begin
            if(is_axi_lite) begin
                if(wbs_we_i)begin  // AXI Lite write
                    awaddr = wbs_adr_i[11:0];
                    awvalid = wbs_stb_i;
                    wdata = wbs_dat_i;
                    wvalid = wbs_stb_i;

                    axi_ack = wready;
                end
                else begin  // AXI Lite read
                    araddr = wbs_adr_i[11:0]; 
                    arvalid = wbs_stb_i;
                    rready = wbs_stb_i;

                    axi_rdata = rdata;
                    axi_ack = rvalid;
                end
            end
            else if(is_axi_stream)begin
                if(wbs_we_i)begin  // AXI Stream write
                    ss_tdata = wbs_dat_i;
                    ss_tvalid = wbs_stb_i;

                    axi_ack = ss_tready;
                end
                else begin  // AXI Stream read
                    sm_tready = wbs_stb_i;

                    axi_rdata = sm_tdata;
                    axi_ack = sm_tvalid;
                end
            end
        end
    end

    reg [3:0] bram_delay_count;
    reg bram_delay_ready;
    always@(posedge clk)begin
        if(rst)begin
            bram_delay_ready <= 0;
            bram_delay_count <= 0;
            bram_Do_reg <= 0;
        end
        else begin
            bram_delay_ready <= 0;
            if(c_addr_hit && !bram_delay_ready)begin
                if(bram_delay_count==DELAYS)begin
                    bram_delay_ready <= 1;
                    bram_Do_reg <= bram_Do;
                    bram_delay_count <= 0;
                end 
                else begin
                    bram_delay_count <= bram_delay_count + 1;
                end
            end
        end
    end
    
    // this BRAM is for c code FIR firmware
    bram user_bram (
        .CLK(clk),
        .WE0({4{wbs_we_i}}),
        .EN0(bram_EN),
        .Di0(wbs_dat_i),
        .Do0(bram_Do),
        .A0(wbs_adr_i)
    );

    fir lab3_fir(
    .awready(awready),
    .wready(wready),
    .awvalid(awvalid),
    .awaddr(awaddr),
    .wvalid(wvalid),
    .wdata(wdata),

    .arready(arready),
    .rready(rready),
    .arvalid(arvalid),
    .araddr(araddr),
    .rvalid(rvalid),
    .rdata(rdata),    

    // data input(AXI-Stream)
    .ss_tvalid(ss_tvalid), 
    .ss_tdata(ss_tdata), 
    .ss_tlast(ss_tlast), 
    .ss_tready(ss_tready), 

    // data output(AXI-Stream)
    .sm_tready(sm_tready), 
    .sm_tvalid(sm_tvalid), 
    .sm_tdata(sm_tdata), 
    .sm_tlast(sm_tlast), 
    
    // bram for tap RAM
    .tap_WE(tap_WE),
    .tap_EN(tap_EN),
    .tap_Di(tap_Di),
    .tap_A(tap_A),
    .tap_Do(tap_Do),

    // bram for data RAM
    .data_WE(data_WE),
    .data_EN(data_EN),
    .data_Di(data_Di),
    .data_A(data_A),
    .data_Do(data_Do),

    .axis_clk(clk),
    .axis_rst_n(~rst)
    );

    bram11 tap_RAM(
    .clk(clk), 
    .we(tap_WE[0]), 
    .re(1'b1), 
    .waddr(tap_A>>2), 
    .raddr(tap_A>>2), 
    .wdi(tap_Di), 
    .rdo(tap_Do));

bram11 data_RAM(
    .clk(clk), 
    .we(data_WE[0]), 
    .re(1'b1), 
    .waddr(data_A>>2), 
    .raddr(data_A>>2), 
    .wdi(data_Di), 
    .rdo(data_Do));

endmodule

`default_nettype wire