#!/usr/bin/bash

WAV_FILE_NAME="1"
OUTPUT_PORT="0"

while getopts 'f:o:' opt; do
    case "$opt" in
        f ) WAV_FILE_NAME="${OPTARG}" ;;
        o ) OUTPUT_PORT="${OPTARG}" ;;
        ? ) echo "Usage: $0 -f <WAV file name> -o <output port>" ;;
    esac
done

if lsmod | grep -wq "ftdi_sio"; then
	sudo rmmod ftdi_sio
fi
if lsmod | grep -wq "usbserial"; then
	sudo rmmod usbserial
fi
sudo ./ft2232 -f $WAV_FILE_NAME -o $OUTPUT_PORT
