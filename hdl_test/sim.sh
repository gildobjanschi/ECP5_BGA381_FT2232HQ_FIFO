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
    echo "Usage: $0 -t <test number> -p <payload length> -c <count of packets> [-f <FIFO address bits>] [-s <clock period>] [-D <flag>] -l -h"
    echo "    -t: Test number (0..2). Test 0: Send from FT2232 to FPGA. Test 1: Send from FT2232 to FPGA and loopback from FPGA. Test 2: Send from FPGA to FT2232."
    echo "    -p: Test payload length (0..63). Default is 63."
    echo "    -c: Test number of packets (1..255). Default is 1."
    echo "    -f: Async FIFO address bits. Default is 5 (32 bytes FIFO)."
    echo "    -s: The clock period of the application (in ps). Eg. 10000 for 100MHz. Default is 40690 (24.576MHz)."
    echo "    -D: debug flags (e.g. -D D_CORE ...)"
    echo "    -l Loopback mode."
    echo "    -h: Help."
    exit 1
}

# Flags added by default by the script
#
# SIMULATION:              Use simulation mode.
# D_FT2232:                FT2232 simulation messages.
# D_CORE:                  Core debug messages.
# D_FT_FIFO/FT_FIFO_FINE:  FT2232 FIFO messages.
# D_FIFO:                  Asynchronous FIFO messages.
# D_CTRL:                  Controller messages.
OPTIONS="-D SIMULATION -D D_FT2232 -D D_FT_FIFO -D D_CORE -D D_CTRL"
OUTPUT_FILE=out.sim
CONTROL=""
TOOLS_PATH="/home/gil/tools-oss-cad-suite-0.1.0"

# Add BIN_PATH to the path if not already part of the path.
BIN_PATH="${TOOLS_PATH}/bin"

if [ -d "$BIN_PATH" ] && [[ ! $PATH =~ (^|:)$BIN_PATH(:|$) ]]; then
    PATH+=:$BIN_PATH
fi

while getopts 't:p:c:f:s:D:lh' opt; do
    case "$opt" in
        t ) OPTIONS="$OPTIONS -D TEST_NUMBER=${OPTARG}" ;;
        p ) OPTIONS="$OPTIONS -D DATA_PACKET_PAYLOAD=6'd${OPTARG}" ;;
        c ) OPTIONS="$OPTIONS -D DATA_PACKETS_COUNT=8'd${OPTARG}" ;;
        f ) OPTIONS="$OPTIONS -D FIFO_ADDR_BITS=${OPTARG}" ;;
        s ) OPTIONS="$OPTIONS -D CLK_PERIOD=${OPTARG}" ;;
        D ) OPTIONS="$OPTIONS -D ${OPTARG}" ;;
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

if test -f "$OUTPUT_FILE"; then
    rm $OUTPUT_FILE
fi

iverilog -g2005-sv $OPTIONS -o $OUTPUT_FILE \
            sim_trellis.sv utils.sv async_fifo.sv ft2232_fifo.sv $CONTROL audio.sv sim_ft2232.sv sim_audio.sv
if [ $? -eq 0 ]; then
    vvp $OUTPUT_FILE
fi
