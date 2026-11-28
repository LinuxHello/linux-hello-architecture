---
type: adr
subject: Attested quality gates, fuzzing, SBOMs and signed releases
artifact: adr
status: accepted
owner: "@atterdag"
concepts: [supply-chain, governance, ci, fuzzing]
tags: [adr, ci, security, release]
sources: ["https://github.com/LinuxHello/linux-hello/blob/main/GOVERNANCE.md", "https://github.com/LinuxHello/linux-hello/blob/main/AGENTS.md", "https://github.com/LinuxHello/linux-hello/blob/main/.github/workflows/ci.yml", "https://github.com/LinuxHello/linux-hello/blob/main/.github/workflows/release.yml", "https://github.com/actions/attest/tree/v4.2.2", "https://slsa.dev/spec/v1.0/provenance", "https://slsa.dev/spec/v1.2/", "https://slsa.dev/spec/v1.2/build-requirements", "https://slsa.dev/spec/v1.2/source-requirements", "https://slsa.dev/spec/v1.2/verification_summary", "https://docs.github.com/en/actions/security-for-github-actions/using-artifact-attestations/using-artifact-attestations-and-reusable-workflows-to-achieve-slsa-v1-build-level-3"]
date: 2026-11-28
---

# ADR-0006: Attested quality gates and releases

## Status

Accepted, 2026-11-18, on the maintainer's decision (proposed 2026-11-03).

## Context

Most code here is written by coding agents and reviewed by behaviour ([GOVERNANCE.md](https://github.com/LinuxHello/linux-hello/blob/main/GOVERNANCE.md)). Required checks already block a merge on fmt, clippy (`-D warnings`), tests, cargo-deny, cargo-audit, unsafe-policy and DCO. Three gaps remain:

1. **No fuzzing.** [AGENTS.md](https://github.com/LinuxHello/linux-hello/blob/main/AGENTS.md) requires fuzzing for every parser once one exists. The routing-policy parser (`policy::schema::parse`) exists and was not fuzzed. Writing the fuzz target exposed an unchecked multiplication: `reverify_after = "213503982334602d"` parsed, then `total_seconds()` panicked in debug builds and wrapped to an arbitrary value in release builds.
2. **No evidence outside GitHub's check UI.** A green check is a mutable record in one web interface; nobody can later prove that a given commit passed the gates.
3. **No release process.** Nothing is released yet, but once it is, users need to verify what is in a binary and where it was built.

GitHub artifact attestations (`actions/attest`, v4.2.2 checked) sign in-toto statements with a short-lived Sigstore certificate. For a public repository the public-good Sigstore instance is used, and the signature is recorded in its transparency log. The certificate names the workflow, the ref and the commit of the run. `gh attestation verify` checks them.

## Decision

### Quality gate

A **passed quality gate** for a commit means every CI job listed in [`scripts/ci/quality-gates.txt`](https://github.com/LinuxHello/linux-hello/blob/main/scripts/ci/quality-gates.txt) succeeded on it: `fmt`, `clippy`, `test`, `cargo-deny`, `cargo-audit`, `unsafe-policy`, `fuzz`, `docs` (added by [ADR-0008](0008-code-documentation-mapped-to-c4.md)). On a pull request, `dco` must also succeed.

- **`fuzz`** runs every cargo-fuzz target for 60 seconds ([`scripts/ci/fuzz.sh`](https://github.com/LinuxHello/linux-hello/blob/main/scripts/ci/fuzz.sh)) on a pinned nightly. A crash fails the job and the crashing input is kept as a workflow artifact. Each target is seeded with inputs near the limits it checks. The smoke run is a regression net, not exhaustive fuzzing, so every crash it finds also gets a named unit test.
- **`quality-gate`** is the aggregate required check. It always runs, so a skipped gate cannot count as passed. It fails unless every gate succeeded and its `needs:` list matches `quality-gates.txt`. It then signs an attestation and verifies it.

### Docs-only pull requests

A pull request whose every changed path is documentation may skip the eight gate jobs. The rule is fail-closed and applies to pull requests only:

- **Documentation paths** are `docs/**` and the root files `README.md`, `GOVERNANCE.md`, `SECURITY.md`, `CONTRIBUTING.md`, `AGENTS.md` and `CLAUDE.md`. Any other path, including `architecture` (the submodule pointer), `policy/`, `scripts/`, `.github/` and every crate, makes the pull request a code pull request. An empty or unreadable file list also counts as code.
- **A push to `main` always runs every gate.** A squash merge is a new commit, so the commit that ships is gated in full. The release check relies on that attestation, so a released commit has passed all eight gates whatever its pull request skipped.
- **`quality-gate` still decides.** It accepts `skipped` for a gate only when the change classification says docs-only; any other skip fails. `dco` always runs.
- **The predicate says what happened.** `passed` lists the gates that succeeded and `skipped` lists those that did not run, so an attestation never claims a gate that was skipped. The subject is unchanged.

### quality-gate-v1

- **Subject:** a canonical JSON file `{"commit","gates","repository","type":"quality-gate/v1"}`, printed by [`scripts/ci/quality-gate-subject.sh`](https://github.com/LinuxHello/linux-hello/blob/main/scripts/ci/quality-gate-subject.sh). It is deterministic, so anyone can rebuild it from the commit. A Git commit cannot be the subject directly, because `actions/attest` takes only sha256 digests.
- **Predicate type:** `https://github.com/LinuxHello/linux-hello/blob/main/docs/adr/0006-attested-quality-gates-and-releases.md#quality-gate-v1`
- **Predicate:** commit, pull request head, ref, event, run URL, Rust toolchain, gates passed.
- **Signed by:** `.github/workflows/ci.yml` on a GitHub-hosted runner. The attested commit is always the one the gate jobs checked out. On `main` that is the pushed commit (`source-ref refs/heads/main`). On a pull request it is GitHub's merge commit of the head into the base (`source-ref refs/pull/<n>/merge`), with the head recorded in the predicate. Either way, `source-digest <commit>` binds the certificate to it.
- **Verify:** `scripts/ci/verify-quality-gate.sh <commit> [ref]` or `make verify-gate SHA=<commit>`. The script downloads the bundle and verifies it locally, because the attestations API refuses a custom predicate type as a lookup filter (HTTP 422).

### Merge and release requirements

- **Merge:** `quality-gate` is a required status check. Because it succeeds only after the attestation for the commit the gates tested is signed and verified, a pull request cannot merge without one. The required check is pinned to the GitHub Actions app (integration ID 15368), together with `fuzz` and `unsafe-policy`, so no other app can satisfy it by posting a passing status under the same name ([`scripts/admin/apply-merge-settings.sh`](https://github.com/LinuxHello/linux-hello/blob/main/scripts/admin/apply-merge-settings.sh)). Reviewers (lead, Copilot, maintainer) confirm the check passed. Anyone can re-verify with the script.
- **Squash commits:** a squash merge creates a new commit, so the push to `main` runs CI again and attests the commit that actually ships. Squash commit messages take the pull request title and body (repository setting, [`scripts/admin/apply-merge-settings.sh`](https://github.com/LinuxHello/linux-hello/blob/main/scripts/admin/apply-merge-settings.sh)).
- **Release:** a crate tag (`agent-v0.1.0`) triggers [`release.yml`](https://github.com/LinuxHello/linux-hello/blob/main/.github/workflows/release.yml). Nothing is published unless:
  1. the tagged commit is on `main` and its quality-gate attestation verifies;
  2. binaries (bin and cdylib targets), a source archive, `SHA256SUMS` and a CycloneDX 1.5 SBOM (`cargo-cyclonedx` 0.5.9, every dependency at its `Cargo.lock` version) are built from it;
  3. SLSA build provenance is signed for every file, `SHA256SUMS` included, and an SBOM attestation for the binaries and the source archive;
  4. a separate publish job, which alone can write releases, re-checks every checksum and attestation before it creates the GitHub release.

### What this ADR does not adopt from the original proposal

- **Separate cosign signatures.** Artifact attestations already sign with Sigstore (Fulcio certificate, Rekor log). Signing the same files again with `cosign sign-blob` would add a second key path to verify and no new assurance.
- **A per-PR "attestation present" check separate from the gates.** It would verify a statement that the same workflow just produced. The required `quality-gate` check is that gate.
- **Aider-specific rules.** Aider has no role in [ADR-0004](0004-agent-roles.md). The pull request structure is set in the template and [AGENTS.md](https://github.com/LinuxHello/linux-hello/blob/main/AGENTS.md) for every agent; adding Aider would amend ADR-0004.

### Amendment 2026-11-28 (proposed): which SLSA levels the releases claim

This ADR says that releases carry "SLSA build provenance", but not which level of SLSA they reach. Without a level, the phrase promises little. A user cannot tell whether someone who changes the build could also have forged the record of it. This amendment states the levels, shows which part of the release workflow meets each requirement, and adds one CI check that keeps the claim true.

[SLSA](../arc42/12-glossary.md#slsa) (Supply-chain Levels for Software Artifacts, said "salsa") is a specification of the Open Source Security Foundation (OpenSSF). It says how much a user can trust that a downloaded file was built from the source it claims, by the process it claims. The current version is 1.2. It has two *tracks*, each with numbered levels. The **Build track** is about how a file was built. The **Source track** is about how the source code was changed and reviewed. A level is a claim that a fixed list of requirements is met. A higher level adds requirements, and it means nothing unless every requirement below it is met too.

In plain words: the releases reach **Build level 3**, the highest level on the Build track, and the repository reaches **Source level 1**. This amendment does not claim Source level 2 or higher. Nothing has been released yet, so these levels are claims about the workflow. A release first shows that the workflow works when the first tag runs and `publish` verifies every file.

1. **Build level 2: the build runs on a hosted platform, and the provenance is signed.** Every job of [`release.yml`](https://github.com/LinuxHello/linux-hello/blob/main/.github/workflows/release.yml) runs on a [GitHub-hosted runner](../arc42/12-glossary.md#github-hosted-runner) (`ubuntu-24.04`). A GitHub-hosted runner is a fresh virtual machine that GitHub starts for one job and then throws away. The [build provenance](../arc42/12-glossary.md#build-provenance), a signed record that says which workflow built a file, from which tag and commit, is signed through [Sigstore](../arc42/12-glossary.md#sigstore). Sigstore is a public signing service that issues a certificate for one workflow run instead of a long-lived key. Anyone can check the provenance with `gh attestation verify <file> --repo LinuxHello/linux-hello --signer-workflow LinuxHello/linux-hello/.github/workflows/release.yml --source-ref refs/tags/<tag>`.
2. **Build level 3, first requirement: the build cannot forge its own provenance.** SLSA requires that the signing secret "MUST NOT be accessible to the environment running the user-defined build steps". The *user-defined build steps* are the commands the project chooses to run: here `cargo build`, with every build script and procedural macro of every dependency, and `cargo-cyclonedx`. The secret is the token from which GitHub issues the Sigstore certificate (`id-token: write`). The workflow already keeps the two apart, as a fix for finding R-24 of the [security review of 22 November 2026](https://linuxhello.github.io/security-review.html) (LinuxHello/linux-hello#366):
   - the `build` job runs every build step with `permissions: contents: read` and no signing token;
   - the `attest` job holds the signing token, runs no build step and no project code, and signs only after it has checked that the files are the ones `build` reported, through the digest of `SHA256SUMS` that `build` passed on;
   - `attest` runs in the protected environment `release`, so the maintainer must approve the run before anything is signed (finding R-06, LinuxHello/linux-hello#349).

   A dependency whose build script is malicious can therefore change a binary, but it cannot sign a statement about it. It also cannot make the provenance name another workflow, tag or commit.
3. **Build level 3, second requirement: each build is isolated.** SLSA requires that every build runs in a fresh environment and that one build cannot change another. Each job gets a new virtual machine. `release.yml` uses no cache, so nothing that an earlier run left behind reaches a release build. A shared cache (`actions/cache`, or `cache: true` in a toolchain action) would break this requirement: a pull request run could poison the cache, and the release would build from it.
4. **Who could still forge it, and what stops them.** SLSA calls the people who control a build's own steps its *tenants*. Here that is anyone who can change `release.yml` at a release tag, because a changed `attest` job could sign anything. Two *rulesets* hold this shut. A ruleset is a set of rules that GitHub enforces on a repository's branches or tags, whatever a person or a workflow tries. Both are set today, and both were read from the repository on 28 November 2026:
   - the `main` ruleset lets a change reach `main` only through a pull request that passes the required checks, and forbids force-pushes and deleting the branch;
   - the `release tags` ruleset lets only repository administrators create, move or delete a tag, and every tag must be signed.

   So a forged `attest` job would have to pass review and be merged, and then the maintainer would have to tag it and approve it.
5. **Why not GitHub's recipe with a reusable workflow.** GitHub's documentation reaches Build level 3 by moving the build and the signing into a *reusable workflow*. A reusable workflow is a workflow file that other workflows call, and it signs under its own name. GitHub's recipe protects a caller from changing the signing steps, because the reusable workflow lives somewhere the caller cannot edit. Here the caller and the signer would sit in the same repository, under the same rulesets, with the same maintainer. Such a move would change the name in the certificate and nothing else. Splitting the build and the signing into two jobs already gives what SLSA asks for. A separate repository for the signing workflow, with its own maintainers, would add a real barrier. The project has one maintainer, so that is not adopted now.
6. **Self-hosted runners stay refused.** SLSA level 3 allows a build to call out to a self-hosted runner, a machine the project runs itself, as long as that machine is not trusted to sign. The checks here are stricter: every `gh attestation verify` passes `--deny-self-hosted-runners`, so a file built on the maintainer's workstation can never pass for a release. [ADR-0009](0009-self-hosted-runner.md) relies on this, because there the workstation only rebuilds and compares, and never signs.
7. **Source level 1, and why not higher.** Source level 1 asks that the source is kept in a modern version control system; Git on GitHub meets it. Source level 2 asks that the source control system itself issues a signed source provenance for every new commit on a protected branch. GitHub issues none for this repository. The quality-gate attestation is signed by this project's CI, not by GitHub's source control, so it does not stand in for it. The history requirements of level 2 are already enforced by the `main` ruleset (no force-push, no deletion, linear history). Level 3 builds on level 2. Level 4 asks that two trusted persons review every change to a protected branch. Today one person, the maintainer, reviews code that AI agents wrote ([ADR-0004](0004-agent-roles.md)). Level 4 becomes possible only with a second human maintainer.
8. **The quality-gate attestation stays `quality-gate/v1`.** SLSA defines a *verification summary attestation* (VSA). Its *predicate type*, the name that says what kind of statement an attestation makes, is `https://slsa.dev/verification_summary/v1`. A VSA is a signed statement that a verifier checked an artifact against a policy and found it at given SLSA levels. Its required fields are `verifier`, `resourceUri`, `policy`, `verificationResult` and `verifiedLevels`. The quality gate checks something else: that formatting, lints, tests, licence and security-advisory checks, fuzzing and documentation passed for a commit. It verifies no SLSA level. Recording it as a VSA would mislabel it, so the custom predicate stays.
9. **What the code gains: one check that keeps the claim true.** A new CI job, `release-workflow-policy`, runs on every pull request and every push to `main` and fails when `release.yml` breaks one of the requirements above. It joins the quality gates in `scripts/ci/quality-gates.txt`, so it changes what later attestations list, as this ADR requires. It checks that:
   - every job runs on a GitHub-hosted label (`ubuntu-*`);
   - `id-token: write` and `attestations: write` appear only in the job `attest`, and that job has no `run:` step that calls `cargo`, `make` or a script from the repository;
   - no step uses `actions/cache` or turns on a toolchain action's cache;
   - every `gh attestation verify` in the workflow passes `--deny-self-hosted-runners`.

   Tests the code will name: `a_job_on_a_self_hosted_label_fails`, `a_signing_token_outside_attest_fails`, `a_build_step_in_attest_fails`, `a_cache_in_the_release_workflow_fails`, `a_verify_without_deny_self_hosted_fails`, `the_current_release_workflow_passes`. The notes of each release then name the claim: "SLSA Build level 3, see ADR-0006", with a link to this amendment.

Not decided here: reproducible builds, which let a second builder confirm the same bytes from the same source. [ADR-0009](0009-self-hosted-runner.md) tests them with a rebuild on the maintainer's workstation, and SLSA does not need them for any level claimed here.

## Consequences

**Easier:**

- Anyone can prove, without trusting GitHub's UI, that a commit on `main` passed every gate, and which gates those were.
- Users can verify a released file's origin (repository, workflow, tag, commit) and contents (SBOM) with one `gh attestation verify` command.
- A release states a checkable SLSA claim, Build level 3 and Source level 1 (amendment of 2026-11-28, if accepted), instead of "SLSA build provenance" with no level.
- Parser crashes are caught before merge; the policy parser now refuses durations that overflow.
- One aggregate required check survives path filtering. Documentation-only pull requests skip the Rust gates; per-crate filtering is not adopted, because the gates are workspace-wide and `linuxhello-dbus` is linked into every container.
- `make fix` and `make gates` give agents and humans the same local entry point as CI.

**Harder:**

- Pull requests from forks cannot be attested (forks get no OIDC token), so their `quality-gate` fails. The maintainer pushes the reviewed branch to this repository to attest it.
- CI takes longer: about two minutes for the fuzz build and run, plus the attestation job.
- A nightly toolchain is pinned for fuzzing and must be bumped by pull request. The fuzz crate is a separate workspace, so the root `cargo deny` and `cargo audit` do not cover its `Cargo.lock`; Dependabot does. Its one dependency, `libfuzzer-sys`, is `(MIT OR Apache-2.0) AND NCSA`. NCSA is permissive but not on the allow-list, so dependency review exempts that one package. It is linked only into fuzz binaries, which are never released.
- Changing `quality-gates.txt` changes what later attestations claim, so it needs the same review as a gate change.
- A tag pushed before CI on `main` finishes fails the release gate and must be re-run.
- The release workflow has not run yet. The first tag is its first test.
- `release.yml` may not use a cache, a self-hosted runner, or a signing token outside the job `attest` (amendment of 2026-11-28, if accepted). A new gate, `release-workflow-policy`, fails any change that breaks this. Release builds therefore always compile from scratch.
- Source level 2 needs signed source provenance that GitHub does not issue, and level 4 needs a second human reviewer. Neither can be claimed until that changes.
