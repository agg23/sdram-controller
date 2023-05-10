function integer rtoi(input integer x);
  return x;
endfunction

`define CEIL(x) ((rtoi(x) > x) ? rtoi(x) : rtoi(x) + 1)

module sdram #(
    parameter CLOCK_SPEED_MHZ = 0,
    parameter BURST_LENGTH = 1,  // 1, 2, 4, 8 words per read
    parameter BURST_TYPE = 0,  // 1 for interleaved
    parameter CAS_LATENCY = 2,  // 1, 2, or 3 cycle delays
    parameter WRITE_BURST = 0  // 1 to enable write bursting
) (
    input wire clk,
    input wire reset, // Used to trigger start of FSM

    inout  reg  [15:0] SDRAM_DQ,    // Bidirectional data bus
    output reg  [12:0] SDRAM_A,     // Address bus
    output reg  [ 1:0] SDRAM_DQM,   // High/low byte mask
    output reg  [ 1:0] SDRAM_BA,    // Bank select (single bits)
    output reg         SDRAM_nCS,   // Chip select, neg triggered
    output reg         SDRAM_nWE,   // Write enable, neg triggered
    output reg         SDRAM_nRAS,  // Select row address, neg triggered
    output reg         SDRAM_nCAS,  // Select column address, neg triggered
    output reg         SDRAM_CKE,   // Clock enable
    output wire        SDRAM_CLK    // Chip clock
);
  // Config values
  // NOTE: These are configured by default for the Pocket's SDRAM
  localparam SETTING_INHIBIT_DELAY_MICRO_SEC = 100;

  // tCK - Min clock cycle time
  localparam SETTING_T_CK_MIN_CLOCK_CYCLE_TIME_NANO_SEC = 6;

  // tRAS - Min row active time
  localparam SETTING_T_RAS_MIN_ROW_ACTIVE_TIME_NANO_SEC = 48;

  // tRC - Min row cycle time
  localparam SETTING_T_RC_MIN_ROW_CYCLE_TIME_NANO_SEC = 60;

  // tRP - Min precharge command period
  localparam SETTING_T_RP_MIN_PRECHARGE_CMD_PERIOD_NANO_SEC = 18;

  // tRFC - Min autorefresh period
  localparam SETTING_T_RFC_MIN_AUTOREFRESH_PERIOD_NANO_SEC = 80;

  // tMRD - Min number of clock cycles between mode set and normal usage
  localparam SETTING_T_MRD_MIN_LOAD_MODE_CLOCK_CYCLES = 2;

  ////////////////////////////////////////////////////////////////////////////////////////
  // Generated parameters

  localparam CLOCK_PERIOD_NANO_SEC = 1000.0 / CLOCK_SPEED_MHZ;

  // Number of cycles after reset until we start command inhibit
  localparam CYCLES_UNTIL_START_INHIBIT =
  `CEIL(SETTING_INHIBIT_DELAY_MICRO_SEC * 500 / CLOCK_PERIOD_NANO_SEC);
  // Number of cycles after reset until we clear command inhibit and start operation
  // We add 100 cycles for good measure
  localparam CYCLES_UNTIL_CLEAR_INHIBIT = 100 +
  `CEIL(SETTING_INHIBIT_DELAY_MICRO_SEC * 1000 / CLOCK_PERIOD_NANO_SEC);

  // Number of cycles after reset until we are done with precharge
  // We add 10 cycles for good measure
  localparam CYCLES_UNTIL_PRECHARGE_END = 10 + CYCLES_UNTIL_CLEAR_INHIBIT +
  `CEIL(SETTING_T_RP_MIN_PRECHARGE_CMD_PERIOD_NANO_SEC / CLOCK_PERIOD_NANO_SEC);

  // Number of cycles an autorefresh takes
  localparam CYCLES_FOR_AUTOREFRESH =
  `CEIL(SETTING_T_RFC_MIN_AUTOREFRESH_PERIOD_NANO_SEC / CLOCK_PERIOD_NANO_SEC);

  ////////////////////////////////////////////////////////////////////////////////////////
  // Init helpers
  localparam CYCLES_UNTIL_REFRESH1_END = CYCLES_UNTIL_PRECHARGE_END + CYCLES_FOR_AUTOREFRESH;
  localparam CYCLES_UNTIL_REFRESH2_END = CYCLES_UNTIL_REFRESH1_END + CYCLES_FOR_AUTOREFRESH;

  wire [2:0] concrete_burst_length = BURST_LENGTH == 1 ? 3'h0 : BURST_LENGTH == 2 ? 3'h1 : BURST_LENGTH == 4 ? 3'h2 : 3'h3;
  // Reserved, write burst, operating mode, CAS latency, burst type, burst length
  wire [12:0] configured_mode = {
    3'b0, ~WRITE_BURST[0], 2'b0, CAS_LATENCY[2:0], BURST_TYPE[0], concrete_burst_length
  };

  ////////////////////////////////////////////////////////////////////////////////////////
  // State machine

  localparam STATE_INIT = 0;
  localparam STATE_IDLE = 1;

  reg [ 7:0] state = STATE_INIT;

  reg [31:0] init_counter = 0;

  always @(posedge clk) begin
    if (reset) begin
      // 2. Assert and hold CKE at logic low
      SDRAM_CKE <= 0;

      init_counter <= 0;
    end else begin
      case (state)
        STATE_INIT: begin
          init_counter <= init_counter + 32'h1;

          // Default to NOP at all times in between commands
          // NOP
          SDRAM_nCS <= 0;
          SDRAM_nRAS <= 1;
          SDRAM_nCAS <= 1;
          SDRAM_nWE <= 1;

          if (init_counter == CYCLES_UNTIL_START_INHIBIT) begin
            // Start setting inhibit
            // 5. Starting at some point during this 100us period, bring CKE high
            SDRAM_CKE <= 1;

            // We're already asserting NOP above
          end else if (init_counter == CYCLES_UNTIL_CLEAR_INHIBIT) begin
            // Clear inhibit, start precharge
            SDRAM_nCS   <= 0;
            SDRAM_nRAS  <= 0;
            SDRAM_nCAS  <= 1;
            SDRAM_nWE   <= 0;

            // Mark all banks for refresh
            SDRAM_A[10] <= 1;
          end else if (init_counter == CYCLES_UNTIL_PRECHARGE_END || init_counter == CYCLES_UNTIL_REFRESH1_END) begin
            // Precharge done (or first auto refresh), auto refresh
            // CKE high specifies auto refresh
            SDRAM_CKE  <= 1;

            SDRAM_nCS  <= 0;
            SDRAM_nRAS <= 0;
            SDRAM_nCAS <= 0;
            SDRAM_nWE  <= 1;
          end else if (init_counter == CYCLES_UNTIL_REFRESH2_END) begin
            // Second auto refresh done, load mode register
            SDRAM_nCS <= 0;
            SDRAM_nRAS <= 0;
            SDRAM_nCAS <= 0;
            SDRAM_nWE <= 0;

            SDRAM_BA <= 2'b0;

            SDRAM_A <= configured_mode;
          end else if (init_counter == CYCLES_UNTIL_REFRESH2_END + SETTING_T_MRD_MIN_LOAD_MODE_CLOCK_CYCLES) begin
            // We can now execute commands
            state <= STATE_IDLE;
          end
        end
      endcase
    end
  end

  // This DDIO block doesn't double the clock, it just relocates the RAM clock to trigger
  // on the negative edge
  altddio_out #(
      .extend_oe_disable("OFF"),
      .intended_device_family("Cyclone V"),
      .invert_output("OFF"),
      .lpm_hint("UNUSED"),
      .lpm_type("altddio_out"),
      .oe_reg("UNREGISTERED"),
      .power_up_high("OFF"),
      .width(1)
  ) sdramclk_ddr (
      .datain_h(1'b0),
      .datain_l(1'b1),
      .outclock(clk),
      .dataout(SDRAM_CLK),
      .oe(1'b1),
      .outclocken(1'b1)
      // .aclr(),
      // .aset(),
      // .sclr(),
      // .sset()
  );

  // Parameter validation
  initial begin
    $info("Instantiated SDRAM with the following settings");
    $info("  Clock speed %6f, period %6f", CLOCK_SPEED_MHZ, CLOCK_PERIOD_NANO_SEC);

    if (CLOCK_SPEED_MHZ <= 0 || CLOCK_PERIOD_NANO_SEC <= SETTING_T_CK_MIN_CLOCK_CYCLE_TIME_NANO_SEC) begin
      $error("Invalid clock speed. Quitting");
    end

    $info("  Cycles until start inhibit %6f, clear inhibit %6f", CYCLES_UNTIL_START_INHIBIT,
          CYCLES_UNTIL_CLEAR_INHIBIT);

    $info("--------------------");
    $info("Configured values:");
    $info("  CAS Latency %1h", CAS_LATENCY);

    if (CAS_LATENCY != 1 && CAS_LATENCY != 2 && CAS_LATENCY != 3) begin
      $error("Unknown CAS latency");
    end

    $info("  Burst length %1h", BURST_LENGTH);

    if (BURST_LENGTH != 1 && BURST_LENGTH != 2 && BURST_LENGTH != 4 && BURST_LENGTH != 8) begin
      $error("Unknown burst length");
    end

    $info("  Burst type %s",
          BURST_TYPE == 0 ? "Sequential" : BURST_TYPE == 1 ? "Interleaved" : "Unknown");

    if (BURST_TYPE != 0 && BURST_TYPE != 1) begin
      $error("Unknown burst type");
    end

    $info("  Write burst %s",
          WRITE_BURST == 0 ? "Single word write" : WRITE_BURST == 1 ? "Write burst" : "Unknown");

    if (WRITE_BURST != 0 && WRITE_BURST != 1) begin
      $error("Unknown write burst");
    end
  end

endmodule
