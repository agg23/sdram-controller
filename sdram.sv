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
    input wire reset,  // Used to trigger start of FSM
    output wire init_complete,  // SDRAM is done initializing

    // Port 0
    input  wire [25:1] p0_addr,
    input  wire [15:0] p0_data,
    input  wire [ 1:0] p0_byte_en,  // Byte enable for writes
    output reg  [31:0] p0_q,

    input wire p0_wr_req,
    input wire p0_rd_req,

    output wire p0_ready,

    inout  wire [15:0] SDRAM_DQ,    // Bidirectional data bus
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

  // tRC - Min active to active command period for the same bank
  localparam SETTING_T_RC_MIN_ACTIVE_TO_ACTIVE_PERIOD_NANO_SEC = 60;

  // tRCD - Min read/write delay
  localparam SETTING_T_RCD_MIN_READ_WRITE_DELAY_NANO_SEC = 18;

  // tWR - Min write auto precharge recovery time
  localparam SETTING_T_WR_MIN_WRITE_AUTO_PRECHARGE_RECOVERY_NANO_SEC = 15;

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

  // Number of cycles for precharge duration
  localparam CYCLES_FOR_PRECHARGE =
  `CEIL(SETTING_T_RP_MIN_PRECHARGE_CMD_PERIOD_NANO_SEC / CLOCK_PERIOD_NANO_SEC);

  // Number of cycles for autorefresh duration
  localparam CYCLES_FOR_AUTOREFRESH =
  `CEIL(SETTING_T_RFC_MIN_AUTOREFRESH_PERIOD_NANO_SEC / CLOCK_PERIOD_NANO_SEC);

  // Number of cycles between two active commands to the same bank
  localparam CYCLES_BETWEEN_ACTIVE_COMMAND =
  `CEIL(SETTING_T_RC_MIN_ACTIVE_TO_ACTIVE_PERIOD_NANO_SEC / CLOCK_PERIOD_NANO_SEC);

  // Number of cycles after active command before a read/write can be executed
  localparam CYCLES_FOR_ACTIVE_ROW =
  `CEIL(SETTING_T_RCD_MIN_READ_WRITE_DELAY_NANO_SEC / CLOCK_PERIOD_NANO_SEC);

  // Number of cycles after write that precharge_starts
  localparam CYCLES_AFTER_WRITE_FOR_PRECHARGE_START =
  `CEIL(SETTING_T_WR_MIN_WRITE_AUTO_PRECHARGE_RECOVERY_NANO_SEC / CLOCK_PERIOD_NANO_SEC);

  ////////////////////////////////////////////////////////////////////////////////////////
  // Init helpers
  // Number of cycles after reset until we are done with precharge
  // We add 10 cycles for good measure
  localparam CYCLES_UNTIL_INIT_PRECHARGE_END = 10 + CYCLES_UNTIL_CLEAR_INHIBIT +
  `CEIL(SETTING_T_RP_MIN_PRECHARGE_CMD_PERIOD_NANO_SEC / CLOCK_PERIOD_NANO_SEC);

  localparam CYCLES_UNTIL_REFRESH1_END = CYCLES_UNTIL_INIT_PRECHARGE_END + CYCLES_FOR_AUTOREFRESH;
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
  localparam STATE_DELAY = 2;
  localparam STATE_WRITE = 3;

  reg [ 7:0] state = STATE_INIT;

  reg [31:0] delay_counter = 0;

  reg [ 1:0] active_port = 0;

  localparam ACTION_IDLE = 0;
  localparam ACTION_READ = 1;
  localparam ACTION_WRITE = 2;

  reg [1:0] delay_action = ACTION_IDLE;

  // Cache the signals we received, potentially while busy
  reg p0_wr_cache = 0;
  reg p0_rd_cache = 0;
  reg [1:0] p0_byte_en_cache = 0;
  reg [24:0] p0_addr_cache = 0;
  reg [15:0] p0_data_cache = 0;

  wire p0_req = p0_wr_req || p0_rd_req;
  wire p0_req_cache = p0_wr_cache || p0_rd_cache;
  // The current p0 address that should be used for any operations on this cycle
  wire [24:0] p0_addr_current = p0_req_cache ? p0_addr_cache : p0_addr;

  // An active new request or cached request
  wire port_req = p0_req || p0_req_cache;

  // Activates a row
  task set_active_command(reg [1:0] port, reg [24:0] addr);
    SDRAM_nCS <= 0;
    SDRAM_nRAS <= 0;
    SDRAM_nCAS <= 1;
    SDRAM_nWE <= 1;

    // Upper two bits choose the bank
    SDRAM_BA <= addr[24:23];

    // Row address
    SDRAM_A <= addr[22:10];

    active_port <= port;
    delay_counter <= CYCLES_FOR_ACTIVE_ROW;
  endtask

  reg dq_output = 0;

  reg [15:0] sdram_data = 0;
  assign SDRAM_DQ = dq_output ? sdram_data : 16'hZZZZ;

  assign init_complete = state != STATE_INIT;

  assign p0_ready = state == STATE_IDLE && ~port_req;

  always @(posedge clk) begin
    if (reset) begin
      // 2. Assert and hold CKE at logic low
      SDRAM_CKE <= 0;

      delay_counter <= 0;

      p0_wr_cache <= 0;
      p0_rd_cache <= 0;
    end else begin
      // Cache port 0 input values
      if (p0_wr_req) begin
        p0_wr_cache <= 1;

        p0_byte_en_cache <= p0_byte_en;
        p0_addr_cache <= p0_addr;
        p0_data_cache <= p0_data;
      end else if (p0_rd_req) begin
        p0_rd_cache   <= 1;

        p0_addr_cache <= p0_addr;
      end

      // Default to NOP at all times in between commands
      // NOP
      SDRAM_nCS  <= 0;
      SDRAM_nRAS <= 1;
      SDRAM_nCAS <= 1;
      SDRAM_nWE  <= 1;

      case (state)
        STATE_INIT: begin
          delay_counter <= delay_counter + 32'h1;

          if (delay_counter == CYCLES_UNTIL_START_INHIBIT) begin
            // Start setting inhibit
            // 5. Starting at some point during this 100us period, bring CKE high
            SDRAM_CKE <= 1;

            // We're already asserting NOP above
          end else if (delay_counter == CYCLES_UNTIL_CLEAR_INHIBIT) begin
            // Clear inhibit, start precharge
            SDRAM_nCS   <= 0;
            SDRAM_nRAS  <= 0;
            SDRAM_nCAS  <= 1;
            SDRAM_nWE   <= 0;

            // Mark all banks for refresh
            SDRAM_A[10] <= 1;
          end else if (delay_counter == CYCLES_UNTIL_INIT_PRECHARGE_END || delay_counter == CYCLES_UNTIL_REFRESH1_END) begin
            // Precharge done (or first auto refresh), auto refresh
            // CKE high specifies auto refresh
            SDRAM_CKE  <= 1;

            SDRAM_nCS  <= 0;
            SDRAM_nRAS <= 0;
            SDRAM_nCAS <= 0;
            SDRAM_nWE  <= 1;
          end else if (delay_counter == CYCLES_UNTIL_REFRESH2_END) begin
            // Second auto refresh done, load mode register
            SDRAM_nCS <= 0;
            SDRAM_nRAS <= 0;
            SDRAM_nCAS <= 0;
            SDRAM_nWE <= 0;

            SDRAM_BA <= 2'b0;

            SDRAM_A <= configured_mode;
          end else if (delay_counter == CYCLES_UNTIL_REFRESH2_END + SETTING_T_MRD_MIN_LOAD_MODE_CLOCK_CYCLES) begin
            // We can now execute commands
            state <= STATE_IDLE;
          end
        end
        STATE_IDLE: begin
          // Stop outputting on DQ and hold in high Z
          dq_output <= 0;

          // TODO: Check for refresh
          if (p0_wr_req || p0_wr_cache) begin
            // Port 0 write
            state <= STATE_DELAY;
            delay_action <= ACTION_WRITE;

            p0_wr_cache <= 0;

            set_active_command(0, p0_addr_current);
          end
        end
        STATE_DELAY: begin
          if (delay_counter > 0) begin
            delay_counter <= delay_counter - 32'h1;
          end else begin
            // TODO: Change
            delay_action <= ACTION_IDLE;

            case (delay_action)
              ACTION_IDLE:  state <= STATE_IDLE;
              ACTION_WRITE: state <= STATE_WRITE;
            endcase
          end
        end
        STATE_WRITE: begin
          // Write to the selected row
          reg [ 9:0] port_addr;
          reg [15:0] port_data;
          reg [ 1:0] port_byte_en;

          state <= STATE_DELAY;
          // A write must wait for auto precharge (tWR) and precharge command period (tRP)
          delay_counter <= CYCLES_AFTER_WRITE_FOR_PRECHARGE_START + CYCLES_FOR_PRECHARGE;

          case (active_port)
            0: begin
              port_addr = p0_addr_cache[9:0];
              port_data = p0_data_cache;
              port_byte_en = p0_byte_en_cache;
            end
          endcase

          SDRAM_nCS <= 0;
          SDRAM_nRAS <= 1;
          SDRAM_nCAS <= 0;
          SDRAM_nWE <= 0;

          // NOTE: Bank is still set from ACTIVE command assertion
          // High bit enables auto precharge. I assume the top 2 bits are unused
          SDRAM_A <= {2'b0, 1'b1, port_addr};
          dq_output <= 1;
          sdram_data <= port_data;

          // Use byte enable from port
          SDRAM_DQM <= ~port_byte_en;
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

    $info("--------------------");
    $info("  Cycles until start inhibit %6f, clear inhibit %6f", CYCLES_UNTIL_START_INHIBIT,
          CYCLES_UNTIL_CLEAR_INHIBIT);

    $info("  Cycles until between active commands %6f, command duration %6f",
          CYCLES_BETWEEN_ACTIVE_COMMAND, CYCLES_FOR_ACTIVE_ROW);
  end

endmodule
