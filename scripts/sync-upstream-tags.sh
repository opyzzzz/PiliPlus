#!/usr/bin/env bash
set -Eeuo pipefail

: "${UPSTREAM_URL:?UPSTREAM_URL is required}"
: "${BASELINE_TAG:?BASELINE_TAG is required}"
: "${LANDSCAPE_PATCH_SHA:?LANDSCAPE_PATCH_SHA is required}"

DRY_RUN="${DRY_RUN:-false}"

ORIGIN_URL="$(git remote get-url origin)"

# Clean stale upstream refs before fetching, so tags deleted upstream do not
# linger locally and cause useless reprocessing.
git for-each-ref --format='%(refname)' refs/tags/upstream/ \
  | xargs -r -n1 git update-ref -d

git fetch origin main --no-tags
git fetch upstream '+refs/tags/*:refs/tags/upstream/*' --force

# --- Validate the landscape patch commit ------------------------------------

if [[ ! "$LANDSCAPE_PATCH_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "::error::LANDSCAPE_PATCH_SHA must be a full 40-character lowercase hex SHA; got '${LANDSCAPE_PATCH_SHA}'."
  exit 1
fi

if ! git cat-file -e "${LANDSCAPE_PATCH_SHA}^{commit}" 2>/dev/null; then
  echo "::error::Landscape patch commit ${LANDSCAPE_PATCH_SHA} is not available in the checked-out repository."
  exit 1
fi

# A merge commit cannot be cherry-picked without -m. Fail loudly so the
# workflow owner knows to point at the squashed feature commit instead.
patch_parents="$(git rev-list --parents -n 1 "$LANDSCAPE_PATCH_SHA" | wc -w)"
if (( patch_parents > 2 )); then
  echo "::error::LANDSCAPE_PATCH_SHA ${LANDSCAPE_PATCH_SHA} is a merge commit (parents: $((patch_parents - 1)))."
  echo "::error::Point LANDSCAPE_PATCH_SHA at the squashed single commit instead, then re-run."
  exit 1
fi

# --- Summary helpers --------------------------------------------------------

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
  # Accept X.Y, X.Y.Z, X.Y.Z.W, ... — i.e. two or more numeric segments.
  # This covers upstream tags like 2.1.5, 2.1.6.1, 2.1.6.2, 1.1.3.40.
  [[ "$version" =~ ^[0-9]+(\.[0-9]+)+$ ]] || return 1
  first="$(printf '%s\n%s\n' "$BASELINE_TAG" "$version" | sort -V | head -n 1)"
  [[ "$first" == "$BASELINE_TAG" ]]
}

# Cache remote tag list once to avoid O(N) network round-trips.
origin_tags="$(git ls-remote --tags --refs origin | awk '{print $2}')"
has_remote_tag() {
  local ref="$1"
  grep -qxF "$ref" <<<"$origin_tags"
}

record "## Upstream Tag Sync"
record ""
record "- Upstream: \`$UPSTREAM_URL\`"
record "- Baseline: \`$BASELINE_TAG\` (inclusive)"
record "- Landscape patch: \`$LANDSCAPE_PATCH_SHA\`"
record "- Dry run: \`$DRY_RUN\`"
record "- Original tags are never overwritten; patched tags use \`patched/<tag>\`."
record "- The patch is built against the latest upstream code; tags it does not apply to are skipped, not treated as failures."
record ""
record "| Upstream tag | Original tag | Patched tag | Result |"
record "|---|---|---|---|"

success_count=0
failure_count=0
skip_count=0
not_applicable_count=0

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
  if has_remote_tag "$original_remote_ref"; then
    original_status="already present (preserved)"
  else
    if [[ "$DRY_RUN" == "true" ]]; then
      original_status="would sync (dry-run)"
    elif git push origin "$source_ref:$original_remote_ref"; then
      original_status="synced"
    else
      record "| \`$tag\` | failed to sync | not attempted | original tag push failed |"
      failure_count=$((failure_count + 1))
      continue
    fi
  fi

  # Existing patched tags are immutable and are not silently replaced.
  if has_remote_tag "$patched_remote_ref"; then
    record "| \`$tag\` | $original_status | already exists | skipped; existing patched tag preserved |"
    skip_count=$((skip_count + 1))
    continue
  fi

  git checkout --detach "$base_commit" >/dev/null

  if git cherry-pick "$LANDSCAPE_PATCH_SHA"; then
    result="patch applied"
  else
    if [[ -n "$(git status --porcelain)" ]]; then
      # The patch is developed against the latest upstream code and is not
      # expected to apply cleanly to every tag. A conflict here means the
      # patch is simply not applicable to this version, which is expected
      # behavior, not a sync failure.
      git cherry-pick --abort >/dev/null 2>&1 || true
      record "| \`$tag\` | $original_status | skipped | patch not applicable to this version |"
      not_applicable_count=$((not_applicable_count + 1))
      continue
    fi
    git cherry-pick --skip >/dev/null 2>&1 || true
    result="patch already present"
  fi

  if [[ -n "$(git status --porcelain)" ]]; then
    git cherry-pick --abort >/dev/null 2>&1 || true
    record "| \`$tag\` | $original_status | failed | worktree not clean after patch |"
    failure_count=$((failure_count + 1))
    continue
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    record "| \`$tag\` | $original_status | would create | $result (dry-run) |"
    skip_count=$((skip_count + 1))
    continue
  fi

  # Annotated tag message records full provenance: base commit and patch SHA.
  git tag -a "$patched_tag" HEAD \
    -m "PiliPlus $tag with landscape orientation patch" \
    -m "base-commit: $base_commit" \
    -m "patch-sha: $LANDSCAPE_PATCH_SHA" \
    -m "generated-by: $GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"

  if git push origin "$patched_remote_ref"; then
    record "| \`$tag\` | $original_status | created | $result |"
    success_count=$((success_count + 1))
  else
    git tag -d "$patched_tag" >/dev/null 2>&1 || true
    record "| \`$tag\` | $original_status | failed | could not push patched tag |"
    failure_count=$((failure_count + 1))
  fi
done

record ""
record "- Patched tags created: $success_count"
record "- Skipped existing patched tags: $skip_count"
record "- Patch not applicable to this version: $not_applicable_count"
record "- Failed tags: $failure_count"

# Only genuine errors (push failures, invalid patch, etc.) should fail the run.
# A patch that does not apply to an older tag is expected and is not an error.
if (( failure_count > 0 )); then
  exit 1
fi