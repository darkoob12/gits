# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`gits.sh` is a standalone bash utility that runs git operations across multiple repositories in a directory. No build system or dependencies required.

## Usage

```bash
# Run directly
bash gits.sh [options] [command] [args]

# Or make executable
chmod +x gits.sh
./gits.sh [options] [command] [args]
```

Set `GITS_ROOT` env var to specify which directory to scan (defaults to current directory).

## Commands

- `status` (default) — show branch, commit info, and working tree state
- `switch <branch>` — checkout branch across all repos
- `fetch` — fetch from origin in every repo
- `pull` — pull in every repo
- `prune` — prune stale remote-tracking refs

## Output formats

Selected with `-f <a|b|c>` or `--format=<a|b|c>`:
- `a` — two-line format with detailed info (default)
- `b` — single wide line (~120 cols) with compressed symbols
- `c` — labeled block format

## Architecture

All logic lives in `gits.sh` (~313 lines), organized in three layers:

1. **Helper functions** (lines 9–103) — low-level git queries: `is_git_repo`, `get_current_branch`, `get_ahead_behind`, `get_file_counts`, `find_repos`, etc.
2. **Formatter functions** (lines 107–176) — `fmt_a`, `fmt_b`, `fmt_c` each render one repo's data in the chosen format.
3. **Command handlers + dispatcher** (lines 180–313) — `cmd_status`, `cmd_switch`, `cmd_fetch`, `cmd_pull`, `cmd_prune` iterate over repos; argument parsing dispatches to these.
