#!/usr/bin/bash

PACKET_BYTES="1"
BYTES_TO_SEND="1"

while getopts 'p:c:' opt; do
    case "$opt" in
        p ) PACKET_BYTES="${OPTARG}" ;;
        c ) BYTES_TO_SEND="${OPTARG}" ;;
        ? ) echo "Usage: $0 -p <packet bytes> -c bytes to send" ;;
    esac
done

sudo rmmod ftdi_sio
sudo rmmod usbserial
sudo ./ft2232 -c $BYTES_TO_SEND -p $PACKET_BYTES
