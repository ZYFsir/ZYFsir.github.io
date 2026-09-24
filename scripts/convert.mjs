#!/usr/bin/env node
/**
 * convert.mjs — 把 Obsidian 笔记库中的「博客」目录转换为 AstroPaper 内容集合
 *
 * 设计要点：
 *  - 先全部解析到内存，写盘只在调用方校验通过后发生（这里写的是 staging 目录）
 *  - 单篇文件出错只跳过该篇并记入 report.warnings，不中断整轮
 *  - slug 用拼音（中文文件名），碰撞自动加序号
 *
 * 用法:
 *   node convert.mjs --src <博客目录> --vault <笔记库根> --out <staging目录> [--report <json路径>]
 */

import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { execFileSync } from "node:child_process";
import { pinyin } from "pinyin-pro";
import yaml from "js-yaml";

// ---------------------------------------------------------------- 参数解析
function parseArgs(argv) {
  const out = {};
  for (let i = 2; i < argv.length; i += 2) {
    const k = argv[i].replace(/^--/, "");
    out[k] = argv[i + 1];
  }
  return out;
}
const args = parseArgs(process.argv);
const SRC_DIR = args.src;
const VAULT_DIR = args.vault;
const OUT_DIR = args.out;
const REPORT_PATH = args.report;

if (!SRC_DIR || !VAULT_DIR || !OUT_DIR) {
  console.error("用法: node convert.mjs --src <dir> --vault <dir> --out <dir> [--report <json>]");
  process.exit(64);
}

const IMAGE_EXT = new Set([
  ".png", ".jpg", ".jpeg", ".gif", ".webp", ".avif", ".svg", ".bmp", ".ico",
]);
const ALLOWED_EXT = new Set([".md"]); // 只处理 markdown（.excalidraw.md 单独排除）
const MAX_DESC_LEN = 160;

const warnings = [];
const errors = [];

// ---------------------------------------------------------------- 工具函数
const sha256 = (buf) => crypto.createHash("sha256").update(buf).digest("hex");

function walkMd(dir) {
  const found = [];
  const stack = [dir];
  while (stack.length) {
    const cur = stack.pop();
    let entries;
    try {
      entries = fs.readdirSync(cur, { withFileTypes: true });
    } catch (e) {
      errors.push(`无法读取目录 ${cur}: ${e.message}`);
      continue;
    }
    for (const ent of entries) {
      if (ent.name.startsWith(".")) continue;
      const full = path.join(cur, ent.name);
      if (ent.isDirectory()) {
        stack.push(full);
      } else if (ent.isFile()) {
        const ext = path.extname(ent.name).toLowerCase();
        if (!ALLOWED_EXT.has(ext)) continue;
        // 跳过 Obsidian Excalidraw 等派生文件
        if (ent.name.toLowerCase().endsWith(".excalidraw.md")) {
          warnings.push({ type: "skipped", file: path.relative(SRC_DIR, full), reason: "excalidraw 派生文件" });
          continue;
        }
        found.push(full);
      }
    }
  }
  return found.sort();
}

/** 建立「文件名 -> 绝对路径列表」索引，用于解析 Obsidian 的 ![[image.png]] 引用 */
function buildAssetIndex(vaultDir) {
  const index = new Map();
  const stack = [vaultDir];
  while (stack.length) {
    const cur = stack.pop();
    let entries;
    try {
      entries = fs.readdirSync(cur, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const ent of entries) {
      if (ent.name.startsWith(".")) continue;
      const full = path.join(cur, ent.name);
      if (ent.isDirectory()) {
        stack.push(full);
      } else if (ent.isFile()) {
        const ext = path.extname(ent.name).toLowerCase();
        if (!IMAGE_EXT.has(ext)) continue;
        if (!index.has(ent.name)) index.set(ent.name, []);
        index.get(ent.name).push(full);
      }
    }
  }
  return index;
}

/** 解析 frontmatter，返回 { data, body } */
function splitFrontmatter(raw) {
  if (!raw.startsWith("---")) return { data: {}, body: raw };
  const m = raw.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?/);
  if (!m) return { data: {}, body: raw };
  let data = {};
  try {
    const parsed = yaml.load(m[1]);
    if (parsed && typeof parsed === "object") data = parsed;
  } catch (e) {
    warnings.push({ type: "frontmatter_parse_error", reason: e.message });
  }
  return { data, body: raw.slice(m[0].length) };
}

/** markdown -> 纯文本（用于生成 description） */
function toPlainText(md) {
  return md
    .replace(/^---[\s\S]*?---/, "")
    .replace(/```[\s\S]*?```/g, " ")
    .replace(/`([^`]*)`/g, "$1")
    .replace(/!\[[^\]]*\]\([^)]*\)/g, " ")
    .replace(/!\[\[[^\]]*\]\]/g, " ")
    .replace(/\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/\[\[([^\]|#]*)(?:#[^\]|]*)?(?:\|([^\]]*))?\]\]/g, (_, a, b) => b || a)
    // 只剥离行首的标记，避免误伤词内连字符（pi-ai）与箭头（-&gt;）
    .replace(/^[ \t]{0,3}#{1,6}[ \t]+/gm, "")
    .replace(/^[ \t]{0,3}>[ \t]?/gm, "")
    .replace(/^[ \t]{0,3}(?:[-*+]|\d+\.)[ \t]+/gm, "")
    .replace(/(\*\*|__)(.*?)\1/g, "$2")
    .replace(/~~(.*?)~~/g, "$1")
    .replace(/(?<![\w*])\*([^*\n]+)\*(?![\w*])/g, "$1")
    .replace(/<[^>]+>/g, " ")
    .replace(/&gt;/g, ">").replace(/&lt;/g, "<").replace(/&amp;/g, "&")
    .replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'").replace(/&nbsp;/g, " ")
    .replace(/[ \t]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function firstParagraph(md) {
  const lines = md.split(/\r?\n/);
  const buf = [];
  for (const line of lines) {
    const t = line.trim();
    if (!t) {
      if (buf.length) break;
      continue;
    }
    if (/^#{1,6}\s/.test(t)) continue;          // 跳过标题
    if (/^```/.test(t)) continue;               // 跳过代码块起始
    if (/^[|>\-*+]\s/.test(t) && !buf.length) continue;
    buf.push(t);
    if (toPlainText(buf.join(" ")).length > MAX_DESC_LEN) break;
  }
  return buf.join(" ");
}

function truncate(s, n) {
  const t = s.replace(/\s+/g, " ").trim();
  if (t.length <= n) return t;
  return t.slice(0, n - 1).replace(/[，。、；：,.;: ]+$/, "") + "…";
}

/** 文件名 -> 拼音 slug */
function slugify(name) {
  const base = name.replace(/\.md$/i, "");
  const parts = pinyin(base, { toneType: "none", type: "array", nonZh: "consecutive" });
  return parts
    .join("-")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .replace(/-{2,}/g, "-");
}

/** 取该文件在 git 中首次提交的时间（用于 pubDatetime 兜底） */
function gitFirstCommitISO(absPath) {
  try {
    const rel = path.relative(VAULT_DIR, absPath);
    const out = execFileSync(
      "git",
      ["log", "--diff-filter=A", "--follow", "--format=%aI", "--", rel],
      { cwd: VAULT_DIR, encoding: "utf-8", stdio: ["ignore", "pipe", "ignore"] }
    ).trim();
    const first = out.split("\n").filter(Boolean).pop();
    return first ? new Date(first) : null;
  } catch {
    return null;
  }
}

function toDate(v) {
  if (v == null) return null;
  if (v instanceof Date && !isNaN(v)) return v;
  const d = new Date(String(v));
  return isNaN(d) ? null : d;
}

/** 正文变换：剥离首个 H1、wiki 链接、HTML 实体；图片引用交给调用方处理 */
function transformBody(body) {
  let b = body;

  // 还原被转义的 wiki 链接
  b = b.replace(/\\\[\\\[/g, "[[").replace(/\\\]\\\]/g, "]]");

  // wiki 链接 -> 文本/别名
  b = b.replace(/\[\[([^\]|#]+)(?:#[^\]|]*)?(?:\|([^\]]*))?\]\]/g, (_, target, alias) => {
    return (alias || target).trim();
  });

  // HTML 实体还原
  b = b.replace(/&gt;/g, ">").replace(/&lt;/g, "<").replace(/&amp;/g, "&")
       .replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'").replace(/&nbsp;/g, " ");

  return b;
}

/** 剥离正文开头的第一个 H1，返回 { title, body } */
function extractLeadingH1(body) {
  const lines = body.split(/\r?\n/);
  let i = 0;
  while (i < lines.length && !lines[i].trim()) i++;
  const m = lines[i] && lines[i].match(/^#\s+(.+?)\s*$/);
  if (!m) return { title: null, body };
  lines.splice(i, 1);
  return { title: m[1].trim(), body: lines.join("\n") };
}

// ---------------------------------------------------------------- 主流程
if (!fs.existsSync(SRC_DIR) || !fs.statSync(SRC_DIR).isDirectory()) {
  console.error(`[FATAL] 源目录不存在或不是目录: ${SRC_DIR}`);
  process.exit(65);
}
if (!fs.existsSync(VAULT_DIR) || !fs.statSync(VAULT_DIR).isDirectory()) {
  console.error(`[FATAL] 笔记库不存在或不是目录: ${VAULT_DIR}`);
  process.exit(65);
}

const assetIndex = buildAssetIndex(VAULT_DIR);
const files = walkMd(SRC_DIR);

// 清理并建立 staging 输出
fs.rmSync(OUT_DIR, { recursive: true, force: true });
fs.mkdirSync(path.join(OUT_DIR, "posts"), { recursive: true });
fs.mkdirSync(path.join(OUT_DIR, "images"), { recursive: true });

const usedSlugs = new Map();
const posts = [];

for (const abs of files) {
  const rel = path.relative(SRC_DIR, abs);
  let raw;
  try {
    raw = fs.readFileSync(abs, "utf-8");
  } catch (e) {
    warnings.push({ type: "read_error", file: rel, reason: e.message });
    continue;
  }

  try {
    const { data, body: body0 } = splitFrontmatter(raw);
    const { title: h1, body: body1 } = extractLeadingH1(body0);

    // ---- title
    const title =
      (typeof data.title === "string" && data.title.trim()) ||
      h1 ||
      path.basename(abs, ".md");

    // ---- slug
    let slug =
      (typeof data.slug === "string" && data.slug.trim()) ||
      slugify(path.basename(abs, ".md"));
    if (!slug) {
      slug = "post-" + sha256(rel).slice(0, 8);
      warnings.push({ type: "slug_fallback", file: rel, slug });
    }
    if (usedSlugs.has(slug)) {
      const n = usedSlugs.get(slug) + 1;
      usedSlugs.set(slug, n);
      const newSlug = `${slug}-${n}`;
      warnings.push({ type: "slug_collision", file: rel, slug, renamed: newSlug });
      slug = newSlug;
    } else {
      usedSlugs.set(slug, 1);
    }

    // ---- 日期
    let pub =
      toDate(data.pubDatetime) || toDate(data.created) || toDate(data.date) ||
      gitFirstCommitISO(abs);
    if (!pub) {
      try {
        pub = fs.statSync(abs).mtime;
        warnings.push({ type: "date_fallback_mtime", file: rel });
      } catch {
        pub = new Date(0);
      }
    }
    const mod = toDate(data.modDatetime) || toDate(data.modified);

    // ---- tags（去掉与 type 同名的元标签）
    let tags = [];
    const rawTags = data.tags ?? data.tag;
    if (Array.isArray(rawTags)) tags = rawTags.map(String);
    else if (typeof rawTags === "string") tags = rawTags.split(/[,\s]+/);
    else if (Buffer.isBuffer(rawTags)) tags = [rawTags.toString()];
    const typeVal = typeof data.type === "string" ? data.type : null;
    tags = tags.map((t) => t.trim()).filter(Boolean);
    if (typeVal) tags = tags.filter((t) => t !== typeVal);

    // ---- 正文与图片
    let body = transformBody(body1);
    const images = [];
    const imgDirOut = path.join(OUT_DIR, "images", slug);

    const copyImage = (refRaw) => {
      const ref = refRaw.trim().replace(/^<|>$/g, "");
      const name = path.basename(ref);
      let srcAbs = null;
      if (path.isAbsolute(ref) && fs.existsSync(ref)) srcAbs = ref;
      else {
        const same = path.join(path.dirname(abs), ref);
        if (fs.existsSync(same)) srcAbs = same;
        else if (fs.existsSync(path.join(VAULT_DIR, ref))) srcAbs = path.join(VAULT_DIR, ref);
        else if (fs.existsSync(path.join(VAULT_DIR, "attachments", ref))) srcAbs = path.join(VAULT_DIR, "attachments", ref);
        else if (assetIndex.has(name) && assetIndex.get(name).length > 0) srcAbs = assetIndex.get(name)[0];
      }
      if (!srcAbs) {
        warnings.push({ type: "image_not_found", file: rel, ref });
        return null;
      }
      let outName = name;
      let i = 2;
      while (images.some((im) => im.outName === outName)) {
        const ext = path.extname(name);
        outName = `${path.basename(name, ext)}-${i}${ext}`;
        i++;
      }
      fs.mkdirSync(imgDirOut, { recursive: true });
      fs.copyFileSync(srcAbs, path.join(imgDirOut, outName));
      images.push({ outName, srcAbs });
      return outName;
    };

    // ![[image.png]] / ![[image.png|300]]
    body = body.replace(/!\[\[([^\]|]+)(?:\|[^\]]*)?\]\]/g, (whole, ref) => {
      const out = copyImage(ref);
      return out ? `![${path.basename(out)}](/images/${slug}/${out})` : whole;
    });

    // ![alt](path) —— 只处理指向本地真实文件的引用
    body = body.replace(/!\[([^\]]*)\]\(([^)\s]+)\)/g, (whole, alt, ref) => {
      if (/^(https?:)?\/\//.test(ref) || ref.startsWith("data:")) return whole;
      const ext = path.extname(ref).toLowerCase();
      if (!IMAGE_EXT.has(ext)) return whole;
      const out = copyImage(ref);
      return out ? `![${alt || path.basename(out)}](/images/${slug}/${out})` : whole;
    });

    // ---- description
    const desc =
      (typeof data.description === "string" && data.description.trim()) ||
      truncate(toPlainText(firstParagraph(body)), MAX_DESC_LEN) ||
      truncate(toPlainText(body), MAX_DESC_LEN) ||
      title;

    // ---- 组装输出
    const fm = {
      title,
      description: desc,
      // 传 Date 对象：js-yaml 会输出不带引号的 ISO 时间戳，与上游示例一致
      pubDatetime: pub,
    };
    if (mod && mod.getTime() !== pub.getTime()) fm.modDatetime = mod;
    fm.tags = tags;
    if (typeof data.featured === "boolean") fm.featured = data.featured;

    const header =
      "---\n" +
      yaml.dump(fm, { lineWidth: -1, quotingType: '"', forceQuotes: false }) +
      "---\n\n" +
      `<!-- 由 blog-publish 自动生成，请勿手工编辑。源文件: 博客/${rel} -->\n\n`;

    const outFile = path.join(OUT_DIR, "posts", `${slug}.md`);
    fs.writeFileSync(outFile, header + body.replace(/^\s*\n/, ""), "utf-8");

    posts.push({
      slug,
      srcRel: rel,
      // 源文件内容 hash：用于变更检测与「新增/修改/删除」差异报告
      hash: sha256(raw),
      title,
      pubDatetime: pub.toISOString(),
      tags: fm.tags,
      images: images.map((i) => i.outName),
      bytes: Buffer.byteLength(header + body, "utf-8"),
    });
  } catch (e) {
    errors.push({ file: rel, reason: e?.message || String(e) });
  }
}

const report = {
  generatedAt: new Date().toISOString(),
  srcDir: SRC_DIR,
  vaultDir: VAULT_DIR,
  outDir: OUT_DIR,
  count: posts.length,
  sourceFiles: files.length,
  posts,
  warnings,
  errors,
};

const reportJson = JSON.stringify(report, null, 2);
if (REPORT_PATH) {
  fs.mkdirSync(path.dirname(REPORT_PATH), { recursive: true });
  fs.writeFileSync(REPORT_PATH, reportJson, "utf-8");
}
process.stdout.write(reportJson);

// 单篇失败不致命；只有"一篇都没成功但源里有文件"才是异常（由 publish.sh 的 G3 判定）
process.exit(0);
