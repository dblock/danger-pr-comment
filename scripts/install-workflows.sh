#!/usr/bin/env bash
set -euo pipefail

force=0
root=""

usage() {
  cat <<'USAGE'
Usage: install-workflows.sh [--root PATH] [--force]

Creates:
  .github/workflows/danger.yml
  .github/workflows/danger-comment.yml

Options:
  --root PATH  Target repository root (defaults to git root or current dir)
  --force      Overwrite existing workflow files
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      root="$2"
      shift 2
      ;;
    --force)
      force=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$root" ]]; then
  if git_root=$(git rev-parse --show-toplevel 2>/dev/null); then
    root="$git_root"
  else
    root="$PWD"
  fi
fi

workflows_dir="$root/.github/workflows"
mkdir -p "$workflows_dir"

write_file() {
  local path="$1"
  if [[ -e "$path" && "$force" -ne 1 ]]; then
    echo "File exists: $path (use --force to overwrite)" >&2
    exit 1
  fi
  cat > "$path"
  echo "Wrote $path"
}

write_file "$workflows_dir/danger.yml" <<'EOF'
name: Danger
on:
  pull_request:
    types: [opened, reopened, edited, synchronize]

jobs:
  danger:
    uses: numbata/danger-pr-comment/.github/workflows/danger-run.yml@v0.1.1
    secrets: inherit
    with:
      ruby-version: '3.4'
      bundler-cache: true
EOF

write_file "$workflows_dir/danger-comment.yml" <<'EOF'
name: Danger Comment
on:
  workflow_run:
    workflows: [Danger]
    types: [completed]

permissions:
  actions: read        # download artifacts
  issues: write        # list + create/update comments
  pull-requests: write # PR comment access

jobs:
  comment:
    uses: numbata/danger-pr-comment/.github/workflows/danger-comment.yml@v0.1.1
    secrets: inherit
EOF
