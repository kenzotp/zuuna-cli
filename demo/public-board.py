#!/usr/bin/env python3
"""Render the PUBLIC demo board (https://app.zuuna.de/demo) as any visitor
sees it. Read-only, unauthenticated — the /demo page IS the public view.

Usage:
  python3 public-board.py              # render all columns
  python3 public-board.py --watch KEY  # poll until KEY sits in Done
"""
import argparse
import html
import re
import sys
import time
import urllib.request

DEMO_URL = "https://app.zuuna.de/demo"

# The rendered column header: <span ...>In Progress</span><span ...>2</span>
COL_RE = re.compile(r'<span[^>]*>([A-Za-z ]+)</span><span[^>]*>\d+</span>')
# The rendered card face: <p ...>CLI-3</p> ... <h3 ...>title</h3>
CARD_RE = re.compile(
    r'<p class="text-\[12px\] font-medium text-zinc-400">((?:[A-Z]+-\d+))</p>'
    r'.*?<h3[^>]*>(.*?)</h3>',
    re.DOTALL,
)


def fetch():
    req = urllib.request.Request(DEMO_URL, headers={"User-Agent": "zuuna-demo-viewer"})
    with urllib.request.urlopen(req, timeout=20) as res:
        return res.read().decode("utf-8")


def board(page):
    cols = [(m.start(), m.group(1).strip()) for m in COL_RE.finditer(page)]
    cards = [
        (m.start(), m.group(1), html.unescape(m.group(2)).strip())
        for m in CARD_RE.finditer(page)
    ]
    board = {name: [] for _, name in cols}
    for pos, key, title in cards:
        here = [name for at, name in cols if at < pos]
        if here:
            board[here[-1]].append((key, title))
    return board


def render(b):
    width = max(len(name) for name in b)
    lines = []
    for name, cards in b.items():
        body = ", ".join(f"{k} — {t}" for k, t in cards) if cards else "(empty)"
        lines.append(f"  {name:<{width}}  {body}")
    return "\n".join(lines)


def column_of(b, key):
    for name, cards in b.items():
        for k, _ in cards:
            if k == key:
                return name
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--watch", metavar="KEY", help="poll KEY until it reaches --until")
    ap.add_argument("--until", metavar="COLUMN", default="Done", help="target column (default: Done)")
    args = ap.parse_args()

    if not args.watch:
        print(render(board(fetch())))
        return 0

    deadline = time.monotonic() + 90
    while True:
        b = board(fetch())
        col = column_of(b, args.watch)
        if col == args.until:
            print()
            print(render(b))
            return 0
        if time.monotonic() > deadline:
            print(f"\n  {args.watch} is in {col!r} after 90s — no move recorded")
            print(render(b))
            return 1
        print(".", end="", flush=True)
        time.sleep(4)


if __name__ == "__main__":
    sys.exit(main())
