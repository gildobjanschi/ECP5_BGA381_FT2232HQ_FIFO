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
    echo "Usage: $0 -a -b -t <test number> -p <payload length> -c <count of packets> -e <empty cycles> -f <full cycles> -s <clock period> -u -h [-D <flag>]"
    echo "    -a: Tx board Rev A."
    echo "    -b: Tx board Rev B."
    echo "    -t: Test number (0..2). Test 0: Send from FT2232 to FPGA. Test 1: Send from FT2232 to FPGA and loopback from FPGA. Test 2: Send from FPGA to FT2232."
    echo "    -p: Test payload length (0..63). Default is 63."
    echo "    -c: Test number of packets (1..255). Default is 1."
    echo "    -e: Test 1 and 2 only: number of cycles the FT2232 output FIFO is empty (0..255). Default is 0."
    echo "    -f: Test 2 only: number of cycles the FT2232 input FIFO is full (0..255). Default is 0."
    echo "    -s: The clock period of the application (in ps). Eg. 10000 for 100MHz. Default is 40690 (24.576MHz)."
    echo "    -u: Enable UART debugging."
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
# SPDIF:        SPDIF messages.
# SPDIF_BC:     SPDIF bit clock messages.
# I2S:          I2S messages.
# I2S_BC:       I2S bit clock messages.
# BIG_ENDIAN_SAMPLES    Audio samples received in big endian order.
#OPTIONS="-D SIMULATION -D D_FT2232 -D D_CORE -D D_FT_FIFO -D D_CTRL -D D_SPDIF -D D_SPDIF_BC -D D_I2S -D D_I2S_FRAME -D D_I2S_BC"
OPTIONS="-D SIMULATION -D D_FT2232 -D D_FT_FIFO -D D_CORE -D D_CTRL -D D_SPDIF -D D_I2S -D D_I2S_FRAME"
BOARD=""
OUTPUT_FILE=out.sim

while getopts 'abt:p:c:e:f:s:D:uh' opt; do
    case "$opt" in
        a ) BOARD="BOARD_REV_A" ;;
        b ) BOARD="BOARD_REV_B" ;;
        t ) OPTIONS="$OPTIONS -D TEST_MODE -D TEST_NUMBER=${OPTARG}"
            TEST_MODE="yes" ;;
        p ) OPTIONS="$OPTIONS -D DATA_PACKET_PAYLOAD=6'd${OPTARG}" ;;
        c ) OPTIONS="$OPTIONS -D DATA_PACKETS_COUNT=8'd${OPTARG}" ;;
        e ) OPTIONS="$OPTIONS -D OUT_EMPTY_CYCLES=8'd${OPTARG}" ;;
        f ) OPTIONS="$OPTIONS -D IN_FULL_CYCLES=8'd${OPTARG}" ;;
        s ) OPTIONS="$OPTIONS -D CLK_PERIOD=${OPTARG}" ;;
        u ) OPTIONS="$OPTIONS -D ENABLE_UART" ;;
        D ) OPTIONS="$OPTIONS -D ${OPTARG}" ;;
        h ) helpFunction ;;
        ? ) helpFunction ;; # Print helpFunction in case parameter is non-existent
    esac
done

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

if test -z "$TEST_MODE"; then
    # Normal mode
    iverilog -g2005-sv -D $BOARD $OPTIONS -o $OUTPUT_FILE \
            sim_trellis.sv uart_tx.sv uart_rx.sv utils.sv divider.sv async_fifo.sv tx_spdif.sv tx_i2s.sv control.sv ft2232_fifo.sv audio.sv sim_ft2232.sv sim_audio.sv
else
    # Test mode
    iverilog -g2005-sv -D $BOARD $OPTIONS -o $OUTPUT_FILE \
            sim_trellis.sv uart_tx.sv uart_rx.sv utils.sv async_fifo.sv test_ft2232_fifo.sv audio.sv sim_ft2232.sv sim_audio.sv
fi
if [ $? -eq 0 ]; then
    vvp $OUTPUT_FILE
fi
