---
title: "零 libc 架构解析：如何用纯 x86-64 汇编实现博客框架"
slug: x86-64-assembly-architecture
date: 2026-11-23
category: "技术笔记"
tags: assembly, x86-64, architecture
summary: "拆解 AsmBlog 的模块化汇编设计：Arena 内存管理、流式 Markdown 解析器、Mustache 模板引擎、epoll 事件循环与 SSG 静态生成器。"
draft: false
---

## 整体模块设计

AsmBlog 由 13 个职责清晰的 x86-64 汇编源文件（Intel 语法，GNU `as` + `ld -static` 编译）构成，入口为裸 `_start`：

- `syscall.s`：封装 Linux x86-64 系统调用（`openat`、`read`、`write`、`mmap`、`epoll_*`、`sendfile`、`inotify_*`、`signalfd4`、`getdents64`）。
- `mem.s`：基于 `mmap` 的线性 Bump Arena 分配器，配合带容量边界检查的 `sbuf_t` 安全缓冲区，从源头杜绝缓冲区溢出。
- `markdown.s`：Front-Matter 解析 + 流式状态机 Markdown 转 HTML 引擎，同时完成 HTML 实体转义与链接协议白名单校验。
- `template.s`：Mustache 风格模板引擎，支持 `{{ var }}`、`{{{ raw }}}`、`{{> partial }}`、`{{#section}}` 与 `{{^section}}`。
- `store.s`：启动或文件变动时扫描 `content/posts/*.md` 与 `themes/<theme>/*.html`，一次性完成排序、标签倒排索引与 HTML 预渲染。
- `handlers.s` & `cli.s`：同一套 `render_*` 渲染核心同时服务于 `asmblog build`（导出纯静态 `dist/`）与 `asmblog serve`（实时 HTTP 服务）。

## Arena 热重载如何做到零内存泄漏？

传统服务器在热重载时逐块 `free()` 极易产生碎片或遗漏。AsmBlog 将所有文章、标签和模板字符串统一分配在一块 16 MiB 的匿名 `mmap` Arena 中：

```asm
arena_reset:
    mov qword ptr [rip + g_arena_used], 0
    ret
```

每当 `inotify` 检测到文件改动或收到 `SIGHUP` 时，只需一条指令重置偏移指针并重新扫描目录，O(1) 回收全部旧数据，内存占用恒定不变。

## 为什么选择 signalfd4 + epoll？

在纯汇编中编写异步信号处理函数需要处理 `SA_RESTORER` 蹦床与重入问题。将 `SIGINT`、`SIGTERM`、`SIGHUP` 屏蔽后接入 `signalfd4` 放进同一个 `epoll` 循环，所有网络 I/O、信号控制和 `inotify` 文件变动都能在单线程主循环里以完全确定的顺序安全处理。
