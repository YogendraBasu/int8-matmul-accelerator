`timescale 1ns/1ps
module tb_matmul_axil;

  parameter int MAX_N   = 8;
  parameter int NUM_MAC = 4;
  localparam int DEPTH = MAX_N*MAX_N;

  localparam logic [11:0] ADDR_CTRL   = 12'h000;
  localparam logic [11:0] ADDR_STATUS = 12'h004;
  localparam logic [11:0] ADDR_CONFIG = 12'h008;
  localparam logic [11:0] ADDR_CYCLES = 12'h00C;
  localparam logic [11:0] BASE_A      = 12'h400;
  localparam logic [11:0] BASE_B      = 12'h800;
  localparam logic [11:0] BASE_C      = 12'hC00;

  logic        clk = 1'b0;
  logic        rst_n;
  logic [11:0] awaddr, araddr;
  logic        awvalid, wvalid, bready, arvalid, rready;
  logic [31:0] wdata;
  logic [3:0]  wstrb;
  logic        awready, wready, bvalid, arready, rvalid;
  logic [1:0]  bresp, rresp;
  logic [31:0] rdata;

  matmul_axil #(.MAX_N(MAX_N), .NUM_MAC(NUM_MAC)) dut (
    .s_axi_aclk(clk), .s_axi_aresetn(rst_n),
    .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
    .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
    .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
    .s_axi_araddr(araddr), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
    .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready)
  );

  always #5 clk = ~clk;

`ifdef DUMP
  initial begin $dumpfile("tb.vcd"); $dumpvars(0, tb_matmul_axil); end
`endif

  initial begin
    #50_000_000;
    $display("[FATAL] simulation watchdog expired");
    $finish;
  end

  int errors = 0;
  int checks = 0;

  task automatic check(input bit cond, input string msg);
    begin
      checks++;
      if (!cond) begin
        errors++;
        $display("[ERROR] t=%0t : %s", $time, msg);
      end
    end
  endtask

  task automatic axi_write(input logic [11:0] addr, input logic [31:0] data,
                           output logic [1:0] resp);
    begin
      @(posedge clk); #1;
      awaddr = addr; awvalid = 1'b1; wdata = data; wstrb = 4'hF; wvalid = 1'b1;
      @(posedge clk);
      while (!(awready && wready)) @(posedge clk);
      #1; awvalid = 1'b0; wvalid = 1'b0;
      repeat ($urandom_range(0, 3)) @(posedge clk);
      #1; bready = 1'b1;
      @(posedge clk);
      while (!bvalid) @(posedge clk);
      resp = bresp;
      #1; bready = 1'b0;
    end
  endtask

  task automatic axi_read(input logic [11:0] addr, output logic [31:0] data,
                          output logic [1:0] resp);
    begin
      @(posedge clk); #1;
      araddr = addr; arvalid = 1'b1;
      @(posedge clk);
      while (!arready) @(posedge clk);
      #1; arvalid = 1'b0;
      repeat ($urandom_range(0, 3)) @(posedge clk);
      #1; rready = 1'b1;
      @(posedge clk);
      while (!rvalid) @(posedge clk);
      data = rdata; resp = rresp;
      #1; rready = 1'b0;
    end
  endtask

  task automatic wr_ok(input logic [11:0] addr, input logic [31:0] data);
    logic [1:0] r;
    begin axi_write(addr, data, r); check(r == 2'b00, $sformatf("unexpected SLVERR on write 0x%0h", addr)); end
  endtask

  task automatic wr_err(input logic [11:0] addr, input logic [31:0] data, input string what);
    logic [1:0] r;
    begin axi_write(addr, data, r); check(r == 2'b10, {"expected SLVERR: ", what}); end
  endtask

  task automatic rd_ok(input logic [11:0] addr, output logic [31:0] data);
    logic [1:0] r;
    begin axi_read(addr, data, r); check(r == 2'b00, $sformatf("unexpected SLVERR on read 0x%0h", addr)); end
  endtask

  int a_m [0:255];
  int b_m [0:255];
  int c_exp [0:255];

  task automatic golden(input int n);
    int acc;
    begin
      for (int i = 0; i < n; i++)
        for (int j = 0; j < n; j++) begin
          acc = 0;
          for (int k = 0; k < n; k++) acc += a_m[i*n+k] * b_m[k*n+j];
          c_exp[i*n+j] = acc;
        end
    end
  endtask

  function automatic int expected_cycles(input int n);
    return n * ((n + NUM_MAC - 1) / NUM_MAC) * (n + 1);
  endfunction

  typedef enum int {P_RANDOM, P_MIN, P_MIN_MAX, P_ZERO, P_IDENT, P_MAX} pattern_t;

  task automatic fill(input int n, input pattern_t p);
    begin
      for (int i = 0; i < n; i++)
        for (int j = 0; j < n; j++) begin
          case (p)
            P_RANDOM: begin a_m[i*n+j] = int'($urandom_range(0,255)) - 128;
                            b_m[i*n+j] = int'($urandom_range(0,255)) - 128; end
            P_MIN:     begin a_m[i*n+j] = -128; b_m[i*n+j] = -128; end
            P_MIN_MAX: begin a_m[i*n+j] = -128; b_m[i*n+j] =  127; end
            P_MAX:     begin a_m[i*n+j] =  127; b_m[i*n+j] =  127; end
            P_ZERO:    begin a_m[i*n+j] = 0;    b_m[i*n+j] = 0;    end
            P_IDENT:   begin a_m[i*n+j] = (i == j) ? 1 : 0;
                             b_m[i*n+j] = int'($urandom_range(0,255)) - 128; end
          endcase
        end
    end
  endtask

  int cov_n;
  pattern_t cov_p;
`ifdef USE_COVERGROUP
  covergroup cg_run;
    cp_n : coverpoint cov_n { bins sizes[] = {[1:MAX_N]}; }
    cp_p : coverpoint cov_p;
    x_np : cross cp_n, cp_p;
  endgroup
  cg_run cg = new();
`endif

  task automatic wait_done(input int max_polls);
    logic [31:0] st;
    int polls;
    begin
      st = 0; polls = 0;
      while (!st[1] && polls < max_polls) begin rd_ok(ADDR_STATUS, st); polls++; end
      check(st[1] == 1'b1, "timeout waiting for DONE");
    end
  endtask

  task automatic run_test(input int n, input pattern_t p);
    logic [31:0] v;
    int idx;
    begin
      fill(n, p);
      golden(n);

      wr_ok(ADDR_CONFIG, n);
      for (int i = 0; i < n*n; i++) begin
        wr_ok(BASE_A + 4*i, a_m[i]);
        wr_ok(BASE_B + 4*i, b_m[i]);
      end

      wr_ok(ADDR_CTRL, 32'h1);
      rd_ok(ADDR_STATUS, v);
      check(v[0] == 1'b1 || v[1] == 1'b1, "STATUS shows neither BUSY nor DONE right after START");
      wait_done(5000);

      rd_ok(ADDR_STATUS, v);
      check(v[1] == 1'b1 && v[0] == 1'b0 && v[2] == 1'b0, $sformatf("STATUS after run = 0x%0h", v));

      rd_ok(ADDR_CYCLES, v);
      check(int'(v) == expected_cycles(n),
            $sformatf("cycle count n=%0d : got %0d expected %0d", n, v, expected_cycles(n)));

      for (int i = 0; i < n*n; i++) begin
        rd_ok(BASE_C + 4*i, v);
        check($signed(v) == c_exp[i],
              $sformatf("C[%0d] n=%0d pat=%s : got %0d expected %0d", i, n, p.name(), $signed(v), c_exp[i]));
      end

      wr_ok(ADDR_STATUS, 32'h2);
      rd_ok(ADDR_STATUS, v);
      check(v[1] == 1'b0, "DONE did not clear on W1C");

      cov_n = n; cov_p = p;
`ifdef USE_COVERGROUP
      cg.sample();
`endif
    end
  endtask

  logic [31:0] v;
  logic [1:0]  r;

  initial begin
    rst_n = 1'b0;
    awaddr = '0; araddr = '0; awvalid = 0; wvalid = 0; bready = 0;
    arvalid = 0; rready = 0; wdata = '0; wstrb = 4'hF;
    repeat (5) @(posedge clk);
    #1 rst_n = 1'b1;
    repeat (3) @(posedge clk);

    rd_ok(ADDR_STATUS, v);  check(v == 32'h0,          "STATUS reset value");
    rd_ok(ADDR_CONFIG, v);  check(v == MAX_N,          "CONFIG reset value");

    $display("[TB] directed tests");
    run_test(MAX_N, P_RANDOM);
    run_test(MAX_N, P_MIN);
    run_test(MAX_N, P_MIN_MAX);
    run_test(MAX_N, P_MAX);
    run_test(MAX_N, P_ZERO);
    run_test(MAX_N, P_IDENT);
    run_test(1, P_RANDOM);
    run_test(2, P_RANDOM);
    run_test(4, P_RANDOM);
    run_test(5, P_RANDOM);
    run_test(7, P_RANDOM);
    run_test(3, P_MIN);

    run_test(MAX_N, P_RANDOM);
    wr_ok(ADDR_CTRL, 32'h1); wait_done(5000);
    rd_ok(ADDR_CYCLES, v);
    check(int'(v) == expected_cycles(MAX_N), "cycle count on re-run");
    for (int i = 0; i < MAX_N*MAX_N; i++) begin
      rd_ok(BASE_C + 4*i, v);
      check($signed(v) == c_exp[i], "re-run result mismatch");
    end
    wr_ok(ADDR_STATUS, 32'h2);

    wr_ok(BASE_A, -5);   rd_ok(BASE_A, v);  check($signed(v) == -5, "A read-back sign extension");
    wr_ok(BASE_B, 127);  rd_ok(BASE_B, v);  check($signed(v) == 127, "B read-back");

    $display("[TB] error-path tests");
    fill(MAX_N, P_RANDOM); golden(MAX_N);
    wr_ok(ADDR_CONFIG, MAX_N);
    for (int i = 0; i < MAX_N*MAX_N; i++) begin wr_ok(BASE_A + 4*i, a_m[i]); wr_ok(BASE_B + 4*i, b_m[i]); end

    wr_ok(ADDR_CTRL, 32'h1);
    wr_err(ADDR_CTRL, 32'h1, "START while BUSY");
    wr_err(BASE_A,   32'h55, "write A while BUSY");
    wr_err(ADDR_CONFIG, 32'h3, "write CONFIG while BUSY");
    wait_done(5000);
    rd_ok(ADDR_STATUS, v);   check(v[2] == 1'b1, "ERROR flag not set after illegal accesses");
    for (int i = 0; i < MAX_N*MAX_N; i++) begin
      rd_ok(BASE_C + 4*i, v);
      check($signed(v) == c_exp[i], "result corrupted by illegal accesses");
    end
    wr_ok(ADDR_STATUS, 32'h6);
    rd_ok(ADDR_STATUS, v);   check(v == 32'h0, "STATUS not clean after W1C");

    wr_ok(ADDR_CONFIG, 0);          wr_err(ADDR_CTRL, 32'h1, "START with N=0");
    rd_ok(ADDR_STATUS, v);          check(v[0] == 1'b0 && v[2] == 1'b1, "core must stay idle on N=0");
    wr_ok(ADDR_STATUS, 32'h4);
    wr_ok(ADDR_CONFIG, MAX_N+1);    wr_err(ADDR_CTRL, 32'h1, "START with N>MAX_N");
    wr_ok(ADDR_STATUS, 32'h4);
    wr_ok(ADDR_CONFIG, MAX_N);

    wr_err(BASE_A + 4*DEPTH, 32'h1, "A index out of range");
    wr_err(BASE_C,           32'h1, "write to read-only C window");
    wr_err(ADDR_CYCLES,      32'h1, "write to read-only CYCLES");
    wr_err(12'h010,          32'h1, "unmapped register");
    axi_read(12'h010, v, r);        check(r == 2'b10, "expected SLVERR on unmapped read");
    axi_read(BASE_B + 4*DEPTH, v, r); check(r == 2'b10, "expected SLVERR on out-of-range read");

    wr_ok(ADDR_CTRL, 32'h1);
    repeat (20) @(posedge clk);
    wr_ok(ADDR_CTRL, 32'h2);
    rd_ok(ADDR_STATUS, v);   check(v == 32'h0, "STATUS after soft reset");
    run_test(6, P_RANDOM);

    $display("[TB] random regression");
    for (int t = 0; t < 150; t++)
      run_test($urandom_range(1, MAX_N), P_RANDOM);

    $display("--------------------------------------------------");
    $display("[TB] cycles for N=%0d with NUM_MAC=%0d : %0d  (1-MAC baseline would be %0d)",
             MAX_N, NUM_MAC, expected_cycles(MAX_N), MAX_N*MAX_N*(MAX_N+1));
    $display("[TB] checks=%0d  errors=%0d", checks, errors);
    if (errors == 0) $display("[TB] *** TEST PASSED ***");
    else begin
      $display("[TB] *** TEST FAILED ***");
      $fatal(1, "testbench reported %0d errors", errors);
    end
    $finish;
  end

endmodule
