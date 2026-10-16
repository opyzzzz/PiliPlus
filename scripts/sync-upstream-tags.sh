#!/usr/bin/env bash
set -Eeuo pipefail
: "${UPSTREAM_URL:?UPSTREAM_URL is required}"
: "${BASELINE_TAG:?BASELINE_TAG is required}"
MODE="${MODE:-sync}"
DRY_RUN="${DRY_RUN:-false}"
PATCH_LIST="${PATCH_LIST:-scripts/patches.conf}"
SUMMARY="${GITHUB_STEP_SUMMARY:-}"

record() { printf '%s\n' "$1"; [[ -z "$SUMMARY" ]] || printf '%s\n' "$1" >> "$SUMMARY"; }
fail() { echo "::error::$*" >&2; record "**ERROR:** $*"; exit 1; }
[[ "$MODE" == sync || "$MODE" == audit ]] || fail "MODE must be sync or audit."
[[ -f "$PATCH_LIST" ]] || fail "Patch list not found: $PATCH_LIST"
git fetch origin main --no-tags
git remote get-url upstream >/dev/null 2>&1 || git remote add upstream "$UPSTREAM_URL"

# Resolve exact commit subjects from origin/main history. Fail closed on ambiguity.
declare -a patch_titles=() patch_shas=()
while IFS='|' read -r requirement title || [[ -n "${requirement:-}${title:-}" ]]; do
  requirement="${requirement%$'\r'}"; title="${title%$'\r'}"
  [[ -z "${requirement//[[:space:]]/}" || "$requirement" == \#* ]] && continue
  [[ "$requirement" == required || "$requirement" == optional ]] || fail "Invalid patch type '$requirement' in $PATCH_LIST."
  [[ -n "${title//[[:space:]]/}" ]] || fail "Empty patch title in $PATCH_LIST."
  matches="$(git log origin/main --format='%H%x09%s' | awk -F '\t' -v wanted="$title" '$2 == wanted {print $1}')"
  count="$(printf '%s\n' "$matches" | awk 'NF {n++} END {print n+0}')"
  if (( count == 0 )); then
    [[ "$requirement" == optional ]] && { record "Optional patch not found; skipping: $title"; continue; }
    fail "Required patch title has no exact match on origin/main: '$title'."
  fi
  if (( count > 1 )); then
    record "Ambiguous title '$title'; candidates:"
    while IFS= read -r candidate; do [[ -z "$candidate" ]] || record "- $candidate"; done <<< "$matches"
    fail "Patch title matched $count commits; refusing arbitrary selection."
  fi
  sha="$(printf '%s\n' "$matches" | head -n1)"
  parents="$(git rev-list --parents -n 1 "$sha" | awk '{print NF-1}')"
  (( parents <= 1 )) || fail "Patch '$title' is merge commit $sha; use a single-parent commit."
  [[ -n "$(git diff-tree --no-commit-id --name-only -r "$sha")" ]] || fail "Patch '$title' ($sha) has no file changes."
  patch_titles+=("$title"); patch_shas+=("$sha")
  record "Resolved patch $((${#patch_shas[@]})): $title ($sha; $requirement)"
done < "$PATCH_LIST"
(("${#patch_shas[@]}" > 0)) || fail "No patches resolved."

record ""
record "Mode: $MODE; patches are processed in manifest order."
if [[ "$MODE" == audit ]]; then
  git fetch origin '+refs/tags/patched/*:refs/tags/audit-patched/*' --force
  record "## Existing patched tag audit"
  record "| Tag | Status | Details |"
  record "|---|---|---|"
  total=0 ok=0 bad=0
  mapfile -t refs < <(git for-each-ref --format='%(refname)' refs/tags/audit-patched/ | sort -V)
  expected="$(printf '%s\n' "${patch_shas[@]}")"
  for ref in "${refs[@]}"; do
    total=$((total+1)); name="${ref#refs/tags/audit-patched/}"
    commit="$(git rev-parse "${ref}^{commit}")"
    message="$(git for-each-ref --format='%(contents)' "$ref")"
    recorded="$(printf '%s\n' "$message" | sed -n 's/^patch-sha: //p')"
    if [[ "$recorded" != "$expected" ]]; then
      record "| $name | MISMATCH | Patch SHA list differs from current manifest (legacy tags have no complete provenance) |"
      bad=$((bad+1)); continue
    fi
    origref="refs/tags/audit-original/$name"
    if ! git fetch origin "refs/tags/$name:$origref" --force >/dev/null 2>&1; then
      record "| $name | MISMATCH | Original tag missing |"; bad=$((bad+1)); continue
    fi
    base="$(git rev-parse "${origref}^{commit}")"
    recorded_base="$(printf '%s\n' "$message" | sed -n 's/^base-commit: //p' | head -n1)"
    if [[ "$base" != "$recorded_base" ]]; then
      record "| $name | MISMATCH | Base commit provenance does not match original tag |"; bad=$((bad+1)); continue
    fi
    actual_subjects="$(git log --reverse --format='%s' "$base..$commit")"
    expected_subjects="$(printf '%s\\n' "${patch_titles[@]}")"
    if [[ "$actual_subjects" != "$expected_subjects" ]]; then
      record "| $name | MISMATCH | Actual ordered commit subjects between base and patched tag do not match the manifest |"
      bad=$((bad+1)); continue
    fi
    if git diff --quiet "$base" "$commit" --; then
      record "| $name | MISMATCH | No file-tree differences from original tag |"; bad=$((bad+1)); continue
    fi
    record "| $name | OK | Ordered patch subjects, recorded SHAs, base provenance and tree differences match |"; ok=$((ok+1))
  done
  record ""
  record "Audited: $total; compliant: $ok; mismatches: $bad"
  (( bad == 0 )) || exit 1
  exit 0
fi

git for-each-ref --format='%(refname)' refs/tags/upstream/ | xargs -r -n1 git update-ref -d
git fetch upstream '+refs/tags/*:refs/tags/upstream/*' --force
remote_tags="$(git ls-remote --tags --refs origin | awk '{print $2}')"
has_remote_tag() { grep -qxF "$1" <<< "$remote_tags"; }
is_eligible() {
  local v first
  v="${1#v}"; [[ "$v" =~ ^[0-9]+(\.[0-9]+)+$ ]] || return 1
  first="$(printf '%s\n%s\n' "$BASELINE_TAG" "$v" | sort -V | head -n1)"
  [[ "$first" == "$BASELINE_TAG" ]]
}
record ""
record "## Upstream Tag Sync"
record "| Upstream tag | Original tag | Patched tag | Result |"
record "|---|---|---|---|"
success=0 failed_count=0 skipped=0 not_applicable=0
mapfile -t tags < <(git for-each-ref --format='%(refname)' refs/tags/upstream/ | sed 's#^refs/tags/upstream/##' | sort -Vu)
for tag in "${tags[@]}"; do
  is_eligible "$tag" || continue
  source="refs/tags/upstream/$tag"; base="$(git rev-parse "${source}^{commit}")"
  orig="refs/tags/$tag"; patched="patched/$tag"; patched_ref="refs/tags/$patched"
  if has_remote_tag "$orig"; then orig_status="already present (preserved)"
  elif [[ "$DRY_RUN" == true ]]; then orig_status="would sync (dry-run)"
  elif git push origin "$source:$orig"; then orig_status=synced; remote_tags+=$'\n'"$orig"
  else record "| $tag | failed | not attempted | original tag push failed |"; failed_count=$((failed_count+1)); continue
  fi
  if has_remote_tag "$patched_ref"; then record "| $tag | $orig_status | already exists | preserved; run audit mode |"; skipped=$((skipped+1)); continue; fi
  git checkout --detach "$base" >/dev/null
  applied=(); patch_failed=false
  for i in "${!patch_shas[@]}"; do
    sha="${patch_shas[$i]}"; title="${patch_titles[$i]}"; before="$(git rev-parse 'HEAD^{tree}')"
    record "Applying to $tag ($((i+1))/${#patch_shas[@]}): $title ($sha)"
    if git cherry-pick "$sha"; then
      after="$(git rev-parse 'HEAD^{tree}')"
      if [[ "$before" == "$after" ]]; then
        git cherry-pick --abort >/dev/null 2>&1 || true
        record "| $tag | $orig_status | failed | '$title' produced no tree difference |"
        failed_count=$((failed_count+1)); patch_failed=true; break
      fi
      applied+=("$sha")
    else
      if [[ -n "$(git status --porcelain)" ]]; then
        git cherry-pick --abort >/dev/null 2>&1 || true
        record "| $tag | $orig_status | skipped | '$title' conflicts / not applicable |"
        not_applicable=$((not_applicable+1))
      else
        git cherry-pick --skip >/dev/null 2>&1 || true
        record "| $tag | $orig_status | failed | '$title' empty/already present; cannot verify application |"
        failed_count=$((failed_count+1))
      fi
      patch_failed=true; break
    fi
  done
  [[ "$patch_failed" == false ]] || continue
  [[ -n "$(git diff --name-only "$base" HEAD)" ]] || { record "| $tag | $orig_status | failed | final tree unchanged |"; failed_count=$((failed_count+1)); continue; }
  if [[ "$DRY_RUN" == true ]]; then record "| $tag | $orig_status | would create | all patches applied in order (dry-run) |"; skipped=$((skipped+1)); continue; fi
  args=("$patched" HEAD -m "PiliPlus $tag with ordered patch manifest" -m "base-commit: $base")
  for sha in "${applied[@]}"; do args+=(-m "patch-sha: $sha"); done
  args+=(-m "generated-by: $GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID")
  git tag -a "${args[@]}"
  if git push origin "$patched_ref"; then remote_tags+=$'\n'"$patched_ref"; record "| $tag | $orig_status | created | ${#applied[@]} patches; differences verified |"; success=$((success+1))
  else git tag -d "$patched" >/dev/null 2>&1 || true; record "| $tag | $orig_status | failed | push failed |"; failed_count=$((failed_count+1)); fi
done
record ""
record "Created: $success; existing skipped: $skipped; not applicable: $not_applicable; failed: $failed_count"
(( failed_count == 0 ))
