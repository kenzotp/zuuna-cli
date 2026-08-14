# zuuna

A single-file shell script that links local git activity to cards on a [Zuuna](https://zuuna.de) board, and cuts releases from git tags.

No dependencies beyond `git` and `curl`. `release` and `plan` also want `jq`.

```bash
curl -o zuuna https://app.zuuna.de/zuuna.sh
chmod +x zuuna
./zuuna init https://app.zuuna.de zk_live_your_token
```

That writes `.git/zuuna.conf` (mode `600`) and installs a `post-commit` hook. From then on every commit is reported automatically.

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

## Licence

MIT. See [LICENSE](LICENSE).
