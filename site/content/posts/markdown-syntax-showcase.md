---
title: "Markdown 语法排版与安全特性演示"
slug: markdown-syntax-showcase
date: 2026-11-22
category: "技术笔记"
tags: markdown, asmblog, guide
summary: "展示 AsmBlog 汇编 Markdown 引擎支持的标题、代码块、引用、有序/无序列表、行内样式以及自动 XSS 过滤能力。"
draft: false
---

## 文本与行内格式

你可以在段落中使用 **粗体强调**、*斜体文字*、行内代码 `mov rax, 60; syscall` 以及标准链接 [回到首页](/)。

为了防止恶意脚本注入，所有原生 HTML 标签（如 `<script>`）都会被自动转义显示为纯文本，且不安全协议链接会被剥离链接地址。

---

## 列表与引用

无序列表：

- 支持 ATX 一至六级标题，并自动生成 `id="h-N"` 锚点
- 支持 UTF-8 中文文章、中文标签与中文关键词搜索
- 支持按 `/` 快捷键随时跳转到站内静态搜索

有序列表：

1. 在 `content/posts/` 下新建 `.md` 文件
2. 编写 `---` 包裹的 Front-Matter 元数据
3. 运行 `asmblog build` 生成 `dist/` 静态目录

> 简洁即可靠：一台 900 MiB 内存的小型云主机，也能在纯汇编静态博客下轻松承载数万级并发读取。

## 代码块示例

```c
// Front-Matter 支持的元数据字段示例:
// title, slug, date, tags, summary, draft
int main(void) {
    return 0;
}
```

### 主题自定义提示

所有页面布局都位于 `themes/default/` 目录下的纯 HTML 文件，样式表位于 `themes/default/static/style.css`，可按个人审美自由调整配色与字体。
