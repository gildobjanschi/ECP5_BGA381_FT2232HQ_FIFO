/***********************************************************************************************************************
 * Copyright (c) 2024 Virgil Dobjanschi dobjanschivirgil@gmail.com
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
 * documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
 * rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all copies or substantial portions of
 * the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
 * WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS
 * OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
 * OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 **********************************************************************************************************************/
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/time.h>

#include "ftd2xx.h"

//======================================================================================================================
BOOL rx_data (unsigned int packet_count, unsigned int packet_bytes, unsigned char* rx_buffer, unsigned int rx_bytes,
                    unsigned char verbose);
BOOL tx_data (unsigned int packet_count, unsigned int packet_bytes, unsigned char* tx_buffer,
                    unsigned int* tx_bytes_to_send, unsigned char verbose);

#define USB_BUFFER_SIZE 0x10000
//======================================================================================================================
#define RX_BUFFER_SIZE USB_BUFFER_SIZE
unsigned int bytes_received = 0;
//======================================================================================================================
#define TX_BUFFER_SIZE USB_BUFFER_SIZE
unsigned char out_data = 0;
unsigned char in_data = 0;
BOOL run_test = TRUE;
unsigned int packets_sent = 0;


//======================================================================================================================
int main(int argc, char *argv[]) {
    int opt;
    unsigned int packet_count = 1;
    unsigned int packet_bytes = 1;
    unsigned char verbose = 0;
    if (argc <= 1) {
        printf("Usage: %s [-p <bytes per packet> -c <count of packets> -v]\r\n", argv[0]);
        return 1;
    } else {
        while ((opt = getopt(argc, argv, "c:p:v")) != -1) {
            switch (opt) {
                case 'c': packet_count = strtol (argv[2], NULL, 10); break;
                case 'p': packet_bytes = strtol (argv[4], NULL, 10); break;
                case 'v': verbose = 1; break;
                default: {
                    printf("Usage: %s [-p <bytes per packet> -c <count of packets> -v]\r\n", argv[0]);
                    return 1;
                }
            }
        }
    }

    if (verbose) {
        printf("Packet count: %d, packet bytes: %d\r\n", packet_count, packet_bytes);
    }

    if (packet_bytes > TX_BUFFER_SIZE) {
        printf("Packet size > TX_BUFFER_SIZE (%d)\r\n", TX_BUFFER_SIZE);
        return 1;
    }

    FT_HANDLE ftHandle = NULL;
    FT_STATUS ftStatus;
    unsigned char Mask = 0xff;
    unsigned char Mode;

    ftStatus = FT_Open(0, &ftHandle);
    if(ftStatus != FT_OK) {
        printf("FT_Open failed! %d\r\n", ftStatus);
        return 1;
    }

    // Set interface into FT245 Synchronous FIFO mode
    Mode = 0x00; //reset mode
    ftStatus = FT_SetBitMode(ftHandle, Mask, Mode);
    if (ftStatus != FT_OK) {
        printf("FT_SetBitMode RESET failed! %d\r\n", ftStatus);
        FT_Close(ftHandle);
        return 1;
    }

    usleep(1000000);

    Mode = 0x40; // Sync FIFO mode
    ftStatus = FT_SetBitMode(ftHandle, Mask, Mode);
    if (ftStatus != FT_OK) {
        printf("FT_SetBitMode SYNC FIFO MODE failed! %d\r\n", ftStatus);
        FT_Close(ftHandle);
        return 1;
    }

    FT_SetLatencyTimer(ftHandle, 2);
    FT_SetUSBParameters(ftHandle, USB_BUFFER_SIZE, USB_BUFFER_SIZE);
    FT_SetFlowControl(ftHandle, FT_FLOW_RTS_CTS, 0x0, 0x0);
    FT_Purge(ftHandle, FT_PURGE_RX | FT_PURGE_TX);

    unsigned int EventStatus;
    unsigned int rx_bytes, tx_bytes;
    unsigned int rx_bytes_received;
    unsigned char rx_buffer[RX_BUFFER_SIZE];
    unsigned char tx_buffer[TX_BUFFER_SIZE];

    unsigned int tx_bytes_to_send = 0, tx_bytes_written;
    unsigned int rx_total_bytes_received = 0;
    unsigned int tx_total_bytes_sent = 0;

    // Get the start time
    struct timeval tv_start;
    gettimeofday(&tv_start, NULL);
    long long start_ms = tv_start.tv_sec*1000LL + tv_start.tv_usec/1000;

    while (1) {
        ftStatus = FT_GetStatus (ftHandle, &rx_bytes, &tx_bytes, &EventStatus);
        if (ftStatus != FT_OK) {
            printf("FT_GetStatus failed! %d\r\n", ftStatus);
            FT_Close(ftHandle);
            return 1;
        }

        if (rx_bytes > 0) {
            if (rx_bytes > RX_BUFFER_SIZE) {
                rx_bytes = RX_BUFFER_SIZE;
            }

            ftStatus = FT_Read(ftHandle, rx_buffer, rx_bytes, &rx_bytes_received);
            if (verbose) {
                printf("RD: %d\r\n", rx_bytes_received);
            }
            if (ftStatus != FT_OK || rx_bytes_received != rx_bytes) {
                printf("FT_Read failed! ftStatus = %d; Bytes requested: %d, Bytes received: %d\r\n",
                                    ftStatus, rx_bytes, rx_bytes_received);
                FT_Close(ftHandle);
                return 1;
            }

            rx_total_bytes_received += rx_bytes_received;
            if (FALSE == rx_data (packet_count, packet_bytes, rx_buffer, rx_bytes, verbose)) {
                break;
            }
        }
        if (tx_bytes_to_send == 0) {
            tx_data (packet_count, packet_bytes, tx_buffer, &tx_bytes_to_send, verbose);
        }

        if (tx_bytes_to_send > 0 && USB_BUFFER_SIZE - tx_bytes >= tx_bytes_to_send) {
            ftStatus = FT_Write(ftHandle, tx_buffer, tx_bytes_to_send, &tx_bytes_written);

            if (ftStatus != FT_OK || tx_bytes_written != tx_bytes_to_send) {
                printf("FT_Write failed! ftStatus = %d; Bytes to send: %d, Bytes sent: %d\r\n",
                                    ftStatus, tx_bytes_to_send, tx_bytes_written);
                FT_Close(ftHandle);
                return 1;
            }

            if (verbose) {
                printf("WR: %d\r\n", tx_bytes_written);
            }

            tx_total_bytes_sent += tx_bytes_written;
/*
            // If we don't want to wait for the loopback data this code is useful in breaking out of the while loop.
            if (tx_total_bytes_sent == packet_bytes * packet_count) {
                break;
            }
*/
            // This buffer was sent
            tx_bytes_to_send = 0;
        }
    }

    // Get the stop time
    struct timeval tv_stop;
    gettimeofday(&tv_stop, NULL);
    long long stop_ms = tv_stop.tv_sec*1000LL + tv_stop.tv_usec/1000;
    long duration = (long)(stop_ms - start_ms);

    printf("%d bytes sent, %d bytes received in %ld ms. Tx: %ld KBps, Rx: %ld KBps\r\n",
                tx_total_bytes_sent, rx_total_bytes_received, duration, tx_total_bytes_sent / duration,
                rx_total_bytes_received / duration);

    FT_Close(ftHandle);

    return 0;
}

//======================================================================================================================
BOOL rx_data (unsigned int packet_count, unsigned int packet_bytes, unsigned char* rx_buffer, unsigned int rx_bytes,
                unsigned char verbose) {
    for (unsigned int i = 0; i < rx_bytes; i++) {
        if (rx_buffer[i] == in_data) {
            if (verbose) {
                printf("Recv: %d\r\n", rx_buffer[i]);
            }
        } else {
            printf("Recv: %d, exp: %d\r\n", rx_buffer[i], in_data);
            return FALSE;
        }
        in_data += 1;
    }
    bytes_received += rx_bytes;
    if (verbose) {
        printf("RD: %d of %d\r\n", bytes_received, packet_count * packet_bytes);
    }

    if (bytes_received == packet_count * packet_bytes) {
        printf("==== Test successful ====\r\n");
        return FALSE;
    }
    return TRUE;
}

//======================================================================================================================
BOOL tx_data (unsigned int packet_count, unsigned int packet_bytes, unsigned char* tx_buffer,
                    unsigned int* tx_bytes_to_send, unsigned char verbose) {
    if (run_test) {
        for (unsigned int i = 0; i < packet_bytes; i++) {
            tx_buffer[i] = out_data;
            if (verbose) {
                printf("Send: %d\r\n", out_data);
            }
            out_data += 1;
        }

        *tx_bytes_to_send = packet_bytes;
        packets_sent += 1;

        if (packets_sent == packet_count) {
            // Done sending data
            run_test = FALSE;
            printf("Done sending %d packets\r\n", packet_count);
        }
    } else {
        *tx_bytes_to_send = 0;
    }

    return TRUE;
}

