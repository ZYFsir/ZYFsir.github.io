#!/usr/bin/env bash
# ============================================================================
# blog-publish.sh — 把笔记库的「博客」目录发布到 yifhhh.xyz 与 GitHub Pages
#
# 内容流：
#   $SRC_DIR/*.md  --convert-->  src/content/posts/  --build-->  dist
#                                                            --原子切换-->  线上
#                                                            --push-->     GitHub Pages
#
# 安全设计（任一校验失败 → 拒绝发布，站点与仓库全部保持原样）：
#   G0  笔记库可读
#   G1  源目录存在（捕获重命名/删除，并提示疑似目录）
#   G2  源目录已静默 N 秒（捕获取消半写状态）
#   G3  解析出至少 1 篇（防止站点被清空）
#   G4  文章数不低于上轮的 MIN_RATIO%（防止批量误删被传播到线上与公开仓库）
#
# 覆盖开关（仅在确需大改时显式使用）：
#   ALLOW_EMPTY=1 blog-publish     允许本轮变空
#   ALLOW_SHRINK=1 blog-publish    允许本轮大幅缩水
#   FORCE=1 blog-publish           忽略"内容未变化"的快速退出
# ============================================================================
set -uo pipefail

CONF_FILE="${BLOG_PUBLISH_CONF:-/etc/blog-publish.conf}"
# shellcheck source=/dev/null
[ -r "$CONF_FILE" ] && . "$CONF_FILE"

VAULT_DIR="${VAULT_DIR:-/opt/obsidian-sync}"
SRC_DIR="${SRC_DIR:-$VAULT_DIR/博客}"
BLOG_DIR="${BLOG_DIR:-/opt/blog}"
STAGING_DIR="${STAGING_DIR:-/var/lib/blog-publish/staging}"
RELEASES_DIR="${RELEASES_DIR:-/var/www/yifhhh-releases}"
CURRENT_LINK="${CURRENT_LINK:-/var/www/yifhhh-current}"
STATE_DIR="${STATE_DIR:-/var/lib/blog-publish}"
STATE_FILE="$STATE_DIR/state.json"
LOCK_FILE="$STATE_DIR/publish.lock"
LOG_FILE="${LOG_FILE:-/var/log/blog-publish.log}"
QUIET_SECONDS="${QUIET_SECONDS:-15}"
MIN_RATIO="${MIN_RATIO:-50}"
MIN_COUNT_FOR_RATIO="${MIN_COUNT_FOR_RATIO:-4}"
KEEP_RELEASES="${KEEP_RELEASES:-5}"
GIT_REMOTE="${GIT_REMOTE:-origin}"
GIT_BRANCH="${GIT_BRANCH:-main}"
PUSH="${PUSH:-1}"
SITE_HOST="${SITE_HOST:-yifhhh.xyz}"

REPORT_FILE="$STATE_DIR/report.json"

# --------------------------------------------------------------------- 日志
mkdir -p "$STATE_DIR" 2>/dev/null || true
if [ -f "$LOG_FILE" ] && [ "$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)" -gt 5242880 ]; then
  mv -f "$LOG_FILE" "$LOG_FILE.1" 2>/dev/null || true
fi
log()  { local m="[$(date '+%F %T')] $*"; echo "$m" >>"$LOG_FILE" 2>/dev/null; echo "$m"; }
info() { log "INFO   $*"; }
warn() { log "WARN   $*"; }
err()  { log "ERROR  $*"; }

die() {
  local msg="$1"; shift || true
  err "$msg"
  for l in "$@"; do log "HINT   $l"; done
  log "ABORT  拒绝发布 —— 站点与 GitHub 仓库均保持上一版本不变"
  exit 1
}

# --------------------------------------------------------------------- 并发锁
exec 9>"$LOCK_FILE" 2>/dev/null || die "无法创建锁文件 $LOCK_FILE"
if ! flock -n 9; then
  info "另一轮发布正在进行，本轮跳过"
  exit 0
fi

info "==================== 发布开始 ===================="
info "源目录   : $SRC_DIR"
info "博客工程 : $BLOG_DIR"

# ------------------------------------------------------- 读取上一轮状态
read_state() {
  if [ -r "$STATE_FILE" ]; then
    node -e '
      const fs=require("fs");
      try{ const s=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
        process.stdout.write(JSON.stringify(s));
      }catch(e){ process.stdout.write("{}"); }
    ' "$STATE_FILE"
  else
    echo "{}"
  fi
}
STATE_JSON="$(read_state)"
state_field() {
  node -e '
    const s=JSON.parse(process.argv[1]||"{}");
    const v=s[process.argv[2]];
    process.stdout.write(v===undefined||v===null?"":String(v));
  ' "$STATE_JSON" "$1"
}
LAST_HASH="$(state_field sourceHash)"
LAST_COUNT="$(state_field count)"
LAST_COUNT="${LAST_COUNT:-0}"

# ============================================================ G0 笔记库可读
[ -d "$VAULT_DIR" ] || die "G0 笔记库不存在: $VAULT_DIR" \
  "请确认笔记库是否已挂载/存在"
[ -r "$VAULT_DIR" ] || die "G0 笔记库不可读: $VAULT_DIR" \
  "检查目录权限"

# ============================================================ G1 源目录存在
if [ ! -d "$SRC_DIR" ]; then
  CANDIDATES="$(find "$VAULT_DIR" -maxdepth 2 -type d \
                  \( -iname "*博客*" -o -iname "*blog*" \) 2>/dev/null | head -8)"
  HINTS=("如果这是有意的重命名或移动，请修改 $CONF_FILE 里的 SRC_DIR 后重试")
  if [ -n "$CANDIDATES" ]; then
    HINTS+=("在笔记库中找到疑似目录:")
    while IFS= read -r c; do [ -n "$c" ] && HINTS+=("    $c"); done <<< "$CANDIDATES"
  fi
  HINTS+=("如果只是想临时停止发布，直接忽略即可（站点不受影响）")
  die "G1 源目录不存在或不可读: $SRC_DIR" "${HINTS[@]}"
fi
if [ ! -r "$SRC_DIR" ]; then
  die "G1 源目录不可读: $SRC_DIR" "检查目录权限"
fi

# ============================================================ 内容未变化快速退出
compute_source_hash() {
  local h
  h="$(cd "$SRC_DIR" && find . -type f -name '*.md' -not -path '*/.*' -print0 2>/dev/null \
        | sort -z \
        | xargs -0 -r sha256sum 2>/dev/null \
        | sha256sum | cut -d' ' -f1)"
  echo "${h:-none}"
}
SRC_HASH="$(compute_source_hash)"
if [ "${FORCE:-0}" != "1" ] && [ -n "$LAST_HASH" ] && [ "$SRC_HASH" = "$LAST_HASH" ]; then
  info "内容未变化（hash ${SRC_HASH:0:12}…），无需发布"
  info "==================== 结束（无变化）===================="
  exit 0
fi

# ============================================================ G2 静默期
if [ "${G2_SKIP:-0}" != "1" ]; then
  RECENT="$(find "$SRC_DIR" -type f -newermt "-${QUIET_SECONDS} seconds" 2>/dev/null | wc -l)"
  if [ "$RECENT" -gt 0 ]; then
    info "G2 源目录 ${QUIET_SECONDS}s 内有 $RECENT 个文件变动（可能仍在写入），等下一轮"
    exit 0
  fi
fi

# ============================================================ 转换（只写 staging）
info "开始转换 …"
node "$BLOG_DIR/scripts/convert.mjs" \
     --src "$SRC_DIR" --vault "$VAULT_DIR" \
     --out "$STAGING_DIR" --report "$REPORT_FILE" >/dev/null 2>"$STATE_DIR/convert.err"
CONV_RC=$?
if [ $CONV_RC -ne 0 ]; then
  err "转换器退出码 $CONV_RC"
  [ -s "$STATE_DIR/convert.err" ] && sed 's/^/       /' "$STATE_DIR/convert.err" | while IFS= read -r l; do log "$l"; done
  die "转换阶段失败" "详情见 $LOG_FILE"
fi

IFS=$'\t' read -r NEW_COUNT NEW_SLUGS WARN_N ERR_N SRC_FILES <<< "$(node -e '
  const fs=require("fs");
  const r=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
  process.stdout.write([
    r.count,
    r.posts.map(p=>p.slug).join(" "),
    r.warnings.length,
    r.errors.length,
    r.sourceFiles
  ].join("\t"));
' "$REPORT_FILE")"

info "解析结果: $NEW_COUNT 篇有效文章（源 markdown 文件 $SRC_FILES 个），警告 $WARN_N，错误 $ERR_N"

# 逐条打印警告/错误
node -e '
  const fs=require("fs");
  const r=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
  for(const w of r.warnings) console.log("WARNDETAIL\t"+JSON.stringify(w));
  for(const e of r.errors)   console.log("ERRDETAIL\t"+JSON.stringify(e));
' "$REPORT_FILE" 2>/dev/null | while IFS=$'\t' read -r tag payload; do
  case "$tag" in
    WARNDETAIL) log "WARN   (细节) $payload" ;;
    ERRDETAIL)  log "ERROR  (细节) $payload" ;;
  esac
done

# ============================================================ G3 非空
if [ "$NEW_COUNT" -eq 0 ]; then
  if [ "${ALLOW_EMPTY:-0}" = "1" ]; then
    warn "G3 本轮解析出 0 篇，但 ALLOW_EMPTY=1，继续"
  else
    die "G3 本轮解析出 0 篇有效文章（源目录里共有 $SRC_FILES 个 markdown 文件）" \
        "这通常意味着源目录内容异常，拒绝把站点清空" \
        "如果你确实想让博客变空，请显式执行: ALLOW_EMPTY=1 blog-publish"
  fi
fi

# ============================================================ G4 缩水比例
if [ "$LAST_COUNT" -ge "$MIN_COUNT_FOR_RATIO" ] && [ "$NEW_COUNT" -lt "$LAST_COUNT" ]; then
  THRESHOLD=$(( LAST_COUNT * MIN_RATIO / 100 ))
  if [ "$NEW_COUNT" -lt "$THRESHOLD" ]; then
    if [ "${ALLOW_SHRINK:-0}" = "1" ]; then
      warn "G4 文章数 $LAST_COUNT -> $NEW_COUNT 低于阈值 $THRESHOLD，但 ALLOW_SHRINK=1，继续"
    else
      REMOVED="$(node -e '
        const fs=require("fs");
        const r=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
        const prev=(JSON.parse(process.argv[2]||"{}").slugs)||[];
        const now=new Set(r.posts.map(p=>p.slug));
        process.stdout.write(prev.filter(s=>!now.has(s)).join(", "));
      ' "$REPORT_FILE" "$STATE_JSON")"
      HINTS=("消失的 slug: ${REMOVED:-（无）}")
      HINTS+=("常见原因: 误删文件、子目录被移动、同步未完成、重命名了文章")
      HINTS+=("如果你确实要删除这些文章，请显式执行: ALLOW_SHRINK=1 blog-publish")
      die "G4 文章数从 $LAST_COUNT 骤降到 $NEW_COUNT（低于 ${MIN_RATIO}% 阈值 $THRESHOLD）" "${HINTS[@]}"
    fi
  fi
fi

# ============================================================ 应用内容
info "校验通过，写入内容集合 …"
mkdir -p "$BLOG_DIR/src/content/posts" "$BLOG_DIR/public/images"
rsync -a --delete "$STAGING_DIR/posts/"  "$BLOG_DIR/src/content/posts/"
rsync -a --delete "$STAGING_DIR/images/" "$BLOG_DIR/public/images/"

# 差异报告
node -e '
  const fs=require("fs");
  const r=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
  const prev=JSON.parse(process.argv[2]||"{}");
  const oldHashes=prev.postHashes||{};
  const now=new Set(r.posts.map(p=>p.slug));
  const added=[],changed=[];
  for(const p of r.posts){
    if(!(p.slug in oldHashes)) added.push(p.slug);
    else if(oldHashes[p.slug]!==p.hash) changed.push(p.slug);
  }
  const removed=Object.keys(oldHashes).filter(s=>!now.has(s));
  console.log("INFO   \t新增: " + (added.join(", ")||"（无）"));
  console.log("INFO   \t修改: " + (changed.join(", ")||"（无）"));
  console.log("INFO   \t删除: " + (removed.join(", ")||"（无）"));
' "$REPORT_FILE" "$STATE_JSON" 2>/dev/null | while IFS=$'\t' read -r tag payload; do log "$tag$payload"; done

# ============================================================ 构建
info "开始构建 …"
rm -rf "$BLOG_DIR/dist"
cd "$BLOG_DIR" || die "无法进入 $BLOG_DIR"
BUILD_START=$(date +%s)
if ! pnpm exec astro build >>"$LOG_FILE" 2>&1; then
  err "astro build 失败，详见 $LOG_FILE"
  tail -20 "$LOG_FILE" | sed 's/^/       /' | while IFS= read -r l; do log "$l"; done
  die "构建失败" "线上站点与 GitHub 仓库均未改动"
fi
if ! pnpm exec pagefind --site dist >>"$LOG_FILE" 2>&1; then
  err "pagefind 索引生成失败"
  die "搜索索引构建失败" "线上站点与 GitHub 仓库均未改动"
fi
BUILD_SEC=$(( $(date +%s) - BUILD_START ))
info "构建完成，耗时 ${BUILD_SEC}s"

# ============================================================ 构建产物校验
[ -f "$BLOG_DIR/dist/index.html" ] || die "构建产物缺少 index.html" "线上站点未改动"
MISSING=""
for s in $NEW_SLUGS; do
  [ -f "$BLOG_DIR/dist/posts/$s/index.html" ] || MISSING="$MISSING $s"
done
if [ -n "$MISSING" ]; then
  die "构建产物缺少以下文章页面:$MISSING" "线上站点未改动"
fi
info "产物校验通过: index.html + $NEW_COUNT 篇文章页面均在"

# ============================================================ 原子切换
RELEASE_NAME="$(date +%Y%m%d-%H%M%S)"
RELEASE_PATH="$RELEASES_DIR/$RELEASE_NAME"
mkdir -p "$RELEASES_DIR"
mv "$BLOG_DIR/dist" "$RELEASE_PATH" || die "无法生成发布目录 $RELEASE_PATH"
ln -sfn "$RELEASE_PATH" "$CURRENT_LINK.new" || die "创建符号链接失败"
if ! mv -T "$CURRENT_LINK.new" "$CURRENT_LINK"; then
  rm -rf "$RELEASE_PATH"
  die "原子切换失败" "线上站点保持上一版本"
fi
info "已原子切换到 $RELEASE_PATH"

# 本地冒烟验证
SMOKE="$(curl -s -o /dev/null -w '%{http_code}' -H "Host: $SITE_HOST" http://127.0.0.1:80/ --max-time 8)"
if [ "$SMOKE" != "200" ]; then
  err "冒烟验证失败（HTTP $SMOKE），自动回滚"
  PREV="$(state_field releasePath)"
  if [ -n "$PREV" ] && [ -d "$PREV" ]; then
    ln -sfn "$PREV" "$CURRENT_LINK.new" && mv -T "$CURRENT_LINK.new" "$CURRENT_LINK"
    info "已回滚到 $PREV"
  fi
  rm -rf "$RELEASE_PATH"
  die "发布后冒烟验证未通过"
fi
info "冒烟验证通过 (HTTP $SMOKE)"

# ============================================================ 清理旧版本
mapfile -t ALL_RELEASES < <(ls -1d "$RELEASES_DIR"/*/ 2>/dev/null | sort -r)
CURRENT_TARGET="$(readlink -f "$CURRENT_LINK")"
idx=0
for r in "${ALL_RELEASES[@]}"; do
  idx=$((idx+1))
  r="${r%/}"
  [ "$r" = "$CURRENT_TARGET" ] && continue
  [ "$idx" -le "$KEEP_RELEASES" ] && continue
  rm -rf "$r" && info "清理旧版本 $(basename "$r")"
done

# ============================================================ git + push
if command -v git >/dev/null 2>&1 && [ -d "$BLOG_DIR/.git" ]; then
  cd "$BLOG_DIR" || true
  git add -A >>"$LOG_FILE" 2>&1
  if ! git diff --cached --quiet; then
    if git -c user.name="blog-publish" -c user.email="blog-publish@yifhhh.xyz" \
         commit -q -m "publish: $(date '+%F %T') (${NEW_COUNT} posts)"; then
      info "已提交内容变更"
    else
      warn "git commit 失败（不阻断本地发布）"
    fi
  else
    info "内容无变化，无需提交"
  fi

  if [ "$PUSH" = "1" ]; then
    if git push "$GIT_REMOTE" "$GIT_BRANCH" >>"$LOG_FILE" 2>&1; then
      info "push 成功 -> $GIT_REMOTE/$GIT_BRANCH"
    else
      warn "push 失败（不阻断本地发布，下轮会重试）"
      tail -5 "$LOG_FILE" | sed 's/^/       /' | while IFS= read -r l; do log "$l"; done
    fi
  else
    info "PUSH=0，跳过推送"
  fi
fi

# ============================================================ 保存状态
node -e '
  const fs=require("fs");
  const [reportPath,statePath,srcHash,releasePath] = process.argv.slice(1);
  const r=JSON.parse(fs.readFileSync(reportPath,"utf8"));
  const postHashes={};
  for(const p of r.posts) postHashes[p.slug]=p.hash;
  const state={
    sourceHash: srcHash,
    count: r.count,
    slugs: r.posts.map(p=>p.slug),
    postHashes,
    releasePath,
    updatedAt: new Date().toISOString(),
  };
  fs.writeFileSync(statePath, JSON.stringify(state,null,2));
' "$REPORT_FILE" "$STATE_FILE" "$SRC_HASH" "$RELEASE_PATH" 2>/dev/null \
  || warn "状态文件写入失败"

info "==================== 发布完成 ===================="
exit 0
