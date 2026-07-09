`default_nettype none

module soc_system_tb(
    input wire clk,
    input wire reset,
    input wire rxd,
    output wire txd,
    output wire [31:0] debug_pc
);

wire        cpu_bus_valid;
wire        cpu_bus_write;
wire [1:0]  cpu_bus_size;
wire [31:0] cpu_bus_addr;
wire [31:0] cpu_bus_wdata;
wire [31:0] cpu_bus_rdata;
wire        cpu_bus_ready;

wire [31:0] base_ram_data;
wire [19:0] base_ram_addr;
wire [3:0]  base_ram_be_n;
wire        base_ram_ce_n;
wire        base_ram_oe_n;
wire        base_ram_we_n;

wire [31:0] ext_ram_data;
wire [19:0] ext_ram_addr;
wire [3:0]  ext_ram_be_n;
wire        ext_ram_ce_n;
wire        ext_ram_oe_n;
wire        ext_ram_we_n;

wire [31:0] unused_wb_pc;
wire [3:0]  unused_wb_rf_wen;
wire [4:0]  unused_wb_rf_wnum;
wire [31:0] unused_wb_rf_wdata;
`ifdef SIMULATION
wire [1:0]  unused_debug_bus_owner;
wire        unused_debug_fetch_issue_wants;
wire        unused_debug_fetch_issue_hit;
wire        unused_debug_dcache_mem_hit;
wire        unused_debug_mem_stage_needs_bus;
wire        unused_debug_mem_stall;
wire        unused_debug_load_use_hazard;
wire        unused_debug_mul_hazard;
wire        unused_debug_control_taken_now;
wire        unused_debug_control_pred_miss_now;
wire        unused_debug_icache_miss_complete;
wire        unused_debug_dcache_load_miss_complete;
wire        unused_debug_dcache_prefetch_complete;
wire        unused_debug_mem_store_complete;
wire        unused_debug_mmio_or_base_load_complete;
wire        unused_debug_mul_issue;
`endif

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
    .debug_wb_pc(unused_wb_pc),
    .debug_wb_rf_wen(unused_wb_rf_wen),
    .debug_wb_rf_wnum(unused_wb_rf_wnum),
    .debug_wb_rf_wdata(unused_wb_rf_wdata),
    .debug_pc(debug_pc)
`ifdef SIMULATION
    ,
    .debug_bus_owner(unused_debug_bus_owner),
    .debug_fetch_issue_wants(unused_debug_fetch_issue_wants),
    .debug_fetch_issue_hit(unused_debug_fetch_issue_hit),
    .debug_dcache_mem_hit(unused_debug_dcache_mem_hit),
    .debug_mem_stage_needs_bus(unused_debug_mem_stage_needs_bus),
    .debug_mem_stall(unused_debug_mem_stall),
    .debug_load_use_hazard(unused_debug_load_use_hazard),
    .debug_mul_hazard(unused_debug_mul_hazard),
    .debug_control_taken_now(unused_debug_control_taken_now),
    .debug_control_pred_miss_now(unused_debug_control_pred_miss_now),
    .debug_icache_miss_complete(unused_debug_icache_miss_complete),
    .debug_dcache_load_miss_complete(unused_debug_dcache_load_miss_complete),
    .debug_dcache_prefetch_complete(unused_debug_dcache_prefetch_complete),
    .debug_mem_store_complete(unused_debug_mem_store_complete),
    .debug_mmio_or_base_load_complete(unused_debug_mmio_or_base_load_complete),
    .debug_mul_issue(unused_debug_mul_issue)
`endif
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

reg [31:0] base_mem [0:1048575];
reg [31:0] ext_mem [0:1048575];

integer i;
reg [1023:0] ext_hex_path;
initial begin
    for (i = 0; i < 1048576; i = i + 1) begin
        base_mem[i] = 32'b0;
        ext_mem[i] = 32'b0;
    end
    $readmemh("/tmp/kernel_mips.hex", base_mem);
    if ($value$plusargs("EXT_HEX=%s", ext_hex_path)) begin
        $readmemh(ext_hex_path, ext_mem);
    end
end

assign base_ram_data = (!base_ram_ce_n && !base_ram_oe_n && base_ram_we_n) ? base_mem[base_ram_addr] : 32'bz;
assign ext_ram_data = (!ext_ram_ce_n && !ext_ram_oe_n && ext_ram_we_n) ? ext_mem[ext_ram_addr] : 32'bz;

always @(posedge clk) begin
    if (!base_ram_ce_n && !base_ram_we_n) begin
        if (!base_ram_be_n[0]) base_mem[base_ram_addr][7:0] <= base_ram_data[7:0];
        if (!base_ram_be_n[1]) base_mem[base_ram_addr][15:8] <= base_ram_data[15:8];
        if (!base_ram_be_n[2]) base_mem[base_ram_addr][23:16] <= base_ram_data[23:16];
        if (!base_ram_be_n[3]) base_mem[base_ram_addr][31:24] <= base_ram_data[31:24];
    end
    if (!ext_ram_ce_n && !ext_ram_we_n) begin
        if (!ext_ram_be_n[0]) ext_mem[ext_ram_addr][7:0] <= ext_ram_data[7:0];
        if (!ext_ram_be_n[1]) ext_mem[ext_ram_addr][15:8] <= ext_ram_data[15:8];
        if (!ext_ram_be_n[2]) ext_mem[ext_ram_addr][23:16] <= ext_ram_data[23:16];
        if (!ext_ram_be_n[3]) ext_mem[ext_ram_addr][31:24] <= ext_ram_data[31:24];
    end
end

endmodule

`default_nettype wire
