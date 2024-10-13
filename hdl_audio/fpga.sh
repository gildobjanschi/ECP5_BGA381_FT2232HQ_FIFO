########################################################################################################################
# Configure synthesis, build the bitstream and FPGA flash.
########################################################################################################################
#!/usr/bin/bash

helpFunction()
{
    echo ""
    echo "Usage: $0 [-a <FIFO address bits>] -e -h"
    echo "    -a: Async FIFO address bits. Default is 5 (32 bytes FIFO)."
    echo "    -e: Enable extension."
    echo "    -h: Help."
    exit 1
}

while getopts 'a:eh' opt; do
    case "$opt" in
        a ) OPTIONS="$OPTIONS -D FIFO_ADDR_BITS=${OPTARG}" ;;
        e ) OPTIONS="$OPTIONS -D EXT_A_ENABLED" ;;
        h ) helpFunction ;;
        ? ) helpFunction ;; # Print helpFunction in case parameter is non-existent
    esac
done

TOOLS_PATH="/home/gil/tools-oss-cad-suite-0.1.0"

TRELLISD_DB="${TOOLS_PATH}/share/trellis/database"
# Add BIN_PATH to the path if not already part of the path.
BIN_PATH="${TOOLS_PATH}/bin"

if [ -d "$BIN_PATH" ] && [[ ! $PATH =~ (^|:)$BIN_PATH(:|$) ]]; then
    PATH+=:$BIN_PATH
fi

if test -f "out.bit"; then
    rm out.bit
fi

if test -f "out.cfg"; then
    rm out.cfg
fi

if test -f "out.json"; then
    rm out.json
fi

yosys -p "synth_ecp5 -noabc9 -json out.json" $OPTIONS utils.sv ecp5pll.sv async_fifo.sv divider.sv ft2232_fifo.sv control.sv tx_i2s.sv tx_spdif.sv audio.sv

SPEED="6"
LPF_FILE="audio_tx_rev_A.lpf"

if [ $? -eq 0 ]; then
    nextpnr-ecp5 --package CABGA381 --25k --speed $SPEED --freq 100.00 --json out.json --lpf $LPF_FILE --textcfg out.cfg
    if [ $? -eq 0 ]; then
        ecppack --db $TRELLISD_DB out.cfg out.bit
        if [ $? -eq 0 ]; then
            sudo $BIN_PATH/openFPGALoader -b ulx3s out.bit
        fi
    fi
fi
