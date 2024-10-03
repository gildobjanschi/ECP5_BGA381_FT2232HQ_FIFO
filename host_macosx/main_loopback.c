/*
 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include "ftd2xx.h"

//======================================================================================================================
BOOL rx_data (unsigned char* rx_buffer, unsigned int rx_bytes);
BOOL tx_data (unsigned char send_bytes, unsigned char* tx_buffer, unsigned int* tx_bytes_to_send);

//======================================================================================================================
#define RX_BUFFER_SIZE 64

//======================================================================================================================
#define TX_BUFFER_SIZE 64
unsigned char out_data = 0;
unsigned char in_data = 0;
BOOL run_test = TRUE;
//======================================================================================================================
int main(int argc, char *argv[])
{
    FT_HANDLE ftHandle = NULL;
    FT_STATUS ftStatus;
    unsigned char Mask = 0xff;
    unsigned char Mode;

    int opt;
    unsigned char send_bytes = 1;
    if (argc <= 1) {
        printf("Usage: %s [-p send bytes (1..255)]\r\n", argv[0]);
        return 1;
    } else {
        while ((opt = getopt(argc, argv, "p:")) != -1) {
            switch (opt) {
                case 'p': send_bytes = strtol (argv[2], NULL, 10); break;
                default: {
                    printf("Usage: %s [-p send bytes]\r\n", argv[0]);
                    return 1;
                }
            }
        }
    }

    //printf("Send bytes: %d\r\n", send_bytes);

    ftStatus = FT_SetVIDPID(0x1403, 0x6010);
    if(ftStatus != FT_OK) {
        printf("FT_SetVIDPID failed! %d\r\n", ftStatus);
        return 1;
    }

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
    unsigned int rx_bytes, tx_bytes;
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
            printf("RD: %d\r\n", rx_bytes_received);
            if (ftStatus != FT_OK || rx_bytes_received != rx_bytes) {
                printf("FT_Read failed! ftStatus = %d; Bytes requested: %d, Bytes received: %d\r\n",
                                    ftStatus, rx_bytes, rx_bytes_received);
                FT_Close(ftHandle);
                return 1;
            }

            if (FALSE == rx_data (rx_buffer, rx_bytes)) {
                FT_Close(ftHandle);
                return 1;
            }
        }

        if (tx_bytes_to_send == 0) {
            tx_data (send_bytes, tx_buffer, &tx_bytes_to_send);
        }

        /* Although the RX and TX buffers are 4KB, they only use 2x 512 bytes for each buffer under FT245
         * Synchronous FIFO mode.
         */
        if (tx_bytes_to_send > 0 && 512 - tx_bytes >= tx_bytes_to_send) {
            ftStatus = FT_Write(ftHandle, tx_buffer, tx_bytes_to_send, &tx_bytes_written);
            //printf("WR: %d\r\n", tx_bytes_written);
            if (ftStatus != FT_OK || tx_bytes_written != tx_bytes_to_send) {
                printf("FT_Write failed! ftStatus = %d; Bytes to send: %d, Bytes sent: %d\r\n",
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
BOOL rx_data (unsigned char* rx_buffer, unsigned int rx_bytes) {
    for (unsigned int i = 0; i < rx_bytes; i++) {
        if (rx_buffer[i] == in_data) {
            printf("Recv: %d\r\n", rx_buffer[i]);
        } else {
            printf("Recv: %d, exp: %d\r\n", rx_buffer[i], in_data);
            //return FALSE;
        }
        in_data += 1;
    }

    return TRUE;
}

//======================================================================================================================
BOOL tx_data (unsigned char send_bytes, unsigned char* tx_buffer, unsigned int* tx_bytes_to_send) {
    if (run_test) {
        tx_buffer[0] = out_data;
        *tx_bytes_to_send = 1;
        printf("Send: %d\r\n", out_data);

        out_data += 1;
        if (out_data == send_bytes) {
            // Done sending data
            run_test = FALSE;
            printf("Done sending\r\n");
        }
    } else {
        *tx_bytes_to_send = 0;
    }
    return TRUE;
}

