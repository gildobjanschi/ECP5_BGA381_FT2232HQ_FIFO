########################################################################################################################
# Configure SIMULATION mode for iverilog with the following command line parameters:
#
# Use -D SIMULATION to enable simulation.
# Use -D D_CORE, D_CORE_FINE for core and trap debug messages
# Use -D GENERATE_VCD to generate a waveform file for GtkWave
#
# Note that all the -D flags above only apply if SIMULATION is enabled. For sythesis none of this flags are used.
########################################################################################################################
#!/usr/bin/bash)

helpFunction()
{
    echo ""
    echo "Usage: $0 -a -b -t <test number> -p <payload length> -c <count of packets> -h [-D <flag>]"
    echo "    -a: Tx board Rev A."
    echo "    -b: Tx board Rev B."
    echo "    -t: Test number (0..2)."
    echo "    -p: Test payload length (0..63)."
    echo "    -c: Test number of packets (1..255)."
    echo "    -h: Help."
    echo "    -D: debug flags (e.g. -D D_CORE ...)"
    exit 1
}

# Flags added by default by the script
#
# SIMULATION:   Use simulation mode.
# FT2232:       FT2232 simulation.
# CORE:         Core debug messages.
# FT_FIFO:      FT2232 FIFO messages.
# FIFO:         Asynchronous FIFO messages.
# CTRL:         Controller messages.
OPTIONS="-D SIMULATION -D D_FT2232 -D D_CORE -D D_FT_FIFO -D D_CTRL"

BOARD=""
OUTPUT_FILE=out.sim
CONTROL_FILE=""

while getopts 'abt:p:c:hD:' opt; do
    case "$opt" in
        a ) BOARD="BOARD_REV_A" ;;
        b ) BOARD="BOARD_REV_B" ;;
        t ) OPTIONS="$OPTIONS -D TEST_MODE -D TEST_NUMBER=${OPTARG}"
            CONTROL_FILE="test_control.sv" ;;
        p ) OPTIONS="$OPTIONS -D DATA_PACKET_PAYLOAD=6'd${OPTARG}" ;;
        c ) OPTIONS="$OPTIONS -D DATA_PACKETS_COUNT=8'd${OPTARG}" ;;
        D ) OPTIONS="$OPTIONS -D ${OPTARG}" ;;
        h ) helpFunction ;;
        ? ) helpFunction ;; # Print helpFunction in case parameter is non-existent
    esac
done

if test -z "$CONTROL_FILE"; then
    CONTROL_FILE="control.sv"
fi

if test -f "$OUTPUT_FILE"; then
    rm $OUTPUT_FILE
fi

if test -z "$BOARD"; then
    BOARD="BOARD_REV_A"
fi

if [ "$BOARD" = "BOARD_REV_A" ] ; then
    echo "Running on Rev A board."
else if [ "$BOARD" = "BOARD_REV_B" ] ; then
    echo "Running on Rev B board."
fi
fi

echo $OPTIONS

iverilog -g2005-sv -D $BOARD $OPTIONS -o $OUTPUT_FILE \
            sim_trellis.sv utils.sv async_fifo.sv $CONTROL_FILE ft2232_fifo.sv audio.sv sim_ft2232.sv sim_top_tx_audio.sv
if [ $? -eq 0 ]; then
    vvp $OUTPUT_FILE
fi
