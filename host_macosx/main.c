/*
 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>

#include "WinTypes.h"
#include "ftd2xx.h"
#include "wav_reader.h"

// Bit rates
#define BIT_DEPTH_DOP       0x00
#define BIT_DEPTH_16        0x01
#define BIT_DEPTH_24        0x02
#define BIT_DEPTH_32        0x03

// Sample rate
// CMD_SETUP_OUTPUT payload byte[0] bits[4:2]
#define STREAM_44100_HZ    0x00
#define STREAM_88200_HZ    0x04
#define STREAM_176400_HZ   0x08
#define STREAM_352800_HZ   0x0c

#define STREAM_48000_HZ    0x10
#define STREAM_96000_HZ    0x14
#define STREAM_192000_HZ   0x18
#define STREAM_384000_HZ   0x1c

//======================================================================================================================
BOOL rx_data (unsigned char* rx_buffer, unsigned int rx_bytes, BOOL* pStopped);
BOOL tx_data (FILE* fp, struct wav_header wh,  unsigned char output, unsigned char* tx_buffer, unsigned int* tx_bytes_to_send);

//======================================================================================================================
#define RX_BUFFER_SIZE 64

unsigned int rx_payload_length = 0;
unsigned char last_rx_cmd;

// Commands from the FPGA to the host.
#define CMD_RX_STOPPED             0xc0

#define STATE_RX_CMD               1
#define STATE_RX_STOPPED_PAYLOAD   2
#define STATE_RX_DONE              3
unsigned char rx_state_m = STATE_RX_CMD;

//======================================================================================================================
#define TX_BUFFER_SIZE 64

// Commands from the host to the FPGA.
// Command byte bits[7:6]. Bits[5:0] represent the length of the frame.
#define CMD_TX_SETUP_OUTPUT        0x00
#define CMD_TX_STREAM_OUTPUT       0x80
#define CMD_TX_STOP                0xc0

#define STATE_TX_START_CMD         1
#define STATE_TX_STREAM_CMD        2
#define STATE_TX_STOP_CMD          3
#define STATE_TX_DONE              4
unsigned char tx_state_m = STATE_TX_START_CMD;
unsigned int tx_total_bytes_read;
//======================================================================================================================
int main(int argc, char *argv[])
{
    FT_HANDLE ftHandle;
    FT_STATUS ftStatus;
    FILE* fp = NULL;
    unsigned char Mask = 0xff;
    unsigned char Mode;

    int opt;
    char* filename;
    unsigned char output = 0;
    if (argc <= 1) {
        printf("Usage: %s -f file name [-o output 0..3]\r\n", argv[0]);
        return 1;
    } else {
        while ((opt = getopt(argc, argv, "f:o:")) != -1) {
            switch (opt) {
                case 'f': filename = argv[2]; break;
                case 'o': output = strtol (argv[4], NULL, 10); break;
                default: {
                    printf("Usage: %s -f file name [-o output 0..3] (char %c)\r\n", argv[0], opt);
                    return 1;
                }
            }
        }
    }

    // Open the wav file
    fp = fopen(filename, "rb");
    if (fp == NULL) {
        printf("Cannot open file: %s\r\n", filename);
        return 1;
    }

    // Read the wav header
    struct wav_header wh;
    memset(&wh, 0, sizeof(struct wav_header));
    if (read_wav_file (fp, &wh) != 0) {
        printf("Invalid WAV file: %s\r\n", filename);
        fclose(fp);
        return 1;
    }

    /*
     * Generate a file containg all the commands and audio for the specified wav file which is
     * used for simulation.
     */
    /*
    unsigned int tx_bytes_to_send_t = 0;
    unsigned char tx_buffer_t[TX_BUFFER_SIZE];
    FILE* fpb = fopen("spdif_192000_16bit.bin", "wb");
    do {
        tx_data (fp, wh, output, tx_buffer_t, &tx_bytes_to_send_t);
        fwrite(tx_buffer_t, 1, tx_bytes_to_send_t, fpb);
    } while (tx_bytes_to_send_t > 0);

    fclose(fpb);
    */
    ftStatus = FT_Open(0, &ftHandle);
    if(ftStatus != FT_OK) {
        // FT_Open failed return;
        printf("FT_Open failed! %d\r\n", ftStatus);
        fclose(fp);
        return 1;
    }

    // Set interface into FT245 Synchronous FIFO mode
    Mode = 0x00; //reset mode
    ftStatus = FT_SetBitMode(ftHandle, Mask, Mode);
    if (ftStatus != FT_OK) {
        printf("FT_SetBitMode RESET failed! %d\r\n", ftStatus);
        FT_Close(ftHandle);
        fclose(fp);
        return 1;
    }

    usleep(1000000);

    Mode = 0x40; // Sync FIFO mode
    ftStatus = FT_SetBitMode(ftHandle, Mask, Mode);
    if (ftStatus != FT_OK) {
        // FT_SetBitMode FAILED!
        printf("FT_SetBitMode SYNC FIFO MODE failed! %d\r\n", ftStatus);
        FT_Close(ftHandle);
        fclose(fp);
        return 1;
    }

    FT_SetLatencyTimer(ftHandle, 2);
    FT_SetUSBParameters(ftHandle,0x10000, 0x10000);
    FT_SetFlowControl(ftHandle, FT_FLOW_RTS_CTS, 0x0, 0x0);
    FT_Purge(ftHandle, FT_PURGE_RX);

    // Send the data.
    unsigned int EventStatus;
    unsigned int rx_bytes;
    unsigned int tx_bytes;
    unsigned int rx_bytes_received;
    unsigned char rx_buffer[RX_BUFFER_SIZE];
    unsigned char tx_buffer[TX_BUFFER_SIZE];
    unsigned int tx_bytes_to_send = 0;
    unsigned int tx_bytes_written;
    BOOL rx_stopped = FALSE;
    while (!rx_stopped) {
        ftStatus = FT_GetStatus (ftHandle, &rx_bytes, &tx_bytes, &EventStatus);
        if (ftStatus != FT_OK) {
            printf("FT_GetStatus failed! %d\r\n", ftStatus);
            FT_Close(ftHandle);
            fclose(fp);
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
                fclose(fp);
                return 1;
            }

            if (FALSE == rx_data (rx_buffer, rx_bytes, &rx_stopped)) {
                FT_Close(ftHandle);
                fclose(fp);
                return 1;
            }
        }

        if (tx_bytes_to_send == 0) {
            tx_data (fp, wh, output, tx_buffer, &tx_bytes_to_send);
        }

        /* Although the RX and TX buffers are 4KB, they only use 2x 512 bytes for each buffer under FT245
         * Synchronous FIFO mode.
         */
        if (tx_bytes_to_send > 0 && 512 - tx_bytes >= tx_bytes_to_send) {
            ftStatus = FT_Write(ftHandle, tx_buffer, tx_bytes_to_send, &tx_bytes_written);
            if (ftStatus != FT_OK || tx_bytes_written != tx_bytes_to_send) {
                printf("FT_Write failed! ftStatus = %d; Bytes to send: %d, Bytes sent: %d\r\n",
                                    ftStatus, tx_bytes_to_send, tx_bytes_written);
                FT_Close(ftHandle);
                fclose(fp);
                return 1;
            }

            // This buffer was sent
            tx_bytes_to_send = 0;
        }
    }

    FT_Close(ftHandle);
    fclose(fp);
    return 0;
}

//======================================================================================================================
BOOL tx_data (FILE* fp, struct wav_header wh, unsigned char output, unsigned char* tx_buffer, unsigned int* tx_bytes_to_send) {
    switch (tx_state_m) {
        case STATE_TX_START_CMD: {
            tx_buffer[0] = CMD_TX_SETUP_OUTPUT | 1;
            // Set the bit depth
            switch (wh.fmt_subchunk.bits_per_sample) {
                case 16: tx_buffer[1] = BIT_DEPTH_16; break;
                case 24: tx_buffer[1] = BIT_DEPTH_24; break;
                case 32: tx_buffer[1] = BIT_DEPTH_32; break;
                default: {
                    printf("Unsupported bit depth: %d\r\n", wh.fmt_subchunk.bits_per_sample);
                    return FALSE;
                }
            }

            // Set the sampling rate
            switch (wh.fmt_subchunk.sample_rate) {
                case 44100: tx_buffer[1] |= STREAM_44100_HZ; break;
                case 88200: tx_buffer[1] |= STREAM_88200_HZ; break;
                case 176400: tx_buffer[1] |= STREAM_176400_HZ; break;
                case 352800: tx_buffer[1] |= STREAM_352800_HZ; break;

                case 48000: tx_buffer[1] |= STREAM_48000_HZ; break;
                case 96000: tx_buffer[1] |= STREAM_96000_HZ; break;
                case 192000: tx_buffer[1] |= STREAM_192000_HZ; break;
                case 384000: tx_buffer[1] |= STREAM_384000_HZ; break;

                default: {
                    printf("Unsupported sample rate %d bytes\r\n", wh.fmt_subchunk.sample_rate);
                    return FALSE;
                }
            }

            // Set the output
            tx_buffer[1] |= output << 6;

            switch (wh.fmt_subchunk.num_channels) {
                case 2: break; // Only two channels are supported. Mono will be supported later.
                default: {
                    printf("Unsupported number of channels: %d\r\n", wh.fmt_subchunk.num_channels);
                    return FALSE;
                }
            }
            *tx_bytes_to_send = 2;

            tx_state_m = STATE_TX_STREAM_CMD;
            tx_total_bytes_read = 0;
            break;
        }

        case STATE_TX_STREAM_CMD: {
            // Number of bytes to read
            *tx_bytes_to_send = 0;
            size_t bytes_read;
            unsigned int bytes_per_sample = wh.fmt_subchunk.num_channels * (wh.fmt_subchunk.bits_per_sample >> 3);
            while (1) {
                if (*tx_bytes_to_send + bytes_per_sample < TX_BUFFER_SIZE - 1) {
                    bytes_read = fread(tx_buffer + *tx_bytes_to_send + 1, 1, bytes_per_sample, fp);
                    //printf("Read %ld bytes, requested %d\r\n", (unsigned long) bytes_read, bytes_per_sample);
                    *tx_bytes_to_send += bytes_read;

                    tx_total_bytes_read += bytes_read;
                    if ((unsigned int)wh.data_subchunk.subchunk2_size == tx_total_bytes_read) {
                        printf("Read all the data %d bytes\r\n", tx_total_bytes_read);
                        if ( *tx_bytes_to_send > 0) {
                            tx_buffer[0] = CMD_TX_STREAM_OUTPUT | *tx_bytes_to_send;
                            *tx_bytes_to_send += 1;
                        }

                        tx_state_m = STATE_TX_STOP_CMD;
                        break;
                    }
                } else { // No more room in the buffer
                    //printf("Read total %d bytes\r\n", tx_total_bytes_read);
                    //printf("Sending %d bytes\r\n", *tx_bytes_to_send);
                    tx_buffer[0] = CMD_TX_STREAM_OUTPUT | *tx_bytes_to_send;
                    *tx_bytes_to_send += 1;
                    printf("%2X  ", tx_buffer[0]);
                    for (unsigned int i=1 ; i<*tx_bytes_to_send; i++) {
                        printf("%2X ", tx_buffer[i]);
                    }
                    printf("\r\n");
                    break;
                }
            }

            break;
        }

        case STATE_TX_STOP_CMD: {
            tx_buffer[0] = CMD_TX_STOP;
            *tx_bytes_to_send = 1;

            tx_state_m = STATE_TX_DONE;
            break;
        }

        case STATE_TX_DONE: {
            *tx_bytes_to_send = 0;
            break;
        }
    }

    return TRUE;
}

//======================================================================================================================
BOOL rx_data (unsigned char* rx_buffer, unsigned int rx_bytes, BOOL* pStopped) {
    *pStopped = FALSE;

    for (unsigned int i = 0; i < rx_bytes; i++) {
        switch (rx_state_m) {
            case STATE_RX_CMD: {
                last_rx_cmd = rx_buffer[i] & 0xc0;
                rx_payload_length = rx_buffer[i] & 0x3f;
                switch (last_rx_cmd) {
                    case CMD_RX_STOPPED: {
                        printf("CMD_RX_STOPPED with payload: %d\r\n", rx_payload_length);
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

            case STATE_RX_STOPPED_PAYLOAD: {
                    printf("STATE_RX_STOPPED_PAYLOAD. Error code: %d\r\n", rx_buffer[i]);
                    if (rx_buffer[i] == 0) {
                        printf("===== Test OK =====\r\n");
                    } else {
                        printf("===== Test failed (error code %d) =====\r\n", rx_buffer[i]);
                    }

                    rx_state_m = STATE_RX_DONE;
                    *pStopped = TRUE;
                break;
            }

            case STATE_RX_DONE: {
                *pStopped = TRUE;
                break;
            }
        }
    }

    return TRUE;
}
