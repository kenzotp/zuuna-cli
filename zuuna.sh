#!/usr/bin/env bash
#
# zuuna — link local git activity to Zuuna cards, and cut releases.
#
# Install per repository:
#
#   curl -o zuuna https://<your-zuuna>/zuuna.sh
#   chmod +x zuuna
#   ./zuuna init https://<your-zuuna> zk_live_your_token
#
# After that, every commit is reported automatically via a post-commit hook.
# Reference a card key (e.g. UNI-42) in the commit message or branch name and
# the commit/branch links to that card on the board.
#
# `init` and `report` need nothing but git + curl. `release` and `plan` also need
# `jq`: a release payload carries a whole commit range, and hand-escaping JSON in
# bash silently corrupts messages that contain quotes, control bytes or unicode —
# a wrong manifest that still parses is worse than a loud failure.
set -euo pipefail

CMD="${1:-help}"

repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || { echo "zuuna: not a git repository." >&2; exit 1; }
}

load_conf() {
  ROOT="$(repo_root)"
  CONF="${ZUUNA_CONF:-$ROOT/.git/zuuna.conf}"
  [ -f "$CONF" ] || { echo "zuuna: run 'zuuna init' first (no $CONF)." >&2; exit 1; }
  # shellcheck disable=SC1090
  . "$CONF"
  : "${ZUUNA_URL:?ZUUNA_URL missing from $CONF}"
  : "${ZUUNA_TOKEN:?ZUUNA_TOKEN missing from $CONF}"
}

need_jq() {
  command -v jq >/dev/null 2>&1 || {
    cat >&2 <<'MSG'
zuuna: this command needs `jq`.

  A release carries a whole commit range. Escaping that JSON by hand in bash
  silently mangles messages containing quotes, tabs or unicode — you would get a
  release manifest that parses but is wrong. jq is one package:

    apt install jq   |   brew install jq   |   apk add jq
MSG
    exit 1
  }
}

need_group() {
  if [ -z "${ZUUNA_GROUP:-}" ]; then
    cat >&2 <<MSG
zuuna: ZUUNA_GROUP is not set in $CONF.

  It is the group your releases belong to, and it is never guessed — guessing it
  from card keys would let this token write into the wrong group.
  Open the group's Releases page and copy the id from the URL:

      /groups/<THIS-PART>/releases

  then add to $CONF:

      ZUUNA_GROUP=<id>
MSG
    exit 1
  fi
}

# api <method> <path> [body] — writes the response body to $API_OUT and the
# status to $HTTP. NOT via command substitution: that runs in a SUBSHELL, so the
# HTTP assignment would be lost and `set -u` then kills the script with
# "HTTP: unbound variable" (found by running it).
HTTP=""
API_OUT=""
api() {
  local method="$1" path="$2" body="${3:-}"
  API_OUT="$(mktemp)"
  HTTP=$(curl -sS -o "$API_OUT" -w '%{http_code}' -X "$method" "$ZUUNA_URL$path" \
    -H "Authorization: Bearer $ZUUNA_TOKEN" \
    -H "Content-Type: application/json" \
    ${body:+-d "$body"} || echo "000")
}
api_body() { cat "$API_OUT"; }
api_done() { rm -f "$API_OUT"; }

case "$CMD" in
  init)
    URL="${2:-}"; TOKEN="${3:-}"; GROUP="${4:-}"
    if [ -z "$URL" ] || [ -z "$TOKEN" ]; then
      echo "Usage: zuuna init <zuuna-url> <api-token> [group-id]" >&2
      echo "  group-id is only needed for 'zuuna release' / 'zuuna plan'." >&2
      exit 1
    fi
    URL="${URL%/}" # drop a trailing slash
    ROOT="$(repo_root)"
    REMOTE="$(git -C "$ROOT" remote get-url origin 2>/dev/null || echo "local:$(basename "$ROOT")")"
    CONF="$ROOT/.git/zuuna.conf"
    {
      echo "ZUUNA_URL=$URL"
      echo "ZUUNA_TOKEN=$TOKEN"
      echo "ZUUNA_REMOTE=$REMOTE"
      echo "ZUUNA_GROUP=$GROUP"
    } > "$CONF"
    chmod 600 "$CONF"

    HOOK="$ROOT/.git/hooks/post-commit"
    cat > "$HOOK" <<'HOOK_EOF'
#!/usr/bin/env bash
# Installed by `zuuna init` — reports each commit to Zuuna.
#
# --git-common-dir, NOT --git-dir: inside a git WORKTREE, --git-dir resolves to
# .git/worktrees/<name>, where no conf exists — so the hook found nothing and
# exited 0, silently. Every commit made in a worktree went unlinked and nothing
# anywhere said so. --git-common-dir points at the real .git in both cases.
CONF="$(git rev-parse --git-common-dir)/zuuna.conf"
[ -f "$CONF" ] || exit 0
# shellcheck disable=SC1090
. "$CONF"
SHA="$(git rev-parse HEAD)"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
AUTHOR="$(git log -1 --pretty=%an)"
MSG="$(git log -1 --pretty=%B)"
# Minimal JSON escaping for the commit message (backslash, quote, newlines).
# ⚠️ The newline is ESCAPED (\n), never replaced with a space. The server
# splits `message` at the FIRST newline into subject + body, and only the subject (or
# a body key behind ref/see/fixes) counts as WORK — that is the intent rule.
# Flattening the message makes the whole thing one subject line, so every ticket
# merely CITED in a commit body gets linked and MOVED. It has no visible symptom in
# the hook itself; it shows up days later as cards that walked backwards on the board.
MSG="${MSG//\\/\\\\}"; MSG="${MSG//\"/\\\"}"; MSG="${MSG//$'\n'/\\n}"; MSG="${MSG//$'\r'/}"
BODY="{\"repo\":{\"remoteUrl\":\"$ZUUNA_REMOTE\"},\"events\":[{\"kind\":\"commit\",\"ref\":\"$SHA\",\"message\":\"$MSG\",\"author\":\"$AUTHOR\"},{\"kind\":\"branch\",\"ref\":\"$BRANCH\"}]}"
# A hook must never fail a commit, so this stays non-fatal — but it must not be
# SILENT. `curl -sf … >/dev/null 2>&1 || true` swallowed everything: when the
# configured token was revoked, every commit 401'd and linking simply stopped
# forever with no symptom. The only clue was cards that quietly never linked.
# Print the failure to stderr (visible in the commit output) and still exit 0.
HTTP="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$ZUUNA_URL/api/v1/git/events" \
  -H "Authorization: Bearer $ZUUNA_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$BODY" 2>/dev/null)" || HTTP="000"
case "$HTTP" in
  2*) ;;
  000) echo "zuuna: could not reach $ZUUNA_URL — commit not linked." >&2 ;;
  401|403) echo "zuuna: token rejected (HTTP $HTTP) — commit not linked. Re-run 'zuuna init'." >&2 ;;
  *) echo "zuuna: git/events returned HTTP $HTTP — commit not linked." >&2 ;;
esac
exit 0
HOOK_EOF
    chmod +x "$HOOK"

    echo "✓ zuuna initialised for $(basename "$ROOT")."
    echo "  Commits are now reported automatically. Put a card key like UNI-42 in"
    echo "  your commit message or branch name to link it to that card."
    if [ -z "$GROUP" ]; then
      echo
      echo "  For releases, add your group id to .git/zuuna.conf:"
      echo "      ZUUNA_GROUP=<the id in /groups/<id>/releases>"
    fi
    ;;

  report)
    # Report the current commit and branch by hand, using the same config.
    load_conf
    SHA="$(git rev-parse HEAD)"; BRANCH="$(git rev-parse --abbrev-ref HEAD)"
    AUTHOR="$(git log -1 --pretty=%an)"; MSG="$(git log -1 --pretty=%B)"
    MSG="${MSG//\\/\\\\}"; MSG="${MSG//\"/\\\"}"; MSG="${MSG//$'\n'/\\n}"; MSG="${MSG//$'\r'/}"
    BODY="{\"repo\":{\"remoteUrl\":\"$ZUUNA_REMOTE\"},\"events\":[{\"kind\":\"commit\",\"ref\":\"$SHA\",\"message\":\"$MSG\",\"author\":\"$AUTHOR\"},{\"kind\":\"branch\",\"ref\":\"$BRANCH\"}]}"
    # `curl -sf` prints NOTHING on a 401 and this command has no exit check, so a
    # revoked token made `zuuna report` a silent no-op that looked like success.
    # Unlike the hook, this one is run BY A HUMAN who is waiting for an answer —
    # so it reports the body and exits non-zero.
    OUT="$(curl -s -w $'\n%{http_code}' -X POST "$ZUUNA_URL/api/v1/git/events" \
      -H "Authorization: Bearer $ZUUNA_TOKEN" -H "Content-Type: application/json" -d "$BODY")"
    HTTP="${OUT##*$'\n'}"; BODY_OUT="${OUT%$'\n'*}"
    echo "$BODY_OUT"
    case "$HTTP" in
      2*) ;;
      401|403) echo "zuuna: token rejected (HTTP $HTTP). Re-run 'zuuna init'." >&2; exit 1 ;;
      *) echo "zuuna: git/events returned HTTP $HTTP." >&2; exit 1 ;;
    esac
    ;;

  plan)
    # Create a PLANNED release, optionally bound to the tag it will ship as.
    load_conf; need_jq; need_group
    NAME="${2:-}"
    [ -n "$NAME" ] || { echo "Usage: zuuna plan <name> [--tag v1.2.3] [--date YYYY-MM-DD]" >&2; exit 1; }
    shift 2 || true
    TAG=""; DATE=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --tag)  TAG="${2:?--tag needs a value}"; shift 2 ;;
        --date) DATE="${2:?--date needs a value}"; shift 2 ;;
        *) echo "zuuna: unknown argument $1" >&2; exit 2 ;;
      esac
    done
    BODY="$(jq -n --arg g "$ZUUNA_GROUP" --arg n "$NAME" --arg t "$TAG" --arg d "$DATE" \
      '{groupId:$g, name:$n, publish:false}
       + (if $t != "" then {tag:$t}         else {} end)
       + (if $d != "" then {releaseDate:$d} else {} end)')"
    api POST /api/v1/releases "$BODY"
    case "$HTTP" in
      2*) api_body | jq -r '"✓ planned \(.release.name)" + (if .release.tag then " → \(.release.tag)" else " (no tag yet — your next deploy binds it, as long as it is your only planned release)" end)' ;;
      *)  echo "✖ could not plan the release (HTTP $HTTP)" >&2; api_body | head -c 300 >&2; echo >&2; api_done; exit 1 ;;
    esac
    api_done
    ;;

  release)
    # Post the commit range for a release. This is what fills a release in.
    #
    # The range is computed HERE, on the machine that has the repo — Zuuna cannot
    # derive it: it only ever sees commits that named a card key, stores no
    # ancestry, and its timestamps are ingest-time. The producer sends the answer.
    load_conf; need_jq; need_group
    shift || true
    TAG=""; PREV=""; DRY=""; PUBLISH=true; NOTES=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --tag)     TAG="${2:?--tag needs a value}"; shift 2 ;;
        --prev)    PREV="${2:?--prev needs a value}"; shift 2 ;;
        --notes)   NOTES="${2:?--notes needs a value}"; shift 2 ;;
        --dry-run) DRY=1; PUBLISH=false; shift ;;
        --no-publish) PUBLISH=false; shift ;;
        *) echo "zuuna: unknown argument $1" >&2; exit 2 ;;
      esac
    done

    # Which tag are we describing? Default: the most recent one.
    if [ -z "$TAG" ]; then
      TAG="$(git describe --tags --abbrev=0 2>/dev/null || true)"
      [ -n "$TAG" ] || { echo "zuuna: no tags in this repo — pass --tag <name>." >&2; exit 1; }
    fi

    # The range. If TAG exists, describe it: parent-of-tag .. tag. Otherwise the
    # tag is about to be cut, so measure to HEAD. Measuring an EXISTING tag
    # against HEAD would include commits made AFTER it — a wrong manifest.
    if [ -z "$PREV" ]; then
      if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
        TIP="$TAG"; PREV="$(git describe --tags --abbrev=0 "${TAG}^" 2>/dev/null || true)"
      else
        TIP="HEAD"; PREV="$(git describe --tags --abbrev=0 2>/dev/null || true)"
      fi
    else
      git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1 && TIP="$TAG" || TIP="HEAD"
    fi
    RANGE="${PREV:+$PREV..}$TIP"

    # -z NUL-separates RECORDS (a commit message cannot contain a NUL) and %s is
    # LAST with the tail rejoined, so a message containing the field separator
    # cannot shift the other fields. Learned the hard way.
    COMMITS="$(git log -z --format="%H%x1f%an%x1f%ae%x1f%aI%x1f%P%x1f%s" "$RANGE" \
      | jq -Rs '
          split("\u0000") | map(select(length > 0))
          | map(split("\u001f") as $f
              | { sha: $f[0], authorName: $f[1], authorEmail: $f[2],
                  committedAt: $f[3],
                  parents: (($f[4] // "") | split(" ") | map(select(length > 0))),
                  message: ($f[5:] | join("\u001f")) })
          | map(select(.sha != null and (.sha | length) == 40))')"
    COUNT="$(echo "$COMMITS" | jq 'length')"
    echo "→ $TAG   range ${RANGE}   ${COUNT} commits"
    [ "$COUNT" = "0" ] && { echo "  nothing to send — the range is empty."; exit 0; }

    BODY="$(jq -n --arg g "$ZUUNA_GROUP" --arg n "$TAG" --arg t "$TAG" --arg p "$PREV" \
      --arg notes "$NOTES" --arg rid "${ZUUNA_RELEASE_ID:-}" \
      --argjson pub "$PUBLISH" --argjson c "$COMMITS" \
      '{groupId:$g, name:$n, tag:$t, publish:$pub, commits:$c}
       + (if $p     != "" then {prevTag:$p}      else {} end)
       + (if $notes != "" then {notes:$notes}    else {} end)
       + (if $rid   != "" then {releaseId:$rid}  else {} end)')"

    if [ -n "$DRY" ]; then
      echo "  [dry-run] would POST to $ZUUNA_URL/api/v1/releases:"
      echo "$BODY" | jq '{groupId, name, tag, prevTag, publish, commits: (.commits|length)}'
      exit 0
    fi

    api POST /api/v1/releases "$BODY"
    case "$HTTP" in
      2*)
        api_body | jq -r '"  ✓ \(.release.name) — \(.ingest.commits) commits, \(.ingest.merges) merges, \(.ingest.linkedCards) cards"
          + (if .ingest.ghostCommits > 0 then ", \(.ingest.ghostCommits) with no ticket" else "" end)
          + (if (.ingest.unknownKeys|length) > 0 then "\n  ⚠ unknown card keys: \(.ingest.unknownKeys|join(", "))" else "" end)
          + (if .droppedCommits > 0 then "\n  ⚠ \(.droppedCommits) commits dropped (unparsable date)" else "" end)
          + "\n  matched by: \(.matchedBy)"'
        api_done
        ;;
      401|403)
        # LOUD: a scope problem that fails quietly leaves the board silently
        # empty for weeks while the tag looks fine.
        echo "✖ Zuuna rejected this (HTTP $HTTP)." >&2
        api_body | head -c 300 >&2; echo >&2
        echo "  Almost always: the token needs the \"releases:write\" scope." >&2
        echo "  Mint one in Developers → API tokens, update ZUUNA_TOKEN in $CONF," >&2
        echo "  then re-run — posting a manifest is idempotent." >&2
        api_done
        exit 1
        ;;
      *)
        echo "✖ could not post the release (HTTP $HTTP)" >&2
        api_body | head -c 300 >&2; echo >&2
        api_done
        exit 1
        ;;
    esac
    ;;

  help|*)
    cat <<'HELP'
zuuna — link local git activity to Zuuna cards

  zuuna init <zuuna-url> <api-token> [group-id]
        set up this repository (installs a post-commit hook)
  zuuna report
        report the current commit now

  Releases (need jq + ZUUNA_GROUP in .git/zuuna.conf):

  zuuna plan <name> [--tag v1.2.3] [--date YYYY-MM-DD]
        create a planned release. Name it anything — "Aurora", "Summer
        Release". Bind it to the tag it will ship as, or leave the tag off
        and your next deploy binds it, as long as it is your only planned one.
  zuuna release [--tag v1.2.3] [--prev v1.2.2] [--notes "..."] [--dry-run]
        send the commit range for a tag. Cards, commits and merges land in the
        release automatically; it is marked released unless --no-publish.
        Defaults to the most recent tag. Safe to re-run — it is idempotent.

  Typical CI step, right after your deploy succeeds:

      ./zuuna release --tag "$TAG"
HELP
    ;;
esac
