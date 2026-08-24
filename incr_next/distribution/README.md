# Incr Next distribution candidate policy

**Reader:** Maintainers and reviewers of Plan 016 K2.3 distribution evidence.

**Decision:** Build an unpublished candidate from an isolated staging copy of
`incr_next`, constrained by `.moonignore` and the checked file manifest.

**Keep until:** The K2 product disposition is accepted.

**Disposition:** At K2 closure, retain this policy with the product package or
delete it with the disposition rationale.

## Included content

The candidate contains the module and package manifests, public README,
production MoonBit sources, generated public interface, Apache-2.0 license, and
`native_rc/rc_probe.c`. The root `moon.pkg` names that C file as a native stub,
so native consumer linking requires it. The native RC executable harness and
its package manifest remain excluded.

The repository-root `LICENSE` is the single source of truth. The checker copies
it into isolated staging immediately before packaging and verifies the staged
bytes. No second tracked license copy is maintained.

## Excluded content

`.moonignore` excludes black-box and white-box tests, K1 validation history,
negative compile probes, private evidence, the native RC executable harness,
and K2 distribution evidence. These files remain repository validation assets;
they are not consumer product content.

The expected sorted archive paths are in `package-files.txt`. The checker uses
MoonBit's own `moon package --list --frozen` in an isolated module copy, then
compares the produced archive with that manifest. It does not emulate
`.moonignore` semantics.

## Safety boundary

The checker never invokes `moon publish`. It captures `moon publish --help` and
records whether `--dry-run` is supported. A supported option remains
unexecuted because this local gate has no network-isolated credential-free
registry sandbox. Publication and registry mutation remain unauthorized.

The generated ZIP is temporary and is never committed. Durable evidence keeps
its SHA-256, extracted content hashes, dependency tree, commands, and validation
result without storing the archive itself.
