//
// Created by franciscohanna92 on 08/09/18.
//

#include <stdio.h>

#ifndef WAV_READER_WAV_READER_H
#define WAV_READER_WAV_READER_H


struct riff_header {
    char chunk_id[5];       // Contains the letters "RIFF" in ASCII form
    int chunk_size;         // This is the size of the entire file in bytes minus 8 bytes (ChunkID and ChunkSize not included).
    char format[5];         // Contains the letters "WAVE"
};

struct fmt_subchunk {
    char subchunk1_id[5];   // Contains the letters "fmt "
    int subchunk1_size;     // 16 or 18 for PCM.  This is the size of the rest of the Subchunk which follows this number.
    int audio_format;       // PCM = 1 (i.e. Linear quantization) Values other than 1 indicate some form of compression.
    int num_channels;       // Mono = 1, Stereo = 2, etc.
    int sample_rate;        // 8000, 44100, etc.
    int byte_rate;          // == SampleRate * NumChannels * BitsPerSample/8
    int block_align;        // == NumChannels * BitsPerSample/8. The number of bytes for one sample including all channels
    int bits_per_sample;    // 8 bits = 8, 16 bits = 16, etc.
};

struct data_subchunk {
    char subchunk2_id[5];   // Contains the letters "data"
    int subchunk2_size;     // == NumSamples * NumChannels * BitsPerSample/8. This is the number of bytes in the data.
};

struct wav_header {
    struct riff_header riff_header;
    struct fmt_subchunk fmt_subchunk;
    struct data_subchunk data_subchunk;
};
/*
int check_file_format(FILE* fp);
struct riff_header read_riff_header(FILE* fp);
struct fmt_subchunk read_fmt_subchunk(FILE* fp);
struct data_subchunk read_data_subchunk(FILE* fp);
void print_wav_header(struct wav_header wh);
*/
int read_wav_file(FILE* fp, struct wav_header* wh);

#endif //WAV_READER_WAV_READER_H
