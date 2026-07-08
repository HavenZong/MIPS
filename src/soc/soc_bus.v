`default_nettype none

module soc_bus #(
    parameter CLK_FREQ = 50000000,
    parameter UART_BAUD = 9600,
    parameter UART_DATA_ADDR = 32'hbfd0_03f8,
    parameter UART_STATUS_ADDR = 32'hbfd0_03fc
)(
    input  wire        clk,
    input  wire        reset,

    input  wire        cpu_valid,
    input  wire        cpu_write,
    input  wire [1:0]  cpu_size,
    input  wire [31:0] cpu_addr,
    input  wire [31:0] cpu_wdata,
    output reg  [31:0] cpu_rdata = 32'b0,
    output reg         cpu_ready = 1'b0,

    inout  wire [31:0] base_ram_data,
    output reg  [19:0] base_ram_addr = 20'b0,
    output reg  [3:0]  base_ram_be_n = 4'hf,
    output reg         base_ram_ce_n = 1'b1,
    output reg         base_ram_oe_n = 1'b1,
    output reg         base_ram_we_n = 1'b1,

    inout  wire [31:0] ext_ram_data,
    output reg  [19:0] ext_ram_addr = 20'b0,
    output reg  [3:0]  ext_ram_be_n = 4'hf,
    output reg         ext_ram_ce_n = 1'b1,
    output reg         ext_ram_oe_n = 1'b1,
    output reg         ext_ram_we_n = 1'b1,

    output wire        txd,
    input  wire        rxd
);

localparam SIZE_BYTE = 2'b00;
localparam B_IDLE        = 3'd0;
localparam B_SRAM_WAIT   = 3'd1;
localparam B_RESP        = 3'd2;
localparam B_UART_TXWAIT = 3'd3;
localparam B_UART_START  = 3'd4;
localparam B_UART_DUMMY  = 3'd5;
localparam UART_RX_FIFO_DEPTH = 1024;
localparam [19:0] UART_DUMMY_BASE = 20'hf8000; // ExtRAM byte offset 0x003e0000.
localparam [2:0] SRAM_WAIT_CYCLES = 3'd1;
localparam [2:0] UART_DUMMY_WAIT_CYCLES = 3'd2;

reg [2:0] state = B_IDLE;
reg [2:0] wait_count = 3'b0;
reg active_ext = 1'b0;
reg active_write = 1'b0;

reg base_drive = 1'b0;
reg ext_drive = 1'b0;
reg [31:0] base_dout = 32'b0;
reg [31:0] ext_dout = 32'b0;

assign base_ram_data = base_drive ? base_dout : 32'bz;
assign ext_ram_data = ext_drive ? ext_dout : 32'bz;

wire uart_rx_ready;
wire uart_rx_clear;
wire [7:0] uart_rx_data;
reg [7:0] uart_rx_fifo [0:UART_RX_FIFO_DEPTH-1];
reg [9:0] uart_rx_head = 10'b0;
reg [9:0] uart_rx_tail = 10'b0;
reg [10:0] uart_rx_count = 11'b0;

reg [7:0] uart_tx_data = 8'b0;
reg uart_tx_start = 1'b0;
wire uart_tx_busy;
reg [7:0] uart_dummy_count = 8'b0;

async_receiver #(
    .ClkFrequency(CLK_FREQ),
    .Baud(UART_BAUD)
) uart_rx (
    .clk(clk),
    .reset(reset),
    .RxD(rxd),
    .RxD_data_ready(uart_rx_ready),
    .RxD_clear(uart_rx_clear),
    .RxD_data(uart_rx_data)
);

async_transmitter #(
    .ClkFrequency(CLK_FREQ),
    .Baud(UART_BAUD)
) uart_tx (
    .clk(clk),
    .reset(reset),
    .TxD(txd),
    .TxD_busy(uart_tx_busy),
    .TxD_start(uart_tx_start),
    .TxD_data(uart_tx_data)
);

assign uart_rx_clear = uart_rx_ready;

wire is_uart_data = (cpu_addr == UART_DATA_ADDR);
wire is_uart_status = (cpu_addr == UART_STATUS_ADDR);
wire is_uart = is_uart_data || is_uart_status;
wire uart_rx_fifo_empty = (uart_rx_count == 11'd0);
wire uart_rx_fifo_full = (uart_rx_count == 11'd1024);
wire [7:0] uart_status_value = {6'b0, !uart_rx_fifo_empty, !uart_tx_busy};
wire uart_rx_pop = (state == B_IDLE) && cpu_valid && !cpu_write && is_uart_data && !uart_rx_fifo_empty;
wire uart_rx_push = uart_rx_ready && (!uart_rx_fifo_full || uart_rx_pop);

wire [22:0] sram_addr = cpu_addr[22:0];
wire select_ext = sram_addr[22];
wire [19:0] ram_word_addr = sram_addr[21:2];

reg [3:0] byte_enable_n;
reg [31:0] write_data_shifted;

always @(*) begin
    byte_enable_n = 4'b0000;
    write_data_shifted = cpu_wdata;
    if (cpu_size == SIZE_BYTE) begin
        byte_enable_n = ~(4'b0001 << sram_addr[1:0]);
        write_data_shifted = {4{cpu_wdata[7:0]}} << (sram_addr[1:0] * 8);
    end
end

always @(posedge clk) begin
    if (reset) begin
        state <= B_IDLE;
        wait_count <= 3'b0;
        cpu_rdata <= 32'b0;
        cpu_ready <= 1'b0;
        base_ram_addr <= 20'b0;
        base_ram_be_n <= 4'hf;
        base_ram_ce_n <= 1'b1;
        base_ram_oe_n <= 1'b1;
        base_ram_we_n <= 1'b1;
        ext_ram_addr <= 20'b0;
        ext_ram_be_n <= 4'hf;
        ext_ram_ce_n <= 1'b1;
        ext_ram_oe_n <= 1'b1;
        ext_ram_we_n <= 1'b1;
        active_ext <= 1'b0;
        active_write <= 1'b0;
        base_drive <= 1'b0;
        ext_drive <= 1'b0;
        base_dout <= 32'b0;
        ext_dout <= 32'b0;
        uart_rx_head <= 10'b0;
        uart_rx_tail <= 10'b0;
        uart_rx_count <= 11'b0;
        uart_tx_data <= 8'b0;
        uart_tx_start <= 1'b0;
        uart_dummy_count <= 8'b0;
    end else begin
        cpu_ready <= 1'b0;
        uart_tx_start <= 1'b0;

        if (uart_rx_push) begin
            uart_rx_fifo[uart_rx_tail] <= uart_rx_data;
            uart_rx_tail <= uart_rx_tail + 10'd1;
        end
        if (uart_rx_pop) begin
            uart_rx_head <= uart_rx_head + 10'd1;
        end
        case ({uart_rx_push, uart_rx_pop})
            2'b10: uart_rx_count <= uart_rx_count + 11'd1;
            2'b01: uart_rx_count <= uart_rx_count - 11'd1;
            default: uart_rx_count <= uart_rx_count;
        endcase

        case (state)
            B_IDLE: begin
                base_ram_ce_n <= 1'b1;
                base_ram_oe_n <= 1'b1;
                base_ram_we_n <= 1'b1;
                base_ram_be_n <= 4'hf;
                ext_ram_ce_n <= 1'b1;
                ext_ram_oe_n <= 1'b1;
                ext_ram_we_n <= 1'b1;
                ext_ram_be_n <= 4'hf;
                base_drive <= 1'b0;
                ext_drive <= 1'b0;

                if (cpu_valid) begin
                    if (is_uart) begin
                        if (cpu_write && is_uart_data) begin
                            if (uart_tx_busy) begin
                                state <= B_UART_TXWAIT;
                            end else begin
                                uart_tx_data <= cpu_wdata[7:0];
                                state <= B_UART_START;
                            end
                        end else begin
                            if (is_uart_data) begin
                                cpu_rdata <= {24'b0, uart_rx_fifo_empty ? 8'b0 : uart_rx_fifo[uart_rx_head]};
                                ext_dout <= {8'h55, uart_dummy_count, 8'h52, uart_rx_fifo_empty ? 8'b0 : uart_rx_fifo[uart_rx_head]};
                            end else begin
                                cpu_rdata <= {24'b0, uart_status_value};
                                ext_dout <= {8'h55, uart_dummy_count, 8'h53, uart_status_value};
                            end
                            ext_ram_addr <= UART_DUMMY_BASE + {12'b0, uart_dummy_count};
                            ext_ram_be_n <= 4'b0000;
                            ext_ram_ce_n <= 1'b0;
                            ext_ram_oe_n <= 1'b1;
                            ext_ram_we_n <= 1'b0;
                            ext_drive <= 1'b1;
                            wait_count <= UART_DUMMY_WAIT_CYCLES;
                            uart_dummy_count <= uart_dummy_count + 8'd1;
                            state <= B_UART_DUMMY;
                        end
                    end else begin
                        active_ext <= select_ext;
                        active_write <= cpu_write;
                        wait_count <= SRAM_WAIT_CYCLES;

                        if (select_ext) begin
                            ext_ram_addr <= ram_word_addr;
                            ext_ram_be_n <= cpu_write ? byte_enable_n : 4'b0000;
                            ext_ram_ce_n <= 1'b0;
                            ext_ram_oe_n <= cpu_write ? 1'b1 : 1'b0;
                            ext_ram_we_n <= cpu_write ? 1'b0 : 1'b1;
                            ext_dout <= write_data_shifted;
                            ext_drive <= cpu_write;
                        end else begin
                            base_ram_addr <= ram_word_addr;
                            base_ram_be_n <= cpu_write ? byte_enable_n : 4'b0000;
                            base_ram_ce_n <= 1'b0;
                            base_ram_oe_n <= cpu_write ? 1'b1 : 1'b0;
                            base_ram_we_n <= cpu_write ? 1'b0 : 1'b1;
                            base_dout <= write_data_shifted;
                            base_drive <= cpu_write;
                        end
                        state <= B_SRAM_WAIT;
                    end
                end
            end
            B_SRAM_WAIT: begin
                if (wait_count != 3'b0) begin
                    wait_count <= wait_count - 3'b1;
                end else begin
                    if (!active_write) begin
                        cpu_rdata <= active_ext ? ext_ram_data : base_ram_data;
                    end
                    if (active_ext) begin
                        ext_ram_ce_n <= 1'b1;
                        ext_ram_oe_n <= 1'b1;
                        ext_ram_we_n <= 1'b1;
                    end else begin
                        base_ram_ce_n <= 1'b1;
                        base_ram_oe_n <= 1'b1;
                        base_ram_we_n <= 1'b1;
                    end
                    cpu_ready <= 1'b1;
                    state <= B_RESP;
                end
            end
            B_UART_TXWAIT: begin
                if (!uart_tx_busy) begin
                    uart_tx_data <= cpu_wdata[7:0];
                    state <= B_UART_START;
                end
            end
            B_UART_START: begin
                if (!uart_tx_busy) begin
                    uart_tx_start <= 1'b1;
                    ext_ram_addr <= UART_DUMMY_BASE + {12'b0, uart_dummy_count};
                    ext_ram_be_n <= 4'b0000;
                    ext_ram_ce_n <= 1'b0;
                    ext_ram_oe_n <= 1'b1;
                    ext_ram_we_n <= 1'b0;
                    ext_dout <= {8'h55, uart_dummy_count, 8'h57, uart_tx_data};
                    ext_drive <= 1'b1;
                    wait_count <= UART_DUMMY_WAIT_CYCLES;
                    uart_dummy_count <= uart_dummy_count + 8'd1;
                    state <= B_UART_DUMMY;
                end
            end
            B_UART_DUMMY: begin
                if (wait_count != 3'b0) begin
                    wait_count <= wait_count - 3'b1;
                end else begin
                    ext_ram_ce_n <= 1'b1;
                    ext_ram_we_n <= 1'b1;
                    ext_ram_be_n <= 4'hf;
                    ext_drive <= 1'b0;
                    cpu_ready <= 1'b1;
                    state <= B_RESP;
                end
            end
            B_RESP: begin
                base_drive <= 1'b0;
                ext_drive <= 1'b0;
                state <= B_IDLE;
            end
            default: begin
                state <= B_IDLE;
            end
        endcase
    end
end

endmodule

`default_nettype wire
