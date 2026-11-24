---
title: "欢迎使用 AsmBlog：纯 x86-64 汇编个人静态博客"
slug: welcome-to-asmblog
date: 2026-11-24
category: "日常随笔"
tags: asmblog, 静态博客, linux
summary: "无需数据库、无需登录后台、零 libc 依赖——直接用 Markdown 写作，用纯 x86-64 汇编构建与托管你的个人静态博客。"
draft: false
---

## 为什么选择纯汇编静态博客？

AsmBlog 是专为单人写作打造的**纯 x86-64 Linux 汇编静态博客框架**。整个可执行文件直接通过 Linux `syscall` 与内核交互，不依赖 `glibc`、不依赖任何第三方动态库，也没有登录、评论、数据库等额外攻击面。

> 写文章只需要打开编辑器编写本地 `.md` 文件，保存即可生效或一键导出完整静态站点。

## 日常写作流程

1. 创建一篇新文章：

```bash
asmblog new my-first-note "我的第一篇随笔"
```

2. 用 `vim` / `nano` 或通过 SFTP/Git 编辑 `content/posts/my-first-note.md`。
3. 两种发布方式任选其一：
   - **直接实时托管（当前服务器已开启）**：`asmblog serve` 内置 `inotify` 文件监听，保存 `.md` 文件的瞬间自动重新解析并渲染，无需重启进程。
   - **一键导出纯静态站点**：运行 `asmblog build`，在 `dist/` 目录生成包含所有 HTML、RSS、Sitemap、静态搜索索引和 CSS/JS 的纯静态网站，可随时上传到 Nginx、Cloudflare Pages 或 GitHub Pages。

## 核心特性一览

- **零依赖静态 ELF**：单文件二进制直接运行于 x86-64 Linux，常驻内存仅几 MB。
- **完整静态生成 (`asmblog build`)**：生成首页、分页、文章页、归档页、标签页、搜索页、`search-index.json`、`rss.xml`、`sitemap.xml` 与 `404.html`。
- **高性能内置静态服务器 (`asmblog serve`)**：基于 `epoll` 非阻塞事件循环、HTTP/1.1 Keep-Alive、`ETag / 304` 与内核 `sendfile` 零拷贝。
- **主题可自由定制**：修改 `themes/default/` 下的 HTML 模板和 CSS 样式，无需重新编译汇编代码。
