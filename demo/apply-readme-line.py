#!/usr/bin/env python3
"""Apply the one-line README change for the agent-run demo. Idempotent:
asserts the anchor exists and the line is not already there, then inserts."""
from pathlib import Path

ANCHOR = "![zuuna: a commit moves the card](demo/zuuna-demo.gif)"
LINE = (
    "\n\nThe same loop, run by an agent: [demo/agent-run.gif](demo/agent-run.gif) records"
    " a ZCode (GLM) agent session — MCP tools read the work, the agent opens the PR, and"
    " the merge itself closes card CLI-3 on the public demo board at"
    " [app.zuuna.de/demo](https://app.zuuna.de/demo)."
)

readme = Path("README.md")
text = readme.read_text()
if "demo/agent-run.gif" in text:
    raise SystemExit("line already present — nothing to do")
if ANCHOR not in text:
    raise SystemExit("anchor not found — README changed upstream?")
readme.write_text(text.replace(ANCHOR, ANCHOR + LINE, 1))
print("README.md: added the agent-run line")
