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
    int has_durations;
};

static const char *const kInputNames[] = {"input_ids", "style", "speed"};
static const char *const kOutputNames[] = {"waveform", "durations"};

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

/// True when the graph declares an output named "durations".
///
/// Probed once at load: asking Run for an output the graph does not declare fails
/// the whole pass, and an older installed model has only "waveform".
static int detect_durations(const OrtApi *api, OrtSession *session) {
    OrtAllocator *allocator = NULL;
    OrtStatus *status = api->GetAllocatorWithDefaultOptions(&allocator);
    if (status) { api->ReleaseStatus(status); return 0; }
    if (!allocator) return 0;

    size_t count = 0;
    status = api->SessionGetOutputCount(session, &count);
    if (status) { api->ReleaseStatus(status); return 0; }

    int found = 0;
    for (size_t index = 0; index < count && !found; index++) {
        char *name = NULL;
        status = api->SessionGetOutputName(session, index, allocator, &name);
        if (status) { api->ReleaseStatus(status); continue; }
        found = strcmp(name, kOutputNames[1]) == 0;
        status = api->AllocatorFree(allocator, name);
        if (status) api->ReleaseStatus(status);
    }
    return found;
}

/// Copies a float tensor out of ORT ownership into a malloc'd buffer.
static OrtStatus *copy_float_tensor(const OrtApi *api, OrtValue *value,
                                    float **out, size_t *count) {
    OrtTensorTypeAndShapeInfo *info = NULL;
    OrtStatus *status = api->GetTensorTypeAndShape(value, &info);
    if (status) return status;

    size_t elements = 0;
    status = api->GetTensorShapeElementCount(info, &elements);
    api->ReleaseTensorTypeAndShapeInfo(info);
    if (status) return status;

    if (elements == 0) {
        *out = NULL;
        *count = 0;
        return NULL;
    }

    float *data = NULL;
    status = api->GetTensorMutableData(value, (void **)&data);
    if (status) return status;

    float *copy = malloc(elements * sizeof(float));
    if (!copy) return api->CreateStatus(ORT_FAIL, "out of memory");
    memcpy(copy, data, elements * sizeof(float));

    *out = copy;
    *count = elements;
    return NULL;
}

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
    h->has_durations = detect_durations(api, h->session);
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

int kokoro_ort_has_durations(const KokoroOrt *h) { return h ? h->has_durations : 0; }

int kokoro_ort_run(KokoroOrt *h,
                   const int64_t *ids, size_t n_ids,
                   const float *style, size_t n_style,
                   float speed,
                   float **out_samples, size_t *out_count,
                   float **out_durations, size_t *out_duration_count,
                   char *err, size_t err_len) {
    if (!h || !ids || !style || !out_samples || !out_count ||
        !out_durations || !out_duration_count) {
        set_err(err, err_len, "invalid argument");
        return 1;
    }
    const OrtApi *api = h->api;
    OrtValue *in[3] = {NULL, NULL, NULL};
    OrtValue *out[2] = {NULL, NULL};
    float *samples = NULL;
    float *durations = NULL;
    size_t sample_count = 0;
    size_t duration_count = 0;
    const size_t n_outputs = h->has_durations ? 2 : 1;
    int rc = 1;

    *out_samples = NULL;
    *out_count = 0;
    *out_durations = NULL;
    *out_duration_count = 0;

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
                     kOutputNames, n_outputs, out));

    ORT_TRY(copy_float_tensor(api, out[0], &samples, &sample_count));
    if (n_outputs > 1) {
        ORT_TRY(copy_float_tensor(api, out[1], &durations, &duration_count));
    }

    *out_samples = samples;
    *out_count = sample_count;
    *out_durations = durations;
    *out_duration_count = duration_count;
    samples = NULL;
    durations = NULL;
    rc = 0;

fail:
    free(samples);
    free(durations);
    if (out[1]) api->ReleaseValue(out[1]);
    if (out[0]) api->ReleaseValue(out[0]);
    for (int i = 0; i < 3; i++) if (in[i]) api->ReleaseValue(in[i]);
    return rc;
}

void kokoro_ort_free(float *buffer) { free(buffer); }
