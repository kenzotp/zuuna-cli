#!/usr/bin/env bash
# ZNA-2005 demo recording driver. Runs the real zuuna CLI against the STAGE
# workspace. The API token lives in $ZUUNA_TOKEN (exported before recording)
# and is never printed; commands are shown exactly as executed.
set -u

export ZUUNA_URL="$QS_STAGE_URL"
# Scoped git config for the demo box only (default branch main, no hint spam).
GIT_CONFIG_GLOBAL="$(mktemp)"
export GIT_CONFIG_GLOBAL
printf '[init]\n\tdefaultBranch = main\n' > "$GIT_CONFIG_GLOBAL"

G='\033[1;32m'; D='\033[2m'; N='\033[0m'
say() { printf "%b\n" "$1"; sleep 0.9; }
run() { printf "${G}\$${N} %s\n" "$1"; sleep 0.4; eval "$1"; sleep 0.7; }

say "${D}# zuuna — a commit moves the card${N}"
say "${D}# real CLI, real calls. Recorded against our staging server;${N}"
say "${D}# the API token (minted in Developers -> API tokens) stays in${N}"
say "${D}# \$ZUUNA_TOKEN and is never printed.${N}"
say ""
say "${D}# On the staging board sits card QUI-3, column: To do.${N}"
run "curl -sS \"\$ZUUNA_URL/api/v1/cards/QUI-3\" -H \"Authorization: Bearer \$ZUUNA_TOKEN\" | jq '{key, status}'"
say ""
say "${D}# 1) Install — one file, no dependencies beyond git + curl${N}"
run "git init my-project"
run "cd my-project"
run "curl -o zuuna https://app.zuuna.de/zuuna.sh"
run "chmod +x zuuna"
say ""
say "${D}# 2) Connect this repo — writes .git/zuuna.conf (mode 600) + a post-commit hook${N}"
run "./zuuna init \"\$ZUUNA_URL\" \"\$ZUUNA_TOKEN\""
say ""
say "${D}# 3) Commit with the card key in the subject line${N}"
run "echo '# demo' > README.md && git add -A"
run "git config user.email demo@example.com && git config user.name Demo"
run "git commit -m 'QUI-3: first commit from a fresh clone'"
say ""
say "${D}# ...nothing. The hook is silent on success — by design.${N}"
say "${D}# Did it work? Look at the card.${N}"
sleep 0.9
run "curl -sS \"\$ZUUNA_URL/api/v1/cards/QUI-3\" -H \"Authorization: Bearer \$ZUUNA_TOKEN\" | jq '{key, status}'"
say ""
say "${D}# QUI-3 walked from 'To do' to 'In Progress'. The board mirrors the repo.${N}"
say "${D}# That is the whole loop: card key in the commit subject -> zuuna links${N}"
say "${D}# the commit -> the board's 'A commit is linked' automation moves the card.${N}"
say "${D}# https://github.com/kenzotp/zuuna-cli${N}"
