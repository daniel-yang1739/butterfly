#ifndef BUTTERFLY_WHISPER_H
#define BUTTERFLY_WHISPER_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ButterflyWhisperContext ButterflyWhisperContext;

ButterflyWhisperContext *butterfly_whisper_create(
    const char *model_path,
    char **error_message
);

char *butterfly_whisper_transcribe(
    ButterflyWhisperContext *context,
    const float *samples,
    int sample_count,
    const char *initial_prompt,
    char **error_message
);

void butterfly_whisper_destroy(ButterflyWhisperContext *context);
void butterfly_whisper_free_string(char *string);

#ifdef __cplusplus
}
#endif

#endif
