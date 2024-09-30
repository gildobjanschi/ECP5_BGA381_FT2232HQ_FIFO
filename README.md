# ECP5/FT2232HQ Board
This project aims to implement a High Speed USB device using the Lattice Semiconductor ECP5 FPGA coupled with a FT2232HQ operating in synchronous FIFO mode. An [extension board](https://github.com/gildobjanschi/ECP5_BGA381_FT2232HQ_FIFO_EXT) was developed to help validate the design.

## Software
The Verilog software is located in the [/hdl](https://github.com/gildobjanschi/ECP5_BGA381_FT2232HQ_FIFO/tree/main/hdl) directory. The host application that interfaces to the D2XX FTDI driver can be found in the [/host_macosx](https://github.com/gildobjanschi/ECP5_BGA381_FT2232HQ_FIFO/tree/main/host_macosx) directory.

## Project Status
The board is back from manufacturing at PCBWay and it is functional. Read all the details of the bringup steps and testing in the [Wiki](https://github.com/gildobjanschi/ECP5_BGA381_FT2232HQ_FIFO/wiki).

[Schematic PDF](https://github.com/gildobjanschi/ECP5_BGA381_FT2232HQ_FIFO/blob/main/kicad/ECP5.pdf)

![Board rendering](https://github.com/gildobjanschi/ECP5_BGA381_FT2232HQ_FIFO/blob/main/ECP5.jpg)

## How to setup KiCAD
Checkout the project and open it. In the Configure Paths dialog add: Name: ECP5_BGA381_FT2232HQ_FIFO and Path: "The full path to the GitHub directory"/GitHub/ECP5_BGA381_FT2232HQ_FIFO

In the Manage Symbol Libraries click the Project Specific Libraries and add: Name: ECP5_BGA381_FT2232HQ_FIFO and Library Path: ${ECP5_BGA381_FT2232HQ_FIFO}/symbols/Symbols.kicad_sym

In the Manage Footprint Libraries click the Project Specific Libraries and add: Name: ECP5_BGA381_FT2232HQ_FIFO and Library Path: ${ECP5_BGA381_FT2232HQ_FIFO}/footprints/Footprints.pretty
