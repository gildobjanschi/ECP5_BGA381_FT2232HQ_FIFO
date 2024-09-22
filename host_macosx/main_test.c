/*
 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include "ftd2xx.h"

//======================================================================================================================
BOOL check_rx_data (unsigned char* rx_buffer, unsigned int rx_bytes, BOOL* pStopped);
BOOL tx_data (int test_number, unsigned char send_payload_length, unsigned int send_packet_count,
                        unsigned char* tx_buffer, unsigned int* tx_bytes_to_send);

unsigned int payload_received = 0;
unsigned int rx_payload_length = 0;
unsigned char next_rx_value = 0;
unsigned char last_rx_cmd;

// Commands from the FPGA to the host.
#define CMD_RX_TEST_DATA          0x40
#define CMD_RX_TEST_STOPPED       0xc0

#define STATE_RX_CMD               1
#define STATE_RX_STREAM_PAYLOAD    2
#define STATE_RX_STOPPED_PAYLOAD   3
unsigned char rx_state_m = STATE_RX_CMD;

#define RX_BUFFER_SIZE 64
//======================================================================================================================
unsigned char next_tx_value = 0;
unsigned int packets_sent = 0;
// Command byte bits[7:6]. Bits[5:0] represent the length of the frame.
#define CMD_TX_TEST_START         0x00
#define CMD_TX_TEST_DATA          0x40
#define CMD_TX_TEST_STOP          0x80


#define STATE_TX_START_CMD         1
#define STATE_TX_STREAM_CMD        2
#define STATE_TX_STOP_CMD          3
#define STATE_TX_DONE              4
unsigned char tx_state_m = STATE_TX_START_CMD;

#define TX_BUFFER_SIZE 64
//======================================================================================================================
int main(int argc, char *argv[])
{
    FT_HANDLE ftHandle = NULL;
    FT_STATUS ftStatus;
    unsigned char Mask = 0xff;
    unsigned char Mode;

    int opt;
    int test_number;
    unsigned char send_payload_length = 1;
    unsigned int send_packet_count = 1;
    if (argc <= 1) {
        printf("Usage: %s -t test number [-p send payload length] [-c send packet count]\r\n", argv[0]);
        return 1;
    } else {
        while ((opt = getopt(argc, argv, "t:p:c:")) != -1) {
            switch (opt) {
                case 't': test_number = strtol (argv[2], NULL, 10); break;
                case 'p': send_payload_length = strtol (argv[4], NULL, 10); break;
                case 'c': send_packet_count = strtol (argv[6], NULL, 10); break;
                default: {
                    printf("Usage: %s -t test number [-p send payload length] [-c send packet count]\r\n", argv[0]);
                    return 1;
                }
            }
        }
    }

    printf("Test number: %d, send payload length: %d, packet count: %d\r\n",
                            test_number, send_payload_length, send_packet_count);

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
    FT_SetUSBParameters(ftHandle,0x10000, 0x10000);
    FT_SetFlowControl(ftHandle, FT_FLOW_RTS_CTS, 0x0, 0x0);
    FT_Purge(ftHandle, FT_PURGE_RX);

    unsigned int EventStatus;
    unsigned int rx_bytes;
    unsigned int tx_bytes;
    unsigned int rx_bytes_received;
    unsigned char rx_buffer[RX_BUFFER_SIZE];
    unsigned char tx_buffer[TX_BUFFER_SIZE];
    unsigned int tx_bytes_to_send = 0, tx_bytes_written;
    BOOL rx_stopped = FALSE;
    while (!rx_stopped) {
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

            if (FALSE == check_rx_data (rx_buffer, rx_bytes, &rx_stopped)) {
                FT_Close(ftHandle);
                return 1;
            }
        }

        /* Although the RX and TX buffers are 4KB, they only use 2x 512 bytes for each buffer under FT245
         * Synchronous FIFO mode.
         */
        if (tx_bytes_to_send == 0) {
            tx_data (test_number, send_payload_length, send_packet_count, tx_buffer, &tx_bytes_to_send);
        }

        if (tx_bytes_to_send > 0 && 512 - tx_bytes >= tx_bytes_to_send) {
            ftStatus = FT_Write(ftHandle, tx_buffer, tx_bytes_to_send, &tx_bytes_written);
            if (ftStatus != FT_OK || tx_bytes_written != tx_bytes_to_send) {
                printf("FT_Write FAILED! ftStatus = %d; Bytes to send: %d, Bytes sent: %d\r\n",
                                    ftStatus, tx_bytes_to_send, tx_bytes_written);
                FT_Close(ftHandle);
                return 1;
            }

            // This buffer was sent
            tx_bytes_to_send = 0;
        }
    }

    FT_Close(ftHandle);

    return 0;
}

//======================================================================================================================
BOOL check_rx_data (unsigned char* rx_buffer, unsigned int rx_bytes, BOOL* pStopped) {
    *pStopped = FALSE;

    for (unsigned int i = 0; i < rx_bytes; i++) {
        switch (rx_state_m) {
            case STATE_RX_CMD: {
                payload_received = 0;

                last_rx_cmd = rx_buffer[i] & 0xc0;
                rx_payload_length = rx_buffer[i] & 0x3f;
                switch (last_rx_cmd) {
                    case CMD_RX_TEST_DATA: {
                        printf("CMD_RX_TEST_DATA with payload: %d\r\n", rx_payload_length);
                        rx_state_m = STATE_RX_STREAM_PAYLOAD;
                        break;
                    }

                    case CMD_RX_TEST_STOPPED: {
                        printf("CMD_RX_TEST_STOPPED with payload: %d\r\n", rx_payload_length);
                        if (rx_payload_length != 1) {
                            return FALSE;
                        } else {
                            rx_state_m = STATE_RX_STOPPED_PAYLOAD;
                        }
                        break;
                    }

                    default: {
                        printf("Bad command: %d with payload: %d\r\n", last_rx_cmd, rx_payload_length);
                        return FALSE;
                    }
                }

                break;
            }

            case STATE_RX_STREAM_PAYLOAD: {
                printf("STATE_RX_STREAM_PAYLOAD: %d\r\n", rx_buffer[i]);
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

            case STATE_RX_STOPPED_PAYLOAD: {
                printf("STATE_RX_STOPPED_PAYLOAD. Error code: %d\r\n", rx_buffer[i]);
                if (rx_buffer[i] == 0) {
                    printf("===== Test OK =====\r\n");
                } else {
                    printf("===== Test FAILED (error code %d) =====\r\n", rx_buffer[i]);
                }

                rx_state_m = STATE_RX_CMD;
                *pStopped = TRUE;
                break;
            }
        }
    }

    return TRUE;
}

//======================================================================================================================
BOOL tx_data (int test_number, unsigned char send_payload_length, unsigned int send_packet_count,
                        unsigned char* tx_buffer, unsigned int* tx_bytes_to_send) {
    if (test_number == 0 || test_number == 1) {
        switch (tx_state_m) {
            case STATE_TX_START_CMD: {
                tx_buffer[0] = CMD_TX_TEST_START | 1;
                tx_buffer[1] = test_number;

                *tx_bytes_to_send = 2;

                tx_state_m = STATE_TX_STREAM_CMD;
                break;
            }

            case STATE_TX_STREAM_CMD: {
                tx_buffer[0] = (unsigned char) CMD_TX_TEST_DATA | send_payload_length;
                for (int i = 1; i < send_payload_length + 1; i++) {
                    tx_buffer[i] = next_tx_value;
                    next_tx_value += 1;
                }

                *tx_bytes_to_send = send_payload_length + 1;

                packets_sent = packets_sent + 1;
                if (packets_sent == send_packet_count) {
                    tx_state_m = STATE_TX_STOP_CMD;
                }
                break;
            }

            case STATE_TX_STOP_CMD: {
                tx_buffer[0] = CMD_TX_TEST_STOP;

                *tx_bytes_to_send = 1;

                tx_state_m = STATE_TX_DONE;
                break;
            }

            case STATE_TX_DONE: {
                // No more data to send
                *tx_bytes_to_send = 0;
                break;
            }
        }
    } else {
        // For test 2 there is no data to send.
        *tx_bytes_to_send = 0;
    }

    return TRUE;
}

