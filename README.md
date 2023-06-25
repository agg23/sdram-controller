# SDRAM Controller

This is designed to be a guaranteed timing-accurate SDRAM controller. I was frustrated with the other controllers I could find, in terms of their licensing (most are GPL), their lack of calculations of proper timings, and their general readability/comments. Every time I had trouble with other popular controllers for FPGA retrogaming, I wasn't sure if I had done something wrong, or if the controller was not properly set up for my SDRAM.

> **Warning**: Controllers are not highly tested in sims or in production
>
> If you decide to use these controllers, beware that there may be some subtle bugs that I haven't encountered. I have pretty thoroughly tested (in production) the `sdram_burst` controller at both `CAS Latency = 2 and 3`, and have used the standard controller at both `CAS Latency = 2 and 3` as well. If you find or suspect an bug, please feel free to open an issue.
> 

# Features

* Customizable SDRAM `mode` settings
* Calculation and implementation of required cycle counts for your given clock speed
* Parameterized `t` constraint calculations
* Full-page burst mode controller in `sdram_burst.sv` - Which is currently in use in https://github.com/agg23/fpga-gameandwatch

Neither controller has multiple ports, but the controller design should lend itself to easily adding port functionality.

# Test

Both controllers have had basic validation against Micron's SDRAM testbench. It's generally rather lacking and doesn't test some important metrics like timing, but it was useful in getting started and validating some ideas.

The SDRAM test structure ([taken from Micron](https://www.micron.com/products/dram/sdram/part-catalog/mt48lc16m16a2b4-6a)) has been modified in `sdr_parameters.vh`. Intel's simulation tool, ModelSim/Questa, did not like certain defines being on the same line as other preprocessor directives, so they've been moved.