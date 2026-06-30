# AnimationFrame Subscription Plan

**Goal:** Add `SubSpec::AnimationFrame(Msg)` to `examples/incr_tea/subscription.mbt`, completing issue #290 (expanding subscriptions beyond Timer).

## Design

Follow the established `KeydownSub` pattern exactly:

- **`SubSpec::AnimationFrame(Msg)`** — no delta_ms parameter (simpler Eq, matches Timer pattern where elapsed time is the user's responsibility).
- **`AnimationFrameSub[Msg]`** struct with `raf_handle` (self-rescheduling loop), `Ref[Msg]`, and `dispatch`.
- **JS extern:** `dom_request_animation_frame(callback) -> RafHandleId` — fires callback once per frame, re-requests inside the callback.
- **Non-JS stub:** increment debug counter, return fake handle.
- **`ActiveSub::AnimationFrame(...)`** arm in the enum.
- **`SubscriptionsManager::start_or_update_animation_frame`** — start lifecycle (request + callback), update only message in-place (no restart), stop cancels pending frame.
- **`reconcile`** gets a `SubSpec::AnimationFrame` match arm.

Key lifecycle behavior:
- **Start:** calls `dom_request_animation_frame` once. The JS callback re-requests the next frame, creating a continuous loop.
- **Update (message-only):** just replaces `self.message.val` — no restart needed.
- **Stop:** calls `dom_cancel_animation_frame(handle)`.
- **Transition:** if same SubKey switches from Timer/Keydown to AnimationFrame (or vice versa), the existing `ActiveSub::stop` + new start path handles it.

## Files

- **Modify:** `examples/incr_tea/subscription.mbt` — add SubSpec variant, AnimationFrameSub, ActiveSub arm, start_or_update, reconcile arm, JS externs, stubs
- **Modify:** `examples/incr_tea/subscription_wbtest.mbt` — add lifecycle tests (enable/disable, message-only update no restart, stop)
- Existing tests pass unchanged.

## Acceptance

- `moon check examples/incr_tea` — 0 errors
- `moon test examples/incr_tea` — all tests pass (97+new)
- AnimationFrame lifecycle: start starts, stop stops, message update doesn't restart, no churn on unrelated changes
