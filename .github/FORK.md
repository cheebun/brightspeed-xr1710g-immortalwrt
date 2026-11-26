# About this fork

This repository is a fork of [immortalwrt/immortalwrt](https://github.com/immortalwrt/immortalwrt).
It is the single common base for all derived firmware repositories (device-specific
build repos). Derived repos never fork ImmortalWrt directly; they build from this fork.

## Branches

| Branch   | Role |
|----------|------|
| `master` | Untouched mirror of `immortalwrt/immortalwrt` `master`. Only ever fast-forwarded from upstream. Never commit here. |
| `base`   | Default branch. `master` plus fork-specific additions: selected upstream OpenWrt commits merged ahead of ImmortalWrt (for example newer kernel bumps) and fork documentation under `.github/`. |

## Rule: merge, never cherry-pick

Commits taken from `openwrt/openwrt` ahead of ImmortalWrt are brought into `base` with
`git merge --no-ff <openwrt-sha>`, never with `git cherry-pick`.

ImmortalWrt regularly merges OpenWrt itself ("Merge Official Source"). Because `base`
already contains the *same* commit objects, the later upstream merge is recognised by git
as already applied and merges cleanly. Cherry-picked copies have different SHAs and
produce duplicate history and conflicts on the next sync.

Fork-only changes should stay out of upstream-owned files wherever possible (prefer new
files under `.github/`) so that syncs remain conflict-free.

Check before pushing a new `base`:

```sh
git merge-tree --write-tree base immortalwrt/master   # must exit 0 (no conflicts)
```

## History of fork-specific merges

| Merge into `base` | Source | Reason |
|-------------------|--------|--------|
| `Merge OpenWrt main up to kernel 6.18.64 (75fde714f9)` | `openwrt/openwrt` `75fde714f9` (includes `f7d14dc28e`, `a5383abb34`) | Kernel 6.18.60 -> 6.18.64 ahead of ImmortalWrt |

## How derived repos consume this fork

- Pin an exact `base` commit SHA (not the branch name) in the derived repo's build
  configuration, so builds are reproducible.
- Bump the pinned SHA deliberately, in its own commit, after the new `base` has passed a
  build for that device.
- Never point a derived repo at `master` of this fork, and never at a moving tag.
- Device-specific patches live in the derived repo, not here. Only changes useful to all
  derived repos belong in `base`.

## TODO: automated sync (not enabled yet)

GitHub Actions are **disabled** in this fork. Upstream's workflows are inherited and must
not run here unintentionally.

Planned daily sync workflow:

1. Fast-forward `master` from `immortalwrt/immortalwrt` `master` (`--ff-only`; fail loudly
   if that is not possible, since `master` must never diverge).
2. Merge `master` into `base` (`git merge --no-ff master`).
3. On conflict: do not push; open an issue in this repo listing the conflicting files.
4. On success: push `base`.

Credentials: the default `GITHUB_TOKEN` cannot push commits that add or modify files under
`.github/workflows/`, and upstream changes those regularly. The sync job therefore needs
either a deploy key with write access or a fine-grained PAT with `contents: write` and
`workflows: write`. Decision pending.

Before enabling Actions in this fork, disable every inherited upstream workflow
(`gh workflow disable <workflow> --repo <this fork>`) so that only the sync workflow runs.
