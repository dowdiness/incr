# incr_tea 7GUIs stress test

Browser stress-test examples for the experimental `examples/incr_tea` renderer,
using the [7GUIs](https://eugenkiss.github.io/7guis/) tasks as a compact
framework-completeness checklist.

Each task is its own MoonBit package and browser root so the examples are easy
to read independently:

| Task | Package |
| --- | --- |
| Counter | `counter/` |
| Temperature Converter | `temperature_converter/` |
| Flight Booker | `flight_booker/` |
| Timer | `timer/` |
| CRUD | `crud/` |
| Circle Drawer | `circle_drawer/` |
| Cells | `cells/` |

The suite intentionally keeps all handlers at the renderer boundary: cached
`Html` stores pure event descriptors and payload ids, while `BrowserRenderer` maps
text/select/range and pointer payloads back into each task's `Msg` values.

## What it covers

- Counter: basic `Program` dispatch and view reads.
- Temperature Converter: paired text inputs through `on_input` payload ids.
- Flight Booker: select/date controls through the pure `on_change` descriptor.
- Timer: `Program::with_subscriptions` and timer reconciliation.
- CRUD: filtered list selection and keyed model updates.
- Circle Drawer: pointer payload resolver and undo/redo model snapshots. It uses CSS circles rather than SVG, deliberately keeping the first slice inside the current HTML renderer.
- Cells: a small spreadsheet-shaped dependency toy (`=A1` mirrors another cell).

This is a stress test, not a replacement for a production UI framework.

## Run

```bash
npm install
npm run dev
```

Production build, static smoke check, and browser DOM check:

```bash
npm run build
npm run smoke
npm run test:dom
```

MoonBit-only validation from the repository root:

```bash
moon check --target js examples/incr_tea_7guis
moon test --target js examples/incr_tea_7guis
```
