module matmul_core #(
  parameter int DATA_W  = 8,
  parameter int ACC_W   = 32,
  parameter int MAX_N   = 8,
  parameter int NUM_MAC = 4,
  parameter int DEPTH   = MAX_N*MAX_N,
  parameter int IDX_W   = (DEPTH > 1) ? $clog2(DEPTH) : 1,
  parameter int DIM_W   = $clog2(MAX_N+1)
)(
  input  logic                      clk,
  input  logic                      rst_n,
  input  logic                      soft_rst,
  input  logic                      start,
  input  logic [7:0]                n,

  output logic                      busy,
  output logic                      done_pulse,
  output logic [31:0]               cycle_cnt,

  input  logic                      h_we_a,
  input  logic                      h_we_b,
  input  logic [IDX_W-1:0]          h_waddr,
  input  logic signed [DATA_W-1:0]  h_wdata,
  input  logic [IDX_W-1:0]          h_raddr,
  output logic signed [DATA_W-1:0]  h_rdata_a,
  output logic signed [DATA_W-1:0]  h_rdata_b,
  output logic signed [ACC_W-1:0]   h_rdata_c
);

  logic signed [DATA_W-1:0] mem_a [0:DEPTH-1];
  logic signed [DATA_W-1:0] mem_b [0:DEPTH-1];
  logic signed [ACC_W-1:0]  mem_c [0:DEPTH-1];

  initial begin : init_mem
    for (int x = 0; x < DEPTH; x++) begin
      mem_a[x] = '0; mem_b[x] = '0; mem_c[x] = '0;
    end
  end

  always @(posedge clk) begin
    if (h_we_a) mem_a[h_waddr] <= h_wdata;
    if (h_we_b) mem_b[h_waddr] <= h_wdata;
  end

  assign h_rdata_a = mem_a[h_raddr];
  assign h_rdata_b = mem_b[h_raddr];
  assign h_rdata_c = mem_c[h_raddr];

  typedef enum logic [1:0] {S_IDLE, S_COMPUTE, S_WRITE, S_DONE} state_t;
  state_t state;

  logic [DIM_W-1:0] i, j, k;
  logic [7:0]       n_r;
  logic [8:0]       j_next;
  assign j_next = j + NUM_MAC;

  assign busy       = (state != S_IDLE);
  assign done_pulse = (state == S_DONE);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE; i <= '0; j <= '0; k <= '0; n_r <= '0; cycle_cnt <= '0;
    end else if (soft_rst) begin
      state <= S_IDLE; i <= '0; j <= '0; k <= '0;
    end else begin
      case (state)
        S_IDLE: if (start) begin
          n_r <= n; i <= '0; j <= '0; k <= '0;
          cycle_cnt <= '0;
          state <= S_COMPUTE;
        end

        S_COMPUTE: begin
          cycle_cnt <= cycle_cnt + 1;
          if (k == n_r - 1) begin k <= '0; state <= S_WRITE; end
          else                   k <= k + 1;
        end

        S_WRITE: begin
          cycle_cnt <= cycle_cnt + 1;
          if (j_next >= n_r) begin
            j <= '0;
            if (i == n_r - 1) state <= S_DONE;
            else begin i <= i + 1; state <= S_COMPUTE; end
          end else begin
            j <= j_next[DIM_W-1:0];
            state <= S_COMPUTE;
          end
        end

        S_DONE: state <= S_IDLE;
        default: state <= S_IDLE;
      endcase
    end
  end

  logic [NUM_MAC-1:0]       lane_valid;
  logic [IDX_W-1:0]         a_idx;
  logic [IDX_W-1:0]         b_idx [NUM_MAC];
  logic [IDX_W-1:0]         c_idx [NUM_MAC];
  logic signed [DATA_W-1:0] a_val;
  logic signed [DATA_W-1:0] b_val [NUM_MAC];
  logic signed [ACC_W-1:0]  acc   [NUM_MAC];

  assign a_idx = i * n_r + k;

  always_comb begin
    for (int m = 0; m < NUM_MAC; m++) begin
      lane_valid[m] = ((j + m) < n_r);
      b_idx[m]      = k * n_r + j + m;
      c_idx[m]      = i * n_r + j + m;
      b_val[m]      = lane_valid[m] ? mem_b[b_idx[m]] : '0;
    end
  end
  assign a_val = mem_a[a_idx];

  logic mac_clr;
  assign mac_clr = (state != S_COMPUTE);

  genvar g;
  generate
    for (g = 0; g < NUM_MAC; g++) begin : g_mac
      mac_unit #(.DATA_W(DATA_W), .ACC_W(ACC_W)) u_mac (
        .clk(clk), .rst_n(rst_n), .clr(mac_clr),
        .a(a_val), .b(b_val[g]), .acc(acc[g])
      );
    end
  endgenerate

  always @(posedge clk) begin
    if (state == S_WRITE)
      for (int m = 0; m < NUM_MAC; m++)
        if (lane_valid[m]) mem_c[c_idx[m]] <= acc[m];
  end

endmodule
