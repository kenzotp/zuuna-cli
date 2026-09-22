#!/usr/bin/env bash
# ZNA-2021 [C11] — the "agent-run" sprint demo.
#
# The session stars ZCode agent (GLM). Everything on screen is a REAL tool
# call and a REAL commit, executed live in a clone of the public
# kenzotp/zuuna-cli repository against the PUBLIC demo board
# (https://app.zuuna.de/demo — read-only for everyone). The driver only
# sequences the steps and sets a readable pace: nothing is mocked, replayed
# or printed that was not actually run.
#
# Tokens: the Zuuna API token stays in $ZUUNA_API_TOKEN and is never printed;
# commands that carry it are shown with the variable unexpanded. The /demo
# board read is unauthenticated.
set -u

# The recorder hands the session a real TTY: keep pagers out of the shot and
# gh non-interactive, or git diff would sit at a pager prompt on camera.
export TERM=xterm-256color
export GIT_PAGER=cat PAGER=cat
export GH_PROMPT_DISABLED=true
export GIT_TERMINAL_PROMPT=0

G='\033[1;32m'; D='\033[2m'; N='\033[0m'
say() { printf "%b\n" "$1"; sleep 1.1; }
run() { printf "${G}\$${N} %s\n" "$1"; sleep 0.5; eval "$1"; sleep 0.9; }

say "${D}# an agent-run sprint — the whole loop, and no human touches the board${N}"
say "${D}# session: ZCode agent (GLM) · board: the public demo at app.zuuna.de/demo${N}"
say "${D}# every command below is executed for real; this driver only sets the pace.${N}"
say ""

say "${D}# 1) the interface any coding agent speaks: a real MCP client session${N}"
say "${D}#    against the published mcp-server-zuuna (npm, stdio)${N}"
run "node demo/agent-run-mcp-probe.mjs"
say ""
say "${D}#    (the public demo board lives in its own demo org; the token here is${N}"
say "${D}#     ours, so the board truth below is read from the public page — the${N}"
say "${D}#     exact view any visitor gets)${N}"
say ""

say "${D}# 2) the board as the agent finds it: CLI-3 shipped in the last sprint${N}"
run "python3 demo/public-board.py"
say ""

say "${D}# 3) the agent continues work on CLI-3 — one line in the README, pointing${N}"
say "${D}#    at the very recording you are watching${N}"
run "python3 demo/apply-readme-line.py"
run "git --no-pager diff"
say ""
run "git config user.name kenzotp"
run "git config user.email kenzotp@users.noreply.github.com"
run "git checkout -b cli-3-agent-demo"
run "git add README.md"
run "git commit -m 'docs: point at the agent-run recording (CLI-3)'"
say ""

say "${D}# 4) ship it: push, open the PR, merge — the board watches GitHub, not us${N}"
run "git push -u origin cli-3-agent-demo"
run "python3 demo/public-board.py --watch CLI-3 --until 'In Progress'"
say ""
say "${D}#    the push reopened the card. now the merge closes it:${N}"
run "gh pr create --title 'Agent-run demo: README pointer (CLI-3)' --body 'One README line pointing at demo/agent-run.gif (the recording itself lands in the next commit). Merging this is the moment the public demo board moves: the PR title carries the card key, so the PR-merged automation closes CLI-3 on app.zuuna.de/demo with no human touching the board.'"
run "gh pr merge --squash --delete-branch"
say ""

say "${D}# 5) verify live — watch the public board until the merge lands${N}"
run "python3 demo/public-board.py --watch CLI-3"
say ""
say "${D}# CLI-3: Done -> In Progress (the push) -> Done (the merge).${N}"
say "${D}# Nobody touched the board; git did all of it. The board mirrors the repo.${N}"
say "${D}# zuuna.de/demo · agent: ZCode (GLM) · github.com/kenzotp/zuuna-cli${N}"
