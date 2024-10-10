########################################################################################################################
# Configure synthesis, binary and FPGA flash.
########################################################################################################################
#!/usr/bin/bash

helpFunction()
{
    echo ""
    echo "Usage: $0 [-f <FIFO address bits>] -l -h"
    echo "    -f: Async FIFO address bits. Default is 5 (32 bytes FIFO)."
    echo "    -l Loopback mode."
    echo "    -h: Help."
    exit 1
}

CONTROL=""
SPEED="6"
LPF_FILE="audio_tx_rev_A.lpf"
TOOLS_PATH="/home/gil/tools-oss-cad-suite-0.1.0"


TRELLISD_DB="${TOOLS_PATH}/share/trellis/database"
# Add BIN_PATH to the path if not already part of the path.
BIN_PATH="${TOOLS_PATH}/bin"

if [ -d "$BIN_PATH" ] && [[ ! $PATH =~ (^|:)$BIN_PATH(:|$) ]]; then
    PATH+=:$BIN_PATH
fi

while getopts 'f:lh' opt; do
    case "$opt" in
        f ) OPTIONS="$OPTIONS -D FIFO_ADDR_BITS=${OPTARG}" ;;
        l ) CONTROL="control_loopback.sv" ;;
        h ) helpFunction ;;
        ? ) helpFunction ;; # Print helpFunction in case parameter is non-existent
    esac
done

# Select which control module to use.
# control_test.sv for running 3 tests or control_loopback.sv for looping back host data.
# The default is control_test.sv.
if [ -z "$CONTROL" ]; then
    CONTROL="control_test.sv"
fi

# Remove intermediary build files.
if test -f "out.bit"; then
    rm out.bit
fi

if test -f "out.cfg"; then
    rm out.cfg
fi

if test -f "out.json"; then
    rm out.json
fi

# Build the code.
yosys -p "synth_ecp5 -noabc9 -json out.json" $OPTIONS utils.sv async_fifo.sv $CONTROL ft2232_fifo.sv audio.sv

if [ $? -eq 0 ]; then
    nextpnr-ecp5 --package CABGA381 --25k --speed $SPEED --freq 62.50 --json out.json --lpf $LPF_FILE --textcfg out.cfg
    if [ $? -eq 0 ]; then
        ecppack --db $TRELLISD_DB out.cfg out.bit
        if [ $? -eq 0 ]; then
            sudo $BIN_PATH/openFPGALoader -b ulx3s out.bit
        fi
    fi
fi
