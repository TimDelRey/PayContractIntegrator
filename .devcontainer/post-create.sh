#!/usr/bin/env bash
set -euo pipefail

bundle install --jobs 4 --retry 3

workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
backup_dir="${workspace_root}/.codex-rebuild-backup"
codex_home="${CODEX_HOME:-/home/vscode/.codex}"

if [[ -d "${backup_dir}" ]]; then
  mkdir -p "${codex_home}"
  chmod 700 "${codex_home}"

  rsync -a "${backup_dir}/" "${codex_home}/"

  if [[ -n "$(rsync -a --checksum --dry-run --itemize-changes "${backup_dir}/" "${codex_home}/")" ]]; then
    echo "Codex state verification failed; backup was kept at ${backup_dir}" >&2
    exit 1
  fi

  rm -rf -- "${backup_dir}"
  echo "Codex state restored to the persistent volume."
fi
