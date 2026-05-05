#!/usr/bin/env bash

# gits.sh - Run git operations across all git repos in a directory
# Usage: gits.sh [options] [status|switch <branch>|fetch|pull|prune]

ROOT="${GITS_ROOT:-$(pwd)}"

# ── helpers ───────────────────────────────────────────────────────────────────

is_git_repo() {
    git -C "$1" rev-parse --git-dir &>/dev/null
}

get_current_branch() {
    git -C "$1" symbolic-ref --short HEAD 2>/dev/null || git -C "$1" rev-parse --short HEAD 2>/dev/null
}

get_tags() {
    git -C "$1" tag --points-at HEAD 2>/dev/null | tr '\n' ' ' | sed 's/ $//'
}

get_pointing_branches() {
    local current="$2"
    git -C "$1" branch --points-at HEAD --format='%(refname:short)' 2>/dev/null \
        | grep -v "^${current}$" | tr '\n' ' ' | sed 's/ $//'
}

get_describe() {
    git -C "$1" describe --tags --always 2>/dev/null
}

get_other_branches() {
    local current="$2"
    local -a all
    mapfile -t all < <(git -C "$1" branch --format='%(refname:short)' 2>/dev/null | grep -v "^${current}$")
    local total="${#all[@]}"
    if (( total == 0 )); then
        echo ""
    elif (( total <= 3 )); then
        echo "${all[*]}"
    else
        echo "${all[0]} ${all[1]} ${all[2]} +$((total - 3)) more"
    fi
}

get_short_hash() {
    git -C "$1" rev-parse --short HEAD 2>/dev/null || echo "n/a"
}

is_clean() {
    if [[ -z $(git -C "$1" status --porcelain) ]]; then
        echo "clean"
    else
        echo "dirty"
    fi
}

get_ahead_behind() {
    local remote
    remote=$(git -C "$1" rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>/dev/null)
    [[ -z "$remote" ]] && return
    local behind ahead
    read -r behind ahead < <(git -C "$1" rev-list --left-right --count "${remote}...HEAD" 2>/dev/null)
    echo "↑${ahead} ↓${behind}"
}

get_file_counts() {
    local status
    status=$(git -C "$1" status --porcelain 2>/dev/null)
    [[ -z "$status" ]] && return
    local modified=0 added=0 deleted=0 line
    while IFS= read -r line; do
        local x="${line:0:1}" y="${line:1:1}"
        if [[ "${x}${y}" == "??" ]]; then
            (( added++ )) || true
        else
            [[ "$x" == "M" || "$y" == "M" ]] && (( modified++ )) || true
            [[ "$x" == "A" ]]                 && (( added++ ))    || true
            [[ "$x" == "D" || "$y" == "D" ]] && (( deleted++ )) || true
        fi
    done <<< "$status"
    local parts=""
    (( modified > 0 )) && parts+="~${modified} "
    (( added    > 0 )) && parts+="+${added} "
    (( deleted  > 0 )) && parts+="-${deleted}"
    echo "${parts% }"
}

get_last_author() {
    git -C "$1" log -1 --format='%an' 2>/dev/null || echo "unknown"
}

get_last_time() {
    git -C "$1" log -1 --format='%ar' 2>/dev/null || echo "unknown"
}

shorten_time() {
    sed -E \
        -e 's/([0-9]+) seconds? ago/\1s/'  \
        -e 's/([0-9]+) minutes? ago/\1m/'  \
        -e 's/([0-9]+) hours? ago/\1h/'    \
        -e 's/([0-9]+) days? ago/\1d/'     \
        -e 's/([0-9]+) weeks? ago/\1w/'    \
        -e 's/([0-9]+) months? ago/\1mo/'  \
        -e 's/([0-9]+) years? ago/\1y/'    \
        <<< "$1"
}

find_repos() {
    for dir in "$ROOT"/*/; do
        [[ -d "$dir" ]] && is_git_repo "$dir" && echo "$dir"
    done
}

# ── formatters ────────────────────────────────────────────────────────────────

# Format A — two lines: primary info + secondary info (default)
#
#   my-repo                        main [a1b2c3] ↑2 ↓1  dirty
#                                  John Doe · 3 hours ago · ~3 +1 -2 · (feat dev +1 more)
#
fmt_a() {
    local name="$1" branch="$2" tags="$3" others="$4" hash="$5"
    local state="$6" ab="$7" counts="$8" author="$9" rel_time="${10}"
    local pointing="${11}" describe="${12}"
    local w=28
    local ab_str="" desc_str=""
    [[ -n "$ab"       ]] && ab_str="  ${ab}"
    [[ -n "$describe" ]] && desc_str="  (${describe})"

    printf "%-${w}s  %-20s [%s]%s%s  %s\n" "${name}:" "$branch" "$hash" "$ab_str" "$desc_str" "$state"

    local line2="${author} · ${rel_time}"
    [[ -n "$counts"   ]] && line2+=" · ${counts}"
    [[ -n "$tags"     ]] && line2+=" · ${tags}"
    [[ -n "$pointing" ]] && line2+=" · @(${pointing})"
    line2+=" · (${others:-(no other branches)})"

    printf "%-${w}s  %s\n" "" "$line2"
    echo
}

# Format B — single wide line with compressed symbols (~120 cols)
#
#   my-repo                main  a1b2c3  ↑2↓1   John Doe     3h   ~3+1-2   feat dev +1
#
fmt_b() {
    local name="$1" branch="$2" tags="$3" others="$4" hash="$5"
    local state="$6" ab="$7" counts="$8" author="$9" rel_time="${10}"
    local pointing="${11}" describe="${12}"

    local short_author short_time ab_str counts_str others_str tags_str pointing_str desc_str
    short_author="${author:0:12}"
    short_time=$(shorten_time "$rel_time")
    ab_str="${ab:----}"
    counts_str="${counts:-clean}"
    others_str="${others:-(none)}"
    tags_str="${tags:+[${tags}] }"
    pointing_str="${pointing:+@(${pointing}) }"
    desc_str="${describe:+(${describe}) }"

    printf "%-22s %-16s %-7s %-10s %-13s %-5s %-12s %s%s%s%s\n" \
        "${name}:" "$branch" "$hash" "$ab_str" "$short_author" \
        "$short_time" "$counts_str" "$tags_str" "$desc_str" "$pointing_str" "$others_str"
}

# Format C — labeled block per repo
#
#   ── my-repo ─────────────────────────────────────
#      branch : main [a1b2c3]   ↑2 ↓1   dirty
#      commit : John Doe · 3 hours ago
#      changes: ~3 +1 -2
#      others : feat  dev  +1 more
#
fmt_c() {
    local name="$1" branch="$2" tags="$3" others="$4" hash="$5"
    local state="$6" ab="$7" counts="$8" author="$9" rel_time="${10}"
    local pointing="${11}" describe="${12}"

    local header="── ${name} "
    local fill_len=$(( 52 - ${#header} ))
    (( fill_len < 2 )) && fill_len=2
    local dashes
    dashes=$(printf '─%.0s' $(seq 1 "$fill_len"))
    echo "${header}${dashes}"

    printf "   branch  : %s [%s]   %s   %s\n" "$branch" "$hash" "${ab:-no remote}" "$state"
    printf "   commit  : %s · %s\n" "$author" "$rel_time"
    [[ -n "$counts"   ]] && printf "   changes : %s\n" "$counts"
    [[ -n "$tags"     ]] && printf "   tags    : %s\n" "$tags"
    [[ -n "$describe" ]] && printf "   describe: %s\n" "$describe"
    [[ -n "$pointing" ]] && printf "   at head : %s\n" "$pointing"
    printf "   others  : %s\n" "${others:-(none)}"
    echo
}

# ── commands ──────────────────────────────────────────────────────────────────

cmd_status() {
    local fmt="${1:-a}"
    find_repos | while read -r repo; do
        local name branch tags others hash state ab counts author rel_time pointing describe
        name=$(basename "$repo")
        branch=$(get_current_branch "$repo")
        tags=$(get_tags "$repo")
        others=$(get_other_branches "$repo" "$branch")
        hash=$(get_short_hash "$repo")
        state=$(is_clean "$repo")
        ab=$(get_ahead_behind "$repo")
        counts=$(get_file_counts "$repo")
        author=$(get_last_author "$repo")
        rel_time=$(get_last_time "$repo")
        pointing=$(get_pointing_branches "$repo" "$branch")
        describe=$(get_describe "$repo")

        "fmt_${fmt}" "$name" "$branch" "$tags" "$others" "$hash" "$state" "$ab" "$counts" "$author" "$rel_time" "$pointing" "$describe"
    done
}

cmd_switch() {
    local target="$1"
    if [[ -z "$target" ]]; then
        echo "Usage: gits.sh switch <branch>" >&2
        exit 1
    fi

    find_repos | while read -r repo; do
        local name
        name=$(basename "$repo")
        printf "%-30s " "${name}:"
        if git -C "$repo" checkout "$target" 2>&1; then
            echo "switched to $target"
        else
            echo "FAILED (branch '$target' not found?)"
        fi
    done
}

cmd_fetch() {
    find_repos | while read -r repo; do
        local name
        name=$(basename "$repo")
        printf "%-30s " "${name}:"
        if git -C "$repo" fetch 2>&1; then
            echo "fetched"
        else
            echo "FAILED"
        fi
    done
}

cmd_pull() {
    find_repos | while read -r repo; do
        local name
        name=$(basename "$repo")
        printf "%-30s " "${name}:"
        git -C "$repo" pull 2>&1 | tail -1
    done
}

cmd_prune() {
    find_repos | while read -r repo; do
        local name
        name=$(basename "$repo")
        printf "%-30s " "${name}:"
        git -C "$repo" remote prune origin 2>&1 | grep -E 'pruned|nothing' || echo "done"
    done
}

cmd_exec() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: gits.sh exec <git-command> [args...]" >&2
        exit 1
    fi

    find_repos | while read -r repo; do
        local name
        name=$(basename "$repo")
        printf "%-30s " "${name}:"
        git -C "$repo" "$@" 2>&1
    done
}

cmd_sync() {
    local -a branches=("${@}")
    if [[ ${#branches[@]} -eq 0 ]]; then
        branches=(master release develop)
    fi

    find_repos | while read -r repo; do
        local name
        name=$(basename "$repo")
        echo "── ${name} ──"

        local original stashed
        original=$(get_current_branch "$repo")
        stashed=false

        if [[ $(is_clean "$repo") == "dirty" ]]; then
            printf "  stashing changes... "
            if git -C "$repo" stash push --quiet --include-untracked -m "gits-sync"; then
                echo "ok"
                stashed=true
            else
                echo "FAILED — skipping repo"
                echo
                continue
            fi
        fi

        for branch in "${branches[@]}"; do
            if git -C "$repo" show-ref --verify --quiet "refs/heads/${branch}"; then
                printf "  %-16s " "${branch}:"
                git -C "$repo" checkout --quiet "$branch" 2>/dev/null
                git -C "$repo" pull 2>&1 | tail -1
            else
                printf "  %-16s skipped (branch not found)\n" "${branch}:"
            fi
        done

        printf "  %-16s " "← ${original}:"
        git -C "$repo" checkout --quiet "$original" 2>/dev/null && echo "restored"

        if [[ "$stashed" == true ]]; then
            printf "  unstashing changes... "
            if git -C "$repo" stash pop --quiet; then
                echo "ok"
            else
                echo "FAILED — run 'git stash pop' manually"
            fi
        fi

        echo
    done
}

# ── dispatch ──────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: gits.sh [options] [command] [args]

Commands:
  status              Show branch, commit info, and working tree state for
                      every repo (default command)
  switch <branch>     Check out <branch> in every repo that has it
  fetch               Fetch from origin in every repo
  pull                Pull in every repo
  prune               Prune stale remote-tracking refs in every repo
  exec <cmd> [args]   Run any git command in every repo (e.g. exec switch master)
  sync [branches...]  For each repo: stash if dirty, pull all given branches
                      (default: master release develop), then restore the
                      original branch and unstash

Options:
  -f, --format <a|b|c>  Output format for 'status':
                          a  Two-line: primary + secondary info (default)
                          b  Single wide line with compressed symbols (~120 cols)
                          c  Labeled block per repo
  -h, --help            Show this help message

Environment:
  GITS_ROOT             Directory to scan for repos (default: current directory)
EOF
}

FORMAT="a"
COMMAND=""
SWITCH_TARGET=""
SYNC_BRANCHES=()
EXEC_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--format)
            FORMAT="${2:-a}"; shift 2 ;;
        --format=*)
            FORMAT="${1#--format=}"; shift ;;
        -h|--help)
            usage; exit 0 ;;
        status|fetch|pull|prune)
            COMMAND="$1"; shift ;;
        exec)
            COMMAND="exec"; shift
            EXEC_ARGS=("$@"); set -- ;;

        sync)
            COMMAND="sync"; shift
            while [[ $# -gt 0 && "$1" != -* ]]; do
                SYNC_BRANCHES+=("$1"); shift
            done
            ;;
        switch)
            COMMAND="switch"
            SWITCH_TARGET="${2:-}"
            shift
            [[ -n "$SWITCH_TARGET" ]] && shift
            ;;
        *)
            echo "Unknown argument: $1" >&2
            echo "Run 'gits.sh --help' for usage." >&2
            exit 1 ;;
    esac
done

if [[ ! "$FORMAT" =~ ^[abc]$ ]]; then
    echo "Invalid format: '$FORMAT'. Use a, b, or c." >&2
    exit 1
fi

case "${COMMAND:-status}" in
    status)  cmd_status "$FORMAT" ;;
    switch)  cmd_switch "$SWITCH_TARGET" ;;
    fetch)   cmd_fetch ;;
    pull)    cmd_pull ;;
    prune)   cmd_prune ;;
    sync)    cmd_sync "${SYNC_BRANCHES[@]}" ;;
    exec)    cmd_exec "${EXEC_ARGS[@]}" ;;
esac
