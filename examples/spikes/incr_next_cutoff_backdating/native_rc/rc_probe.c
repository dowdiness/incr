#include <stdint.h>
#include "moonbit.h"

#define RC_PROBE_KIND_COUNT 13

typedef struct { int32_t kind; } RcProbeToken;
static int32_t live_counts[RC_PROBE_KIND_COUNT];
static int32_t finalized_counts[RC_PROBE_KIND_COUNT];

static void rc_probe_finalize(void *self) {
  RcProbeToken *token = (RcProbeToken *)self;
  if (token->kind >= 0 && token->kind < RC_PROBE_KIND_COUNT) {
    live_counts[token->kind] -= 1;
    finalized_counts[token->kind] += 1;
  }
}

MOONBIT_FFI_EXPORT
RcProbeToken *incr_next_cutoff_token_new(int32_t kind) {
  RcProbeToken *token = (RcProbeToken *)moonbit_make_external_object(
    rc_probe_finalize,
    sizeof(RcProbeToken)
  );
  token->kind = kind;
  if (kind >= 0 && kind < RC_PROBE_KIND_COUNT) live_counts[kind] += 1;
  return token;
}

MOONBIT_FFI_EXPORT
void incr_next_cutoff_token_touch(RcProbeToken *token) { (void)token->kind; }

MOONBIT_FFI_EXPORT
int32_t incr_next_cutoff_live(int32_t kind) {
  return kind >= 0 && kind < RC_PROBE_KIND_COUNT ? live_counts[kind] : -1;
}

MOONBIT_FFI_EXPORT
int32_t incr_next_cutoff_finalized(int32_t kind) {
  return kind >= 0 && kind < RC_PROBE_KIND_COUNT
    ? finalized_counts[kind]
    : -1;
}
