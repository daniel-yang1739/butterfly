#include "ButterflyWhisper.h"

#include <ggml-backend.h>
#include <whisper.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

struct ButterflyWhisperContext {
    struct whisper_context *whisper;
};

static void set_error(char **error_message, const char *message) {
    if (error_message != NULL) {
        *error_message = strdup(message);
    }
}

ButterflyWhisperContext *butterfly_whisper_create(
    const char *model_path,
    char **error_message
) {
    if (model_path == NULL) {
        set_error(error_message, "The Whisper model path is missing");
        return NULL;
    }

    ggml_backend_load_all();

    struct whisper_context_params parameters = whisper_context_default_params();
    parameters.use_gpu = true;
    parameters.flash_attn = true;

    struct whisper_context *whisper = whisper_init_from_file_with_params(model_path, parameters);
    if (whisper == NULL) {
        set_error(error_message, "Failed to load the Whisper model");
        return NULL;
    }

    ButterflyWhisperContext *context = calloc(1, sizeof(ButterflyWhisperContext));
    if (context == NULL) {
        whisper_free(whisper);
        set_error(error_message, "Failed to allocate the Whisper context");
        return NULL;
    }

    context->whisper = whisper;
    return context;
}

char *butterfly_whisper_transcribe(
    ButterflyWhisperContext *context,
    const float *samples,
    int sample_count,
    const char *initial_prompt,
    char **error_message
) {
    if (context == NULL || context->whisper == NULL) {
        set_error(error_message, "The Whisper context is not initialized");
        return NULL;
    }
    if (samples == NULL || sample_count <= 0) {
        return strdup("");
    }

    struct whisper_full_params parameters = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    long processor_count = sysconf(_SC_NPROCESSORS_ONLN);
    parameters.n_threads = (int) (processor_count > 4 ? 4 : processor_count);
    if (parameters.n_threads < 1) {
        parameters.n_threads = 1;
    }
    parameters.language = "zh";
    parameters.initial_prompt = initial_prompt;
    parameters.no_context = true;
    parameters.no_timestamps = true;
    parameters.single_segment = true;
    parameters.print_special = false;
    parameters.print_progress = false;
    parameters.print_realtime = false;
    parameters.print_timestamps = false;
    parameters.suppress_blank = true;

    int result = whisper_full(context->whisper, parameters, samples, sample_count);
    if (result != 0) {
        char message[96];
        snprintf(message, sizeof(message), "Whisper inference failed with status %d", result);
        set_error(error_message, message);
        return NULL;
    }

    int segment_count = whisper_full_n_segments(context->whisper);
    size_t total_length = 1;
    for (int index = 0; index < segment_count; index++) {
        const char *text = whisper_full_get_segment_text(context->whisper, index);
        if (text != NULL) {
            total_length += strlen(text);
        }
    }

    char *output = calloc(total_length, 1);
    if (output == NULL) {
        set_error(error_message, "Failed to allocate the transcription result");
        return NULL;
    }

    for (int index = 0; index < segment_count; index++) {
        const char *text = whisper_full_get_segment_text(context->whisper, index);
        if (text != NULL) {
            strcat(output, text);
        }
    }
    return output;
}

void butterfly_whisper_destroy(ButterflyWhisperContext *context) {
    if (context == NULL) {
        return;
    }
    if (context->whisper != NULL) {
        whisper_free(context->whisper);
    }
    free(context);
}

void butterfly_whisper_free_string(char *string) {
    free(string);
}
