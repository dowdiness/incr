#include <stdint.h>
#include "moonbit.h"

typedef struct { int32_t marker; } CutoffPolicyToken;
static int32_t live_count;
static int32_t finalized_count;

static void cutoff_policy_finalize(void *self) {
  CutoffPolicyToken *token = (CutoffPolicyToken *)self;
  (void)token->marker;
  live_count -= 1;
  finalized_count += 1;
}

MOONBIT_FFI_EXPORT
CutoffPolicyToken *incr_next_cutoff_policy_token_new(void) {
  CutoffPolicyToken *token = (CutoffPolicyToken *)moonbit_make_external_object(
    cutoff_policy_finalize,
    sizeof(CutoffPolicyToken)
  );
  token->marker = 1;
  live_count += 1;
  return token;
}

MOONBIT_FFI_EXPORT
void incr_next_cutoff_policy_token_touch(CutoffPolicyToken *token) {
  (void)token->marker;
}

MOONBIT_FFI_EXPORT
int32_t incr_next_cutoff_policy_live(void) { return live_count; }

MOONBIT_FFI_EXPORT
int32_t incr_next_cutoff_policy_finalized(void) { return finalized_count; }
