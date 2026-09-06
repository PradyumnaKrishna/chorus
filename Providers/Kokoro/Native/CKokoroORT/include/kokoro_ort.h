// A thin C facade over the ONNX Runtime C API.
//
// The ORT C API is a struct of function pointers, which is painful to drive
// from Swift. Everything Kokoro needs is three inputs and one output, so we
// wrap exactly that and keep the Swift side clean.
#ifndef KOKORO_ORT_H
#define KOKORO_ORT_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct KokoroOrt KokoroOrt;

/// Compute backend requested for the session.
typedef enum {
    KOKORO_ORT_BACKEND_CPU = 0,
    KOKORO_ORT_BACKEND_COREML = 1,
} KokoroOrtBackend;

/// Loads the Kokoro graph. Returns NULL on failure and writes a message into
/// `err`. If CoreML is requested but unavailable the session silently falls
/// back to CPU.
KokoroOrt *kokoro_ort_create(const char *model_path,
                             int intra_op_threads,
                             KokoroOrtBackend backend,
                             char *err,
                             size_t err_len);

void kokoro_ort_destroy(KokoroOrt *handle);

/// Runs one forward pass.
///
/// `ids` is the padded phoneme sequence, `style` the 256-wide style vector for
/// that sequence length. On success writes a malloc'd sample buffer into
/// `out_samples` (free with kokoro_ort_free) and its length into `out_count`.
/// Returns 0 on success, non-zero on failure.
int kokoro_ort_run(KokoroOrt *handle,
                   const int64_t *ids, size_t n_ids,
                   const float *style, size_t n_style,
                   float speed,
                   float **out_samples, size_t *out_count,
                   char *err, size_t err_len);

void kokoro_ort_free(float *samples);

/// True if the live session ended up on CoreML rather than CPU.
int kokoro_ort_uses_coreml(const KokoroOrt *handle);

#ifdef __cplusplus
}
#endif
#endif /* KOKORO_ORT_H */
