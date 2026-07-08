`default_nettype none

module mips_core #(
    parameter RESET_PC = 32'h8000_0000
)(
    input  wire        clk,
    input  wire        reset,

    output reg         bus_valid,
    output reg         bus_write,
    output reg  [1:0]  bus_size,
    output reg  [31:0] bus_addr,
    output reg  [31:0] bus_wdata,
    input  wire [31:0] bus_rdata,
    input  wire        bus_ready,

    output reg  [31:0] debug_wb_pc,
    output reg  [3:0]  debug_wb_rf_wen,
    output reg  [4:0]  debug_wb_rf_wnum,
    output reg  [31:0] debug_wb_rf_wdata,
    output wire [31:0] debug_pc
);

localparam SIZE_BYTE = 2'b00;
localparam SIZE_WORD = 2'b10;

localparam BUS_NONE = 2'd0;
localparam BUS_IF   = 2'd1;
localparam BUS_MEM  = 2'd2;

reg [31:0] gpr [0:31];

reg [1:0]  bus_owner;
reg [31:0] if_req_pc;
reg [31:0] fetch_pc;
reg        fetch_buf_valid;
reg [31:0] fetch_buf_pc;
reg [31:0] fetch_buf_inst;

reg        redirect_pending;
reg [31:0] redirect_target;
reg [31:0] redirect_delay_pc;

reg        if_id_valid;
reg [31:0] if_id_pc;
reg [31:0] if_id_inst;

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
wire signed [31:0] ex_rs_signed_base = ex_rs_value;
wire signed [31:0] ex_rt_signed_base = ex_rt_value;

reg [31:0] ex_rs_value;
reg [31:0] ex_rt_value;
reg [31:0] ex_alu_result;
reg [31:0] ex_store_data;
reg [31:0] mem_store_data;

wire [7:0] mem_load_byte =
    (ex_mem_mem_addr[1:0] == 2'b00) ? bus_rdata[7:0] :
    (ex_mem_mem_addr[1:0] == 2'b01) ? bus_rdata[15:8] :
    (ex_mem_mem_addr[1:0] == 2'b10) ? bus_rdata[23:16] :
                                      bus_rdata[31:24];
wire [31:0] mem_load_value =
    (ex_mem_mem_size == SIZE_BYTE) ? {{24{ex_mem_mem_signed && mem_load_byte[7]}}, mem_load_byte} : bus_rdata;

wire mem_stage_needs_bus = ex_mem_valid && (ex_mem_mem_read || ex_mem_mem_write);
wire mem_completes = mem_stage_needs_bus && mem_active && bus_owner == BUS_MEM && bus_ready;
wire mem_stall = mem_stage_needs_bus && !mem_completes;

wire load_use_hazard =
    if_id_valid && id_ex_valid && id_ex_mem_read && id_ex_wb_addr != 5'b0 &&
    ((id_uses_rs && id_rs == id_ex_wb_addr) || (id_uses_rt && id_rt == id_ex_wb_addr));

wire front_stall = mem_stall || load_use_hazard;
wire id_advance = if_id_valid && !front_stall;
wire if_id_can_accept = !front_stall && (!if_id_valid || id_advance);
wire control_taken_now = if_id_valid && !front_stall && id_is_control && id_branch_taken;
wire [31:0] control_delay_pc_now = if_id_pc + 32'd4;
wire fetch_buf_take = fetch_buf_valid && if_id_can_accept &&
                      (!redirect_pending || fetch_buf_pc == redirect_delay_pc) &&
                      (!control_taken_now || fetch_buf_pc == control_delay_pc_now);
wire can_issue_fetch = !bus_valid && !fetch_buf_valid && !mem_stage_needs_bus &&
                       if_id_can_accept && (!redirect_pending || fetch_pc == redirect_delay_pc) &&
                       (!control_taken_now || fetch_pc == control_delay_pc_now);

assign debug_pc = fetch_pc;

always @(*) begin
    id_rs_value = id_rs_gpr;
    id_rt_value = id_rt_gpr;

    if (id_ex_valid && id_ex_wb_en && !id_ex_mem_read && id_ex_wb_addr != 5'b0 && id_ex_wb_addr == id_rs) begin
        id_rs_value = ex_alu_result;
    end else if (ex_mem_valid && ex_mem_wb_en && !ex_mem_mem_read && ex_mem_wb_addr != 5'b0 && ex_mem_wb_addr == id_rs) begin
        id_rs_value = ex_mem_wb_data;
    end else if (mem_wb_valid && mem_wb_wb_en && mem_wb_wb_addr != 5'b0 && mem_wb_wb_addr == id_rs) begin
        id_rs_value = mem_wb_wb_data;
    end

    if (id_ex_valid && id_ex_wb_en && !id_ex_mem_read && id_ex_wb_addr != 5'b0 && id_ex_wb_addr == id_rt) begin
        id_rt_value = ex_alu_result;
    end else if (ex_mem_valid && ex_mem_wb_en && !ex_mem_mem_read && ex_mem_wb_addr != 5'b0 && ex_mem_wb_addr == id_rt) begin
        id_rt_value = ex_mem_wb_data;
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
    end else if (mem_wb_valid && mem_wb_wb_en && mem_wb_wb_addr != 5'b0 && mem_wb_wb_addr == id_ex_rs) begin
        ex_rs_value = mem_wb_wb_data;
    end

    if (ex_mem_valid && ex_mem_wb_en && !ex_mem_mem_read && ex_mem_wb_addr != 5'b0 && ex_mem_wb_addr == id_ex_rt) begin
        ex_rt_value = ex_mem_wb_data;
    end else if (mem_wb_valid && mem_wb_wb_en && mem_wb_wb_addr != 5'b0 && mem_wb_wb_addr == id_ex_rt) begin
        ex_rt_value = mem_wb_wb_data;
    end
end

always @(*) begin
    mem_store_data = ex_mem_store_data;
    if (ex_mem_mem_write && ex_mem_store_rt != 5'b0) begin
        mem_store_data = gpr[ex_mem_store_rt];
        if (mem_wb_valid && mem_wb_wb_en && mem_wb_wb_addr == ex_mem_store_rt) begin
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
        6'b011100: ex_alu_result = ex_rs_signed_base * ex_rt_signed_base;
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
        redirect_pending <= 1'b0;
        redirect_target <= 32'b0;
        redirect_delay_pc <= 32'b0;
        if_id_valid <= 1'b0;
        if_id_pc <= 32'b0;
        if_id_inst <= 32'b0;
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
        mem_active <= 1'b0;
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

        if (mem_wb_valid && mem_wb_wb_en && mem_wb_wb_addr != 5'b0) begin
            gpr[mem_wb_wb_addr] <= mem_wb_wb_data;
            debug_wb_pc <= mem_wb_pc;
            debug_wb_rf_wen <= 4'hf;
            debug_wb_rf_wnum <= mem_wb_wb_addr;
            debug_wb_rf_wdata <= mem_wb_wb_data;
        end
        gpr[0] <= 32'b0;

        if (bus_valid && bus_ready) begin
            if (bus_owner == BUS_IF) begin
                if (!redirect_pending || if_req_pc == redirect_delay_pc) begin
                    fetch_buf_valid <= 1'b1;
                    fetch_buf_pc <= if_req_pc;
                    fetch_buf_inst <= bus_rdata;
                end
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
            ex_mem_valid <= 1'b0;
        end else if (!mem_stall) begin
            mem_wb_valid <= ex_mem_valid && !(ex_mem_mem_read || ex_mem_mem_write);
            mem_wb_pc <= ex_mem_pc;
            mem_wb_wb_en <= ex_mem_wb_en && !(ex_mem_mem_read || ex_mem_mem_write);
            mem_wb_wb_addr <= ex_mem_wb_addr;
            mem_wb_wb_data <= ex_mem_wb_data;

            ex_mem_valid <= id_ex_valid;
            ex_mem_pc <= id_ex_pc;
            ex_mem_wb_en <= id_ex_wb_en;
            ex_mem_wb_addr <= id_ex_wb_addr;
            ex_mem_wb_data <= ex_alu_result;
            ex_mem_mem_read <= id_ex_mem_read;
            ex_mem_mem_write <= id_ex_mem_write;
            ex_mem_mem_size <= id_ex_mem_size;
            ex_mem_mem_signed <= id_ex_mem_signed;
            ex_mem_mem_addr <= ex_alu_result;
            ex_mem_store_data <= ex_store_data;
            ex_mem_store_rt <= id_ex_rt;

            if (load_use_hazard) begin
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

                if (if_id_valid && id_is_control && id_branch_taken) begin
                    redirect_pending <= 1'b1;
                    redirect_target <= id_branch_target;
                    redirect_delay_pc <= if_id_pc + 32'd4;
                    fetch_pc <= if_id_pc + 32'd4;
                    if ((fetch_buf_valid && fetch_buf_pc != if_id_pc + 32'd4) ||
                        (bus_valid && bus_ready && bus_owner == BUS_IF && if_req_pc != if_id_pc + 32'd4)) begin
                        fetch_buf_valid <= 1'b0;
                    end
                end

                if (fetch_buf_take) begin
                    if_id_valid <= 1'b1;
                    if_id_pc <= fetch_buf_pc;
                    if_id_inst <= fetch_buf_inst;
                    if (redirect_pending) begin
                        fetch_buf_valid <= 1'b0;
                        fetch_pc <= redirect_target;
                        redirect_pending <= 1'b0;
                    end else if (!(bus_valid && bus_ready && bus_owner == BUS_IF)) begin
                        fetch_buf_valid <= 1'b0;
                    end
                end else if (if_id_valid) begin
                    if_id_valid <= 1'b0;
                end
            end
        end else begin
            mem_wb_valid <= 1'b0;
        end

        if (!bus_valid && mem_stage_needs_bus && !mem_active) begin
            bus_valid <= 1'b1;
            bus_owner <= BUS_MEM;
            bus_write <= ex_mem_mem_write;
            bus_size <= ex_mem_mem_size;
            bus_addr <= ex_mem_mem_addr;
            bus_wdata <= mem_store_data;
            mem_active <= 1'b1;
        end else if (can_issue_fetch) begin
            bus_valid <= 1'b1;
            bus_owner <= BUS_IF;
            bus_write <= 1'b0;
            bus_size <= SIZE_WORD;
            bus_addr <= fetch_pc;
            bus_wdata <= 32'b0;
            if_req_pc <= fetch_pc;
            fetch_pc <= fetch_pc + 32'd4;
        end
    end
end

endmodule

`default_nettype wire
