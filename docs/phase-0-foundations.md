# Phase 0 — Foundations & repo scaffolding

## What we built

The project skeleton: the guiding [ROADMAP.md](../ROADMAP.md), a [README.md](../README.md), a
`.gitignore`, the planned folder layout (`app/`, `k8s/`, `helm/`, `scripts/`, `docs/`), a local git
repo connected to a GitHub remote, and one GitHub Issue per phase (Phases 0–10) to track the work.

## Why

Before writing a single line of application code, we need three things: a **plan** (so we build things
in an order that makes sense and never skip a concept), a **place** for each kind of file (app code,
infra manifests, test scripts, docs — kept separate on purpose), and a **way to track progress** that
survives across sessions (GitHub Issues, not just our memory of "what's next").

## New concepts introduced

- **Git remote** — a copy of the repo hosted elsewhere (GitHub). `origin` is the conventional name for
  "the main remote."
- **GitHub Issue** — a trackable unit of work with a title, description, labels, and open/closed state.
  We use one per phase.
- **Label** — a tag on an issue for filtering/grouping. We use `phase-N` (which phase) and
  `type:feature` / `type:test` / `type:docs` (what kind of work).
- **`gh` (GitHub CLI)** — a command-line tool for interacting with GitHub (issues, PRs, etc.) without
  opening a browser.

## Step-by-step reproduction

```bash
# 1. Initialize git and point it at your GitHub repo
git init
git branch -M main
git remote add origin https://github.com/<you>/<repo>.git

# 2. Authenticate the GitHub CLI (one-time, opens a browser)
gh auth login --hostname github.com --git-protocol https --web

# 3. Create the folder skeleton
mkdir -p app/src/main/java app/src/test/java app/src/main/resources k8s helm scripts docs

# 4. Commit and push the scaffolding
git add .gitignore README.md ROADMAP.md
git commit -m "Add project roadmap, README, and gitignore"
git push -u origin main

# 5. Create labels
gh label create "phase-0" --color "0E8A16" --description "Work belonging to Phase 0"
# ...repeat for phase-1..phase-10, plus type:feature / type:test / type:docs

# 6. Create one issue per phase, body pulled from ROADMAP.md's checklist for that phase
gh issue create --title "Phase 0 — Foundations & repo scaffolding" \
  --body-file .github/issue-drafts/phase-0.md \
  --label "phase-0" --label "type:feature" --label "type:test" --label "type:docs"
```

## How we tested it

This phase's "test" is structural, not code:

- `git push` succeeded and `origin/main` on GitHub matches local `main`.
- `gh issue list` shows 11 open issues (Phase 0 through Phase 10), each correctly labeled.
- The planned folders (`app/`, `k8s/`, `helm/`, `scripts/`, `docs/`) exist in the repo.

```bash
gh issue list --limit 15
# Expect: 11 rows, phase-0 .. phase-10, each OPEN
```

## Common errors & fixes

- **`gh: command not found` right after installing via winget.** The terminal's PATH was loaded before
  the install updated it. Fix: open a *new* terminal window, or call the tool by its full path —
  `"C:\Program Files\GitHub CLI\gh.exe"` — in the current one.
- **`gh auth status` fails even though `git push` works.** These are two separate credential stores.
  `git push` can succeed via Git's own credential manager (cached from prior use on the machine) while
  `gh` still needs its own separate `gh auth login`. Don't assume one implies the other.
- **Don't write scratch/temporary files (like issue-body drafts) to the OS temp directory** if you want
  them to persist across the session — keep them inside the project directory instead (we use
  `.github/issue-drafts/`, excluded from commits via `.gitignore`).
