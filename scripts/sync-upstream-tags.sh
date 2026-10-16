#!/usr/bin/env bash
set -Eeuo pipefail
: "${UPSTREAM_URL:?UPSTREAM_URL is required}"
: "${BASELINE_TAG:?BASELINE_TAG is required}"
MODE="${MODE:-sync}"
DRY_RUN="${DRY_RUN:-false}"
PATCH_LIST="${PATCH_LIST:-scripts/patches.conf}"
SUMMARY="${GITHUB_STEP_SUMMARY:-}"

record() { printf '%s\n' "$1"; [[ -z "$SUMMARY" ]] || printf '%s\n' "$1" >> "$SUMMARY"; }
fail() { echo "::error::$*" >&2; record "**失败：** $*"; exit 1; }
[[ "$MODE" == sync || "$MODE" == audit ]] || fail "运行模式只能是 sync 或 audit。"
[[ -f "$PATCH_LIST" ]] || fail "找不到补丁清单：$PATCH_LIST"
git fetch origin main --no-tags
git remote get-url upstream >/dev/null 2>&1 || git remote add upstream "$UPSTREAM_URL"

# Resolve exact commit subjects from origin/main history. Fail closed on ambiguity.
declare -a patch_titles=() patch_shas=() patch_requirements=()
while IFS='|' read -r requirement title || [[ -n "${requirement:-}${title:-}" ]]; do
  requirement="${requirement%$'\r'}"; title="${title%$'\r'}"
  [[ -z "${requirement//[[:space:]]/}" || "$requirement" == \#* ]] && continue
  [[ "$requirement" == required || "$requirement" == optional ]] || fail "补丁类型无效：'$requirement'（文件：$PATCH_LIST）。"
  [[ -n "${title//[[:space:]]/}" ]] || fail "补丁标题不能为空（文件：$PATCH_LIST）。"
  matches="$(git log origin/main --format='%H%x09%s' | awk -F '\t' -v wanted="$title" '$2 == wanted {print $1}')"
  count="$(printf '%s\n' "$matches" | awk 'NF {n++} END {print n+0}')"
  if (( count == 0 )); then
    [[ "$requirement" == optional ]] && { record "已跳过可选补丁：上游未找到精确匹配的提交标题「$title」。"; continue; }
    fail "上游 main 中找不到必需补丁的精确标题：'$title'。"
  fi
  if (( count > 1 )); then
    record "补丁标题存在歧义「$title」，候选提交："
    while IFS= read -r candidate; do [[ -z "$candidate" ]] || record "- $candidate"; done <<< "$matches"
    fail "补丁标题匹配到 $count 个提交，已停止以避免错误应用。"
  fi
  sha="$(printf '%s\n' "$matches" | head -n1)"
  parents="$(git rev-list --parents -n 1 "$sha" | awk '{print NF-1}')"
  (( parents <= 1 )) || fail "补丁「$title」是合并提交（$sha），请改用单父提交。"
  [[ -n "$(git diff-tree --no-commit-id --name-only -r "$sha")" ]] || fail "补丁「$title」（$sha）没有文件变更。"
  patch_titles+=("$title"); patch_shas+=("$sha"); patch_requirements+=("$requirement")
  record "已解析补丁 $((${#patch_shas[@]}))：$title（$sha；$requirement）"
done < "$PATCH_LIST"
(("${#patch_shas[@]}" > 0)) || fail "没有解析到可应用的补丁。"

record ""
record "运行模式：$MODE。补丁严格按清单顺序处理。"
if [[ "$MODE" == audit ]]; then
  git fetch origin '+refs/tags/patched/*:refs/tags/audit-patched/*' --force
  record "## 已发布补丁标签审计"
  record "按标签逐项列出审计结果："
  total=0 ok=0 bad=0
  mapfile -t refs < <(git for-each-ref --format='%(refname)' refs/tags/audit-patched/ | sort -V)
  for ref in "${refs[@]}"; do
    total=$((total+1)); name="${ref#refs/tags/audit-patched/}"
    commit="$(git rev-parse "${ref}^{commit}")"
    message="$(git for-each-ref --format='%(contents)' "$ref")"
    recorded="$(printf '%s\n' "$message" | sed -n 's/^patch-sha: //p')"
    recorded_base="$(printf '%s\n' "$message" | sed -n 's/^base-commit: //p' | head -n1)"
    if [[ -z "$recorded" || -z "$recorded_base" ]]; then
      record "- **$name：不通过** — 标签缺少补丁或基础提交来源记录（旧标签需人工检查）"; bad=$((bad+1)); continue
    fi
    origref="refs/tags/audit-original/$name"
    if ! git fetch origin "refs/tags/$name:$origref" --force >/dev/null 2>&1; then
      record "- **$name：不通过** — 找不到对应的原始上游标签"; bad=$((bad+1)); continue
    fi
    base="$(git rev-parse "${origref}^{commit}")"
    if [[ "$base" != "$recorded_base" ]]; then
      record "- **$name：不通过** — 基础提交来源与原始标签不一致"; bad=$((bad+1)); continue
    fi
    mapfile -t recorded_array <<< "$recorded"
    mapfile -t actual_shas < <(git log --reverse --format='%H' "$base..$commit")
    mapfile -t actual_subjects < <(git log --reverse --format='%s' "$base..$commit")
    valid=true; expected_subjects=(); last_index=-1
    if (("${#recorded_array[@]}" == 0 || ${#recorded_array[@]} != ${#actual_shas[@]})); then valid=false; fi
    if [[ "$valid" == true ]]; then
      for sha in "${recorded_array[@]}"; do
        found=-1
        for i in "${!patch_shas[@]}"; do [[ "${patch_shas[$i]}" == "$sha" ]] && { found=$i; break; }; done
        if (( found < 0 || found <= last_index )); then valid=false; break; fi
        last_index=$found; expected_subjects+=("${patch_titles[$found]}")
      done
    fi
    if [[ "$valid" == true ]]; then
      for i in "${!patch_shas[@]}"; do
        if [[ "${patch_requirements[$i]}" == required ]] && ! printf '%s\n' "$recorded" | grep -qxF "${patch_shas[$i]}"; then valid=false; break; fi
      done
    fi
    if [[ "$valid" == true ]]; then
      for i in "${!actual_shas[@]}"; do
        [[ "${actual_subjects[$i]}" == "${expected_subjects[$i]}" ]] || { valid=false; break; }
      done
    fi
    if [[ "$valid" != true ]] || git diff --quiet "$base" "$commit" --; then
      record "- **$name：不通过** — 补丁顺序、必需补丁、提交记录或文件差异校验失败"; bad=$((bad+1)); continue
    fi
    record "- **$name：通过** — 来源、补丁顺序、必需补丁及文件差异均符合清单"; ok=$((ok+1))
  done
  record ""
  record "审计标签：$total；通过：$ok；不通过：$bad"
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
record "## 上游版本同步结果"
record "按版本逐项列出同步结果："
success=0 failed_count=0 existing_skipped=0 would_create_count=0 not_applicable=0
mapfile -t tags < <(git for-each-ref --format='%(refname)' refs/tags/upstream/ | sed 's#^refs/tags/upstream/##' | sort -Vu)
for tag in "${tags[@]}"; do
  is_eligible "$tag" || continue
  source="refs/tags/upstream/$tag"; base="$(git rev-parse "${source}^{commit}")"
  orig="refs/tags/$tag"; patched="patched/$tag"; patched_ref="refs/tags/$patched"
  if has_remote_tag "$orig"; then orig_status="already present (preserved)"
  elif [[ "$DRY_RUN" == true ]]; then orig_status="would sync (dry-run)"
  elif git push origin "$source:$orig"; then orig_status=synced; remote_tags+=$'\n'"$orig"
  else record "- **$tag：失败** — 推送原始标签失败"; failed_count=$((failed_count+1)); continue
  fi
  if has_remote_tag "$patched_ref"; then record "- **$tag：已跳过** — 原始标签$orig_status；补丁标签已存在并保留，请运行审计模式"; existing_skipped=$((existing_skipped+1)); continue; fi
  git checkout --detach "$base" >/dev/null
  applied=(); patch_failed=false
  for i in "${!patch_shas[@]}"; do
    sha="${patch_shas[$i]}"; title="${patch_titles[$i]}"; requirement="${patch_requirements[$i]}"; before="$(git rev-parse 'HEAD^{tree}')"
    record "正在应用补丁：$tag（$((i+1))/${#patch_shas[@]}）— $title"
    if git cherry-pick "$sha"; then
      after="$(git rev-parse 'HEAD^{tree}')"
      if [[ "$before" == "$after" ]]; then
        git cherry-pick --abort >/dev/null 2>&1 || true
        record "- **$tag：失败** — 补丁「$title」未产生文件差异，无法确认已应用"
        failed_count=$((failed_count+1)); patch_failed=true; break
      fi
      applied+=("$sha")
    else
      if [[ -n "$(git diff --name-only --diff-filter=U)" ]]; then
        git cherry-pick --abort >/dev/null 2>&1 || true
        if [[ "$requirement" == required ]]; then
          record "- **$tag：失败** — 必需补丁「$title」冲突，已停止该版本"
          failed_count=$((failed_count+1)); patch_failed=true; break
        fi
        record "已跳过可选补丁「$title」：与版本 $tag 冲突；继续处理后续补丁。"
        not_applicable=$((not_applicable+1))
        continue
      else
        git cherry-pick --skip >/dev/null 2>&1 || true
        record "- **$tag：失败** — 补丁「$title」为空或已存在，无法确认是否已应用"
        failed_count=$((failed_count+1))
      fi
      patch_failed=true; break
    fi
  done
  [[ "$patch_failed" == false ]] || continue
  [[ -n "$(git diff --name-only "$base" HEAD)" ]] || { record "- **$tag：失败** — 最终文件树未发生变化"; failed_count=$((failed_count+1)); continue; }
  if [[ "$DRY_RUN" == true ]]; then record "- **$tag：模拟创建** — 已按顺序应用 ${#applied[@]} 个补丁"; would_create_count=$((would_create_count+1)); continue; fi
  args=("$patched" HEAD -m "PiliPlus $tag（补丁版）" -m "基于上游版本 $tag 构建。" -m "base-commit: $base")
  for sha in "${applied[@]}"; do args+=(-m "patch-sha: $sha"); done
  args+=(-m "generated-by: $GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID")
  git tag -a "${args[@]}"
  if git push origin "$patched_ref"; then remote_tags+=$'\n'"$patched_ref"; record "- **$tag：已创建** — 成功应用 ${#applied[@]} 个补丁；文件差异校验通过"; success=$((success+1))
  else git tag -d "$patched" >/dev/null 2>&1 || true; record "- **$tag：失败** — 推送补丁标签失败"; failed_count=$((failed_count+1)); fi
done
record ""
record "## 汇总"
record "- 新建补丁标签：$success"
record "- 已存在并保留：$existing_skipped"
record "- 模拟创建：$would_create_count"
record "- 已跳过的可选冲突：$not_applicable"
record "- 失败：$failed_count"
(( failed_count == 0 ))
