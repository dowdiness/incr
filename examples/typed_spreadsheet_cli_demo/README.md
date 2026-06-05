# Typed spreadsheet CLI demo

Run the fixed typed-spreadsheet scenario from the repository root:

```bash
moon run --target native examples/typed_spreadsheet_cli_demo
moon run --target native examples/typed_spreadsheet_cli_demo -- --format json
```

The CLI drives the demo-layer operation runner from cell-edit text. The fixed
scenario parses text such as `10`, `15`, and `=A1 + 1` into `SheetOp` values,
then applies those operations to a `Worksheet` and prints trace/snapshot data.

## Text output excerpt

```text
#2 SetFormulaAst B1 : Int = (A1 + Int(1))
outcome: Ok(())
trace:
  recomputed: [B1]
  changed: [B1]
  unchanged: []
snapshots:
  B1:
    before: missing RefError("no cell at the requested address")
    after:  formula Ok(Int(11)) shape=applicative deps=[] refs=[A1] dyn=[A1]

#4 SetInput A1 = Int(15)
outcome: Ok(Int(15))
trace:
  recomputed: []
  changed: []
  unchanged: []
```

## JSON output excerpt

```json
{
  "operation": "SetFormulaAst B1 : Int = (A1 + Int(1))",
  "outcome": "Ok(())",
  "trace": {
    "recomputed": ["B1"],
    "changed": ["B1"],
    "unchanged": []
  },
  "snapshots": [
    {
      "cell": "B1",
      "before": {
        "cell": "B1",
        "present": false,
        "kind": "missing",
        "result": "RefError(\"no cell at the requested address\")",
        "dependency_shape": "none",
        "installed_dependencies": [],
        "static_references": [],
        "last_dynamic_dependencies": []
      },
      "after": {
        "cell": "B1",
        "present": true,
        "kind": "formula",
        "result": "Ok(Int(11))",
        "dependency_shape": "applicative",
        "installed_dependencies": [],
        "static_references": ["A1"],
        "last_dynamic_dependencies": ["A1"]
      }
    }
  ]
}
```

## What this demonstrates

- **Formula text → `SheetOp`**: demo text is parsed inside
  `examples/typed_spreadsheet_demo`; the typed spreadsheet boundary in
  `examples/typed_spreadsheet` does not own the demo operation vocabulary or
  parser grammar.
- **Dependency shape, static refs, dynamic deps**: formula AST references are
  discovered before execution and exposed as `shape=applicative`, `refs=[A1]` /
  `static_references: ["A1"]`; the last logical cells read during evaluation are
  exposed as `dyn=[A1]` / `last_dynamic_dependencies: ["A1"]`.
- **Trace changed/no-op**: changing `A1` from `10` to `15` marks `B1` as
  changed, while setting `A1` to `15` again is a semantic no-op and leaves all
  trace buckets empty. The worksheet API still exposes explicit force paths when
  a caller wants revalidation work.
- **Before/after snapshots**: each step captures visible cells before and after
  the operation, including missing cells, input values, formula results, and
  static references.

The parser is intentionally tiny and demo-scoped. It supports integer inputs,
`=A1 + 1`, `=A1 * 2`, and `=if(A1 > 10, 1, 0)`; it is not an Excel-compatible
parser and does not handle nested formulas or arbitrary whitespace forms such as
`if (`.
