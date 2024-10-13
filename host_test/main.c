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
BOOL rx_data (unsigned char* rx_buffer, unsigned int rx_bytes, unsigned char verbose, BOOL* pStopped);
BOOL tx_data (int test_number, unsigned char payload_length, unsigned char packet_count,
                        unsigned char* tx_buffer, unsigned int* tx_bytes_to_send);
BOOL tx_data_slow (int test_number, unsigned char payload_length, unsigned char packet_count,
                        unsigned char* tx_buffer, unsigned int* tx_bytes_to_send);

//======================================================================================================================
#define RX_BUFFER_SIZE 512

unsigned int payload_received = 0;
unsigned char next_rx_value = 0;
unsigned int rx_payload_length = 0;
unsigned char last_rx_cmd;

// Commands from the FPGA to the host.
#define CMD_FPGA_DATA           0x40
#define CMD_FPGA_LOOPBACK       0x80
#define CMD_FPGA_STOPPED        0xc0

// Receive state machines
#define STATE_RX_CMD               1
#define STATE_RX_STREAM_PAYLOAD    2
#define STATE_RX_LOOPBACK_PAYLOAD  3
#define STATE_RX_STOPPED_PAYLOAD   4
#define STATE_RX_STOPPED           5
unsigned char rx_state_m = STATE_RX_CMD;
//======================================================================================================================
#define TX_BUFFER_SIZE 512

unsigned char next_tx_value = 0;
unsigned char packets_sent = 0;

// Commands from the host to the FPGA; bits[7:6] represent the command and bits[5:0] represent the length of the packet.
#define CMD_HOST_START          0x00
#define CMD_HOST_DATA           0x40
#define CMD_HOST_STOP           0x80

// Send state machines
#define STATE_TX_START_CMD         1
#define STATE_TX_STREAM_CMD        2
#define STATE_TX_STOP_CMD          3
#define STATE_TX_STOPPED           4
unsigned char tx_state_m = STATE_TX_START_CMD;

unsigned int slow_tx_bytes_to_send = 0;
unsigned int slow_index = 0;
unsigned char slow_tx_buffer[TX_BUFFER_SIZE];
BOOL send_slow = FALSE;

//======================================================================================================================
int main(int argc, char *argv[]) {
    FT_HANDLE ftHandle = NULL;
    FT_STATUS ftStatus;
    unsigned char Mask = 0xff;
    unsigned char Mode;

    int opt;
    int test_number;
    unsigned char payload_length = 1;
    unsigned char packet_count = 1;
    unsigned char verbose = 0;
    if (argc <= 1) {
        printf("Usage: %s -t test number [-p payload length] [-c packet count] [-s send slow] [-v]\r\n", argv[0]);
        return 1;
    } else {
        while ((opt = getopt(argc, argv, "t:p:c:sv")) != -1) {
            switch (opt) {
                case 't': test_number = strtol (argv[2], NULL, 10); break;
                case 'p': payload_length = strtol (argv[4], NULL, 10); break;
                case 'c': packet_count = strtol (argv[6], NULL, 10); break;
                case 's': send_slow = TRUE; break;
                case 'v': verbose = 1; break;
                default: {
                    printf("Usage: %s -t test number [-p payload length] [-c packet count] [-s send slow]\r\n", argv[0]);
                    return 1;
                }
            }
        }
    }

    if (verbose) {
        printf("Test number: %d, payload length: %d, packet count: %d\r\n", test_number, payload_length, packet_count);
    }

    ftStatus = FT_Open(0, &ftHandle);
    if(ftStatus != FT_OK) {
        printf("FT_Open failed! %d\r\n", ftStatus);
        return 1;
    }

    // Set interface into FT245 synchronous FIFO mode
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
    FT_SetUSBParameters(ftHandle,0x10000, 0x10000);
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

    printf("Start sending.\r\n");
    // Get the start time
    struct timeval tv_start;
    gettimeofday(&tv_start, NULL);
    long long start_ms = tv_start.tv_sec*1000LL + tv_start.tv_usec/1000;

    BOOL rx_stopped = FALSE;
    while (TRUE) {
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
            if (ftStatus != FT_OK || rx_bytes_received != rx_bytes) {
                printf("FT_Read failed! ftStatus = %d; Bytes requested: %d, Bytes received: %d\r\n",
                                    ftStatus, rx_bytes, rx_bytes_received);
                FT_Close(ftHandle);
                return 1;
            }

            rx_total_bytes_received += rx_bytes_received;
            if (FALSE == rx_data (rx_buffer, rx_bytes, verbose, &rx_stopped)) {
                FT_Close(ftHandle);
                return 1;
            }

            if (rx_stopped) {
                break;
            }
        }

        if (tx_bytes_to_send == 0) {
            if (send_slow) {
                tx_data_slow (test_number, payload_length, packet_count, tx_buffer, &tx_bytes_to_send);
            } else {
                tx_data (test_number, payload_length, packet_count, tx_buffer, &tx_bytes_to_send);
            }
        }

        // Although the RX and TX buffers are 4KB, they only use 2x 512 bytes for each buffer under FT245
        // synchronous FIFO mode.
        if (tx_bytes_to_send > 0 && 512 - tx_bytes >= tx_bytes_to_send) {
            ftStatus = FT_Write(ftHandle, tx_buffer, tx_bytes_to_send, &tx_bytes_written);
            if (ftStatus != FT_OK || tx_bytes_written != tx_bytes_to_send) {
                printf("FT_Write failed! ftStatus = %d; Bytes to send: %d, Bytes sent: %d\r\n",
                                    ftStatus, tx_bytes_to_send, tx_bytes_written);
                FT_Close(ftHandle);
                return 1;
            }

            tx_total_bytes_sent += tx_bytes_written;
            if (verbose) {
                for (unsigned int i = 0; i < tx_bytes_to_send; i++) {
                    printf ("Sending: %d\r\n", tx_buffer[i]);
                }
            }

            if (send_slow) {
                usleep(1000000);
            }

            // This buffer was sent
            tx_bytes_to_send = 0;
        }
    }

    // Get the stop time
    struct timeval tv_stop;
    gettimeofday(&tv_stop, NULL);
    long long stop_ms = tv_stop.tv_sec*1000LL + tv_stop.tv_usec/1000;
    long duration = (long)(stop_ms - start_ms);
    printf("%d bytes sent, %d bytes received in %ld ms. Tx: %ld Kbps, Rx: %ld Kbps\r\n",
                tx_total_bytes_sent, rx_total_bytes_received, duration, (tx_total_bytes_sent * 8) / duration,
                (rx_total_bytes_received * 8) / duration);

    FT_Close(ftHandle);

    return 0;
}

//======================================================================================================================
BOOL rx_data (unsigned char* rx_buffer, unsigned int rx_bytes, unsigned char verbose, BOOL* pStopped) {
    *pStopped = FALSE;

    for (unsigned int i = 0; i < rx_bytes; i++) {
        switch (rx_state_m) {
            case STATE_RX_CMD: {
                payload_received = 0;

                last_rx_cmd = rx_buffer[i] & 0xc0;
                rx_payload_length = rx_buffer[i] & 0x3f;
                switch (last_rx_cmd) {
                    case CMD_FPGA_DATA: {
                        if (verbose) {
                            printf("CMD_FPGA_DATA with payload: %d bytes\r\n", rx_payload_length);
                        }
                        rx_state_m = STATE_RX_STREAM_PAYLOAD;
                        break;
                    }

                    case CMD_FPGA_LOOPBACK: {
                        if (verbose) {
                            printf("CMD_FPGA_LOOPBACK with payload: %d bytes\r\n", rx_payload_length);
                        }
                        rx_state_m = STATE_RX_LOOPBACK_PAYLOAD;
                        break;
                    }

                    case CMD_FPGA_STOPPED: {
                        if (verbose) {
                            printf("CMD_FPGA_STOPPED with payload: %d bytes\r\n", rx_payload_length);
                        }
                        rx_state_m = STATE_RX_STOPPED_PAYLOAD;
                        break;
                    }

                    default: {
                        printf("Bad command: %d with payload: %d bytes\r\n", last_rx_cmd, rx_payload_length);
                        return FALSE;
                    }
                }

                break;
            }

            case STATE_RX_STREAM_PAYLOAD: {
                if (verbose) {
                    printf("STATE_RX_STREAM_PAYLOAD: %d\r\n", rx_buffer[i]);
                }

                if (rx_buffer[i] != next_rx_value) {
                    printf("Got: %d, Expected: %d\r\n", rx_buffer[i], next_rx_value);
                    return FALSE;
                }
                next_rx_value += 1;

                payload_received += 1;
                if (payload_received == rx_payload_length) {
                    rx_state_m = STATE_RX_CMD;
                }

                break;
            }

            case STATE_RX_LOOPBACK_PAYLOAD: {
                if (verbose) {
                    printf("STATE_RX_LOOPBACK_PAYLOAD: %d\r\n", rx_buffer[i]);
                }

                payload_received += 1;
                if (payload_received == rx_payload_length) {
                    rx_state_m = STATE_RX_CMD;
                }

                break;
            }

            case STATE_RX_STOPPED_PAYLOAD: {
                if (payload_received == 0) {
                    if (rx_buffer[i] == 0) {
                        printf("===== Test OK =====\r\n");
                    } else {
                        printf("===== Test failed (error code %d) =====\r\n", rx_buffer[i]);
                    }
                } else {
                    printf("STATE_RX_STOPPED_PAYLOAD [%d]: %d\r\n", payload_received, rx_buffer[i]);
                }

                payload_received += 1;
                if (payload_received == rx_payload_length) {
                    rx_state_m = STATE_RX_STOPPED;
                    *pStopped = TRUE;
                }
                break;
            }

            case STATE_RX_STOPPED: {
                *pStopped = TRUE;
                break;
            }
        }
    }

    return TRUE;
}

//======================================================================================================================
BOOL tx_data_slow (int test_number, unsigned char payload_length, unsigned char packet_count,
                        unsigned char* tx_buffer, unsigned int* tx_bytes_to_send) {
    if (slow_index < slow_tx_bytes_to_send) {
        tx_buffer[0] = slow_tx_buffer[slow_index];
        *tx_bytes_to_send = 1;

        slow_index += 1;
    } else {
        slow_index = 0;
        tx_data (test_number, payload_length, packet_count, slow_tx_buffer, &slow_tx_bytes_to_send);
        if (slow_tx_bytes_to_send > 0) {
            tx_buffer[0] = slow_tx_buffer[0];
            *tx_bytes_to_send = 1;

            slow_index += 1;
        } else {
            *tx_bytes_to_send = 0;
        }
    }
    return TRUE;
}

//======================================================================================================================
BOOL tx_data (int test_number, unsigned char payload_length, unsigned char packet_count,
                        unsigned char* tx_buffer, unsigned int* tx_bytes_to_send) {
    switch (tx_state_m) {
        case STATE_TX_START_CMD: {
            tx_buffer[0] = CMD_HOST_START | 3;
            tx_buffer[1] = test_number;
            tx_buffer[2] = payload_length;
            tx_buffer[3] = packet_count;

            *tx_bytes_to_send = 4;

            if (test_number == 0 || test_number == 1) {
                if (packet_count > 0) {
                    tx_state_m = STATE_TX_STREAM_CMD;
                } else {
                    // Don't send data
                    tx_state_m = STATE_TX_STOP_CMD;
                }
            } else {
                // No more data to send for test 2
                tx_state_m = STATE_TX_STOPPED;
            }
            break;
        }

        case STATE_TX_STREAM_CMD: {
            tx_buffer[0] = (unsigned char) CMD_HOST_DATA | payload_length;
            for (int i = 1; i < payload_length + 1; i++) {
                tx_buffer[i] = next_tx_value;
                next_tx_value += 1;
            }

            *tx_bytes_to_send = payload_length + 1;

            packets_sent = packets_sent + 1;
            if (packets_sent == packet_count) {
                tx_state_m = STATE_TX_STOP_CMD;
            }
            break;
        }

        case STATE_TX_STOP_CMD: {
            tx_buffer[0] = CMD_HOST_STOP;

            *tx_bytes_to_send = 1;

            tx_state_m = STATE_TX_STOPPED;
            break;
        }

        case STATE_TX_STOPPED: {
            // No more data to send
            *tx_bytes_to_send = 0;
            break;
        }
    }

    return TRUE;
}

