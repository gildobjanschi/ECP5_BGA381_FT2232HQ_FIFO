########################################################################################################################
# Configure SIMULATION mode.
########################################################################################################################
#!/usr/bin/bash)

helpFunction()
{
    echo ""
    echo "Usage: $0 -f <bin file name> [-a <FIFO address bits>] [-D <flag>] -h"
    echo "    -f: bin file name."
    echo "    -a: Async FIFO address bits. Default is 5 (32 bytes FIFO)."
    echo "    -D: debug flags (e.g. -D D_CORE ...)"
    echo "    -h: Help."
    exit 1
}

# Flags added by default by the script
#
# SIMULATION:               Use simulation mode.
# D_FT2232:                 FT2232 simulation.
# D_CORE:                   Core debug messages.
# D_FT_FIFO/D_FT_FIFO_FINE: FT2232 FIFO messages.
# D_FIFO:                   Asynchronous FIFO messages.
# D_CTRL:                   Controller messages.
# D_SPDIF:                  SPDIF messages.
# D_SPDIF_BC:               SPDIF bit clock messages.
# D_I2S:                    I2S messages.
# D_I2S_BC:                 I2S bit clock messages.
OPTIONS="-D SIMULATION -D D_FT2232 -D D_CORE -D D_CTRL"
OUTPUT_FILE=out.sim

while getopts 'f:a:D:h' opt; do
    case "$opt" in
        f ) OPTIONS="$OPTIONS -D BIN_FILE_NAME=\"${OPTARG}\"" ;;
        a ) OPTIONS="$OPTIONS -D FIFO_ADDR_BITS=${OPTARG}" ;;
        D ) OPTIONS="$OPTIONS -D ${OPTARG}" ;;
        h ) helpFunction ;;
        ? ) helpFunction ;; # Print helpFunction in case parameter is non-existent
    esac
done

TOOLS_PATH="/home/gil/tools-oss-cad-suite-0.1.0"

# Add BIN_PATH to the path if not already part of the path.
BIN_PATH="${TOOLS_PATH}/bin"

if [ -d "$BIN_PATH" ] && [[ ! $PATH =~ (^|:)$BIN_PATH(:|$) ]]; then
    PATH+=:$BIN_PATH
fi

if test -f "$OUTPUT_FILE"; then
    rm $OUTPUT_FILE
fi

# echo $OPTIONS

iverilog -g2005-sv $OPTIONS -o $OUTPUT_FILE \
            sim_trellis.sv utils.sv async_fifo.sv divider.sv ft2232_fifo.sv control.sv tx_i2s.sv tx_spdif.sv audio.sv sim_ft2232.sv sim_audio.sv
if [ $? -eq 0 ]; then
    vvp $OUTPUT_FILE
fi
