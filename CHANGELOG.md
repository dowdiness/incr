# Changelog

## v0.10.0 (2026-06-24)

### Added
- Experimental `incr_tea` module: keyed VDOM diff, pure event-payload descriptors, renderer lifecycle, and Eq-safe HTML ergonomics
- `incr_tea` activation policy with inactive browser roots and subscription diff flow
- `incr_tea` spreadsheet proof-of-concept with event descriptor expansion
- `incr_tea` keyed DOM benchmark
- `incr_tea` 7GUIs stress test
- `incr_tea` semantic editor demo

### Changed
- **`batch_result` runtime on-change and derived-event hooks are now composable** (breaking)
  - The `batch_result` registration signature changed — old single-hook callers must migrate to the composable form

### Performance
- Optimize `incr_tea` keyed diff planner
- Compare adjacent UI view builds
- Add activation trigger probe

### Removed
- Remove deprecated `try` question syntax

### Documentation
- Document `incr_tea` architectural direction after Rabbita, Qwik, and Luna comparison
