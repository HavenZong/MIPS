`default_nettype none

module thinpad_top(
    input wire clk_50M,
    input wire clk_11M0592,

    input wire clock_btn,
    input wire reset_btn,

    input  wire[3:0]  touch_btn,
    input  wire[31:0] dip_sw,
    output wire[15:0] leds,
    output wire[7:0]  dpy0,
    output wire[7:0]  dpy1,

    inout wire[31:0] base_ram_data,
    output wire[19:0] base_ram_addr,
    output wire[3:0] base_ram_be_n,
    output wire base_ram_ce_n,
    output wire base_ram_oe_n,
    output wire base_ram_we_n,

    inout wire[31:0] ext_ram_data,
    output wire[19:0] ext_ram_addr,
    output wire[3:0] ext_ram_be_n,
    output wire ext_ram_ce_n,
    output wire ext_ram_oe_n,
    output wire ext_ram_we_n,

    output wire txd,
    input  wire rxd,

    output wire [22:0]flash_a,
    inout  wire [15:0]flash_d,
    output wire flash_rp_n,
    output wire flash_vpen,
    output wire flash_ce_n,
    output wire flash_oe_n,
    output wire flash_we_n,
    output wire flash_byte_n,

    output wire[2:0] video_red,
    output wire[2:0] video_green,
    output wire[1:0] video_blue,
    output wire video_hsync,
    output wire video_vsync,
    output wire video_clk,
    output wire video_de
);

wire clk = clk_50M;
reg reset_sync_0;
reg reset_sync_1;

always @(posedge clk) begin
    reset_sync_0 <= reset_btn;
    reset_sync_1 <= reset_sync_0;
end

wire reset = reset_sync_1;

wire        cpu_bus_valid;
wire        cpu_bus_write;
wire [1:0]  cpu_bus_size;
wire [31:0] cpu_bus_addr;
wire [31:0] cpu_bus_wdata;
wire [31:0] cpu_bus_rdata;
wire        cpu_bus_ready;

wire [31:0] debug_wb_pc;
wire [3:0]  debug_wb_rf_wen;
wire [4:0]  debug_wb_rf_wnum;
wire [31:0] debug_wb_rf_wdata;
wire [31:0] debug_pc;

mips_core #(
    .RESET_PC(32'h8000_0000)
) u_cpu (
    .clk(clk),
    .reset(reset),
    .bus_valid(cpu_bus_valid),
    .bus_write(cpu_bus_write),
    .bus_size(cpu_bus_size),
    .bus_addr(cpu_bus_addr),
    .bus_wdata(cpu_bus_wdata),
    .bus_rdata(cpu_bus_rdata),
    .bus_ready(cpu_bus_ready),
    .debug_wb_pc(debug_wb_pc),
    .debug_wb_rf_wen(debug_wb_rf_wen),
    .debug_wb_rf_wnum(debug_wb_rf_wnum),
    .debug_wb_rf_wdata(debug_wb_rf_wdata),
    .debug_pc(debug_pc)
);

soc_bus #(
    .CLK_FREQ(50000000),
    .UART_BAUD(9600)
) u_bus (
    .clk(clk),
    .reset(reset),
    .cpu_valid(cpu_bus_valid),
    .cpu_write(cpu_bus_write),
    .cpu_size(cpu_bus_size),
    .cpu_addr(cpu_bus_addr),
    .cpu_wdata(cpu_bus_wdata),
    .cpu_rdata(cpu_bus_rdata),
    .cpu_ready(cpu_bus_ready),
    .base_ram_data(base_ram_data),
    .base_ram_addr(base_ram_addr),
    .base_ram_be_n(base_ram_be_n),
    .base_ram_ce_n(base_ram_ce_n),
    .base_ram_oe_n(base_ram_oe_n),
    .base_ram_we_n(base_ram_we_n),
    .ext_ram_data(ext_ram_data),
    .ext_ram_addr(ext_ram_addr),
    .ext_ram_be_n(ext_ram_be_n),
    .ext_ram_ce_n(ext_ram_ce_n),
    .ext_ram_oe_n(ext_ram_oe_n),
    .ext_ram_we_n(ext_ram_we_n),
    .txd(txd),
    .rxd(rxd)
);

assign leds = debug_pc[17:2];

SEG7_LUT segL(.oSEG1(dpy0), .iDIG(debug_wb_rf_wnum[3:0]));
SEG7_LUT segH(.oSEG1(dpy1), .iDIG(debug_wb_rf_wen == 4'hf ? debug_wb_rf_wdata[3:0] : debug_pc[5:2]));

assign flash_a = 23'b0;
assign flash_d = 16'bz;
assign flash_rp_n = 1'b1;
assign flash_vpen = 1'b1;
assign flash_ce_n = 1'b1;
assign flash_oe_n = 1'b1;
assign flash_we_n = 1'b1;
assign flash_byte_n = 1'b1;

assign video_red = 3'b0;
assign video_green = 3'b0;
assign video_blue = 2'b0;
assign video_hsync = 1'b1;
assign video_vsync = 1'b1;
assign video_clk = clk_50M;
wire unused_inputs = clk_11M0592 ^ clock_btn ^ |touch_btn ^ |dip_sw ^
                     ^debug_wb_pc ^ debug_wb_rf_wnum[4] ^
                     ^debug_wb_rf_wdata[31:4] ^ ^debug_pc[31:18] ^ ^debug_pc[1:0];
assign video_de = unused_inputs & 1'b0;

endmodule

`default_nettype wire
