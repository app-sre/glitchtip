---
name: glitchtip-upgrade
description: Runs a full GlitchTip version upgrade in this repo — finds or creates the version-bump branch, tracks the work in a Jira ticket, bumps GLITCHTIP_VERSION and the frontend image digest in the Dockerfile, summarizes upstream changes with an unmissable callout for anything touching authentication/authorization (cross-checking the actual GitLab commit range, since the upstream CHANGELOG file lags behind releases), verifies and regenerates the local patches/ against the new upstream source, fixes (not ignores) any lint/build drift surfaced along the way, and keeps README.md's upgrade docs current. Use this whenever the user wants to upgrade/bump GlitchTip, mentions a glitchtip-frontend Renovate or Mintmaker PR (branch names like konflux/mintmaker/main/glitchtip-frontend), asks what changed in a new GlitchTip release, wants to check the GlitchTip CHANGELOG for breaking or auth-relevant changes, or needs to verify/regenerate the patches/*.patch files after a version bump.
---

# GlitchTip Upgrade

This repo ships a Red Hat AppSRE fork of [GlitchTip](https://glitchtip.com) that layers local
patches on top of the upstream `glitchtip-frontend` image (see `README.md` → "Customizations").
Upgrading means: bump the pinned version, make sure the patches still apply to the new upstream
source, and understand what changed upstream — especially anything auth-related, since that's the
one class of change that has actually broken things silently before.

Do the steps below **in order**. Each one produces something the next one needs.

## 0. Establish current and target version

Read `ARG GLITCHTIP_VERSION=` from the top of `Dockerfile` — that's the current version. If the
user hasn't named a target version, ask them, or check for open Renovate/Mintmaker PRs (step 1) —
their PR title/branch name usually carries it (e.g. branch `konflux/mintmaker/main/glitchtip-frontend`
bumping `6.2.2` → `6.2.3`).

## 1. Get onto the right branch

**Ask the user whether there's already an open Renovate/Mintmaker PR for this bump** (they open
automatically — look for one with `gh pr list --search "glitchtip-frontend"` if unsure, or the user
may hand you a link like `https://github.com/app-sre/glitchtip/pull/892`).

- **If yes:** first check whether a local branch with that PR's head branch name already exists
  (`gh pr view <number> --json headRefName`, then `git branch --list <headRefName>`). Bots like
  Konflux/Mintmaker reuse the same branch name (e.g. `konflux/mintmaker/main/glitchtip-frontend`)
  across every bump cycle, so a leftover local branch from a previous upgrade is stale by
  definition — delete it (`git branch -D <headRefName>`) before checking out, otherwise `gh pr
  checkout` may leave you on outdated commits instead of the PR's current head. Then run `gh pr
  checkout <number>` — this works the same whether the PR's branch lives in this repo or a fork, gh
  resolves it either way. You'll build on top of what the bot already did.
- **If no:** create a new branch yourself, e.g. `git checkout -b chore/upgrade-glitchtip-<version>`.

Either way, **do not assume the bot's PR is complete.** Historically these PRs only touch the
`Dockerfile` version/digest lines and leave the patches unverified — see the `f4c465e` commit
message in this repo's history, which explicitly replaced a Renovate PR (#874) "which only bumped
the version and left the build broken." Treat whatever is already in the PR as a starting point for
step 2, not as done.

Before switching branches, run `git status` — if there are uncommitted changes that aren't part of
this upgrade, stash them (`git stash push -- <files>`) rather than losing or carrying them onto the
wrong branch.

## 2. Track the work in Jira

**Ask the user whether a Jira ticket already exists for this upgrade** (past upgrades have one, e.g.
`APPSRE-14911` for the 6.2.2 bump — search with the `jira` skill if unsure:
`project = APPSRE AND summary ~ "GlitchTip" ORDER BY created DESC`).

- **If yes:** use that ticket and keep it updated as you go (see below).
- **If no:** create one with the `jira` skill — project `APPSRE`, type `Task`, assigned to the
  user. Match the format of prior upgrade tickets: a `## Summary` line, a `## Reference` section
  linking the PR, and a `## Tasks` checklist mirroring steps 3-6 below (changelog review, patch
  verification, local build, PR merge, staging/production rollout verification).

Update the ticket's task checklist as you complete each step below — don't leave it all unchecked
until the end, and don't leave it stale after you're done. The point of the ticket is that someone
who wasn't in this conversation can see what was checked and why.

## 3. Bump the Dockerfile

Three places in `Dockerfile` need to agree on the version (grep for `GLITCHTIP_VERSION` and
`glitchtip-frontend:` to find them all — there are two `COPY --from=` lines plus the top `ARG`):

1. `ARG GLITCHTIP_VERSION=<old>` → `<new>`
2. `COPY --from=registry.gitlab.com/glitchtip/glitchtip-frontend:<old>@sha256:<olddigest> /code/LICENSE ...`
3. `COPY --from=registry.gitlab.com/glitchtip/glitchtip-frontend:<old>@sha256:<olddigest> --chown=1001:root /code ./`

The digest must be pinned (see the comment above line 1 in the Dockerfile explaining why — Konflux's
SBOM/EC policy requires a literal `COPY --from=` reference, not an ARG). Resolve the new digest
without pulling the full image:

```bash
docker buildx imagetools inspect registry.gitlab.com/glitchtip/glitchtip-frontend:<new-version>
```

Use the `Digest:` line from the output for both `COPY --from=` references — they must match each
other and the tag. If a bot PR already set these, verify the digest independently with the command
above rather than trusting it blindly — it's a 10-second check.

## 4. Find out what actually changed upstream — don't trust the CHANGELOG file alone

Fetch `https://gitlab.com/glitchtip/glitchtip-backend/-/raw/master/CHANGELOG` first. Entries are
level-2 headings per version (`# 6.2.2`), newest first, with bullets prefixed by category
(`Security:`, `Change:`, `Feat:`, `Fix:`, `Deps:`, ...).

**The CHANGELOG file lags behind actual releases** — a version can be tagged and published as a
container image before anyone updates the CHANGELOG for it. If the target version has no heading in
the CHANGELOG, do not fall back to summarizing the previous version and calling it done — that
silently misses everything in the release you're actually shipping. Instead, get the real commit
list between the two tags and read it directly:

```
https://gitlab.com/glitchtip/glitchtip-backend/-/compare/v<old>...v<new>
```

This is not a rare edge case to shrug off — in practice it's where the interesting changes hide
(e.g. the 6.2.2→6.2.3 range shipped a brand-new per-organization SSO feature and a round of SSRF
hardening with no CHANGELOG entry at all yet). Read the commit titles and, for anything ambiguous,
the commit body — merge commits and one-line "fix" titles often undersell what actually changed.

Summarize what you find in two parts, and **do not merge them into one list** — the split is the
point:

1. **General changes** — a normal bullet list of what's new/fixed/changed.
2. **⚠️ Auth changes requiring manual staging verification** — its own clearly-marked section, even
   if it only has one item, even if you're not fully sure something counts. Scan for anything
   touching: login/logout, SSO/OIDC/SAML, OAuth (including token hashing/scopes), sessions, 2FA/MFA,
   passwords/credentials, roles/permissions/RBAC, API tokens, invitations/member-add flows,
   organization ownership/membership integrity, or security fixes that are auth-adjacent (e.g. SSRF
   via a feature that acts on a user's behalf). If this section is empty, say so explicitly ("no
   authN/authZ-relevant changes in this range") rather than omitting the section — an absent section
   reads as "nobody checked."

This section exists because `patches/00-skip-user-invitation-process.patch` rewrites organization
member creation to bypass GlitchTip's own invitation/auth flow — upstream auth changes are the most
likely thing to silently break it. Whatever you find here, tell the user it needs **manual testing
on the staging instance** before promotion to production (see `README.md` → "Post-Upgrade
Checklist" → "OIDC / SSO login works").

## 5. Verify the patches still apply — and fix them if not

`patches/*.patch` are applied during the Docker build (see the `RUN cat patches/X.patch | patch -p1`
lines in `Dockerfile`, and the table in `README.md` → "Customizations" → "Patches" for what each one
does and why). After bumping the version in step 3, run:

```bash
make build
```

This runs both `docker build -f Dockerfile` and `-f Dockerfile.acceptance`, including the `test`
stage (ruff, ruff format, mypy, collectstatic). If a patch fails to apply, the `RUN cat
patches/X.patch | patch -p1` step fails the build with a rejected-hunk error naming the file.

**If `make build` fails on something other than a patch** — e.g. the `test` stage failing on
lint/type errors unrelated to the version bump — do not treat that as out of scope just because it
isn't a patch. Check whether the same failure exists on `main` independent of this branch (it might
be pre-existing drift, like a tool's version pin in `pyproject.toml` no longer matching what
`uv.lock` actually resolves). Either way, **fix it properly — rename/update the offending
config or code — rather than adding a `noqa`, `type: ignore`, or a new ignore-list entry to make it
quiet.** This repo's standing policy is to keep itself passing its own checks for real, not to
suppress the checks. If you're unsure whether a fix is in scope for this PR or should be split out,
ask the user — don't decide unilaterally to skip it.

For each patch, before touching anything, decide **is it still needed at all** — re-read what it
does (README table) and cross-reference the changelog/commit-range summary from step 4: did
upstream fix the same underlying problem this version? If so, dropping the patch (and removing its
`RUN` line from `Dockerfile` and its row from the README table) is the right fix, not regenerating
it. This has happened before — the AppSRE fork has previously removed patches upstream made
obsolete.

If the patch is still needed but the hunk no longer applies (upstream changed the surrounding code),
regenerate it — don't just widen the context and hope:

1. Get the current upstream version of the target file. The base image already has it — note that
   `glitchtip-frontend` images are `linux/amd64` only, so on an arm64 host (e.g. Apple Silicon) you
   need `--platform`:
   `docker run --rm --platform linux/amd64 --entrypoint cat registry.gitlab.com/glitchtip/glitchtip-frontend:<new-version> <path/in/image>`
2. Apply the *intent* of the old patch to the new file content by hand (read the old patch's `+`/`-`
   lines to understand what it changed and why — the README table gives the purpose).
3. Regenerate the patch file with `git diff --no-index <old> <new>` (fix up the `a/`/`b/` path
   prefixes it emits if you diffed from temp copies — they need to read `a/<repo-relative-path>` /
   `b/<repo-relative-path>` for `patch -p1` to apply them) or by editing the `.patch` file directly,
   matching the format of the existing patches.
4. Verify the regenerated patch applies cleanly against a fresh extraction of the upstream file
   (`patch -p1 --dry-run`) before putting it back, then re-run `make build` end-to-end to confirm
   the whole pipeline (patches, collectstatic, lint, mypy) passes.

This mirrors what actually happened in commit `f4c465e`: patch `08-ingest-prometheus-middleware`
broke because upstream restructured the ASGI middleware list in 6.2.0, and got manually regenerated
against the new structure after confirming (via the changelog) that the middleware-stripping change
wasn't auth-related.

Once every patch either applies cleanly or has been regenerated/removed with a reason, and `make
build` passes end-to-end, this step is done.

## 6. Keep README.md current

`README.md` already documents the "Release / Upgrade Process" and "Post-Upgrade Checklist" — read
those sections before editing. If you added, removed, or regenerated any patch in step 5, update the
"Customizations" → "Patches" table to match reality (rows must always reflect what's actually in
`patches/` and applied in `Dockerfile`). If the "Release / Upgrade Process" section doesn't yet
mention this skill, add a line pointing at it so the next person doing this upgrade finds it instead
of re-deriving the process from scratch.

## 7. Commit and open the PR

Commit `Dockerfile`, any changed/removed `patches/*.patch`, any unrelated-but-fixed config drift from
step 5, and the `README.md` update together. Follow this repo's existing commit style (see `git
log`, e.g. `f4c465e`): a `chore(deps): upgrade GlitchTip to <version>` summary line, then a
markdown-formatted body explaining *why* each patch needed regeneration or removal and what the
changelog/commit-range review found — this is what the next person verifying the upgrade will
actually read. If step 1 checked out an existing bot PR, push to that same branch; otherwise open a
new PR with `gh pr create`.

In the PR description (and to the user directly), restate the auth-callout from step 4 prominently —
whoever promotes this to production needs to see it without digging, and the "Post-Upgrade
Checklist" in `README.md` already has an "OIDC / SSO login works" line for exactly this reason. Mark
the corresponding tasks done on the Jira ticket from step 2 and link the PR on it.

## Output format when reporting back to the user

End every run of this skill with a short report structured as:

```
## GlitchTip upgrade: <old> → <new>

### Jira
...  (ticket key/URL, and whether it was created or already existed)

### Branch/PR
...

### What changed upstream
... (note explicitly whether this came from the CHANGELOG file or the raw commit-range compare)

### ⚠️ Auth changes — manual staging verification required
...  (or: "None found in this range.")

### Patch verification
- 00-skip-user-invitation-process: <applied unchanged | regenerated | removed, because ...>
- ...

### Other fixes along the way
... (e.g. unrelated lint/config drift fixed, not ignored)

### Build
<pass/fail, what `make build` showed>
```
