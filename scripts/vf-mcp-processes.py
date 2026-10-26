#!/usr/bin/env python3
"""Report pre-install vf-mcp helpers and the app that owns each process tree."""

import argparse
import re
import subprocess
import sys
from pathlib import Path

REFRESH_REMINDER = "In ChatGPT and Codex, refresh the Vinyl Fever tools or start a new thread. Open threads keep the old tool list."


def elapsed_seconds(value):
    value = value.strip()
    days = 0
    if "-" in value:
        day_text, value = value.split("-", 1)
        days = int(day_text)
    parts = [int(part) for part in value.split(":")]
    if len(parts) == 3:
        hours, minutes, seconds = parts
    elif len(parts) == 2:
        hours, (minutes, seconds) = 0, parts
    else:
        hours, minutes, seconds = 0, 0, parts[0]
    return days * 86400 + hours * 3600 + minutes * 60 + seconds


def owning_app(pid, processes):
    visited = set()
    current = pid
    while current in processes and current not in visited:
        visited.add(current)
        parent, command = processes[current]
        match = re.search(r"([^\s]+\.app)(?:/[^\s]*)?", command)
        if match:
            app_name = Path(match.group(1)).name
            if "--codex" in command.lower() or "/codex" in command.lower():
                return f"{app_name} (Codex)"
            return app_name
        current = parent
    return "unknown app"


def find_stale_helpers(ps_output, helper_path, swapped_at, captured_at):
    expected = str(Path(helper_path).resolve())
    rows = {}
    for line in ps_output.splitlines():
        fields = line.strip().split(None, 3)
        if len(fields) < 4:
            continue
        try:
            pid, parent = int(fields[0]), int(fields[1])
            started_at = captured_at - elapsed_seconds(fields[2])
        except ValueError:
            continue
        rows[pid] = (parent, fields[3], started_at)

    process_tree = {pid: (parent, command) for pid, (parent, command, _) in rows.items()}
    stale = []
    for pid, (parent, command, started_at) in rows.items():
        executable = command.split(None, 1)[0].strip('"')
        if str(Path(executable).resolve()) != expected or started_at >= swapped_at:
            continue
        stale.append((pid, owning_app(parent, process_tree)))
    return stale


def format_report(stale, include_reminder=True):
    if stale:
        owners = ", ".join(f"PID {pid}: {owner}" for pid, owner in stale)
        count = len(stale)
        noun = "helper is" if count == 1 else "helpers are"
        action = "that session" if count == 1 else "those sessions"
        listing = f"{count} vf-mcp {noun} still on the old build ({owners}). Restart {action} to pick up this install."
    else:
        listing = "No vf-mcp helpers from the installed app are still on the old build."
    if include_reminder:
        return f"{listing}\n{REFRESH_REMINDER}"
    return listing


def self_test():
    helper = "/Applications/VinylFever.app/Contents/Helpers/vf-mcp"
    output = """100 301 10:00 /Applications/VinylFever.app/Contents/Helpers/vf-mcp
200 400 00:01 /Applications/VinylFever.app/Contents/Helpers/vf-mcp
301 1 10:00 /Applications/ChatGPT.app/Contents/MacOS/ChatGPT --codex
400 1 00:01 /Applications/VinylFever.app/Contents/Helpers/tunnel-client
"""
    # PID 100 belongs to ChatGPT/Codex and predates the swap. PID 200 is the
    # tunnel's new helper child and started after the swap, so it is excluded.
    processes = find_stale_helpers(output, helper, swapped_at=1_000, captured_at=1_300)
    assert processes == [(100, "ChatGPT.app (Codex)")], processes
    report = format_report(processes)
    assert "PID 100: ChatGPT.app (Codex)" in report
    assert REFRESH_REMINDER in report
    print(report)
    print("vf-mcp process listing self-test: passed")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--helper")
    parser.add_argument("--swapped-at", type=float)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--listing-only", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if not args.helper or args.swapped_at is None:
        parser.error("--helper and --swapped-at are required")
    captured_at = float(subprocess.check_output(["date", "+%s"], text=True).strip())
    ps_output = subprocess.check_output(
        ["ps", "-axo", "pid=,ppid=,etime=,command="], text=True
    )
    stale = find_stale_helpers(ps_output, args.helper, args.swapped_at, captured_at)
    print(format_report(stale, include_reminder=not args.listing_only))


if __name__ == "__main__":
    main()
