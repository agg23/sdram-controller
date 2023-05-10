`timescale 1ns / 1ns

module sdram_tb;

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

  reg clk = 0;
  reg reset = 0;

  always begin
    #10 clk <= ~clk;
  end

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
      .CLOCK_SPEED_MHZ(100)
  ) sdram (
      .clk  (clk),
      .reset(reset),

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

    #100000;
  end

endmodule
