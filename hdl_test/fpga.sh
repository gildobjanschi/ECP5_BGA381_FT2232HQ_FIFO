########################################################################################################################
# Configure synthesis, binary and FPGA flash.
########################################################################################################################
#!/usr/bin/bash

helpFunction()
{
    echo ""
    echo "Usage: $0 -u -h [-D <flag>]"
    echo "    -u: Enable UART debugging."
    echo "    -h: Help."
    echo "    -D: debug flags (e.g. -D D_CORE ...)"
    exit 1
}

BOARD=""
LPF_FILE=""
SPEED=""
BIN_PATH="/home/gil/tools-oss-cad-suite-0.1.0/bin"
TRELLISD_DB="/home/gil/tools-oss-cad-suite-0.1.0/share/trellis/database"

while getopts 'uh' opt; do
    case "$opt" in
        u ) OPTIONS="$OPTIONS -D ENABLE_UART" ;;
        h ) helpFunction ;;
        ? ) helpFunction ;; # Print helpFunction in case parameter is non-existent
    esac
done

if test -z "$BOARD"; then
    BOARD="BOARD_REV_A"
fi

# Flags added by default by the script
#
if [ "$BOARD" = "BOARD_REV_A" ] ; then
    echo "Running on Rev A board."
    # Enable EXT_A_ENABLED when you have the board
    #OPTIONS="$OPTIONS -D EXT_A_ENABLED"
    LPF_FILE="audio_tx_rev_A.lpf"
    SPEED="6"
else if [ "$BOARD" = "BOARD_REV_B" ] ; then
    echo "Running on Rev B board."
    # Example of adding board specific options
    # Add board specific options
    #echo "OPTIONS: $OPTIONS"
    LPF_FILE="audio_tx_rev_B.lpf"
    SPEED="6"
fi
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

    yosys -p "synth_ecp5 -noabc9 -json out.json" -D $BOARD $OPTIONS utils.sv test_ft2232_fifo.sv audio.sv

    if [ $? -eq 0 ]; then
    nextpnr-ecp5 --package CABGA381 --25k --speed $SPEED --freq 62.50 --json out.json --lpf $LPF_FILE --textcfg out.cfg
    if [ $? -eq 0 ]; then
        ecppack --db $TRELLISD_DB out.cfg out.bit
        if [ $? -eq 0 ]; then
            sudo $BIN_PATH/openFPGALoader -b ulx3s out.bit
        fi
    fi
fi
