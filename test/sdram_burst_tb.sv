`timescale 1ns / 1ns

module sdram_burst_tb;

  reg  clk = 0;
  reg  reset = 0;

  wire init_complete;
  // wire p0_ready;

  // reg [24:0] p0_addr = 0;
  // reg [15:0] p0_data = 0;
  // wire [127:0] p0_q;

  // reg p0_wr_req = 0;
  // reg p0_rd_req = 0;

  // reg [1:0] p0_byte_en = 0;

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

  // sdram_burst #(
  //     .CLOCK_SPEED_MHZ(100)
  // ) sdram (
  //     .clk(clk),
  //     .reset(reset),
  //     .init_complete(init_complete),

  //     // Port 0
  //     .p0_addr(p0_addr),
  //     .p0_data(p0_data),
  //     .p0_byte_en(p0_byte_en),
  //     .p0_q(p0_q),

  //     .p0_wr_req(p0_wr_req),
  //     .p0_rd_req(p0_rd_req),

  //     .p0_ready(p0_ready),

  //     .SDRAM_DQ(dq),
  //     .SDRAM_A(addr),
  //     .SDRAM_DQM(dqm),
  //     .SDRAM_BA(ba),
  //     .SDRAM_nCS(cs_n),
  //     .SDRAM_nWE(we_n),
  //     .SDRAM_nRAS(ras_n),
  //     .SDRAM_nCAS(cas_n),
  //     .SDRAM_CKE(cke),
  //     .SDRAM_CLK(chip_clk)
  // );

  wire p0_ready;
  wire p0_available;
  reg  prev_p0_available;

  reg  sd_wr = 0;
  reg  sd_rd = 0;

  reg  sd_wr_delay = 0;

  localparam INIT = 0;
  localparam READ = 1;

  reg [ 7:0] state = 0;

  reg [15:0] write_addr = 0;
  reg [ 7:0] read_addr = 0;

  always @(posedge clk) begin
    if (~reset) begin
      prev_p0_available <= p0_available;

      sd_rd <= 0;
      sd_wr <= 0;
      sd_wr_delay <= 0;

      case (state)
        INIT: begin
          if (sd_wr_delay) begin
            sd_wr <= 1;
            sd_wr_delay <= 0;
          end else if (p0_available) begin
            // sd_wr <= 1;
            sd_wr_delay <= 1;
          end else if (prev_p0_available && ~p0_available) begin
            write_addr <= write_addr + 16'h1;

            if (write_addr == {8{1'b1}}) begin
              state <= READ;
            end
          end
        end
        READ: begin
          if (p0_available) begin
            sd_rd <= 1;
          end else if (prev_p0_available && ~p0_available) begin
            read_addr <= read_addr + 8'h1;
          end
        end
      endcase
    end
  end


  sdram_burst #(
      .CLOCK_SPEED_MHZ(128.672),
      .CAS_LATENCY(3)
  ) sdram (
      .clk(clk),
      .reset(reset),
      .init_complete(init_complete),

      // Port 0
      .p0_addr(sd_wr ? {9'b0, write_addr} : {17'b0, read_addr}),
      .p0_data(write_addr),
      .p0_byte_en(2'b11),
      // .p0_q(sdram_data),

      .p0_wr_req(sd_wr),
      .p0_rd_req(sd_rd),

      .p0_available(p0_available),
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
  end

  // initial begin
  //   reset = 1;

  //   #40;

  //   reset = 0;

  //   // #100000;
  //   @(posedge clk iff init_complete);
  //   $display("Init complete at %t", $time());

  //   #10;

  //   p0_addr = 25'h0_32_2020;
  //   p0_data = 16'h1234;

  //   p0_byte_en = 2'h3;
  //   p0_wr_req = 1;

  //   #20;
  //   p0_addr = 0;
  //   p0_data = 0;
  //   #20;
  //   p0_wr_req = 0;

  //   @(posedge clk iff p0_ready);

  //   #10;

  //   p0_addr   = 25'h0_32_2021;
  //   p0_data   = 16'h5678;

  //   p0_wr_req = 1;

  //   #20;
  //   p0_addr   = 0;
  //   p0_data   = 0;
  //   p0_wr_req = 0;

  //   @(posedge clk iff p0_ready);

  //   #10;

  //   p0_addr   = 25'h0_32_2022;
  //   p0_data   = 16'h9ABC;

  //   p0_wr_req = 1;

  //   #20;
  //   p0_addr   = 0;
  //   p0_data   = 0;
  //   p0_wr_req = 0;

  //   @(posedge clk iff p0_ready);

  //   #10;

  //   p0_addr   = 25'h0_32_2023;
  //   p0_data   = 16'hDEF0;

  //   p0_wr_req = 1;

  //   #20;
  //   p0_addr   = 0;
  //   p0_data   = 0;
  //   p0_wr_req = 0;

  //   @(posedge clk iff p0_ready);

  //   #10;

  //   p0_addr   = 25'h0_32_2024;
  //   p0_data   = 16'hFEDC;

  //   p0_wr_req = 1;

  //   #20;
  //   p0_addr   = 0;
  //   p0_data   = 0;
  //   p0_wr_req = 0;

  //   @(posedge clk iff p0_ready);

  //   #10;

  //   p0_addr   = 25'h0_32_2025;
  //   p0_data   = 16'hBA98;

  //   p0_wr_req = 1;

  //   #20;
  //   p0_addr   = 0;
  //   p0_data   = 0;
  //   p0_wr_req = 0;

  //   @(posedge clk iff p0_ready);

  //   #10;

  //   p0_addr   = 25'h0_32_2026;
  //   p0_data   = 16'h7654;

  //   p0_wr_req = 1;

  //   #20;
  //   p0_addr   = 0;
  //   p0_data   = 0;
  //   p0_wr_req = 0;

  //   @(posedge clk iff p0_ready);

  //   #10;

  //   p0_addr   = 25'h0_32_2027;
  //   p0_data   = 16'h3210;

  //   p0_wr_req = 1;

  //   #20;
  //   p0_addr   = 0;
  //   p0_data   = 0;
  //   p0_wr_req = 0;

  //   @(posedge clk iff p0_ready);

  //   #10;

  //   // Read
  //   p0_addr = 25'h0_32_2020;
  //   p0_data = 16'hFFFF;

  //   p0_byte_en = 2'h2;
  //   p0_rd_req = 1;

  //   #20;
  //   p0_addr   = 0;
  //   p0_rd_req = 0;

  //   @(posedge clk iff p0_ready);

  //   #100;

  //   $stop();
  // end

endmodule
