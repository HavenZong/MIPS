`default_nettype none

module mips_core #(
    parameter RESET_PC = 32'h8000_0000
)(
    input  wire        clk,
    input  wire        reset,

    output reg         bus_valid = 1'b0,
    output reg         bus_write = 1'b0,
    output reg  [1:0]  bus_size = 2'b10,
    output reg  [31:0] bus_addr = 32'b0,
    output reg  [31:0] bus_wdata = 32'b0,
    input  wire [31:0] bus_rdata,
    input  wire        bus_ready,

    output reg  [31:0] debug_wb_pc = 32'b0,
    output reg  [3:0]  debug_wb_rf_wen = 4'b0,
    output reg  [4:0]  debug_wb_rf_wnum = 5'b0,
    output reg  [31:0] debug_wb_rf_wdata = 32'b0,
    output wire [31:0] debug_pc
`ifdef SIMULATION
    ,
    output wire [1:0]  debug_bus_owner,
    output wire        debug_fetch_issue_wants,
    output wire        debug_fetch_issue_hit,
    output wire        debug_dcache_mem_hit,
    output wire        debug_mem_stage_needs_bus,
    output wire        debug_mem_stall,
    output wire        debug_load_use_hazard,
    output wire        debug_mul_hazard,
    output wire        debug_control_taken_now,
    output wire        debug_control_pred_miss_now,
    output wire        debug_icache_miss_complete,
    output wire        debug_dcache_load_miss_complete,
    output wire        debug_dcache_prefetch_complete,
    output wire        debug_mem_store_complete,
    output wire        debug_mmio_or_base_load_complete,
    output wire        debug_mul_issue,
    output wire        debug_storeq_full_stall,
    output wire        debug_storeq_load_forward,
    output wire        debug_storeq_load_block,
    output wire        debug_storeq_drain_complete,
    output wire        debug_storeq_enqueue,
    output wire        debug_branch_resolved,
    output wire        debug_branch_pred_taken,
    output wire        debug_branch_pred_hit,
    output wire        debug_branch_unpred_taken
`endif
);

localparam SIZE_BYTE = 2'b00;
localparam SIZE_WORD = 2'b10;

localparam BUS_NONE = 2'd0;
localparam BUS_IF   = 2'd1;
localparam BUS_MEM  = 2'd2;
localparam BUS_DCPF = 2'd3;

localparam integer ICACHE_INDEX_BITS = 11;
localparam integer ICACHE_LINES = (1 << ICACHE_INDEX_BITS);
localparam integer ICACHE_TAG_LSB = ICACHE_INDEX_BITS + 2;
localparam integer DCACHE_INDEX_BITS = 10;
localparam integer DCACHE_LINES = (1 << DCACHE_INDEX_BITS);
localparam integer DCACHE_TAG_LSB = DCACHE_INDEX_BITS + 3;
localparam DCACHE_PREFETCH_ENABLE = 1'b0;

reg [31:0] gpr [0:31];

reg [1:0]  bus_owner;
reg [31:0] if_req_pc;
reg [31:0] fetch_pc;
reg        fetch_buf_valid;
reg [31:0] fetch_buf_pc;
reg [31:0] fetch_buf_inst;
reg        fetch_spill_valid;
reg [31:0] fetch_spill_pc;
reg [31:0] fetch_spill_inst;
reg [31:0] icache_data [0:ICACHE_LINES-1];
reg [31:ICACHE_TAG_LSB] icache_tag [0:ICACHE_LINES-1];
reg [ICACHE_LINES-1:0] icache_valid;
reg        icache_resp_valid;
reg [31:0] icache_resp_pc;
reg [31:0] icache_resp_inst;
(* ram_style = "block" *) reg [63:0] dcache_data [0:DCACHE_LINES-1];
(* ram_style = "block" *) reg [31:DCACHE_TAG_LSB] dcache_tag [0:DCACHE_LINES-1];
reg [DCACHE_LINES*2-1:0] dcache_valid;
reg [63:0] dcache_read_data;
reg [31:DCACHE_TAG_LSB] dcache_read_tag;
reg        dcache_prefetch_valid;
reg [31:0] dcache_prefetch_addr;
reg [1:0]  dcache_prefetch_bits;

reg        redirect_pending;
reg [31:0] redirect_target;
reg [31:0] redirect_delay_pc;

reg        if_id_valid;
reg [31:0] if_id_pc;
reg [31:0] if_id_inst;
reg        if_id_pred_taken;

reg        id_ex_valid;
reg [31:0] id_ex_pc;
reg [5:0]  id_ex_op;
reg [5:0]  id_ex_func;
reg [4:0]  id_ex_rs;
reg [4:0]  id_ex_rt;
reg [4:0]  id_ex_sa;
reg [15:0] id_ex_imm;
reg        id_ex_wb_en;
reg [4:0]  id_ex_wb_addr;
reg        id_ex_mem_read;
reg        id_ex_mem_write;
reg [1:0]  id_ex_mem_size;
reg        id_ex_mem_signed;

reg        ex_mem_valid;
reg [31:0] ex_mem_pc;
reg        ex_mem_wb_en;
reg [4:0]  ex_mem_wb_addr;
reg [31:0] ex_mem_wb_data;
reg        ex_mem_mem_read;
reg        ex_mem_mem_write;
reg [1:0]  ex_mem_mem_size;
reg        ex_mem_mem_signed;
reg [31:0] ex_mem_mem_addr;
reg [31:0] ex_mem_store_data;
reg [4:0]  ex_mem_store_rt;

reg        mem_active;
reg [1:0]  storeq_count;
reg        storeq_active;
reg [31:0] storeq_addr0;
reg [31:0] storeq_data0;
reg [1:0]  storeq_size0;
reg [31:0] storeq_addr1;
reg [31:0] storeq_data1;
reg [1:0]  storeq_size1;

reg        mem_wb_valid;
reg [31:0] mem_wb_pc;
reg        mem_wb_wb_en;
reg [4:0]  mem_wb_wb_addr;
reg [31:0] mem_wb_wb_data;

wire [5:0] id_op    = if_id_inst[31:26];
wire [4:0] id_rs    = if_id_inst[25:21];
wire [4:0] id_rt    = if_id_inst[20:16];
wire [4:0] id_rd    = if_id_inst[15:11];
wire [4:0] id_sa    = if_id_inst[10:6];
wire [5:0] id_func  = if_id_inst[5:0];
wire [15:0] id_imm  = if_id_inst[15:0];
wire [25:0] id_jidx = if_id_inst[25:0];

wire [5:0] ex_op    = id_ex_op;
wire [5:0] ex_func  = id_ex_func;

reg id_uses_rs;
reg id_uses_rt;
reg id_wb_en;
reg [4:0] id_wb_addr;
reg id_mem_read;
reg id_mem_write;
reg [1:0] id_mem_size;
reg id_mem_signed;
reg id_is_control;
reg id_branch_taken;
reg [31:0] id_branch_target;

wire [31:0] id_rs_gpr = (id_rs == 5'd0) ? 32'b0 : gpr[id_rs];
wire [31:0] id_rt_gpr = (id_rt == 5'd0) ? 32'b0 : gpr[id_rt];
reg [31:0] id_rs_value;
reg [31:0] id_rt_value;

wire [31:0] ex_imm_sext = {{16{id_ex_imm[15]}}, id_ex_imm};
wire [31:0] ex_imm_zext = {16'b0, id_ex_imm};

reg [31:0] ex_rs_value;
reg [31:0] ex_rt_value;
reg [31:0] ex_alu_result;
reg [31:0] ex_store_data;
reg [31:0] mem_store_data;

wire signed [31:0] ex_rs_signed_base = ex_rs_value;
wire signed [31:0] ex_rt_signed_base = ex_rt_value;

wire id_ex_is_mul = id_ex_valid && ex_op == 6'b011100;

reg        mul_stage_valid;
reg [31:0] mul_stage_pc;
reg [4:0]  mul_stage_wb_addr;
reg signed [31:0] mul_stage_a;
reg signed [31:0] mul_stage_b;
reg        mul_wb_valid;
reg [31:0] mul_wb_pc;
reg [4:0]  mul_wb_addr;
reg [31:0] mul_wb_data;
wire [31:0] mul_stage_product = mul_stage_a * mul_stage_b;

wire [DCACHE_INDEX_BITS-1:0] dcache_mem_index = ex_mem_mem_addr[DCACHE_TAG_LSB-1:3];
wire [31:DCACHE_TAG_LSB] dcache_mem_tag = ex_mem_mem_addr[31:DCACHE_TAG_LSB];
wire dcache_mem_word = ex_mem_mem_addr[2];
wire [1:0] dcache_mem_valid_bits = dcache_valid[{dcache_mem_index, 1'b0} +: 2];
wire dcache_mem_cacheable = ex_mem_mem_addr >= 32'h8040_0000 && ex_mem_mem_addr < 32'h8080_0000;
wire dcache_mem_hit = ex_mem_valid && ex_mem_mem_read && dcache_mem_cacheable &&
                      dcache_mem_valid_bits[dcache_mem_word] &&
                      dcache_read_tag == dcache_mem_tag;
wire [31:0] dcache_mem_word_data = dcache_mem_word ? dcache_read_data[63:32] : dcache_read_data[31:0];
wire storeq_valid0 = storeq_count != 2'd0;
wire storeq_valid1 = storeq_count == 2'd2;
wire storeq_full = storeq_count == 2'd2;
wire storeq_drain_complete = bus_valid && bus_ready && bus_owner == BUS_MEM && storeq_active;
wire storeq_same_word0 = storeq_valid0 && storeq_addr0[31:2] == ex_mem_mem_addr[31:2];
wire storeq_same_byte0 = storeq_same_word0 && storeq_addr0[1:0] == ex_mem_mem_addr[1:0];
wire storeq_same_word1 = storeq_valid1 && storeq_addr1[31:2] == ex_mem_mem_addr[31:2];
wire storeq_same_byte1 = storeq_same_word1 && storeq_addr1[1:0] == ex_mem_mem_addr[1:0];
wire storeq_byte_blocks_word =
    (storeq_same_word1 && storeq_size1 == SIZE_BYTE) ||
    (storeq_same_word0 && storeq_size0 == SIZE_BYTE &&
     !(storeq_same_word1 && storeq_size1 == SIZE_WORD));
wire storeq_load_word_forward =
    ex_mem_valid && ex_mem_mem_read && ex_mem_mem_size == SIZE_WORD &&
    !storeq_byte_blocks_word &&
    ((storeq_same_word1 && storeq_size1 == SIZE_WORD) ||
     (storeq_same_word0 && storeq_size0 == SIZE_WORD));
wire storeq_load_byte_forward =
    ex_mem_valid && ex_mem_mem_read && ex_mem_mem_size == SIZE_BYTE &&
    ((storeq_same_word1 && storeq_size1 == SIZE_WORD) ||
     (storeq_same_byte1 && storeq_size1 == SIZE_BYTE) ||
     (storeq_same_word0 && storeq_size0 == SIZE_WORD) ||
     (storeq_same_byte0 && storeq_size0 == SIZE_BYTE));
wire storeq_load_block =
    ex_mem_valid && ex_mem_mem_read &&
    ex_mem_mem_size == SIZE_WORD && storeq_byte_blocks_word;
wire [7:0] storeq_load_byte =
    (storeq_same_byte1 && storeq_size1 == SIZE_BYTE) ? storeq_data1[7:0] :
    (storeq_same_word1 && storeq_size1 == SIZE_WORD && ex_mem_mem_addr[1:0] == 2'b00) ? storeq_data1[7:0] :
    (storeq_same_word1 && storeq_size1 == SIZE_WORD && ex_mem_mem_addr[1:0] == 2'b01) ? storeq_data1[15:8] :
    (storeq_same_word1 && storeq_size1 == SIZE_WORD && ex_mem_mem_addr[1:0] == 2'b10) ? storeq_data1[23:16] :
    (storeq_same_word1 && storeq_size1 == SIZE_WORD) ? storeq_data1[31:24] :
    (storeq_same_byte0 && storeq_size0 == SIZE_BYTE) ? storeq_data0[7:0] :
    (ex_mem_mem_addr[1:0] == 2'b00) ? storeq_data0[7:0] :
    (ex_mem_mem_addr[1:0] == 2'b01) ? storeq_data0[15:8] :
    (ex_mem_mem_addr[1:0] == 2'b10) ? storeq_data0[23:16] :
                                      storeq_data0[31:24];
wire [31:0] storeq_load_word =
    (storeq_same_word1 && storeq_size1 == SIZE_WORD) ? storeq_data1 : storeq_data0;
wire [31:0] mem_load_word = storeq_load_word_forward ? storeq_load_word :
                             (dcache_mem_hit ? dcache_mem_word_data : bus_rdata);
wire [7:0] mem_load_byte =
    storeq_load_byte_forward ? storeq_load_byte :
    (ex_mem_mem_addr[1:0] == 2'b00) ? mem_load_word[7:0] :
    (ex_mem_mem_addr[1:0] == 2'b01) ? mem_load_word[15:8] :
    (ex_mem_mem_addr[1:0] == 2'b10) ? mem_load_word[23:16] :
                                      mem_load_word[31:24];
wire [31:0] mem_load_value =
    (ex_mem_mem_size == SIZE_BYTE) ? {{24{ex_mem_mem_signed && mem_load_byte[7]}}, mem_load_byte} : mem_load_word;

wire mem_store_queueable = ex_mem_valid && ex_mem_mem_write && dcache_mem_cacheable;
wire mem_store_enqueue_complete = mem_store_queueable && (!storeq_full || storeq_drain_complete);
wire mem_load_forward_complete = storeq_load_word_forward || storeq_load_byte_forward;
wire mem_direct_needs_bus =
    ex_mem_valid &&
    ((ex_mem_mem_write && !dcache_mem_cacheable) ||
     (ex_mem_mem_read && !dcache_mem_hit && !mem_load_forward_complete));
wire mem_stage_needs_bus =
    mem_direct_needs_bus;
wire mem_bus_completes = mem_direct_needs_bus && mem_active && bus_owner == BUS_MEM && bus_ready;
wire mem_completes =
    mem_store_enqueue_complete || mem_load_forward_complete || dcache_mem_hit || mem_bus_completes;
wire mem_stall =
    (mem_store_queueable && storeq_full) || storeq_load_block ||
    (mem_direct_needs_bus && !mem_bus_completes);
wire mem_blocks_fetch = mem_stall;

wire [DCACHE_INDEX_BITS-1:0] dcache_ex_index = ex_alu_result[DCACHE_TAG_LSB-1:3];
wire dcache_ex_cacheable = ex_alu_result >= 32'h8040_0000 && ex_alu_result < 32'h8080_0000;
wire id_ex_needs_bus =
    id_ex_valid && ((id_ex_mem_write && !dcache_ex_cacheable) ||
                    (id_ex_mem_read && !dcache_ex_cacheable));

wire load_use_hazard =
    if_id_valid && id_ex_valid && id_ex_mem_read && id_ex_wb_addr != 5'b0 &&
    ((id_uses_rs && id_rs == id_ex_wb_addr) || (id_uses_rt && id_rt == id_ex_wb_addr));

wire mem_wb_writes_now = mem_wb_valid && mem_wb_wb_en && mem_wb_wb_addr != 5'b0;
wire mul_wb_writes_now = mul_wb_valid && mul_wb_addr != 5'b0 && !mem_wb_writes_now;
wire mul_pipe_can_advance = !mul_wb_valid || mul_wb_writes_now;
wire mul_pipe_block = (mul_stage_valid || id_ex_is_mul) && !mul_pipe_can_advance;
wire mul_ex_hazard =
    if_id_valid && id_ex_is_mul && id_ex_wb_addr != 5'b0 &&
    ((id_uses_rs && id_rs == id_ex_wb_addr) || (id_uses_rt && id_rt == id_ex_wb_addr) ||
     (id_wb_en && id_wb_addr == id_ex_wb_addr));
wire mul_stage_hazard =
    if_id_valid && mul_stage_valid && mul_stage_wb_addr != 5'b0 &&
    ((id_uses_rs && id_rs == mul_stage_wb_addr) || (id_uses_rt && id_rt == mul_stage_wb_addr) ||
     (id_wb_en && id_wb_addr == mul_stage_wb_addr));
wire mul_wb_waw_hazard =
    if_id_valid && mul_wb_valid && !mul_wb_writes_now && id_wb_en &&
    id_wb_addr != 5'b0 && id_wb_addr == mul_wb_addr;
wire mul_hazard = mul_ex_hazard || mul_stage_hazard || mul_wb_waw_hazard || mul_pipe_block;

wire bus_fetch_response_now = bus_valid && bus_ready && bus_owner == BUS_IF;
wire fetch_response_now = bus_fetch_response_now || icache_resp_valid;
wire [31:0] fetch_response_pc = icache_resp_valid ? icache_resp_pc : if_req_pc;
wire [31:0] fetch_response_inst = icache_resp_valid ? icache_resp_inst : bus_rdata;
wire id_is_register_jump =
    id_op == 6'b000000 && (id_func == 6'b001000 || id_func == 6'b001001);
wire control_storeq_drain_hazard = if_id_valid && id_is_register_jump && storeq_valid0;
wire front_stall = mem_stall || load_use_hazard || mul_hazard || control_storeq_drain_hazard;
wire id_advance = if_id_valid && !front_stall;
wire if_id_can_accept = !front_stall && (!if_id_valid || id_advance);
wire control_taken_now = if_id_valid && !front_stall && id_is_control && id_branch_taken;
wire [31:0] control_delay_pc_now = if_id_pc + 32'd4;
wire control_pred_miss_now =
    if_id_valid && !front_stall && id_is_control && if_id_pred_taken && !id_branch_taken;
wire fetch_buf_take = fetch_buf_valid && if_id_can_accept &&
                      (!redirect_pending || fetch_buf_pc == redirect_delay_pc) &&
                      (!control_taken_now || fetch_buf_pc == control_delay_pc_now);
wire fetch_response_can_enqueue = fetch_response_now &&
                                  (!redirect_pending || fetch_response_pc == redirect_delay_pc) &&
                                  (!control_taken_now || fetch_response_pc == control_delay_pc_now);
wire [5:0] fetch_buf_op = fetch_buf_inst[31:26];
wire [5:0] fetch_buf_func = fetch_buf_inst[5:0];
wire fetch_buf_is_control =
    fetch_buf_valid &&
    ((fetch_buf_op == 6'b000000 && (fetch_buf_func == 6'b001000 || fetch_buf_func == 6'b001001)) ||
     fetch_buf_op == 6'b000001 || fetch_buf_op == 6'b000010 ||
     fetch_buf_op == 6'b000011 || fetch_buf_op == 6'b000100 ||
     fetch_buf_op == 6'b000101 || fetch_buf_op == 6'b000110 ||
     fetch_buf_op == 6'b000111);
wire fetch_buf_is_cond_branch =
    fetch_buf_valid &&
    (fetch_buf_op == 6'b000001 || fetch_buf_op == 6'b000100 ||
     fetch_buf_op == 6'b000101 || fetch_buf_op == 6'b000110 ||
     fetch_buf_op == 6'b000111);
wire fetch_buf_predict_taken = fetch_buf_is_cond_branch && fetch_buf_inst[15];
wire [31:0] fetch_buf_predict_target =
    fetch_buf_pc + 32'd4 + {{14{fetch_buf_inst[15]}}, fetch_buf_inst[15:0], 2'b00};
wire redirect_action_now = redirect_pending || control_taken_now;
wire redirect_fetch_after_delay = fetch_buf_take && redirect_action_now;
wire [31:0] redirect_fetch_pc =
    control_pred_miss_now ? if_id_pc + 32'd8 :
    (redirect_pending ? redirect_target : id_branch_target);
wire stream_fetch_after_take = fetch_buf_take && !redirect_pending &&
                               !control_taken_now && !fetch_spill_valid &&
                               (!fetch_buf_is_control || fetch_buf_predict_taken);
wire bus_free_after_ready = !bus_valid || bus_ready;
wire can_issue_ex_mem = bus_free_after_ready && (!mem_stage_needs_bus || mem_completes) &&
                        id_ex_needs_bus && !mem_stall && !mul_pipe_block;
wire can_issue_redirect_fetch = bus_free_after_ready && !fetch_response_now &&
                                !mem_blocks_fetch && redirect_fetch_after_delay;
wire can_issue_stream_fetch = bus_free_after_ready && !fetch_response_now &&
                              !mem_blocks_fetch && stream_fetch_after_take;
wire can_issue_fetch = bus_free_after_ready && !fetch_response_now &&
                       !fetch_buf_valid && !fetch_spill_valid && !mem_blocks_fetch &&
                       if_id_can_accept && (!redirect_pending || fetch_pc == redirect_delay_pc) &&
                       (!control_taken_now || fetch_pc == control_delay_pc_now);
wire fetch_issue_wants = can_issue_stream_fetch || can_issue_fetch;
wire [31:0] fetch_issue_pc = fetch_pc;
wire fetch_issue_cache_ok = !(if_id_valid && id_is_control) && !redirect_pending;
wire fetch_issue_cacheable = fetch_issue_cache_ok &&
                             fetch_issue_pc >= 32'h8010_0000 && fetch_issue_pc < 32'h8080_0000;
wire [ICACHE_INDEX_BITS-1:0] fetch_issue_index =
    fetch_issue_cache_ok ? fetch_issue_pc[ICACHE_TAG_LSB-1:2] : {ICACHE_INDEX_BITS{1'b0}};
wire [31:ICACHE_TAG_LSB] fetch_issue_tag =
    fetch_issue_cache_ok ? fetch_issue_pc[31:ICACHE_TAG_LSB] : {(32-ICACHE_TAG_LSB){1'b0}};
wire fetch_issue_hit = fetch_issue_cacheable && icache_valid[fetch_issue_index] &&
                       icache_tag[fetch_issue_index] == fetch_issue_tag;
wire [31:0] fetch_issue_inst = icache_data[fetch_issue_index];
wire [ICACHE_INDEX_BITS-1:0] if_req_index = if_req_pc[ICACHE_TAG_LSB-1:2];
wire if_req_cacheable = if_req_pc >= 32'h8010_0000 && if_req_pc < 32'h8080_0000;
wire [ICACHE_INDEX_BITS-1:0] ex_mem_addr_index = ex_mem_mem_addr[ICACHE_TAG_LSB-1:2];
wire [ICACHE_INDEX_BITS-1:0] storeq_addr_icache_index = storeq_addr0[ICACHE_TAG_LSB-1:2];
wire [DCACHE_INDEX_BITS-1:0] bus_dcache_index = bus_addr[DCACHE_TAG_LSB-1:3];
wire bus_dcache_word = bus_addr[2];
wire [1:0] bus_dcache_valid_bits = dcache_valid[{bus_dcache_index, 1'b0} +: 2];
wire bus_dcache_cacheable = bus_addr >= 32'h8040_0000 && bus_addr < 32'h8080_0000;
wire bus_mem_store_word = bus_write && bus_size == SIZE_WORD;
wire [1:0] bus_dcache_word_valid = bus_dcache_word ? 2'b10 : 2'b01;
wire [1:0] bus_dcache_fill_bits =
    (dcache_read_tag == bus_addr[31:DCACHE_TAG_LSB]) ?
    (bus_dcache_valid_bits | bus_dcache_word_valid) :
    bus_dcache_word_valid;
wire storeq_must_drain =
    storeq_valid0 &&
    (control_storeq_drain_hazard || mem_direct_needs_bus ||
     (mem_store_queueable && storeq_full) || storeq_load_block);
wire can_issue_storeq = bus_free_after_ready && storeq_valid0 && !storeq_active &&
                        (storeq_must_drain ||
                         (!fetch_issue_wants && !redirect_fetch_after_delay));
wire can_issue_dcache_prefetch = DCACHE_PREFETCH_ENABLE && bus_free_after_ready && !fetch_response_now &&
                                 !mem_blocks_fetch && !storeq_valid0 && dcache_prefetch_valid;

assign debug_pc = fetch_pc;
`ifdef SIMULATION
assign debug_bus_owner = bus_owner;
assign debug_fetch_issue_wants = fetch_issue_wants;
assign debug_fetch_issue_hit = fetch_issue_hit;
assign debug_dcache_mem_hit = dcache_mem_hit;
assign debug_mem_stage_needs_bus = mem_stage_needs_bus;
assign debug_mem_stall = mem_stall;
assign debug_load_use_hazard = load_use_hazard;
assign debug_mul_hazard = mul_hazard;
assign debug_control_taken_now = control_taken_now;
assign debug_control_pred_miss_now = control_pred_miss_now;
assign debug_icache_miss_complete = bus_valid && bus_ready && bus_owner == BUS_IF;
assign debug_dcache_load_miss_complete =
    mem_bus_completes && ex_mem_mem_read && dcache_mem_cacheable;
assign debug_dcache_prefetch_complete =
    bus_valid && bus_ready && bus_owner == BUS_DCPF;
assign debug_mem_store_complete =
    (mem_bus_completes && ex_mem_mem_write) ||
    (bus_valid && bus_ready && bus_owner == BUS_MEM && storeq_active);
assign debug_mmio_or_base_load_complete =
    mem_bus_completes && ex_mem_mem_read && !dcache_mem_cacheable;
assign debug_mul_issue = !mem_stall && !mul_pipe_block && id_ex_is_mul;
assign debug_storeq_full_stall = mem_store_queueable && storeq_full && !storeq_drain_complete;
assign debug_storeq_load_forward = mem_load_forward_complete;
assign debug_storeq_load_block = storeq_load_block;
assign debug_storeq_drain_complete = storeq_drain_complete;
assign debug_storeq_enqueue = mem_store_enqueue_complete;
assign debug_branch_resolved = if_id_valid && !front_stall && id_is_control;
assign debug_branch_pred_taken = if_id_valid && !front_stall && id_is_control && if_id_pred_taken;
assign debug_branch_pred_hit = if_id_valid && !front_stall && id_is_control &&
                               if_id_pred_taken && id_branch_taken;
assign debug_branch_unpred_taken = if_id_valid && !front_stall && id_is_control &&
                                   !if_id_pred_taken && id_branch_taken;
`endif

always @(*) begin
    id_rs_value = id_rs_gpr;
    id_rt_value = id_rt_gpr;

    if (id_ex_valid && id_ex_wb_en && !id_ex_mem_read && !id_ex_is_mul &&
        id_ex_wb_addr != 5'b0 && id_ex_wb_addr == id_rs) begin
        id_rs_value = ex_alu_result;
    end else if (ex_mem_valid && ex_mem_wb_en && !ex_mem_mem_read && ex_mem_wb_addr != 5'b0 && ex_mem_wb_addr == id_rs) begin
        id_rs_value = ex_mem_wb_data;
    end else if (mul_wb_valid && mul_wb_addr != 5'b0 && mul_wb_addr == id_rs) begin
        id_rs_value = mul_wb_data;
    end else if (mem_wb_valid && mem_wb_wb_en && mem_wb_wb_addr != 5'b0 && mem_wb_wb_addr == id_rs) begin
        id_rs_value = mem_wb_wb_data;
    end

    if (id_ex_valid && id_ex_wb_en && !id_ex_mem_read && !id_ex_is_mul &&
        id_ex_wb_addr != 5'b0 && id_ex_wb_addr == id_rt) begin
        id_rt_value = ex_alu_result;
    end else if (ex_mem_valid && ex_mem_wb_en && !ex_mem_mem_read && ex_mem_wb_addr != 5'b0 && ex_mem_wb_addr == id_rt) begin
        id_rt_value = ex_mem_wb_data;
    end else if (mul_wb_valid && mul_wb_addr != 5'b0 && mul_wb_addr == id_rt) begin
        id_rt_value = mul_wb_data;
    end else if (mem_wb_valid && mem_wb_wb_en && mem_wb_wb_addr != 5'b0 && mem_wb_wb_addr == id_rt) begin
        id_rt_value = mem_wb_wb_data;
    end
end

always @(*) begin
    id_uses_rs = 1'b0;
    id_uses_rt = 1'b0;
    id_wb_en = 1'b0;
    id_wb_addr = 5'b0;
    id_mem_read = 1'b0;
    id_mem_write = 1'b0;
    id_mem_size = SIZE_WORD;
    id_mem_signed = 1'b0;
    id_is_control = 1'b0;
    id_branch_taken = 1'b0;
    id_branch_target = 32'b0;

    case (id_op)
        6'b000000: begin
            case (id_func)
                6'b001000: begin id_uses_rs = 1'b1; id_is_control = 1'b1; id_branch_taken = 1'b1; id_branch_target = id_rs_value; end // JR
                6'b001001: begin id_uses_rs = 1'b1; id_wb_en = 1'b1; id_wb_addr = id_rd; id_is_control = 1'b1; id_branch_taken = 1'b1; id_branch_target = id_rs_value; end // JALR
                6'b000000,
                6'b000010,
                6'b000011: begin id_uses_rt = 1'b1; id_wb_en = 1'b1; id_wb_addr = id_rd; end
                default: begin id_uses_rs = 1'b1; id_uses_rt = 1'b1; id_wb_en = 1'b1; id_wb_addr = id_rd; end
            endcase
        end
        6'b011100: begin id_uses_rs = 1'b1; id_uses_rt = 1'b1; id_wb_en = 1'b1; id_wb_addr = id_rd; end // MUL
        6'b001000,
        6'b001001,
        6'b001100,
        6'b001101,
        6'b001110: begin id_uses_rs = 1'b1; id_wb_en = 1'b1; id_wb_addr = id_rt; end
        6'b001111: begin id_wb_en = 1'b1; id_wb_addr = id_rt; end // LUI
        6'b100000: begin id_uses_rs = 1'b1; id_wb_en = 1'b1; id_wb_addr = id_rt; id_mem_read = 1'b1; id_mem_size = SIZE_BYTE; id_mem_signed = 1'b1; end
        6'b100011: begin id_uses_rs = 1'b1; id_wb_en = 1'b1; id_wb_addr = id_rt; id_mem_read = 1'b1; id_mem_size = SIZE_WORD; end
        6'b101000: begin id_uses_rs = 1'b1; id_uses_rt = 1'b1; id_mem_write = 1'b1; id_mem_size = SIZE_BYTE; end
        6'b101011: begin id_uses_rs = 1'b1; id_uses_rt = 1'b1; id_mem_write = 1'b1; id_mem_size = SIZE_WORD; end
        6'b000100: begin id_uses_rs = 1'b1; id_uses_rt = 1'b1; id_is_control = 1'b1; id_branch_taken = (id_rs_value == id_rt_value); id_branch_target = if_id_pc + 32'd4 + {{14{id_imm[15]}}, id_imm, 2'b00}; end
        6'b000101: begin id_uses_rs = 1'b1; id_uses_rt = 1'b1; id_is_control = 1'b1; id_branch_taken = (id_rs_value != id_rt_value); id_branch_target = if_id_pc + 32'd4 + {{14{id_imm[15]}}, id_imm, 2'b00}; end
        6'b000001: begin id_uses_rs = 1'b1; id_is_control = 1'b1; id_branch_taken = (id_rt == 5'b00001) ? ($signed(id_rs_value) >= 0) : ($signed(id_rs_value) < 0); id_branch_target = if_id_pc + 32'd4 + {{14{id_imm[15]}}, id_imm, 2'b00}; end
        6'b000111: begin id_uses_rs = 1'b1; id_is_control = 1'b1; id_branch_taken = ($signed(id_rs_value) > 0); id_branch_target = if_id_pc + 32'd4 + {{14{id_imm[15]}}, id_imm, 2'b00}; end
        6'b000110: begin id_uses_rs = 1'b1; id_is_control = 1'b1; id_branch_taken = ($signed(id_rs_value) <= 0); id_branch_target = if_id_pc + 32'd4 + {{14{id_imm[15]}}, id_imm, 2'b00}; end
        6'b000010: begin id_is_control = 1'b1; id_branch_taken = 1'b1; id_branch_target = {if_id_pc[31:28], id_jidx, 2'b00}; end
        6'b000011: begin id_wb_en = 1'b1; id_wb_addr = 5'd31; id_is_control = 1'b1; id_branch_taken = 1'b1; id_branch_target = {if_id_pc[31:28], id_jidx, 2'b00}; end
        default: begin end
    endcase
end

always @(*) begin
    ex_rs_value = (id_ex_rs == 5'd0) ? 32'b0 : gpr[id_ex_rs];
    ex_rt_value = (id_ex_rt == 5'd0) ? 32'b0 : gpr[id_ex_rt];

    if (ex_mem_valid && ex_mem_wb_en && !ex_mem_mem_read && ex_mem_wb_addr != 5'b0 && ex_mem_wb_addr == id_ex_rs) begin
        ex_rs_value = ex_mem_wb_data;
    end else if (mul_wb_valid && mul_wb_addr != 5'b0 && mul_wb_addr == id_ex_rs) begin
        ex_rs_value = mul_wb_data;
    end else if (mem_wb_valid && mem_wb_wb_en && mem_wb_wb_addr != 5'b0 && mem_wb_wb_addr == id_ex_rs) begin
        ex_rs_value = mem_wb_wb_data;
    end

    if (ex_mem_valid && ex_mem_wb_en && !ex_mem_mem_read && ex_mem_wb_addr != 5'b0 && ex_mem_wb_addr == id_ex_rt) begin
        ex_rt_value = ex_mem_wb_data;
    end else if (mul_wb_valid && mul_wb_addr != 5'b0 && mul_wb_addr == id_ex_rt) begin
        ex_rt_value = mul_wb_data;
    end else if (mem_wb_valid && mem_wb_wb_en && mem_wb_wb_addr != 5'b0 && mem_wb_wb_addr == id_ex_rt) begin
        ex_rt_value = mem_wb_wb_data;
    end
end

always @(*) begin
    mem_store_data = ex_mem_store_data;
    if (ex_mem_mem_write && ex_mem_store_rt != 5'b0) begin
        mem_store_data = gpr[ex_mem_store_rt];
        if (mul_wb_valid && mul_wb_addr == ex_mem_store_rt) begin
            mem_store_data = mul_wb_data;
        end else if (mem_wb_valid && mem_wb_wb_en && mem_wb_wb_addr == ex_mem_store_rt) begin
            mem_store_data = mem_wb_wb_data;
        end
    end
end

always @(*) begin
    ex_alu_result = 32'b0;
    ex_store_data = ex_rt_value;

    case (ex_op)
        6'b000000: begin
            case (ex_func)
                6'b100000,
                6'b100001: ex_alu_result = ex_rs_value + ex_rt_value;
                6'b100010: ex_alu_result = ex_rs_value - ex_rt_value;
                6'b101010: ex_alu_result = ($signed(ex_rs_value) < $signed(ex_rt_value)) ? 32'd1 : 32'd0;
                6'b100100: ex_alu_result = ex_rs_value & ex_rt_value;
                6'b100101: ex_alu_result = ex_rs_value | ex_rt_value;
                6'b100110: ex_alu_result = ex_rs_value ^ ex_rt_value;
                6'b000000: ex_alu_result = ex_rt_value << id_ex_sa;
                6'b000010: ex_alu_result = ex_rt_value >> id_ex_sa;
                6'b000011: ex_alu_result = $signed(ex_rt_value) >>> id_ex_sa;
                6'b000100: ex_alu_result = ex_rt_value << ex_rs_value[4:0];
                6'b000110: ex_alu_result = ex_rt_value >> ex_rs_value[4:0];
                6'b000111: ex_alu_result = $signed(ex_rt_value) >>> ex_rs_value[4:0];
                6'b001001: ex_alu_result = id_ex_pc + 32'd8;
                default: ex_alu_result = 32'b0;
            endcase
        end
        6'b011100: ex_alu_result = 32'b0;
        6'b001000,
        6'b001001: ex_alu_result = ex_rs_value + ex_imm_sext;
        6'b001100: ex_alu_result = ex_rs_value & ex_imm_zext;
        6'b001101: ex_alu_result = ex_rs_value | ex_imm_zext;
        6'b001110: ex_alu_result = ex_rs_value ^ ex_imm_zext;
        6'b001111: ex_alu_result = {id_ex_imm, 16'b0};
        6'b100000,
        6'b100011,
        6'b101000,
        6'b101011: ex_alu_result = ex_rs_value + ex_imm_sext;
        6'b000011: ex_alu_result = id_ex_pc + 32'd8;
        default: ex_alu_result = 32'b0;
    endcase
end

integer i;

always @(posedge clk) begin
    if (!mem_stall) begin
        dcache_read_data <= dcache_data[dcache_ex_index];
        dcache_read_tag <= dcache_tag[dcache_ex_index];
    end

    if (bus_valid && bus_ready &&
        (bus_owner == BUS_MEM || bus_owner == BUS_DCPF) && bus_dcache_cacheable &&
        (!bus_write || bus_mem_store_word)) begin
        if (bus_dcache_word) begin
            dcache_data[bus_dcache_index][63:32] <= bus_write ? bus_wdata : bus_rdata;
        end else begin
            dcache_data[bus_dcache_index][31:0] <= bus_write ? bus_wdata : bus_rdata;
        end
        dcache_tag[bus_dcache_index] <= bus_addr[31:DCACHE_TAG_LSB];
    end
end

always @(posedge clk) begin
    if (reset) begin
        bus_valid <= 1'b0;
        bus_write <= 1'b0;
        bus_size <= SIZE_WORD;
        bus_addr <= 32'b0;
        bus_wdata <= 32'b0;
        bus_owner <= BUS_NONE;
        if_req_pc <= RESET_PC;
        fetch_pc <= RESET_PC;
        fetch_buf_valid <= 1'b0;
        fetch_buf_pc <= 32'b0;
        fetch_buf_inst <= 32'b0;
        fetch_spill_valid <= 1'b0;
        fetch_spill_pc <= 32'b0;
        fetch_spill_inst <= 32'b0;
        icache_valid <= {ICACHE_LINES{1'b0}};
        icache_resp_valid <= 1'b0;
        icache_resp_pc <= 32'b0;
        icache_resp_inst <= 32'b0;
        dcache_valid <= {(DCACHE_LINES*2){1'b0}};
        dcache_prefetch_valid <= 1'b0;
        dcache_prefetch_addr <= 32'b0;
        dcache_prefetch_bits <= 2'b00;
        redirect_pending <= 1'b0;
        redirect_target <= 32'b0;
        redirect_delay_pc <= 32'b0;
        if_id_valid <= 1'b0;
        if_id_pc <= 32'b0;
        if_id_inst <= 32'b0;
        if_id_pred_taken <= 1'b0;
        id_ex_valid <= 1'b0;
        id_ex_pc <= 32'b0;
        id_ex_op <= 6'b0;
        id_ex_func <= 6'b0;
        id_ex_rs <= 5'b0;
        id_ex_rt <= 5'b0;
        id_ex_sa <= 5'b0;
        id_ex_imm <= 16'b0;
        id_ex_wb_en <= 1'b0;
        id_ex_wb_addr <= 5'b0;
        id_ex_mem_read <= 1'b0;
        id_ex_mem_write <= 1'b0;
        id_ex_mem_size <= SIZE_WORD;
        id_ex_mem_signed <= 1'b0;
        ex_mem_valid <= 1'b0;
        ex_mem_pc <= 32'b0;
        ex_mem_wb_en <= 1'b0;
        ex_mem_wb_addr <= 5'b0;
        ex_mem_wb_data <= 32'b0;
        ex_mem_mem_read <= 1'b0;
        ex_mem_mem_write <= 1'b0;
        ex_mem_mem_size <= SIZE_WORD;
        ex_mem_mem_signed <= 1'b0;
        ex_mem_mem_addr <= 32'b0;
        ex_mem_store_data <= 32'b0;
        ex_mem_store_rt <= 5'b0;
        mul_stage_valid <= 1'b0;
        mul_stage_pc <= 32'b0;
        mul_stage_wb_addr <= 5'b0;
        mul_stage_a <= 32'b0;
        mul_stage_b <= 32'b0;
        mul_wb_valid <= 1'b0;
        mul_wb_pc <= 32'b0;
        mul_wb_addr <= 5'b0;
        mul_wb_data <= 32'b0;
        mem_active <= 1'b0;
        storeq_count <= 2'd0;
        storeq_active <= 1'b0;
        storeq_addr0 <= 32'b0;
        storeq_data0 <= 32'b0;
        storeq_size0 <= SIZE_WORD;
        storeq_addr1 <= 32'b0;
        storeq_data1 <= 32'b0;
        storeq_size1 <= SIZE_WORD;
        mem_wb_valid <= 1'b0;
        mem_wb_pc <= 32'b0;
        mem_wb_wb_en <= 1'b0;
        mem_wb_wb_addr <= 5'b0;
        mem_wb_wb_data <= 32'b0;
        debug_wb_pc <= 32'b0;
        debug_wb_rf_wen <= 4'b0;
        debug_wb_rf_wnum <= 5'b0;
        debug_wb_rf_wdata <= 32'b0;
        for (i = 0; i < 32; i = i + 1) begin
            gpr[i] <= 32'b0;
        end
    end else begin
        debug_wb_rf_wen <= 4'b0;

        if (mem_wb_writes_now) begin
            gpr[mem_wb_wb_addr] <= mem_wb_wb_data;
            debug_wb_pc <= mem_wb_pc;
            debug_wb_rf_wen <= 4'hf;
            debug_wb_rf_wnum <= mem_wb_wb_addr;
            debug_wb_rf_wdata <= mem_wb_wb_data;
        end else if (mul_wb_writes_now) begin
            gpr[mul_wb_addr] <= mul_wb_data;
            debug_wb_pc <= mul_wb_pc;
            debug_wb_rf_wen <= 4'hf;
            debug_wb_rf_wnum <= mul_wb_addr;
            debug_wb_rf_wdata <= mul_wb_data;
        end
        gpr[0] <= 32'b0;

        if (mul_wb_writes_now) begin
            mul_wb_valid <= 1'b0;
        end

        if (fetch_response_now) begin
            if (fetch_response_can_enqueue && !fetch_buf_take) begin
                if (fetch_buf_valid && !fetch_spill_valid) begin
                    fetch_spill_valid <= 1'b1;
                    fetch_spill_pc <= fetch_response_pc;
                    fetch_spill_inst <= fetch_response_inst;
                end else if (!fetch_buf_valid) begin
                    fetch_buf_valid <= 1'b1;
                    fetch_buf_pc <= fetch_response_pc;
                    fetch_buf_inst <= fetch_response_inst;
                end
            end
            icache_resp_valid <= 1'b0;
        end

        if (bus_valid && bus_ready) begin
            if (bus_owner == BUS_IF) begin
                if (if_req_cacheable) begin
                    icache_data[if_req_index] <= bus_rdata;
                    icache_tag[if_req_index] <= if_req_pc[31:ICACHE_TAG_LSB];
                    icache_valid[if_req_index] <= 1'b1;
                end
            end else if (bus_owner == BUS_MEM && bus_dcache_cacheable) begin
                if (bus_write) begin
                    dcache_valid[{bus_dcache_index, 1'b0} +: 2] <=
                        bus_mem_store_word ? bus_dcache_word_valid : 2'b00;
                    dcache_prefetch_valid <= 1'b0;
                end else begin
                    dcache_valid[{bus_dcache_index, 1'b0} +: 2] <= bus_dcache_fill_bits;
                    dcache_prefetch_valid <= !bus_dcache_word && !bus_dcache_fill_bits[1];
                    dcache_prefetch_addr <= bus_addr + 32'h0000_0004;
                    dcache_prefetch_bits <= bus_dcache_fill_bits;
                end
            end else if (bus_owner == BUS_DCPF && bus_dcache_cacheable) begin
                dcache_valid[{bus_dcache_index, 1'b0} +: 2] <=
                    dcache_prefetch_bits | bus_dcache_word_valid;
            end
            bus_valid <= 1'b0;
            bus_owner <= BUS_NONE;
        end

        if (mem_completes) begin
            mem_wb_valid <= ex_mem_valid;
            mem_wb_pc <= ex_mem_pc;
            mem_wb_wb_en <= ex_mem_wb_en && ex_mem_mem_read;
            mem_wb_wb_addr <= ex_mem_wb_addr;
            mem_wb_wb_data <= mem_load_value;
            mem_active <= 1'b0;
            if (mem_store_enqueue_complete) begin
                icache_valid[ex_mem_addr_index] <= 1'b0;
                dcache_prefetch_valid <= 1'b0;
            end
        end else if (!mem_stall) begin
            mem_wb_valid <= ex_mem_valid && !(ex_mem_mem_read || ex_mem_mem_write);
            mem_wb_pc <= ex_mem_pc;
            mem_wb_wb_en <= ex_mem_wb_en && !(ex_mem_mem_read || ex_mem_mem_write);
            mem_wb_wb_addr <= ex_mem_wb_addr;
            mem_wb_wb_data <= ex_mem_wb_data;
        end else begin
            mem_wb_valid <= 1'b0;
        end

        if (!mem_stall && !mul_pipe_block) begin
            if (mul_pipe_can_advance) begin
                mul_wb_valid <= mul_stage_valid;
                mul_wb_pc <= mul_stage_pc;
                mul_wb_addr <= mul_stage_wb_addr;
                mul_wb_data <= mul_stage_product;
                mul_stage_valid <= id_ex_is_mul;
                mul_stage_pc <= id_ex_pc;
                mul_stage_wb_addr <= id_ex_wb_addr;
                mul_stage_a <= ex_rs_signed_base;
                mul_stage_b <= ex_rt_signed_base;
            end

            ex_mem_valid <= id_ex_valid && !id_ex_is_mul;
            ex_mem_pc <= id_ex_pc;
            ex_mem_wb_en <= id_ex_wb_en && !id_ex_is_mul;
            ex_mem_wb_addr <= id_ex_wb_addr;
            ex_mem_wb_data <= ex_alu_result;
            ex_mem_mem_read <= id_ex_mem_read;
            ex_mem_mem_write <= id_ex_mem_write;
            ex_mem_mem_size <= id_ex_mem_size;
            ex_mem_mem_signed <= id_ex_mem_signed;
            ex_mem_mem_addr <= ex_alu_result;
            ex_mem_store_data <= ex_store_data;
            ex_mem_store_rt <= id_ex_rt;

            if (load_use_hazard || mul_ex_hazard || mul_stage_hazard || mul_wb_waw_hazard) begin
                id_ex_valid <= 1'b0;
                id_ex_wb_en <= 1'b0;
                id_ex_mem_read <= 1'b0;
                id_ex_mem_write <= 1'b0;
            end else begin
                id_ex_valid <= if_id_valid;
                id_ex_pc <= if_id_pc;
                id_ex_op <= id_op;
                id_ex_func <= id_func;
                id_ex_rs <= id_rs;
                id_ex_rt <= id_rt;
                id_ex_sa <= id_sa;
                id_ex_imm <= id_imm;
                id_ex_wb_en <= id_wb_en;
                id_ex_wb_addr <= id_wb_addr;
                id_ex_mem_read <= id_mem_read;
                id_ex_mem_write <= id_mem_write;
                id_ex_mem_size <= id_mem_size;
                id_ex_mem_signed <= id_mem_signed;

                if (if_id_valid && id_is_control && (id_branch_taken || if_id_pred_taken)) begin
                    redirect_pending <= 1'b1;
                    redirect_target <= id_branch_taken ? id_branch_target : if_id_pc + 32'd8;
                    redirect_delay_pc <= if_id_pc + 32'd4;
                    fetch_pc <= if_id_pc + 32'd4;
                    if ((fetch_buf_valid && fetch_buf_pc != if_id_pc + 32'd4) ||
                        (fetch_response_now && fetch_response_pc != if_id_pc + 32'd4)) begin
                        if (fetch_spill_valid && fetch_spill_pc == if_id_pc + 32'd4) begin
                            fetch_buf_valid <= 1'b1;
                            fetch_buf_pc <= fetch_spill_pc;
                            fetch_buf_inst <= fetch_spill_inst;
                            fetch_spill_valid <= 1'b0;
                        end else begin
                            fetch_buf_valid <= 1'b0;
                        end
                    end
                    if (fetch_spill_valid && fetch_spill_pc != if_id_pc + 32'd4) begin
                        fetch_spill_valid <= 1'b0;
                    end
                end

                if (fetch_buf_take) begin
                    if_id_valid <= 1'b1;
                    if_id_pc <= fetch_buf_pc;
                    if_id_inst <= fetch_buf_inst;
                    if_id_pred_taken <= fetch_buf_predict_taken && !redirect_pending && !control_taken_now;
                    if (redirect_action_now) begin
                        fetch_buf_valid <= 1'b0;
                        fetch_spill_valid <= 1'b0;
                        fetch_pc <= redirect_fetch_pc;
                        redirect_pending <= 1'b0;
                    end else begin
                        if (fetch_buf_predict_taken && !redirect_pending && !control_taken_now) begin
                            redirect_pending <= 1'b1;
                            redirect_target <= fetch_buf_predict_target;
                            redirect_delay_pc <= fetch_buf_pc + 32'd4;
                            fetch_pc <= fetch_buf_pc + 32'd4;
                        end
                        if (fetch_spill_valid) begin
                            fetch_buf_valid <= 1'b1;
                            fetch_buf_pc <= fetch_spill_pc;
                            fetch_buf_inst <= fetch_spill_inst;
                            if (fetch_response_can_enqueue) begin
                                fetch_spill_valid <= 1'b1;
                                fetch_spill_pc <= fetch_response_pc;
                                fetch_spill_inst <= fetch_response_inst;
                            end else begin
                                fetch_spill_valid <= 1'b0;
                            end
                        end else if (fetch_response_can_enqueue) begin
                            fetch_buf_valid <= 1'b1;
                            fetch_buf_pc <= fetch_response_pc;
                            fetch_buf_inst <= fetch_response_inst;
                            fetch_spill_valid <= 1'b0;
                        end else begin
                            fetch_buf_valid <= 1'b0;
                            fetch_spill_valid <= 1'b0;
                        end
                    end
                end else if (if_id_valid) begin
                    if_id_valid <= 1'b0;
                    if_id_pred_taken <= 1'b0;
                end
            end
        end

        if (can_issue_storeq) begin
            bus_valid <= 1'b1;
            bus_owner <= BUS_MEM;
            bus_write <= 1'b1;
            bus_size <= storeq_size0;
            bus_addr <= storeq_addr0;
            bus_wdata <= storeq_data0;
            icache_valid[storeq_addr_icache_index] <= 1'b0;
        end else if (!bus_valid && mem_stage_needs_bus && !mem_active) begin
            bus_valid <= 1'b1;
            bus_owner <= BUS_MEM;
            bus_write <= ex_mem_mem_write;
            bus_size <= ex_mem_mem_size;
            bus_addr <= ex_mem_mem_addr;
            bus_wdata <= mem_store_data;
            mem_active <= 1'b1;
            if (ex_mem_mem_write) begin
                icache_valid[ex_mem_addr_index] <= 1'b0;
            end
        end else if (can_issue_ex_mem) begin
            bus_valid <= 1'b1;
            bus_owner <= BUS_MEM;
            bus_write <= id_ex_mem_write;
            bus_size <= id_ex_mem_size;
            bus_addr <= ex_alu_result;
            bus_wdata <= ex_store_data;
            mem_active <= 1'b1;
        end else if (can_issue_redirect_fetch) begin
            bus_valid <= 1'b1;
            bus_owner <= BUS_IF;
            bus_write <= 1'b0;
            bus_size <= SIZE_WORD;
            bus_addr <= redirect_fetch_pc;
            bus_wdata <= 32'b0;
            if_req_pc <= redirect_fetch_pc;
            fetch_pc <= redirect_fetch_pc + 32'd4;
        end else if (fetch_issue_wants) begin
            bus_write <= 1'b0;
            bus_size <= SIZE_WORD;
            bus_wdata <= 32'b0;
            if_req_pc <= fetch_issue_pc;
            fetch_pc <= fetch_issue_pc + 32'd4;
            if (fetch_issue_hit) begin
                icache_resp_valid <= 1'b1;
                icache_resp_pc <= fetch_issue_pc;
                icache_resp_inst <= fetch_issue_inst;
                bus_owner <= BUS_IF;
                bus_addr <= fetch_issue_pc;
            end else begin
                bus_valid <= 1'b1;
                bus_owner <= BUS_IF;
                bus_addr <= fetch_issue_pc;
            end
        end else if (can_issue_dcache_prefetch) begin
            bus_valid <= 1'b1;
            bus_owner <= BUS_DCPF;
            bus_write <= 1'b0;
            bus_size <= SIZE_WORD;
            bus_addr <= dcache_prefetch_addr;
            bus_wdata <= 32'b0;
            dcache_prefetch_valid <= 1'b0;
        end

        if (storeq_drain_complete) begin
            storeq_active <= 1'b0;
            if (storeq_count == 2'd2) begin
                storeq_addr0 <= storeq_addr1;
                storeq_data0 <= storeq_data1;
                storeq_size0 <= storeq_size1;
                if (mem_store_enqueue_complete) begin
                    storeq_count <= 2'd2;
                    storeq_addr1 <= ex_mem_mem_addr;
                    storeq_data1 <= mem_store_data;
                    storeq_size1 <= ex_mem_mem_size;
                end else begin
                    storeq_count <= 2'd1;
                end
            end else if (mem_store_enqueue_complete) begin
                storeq_count <= 2'd1;
                storeq_addr0 <= ex_mem_mem_addr;
                storeq_data0 <= mem_store_data;
                storeq_size0 <= ex_mem_mem_size;
            end else begin
                storeq_count <= 2'd0;
            end
        end else begin
            if (mem_store_enqueue_complete) begin
                if (storeq_count == 2'd0) begin
                    storeq_count <= 2'd1;
                    storeq_addr0 <= ex_mem_mem_addr;
                    storeq_data0 <= mem_store_data;
                    storeq_size0 <= ex_mem_mem_size;
                end else if (storeq_count == 2'd1) begin
                    storeq_count <= 2'd2;
                    storeq_addr1 <= ex_mem_mem_addr;
                    storeq_data1 <= mem_store_data;
                    storeq_size1 <= ex_mem_mem_size;
                end
            end
            if (can_issue_storeq) begin
                storeq_active <= 1'b1;
            end
        end
    end
end

endmodule

`default_nettype wire
