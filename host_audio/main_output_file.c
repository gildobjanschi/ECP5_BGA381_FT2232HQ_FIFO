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
#include <string.h>

#include "wav_reader.h"

// Bit rates
#define BIT_DEPTH_DOP       0x00
#define BIT_DEPTH_16        0x01
#define BIT_DEPTH_24        0x02
#define BIT_DEPTH_32        0x03

// Sample rate.
#define STREAM_44100_HZ    0x00
#define STREAM_88200_HZ    0x04
#define STREAM_176400_HZ   0x08
#define STREAM_352800_HZ   0x0c

#define STREAM_48000_HZ    0x10
#define STREAM_96000_HZ    0x14
#define STREAM_192000_HZ   0x18
#define STREAM_384000_HZ   0x1c

//======================================================================================================================
int tx_data (FILE* fp, struct wav_header wh,  unsigned char output_port, unsigned char* tx_buffer,
                    unsigned int* tx_bytes_to_send);
void build_file_name (char output_port, struct wav_header wh, char *output_filename);
//======================================================================================================================
#define TX_BUFFER_SIZE 64

// Commands from the host to the FPGA.
#define CMD_HOST_SETUP_OUTPUT        0x00
#define CMD_HOST_STREAM_OUTPUT       0x80
#define CMD_HOST_STOP                0xc0

#define STATE_TX_START_CMD         1
#define STATE_TX_STREAM_CMD        2
#define STATE_TX_STOP_CMD          3
#define STATE_TX_DONE              4
unsigned char tx_state_m = STATE_TX_START_CMD;
unsigned int tx_total_bytes_read;

//======================================================================================================================
int main(int argc, char *argv[])
{
    int opt;
    char* filename;
    unsigned char output_port = 0;
    if (argc <= 1) {
        printf("Usage: %s -f file name [-o output_port 0..3]\r\n", argv[0]);
        return 1;
    } else {
        while ((opt = getopt(argc, argv, "f:o:")) != -1) {
            switch (opt) {
                case 'f': filename = argv[2]; break;
                case 'o': output_port = strtol (argv[4], NULL, 10); break;
                default: {
                    printf("Usage: %s -f file name [-o output_port 0..3]\r\n", argv[0]);
                    return 1;
                }
            }
        }
    }

    if (output_port > 3) {
        printf("Invalid output port: %d\r\n", output_port);
        return 0;
    }

    // Open the wav file
    FILE* fp = fopen(filename, "rb");
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

    // Form the file name from the audio output, sample rate and bit depth
    char output_filename[32] = "";
    build_file_name (output_port, wh, output_filename);

    // Generate a file containg all the commands and audio samples for the specified wav file
    // This file can be used for HDL simulation.
    unsigned int tx_bytes_to_send = 0;
    unsigned char tx_buffer[TX_BUFFER_SIZE];
    FILE* fpb = fopen(output_filename, "wb");
    do {
        tx_data (fp, wh, output_port, tx_buffer, &tx_bytes_to_send);
        fwrite(tx_buffer, 1, tx_bytes_to_send, fpb);
    } while (tx_bytes_to_send > 0);

    fclose(fpb);
    fclose(fp);

    return 0;
}

//======================================================================================================================
int tx_data (FILE* fp, struct wav_header wh, unsigned char output_port, unsigned char* tx_buffer,
                        unsigned int* tx_bytes_to_send) {
    switch (tx_state_m) {
        case STATE_TX_START_CMD: {
            tx_buffer[0] = CMD_HOST_SETUP_OUTPUT | 1;
            // Set the bit depth
            switch (wh.fmt_subchunk.bits_per_sample) {
                case 16: tx_buffer[1] = BIT_DEPTH_16; break;
                case 24: tx_buffer[1] = BIT_DEPTH_24; break;
                case 32: tx_buffer[1] = BIT_DEPTH_32; break;
                default: {
                    printf("Unsupported bit depth: %d\r\n", wh.fmt_subchunk.bits_per_sample);
                    return -1;
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
                    return -2;
                }
            }

            // Set the output_port
            tx_buffer[1] |= output_port << 6;

            switch (wh.fmt_subchunk.num_channels) {
                case 2: break; // Only two channels are supported. Mono will be supported later.
                default: {
                    printf("Unsupported number of channels: %d\r\n", wh.fmt_subchunk.num_channels);
                    return -3;
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
                        printf("Read all the data %d bytes from the WAV file.\r\n", tx_total_bytes_read);
                        if (*tx_bytes_to_send > 0) {
                            tx_buffer[0] = CMD_HOST_STREAM_OUTPUT | *tx_bytes_to_send;
                            *tx_bytes_to_send += 1;
                        }

                        tx_state_m = STATE_TX_STOP_CMD;
                        break;
                    }
                } else { // No more room in the buffer
                    //printf("Read total %d bytes\r\n", tx_total_bytes_read);
                    //printf("Sending %d bytes\r\n", *tx_bytes_to_send);
                    tx_buffer[0] = CMD_HOST_STREAM_OUTPUT | *tx_bytes_to_send;
                    *tx_bytes_to_send += 1;
                    /*
                    printf("%2X  ", tx_buffer[0]);
                    for (unsigned int i=1 ; i<*tx_bytes_to_send; i++) {
                        printf("%2X ", tx_buffer[i]);
                    }
                    printf("\r\n");
                    */
                    break;
                }
            }

            break;
        }

        case STATE_TX_STOP_CMD: {
            tx_buffer[0] = CMD_HOST_STOP;
            *tx_bytes_to_send = 1;

            tx_state_m = STATE_TX_DONE;
            break;
        }

        case STATE_TX_DONE: {
            *tx_bytes_to_send = 0;
            break;
        }
    }

    return 0;
}

//======================================================================================================================
void build_file_name (char output_port, struct wav_header wh, char *output_filename) {
    if (output_port == 0 || output_port == 1) {
        strcat (output_filename, "i2s_");
    } else {
        strcat (output_filename, "spdif_");
    }

    switch (wh.fmt_subchunk.sample_rate) {
        case 44100: strcat (output_filename, "44100_"); break;
        case 88200: strcat (output_filename, "88200_"); break;
        case 176400: strcat (output_filename, "176400_"); break;
        case 352800: strcat (output_filename, "352800_"); break;

        case 48000: strcat (output_filename, "48000_"); break;
        case 96000: strcat (output_filename, "96000_"); break;
        case 192000: strcat (output_filename, "192000_"); break;
        case 384000: strcat (output_filename, "384000_"); break;

        default: {
            printf("Unsupported sample rate %d bytes\r\n", wh.fmt_subchunk.sample_rate);
            return;
        }
    }

    switch (wh.fmt_subchunk.bits_per_sample) {
        case 16: strcat (output_filename, "16.bin"); break;
        case 24: strcat (output_filename, "24.bin"); break;
        case 32: strcat (output_filename, "32.bin"); break;
        default: {
            printf("Unsupported bit depth: %d\r\n", wh.fmt_subchunk.bits_per_sample);
            return;
        }
    }

    printf ("Output file name: %s\r\n", output_filename);
}
