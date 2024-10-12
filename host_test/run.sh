#!/usr/bin/bash
TEST_NUM="0"
PACKET_BYTES="1"
PACKET_COUNT="1"
SEND_SLOW=""
VERBOSE=""

while getopts 't:p:c:sv' opt; do
    case "$opt" in
        t ) TEST_NUM="${OPTARG}" ;;
        p ) PACKET_BYTES="${OPTARG}" ;;
        c ) PACKET_COUNT="${OPTARG}" ;;
        s ) SEND_SLOW="-s" ;;
        v ) VERBOSE="-v" ;;
        ? ) echo "Usage: $0 -t <test number> -p <packet bytes> -c <count of packets> [-s] [-v]" ; exit 1 ;;
    esac
done

sudo rmmod ftdi_sio
sudo rmmod usbserial
sudo ./ft2232 -t $TEST_NUM -p $PACKET_BYTES -c $PACKET_COUNT $SEND_SLOW $VERBOSE
