#include <stdint.h>
#include "moonbit.h"

typedef struct { int32_t marker; } RcToken;
static int32_t live_count;
static int32_t finalized_count;

static void rc_finalize(void *self) {
  (void)self;
  live_count -= 1;
  finalized_count += 1;
}

MOONBIT_FFI_EXPORT
RcToken *incr_next_rc_token_new(void) {
  RcToken *token = (RcToken *)moonbit_make_external_object(rc_finalize, sizeof(RcToken));
  token->marker = 1;
  live_count += 1;
  return token;
}

MOONBIT_FFI_EXPORT
int32_t incr_next_rc_live(void) { return live_count; }
MOONBIT_FFI_EXPORT
int32_t incr_next_rc_finalized(void) { return finalized_count; }
