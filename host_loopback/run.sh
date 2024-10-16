#!/usr/bin/bash
PACKET_BYTES="1"
PACKET_COUNT="1"
VERBOSE=""

while getopts 'p:c:v' opt; do
    case "$opt" in
        p ) PACKET_BYTES="${OPTARG}" ;;
        c ) PACKET_COUNT="${OPTARG}" ;;
        v ) VERBOSE="-v" ;;
        ? ) echo "Usage: $0 -p <bytes per packet> -c <number of packets> [-v]" ; exit 1 ;;
    esac
done

# Remove drivers that conflict with D2XX drivers
if lsmod | grep -wq "ftdi_sio"; then
    sudo rmmod ftdi_sio
fi
if lsmod | grep -wq "usbserial"; then
    sudo rmmod usbserial
fi

sudo ./ft2232 -c $PACKET_COUNT -p $PACKET_BYTES $VERBOSE
