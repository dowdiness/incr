# Incr Query

Incr Query is an adopted, unpublished pre-1.0 typed incremental query kernel.
It is an independent sibling of the current `dowdiness/incr` product.

This directory groups the product family physically while preserving four
independent MoonBit modules and their verification seams:

| Area | Module | Purpose |
|---|---|---|
| [`kernel/`](kernel/) | `dowdiness/incr_query` | Production kernel, colocated tests, package policy, and accepted evidence |
| [`testkit/`](testkit/) | `dowdiness/incr_query_testkit` | Independent Fresh oracle and differential conformance |
| [`docs/`](docs/) | `dowdiness/incr_query_docs` | Checked public-only guide and caller-contract counterexamples |
| [`consumer_probe/`](consumer_probe/) | `dowdiness/incr_query_consumer_probe` | Executable public-consumer probe retained as a distribution regression fixture |
| [`tools/`](tools/) | — | Product-owned boundary, distribution, and historical compile probes |

The umbrella is not a MoonBit module root. Publication, registry mutation,
version release, and production integration remain separately gated.
