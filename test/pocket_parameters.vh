parameter tCK              =     6.0; // tCK    ns    Nominal Clock Cycle Time
parameter tCK3_min         =     6.0; // tCK    ns    Nominal Clock Cycle Time
parameter tCK2_min         =    12.0; // tCK    ns    Nominal Clock Cycle Time
// This doesn't exist
parameter tCK1_min         =    12.0; // tCK    ns    Nominal Clock Cycle Time
parameter tAC3             =     5.5; // tAC3   ns    Access time from CLK (pos edge) CL = 3
parameter tAC2             =     6.0; // tAC2   ns    Access time from CLK (pos edge) CL = 2
parameter tAC1             =    22.0; // tAC1   ns    Parameter definition for compilation - CL = 1
// These are not split out in the datasheet, so may not be right
parameter tHZ3             =     6.0; // tHZ3   ns    Data Out High Z time - CL = 3
parameter tHZ2             =     6.0; // tHZ2   ns    Data Out High Z time - CL = 2
parameter tHZ1             =     6.0; // tHZ1   ns    Parameter definition for compilation - CL = 1
parameter tOH              =     2.5; // tOH    ns    Data Out Hold time
parameter tMRD             =     2.0; // tMRD   tCK   Load Mode Register command cycle time (2 * tCK)
parameter tRAS             =    48.0; // tRAS   ns    Active to Precharge command time
parameter tRC              =    60.0; // tRC    ns    Active to Active/Auto Refresh command time
parameter tRFC             =    80.0; // tRFC   ns    Refresh to Refresh Command interval time
parameter tRCD             =    18.0; // tRCD   ns    Active to Read/Write command time
parameter tRP              =    18.0; // tRP    ns    Precharge command period
parameter tRRD             =    12.0; // tRRD   tCK   Active bank a to Active bank b command time (2 * tCK)
// These are not listed separately
parameter tWRa             =    15.0; // tWR    ns    Write recovery time (auto-precharge mode - must add 1 CLK)
parameter tWRm             =    15.0; // tWR    ns    Write recovery time

// Size Parameters

parameter ADDR_BITS        =      13; // Set this parameter to control how many Address bits are used
parameter ROW_BITS         =      13; // Set this parameter to control how many Row bits are used
parameter COL_BITS         =      10; // Set this parameter to control how many Column bits are used
parameter DQ_BITS          =      16; // Set this parameter to control how many Data bits are used
parameter DM_BITS          =       2; // Set this parameter to control how many DM bits are used
parameter BA_BITS          =       2; // Bank bits

parameter mem_sizes = 2**(ROW_BITS+COL_BITS) - 1;

`define x16
