#!/usr/bin/bash
PACKET_BYTES="1"
PACKET_COUNT="1"

while getopts 'p:c:' opt; do
    case "$opt" in
        p ) PACKET_BYTES="${OPTARG}" ;;
        c ) PACKET_COUNT="${OPTARG}" ;;
        ? ) echo "Usage: $0 -p <bytes per packet> -c <number of packets>" ; exit 1 ;;
    esac
done

# Remove drivers that conflict with D2XX drivers
sudo rmmod ftdi_sio
sudo rmmod usbserial

sudo ./ft2232 -c $PACKET_COUNT -p $PACKET_BYTES
