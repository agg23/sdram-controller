function integer rtoi(input integer x);
  return x;
endfunction

`define CEIL(x) ((rtoi(x) > x) ? rtoi(x) : rtoi(x) + 1)

module sdram #(
    parameter CLOCK_SPEED_MHZ = 0,
    parameter BURST_LENGTH = 1,  // 1, 2, 4, 8 words per read
    parameter BURST_TYPE = 0,  // 1 for interleaved
    parameter CAS_LATENCY = 2,  // 1, 2, or 3 cycle delays
    parameter WRITE_BURST = 0,  // 1 to enable write bursting

    // Port config
    parameter P0_BURST_LENGTH = BURST_LENGTH  // 1, 2, 4, 8 words per read
) (
    input wire clk,
    input wire reset,  // Used to trigger start of FSM
    output wire init_complete,  // SDRAM is done initializing

    // Port 0
    input wire [24:0] p0_addr,
    input wire [15:0] p0_data,
    input wire [1:0] p0_byte_en,  // Byte enable for writes
    output reg [P0_BURST_LENGTH * 16 - 1:0] p0_q,

    input wire p0_wr_req,
    input wire p0_rd_req,

    output wire p0_available,  // The port is able to be used
    output reg p0_ready,  // The port has finished its task. Will rise for a single cycle

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

  // 8,192 refresh commands every 64ms = 7.8125us, which we round to 7500ns to make sure we hit them all
  localparam SETTING_REFRESH_TIMER_NANO_SEC = 7500;

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
  // localparam CYCLES_FOR_PRECHARGE =
  // `CEIL(SETTING_T_RP_MIN_PRECHARGE_CMD_PERIOD_NANO_SEC / CLOCK_PERIOD_NANO_SEC);

  // Number of cycles for autorefresh duration
  localparam CYCLES_FOR_AUTOREFRESH =
  `CEIL(SETTING_T_RFC_MIN_AUTOREFRESH_PERIOD_NANO_SEC / CLOCK_PERIOD_NANO_SEC);

  // Number of cycles between two active commands to the same bank
  localparam CYCLES_BETWEEN_ACTIVE_COMMAND =
  `CEIL(SETTING_T_RC_MIN_ACTIVE_TO_ACTIVE_PERIOD_NANO_SEC / CLOCK_PERIOD_NANO_SEC);

  // Number of cycles after active command before a read/write can be executed
  localparam CYCLES_FOR_ACTIVE_ROW =
  `CEIL(SETTING_T_RCD_MIN_READ_WRITE_DELAY_NANO_SEC / CLOCK_PERIOD_NANO_SEC);

  // Number of cycles after write before next command
  localparam CYCLES_AFTER_WRITE_FOR_NEXT_COMMAND =
  `CEIL(
      (SETTING_T_WR_MIN_WRITE_AUTO_PRECHARGE_RECOVERY_NANO_SEC + SETTING_T_RP_MIN_PRECHARGE_CMD_PERIOD_NANO_SEC) / CLOCK_PERIOD_NANO_SEC);

  // Number of cycles between each autorefresh command
  localparam CYCLES_PER_REFRESH =
  `CEIL(SETTING_REFRESH_TIMER_NANO_SEC / CLOCK_PERIOD_NANO_SEC);

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

  localparam P0_OUTPUT_WIDTH = P0_BURST_LENGTH * 16 - 1;

  typedef struct {
    reg [9:0]  port_addr;
    reg [15:0] port_data;
    reg [1:0]  port_byte_en;
  } port_selection;

  ////////////////////////////////////////////////////////////////////////////////////////
  // State machine

  localparam STATE_INIT = 0;
  localparam STATE_IDLE = 1;
  localparam STATE_DELAY = 2;
  localparam STATE_WRITE = 3;
  localparam STATE_READ = 4;
  localparam STATE_READ_OUTPUT = 5;

  reg [ 2:0] state = STATE_INIT;

  // TODO: Could use fewer bits
  reg [31:0] delay_counter = 0;
  // The number of words we're reading
  reg [ 3:0] read_counter = 0;

  // Measures when auto refresh needs to be triggered
  reg [15:0] refresh_counter = 0;

  reg [ 1:0] active_port = 0;

  reg [ 2:0] delay_state = STATE_IDLE;

  localparam OP_NONE = 0;
  localparam OP_WRITE = 1;
  localparam OP_READ = 2;

  reg [1:0] current_io_operation = OP_NONE;

  // Cache the signals we received, potentially while busy
  reg p0_wr_queue = 0;
  reg p0_rd_queue = 0;
  reg [1:0] p0_byte_en_queue = 0;
  reg [24:0] p0_addr_queue = 0;
  reg [15:0] p0_data_queue = 0;

  wire p0_req = p0_wr_req || p0_rd_req;
  wire p0_req_queue = p0_wr_queue || p0_rd_queue;
  // The current p0 address that should be used for any operations on this first cycle only
  wire [24:0] p0_addr_current = p0_req_queue ? p0_addr_queue : p0_addr;

  // An active new request or cached request
  wire port_req = p0_req || p0_req_queue;

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
    // Current construction takes two cycles to write next data
    delay_counter <= CYCLES_FOR_ACTIVE_ROW > 32'h2 ? CYCLES_FOR_ACTIVE_ROW - 32'h2 : 32'h0;
  endtask

  function port_selection get_active_port();
    port_selection selection;

    case (active_port)
      0: begin
        selection.port_addr = p0_addr_queue[9:0];
        selection.port_data = p0_data_queue;
        selection.port_byte_en = p0_byte_en_queue;
      end
    endcase

    return selection;
  endfunction

  reg dq_output = 0;

  reg [15:0] sdram_data = 0;
  assign SDRAM_DQ = dq_output ? sdram_data : 16'hZZZZ;

  assign init_complete = state != STATE_INIT;

  assign p0_available = state == STATE_IDLE && ~port_req;

  always @(posedge clk) begin
    if (reset) begin
      // 2. Assert and hold CKE at logic low
      SDRAM_CKE <= 0;

      delay_counter <= 0;

      p0_wr_queue <= 0;
      p0_rd_queue <= 0;

      dq_output <= 0;

      p0_q <= 0;
    end else begin
      // Cache port 0 input values
      if (p0_wr_req && current_io_operation != OP_WRITE) begin
        p0_wr_queue <= 1;

        p0_byte_en_queue <= p0_byte_en;
        p0_addr_queue <= p0_addr;
        p0_data_queue <= p0_data;
      end else if (p0_rd_req && current_io_operation != OP_READ) begin
        p0_rd_queue   <= 1;

        p0_addr_queue <= p0_addr;
      end

      // Default to NOP at all times in between commands
      // NOP
      SDRAM_nCS  <= 0;
      SDRAM_nRAS <= 1;
      SDRAM_nCAS <= 1;
      SDRAM_nWE  <= 1;

      if (state != STATE_INIT) begin
        refresh_counter <= refresh_counter + 16'h1;
      end

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

          p0_ready <= 0;

          current_io_operation <= OP_NONE;

          if (refresh_counter >= CYCLES_PER_REFRESH[15:0]) begin
            // Trigger refresh
            state <= STATE_DELAY;
            delay_state <= STATE_IDLE;
            delay_counter <= CYCLES_FOR_AUTOREFRESH - 32'h2;

            refresh_counter <= 0;

            SDRAM_nCS <= 0;
            SDRAM_nRAS <= 0;
            SDRAM_nCAS <= 0;
            SDRAM_nWE <= 1;
          end else if (p0_wr_req || p0_wr_queue) begin
            // Port 0 write
            state <= STATE_DELAY;
            delay_state <= STATE_WRITE;

            current_io_operation <= OP_WRITE;

            // Clear queued action
            p0_wr_queue <= 0;

            set_active_command(0, p0_addr_current);
          end else if (p0_rd_req || p0_rd_queue) begin
            // Port 0 read
            state <= STATE_DELAY;
            delay_state <= STATE_READ;

            current_io_operation <= OP_READ;

            set_active_command(0, p0_addr_current);
          end
        end
        STATE_DELAY: begin
          if (delay_counter > 0) begin
            delay_counter <= delay_counter - 32'h1;
          end else begin
            state <= delay_state;
            delay_state <= STATE_IDLE;

            if (delay_state == STATE_IDLE && current_io_operation != OP_NONE) begin
              case (active_port)
                0: p0_ready <= 1;
              endcase
            end
          end
        end
        STATE_WRITE: begin
          // Write to the selected row
          port_selection active_port_entries;

          state <= STATE_DELAY;
          // A write must wait for auto precharge (tWR) and precharge command period (tRP)
          // Takes one cycle to get back to IDLE, and another to read command
          delay_counter <= CYCLES_AFTER_WRITE_FOR_NEXT_COMMAND - 32'h2;

          active_port_entries = get_active_port();

          SDRAM_nCS <= 0;
          SDRAM_nRAS <= 1;
          SDRAM_nCAS <= 0;
          SDRAM_nWE <= 0;

          // NOTE: Bank is still set from ACTIVE command assertion
          // High bit enables auto precharge. I assume the top 2 bits are unused
          SDRAM_A <= {2'b0, 1'b1, active_port_entries.port_addr};
          // Enable DQ output
          dq_output <= 1;
          sdram_data <= active_port_entries.port_data;

          // Use byte enable from port
          SDRAM_DQM <= ~active_port_entries.port_byte_en;
        end
        STATE_READ: begin
          // Read to the selected row
          port_selection active_port_entries;

          if (CAS_LATENCY == 1) begin
            // Go directly to read
            state <= STATE_READ_OUTPUT;
          end else begin
            state <= STATE_DELAY;
            delay_state <= STATE_READ_OUTPUT;

            read_counter <= 0;

            // Takes one cycle to go to read data, and one to actually read the data
            // TODO: This appears to be incorrect in hardware vs the model, hence the +1
            delay_counter <= CAS_LATENCY - 32'h2 + 32'h1;
          end

          active_port_entries = get_active_port();

          // Clear queued action
          p0_rd_queue <= 0;

          SDRAM_nCS <= 0;
          SDRAM_nRAS <= 1;
          SDRAM_nCAS <= 0;
          SDRAM_nWE <= 1;

          // NOTE: Bank is still set from ACTIVE command assertion
          // High bit enables auto precharge. I assume the top 2 bits are unused
          SDRAM_A <= {2'b0, 1'b1, active_port_entries.port_addr};

          // Fetch all bytes
          SDRAM_DQM <= 2'b0;
        end
        STATE_READ_OUTPUT: begin
          reg [127:0] temp;
          reg [  3:0] expected_count;

          case (active_port)
            0: begin
              temp[P0_OUTPUT_WIDTH:0] = p0_q;

              expected_count = P0_BURST_LENGTH;
            end
          endcase

          if (read_counter < expected_count) begin
            read_counter <= read_counter + 4'h1;
          end else begin
            // We've read everything, and are done
            state <= STATE_IDLE;
          end

          case (read_counter)
            0: temp[15:0] = SDRAM_DQ;
            1: temp[31:16] = SDRAM_DQ;
            2: temp[47:32] = SDRAM_DQ;
            3: temp[63:48] = SDRAM_DQ;
            4: temp[79:64] = SDRAM_DQ;
            5: temp[95:80] = SDRAM_DQ;
            6: temp[111:96] = SDRAM_DQ;
            7: temp[127:112] = SDRAM_DQ;
          endcase

          case (active_port)
            0: begin
              p0_q <= temp[P0_OUTPUT_WIDTH:0];

              if (read_counter == expected_count) begin
                p0_ready <= 1;
              end
            end
          endcase
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
    $info("  Clock speed %f, period %f", CLOCK_SPEED_MHZ, CLOCK_PERIOD_NANO_SEC);

    if (CLOCK_SPEED_MHZ <= 0 || CLOCK_PERIOD_NANO_SEC <= SETTING_T_CK_MIN_CLOCK_CYCLE_TIME_NANO_SEC) begin
      $error("Invalid clock speed. Quitting");
    end

    $info("--------------------");
    $info("Configured values:");
    $info("  CAS Latency %h", CAS_LATENCY);

    if (CAS_LATENCY != 1 && CAS_LATENCY != 2 && CAS_LATENCY != 3) begin
      $error("Unknown CAS latency");
    end

    $info("  Burst length %h", BURST_LENGTH);

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
    $info("Port values:");
    $info("  Port 0 burst length %d, port width %d", P0_BURST_LENGTH, P0_OUTPUT_WIDTH + 1);

    if (P0_BURST_LENGTH > BURST_LENGTH) begin
      $error("Port 0 burst length exceeds global burst length");
    end

    $info("--------------------");
    $info("Delays:");
    $info("  Cycles until start inhibit %f, clear inhibit %f", CYCLES_UNTIL_START_INHIBIT,
          CYCLES_UNTIL_CLEAR_INHIBIT);

    $info("  Cycles until between active commands %f, command duration %f",
          CYCLES_BETWEEN_ACTIVE_COMMAND, CYCLES_FOR_ACTIVE_ROW);
  end

endmodule
