`timescale 1ns / 1ns

module sdram_tb;

  reg clk = 0;
  reg reset = 0;

  wire init_complete;
  wire p0_ready;

  reg [24:0] p0_addr = 0;
  reg [15:0] p0_data = 0;
  wire [127:0] p0_q;

  reg p0_wr_req = 0;
  reg p0_rd_req = 0;

  reg [1:0] p0_byte_en = 0;

  always begin
    #10 clk <= ~clk;
  end

  wire [15:0] dq;
  wire [12:0] addr;
  wire [1:0] dqm;
  wire [1:0] ba;
  wire cs_n;
  wire we_n;
  wire ras_n;
  wire cas_n;
  wire cke;
  wire chip_clk;

  sdr sdram0 (
      dq,
      addr,
      ba,
      chip_clk,
      cke,
      cs_n,
      ras_n,
      cas_n,
      we_n,
      dqm
  );

  sdram #(
      .CLOCK_SPEED_MHZ(100),
      .BURST_LENGTH(8),
      .P0_BURST_LENGTH(8)
  ) sdram (
      .clk(clk),
      .reset(reset),
      .init_complete(init_complete),

      // Port 0
      .p0_addr(p0_addr),
      .p0_data(p0_data),
      .p0_byte_en(p0_byte_en),
      .p0_q(p0_q),

      .p0_wr_req(p0_wr_req),
      .p0_rd_req(p0_rd_req),

      .p0_ready(p0_ready),

      .SDRAM_DQ(dq),
      .SDRAM_A(addr),
      .SDRAM_DQM(dqm),
      .SDRAM_BA(ba),
      .SDRAM_nCS(cs_n),
      .SDRAM_nWE(we_n),
      .SDRAM_nRAS(ras_n),
      .SDRAM_nCAS(cas_n),
      .SDRAM_CKE(cke),
      .SDRAM_CLK(chip_clk)
  );

  initial begin
    reset = 1;

    #40;

    reset = 0;

    // #100000;
    @(posedge clk iff init_complete);
    $display("Init complete at %t", $time());

    #10;

    p0_addr = 25'h0_32_2020;
    p0_data = 16'h1234;

    p0_byte_en = 2'h3;
    p0_wr_req = 1;

    #20;
    p0_addr = 0;
    p0_data = 0;
    #20;
    p0_wr_req = 0;

    @(posedge clk iff p0_ready);

    #10;

    p0_addr   = 25'h0_32_2021;
    p0_data   = 16'h5678;

    p0_wr_req = 1;

    #20;
    p0_addr   = 0;
    p0_data   = 0;
    p0_wr_req = 0;

    @(posedge clk iff p0_ready);

    #10;

    p0_addr   = 25'h0_32_2022;
    p0_data   = 16'h9ABC;

    p0_wr_req = 1;

    #20;
    p0_addr   = 0;
    p0_data   = 0;
    p0_wr_req = 0;

    @(posedge clk iff p0_ready);

    #10;

    p0_addr   = 25'h0_32_2023;
    p0_data   = 16'hDEF0;

    p0_wr_req = 1;

    #20;
    p0_addr   = 0;
    p0_data   = 0;
    p0_wr_req = 0;

    @(posedge clk iff p0_ready);

    #10;

    p0_addr   = 25'h0_32_2024;
    p0_data   = 16'hFEDC;

    p0_wr_req = 1;

    #20;
    p0_addr   = 0;
    p0_data   = 0;
    p0_wr_req = 0;

    @(posedge clk iff p0_ready);

    #10;

    p0_addr   = 25'h0_32_2025;
    p0_data   = 16'hBA98;

    p0_wr_req = 1;

    #20;
    p0_addr   = 0;
    p0_data   = 0;
    p0_wr_req = 0;

    @(posedge clk iff p0_ready);

    #10;

    p0_addr   = 25'h0_32_2026;
    p0_data   = 16'h7654;

    p0_wr_req = 1;

    #20;
    p0_addr   = 0;
    p0_data   = 0;
    p0_wr_req = 0;

    @(posedge clk iff p0_ready);

    #10;

    p0_addr   = 25'h0_32_2027;
    p0_data   = 16'h3210;

    p0_wr_req = 1;

    #20;
    p0_addr   = 0;
    p0_data   = 0;
    p0_wr_req = 0;

    @(posedge clk iff p0_ready);

    #10;

    // Read
    p0_addr = 25'h0_32_2020;
    p0_data = 16'hFFFF;

    p0_byte_en = 2'h2;
    p0_rd_req = 1;

    #20;
    p0_addr   = 0;
    p0_rd_req = 0;

    @(posedge clk iff p0_ready);

    #10;

    $stop();
  end

endmodule
