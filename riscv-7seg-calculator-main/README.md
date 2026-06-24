# FGMT_RiscV

The FGMT_RiscV is a fine grained multi threading processor that executes Risc-V instructions. Currently the RV32I istruction set is supported, this may be extended in the future.

## Hardware

In the `Hardware` directory the project includes the description of the processor and a small system based on it, all described in VHDL. The system can be synthesized into an FPGA using Vivado, currently an implementation for the BASYS3 board from Digilent is available (see `Hardware/Board/BASYS3/synthese/synthese.xpr`).

The system can run a GDB-Server as thread 0, the binary code for the server is offered in the file `Software/FGMT_GDB_Server.hex` which is used to initialize the program memory.

A synthesized system is offered in `Hardware/FGMT_System_BASYS3.bit` which can be directely downloaded to the BASYS3 board.

## Software

An example program is offered in `Software/FGMT_Example` as an Eclipse project. To use it a workspace must be created (maybe by adapting and using `Eclipse.bat` on Windows after loading and installing the required tools). Then `FGMT_Example` can be imported into the Eclipse workspace and compiled. For executing the project a debug configuration must be set up. See the [screenshots](Software/Setup_Debug_Configuration.pdf) for the correct settings.