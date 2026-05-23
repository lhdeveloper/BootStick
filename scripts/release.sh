#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_FILE="$REPO_ROOT/BootStick.command"

die() { echo "erro: $*" >&2; exit 1; }

git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 || die "não é um repositório git"

VERSION=$(grep -E '^SCRIPT_VERSION=' "$SCRIPT_FILE" | sed -E 's/^SCRIPT_VERSION="([^"]+)".*/\1/')
TAG="v${VERSION}"

[[ -n "$VERSION" ]] || die "SCRIPT_VERSION não encontrado em BootStick.command"

if [[ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
  die "commit pendente — atualize SCRIPT_VERSION, commit e rode de novo"
fi

git -C "$REPO_ROOT" tag -l "$TAG" | grep -qx "$TAG" && die "tag ${TAG} já existe"

git -C "$REPO_ROOT" tag -a "$TAG" -m "BootStick ${TAG}"

if [[ "${1:-}" == "--push" ]]; then
  BRANCH=$(git -C "$REPO_ROOT" branch --show-current)
  git -C "$REPO_ROOT" push origin "$BRANCH" "$TAG"
  echo "publicado: ${TAG}"
else
  echo "tag ${TAG} criada"
  echo "publique com: git push origin $(git -C "$REPO_ROOT" branch --show-current) ${TAG}"
fi
