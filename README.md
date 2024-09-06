# ECP5/FT2232HQ Board
This project aims to implement a High Speed USB device using the Lattice Semiconductor ECP5 FPGA coupled with a FT2232HQ operating in the synchronous FIFO mode.

## Software
The FPGA Verilog software for the board is currently being developed in a private Github project. Once the board and the code are verified this page will be updated with a link to that project.

## How to setup KiCAD
Checkout the project and open it. In the Configure Paths dialog add: Name: ECP5_TX_AUDIO and Path: "full path to your GitHub directory"/GitHub/ECP5_Tx_Audio_HW

In the Manage Symbol Libraries click the Project Specific Libraries and add: Name: ECP5_TX_AUDIO and Library Path: ${ECP5_TX_AUDIO}/symbols/Symbols.kicad_sym

In the Manage Footprint Libraries click the Project Specific Libraries and add: Name: ECP5_TX_AUDIO and Library Path: ${ECP5_TX_AUDIO}/footprints/Footprints.pretty

## Project Status
The board is coming back from manufacturing soon. 

![Board 3D view](https://github.com/gildobjanschi/ECP5_Tx_Audio/blob/main/ECP5_Audio_Tx.jpg)