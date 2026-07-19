# Plan 007: Make the documentation-boundary checker validate `file.md:line` links

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat f839477..HEAD -- scripts/check-documentation-boundaries.py scripts/check-documentation-boundaries-selftest.sh`
> If either file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `f839477`, 2026-07-19

## Why this matters

`scripts/check-documentation-boundaries.py` is the CI gate (job step in
`.github/workflows/ci.yml`, "enforce documentation boundaries") that keeps
Markdown links in this repo pointing at files that exist. Its own comment says
source-location links of the form `file.md:line` must have their file part
validated. That validation is currently unreachable for the common
bare-filename form: Python's `urlsplit("README.md:42")` parses `readme.md` as
a URL *scheme*, so `is_external()` classifies the link as external and skips
it entirely. A broken link like `[see](MISSING.md:10)` passes CI. The
path-qualified form `docs/foo.md:12` IS validated (a `/` disqualifies the
scheme), so the checker's behavior is silently inconsistent. The selftest that
CI runs as the checker's regression control never exercises this branch, which
is why the defect shipped green.

## Current state

Relevant files:

- `scripts/check-documentation-boundaries.py` — the checker. The bug is the
  interaction between `is_external` (lines 59–67) and the `file.md:line`
  handler (lines 103–109).
- `scripts/check-documentation-boundaries-selftest.sh` — bash selftest run by
  CI before the checker; builds a throwaway git repo in `mktemp -d` and
  asserts pass/fail cases.

Checker excerpt as of `f839477` (`scripts/check-documentation-boundaries.py:59-67`):

```python
def is_external(target):
    parsed = urlsplit(target)
    return (
        not target
        or target.startswith("#")
        or target.startswith("//")
        or parsed.scheme in {"mailto"}
        or bool(parsed.scheme)
    )
```

And the link loop (`scripts/check-documentation-boundaries.py:100-112`):

```python
        for target in link_targets(text):
            if is_external(target):
                continue
            parsed = urlsplit(target)
            path = unquote(parsed.path)
            # Markdown source-location links commonly use `file.md:line`.
            # Validate the file target while leaving the line fragment unchecked.
            location = re.fullmatch(r"(.+\.(?:mbt\.)?md):\d+", path)
            if location:
                path = location.group(1)
            resolved = (root / path.lstrip("/")) if path.startswith("/") else source.parent / path
            if not resolved.exists():
                missing.append(f"{source.relative_to(root)}:{target}")
```

Reproduction of the root cause (run it yourself to confirm):

```bash
python3 -c "from urllib.parse import urlsplit; print(urlsplit('README.md:42').scheme)"
# prints: readme.md   ← truthy scheme ⇒ is_external() returns True ⇒ link skipped
python3 -c "from urllib.parse import urlsplit; print(repr(urlsplit('docs/foo.md:12').scheme))"
# prints: ''          ← path-qualified form is NOT skipped
```

Selftest excerpt as of `f839477`
(`scripts/check-documentation-boundaries-selftest.sh:48-50`) — the only
broken-link fixture has no `:line` suffix:

```bash
printf '[missing](missing.md)\n' > docs/broken.md
git add -A
expect_failure 'docs/broken.md:missing.md'
```

Known facts verified at planning time:

- The repo currently contains exactly two bare `file.md:line` links, both in
  `docs/performance/2026-06-16-incr-tea-shared-vs-independent-inactive-root-cohorts.md`
  lines 61–62, and **both targets exist** — so fixing the checker does not
  break CI on current docs.
- Repo convention: the selftest uses the `expect_failure '<message>'` helper
  defined at `scripts/check-documentation-boundaries-selftest.sh:26-37`; new
  failure cases must follow that pattern (create fixture → `git add -A` →
  `expect_failure` → restore fixture).

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Run checker on repo | `python3 scripts/check-documentation-boundaries.py` (from repo root) | exit 0, prints `Documentation boundaries OK: ...` |
| Run selftest | `bash scripts/check-documentation-boundaries-selftest.sh` | exit 0, prints `Documentation boundary checker self-test OK.` |

No MoonBit commands are needed; this plan touches only Python and bash.

## Scope

**In scope** (the only files you may modify):

- `scripts/check-documentation-boundaries.py`
- `scripts/check-documentation-boundaries-selftest.sh`

**Out of scope** (do NOT touch, even though they look related):

- `.github/workflows/ci.yml` — the CI wiring already runs both scripts;
  nothing to change.
- Any `.md` documentation file — both existing `file.md:line` links are valid;
  if the fixed checker reports repo docs as broken, that is a STOP condition,
  not a license to edit docs.

## Git workflow

- Branch: `advisor/007-doc-boundary-file-line-links` (do not commit to `main`).
- Commit style: conventional commits, e.g. `fix(scripts): validate bare
  file.md:line links in doc-boundary checker` (matches repo history such as
  `fix(datalog): enforce relation-rule lifetimes (#412)`).
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Reorder the `file.md:line` extraction before the external check

In `scripts/check-documentation-boundaries.py`, move the source-location
extraction so it runs on the raw `target` BEFORE `is_external` is consulted.
Target shape of the loop body:

```python
        for target in link_targets(text):
            # Markdown source-location links commonly use `file.md:line`.
            # Strip the line fragment first: a bare `file.md:42` otherwise
            # parses as URL scheme `file.md` and is misclassified as external.
            location = re.fullmatch(r"(.+\.(?:mbt\.)?md):\d+", target)
            candidate = location.group(1) if location else target
            if is_external(candidate):
                continue
            parsed = urlsplit(candidate)
            path = unquote(parsed.path)
            resolved = (root / path.lstrip("/")) if path.startswith("/") else source.parent / path
            if not resolved.exists():
                missing.append(f"{source.relative_to(root)}:{target}")
```

Notes:
- Keep the reported violation string as `f"{source...}:{target}"` (the
  ORIGINAL target including `:line`), so the selftest message format and any
  operator expectations stay stable.
- Leave `is_external` itself unchanged — genuine external links
  (`https://...`, `mailto:...`, `#anchor`, `//host`) must keep being skipped.
- Do not remove the `unquote(parsed.path)` handling; percent-encoded local
  links must keep working.

**Verify**: `python3 scripts/check-documentation-boundaries.py` → exit 0,
`Documentation boundaries OK: ...` (the two existing `file.md:line` links in
`docs/performance/2026-06-16-incr-tea-shared-vs-independent-inactive-root-cohorts.md`
resolve, so nothing new is reported).

**Verify (known-positive control, throwaway)**: from a temp dir replicate a
minimal repo (copy the selftest's setup pattern) containing
`[x](missing.md:12)` in `docs/broken.md` and confirm the checker now exits
non-zero mentioning `docs/broken.md:missing.md:12`. Alternatively defer this
to the Step 2 selftest fixture — but do not skip both.

### Step 2: Add selftest fixtures for the `file.md:line` branch

In `scripts/check-documentation-boundaries-selftest.sh`, after the existing
broken-link case (lines 48–50), add:

1. **Broken bare source-location link must fail** (the regression control for
   this very bug):

```bash
printf '[missing line link](missing.md:12)\n' > docs/broken.md
git add -A
expect_failure 'docs/broken.md:missing.md:12'
```

2. **Valid bare source-location link must pass**: replace `docs/broken.md`
   with `[ok](README.md:1)` (docs/README.md exists in the fixture repo),
   `git add -A`, then run `python3 "$checker"` bare — under `set -euo pipefail`
   a non-zero exit fails the selftest, which is the assertion.
3. Clean up the fixture file afterwards (`rm docs/broken.md; git add -A`) so
   the final state stays green, matching how earlier cases restore state
   (e.g. line 46 restores `example/README.md`).

**Verify**: `bash scripts/check-documentation-boundaries-selftest.sh` → exit
0, `Documentation boundary checker self-test OK.`

**Verify (known-positive control)**: temporarily revert the Step 1 change
(`git stash push scripts/check-documentation-boundaries.py` or comment the
reorder), run the selftest, and confirm it now FAILS at the new
`missing.md:12` case; restore the fix and confirm it passes again. This
proves the new fixture actually detects the bug it guards against.

## Test plan

Covered by Step 2: the selftest is this script's test suite. New cases:
broken `file.md:line` (must fail), valid `file.md:line` (must pass). Existing
cases (archive dir, missing member README, plain broken link) must keep
passing unchanged.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `python3 scripts/check-documentation-boundaries.py` exits 0 on the repo
- [ ] `bash scripts/check-documentation-boundaries-selftest.sh` exits 0 and
      its output shows no `FAIL:` lines
- [ ] The selftest contains the string `missing.md:12` (new fixture present):
      `grep -c 'missing.md:12' scripts/check-documentation-boundaries-selftest.sh` ≥ 1
- [ ] With the checker fix reverted, the selftest fails (known-positive
      verified once during Step 2)
- [ ] `git status` shows modifications only to the two in-scope files
- [ ] `plans/README.md` status row for 007 updated

## STOP conditions

Stop and report back (do not improvise) if:

- The checker code at lines 59–67 / 100–112 does not match the "Current
  state" excerpts (drift since `f839477`).
- After Step 1, `python3 scripts/check-documentation-boundaries.py` reports
  violations in real repo docs — the planning-time survey found none, so any
  hit means either your change is wrong or docs drifted; report the list
  instead of editing docs.
- The selftest's known-positive control does NOT fail with the fix reverted
  (would mean the fixture is vacuous).

## Maintenance notes

- Anyone extending `is_external` (new schemes, protocol-relative forms) must
  keep the `file.md:line` strip ordered before it, or the bug reintroduces
  silently — the new selftest fixture is the guard.
- Reviewer should scrutinize: that genuinely external links containing `.md:`
  in a path (e.g. `https://host/x.md:1`) are still treated external — the
  strip regex only matches when the WHOLE target ends in `.md:<digits>`, and
  `is_external` then sees `https://host/x.md`, still scheme-bearing, still
  skipped. A quick manual `urlsplit` check in review is cheap.
- Deferred (not this plan): validating the `:line` number against file length
  — the checker's stated contract leaves line fragments unchecked.
