# zuuna

[![shellcheck](https://github.com/kenzotp/zuuna-cli/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/kenzotp/zuuna-cli/actions/workflows/shellcheck.yml)

A single-file shell script that links local git activity to cards on a [Zuuna](https://zuuna.de) board, and cuts releases from git tags.

No dependencies beyond `git` and `curl`. `release` and `plan` also want `jq`.

See it happen — a commit moves the card (30 s, real CLI):

![zuuna: a commit moves the card](demo/zuuna-demo.gif)

---

## Quickstart: from nothing to a moved card

Five steps, one terminal, one board. Everything below is copy-pasteable; the whole path takes well under ten minutes.

### 1. Install

You need a git repository to report from. Create one, or move into the one you have:

```bash
git init my-project && cd my-project    # or: cd into your existing repo
curl -o zuuna https://app.zuuna.de/zuuna.sh
chmod +x zuuna
```

That is the whole install — one file, no package manager, no build step. It needs `git` and `curl` (both preinstalled on Linux and macOS). Keep the script in the repo root, your `bin/` directory, wherever — `init` works from the repo it lives in.

### 2. Get an API token

1. Sign in at [app.zuuna.de](https://app.zuuna.de) and confirm your email address — token minting requires a verified address.
2. Open your account menu → **Developers** → **API tokens**.
3. Create a token. Give it a name and tick the scope **git:write** ("Link commits, branches and PRs to cards"). If you also want `zuuna release` / `zuuna plan`, tick **releases:write** too. A read-mostly default (`boards:read`, `cards:read`) is pre-ticked; keep it if you like.
4. Copy the token. It starts with `zk_live_` and is shown **once** — there is no way to read it back.

Note honestly what this costs: the developer platform (API tokens, git integration, releases) is part of the **Developer** plan. A new workspace starts on a 14-day free trial with no card required, so you can walk the whole quickstart before deciding anything.

### 3. Connect the repository

```bash
./zuuna init https://app.zuuna.de zk_live_paste-your-token-here
```

That writes `.git/zuuna.conf` (mode `600`, inside `.git/`, so it cannot be committed) and installs a `post-commit` hook. From then on every commit is reported automatically.

### 4. Put a card on the board, then commit against it

Create a card on any board in Zuuna. The card shows its key — a short prefix and number like `UNI-42`. Then:

```bash
git add -A
git commit -m "UNI-42: first commit from a fresh clone"
```

The key must be in the commit **subject** line (or the branch name) to count as work on that card. A key mentioned in the body — or behind `ref:` — is treated as a mere reference and links without moving anything. [Why position decides this](#the-part-worth-reading-what-counts-as-work).

### 5. Expected result

Open the card you committed against. The commit is on it — message, author, sha — in the card's activity and Git panel.

Out of the box that is linking, not movement. The **move** is one automation rule on the board: board → **Automations** → new rule → when **"A commit is linked"** → then **move to column** (say, *In Progress*). Boards don't get this rule preinstalled — whether a commit should drag a card across your board is your call, not ours. With the rule in place, your next commit moves the card: your card moves, the board mirrors the repo.

Two ways to check the wiring by hand:

- `./zuuna report` — reports the current commit and branch on demand and prints the server's answer (exits non-zero on a rejected token). Useful after `--amend`, or when the hook is not installed.
- The hook itself is **silent on success** and loud on failure — a broken token or unreachable server prints a warning to stderr but never blocks the commit. Silence means it worked.

---

## The part worth reading: what counts as work

Mentioning a card key in a commit does not always mean you *worked* on that card. Sometimes you are just pointing at it. Treating both the same way is how cards end up walking backwards across a board — a ticket cited in passing gets linked, moved, and reopened by someone else's commit three days later.

So position decides intent:

| Where the key appears | Treated as | Effect on the card |
|---|---|---|
| Commit **subject** line | Work | Links the commit, moves the card |
| **Branch** name | Work | Links the branch, moves the card |
| Commit **body**, behind `ref:` / `see:` | Reference only | Links, does not move |
| Commit body, bare | Reference only | Links, does not move |

```
UNI-42: rewrite the token refresh          → work on UNI-42
                                             (subject line)

fix the retry backoff                      → work on nothing
                                             (no key in subject or branch)

fix the retry backoff                      → references UNI-9,
                                             does not move it
ref: UNI-9
```

The script escapes the newline between subject and body rather than flattening it. That is deliberate and load-bearing: flatten the message and the whole thing becomes one subject line, so every ticket merely *cited* in a body gets treated as work. There is no visible symptom at commit time — it shows up days later as cards that moved on their own.

---

## Commands

| Command | What it does |
|---|---|
| `zuuna init <url> <token> [group-id]` | Writes the config, installs the post-commit hook. The group id is only needed for `release` and `plan`. |
| `zuuna report` | Reports the current commit and branch by hand. Useful after `--amend`, or when the hook is not installed. |
| `zuuna plan <name> [--tag v1.2.3] [--date YYYY-MM-DD]` | Creates a planned release, optionally bound to the tag it will ship as. |
| `zuuna release [--tag v1.2.3]` | Cuts a release from a tag: collects the commit range since the previous tag and sends the manifest. |

### Failure behaviour

The **hook never fails a commit** — a broken token or an unreachable server must not stop you committing. It does print a warning, though: an earlier version swallowed everything with `|| true`, which made a revoked token look exactly like success.

`zuuna report` does the opposite. A human is waiting for an answer, so it prints the response body and exits non-zero on `401`/`403`.

---

## Your token

`init` takes the token as an argument and stores it in `.git/zuuna.conf` with mode `600`. It is never written into the script, and the script contains no credentials of any kind.

`.git/zuuna.conf` sits inside `.git/`, so it is not tracked and cannot be committed by accident.

To rotate: revoke the token in Zuuna and run `init` again.

---

## Works against any Zuuna instance

The URL is a parameter. Nothing is hardcoded to a particular host, so this works against `app.zuuna.de` or any other deployment.

---

## Related

- [Link commits to cards automatically](https://zuuna.de/en/tutorials/link-commits-to-cards-automatically) — the same rules, step by step
- [Git on the board](https://zuuna.de/en/features/git-integration) — what lands on a card
- [Releases](https://zuuna.de/en/features/releases) — versions bound to git tags
- [REST API and webhooks](https://zuuna.de/en/features/developer-platform) — the endpoints this script calls
- [zuuna-webhook-verify](https://github.com/kenzotp/zuuna-webhook-verify) — verifying the signature on an outbound webhook, in Node or Python
- [zuuna-action](https://github.com/kenzotp/zuuna-action) — this script, wrapped as a GitHub Action

## Licence

MIT. See [LICENSE](LICENSE).

## Live demo

Watch the board move itself: <https://app.zuuna.de/demo> — a public read-only board driven by this very repository.
