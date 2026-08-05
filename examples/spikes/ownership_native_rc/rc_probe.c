#include <stdint.h>
#include "moonbit.h"

#define RC_PROBE_KIND_COUNT 11

typedef struct {
  int32_t kind;
} RcProbeToken;

static int32_t live_counts[RC_PROBE_KIND_COUNT];
static int32_t finalized_counts[RC_PROBE_KIND_COUNT];

static void rc_probe_token_finalize(void *self) {
  RcProbeToken *token = (RcProbeToken *)self;
  int32_t kind = token->kind;
  if (kind >= 0 && kind < RC_PROBE_KIND_COUNT) {
    live_counts[kind] -= 1;
    finalized_counts[kind] += 1;
  }
}

MOONBIT_FFI_EXPORT
RcProbeToken *incr_rc_probe_token_new(int32_t kind) {
  RcProbeToken *token = (RcProbeToken *)moonbit_make_external_object(
    rc_probe_token_finalize,
    sizeof(RcProbeToken)
  );
  token->kind = kind;
  if (kind >= 0 && kind < RC_PROBE_KIND_COUNT) {
    live_counts[kind] += 1;
  }
  return token;
}

MOONBIT_FFI_EXPORT
void incr_rc_probe_token_touch(RcProbeToken *token) {
  (void)token->kind;
}

MOONBIT_FFI_EXPORT
int32_t incr_rc_probe_live_count(int32_t kind) {
  if (kind < 0 || kind >= RC_PROBE_KIND_COUNT) {
    return -1;
  }
  return live_counts[kind];
}

MOONBIT_FFI_EXPORT
int32_t incr_rc_probe_finalized_count(int32_t kind) {
  if (kind < 0 || kind >= RC_PROBE_KIND_COUNT) {
    return -1;
  }
  return finalized_counts[kind];
}
