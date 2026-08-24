# K2.3 distribution candidate validation

**Reader:** Maintainers and reviewers deciding whether Plan 016 K2.3 evidence is
sufficient to advance to K2.4.

**Decision:** Treat the isolated 17-file ZIP as an unpublished distribution
candidate and verify it through the accepted public consumer outside the source
repository.

**Keep until:** The K2 product disposition is accepted.

**Disposition:** At K2 closure, retain the accepted distribution policy with
the product package and remove time-bound raw evidence, or delete this record
with the disposition rationale.

**Status:** **ACCEPTED AND MERGED** as
`3007f5ff2e2cf8c459ab04916f27a34fb62cf0e3` from reviewed candidate
`51850082c3668311532b858bcd903ed4a7134d52`; tree equivalence, Hosted CI, and
independent MoonBit review passed. Publication and registry mutation remain
unauthorized.

## Source and tools

The status transition is commit `eb370e6d98aef161f553baa0bbc4e76f7926d5fe`.
The packaging policy is commit `1324b2833da3a6c58f57f274880d0428b00f0cda`.
The exact runner used for the recorded evidence is
`9f10ac5c2d8378ca7f9156889ea957b9cff497cf`. Dual-toolchain CI and both
durable matrices use evidence source commit
`7440108990c32f5c0b85c7acfadb9dc490296c39`.

| Role | Toolchain |
|---|---|
| Candidate packager and current-consumer check | `moon 0.1.20260819`, `moonc v0.10.9+6e6c44045` |
| CI-pinned consumer and package-policy probe | `moon 0.1.20260713`, `moonc v0.10.4+ade96c819` |

Both CLIs advertise `moon publish --dry-run`. The runner records that support
from `moon publish --help` but invokes no publish command. A credential-free,
network-isolated registry sandbox is unavailable, so executing the dry-run
would weaken rather than strengthen the zero-mutation evidence.

## First failures

Three failures shaped the candidate policy before implementation:

1. `moon package --list --frozen` from the repository workspace did not isolate
   `incr_next`; dependency hydration and unrelated workspace checks prevented a
   valid package baseline.
2. An unmodified isolated module archive contained 63 paths, including tests,
   K1 docs, `negative`, `private_evidence`, and the native RC executable
   harness, while omitting the Apache-2.0 license body.
3. Excluding all of `native_rc` produced an archive that checked but failed
   native test/run because root `moon.pkg` references `native_rc/rc_probe.c`.

The selected policy therefore packages an isolated copy, stages the
repository-root license bytes, excludes internal evidence with `.moonignore`,
and retains only the referenced C stub from `native_rc`.

## Tooling characterization

Current MoonBit 0.10.9 honors the selected `.moonignore` and produces the
17-file candidate. The CI-pinned 0.10.4 package-policy probe does not honor the
same file and produces 97 paths, including `_build`, tests, docs, and internal
evidence. K2.3 uses 0.10.9 as the candidate packager and separately proves that
the resulting artifact remains consumable by 0.10.4.

This version split is a packaging-tool constraint. It changes no Incr Next
source, public API, generated interface, or kernel contract.

## Candidate contents

The checked manifest is
[`distribution/package-files.txt`](../distribution/package-files.txt). It
contains:

- `moon.mod`, `moon.pkg`, and `pkg.generated.mbti`;
- the public `README.mbt.md` and staged root `LICENSE`;
- the production MoonBit source files;
- `native_rc/rc_probe.c`, required by root `moon.pkg` for native linking.

It excludes black-box and white-box tests, K1 validation history, negative
compile probes, private evidence, K2 evidence, and the native RC executable
package. The README uses repository-absolute links for material outside the
candidate.

## Reproducibility

Two isolated builds from the same source produced identical ZIP bytes and
identical extracted content manifests.

```text
archive SHA-256
543d715e965507fa5efcd7d790150a15f35746237cc8a261c6270147dcf78f9a

extracted manifest SHA-256
b69b64bd48416d6601632b52069f672bf14db50f514a6f1e277839ef9668a063
```

The ZIP itself is temporary and is not committed. Durable evidence is stored
under [`distribution/evidence/current/`](../distribution/evidence/current/) and
[`distribution/evidence/pinned/`](../distribution/evidence/pinned/). Each
matrix retains:

- `archive-sha256.txt`, `package-content-sha256.txt`, and `package-files.txt`;
- `tooling.txt` and exact `tooling.raw.txt.gz`;
- `dependency-tree.txt`;
- exact target stdout/stderr in `raw-commands.log.gz`;
- `summary.txt`.

The pinned directory additionally retains `policy-probe.txt` and its 97-path
archive manifest. Both matrix directories record the same candidate ZIP and
extracted-content hashes.

## Fresh non-repository workspace

The runner creates a fresh temporary directory containing only:

```text
moon.work
candidate/  # unpacked ZIP
consumer/   # accepted K2.1 public consumer
```

The fresh `moon.work` lists only `candidate` and `consumer`. `moon tree` resolves
`dowdiness/incr_next@0.1.0-alpha.1` to the unpacked local candidate. Searches of
candidate inputs and build metadata find no original checkout path, and the
candidate contains no symlink.

After the positive matrix, the runner removes `candidate`, clears build state,
and rewrites `moon.work` with only `consumer`. Frozen resolution then fails
because `dowdiness/incr_next` is absent from the registry. This negative control
shows that the successful matrix did not use registry or source-checkout
fallback.

## Target matrix

The current toolchain and the CI-pinned consumer toolchain both pass check,
test, and run through the unpacked candidate on every target:

| Target | Check | Test | Run output |
|---|---|---|---|
| default | PASS | PASS | PASS |
| native | PASS | PASS | PASS |
| JavaScript | PASS | PASS | PASS |
| wasm-gc | PASS | PASS | PASS |

Every run matches the accepted K2.1 output:

```text
initial.selected=2
initial.doubled=4
atomic_switch.selected=13
atomic_switch.doubled=26
switch_back.selected=5
switch_back.doubled=10
close.result=ClosedRegion
```

## Boundary results

```text
exact 17-file archive manifest       PASS
two-build ZIP reproducibility        PASS
two-build extracted manifest         PASS
README/license completeness          PASS
consumer public-only manifests       PASS
fresh local candidate resolution     PASS
candidate-absent frozen failure      PASS
original repository path             absent
candidate symlinks                   absent
testkit/private/negative evidence     absent
publish invocations                  0
registry mutations                   0
product/K0/public .mbti delta         absent
```

## Independent review

The first review correctly rejected a claim/evidence mismatch: current 0.10.9
consumption had passed only in temporary output, while durable evidence and CI
retained the pinned 0.10.4 matrix. Commit
`48cdfccb6398450b4f588522b241bd7da25b409c` added distinct current and pinned CI
steps and durable matrices. Re-review of that exact commit returned `APPROVE`
with no critical findings or warnings.

The remaining toolchain risk is explicit: 0.10.4 must not become the candidate
packager while it ignores the selected `.moonignore`.

## Reproduction

```bash
INCR_NEXT_K23_CONSUMER_MOON_BIN="$HOME/.cache/moonbit-k2-3-pinned/bin/moon" \
INCR_NEXT_K23_POLICY_PROBE_MOON_BIN="$HOME/.cache/moonbit-k2-3-pinned/bin/moon" \
INCR_NEXT_K23_OUTPUT_DIR=/tmp/k2-3-evidence \
  ./scripts/check-incr-next-k2-3-distribution.sh

./scripts/check-incr-next-k2-3-distribution-selftest.sh
```

The local gate establishes package preparability only. It does not authorize
publication, registry mutation, a version release, K0/kernel/API changes,
Canopy production integration, or K2.4 disposition.
