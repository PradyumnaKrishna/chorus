#include "kokoro_ort.h"

#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#include <onnxruntime_c_api.h>
#include <coreml_provider_factory.h>

struct KokoroOrt {
    const OrtApi *api;
    OrtEnv *env;
    OrtSessionOptions *options;
    OrtSession *session;
    OrtMemoryInfo *memory_info;
    int uses_coreml;
};

static const char *const kInputNames[] = {"input_ids", "style", "speed"};
static const char *const kOutputNames[] = {"waveform"};

static void set_err(char *err, size_t err_len, const char *msg) {
    if (err && err_len) snprintf(err, err_len, "%s", msg);
}

/// Copies an OrtStatus message into `err` and releases the status.
static void take_status(const OrtApi *api, OrtStatus *status, char *err, size_t err_len) {
    if (!status) return;
    set_err(err, err_len, api->GetErrorMessage(status));
    api->ReleaseStatus(status);
}

#define ORT_TRY(expr)                                       \
    do {                                                    \
        OrtStatus *_st = (expr);                            \
        if (_st) { take_status(api, _st, err, err_len); goto fail; } \
    } while (0)

KokoroOrt *kokoro_ort_create(const char *model_path,
                             int intra_op_threads,
                             KokoroOrtBackend backend,
                             char *err,
                             size_t err_len) {
    const OrtApi *api = OrtGetApiBase()->GetApi(ORT_API_VERSION);
    if (!api) { set_err(err, err_len, "ONNX Runtime API unavailable"); return NULL; }

    KokoroOrt *h = calloc(1, sizeof(KokoroOrt));
    if (!h) { set_err(err, err_len, "out of memory"); return NULL; }
    h->api = api;

    ORT_TRY(api->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "kokoro", &h->env));
    ORT_TRY(api->CreateSessionOptions(&h->options));
    ORT_TRY(api->SetIntraOpNumThreads(h->options, intra_op_threads > 0 ? intra_op_threads : 1));
    ORT_TRY(api->SetSessionGraphOptimizationLevel(h->options, ORT_ENABLE_ALL));

    if (backend == KOKORO_ORT_BACKEND_COREML) {
        // Best effort: if this build has no CoreML EP, keep the CPU session.
        OrtStatus *st = OrtSessionOptionsAppendExecutionProvider_CoreML(h->options, 0);
        if (st) {
            api->ReleaseStatus(st);
        } else {
            h->uses_coreml = 1;
        }
    }

    ORT_TRY(api->CreateSession(h->env, model_path, h->options, &h->session));
    ORT_TRY(api->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &h->memory_info));
    return h;

fail:
    kokoro_ort_destroy(h);
    return NULL;
}

void kokoro_ort_destroy(KokoroOrt *h) {
    if (!h) return;
    const OrtApi *api = h->api;
    if (api) {
        if (h->memory_info) api->ReleaseMemoryInfo(h->memory_info);
        if (h->session)     api->ReleaseSession(h->session);
        if (h->options)     api->ReleaseSessionOptions(h->options);
        if (h->env)         api->ReleaseEnv(h->env);
    }
    free(h);
}

int kokoro_ort_uses_coreml(const KokoroOrt *h) { return h ? h->uses_coreml : 0; }

int kokoro_ort_run(KokoroOrt *h,
                   const int64_t *ids, size_t n_ids,
                   const float *style, size_t n_style,
                   float speed,
                   float **out_samples, size_t *out_count,
                   char *err, size_t err_len) {
    if (!h || !ids || !style || !out_samples || !out_count) {
        set_err(err, err_len, "invalid argument");
        return 1;
    }
    const OrtApi *api = h->api;
    OrtValue *in[3] = {NULL, NULL, NULL};
    OrtValue *out = NULL;
    OrtTensorTypeAndShapeInfo *info = NULL;
    int rc = 1;

    const int64_t ids_shape[2]   = {1, (int64_t)n_ids};
    const int64_t style_shape[2] = {1, (int64_t)n_style};
    const int64_t speed_shape[1] = {1};

    ORT_TRY(api->CreateTensorWithDataAsOrtValue(
        h->memory_info, (void *)ids, n_ids * sizeof(int64_t),
        ids_shape, 2, ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64, &in[0]));
    ORT_TRY(api->CreateTensorWithDataAsOrtValue(
        h->memory_info, (void *)style, n_style * sizeof(float),
        style_shape, 2, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &in[1]));
    ORT_TRY(api->CreateTensorWithDataAsOrtValue(
        h->memory_info, (void *)&speed, sizeof(float),
        speed_shape, 1, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &in[2]));

    ORT_TRY(api->Run(h->session, NULL,
                     kInputNames, (const OrtValue *const *)in, 3,
                     kOutputNames, 1, &out));

    ORT_TRY(api->GetTensorTypeAndShape(out, &info));

    size_t element_count = 0;
    ORT_TRY(api->GetTensorShapeElementCount(info, &element_count));

    float *data = NULL;
    ORT_TRY(api->GetTensorMutableData(out, (void **)&data));

    float *copy = malloc(element_count * sizeof(float));
    if (!copy) { set_err(err, err_len, "out of memory"); goto fail; }
    memcpy(copy, data, element_count * sizeof(float));

    *out_samples = copy;
    *out_count = element_count;
    rc = 0;

fail:
    if (info) api->ReleaseTensorTypeAndShapeInfo(info);
    if (out)  api->ReleaseValue(out);
    for (int i = 0; i < 3; i++) if (in[i]) api->ReleaseValue(in[i]);
    return rc;
}

void kokoro_ort_free(float *samples) { free(samples); }
