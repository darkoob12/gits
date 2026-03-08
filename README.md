# gits.sh

A bash utility to run git operations across all git repositories in a directory.

## Usage

```bash
gits.sh [options] [command] [args]
```

By default, it scans the current directory for subdirectories that are git repos. Set `GITS_ROOT` to override.

## Commands

| Command | Description |
|---------|-------------|
| `status` | Show branch, commit info, and working tree state for every repo (default) |
| `switch <branch>` | Check out `<branch>` in every repo that has it |
| `fetch` | Fetch from origin in every repo |
| `pull` | Pull in every repo |
| `prune` | Prune stale remote-tracking refs in every repo |

## Options

| Option | Description |
|--------|-------------|
| `-f, --format <a\|b\|c>` | Output format for `status` (default: `a`) |
| `-h, --help` | Show help message |

### Status Formats

- **a** — Two-line display with primary + secondary info (default)
- **b** — Single wide line with compressed symbols (~120 cols)
- **c** — Labeled block per repo

## Environment Variables

| Variable | Description |
|----------|-------------|
| `GITS_ROOT` | Directory to scan for repos (default: current directory) |

## Examples

```bash
# Show status of all repos in ~/projects
GITS_ROOT=~/projects gits.sh

# Compact single-line format
gits.sh -f b

# Fetch all repos
gits.sh fetch

# Switch all repos to main
gits.sh switch main
```
