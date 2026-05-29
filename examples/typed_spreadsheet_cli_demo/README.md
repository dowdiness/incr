# Typed spreadsheet CLI demo

Run the fixed typed-spreadsheet scenario from the repository root:

```bash
moon run examples/typed_spreadsheet_cli_demo
moon run examples/typed_spreadsheet_cli_demo -- --format json
```

Text output starts like this:

```text
typed spreadsheet demo scenario
trace buckets summarize formula cells after each operation

#1 SetInput A1 = Int(10)
outcome: Ok(Int(10))
trace:
  recomputed: []
  changed: []
  unchanged: []
```

The script applies the demo operation vocabulary from
`examples/typed_spreadsheet_demo`:

1. `SetInput A1 = 10`
2. `SetFormulaAst B1 = A1 + 1`
3. `SetInput A1 = 15` with `B1` captured
4. `SetInput A1 = 15` again to show an unchanged formula trace
5. `Delete B1`

Output includes each operation, outcome, trace buckets, and before/after cell
snapshots. `Worksheet::trace` is a before/after summary of formula cells after
post-operation reads, not an event log.
