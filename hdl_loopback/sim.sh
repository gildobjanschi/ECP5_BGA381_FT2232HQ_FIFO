########################################################################################################################
# Configure SIMULATION mode for iverilog with the following command line parameters:
#
# Use -D SIMULATION to enable simulation.
# Use -D D_CORE, D_CORE_FINE for core and trap debug messages
# Use -D GENERATE_VCD to generate a waveform file for GtkWave
########################################################################################################################
#!/usr/bin/bash)

helpFunction()
{
    echo ""
    echo "Usage: $0 -p <bytes to send> -h [-D <flag>]"
    echo "    -p: Test bytes to send (1..255). Default is 1."
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
OPTIONS="-D SIMULATION -D D_FT2232 -D D_FT_FIFO -D D_CORE"
BOARD=""
OUTPUT_FILE=out.sim
TOOLS_PATH="/home/gil/tools-oss-cad-suite-0.1.0"

# Add BIN_PATH to the path if not already part of the path.
BIN_PATH="${TOOLS_PATH}/bin"

# Add BIN_PATH to the path if not already part of the path.
if [ -d "$BIN_PATH" ] && [[ ! $PATH =~ (^|:)$BIN_PATH(:|$) ]]; then
    PATH+=:$BIN_PATH
fi

while getopts 'p:h' opt; do
    case "$opt" in
        p ) OPTIONS="$OPTIONS -D DATA_BYTES_TO_SEND=8'd${OPTARG}" ;;
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

iverilog -g2005-sv -D $BOARD $OPTIONS -o $OUTPUT_FILE \
        sim_trellis.sv utils.sv test_ft2232_fifo.sv audio.sv sim_ft2232.sv sim_audio.sv

if [ $? -eq 0 ]; then
    vvp $OUTPUT_FILE
fi
