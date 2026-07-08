////////////////////////////////////////////////////////
// RS-232 RX and TX module
// (c) fpga4fun.com & KNJN LLC - 2003 to 2016

// The RS-232 settings are fixed
// TX: 8-bit data, 2 stop, no-parity
// RX: 8-bit data, 1 stop, no-parity (the receiver can accept more stop bits of course)

//`define SIMULATION   // in this mode, TX outputs one bit per clock cycle
                       // and RX receives one bit per clock cycle (for fast simulations)

////////////////////////////////////////////////////////

module async_transmitter(
	input wire clk,
	input wire reset,
	input wire TxD_start,
	input wire [7:0] TxD_data,
	output reg TxD,
	output reg TxD_busy
);

// Assert TxD_start for (at least) one clock cycle to start transmission of TxD_data
// TxD_data is latched so that it doesn't have to stay valid while it is being sent

parameter ClkFrequency = 25000000;	// 25MHz
parameter Baud = 115200;

// generate
// 	if(ClkFrequency<Baud*8 && (ClkFrequency % Baud!=0)) ASSERTION_ERROR PARAMETER_OUT_OF_RANGE("Frequency incompatible with requested Baud rate");
// endgenerate

function integer log2(input integer v);
begin
	log2 = 0;
	while ((1 << log2) < v) log2 = log2 + 1;
end
endfunction

`ifdef SIMULATION
localparam integer BaudDivider = 1;
`else
localparam integer BaudDivider = (ClkFrequency + Baud / 2) / Baud;
`endif
localparam integer BaudCounterWidth = (log2(BaudDivider) < 1) ? 1 : log2(BaudDivider);

reg [BaudCounterWidth-1:0] baud_count = 0;
reg [3:0] bit_index = 0;
reg [9:0] frame = 10'h3ff;

always @(posedge clk)
begin
	if(reset) begin
		TxD <= 1'b1;
		TxD_busy <= 1'b0;
		baud_count <= {BaudCounterWidth{1'b0}};
		bit_index <= 4'b0;
		frame <= 10'h3ff;
	end else if(!TxD_busy) begin
		TxD <= 1'b1;
		baud_count <= {BaudCounterWidth{1'b0}};
		bit_index <= 4'b0;
		if(TxD_start) begin
			frame <= {1'b1, TxD_data, 1'b0};
			TxD <= 1'b0;
			TxD_busy <= 1'b1;
		end
	end else begin
		if(baud_count == BaudDivider - 1) begin
			baud_count <= {BaudCounterWidth{1'b0}};
			if(bit_index == 4'd9) begin
				TxD <= 1'b1;
				TxD_busy <= 1'b0;
				bit_index <= 4'b0;
				frame <= 10'h3ff;
			end else begin
				TxD <= frame[1];
				frame <= {1'b1, frame[9:1]};
				bit_index <= bit_index + 4'd1;
			end
		end else begin
			baud_count <= baud_count + {{(BaudCounterWidth-1){1'b0}}, 1'b1};
		end
	end
end
endmodule


////////////////////////////////////////////////////////
module async_receiver(
	input wire clk,
	input wire reset,
	input wire RxD,
	output reg RxD_data_ready,
	input wire RxD_clear,
	output reg [7:0] RxD_data  // data received, valid only (for one clock cycle) when RxD_data_ready is asserted
);

parameter ClkFrequency = 25000000; // 25MHz
parameter Baud = 115200;

parameter Oversampling = 8;  // needs to be a power of 2
// we oversample the RxD line at a fixed rate to capture each RxD data bit at the "right" time
// 8 times oversampling by default, use 16 for higher quality reception

// generate
// 	if(ClkFrequency<Baud*Oversampling) ASSERTION_ERROR PARAMETER_OUT_OF_RANGE("Frequency too low for current Baud rate and oversampling");
// 	if(Oversampling<8 || ((Oversampling & (Oversampling-1))!=0)) ASSERTION_ERROR PARAMETER_OUT_OF_RANGE("Invalid oversampling value");
// endgenerate

////////////////////////////////

// We also detect if a gap occurs in the received stream of characters
// That can be useful if multiple characters are sent in burst
//  so that multiple characters can be treated as a "packet"
wire RxD_idle;  // asserted when no data has been received for a while
reg RxD_endofpacket; // asserted for one clock cycle when a packet has been detected (i.e. RxD_idle is going high)


reg [3:0] RxD_state = 0;

`ifdef SIMULATION
wire RxD_bit = RxD;
wire sampleNow = 1'b1;  // receive one bit per clock cycle

`else
wire OversamplingTick;
BaudTickGen #(ClkFrequency, Baud, Oversampling) tickgen(.clk(clk), .enable(1'b1), .tick(OversamplingTick));

// synchronize RxD to our clk domain
reg [1:0] RxD_sync = 2'b11;
always @(posedge clk) if(OversamplingTick) RxD_sync <= {RxD_sync[0], RxD};

// and filter it
reg [1:0] Filter_cnt = 2'b11;
reg RxD_bit = 1'b1;

always @(posedge clk)
if(OversamplingTick)
begin
	if(RxD_sync[1]==1'b1 && Filter_cnt!=2'b11) Filter_cnt <= Filter_cnt + 1'd1;
	else 
	if(RxD_sync[1]==1'b0 && Filter_cnt!=2'b00) Filter_cnt <= Filter_cnt - 1'd1;

	if(Filter_cnt==2'b11) RxD_bit <= 1'b1;
	else
	if(Filter_cnt==2'b00) RxD_bit <= 1'b0;
end

// and decide when is the good time to sample the RxD line
function integer log2(input integer v); begin log2=0; while(v>>log2) log2=log2+1; end endfunction
localparam l2o = log2(Oversampling);
reg [l2o-2:0] OversamplingCnt = 0;
always @(posedge clk) if(OversamplingTick) OversamplingCnt <= (RxD_state==0) ? 1'd0 : OversamplingCnt + 1'd1;
wire sampleNow = OversamplingTick && (OversamplingCnt==Oversampling/2-1);
`endif

// now we can accumulate the RxD bits in a shift-register
always @(posedge clk)
if(reset)
	RxD_state <= 4'b0000;
else
	case(RxD_state)
		4'b0000: if(~RxD_bit) RxD_state <= `ifdef SIMULATION 4'b1000 `else 4'b0001 `endif;  // start bit found?
		4'b0001: if(sampleNow) RxD_state <= 4'b1000;  // sync start bit to sampleNow
		4'b1000: if(sampleNow) RxD_state <= 4'b1001;  // bit 0
		4'b1001: if(sampleNow) RxD_state <= 4'b1010;  // bit 1
		4'b1010: if(sampleNow) RxD_state <= 4'b1011;  // bit 2
		4'b1011: if(sampleNow) RxD_state <= 4'b1100;  // bit 3
		4'b1100: if(sampleNow) RxD_state <= 4'b1101;  // bit 4
		4'b1101: if(sampleNow) RxD_state <= 4'b1110;  // bit 5
		4'b1110: if(sampleNow) RxD_state <= 4'b1111;  // bit 6
		4'b1111: if(sampleNow) RxD_state <= 4'b0010;  // bit 7
		4'b0010: if(sampleNow) RxD_state <= 4'b0000;  // stop bit
		default: RxD_state <= 4'b0000;
	endcase

always @(posedge clk)
if(reset)
	RxD_data <= 8'b0;
else if(sampleNow && RxD_state[3]) RxD_data <= {RxD_bit, RxD_data[7:1]};

//reg RxD_data_error = 0;
always @(posedge clk)
begin
	if(reset)
		RxD_data_ready <= 0;
	else if(RxD_clear)
		RxD_data_ready <= 0;
	else
		RxD_data_ready <= RxD_data_ready | (sampleNow && RxD_state==4'b0010 && RxD_bit);  // make sure a stop bit is received
	//RxD_data_error <= (sampleNow && RxD_state==4'b0010 && ~RxD_bit);  // error if a stop bit is not received
end

`ifdef SIMULATION
assign RxD_idle = 0;
`else
reg [l2o+1:0] GapCnt = 0;
always @(posedge clk) if (RxD_state!=0) GapCnt<=0; else if(OversamplingTick & ~GapCnt[log2(Oversampling)+1]) GapCnt <= GapCnt + 1'h1;
assign RxD_idle = GapCnt[l2o+1];
always @(posedge clk) RxD_endofpacket <= OversamplingTick & ~GapCnt[l2o+1] & &GapCnt[l2o:0];
`endif

endmodule


////////////////////////////////////////////////////////
// dummy module used to be able to raise an assertion in Verilog
module ASSERTION_ERROR();
endmodule


////////////////////////////////////////////////////////
module BaudTickGen(
	input  wire clk, enable,
	output wire tick  // generate a tick at the specified baud rate * oversampling
);
parameter ClkFrequency = 25000000;
parameter Baud = 115200;
parameter Oversampling = 1;

function integer log2(input integer v); begin log2=0; while(v>>log2) log2=log2+1; end endfunction
localparam AccWidth = log2(ClkFrequency/Baud)+8;  // +/- 2% max timing error over a byte
reg [AccWidth:0] Acc = 0;
localparam ShiftLimiter = log2(Baud*Oversampling >> (31-AccWidth));  // this makes sure Inc calculation doesn't overflow
localparam Inc = ((Baud*Oversampling << (AccWidth-ShiftLimiter))+(ClkFrequency>>(ShiftLimiter+1)))/(ClkFrequency>>ShiftLimiter);
always @(posedge clk) if(enable) Acc <= Acc[AccWidth-1:0] + Inc[AccWidth:0]; else Acc <= Inc[AccWidth:0];
assign tick = Acc[AccWidth];
endmodule


////////////////////////////////////////////////////////
