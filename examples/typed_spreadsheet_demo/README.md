# Typed spreadsheet demo core

Shared demo logic for the typed spreadsheet examples.

This module owns the small operation vocabulary, formula text parser, fixed scenario, and serializable view model used by the CLI and Rabbita browser demos. It does not render UI and does not duplicate spreadsheet evaluation logic from `examples/typed_spreadsheet`.

Run from the repository root:

```bash
moon test examples/typed_spreadsheet_demo
```
