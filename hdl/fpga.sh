########################################################################################################################
# Configure synthesis, binary and FPGA flash.
########################################################################################################################
#!/usr/bin/bash

helpFunction()
{
    echo ""
    echo "Usage: $0 -a -b --t -h [-D <flag>]"
    echo "    -a: Tx board rev A."
    echo "    -b: Tx board rev B."
    echo "    -t: Test mode."
    echo "    -h: Help."
    echo "    -D: debug flags (e.g. -D D_CORE ...)"
    exit 1
}

BOARD=""
LPF_FILE=""
SPEED=""
TRELLISD_DB="/Users/virgildobjanschi/tools-oss-cad-suite-0.1.0/share/trellis/database"
MODE="NORMAL"

while getopts 'abthD:' opt; do
    case "$opt" in
        a ) BOARD="BOARD_REV_A" ;;
        b ) BOARD="BOARD_REV_B" ;;
        t ) OPTIONS="$OPTIONS -D TEST_MODE" ;;
        D ) OPTIONS="$OPTIONS -D ${OPTARG}" ;;
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
    # Add board specific options
    OPTIONS="$OPTIONS -D ENABLE_UART"
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

yosys -p "synth_ecp5 -noabc9 -json out.json" -D $BOARD $OPTIONS -D $MODE\
        utils.sv async_fifo.sv tx.sv ft2232_fifo.sv audio.sv
if [ $? -eq 0 ]; then
    nextpnr-ecp5 --package CABGA381 --25k --speed $SPEED --freq 62.50 --json out.json --lpf $LPF_FILE --textcfg out.cfg
    if [ $? -eq 0 ]; then
        ecppack --db $TRELLISD_DB out.cfg out.bit
        if [ $? -eq 0 ]; then
            openFPGALoader -b ulx3s out.bit
        fi
    fi
fi
