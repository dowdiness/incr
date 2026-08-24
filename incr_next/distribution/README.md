# Incr Next distribution candidate policy

**Reader:** Maintainers of Incr Next candidate packaging.

**Decision:** Build an unpublished candidate from an isolated staging copy of
`incr_next`, constrained by `.moonignore` and the checked file manifest.

**Keep until:** Superseded by an accepted package policy.

**Disposition:** Retained at K2 closure as the active package policy and as a
prerequisite for the recommended separate alpha publication commission.

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

The generated ZIP is temporary and is never committed. K2 closure removed raw
command snapshots after preserving the accepted conclusions in the
[sibling-product ADR](../../docs/decisions/2026-08-17-incr-next-pre-1-0-sibling-product.md)
and the hashes in the [K2.3 validation record](../docs/k2-3-validation.md). The immutable K2.3
merge tree remains available for historical audit.
