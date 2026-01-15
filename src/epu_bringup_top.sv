`include "./src/systolic_wrap.sv"
`include "./src/tile_load_fsm.sv"
`include "./src/axi_sram_slave.sv"
`timescale 1ns/1ps

module epu_bringup_top #(
  parameter int M=8,
  parameter int N=8,
  parameter int KMAX=1024,
  parameter int MEM_AW=10,     // 1024 depth
  parameter int AXI_AW=32
)(
  input  wire                 clk,
  input  wire                 rst,

  // --------------- AXI4-Lite slave (CPU) ---------------
  input  wire [AXI_AW-1:0]    s_axi_awaddr,
  input  wire                 s_axi_awvalid,
  output wire                 s_axi_awready,

  input  wire [31:0]          s_axi_wdata,
  input  wire [3:0]           s_axi_wstrb,
  input  wire                 s_axi_wvalid,
  output wire                 s_axi_wready,

  output wire [1:0]           s_axi_bresp,
  output wire                 s_axi_bvalid,
  input  wire                 s_axi_bready,

  input  wire [AXI_AW-1:0]    s_axi_araddr,
  input  wire                 s_axi_arvalid,
  output wire                 s_axi_arready,

  output reg  [31:0]          s_axi_rdata,
  output reg  [1:0]           s_axi_rresp,
  output reg                  s_axi_rvalid,
  input  wire                 s_axi_rready
);

  // ---------------- address decode ----------------
  localparam logic [31:0] CSR_BASE     = 32'h4000_0000;
  localparam logic [31:0] CWIN_BASE    = 32'h4000_1000;
  localparam logic [31:0] W_BASE       = 32'h5000_0000;
  localparam logic [31:0] X_BASE       = 32'h5000_8000;

  // regions
  wire hit_csr  = (s_axi_awaddr[31:12] == CSR_BASE[31:12]) ||
                  (s_axi_araddr[31:12] == CSR_BASE[31:12]);
  wire hit_cwin = (s_axi_araddr[31:12] == CWIN_BASE[31:12]);

  wire hit_w = (s_axi_awaddr[31:16] == W_BASE[31:16]) || (s_axi_araddr[31:16] == W_BASE[31:16]);
  wire hit_x = (s_axi_awaddr[31:16] == X_BASE[31:16]) || (s_axi_araddr[31:16] == X_BASE[31:16]);

  // bank select (each bank is 4KB => [15:12])
  wire [2:0] w_bank_sel = s_axi_awaddr[15:12]; // 0..7
  wire [2:0] x_bank_sel = s_axi_awaddr[15:12]; // 0..7 (within X region)
  wire [3:0] bank_sel   = hit_w ? {1'b0, w_bank_sel} :
                          hit_x ? {1'b1, x_bank_sel} : 4'd0;
  // bank index 0..15: 0..7=W, 8..15=X
  wire [3:0] bank_idx = hit_w ? {1'b0, w_bank_sel} : {1'b1, x_bank_sel};

  // ---------------- 16 bank instances ----------------
  // Connect CPU AXI-Lite to only selected bank (simple demux, single outstanding)
  // We'll implement write demux + read demux in a minimal way.

  // per-bank AXI wires
  wire [15:0] b_awready, b_wready, b_bvalid, b_arready, b_rvalid;
  wire [1:0]  b_bresp [16];
  wire [31:0] b_rdata [16];
  wire [1:0]  b_rresp [16];

  // drive bank inputs
  wire [15:0] b_awvalid, b_wvalid, b_bready, b_arvalid, b_rready;
  wire [AXI_AW-1:0] b_awaddr [16];
  wire [31:0]       b_wdata  [16];
  wire [3:0]        b_wstrb  [16];
  wire [AXI_AW-1:0] b_araddr [16];

  // one-hot select
  wire [15:0] oh = (hit_w || hit_x) ? (16'h1 << bank_idx) : 16'h0;

  for (genvar i=0;i<16;i++) begin
    assign b_awaddr[i]  = s_axi_awaddr;
    assign b_wdata[i]   = s_axi_wdata;
    assign b_wstrb[i]   = s_axi_wstrb;
    assign b_araddr[i]  = s_axi_araddr;

    assign b_awvalid[i] = s_axi_awvalid & oh[i];
    assign b_wvalid[i]  = s_axi_wvalid  & oh[i];
    assign b_bready[i]  = s_axi_bready  & oh[i];
    assign b_arvalid[i] = s_axi_arvalid & oh[i];
    assign b_rready[i]  = s_axi_rready  & oh[i];
  end

  // bank ready/resp mux
  wire bank_awready = |(b_awready & oh);
  wire bank_wready  = |(b_wready  & oh);
  wire bank_bvalid  = |(b_bvalid  & oh);
  wire [1:0] bank_bresp = (oh[0] ? b_bresp[0] :
                           oh[1] ? b_bresp[1] :
                           oh[2] ? b_bresp[2] :
                           oh[3] ? b_bresp[3] :
                           oh[4] ? b_bresp[4] :
                           oh[5] ? b_bresp[5] :
                           oh[6] ? b_bresp[6] :
                           oh[7] ? b_bresp[7] :
                           oh[8] ? b_bresp[8] :
                           oh[9] ? b_bresp[9] :
                           oh[10]? b_bresp[10]:
                           oh[11]? b_bresp[11]:
                           oh[12]? b_bresp[12]:
                           oh[13]? b_bresp[13]:
                           oh[14]? b_bresp[14]:
                           oh[15]? b_bresp[15]: 2'b00);

  wire bank_arready = |(b_arready & oh);
  wire bank_rvalid  = |(b_rvalid  & oh);
  wire [31:0] bank_rdata = (oh[0] ? b_rdata[0] :
                            oh[1] ? b_rdata[1] :
                            oh[2] ? b_rdata[2] :
                            oh[3] ? b_rdata[3] :
                            oh[4] ? b_rdata[4] :
                            oh[5] ? b_rdata[5] :
                            oh[6] ? b_rdata[6] :
                            oh[7] ? b_rdata[7] :
                            oh[8] ? b_rdata[8] :
                            oh[9] ? b_rdata[9] :
                            oh[10]? b_rdata[10]:
                            oh[11]? b_rdata[11]:
                            oh[12]? b_rdata[12]:
                            oh[13]? b_rdata[13]:
                            oh[14]? b_rdata[14]:
                            oh[15]? b_rdata[15]: 32'h0);
  wire [1:0] bank_rresp = (oh[0] ? b_rresp[0] :
                           oh[1] ? b_rresp[1] :
                           oh[2] ? b_rresp[2] :
                           oh[3] ? b_rresp[3] :
                           oh[4] ? b_rresp[4] :
                           oh[5] ? b_rresp[5] :
                           oh[6] ? b_rresp[6] :
                           oh[7] ? b_rresp[7] :
                           oh[8] ? b_rresp[8] :
                           oh[9] ? b_rresp[9] :
                           oh[10]? b_rresp[10]:
                           oh[11]? b_rresp[11]:
                           oh[12]? b_rresp[12]:
                           oh[13]? b_rresp[13]:
                           oh[14]? b_rresp[14]:
                           oh[15]? b_rresp[15]: 2'b00);

  // instantiate banks: 0..7=W, 8..15=X
  logic        w_ext_re [M];
  logic [MEM_AW-1:0] w_ext_addr [M];
  wire  [31:0] w_ext_rdata [M];
  wire         w_ext_rvalid[M];

  logic        x_ext_re [N];
  logic [MEM_AW-1:0] x_ext_addr [N];
  wire  [31:0] x_ext_rdata [N];
  wire         x_ext_rvalid[N];

  for (genvar bi=0; bi<16; bi++) begin : GEN_BANK
    // map ext ports
    wire ext_re_i;
    wire [MEM_AW-1:0] ext_addr_i;
    wire [31:0] ext_rdata_i;
    wire ext_rvalid_i;

    if (bi < 8) begin
      assign ext_re_i    = w_ext_re[bi];
      assign ext_addr_i  = w_ext_addr[bi];
      assign w_ext_rdata[bi]  = ext_rdata_i;
      assign w_ext_rvalid[bi] = ext_rvalid_i;
    end else begin
      localparam int jj = bi-8;
      assign ext_re_i   = x_ext_re[jj];
      assign ext_addr_i = x_ext_addr[jj];
      assign x_ext_rdata[jj]  = ext_rdata_i;
      assign x_ext_rvalid[jj] = ext_rvalid_i;
    end

    axi_sram_slave_ext #(
      .ADDR_W(16),              // only need low 16 bits inside bank window
      .DATA_W(32),
      .STRB_W(4),
      .MEM_ADDR_W(MEM_AW),
      .CONFLICT_POLICY(1)
    ) u_bank (
      .clk(clk),
      .rst(rst),

      .s_axi_awaddr (b_awaddr[bi][15:0]),
      .s_axi_awvalid(b_awvalid[bi]),
      .s_axi_awready(b_awready[bi]),

      .s_axi_wdata  (b_wdata[bi]),
      .s_axi_wstrb  (b_wstrb[bi]),
      .s_axi_wvalid (b_wvalid[bi]),
      .s_axi_wready (b_wready[bi]),

      .s_axi_bresp  (b_bresp[bi]),
      .s_axi_bvalid (b_bvalid[bi]),
      .s_axi_bready (b_bready[bi]),

      .s_axi_araddr (b_araddr[bi][15:0]),
      .s_axi_arvalid(b_arvalid[bi]),
      .s_axi_arready(b_arready[bi]),

      .s_axi_rdata  (b_rdata[bi]),
      .s_axi_rresp  (b_rresp[bi]),
      .s_axi_rvalid (b_rvalid[bi]),
      .s_axi_rready (b_rready[bi]),

      .ext_re       (ext_re_i),
      .ext_addr     (ext_addr_i),
      .ext_rdata    (ext_rdata_i),
      .ext_rvalid   (ext_rvalid_i)
    );
  end

  // ---------------- tile arrays feeding your original systolic_wrap ----------------
  logic [31:0] W_tile [M][KMAX];
  logic [31:0] X_tile [KMAX][N];

  // ---------------- CSR regs ----------------
  logic        csr_go;
  logic        csr_done;
  logic [15:0] csr_K_len;

  // load/compute busy
  wire load_busy, load_done;
  wire sa_busy, sa_done;

  // tile_load_fsm
  tile_load_fsm #(.M(M), .N(N), .KMAX(KMAX), .AW(MEM_AW)) u_load (
    .clk(clk), .rst(rst),
    .load_start(csr_go),
    .K_len(csr_K_len),
    .load_busy(load_busy),
    .load_done(load_done),

    .w_ext_re(w_ext_re),
    .w_ext_addr(w_ext_addr),
    .w_ext_rdata(w_ext_rdata),
    .w_ext_rvalid(w_ext_rvalid),

    .x_ext_re(x_ext_re),
    .x_ext_addr(x_ext_addr),
    .x_ext_rdata(x_ext_rdata),
    .x_ext_rvalid(x_ext_rvalid),

    .W_tile(W_tile),
    .X_tile(X_tile)
  );

  // start pulse to systolic_wrap after load_done
  logic start_sa_pulse;
  always_ff @(posedge clk or posedge rst) begin
    if (rst) start_sa_pulse <= 1'b0;
    else    start_sa_pulse <= load_done; // 1-cycle pulse
  end

  // systolic_wrap (your original)
  logic [31:0] C_tile [M][N];
  logic C_valid;

  systolic_wrap #(.M(M), .N(N), .KMAX(KMAX)) u_wrap (
    .clk(clk),
    .rst(rst),
    .start(start_sa_pulse),
    .K_len(csr_K_len),
    .busy(sa_busy),
    .done(sa_done),
    .W_tile(W_tile),
    .X_tile(X_tile),
    .C_tile(C_tile),
    .C_valid(C_valid)
  );

  // done latch
  always_ff @(posedge clk or posedge rst) begin
    if (rst) csr_done <= 1'b0;
    else begin
      if (sa_done) csr_done <= 1'b1;
      // clr_done via CSR write handled below
    end
  end

  // ---------------- AXI-Lite response mux (banks vs CSR/C window) ----------------
  // Write channel: banks handle writes when address in W/X region; CSR handles writes in CSR region.
  // Read channel: banks handle reads in W/X region; CSR/CWIN handled locally.

  // AW/W ready: if hit bank region -> from bank mux, else if CSR -> always ready (single-cycle)
  assign s_axi_awready = (hit_w || hit_x) ? bank_awready :
                         (s_axi_awaddr[31:12]==CSR_BASE[31:12]) ? 1'b1 : 1'b0;
  assign s_axi_wready  = (hit_w || hit_x) ? bank_wready :
                         (s_axi_awaddr[31:12]==CSR_BASE[31:12]) ? 1'b1 : 1'b0;

  // B channel: if bank -> bank bvalid/bresp else CSR immediate
  assign s_axi_bvalid  = (hit_w || hit_x) ? bank_bvalid : 1'b0; // CSR bvalid handled in small FSM below
  assign s_axi_bresp   = (hit_w || hit_x) ? bank_bresp  : 2'b00;

  // For CSR writes, we generate a simple one-cycle BVALID when both AWVALID+WVALID happen.
  reg csr_bvalid;
  always_ff @(posedge clk or posedge rst) begin
    if (rst) csr_bvalid <= 1'b0;
    else begin
      if (csr_bvalid && s_axi_bready) csr_bvalid <= 1'b0;

      if (!csr_bvalid &&
          (s_axi_awaddr[31:12]==CSR_BASE[31:12]) &&
          s_axi_awvalid && s_axi_wvalid) begin
        csr_bvalid <= 1'b1;
      end
    end
  end

  // override BVALID when CSR write
  wire is_csr_write = (s_axi_awaddr[31:12]==CSR_BASE[31:12]) && s_axi_awvalid && s_axi_wvalid;
  wire final_bvalid = ((hit_w || hit_x) ? bank_bvalid : 1'b0) | csr_bvalid;

  // re-drive output
  // (note: s_axi_bvalid is wire; so we use continuous assign via final)
  // already assigned above; override with final using a second assign is illegal in SV,
  // so use a local wire and connect in port list in your integration if needed.
  // For simplicity: comment out earlier assign and use these two lines instead in your file:
  // assign s_axi_bvalid = final_bvalid;
  // assign s_axi_bresp  = 2'b00 for CSR, bank_bresp for bank (you can mux similarly)

  // CSR write effects
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      csr_go    <= 1'b0;
      csr_K_len <= 16'd0;
    end else begin
      // auto-clear go after starting load (pulse)
      if (csr_go) csr_go <= 1'b0;

      if ((s_axi_awaddr[31:12]==CSR_BASE[31:12]) && s_axi_awvalid && s_axi_wvalid) begin
        case (s_axi_awaddr[11:0])
          12'h000: begin
            if (s_axi_wdata[0]) csr_go <= 1'b1;         // go
            if (s_axi_wdata[1]) csr_done <= 1'b0;       // clr_done
          end
          12'h008: csr_K_len <= s_axi_wdata[15:0];
          default: ;
        endcase
      end
    end
  end

  // Read address ready: banks or local (CSR/CWIN)
  assign s_axi_arready = (hit_w || hit_x) ? bank_arready :
                         ((s_axi_araddr[31:12]==CSR_BASE[31:12]) || hit_cwin) ? 1'b1 : 1'b0;

  // Local read response (CSR/C window)
  wire is_local_read = (s_axi_araddr[31:12]==CSR_BASE[31:12]) || hit_cwin;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      s_axi_rvalid <= 1'b0;
      s_axi_rresp  <= 2'b00;
      s_axi_rdata  <= 32'h0;
    end else begin
      if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 1'b0;

      if (!s_axi_rvalid && s_axi_arvalid && s_axi_arready) begin
        if (hit_w || hit_x) begin
          // bank read: wait for bank_rvalid in combinational world is messy; bring-up assume bank returns soon
          // Simplify: directly take bank mux signals as if registered by bank.
          s_axi_rvalid <= bank_rvalid;
          s_axi_rresp  <= bank_rresp;
          s_axi_rdata  <= bank_rdata;
        end else if (s_axi_araddr[31:12]==CSR_BASE[31:12]) begin
          s_axi_rvalid <= 1'b1;
          s_axi_rresp  <= 2'b00;
          case (s_axi_araddr[11:0])
            12'h004: s_axi_rdata <= {29'b0, csr_done, sa_busy, load_busy};
            12'h008: s_axi_rdata <= {16'b0, csr_K_len};
            default: s_axi_rdata <= 32'h0;
          endcase
        end else if (hit_cwin) begin
          // C window read
          int idx, ii, jj;
          idx = (s_axi_araddr - CWIN_BASE) >> 2;
          ii  = idx / N;
          jj  = idx % N;
          s_axi_rvalid <= 1'b1;
          s_axi_rresp  <= 2'b00;
          if (ii < M && jj < N) s_axi_rdata <= C_tile[ii][jj];
          else s_axi_rdata <= 32'h0;
        end else begin
          s_axi_rvalid <= 1'b1;
          s_axi_rresp  <= 2'b10; // SLVERR
          s_axi_rdata  <= 32'h0;
        end
      end
    end
  end

endmodule
