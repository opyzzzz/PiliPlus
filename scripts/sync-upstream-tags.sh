#!/usr/bin/env bash
set -Eeuo pipefail

: "${UPSTREAM_URL:?UPSTREAM_URL is required}"
: "${BASELINE_TAG:?BASELINE_TAG is required}"
: "${LANDSCAPE_PATCH_SHA:?LANDSCAPE_PATCH_SHA is required}"

ORIGIN_URL="$(git remote get-url origin)"
git fetch origin main --no-tags
git fetch upstream '+refs/tags/*:refs/tags/upstream/*' --force

if ! git cat-file -e "${LANDSCAPE_PATCH_SHA}^{commit}" 2>/dev/null; then
  echo "::error::Landscape patch commit ${LANDSCAPE_PATCH_SHA} is not available in the checked-out repository."
  exit 1
fi

summary_file="${GITHUB_STEP_SUMMARY:-}"
record() {
  printf '%s\n' "$1"
  if [[ -n "$summary_file" ]]; then
    printf '%s\n' "$1" >> "$summary_file"
  fi
}

version_of() {
  local tag="$1"
  printf '%s' "${tag#v}"
}

is_at_or_after_baseline() {
  local tag="$1" version first
  version="$(version_of "$tag")"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  first="$(printf '%s\n%s\n' "$BASELINE_TAG" "$version" | sort -V | head -n 1)"
  [[ "$first" == "$BASELINE_TAG" ]]
}

record "## Upstream Tag Sync"
record ""
record "- Upstream: `$UPSTREAM_URL`"
record "- Baseline: `$BASELINE_TAG` (inclusive)"
record "- Landscape patch: `$LANDSCAPE_PATCH_SHA`"
record "- Original tags are never overwritten; patched tags use `patched/<tag>`."
record ""
record "| Upstream tag | Original tag | Patched tag | Result |"
record "|---|---|---|---|"

success_count=0
failure_count=0
skip_count=0

mapfile -t tags < <(
  git for-each-ref --format='%(refname)' refs/tags/upstream/ |
    sed 's#^refs/tags/upstream/##' |
    sort -Vu
)

for tag in "${tags[@]}"; do
  if ! is_at_or_after_baseline "$tag"; then
    continue
  fi

  source_ref="refs/tags/upstream/$tag"
  base_commit="$(git rev-parse "${source_ref}^{commit}")"
  original_remote_ref="refs/tags/$tag"
  patched_tag="patched/$tag"
  patched_remote_ref="refs/tags/$patched_tag"

  # Preserve any existing original tag, even if it differs from upstream.
  if git ls-remote --exit-code --refs origin "$original_remote_ref" >/dev/null 2>&1; then
    original_status="already present (preserved)"
  else
    if git push origin "$source_ref:$original_remote_ref"; then
      original_status="synced"
    else
      record "| `$tag` | failed to sync | not attempted | original tag push failed |"
      failure_count=$((failure_count + 1))
      continue
    fi
  fi

  # Existing patched tags are immutable and are not silently replaced.
  if git ls-remote --exit-code --refs origin "$patched_remote_ref" >/dev/null 2>&1; then
    record "| `$tag` | $original_status | already exists | skipped; existing patched tag preserved |"
    skip_count=$((skip_count + 1))
    continue
  fi

  git checkout --detach "$base_commit" >/dev/null
  if git cherry-pick "$LANDSCAPE_PATCH_SHA"; then
    if ! git diff-tree --check HEAD^ HEAD; then
      git cherry-pick --abort >/dev/null 2>&1 || true
      record "| `$tag` | $original_status | failed | whitespace/error check failed |"
      failure_count=$((failure_count + 1))
      continue
    fi
    result="patch applied"
  else
    # An empty cherry-pick means the changes are already present; a conflicted
    # cherry-pick leaves a dirty worktree/index and must not be published.
    if git diff --quiet && git diff --cached --quiet; then
      git cherry-pick --skip >/dev/null 2>&1 || true
      result="patch already present"
    else
      git cherry-pick --abort >/dev/null 2>&1 || true
      record "| `$tag` | $original_status | failed | cherry-pick conflict; no patched tag created |"
      failure_count=$((failure_count + 1))
      continue
    fi
  fi

  if [[ -n "$(git status --porcelain)" ]]; then
    git cherry-pick --abort >/dev/null 2>&1 || true
    record "| `$tag` | $original_status | failed | worktree not clean after patch |"
    failure_count=$((failure_count + 1))
    continue
  fi

  git tag -a "$patched_tag" HEAD -m "PiliPlus $tag with landscape orientation patch"
  if git push origin "$patched_remote_ref"; then
    record "| `$tag` | $original_status | created | $result |"
    success_count=$((success_count + 1))
  else
    git tag -d "$patched_tag" >/dev/null 2>&1 || true
    record "| `$tag` | $original_status | failed | could not push patched tag |"
    failure_count=$((failure_count + 1))
  fi
done

record ""
record "- Patched tags created: $success_count"
record "- Skipped existing patched tags: $skip_count"
record "- Failed tags: $failure_count"

# Do not block other tags on an individual conflict, but make the run visibly
# fail after all eligible tags have been attempted.
if (( failure_count > 0 )); then
  exit 1
fi
