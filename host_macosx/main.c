/*
 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include "ftd2xx.h"


int main(int argc, char *argv[])
{
    FT_HANDLE ftHandle;
    FT_STATUS ftStatus;
    unsigned char Mask = 0xff;
    unsigned char Mode;

    int opt;
    unsigned char send_payload_length = 60;
    char* filename;
    if (argc <= 1) {
        printf("Usage: %s -f file name [-p send payload length]\r\n", argv[0]);
        return 1;
    } else {
        while ((opt = getopt(argc, argv, "f:p:")) != -1) {
            switch (opt) {
                case 'f': filename = argv[2]; break;
                case 'p': send_payload_length = strtol (argv[4], NULL, 10); break;
                default: {
                    printf("Usage: %s -f file name [-p send payload length]\r\n", argv[0]);
                    return 1;
                }
            }
        }
    }

    ftStatus = FT_Open(0, &ftHandle);
    if(ftStatus != FT_OK) {
        // FT_Open failed return;
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
        // FT_SetBitMode FAILED!
        printf("FT_SetBitMode SYNC FIFO MODE failed! %d\r\n", ftStatus);
        FT_Close(ftHandle);
        return 1;
    }

    FT_SetLatencyTimer(ftHandle, 2);
    FT_SetUSBParameters(ftHandle,0x10000, 0x10000);
    FT_SetFlowControl(ftHandle, FT_FLOW_RTS_CTS, 0x0, 0x0);
    FT_Purge(ftHandle, FT_PURGE_RX);

    FT_Close(ftHandle);

    return 0;
}

