# yifhhh.xyz — 博客

本站源码仓库。基于 [Astro](https://astro.build/) +
[AstroPaper](https://github.com/satnaing/astro-paper) 主题。

- 主站：<https://yifhhh.xyz>（自建服务器 + Cloudflare 隧道）
- 镜像：<https://zyfsir.github.io>（GitHub Pages）

## 内容从哪来

**不要直接编辑本仓库的 `src/content/posts/`。** 那个目录是自动生成的。

文章在 Obsidian 笔记库的 `博客/` 目录里撰写：

```
/opt/obsidian-sync/博客/*.md
```

写入方式二选一：

- **Obsidian** — 经 WebDAV 同步（`dav.yifhhh.xyz`）
- **ColonyNote** — 浏览器在线编辑（`note.yifhhh.xyz`）

发布流程每隔一段时间自动运行一次，把 `博客/` 下的 Markdown 转换后发布到
本服务器与 GitHub Pages。也可以手动立即发布：

```bash
blog-publish
```

## 写作约定

在 `博客/*.md` 的 frontmatter 里可以写：

```yaml
---
title: 文章标题          # 省略则取正文第一个 H1，再省略则用文件名
description: 摘要        # 省略则取正文第一段（截断 160 字）
created: 2026-09-24      # 省略则用该文件在 git 中的首次提交时间
tags: [agent, 架构]      # 省略为空
slug: my-post            # 省略则由文件名转拼音，如 代码专用agent设计 -> dai-ma-zhuan-yong-agent-she-ji
featured: false          # 是否首页精选
---
```

要点：

- **URL 由文件名（拼音）决定**，所以想固定某篇文章的链接，请设置 `slug`。
- 正文开头的第一个 `# 标题` 会被提取为文章标题，不会重复渲染。
- 图片建议放在笔记库的 `attachments/` 目录，转换时会自动复制并重写链接。
- `.excalidraw.md` 等派生文件会被跳过。

## 发布流程（服务器上）

| 文件 | 作用 |
| --- | --- |
| `/usr/local/bin/blog-publish` | 手动触发入口 |
| `/opt/blog/scripts/publish.sh` | 发布编排：校验 → 转换 → 构建 → 原子切换 → 推送 |
| `/opt/blog/scripts/convert.mjs` | Markdown 转换器（frontmatter 映射 / 拼音 slug / 链接与图片重写） |
| `/etc/blog-publish.conf` | 配置（源目录路径、阈值、推送开关等） |
| `/var/log/blog-publish.log` | 发布日志 |

### 安全闸门

发布前有下列校验，**任一失败即拒绝发布，站点与仓库保持上一版本不变**：

| 闸门 | 内容 |
| --- | --- |
| G0 | 笔记库可读 |
| G1 | 源目录存在（捕获重命名/删除，并提示疑似目录） |
| G2 | 源目录已静默 15 秒（防半写状态） |
| G3 | 至少解析出 1 篇（防止站点被清空） |
| G4 | 文章数不低于上轮的 50%（防止批量误删被传播到线上与公开仓库） |

确需批量删除时显式覆盖：

```bash
ALLOW_SHRINK=1 blog-publish    # 允许大幅缩水
ALLOW_EMPTY=1  blog-publish    # 允许清空
FORCE=1        blog-publish    # 内容无变化也强制重新构建
```

### 部署方式

nginx 的 `root` 指向符号链接 `/var/www/yifhhh-current`，发布时通过
`rename(2)` **原子替换**，因此不存在"半新半旧"窗口；历史版本保留在
`/var/www/yifhhh-releases/`，回滚只需把符号链接指回上一版本。

## 本地开发

```bash
pnpm install
pnpm dev        # 需要先 pnpm build 一次，搜索索引才会生成
pnpm build
```

## 许可

主题部分来自 AstroPaper（MIT）。文章内容版权归作者所有。
