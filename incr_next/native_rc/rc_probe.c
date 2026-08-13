#include <stdint.h>
#include "moonbit.h"

#define RC_KIND_COUNT 12
typedef struct { int32_t kind; } RcToken;
static int32_t live_counts[RC_KIND_COUNT];
static int32_t finalized_counts[RC_KIND_COUNT];

static void rc_finalize(void *self) {
  RcToken *token = (RcToken *)self;
  if (token->kind >= 0 && token->kind < RC_KIND_COUNT) {
    live_counts[token->kind] -= 1;
    finalized_counts[token->kind] += 1;
  }
}

MOONBIT_FFI_EXPORT
RcToken *incr_next_rc_token_new(int32_t kind) {
  RcToken *token = (RcToken *)moonbit_make_external_object(rc_finalize, sizeof(RcToken));
  token->kind = kind;
  if (kind >= 0 && kind < RC_KIND_COUNT) live_counts[kind] += 1;
  return token;
}

MOONBIT_FFI_EXPORT
int32_t incr_next_rc_live(int32_t kind) {
  return kind >= 0 && kind < RC_KIND_COUNT ? live_counts[kind] : -1;
}

MOONBIT_FFI_EXPORT
int32_t incr_next_rc_finalized(int32_t kind) {
  return kind >= 0 && kind < RC_KIND_COUNT ? finalized_counts[kind] : -1;
}
