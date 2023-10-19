module fir 
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 11
)
(
    // AXI4-Lite interface
    // AXI4-Lite write
    output  wire                     awready,
    output  wire                     wready,
    input   wire                     awvalid,
    input   wire [(pADDR_WIDTH-1):0] awaddr,
    input   wire                     wvalid,
    input   wire [(pDATA_WIDTH-1):0] wdata,

    // AXI4-Lite read
    output  wire                     arready,
    input   wire                     rready,
    input   wire                     arvalid,
    input   wire [(pADDR_WIDTH-1):0] araddr,
    output  wire                     rvalid,
    output  wire [(pDATA_WIDTH-1):0] rdata,

    // AXI4-stream interface
    // input stream    
    input   wire                     ss_tvalid, 
    input   wire [(pDATA_WIDTH-1):0] ss_tdata, 
    input   wire                     ss_tlast, 
    output  wire                     ss_tready,

    // output stream 
    input   wire                     sm_tready, 
    output  wire                     sm_tvalid, 
    output  wire [(pDATA_WIDTH-1):0] sm_tdata, 
    output  wire                     sm_tlast, 
    
    // bram for tap RAM
    output  reg [3:0]               tap_WE,
    output  reg                     tap_EN,
    output  reg [(pDATA_WIDTH-1):0] tap_Di,
    output  reg [(pADDR_WIDTH-1):0] tap_A,
    input   wire [(pDATA_WIDTH-1):0] tap_Do,

    // bram for data RAM
    output  reg [3:0]               data_WE,
    output  reg                     data_EN,
    output  reg [(pDATA_WIDTH-1):0] data_Di,
    output  reg [(pADDR_WIDTH-1):0] data_A,
    input   wire [(pDATA_WIDTH-1):0] data_Do,

    input   wire                     axis_clk,
    input   wire                     axis_rst_n
);

    // paramters
    // AXI4-Lite state parameter
    localparam AXI_LITE_IDLE = 0;
    localparam AXI_LITE_READ = 1;
    localparam AXI_LITE_WRITE = 2;
    localparam AXI_LITE_READ_WAIT = 3;
    // Main flow state parameter
    localparam MAIN_IDLE = 0;
    localparam MAIN_INIT_DATA_RAM = 1;
    localparam MAIN_SHIFT_DATA_RAM = 2;
    localparam MAIN_CALC = 3;
    localparam MAIN_RESULT = 4;

    // global variable
    reg [9:0] data_length, data_length_next;
    reg [2:0] config_reg, config_reg_next;

    // state register
    // AXI4-Lite
    reg [1:0] axi_lite_state, axi_lite_state_next;
    // Main flow
    reg [2:0] main_flow_state, main_flow_state_next;

    // Counter & addr reg
    reg [5:0] ram_addr_reg, ram_addr_reg_next;

    // flag
    reg is_data_write_reg, is_data_write_reg_next;  // flag to write data to data ram
    reg is_data_read_reg, is_data_read_reg_next;    // flag to read data from data and tap ram

    // AXI4-Lite output reg
    // read
    reg arready_reg, arready_reg_next;
    reg rvalid_reg, rvalid_reg_next;
    reg [(pDATA_WIDTH-1):0] rdata_reg, rdata_reg_next;
    // write
    reg awready_reg, awready_reg_next;
    reg wready_reg, wready_reg_next;

    // AXI4-stream reg
    // input
    reg ss_tready_reg, ss_tready_reg_next;
    // output
    reg sm_tvalid_reg, sm_tvalid_reg_next;
    reg signed [(pDATA_WIDTH-1):0] sm_tdata_reg, sm_tdata_reg_next;
    reg sm_tlast_reg, sm_tlast_reg_next;

    // continuous assignment
    // AXI4-Lite read
    assign arready = arready_reg;
    assign rvalid = rvalid_reg;
    assign rdata = rdata_reg;
    // AXI4-Lite write
    assign awready = awready_reg;
    assign wready = wready_reg;
    // AXI4-stream input
    assign ss_tready = ss_tready_reg;
    // AXI4-stream output
    assign sm_tvalid = sm_tvalid_reg;
    assign sm_tdata = sm_tdata_reg;
    assign sm_tlast = sm_tlast_reg;

    // Main flow
    // FSM
    always @(*) begin
        main_flow_state_next = main_flow_state;
        case (main_flow_state)
            MAIN_IDLE: begin
                main_flow_state_next = (config_reg[0] == 1'b1) ? MAIN_INIT_DATA_RAM : MAIN_IDLE;
            end
            MAIN_INIT_DATA_RAM: begin
                if (ram_addr_reg < 11) begin
                    main_flow_state_next = MAIN_INIT_DATA_RAM;
                end
                else begin
                    main_flow_state_next = MAIN_SHIFT_DATA_RAM;
                end
            end
            MAIN_SHIFT_DATA_RAM: begin
                if (is_data_write_reg && (ram_addr_reg == 0)) begin
                    main_flow_state_next = MAIN_CALC;
                end
                else begin
                    main_flow_state_next = MAIN_SHIFT_DATA_RAM;
                end
            end
            MAIN_CALC: begin
                if (is_data_read_reg && (ram_addr_reg == 0)) begin
                    main_flow_state_next = MAIN_RESULT;
                end
                else begin
                    main_flow_state_next = MAIN_CALC;
                end
            end
            MAIN_RESULT: begin
                if (ss_tlast == 1) begin
                    main_flow_state_next = MAIN_IDLE;
                end
                else begin
                    main_flow_state_next = MAIN_SHIFT_DATA_RAM;
                end
            end
            default: begin
                main_flow_state_next = main_flow_state;
            end
        endcase
    end

    // Logic
    always @(*) begin
        // rtam addr
        ram_addr_reg_next = ram_addr_reg;
        // flag
        is_data_write_reg_next = is_data_write_reg;
        is_data_read_reg_next = is_data_read_reg;
        // AXI4-stream input
        ss_tready_reg_next = ss_tready_reg;
        // AXI4-stream output
        sm_tvalid_reg_next = sm_tvalid_reg;
        sm_tdata_reg_next = sm_tdata_reg;
        sm_tlast_reg_next = 0;
        case (main_flow_state)
            MAIN_IDLE: begin
                data_EN = 0;
                data_WE = 0;   
                ram_addr_reg_next = 0;
            end
            MAIN_INIT_DATA_RAM: begin
                if (ram_addr_reg < 11) begin    // Init each data ram cell to 0
                    data_EN = 1;
                    data_WE = 4'b1111;
                    data_A = ram_addr_reg << 2;
                    data_Di = 0;
                    ram_addr_reg_next = ram_addr_reg + 1;
                end
                else begin
                    data_EN = 0;
                    data_WE = 0;
                    ram_addr_reg_next = 10;
                    is_data_write_reg_next = 0;
                end
            end
            MAIN_SHIFT_DATA_RAM: begin
                if (is_data_write_reg && (ram_addr_reg == 0)) begin     // End addr 0 shift in data
                    data_EN = 0;
                    data_WE = 0;
                    ram_addr_reg_next = 10;
                    is_data_write_reg_next = 0;
                    is_data_read_reg_next = 0;
                end
                else begin
                    if (ram_addr_reg == 0) begin    // shift in ss x value
                        data_EN = 1;
                        data_WE = 4'b1111;
                        data_A = ram_addr_reg << 2;
                        data_Di = ss_tdata;
                        is_data_write_reg_next = 1;
                    end
                    else begin  // shift in
                        is_data_write_reg_next = ~is_data_write_reg;    // toggle flag
                        if (is_data_write_reg) begin    // write data
                            data_EN = 1;
                            data_WE = 4'b1111;
                            data_A = ram_addr_reg << 2;
                            data_Di = data_Do;
                            ram_addr_reg_next = ram_addr_reg - 1;
                        end
                        else begin  // read data
                            data_EN = 1;
                            data_WE = 0;
                            data_A = (ram_addr_reg - 1) << 2;
                        end
                    end
                end
            end
            MAIN_CALC: begin
                data_EN = 1;
                if (is_data_read_reg && (ram_addr_reg == 0)) begin  // End addr 0 read data out
                    sm_tdata_reg_next = $signed(sm_tdata_reg) + ($signed(data_Do) * $signed(tap_Do));
                    sm_tvalid_reg_next = 1;
                    ss_tready_reg_next = 1;
                    is_data_read_reg_next = 0;
                end
                else begin
                    is_data_read_reg_next = ~is_data_read_reg;  // toggle flag  
                    if (is_data_read_reg) begin // read data out
                        sm_tdata_reg_next = $signed(sm_tdata_reg) + ($signed(data_Do) * $signed(tap_Do));
                        ram_addr_reg_next = ram_addr_reg - 1;
                    end
                    else begin  // set read data addr
                        // data ram
                        data_A = ram_addr_reg << 2;
                    end
                end
            end
            MAIN_RESULT: begin
                sm_tvalid_reg_next = 0;
                ss_tready_reg_next = 0;
                is_data_read_reg_next = 0;
                is_data_write_reg_next = 0;
                sm_tdata_reg_next = 0;
                if (ss_tlast == 1) begin
                    sm_tlast_reg_next = 1;
                    ram_addr_reg_next = 0;
                end
                else begin
                    sm_tlast_reg_next = 0;
                    ram_addr_reg_next = 10;
                end
            end
            default: begin
                // rtam addr
                ram_addr_reg_next = ram_addr_reg;
                // flag
                is_data_write_reg_next = is_data_write_reg;
                is_data_read_reg_next = is_data_read_reg;
                // AXI4-stream input
                ss_tready_reg_next = ss_tready_reg;
                // AXI4-stream output
                sm_tvalid_reg_next = sm_tvalid_reg;
                sm_tdata_reg_next = sm_tdata_reg;
                sm_tlast_reg_next = 0;
            end
        endcase
    end

    // AXI4-Lite Read && Write
    // FSM
    always @(*) begin
        axi_lite_state_next = axi_lite_state;
        case (axi_lite_state)
            AXI_LITE_IDLE: begin
                if (arvalid && rready) begin    // read address valid and ready
                    axi_lite_state_next = AXI_LITE_READ;
                end
                else if (awvalid && wvalid) begin   // write address and data valid
                    axi_lite_state_next = AXI_LITE_WRITE;
                end
                else begin
                    axi_lite_state_next = AXI_LITE_IDLE;
                end
            end
            AXI_LITE_READ: begin
                if (araddr == 0) begin  // read ap signal
                    axi_lite_state_next = AXI_LITE_IDLE;
                end
                else if (araddr == 12'h10) begin    // read data length
                    axi_lite_state_next = AXI_LITE_IDLE;
                end
                else begin  // read tap parameters
                    axi_lite_state_next = AXI_LITE_READ_WAIT;
                end
            end
            AXI_LITE_WRITE: begin
                axi_lite_state_next = AXI_LITE_IDLE;
            end
            AXI_LITE_READ_WAIT: begin
                axi_lite_state_next = AXI_LITE_IDLE;
            end
            default: begin
                axi_lite_state_next = axi_lite_state;
            end
        endcase
    end

    // Logic
    always @(*) begin
        // global variable
        data_length_next = data_length;
        // read
        arready_reg_next = arready_reg;
        rvalid_reg_next = rvalid_reg;
        rdata_reg_next = rdata_reg;
        // write
        awready_reg_next = awready_reg;
        wready_reg_next = wready_reg;
        case (axi_lite_state)
            AXI_LITE_IDLE: begin    // read address valid and ready
                // read
                rvalid_reg_next = 0;
                // write
                wready_reg_next = 0;
                if (arvalid && rready) begin    // read address valid and ready
                    arready_reg_next = 1;
                end
                else if (awvalid && wvalid) begin   // write address and data valid
                    awready_reg_next = 1;
                end
                else begin
                    
                end
            end
            AXI_LITE_READ: begin    // write address and data valid
                arready_reg_next = 0;
                awready_reg_next = 0;
                rvalid_reg_next = 1;
                if (araddr == 0) begin  // read ap signal
                    rdata_reg_next = {{29{1'b0}}, config_reg};
                end
                else if (araddr == 12'h10) begin    // read data length
                    rdata_reg_next = {{22{1'b0}}, data_length};
                end
                else begin  // read tap parameters
                    rdata_reg_next = tap_Do;
                end
            end
            AXI_LITE_WRITE: begin
                awready_reg_next = 0;
                wready_reg_next = 1;
                if (awaddr == 0) begin  
                    
                end
                else if (awaddr == 12'h10) begin    // write data length
                    data_length_next = wdata[9:0];
                end
                else begin  // write tap parameters

                end
            end
            AXI_LITE_READ_WAIT: begin

                rvalid_reg_next = 0;
            end
            default: begin
                // global variable
                data_length_next = data_length;
                config_reg_next = config_reg;
                // read
                arready_reg_next = arready_reg;
                rvalid_reg_next = rvalid_reg;
                rdata_reg_next = rdata_reg;
                // write
                awready_reg_next = awready_reg;
                wready_reg_next = wready_reg;
            end
        endcase
    end

    // config reg logic
    always @(*) begin
        if ((main_flow_state == MAIN_IDLE) && (config_reg[0] == 1'b1)) begin    // set ap_start and ap_idle = 0
            config_reg_next = (config_reg[0] == 1'b1) ? 0 : config_reg; 
        end
        else if (main_flow_state == MAIN_INIT_DATA_RAM) begin
            config_reg_next = 0; 
        end
        else if (main_flow_state == MAIN_RESULT) begin
            if (ss_tlast == 1) begin
                config_reg_next = 3'b110;   // set ap_done and ap_start
            end
            else begin
                config_reg_next = config_reg;
            end
        end
        else if (axi_lite_state == AXI_LITE_WRITE) begin
            if (awaddr == 0) begin  // write ap signal
                config_reg_next = config_reg | wdata[2:0];
            end
            else begin
                config_reg_next = config_reg;
            end
        end
        else begin
            config_reg_next = config_reg;
        end
    end

    // tap ram wire logic
    always @(*) begin
        if (main_flow_state == MAIN_CALC) begin
            tap_WE = 0;
            tap_Di = 0;
            tap_EN = 1;
            tap_A = ram_addr_reg << 2;
        end
        else if (axi_lite_state == AXI_LITE_IDLE) begin
            tap_WE = 0;
            tap_Di = 0;
            tap_EN = 0;
            if (arvalid && rready) begin
                tap_A = araddr - 12'h20;
            end
            else begin
                tap_A = 0;
            end
        end
        else if (axi_lite_state == AXI_LITE_READ) begin
            tap_WE = 0;
            tap_A = 0;
            tap_Di = 0;
            if ((araddr != 0) && (araddr != 12'h10)) begin
                tap_EN = 1;
            end
            else begin
                tap_EN = 0;
            end
        end
        else if (axi_lite_state == AXI_LITE_WRITE) begin
            if ((awaddr != 0) && (awaddr != 12'h10)) begin
                tap_EN = 1;
                tap_WE = 4'b1111;
                tap_A = awaddr - 12'h20;
                tap_Di = wdata;
            end
            else begin
                tap_EN = 0;
                tap_WE = 0;
                tap_A = 0;
                tap_Di = 0;
            end
        end
        else begin
            tap_WE = 0;
            tap_Di = 0;
            tap_EN = 0;
            tap_A = ram_addr_reg << 2;
        end
    end

    // sequential part
    // general
    always @(posedge axis_clk) begin
        if (!axis_rst_n) begin
            data_length <= 0;
            config_reg <= 3'b100;   // ap_idle = 1
            axi_lite_state <= AXI_LITE_IDLE;
            main_flow_state <= MAIN_IDLE;
            ram_addr_reg <= 0;
            is_data_write_reg <= 0;
            is_data_read_reg <= 0;
        end
        else begin
            data_length <= data_length_next;
            config_reg <= config_reg_next;
            axi_lite_state <= axi_lite_state_next;
            main_flow_state <= main_flow_state_next;
            ram_addr_reg <= ram_addr_reg_next;
            is_data_write_reg <= is_data_write_reg_next;
            is_data_read_reg <= is_data_read_reg_next;
        end
    end

    // AXI4-Lite read
    always @(posedge axis_clk) begin
        if (!axis_rst_n) begin
            arready_reg <= 0;
            rvalid_reg <= 0;
            rdata_reg <= 0;
        end
        else begin
            arready_reg <= arready_reg_next;
            rvalid_reg <= rvalid_reg_next;
            rdata_reg <= rdata_reg_next;
        end
    end

    // AXI4-Lite write
    always @(posedge axis_clk) begin
        if (!axis_rst_n) begin
            awready_reg <= 0;
            wready_reg <= 0;
        end
        else begin
            awready_reg <= awready_reg_next;
            wready_reg <= wready_reg_next;
        end
    end

    // AXI4-stream input
    always @(posedge axis_clk) begin
        if (!axis_rst_n) begin
            ss_tready_reg <= 0;
        end
        else begin
            ss_tready_reg <= ss_tready_reg_next;
        end
    end

    // AXI4-stream output
    always @(posedge axis_clk) begin
        if (!axis_rst_n) begin
            sm_tvalid_reg <= 0;
            sm_tdata_reg <= 0;
            sm_tlast_reg <= 0;
        end
        else begin
            sm_tvalid_reg <= sm_tvalid_reg_next;
            sm_tdata_reg <= sm_tdata_reg_next;
            sm_tlast_reg <= sm_tlast_reg_next;
        end
    end

endmodule