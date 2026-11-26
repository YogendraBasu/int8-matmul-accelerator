module matmul_axil #(
  parameter int DATA_W  = 8,
  parameter int ACC_W   = 32,
  parameter int MAX_N   = 8,
  parameter int NUM_MAC = 4
)(
  input  logic        s_axi_aclk,
  input  logic        s_axi_aresetn,

  input  logic [11:0] s_axi_awaddr,
  input  logic        s_axi_awvalid,
  output logic        s_axi_awready,
  input  logic [31:0] s_axi_wdata,
  input  logic [3:0]  s_axi_wstrb,
  input  logic        s_axi_wvalid,
  output logic        s_axi_wready,
  output logic [1:0]  s_axi_bresp,
  output logic        s_axi_bvalid,
  input  logic        s_axi_bready,
  input  logic [11:0] s_axi_araddr,
  input  logic        s_axi_arvalid,
  output logic        s_axi_arready,
  output logic [31:0] s_axi_rdata,
  output logic [1:0]  s_axi_rresp,
  output logic        s_axi_rvalid,
  input  logic        s_axi_rready
);

  localparam int DEPTH = MAX_N*MAX_N;
  localparam int IDX_W = (DEPTH > 1) ? $clog2(DEPTH) : 1;

  localparam logic [1:0] RGN_REG = 2'b00, RGN_A = 2'b01, RGN_B = 2'b10, RGN_C = 2'b11;
  localparam logic [8:0] DEPTH9 = 9'(DEPTH);
  localparam logic [1:0] RESP_OKAY = 2'b00, RESP_SLVERR = 2'b10;

  logic clk, rst_n;
  assign clk   = s_axi_aclk;
  assign rst_n = s_axi_aresetn;

  logic [7:0]  n_reg;
  logic        done_sticky, err_sticky;

  logic                     core_busy, core_done;
  logic [31:0]              core_cycles;
  logic                     core_start, core_soft_rst;
  logic                     h_we_a, h_we_b;
  logic signed [DATA_W-1:0] h_rdata_a, h_rdata_b;
  logic signed [ACC_W-1:0]  h_rdata_c;

  logic wr_fire;
  assign wr_fire       = s_axi_awvalid && s_axi_wvalid && !s_axi_bvalid;
  assign s_axi_awready = wr_fire;
  assign s_axi_wready  = wr_fire;

  logic [1:0] wr_rgn;
  logic [7:0] wr_widx;
  assign wr_rgn  = s_axi_awaddr[11:10];
  assign wr_widx = s_axi_awaddr[9:2];

  logic wr_err, set_err, clr_done, clr_err, cfg_we, start_req, n_valid;

  assign n_valid = (n_reg >= 8'd1) && (n_reg <= 8'(MAX_N));

  always_comb begin
    wr_err        = 1'b0;
    set_err       = 1'b0;
    clr_done      = 1'b0;
    clr_err       = 1'b0;
    cfg_we        = 1'b0;
    start_req     = 1'b0;
    core_soft_rst = 1'b0;
    h_we_a        = 1'b0;
    h_we_b        = 1'b0;

    if (wr_fire) begin
      case (wr_rgn)
        RGN_REG: begin
          case (wr_widx)
            8'd0: begin
              if (s_axi_wdata[1]) core_soft_rst = 1'b1;
              else if (s_axi_wdata[0]) begin
                start_req = 1'b1;
                if (core_busy || !n_valid) begin wr_err = 1'b1; set_err = 1'b1; end
              end
            end
            8'd1: begin
              clr_done = s_axi_wdata[1];
              clr_err  = s_axi_wdata[2];
            end
            8'd2: begin
              if (core_busy) begin wr_err = 1'b1; set_err = 1'b1; end
              else cfg_we = 1'b1;
            end
            default: wr_err = 1'b1;
          endcase
        end

        RGN_A, RGN_B: begin
          if ({1'b0, wr_widx} >= DEPTH9) wr_err = 1'b1;
          else if (core_busy) begin wr_err = 1'b1; set_err = 1'b1; end
          else if (wr_rgn == RGN_A) h_we_a = 1'b1;
          else                      h_we_b = 1'b1;
        end

        default: wr_err = 1'b1;
      endcase
    end
  end

  assign core_start = start_req && !wr_err;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_axi_bvalid <= 1'b0;
      s_axi_bresp  <= RESP_OKAY;
      n_reg        <= 8'(MAX_N);
      done_sticky  <= 1'b0;
      err_sticky   <= 1'b0;
    end else begin
      if (wr_fire) begin
        s_axi_bvalid <= 1'b1;
        s_axi_bresp  <= wr_err ? RESP_SLVERR : RESP_OKAY;
      end else if (s_axi_bvalid && s_axi_bready) begin
        s_axi_bvalid <= 1'b0;
      end

      if (cfg_we) n_reg <= s_axi_wdata[7:0];

      if (clr_done || core_start || core_soft_rst) done_sticky <= 1'b0;
      if (clr_err  || core_soft_rst)               err_sticky  <= 1'b0;
      if (core_done) done_sticky <= 1'b1;
      if (set_err)   err_sticky  <= 1'b1;
    end
  end

  matmul_core #(
    .DATA_W(DATA_W), .ACC_W(ACC_W), .MAX_N(MAX_N), .NUM_MAC(NUM_MAC)
  ) u_core (
    .clk(clk), .rst_n(rst_n),
    .soft_rst(core_soft_rst), .start(core_start), .n(n_reg),
    .busy(core_busy), .done_pulse(core_done), .cycle_cnt(core_cycles),
    .h_we_a(h_we_a), .h_we_b(h_we_b),
    .h_waddr(wr_widx[IDX_W-1:0]), .h_wdata(s_axi_wdata[DATA_W-1:0]),
    .h_raddr(s_axi_araddr[2 +: IDX_W]),
    .h_rdata_a(h_rdata_a), .h_rdata_b(h_rdata_b), .h_rdata_c(h_rdata_c)
  );

  logic        rd_fire, rd_err;
  logic [31:0] rd_mux;
  logic [1:0]  rd_rgn;
  logic [7:0]  rd_widx;
  logic signed [31:0] a_ext, b_ext, c_ext;

  assign rd_rgn  = s_axi_araddr[11:10];
  assign rd_widx = s_axi_araddr[9:2];
  assign a_ext   = h_rdata_a;
  assign b_ext   = h_rdata_b;
  assign c_ext   = h_rdata_c;

  assign rd_fire       = s_axi_arvalid && !s_axi_rvalid;
  assign s_axi_arready = rd_fire;

  always_comb begin
    rd_mux = 32'd0;
    rd_err = 1'b0;
    case (rd_rgn)
      RGN_REG: begin
        case (rd_widx)
          8'd0:    rd_mux = 32'd0;
          8'd1:    rd_mux = {29'd0, err_sticky, done_sticky, core_busy};
          8'd2:    rd_mux = {24'd0, n_reg};
          8'd3:    rd_mux = core_cycles;
          default: rd_err = 1'b1;
        endcase
      end
      RGN_A: if ({1'b0, rd_widx} < DEPTH9) rd_mux = a_ext; else rd_err = 1'b1;
      RGN_B: if ({1'b0, rd_widx} < DEPTH9) rd_mux = b_ext; else rd_err = 1'b1;
      RGN_C: if ({1'b0, rd_widx} < DEPTH9) rd_mux = c_ext; else rd_err = 1'b1;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_axi_rvalid <= 1'b0;
      s_axi_rdata  <= 32'd0;
      s_axi_rresp  <= RESP_OKAY;
    end else begin
      if (rd_fire) begin
        s_axi_rvalid <= 1'b1;
        s_axi_rdata  <= rd_mux;
        s_axi_rresp  <= rd_err ? RESP_SLVERR : RESP_OKAY;
      end else if (s_axi_rvalid && s_axi_rready) begin
        s_axi_rvalid <= 1'b0;
      end
    end
  end

`ifndef SYNTHESIS
`ifndef NO_SVA
  assert property (@(posedge clk) disable iff (!rst_n) core_start |-> !core_busy)
    else $error("SVA: start accepted while busy");

  assert property (@(posedge clk) disable iff (!rst_n) core_start |=> core_busy)
    else $error("SVA: busy did not rise after start");

  assert property (@(posedge clk) disable iff (!rst_n) core_done |-> core_busy)
    else $error("SVA: done without busy");

  assert property (@(posedge clk) disable iff (!rst_n)
                   s_axi_bvalid && !s_axi_bready |=> s_axi_bvalid)
    else $error("SVA: BVALID dropped before BREADY");
  assert property (@(posedge clk) disable iff (!rst_n)
                   s_axi_rvalid && !s_axi_rready |=> s_axi_rvalid)
    else $error("SVA: RVALID dropped before RREADY");

  assert property (@(posedge clk) disable iff (!rst_n)
                   !$isunknown({s_axi_awready, s_axi_wready, s_axi_arready,
                                s_axi_bvalid, s_axi_rvalid}))
    else $error("SVA: X on AXI handshake outputs");

  assert property (@(posedge clk) disable iff (!rst_n) core_busy |-> !(h_we_a || h_we_b))
    else $error("SVA: operand write while busy");

  assert property (@(posedge clk) disable iff (!rst_n) core_soft_rst |=> !core_busy)
    else $error("SVA: core still busy after soft reset");

  assert property (@(posedge clk) disable iff (!rst_n) core_done |=> !core_busy)
    else $error("SVA: core did not return to idle after done");

  assert property (@(posedge clk) disable iff (!rst_n)
                   s_axi_awvalid && s_axi_wvalid && !s_axi_bvalid |-> s_axi_awready && s_axi_wready)
    else $error("SVA: write not accepted with AW and W valid");

  assert property (@(posedge clk) disable iff (!rst_n)
                   s_axi_arvalid && !s_axi_rvalid |-> s_axi_arready)
    else $error("SVA: read address not accepted while idle");

  assert property (@(posedge clk) disable iff (!rst_n)
                   s_axi_bvalid |-> (s_axi_bresp == RESP_OKAY || s_axi_bresp == RESP_SLVERR))
    else $error("SVA: illegal BRESP");
`endif
`endif

endmodule
