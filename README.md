<p align="center">
  <img src="site/themes/sky-ribbon/static/hero-banner.jpg" alt="AsmBlog Sky Ribbon Anime Theme Banner" width="100%" style="border-radius:16px;" />
</p>

<h1 align="center">✦ AsmBlog — Pure x86-64 Assembly Anime Static Blog</h1>

<p align="center">
  <strong>~74 KiB 纯 x86-64 手写汇编零 <code>libc</code> 博客引擎 × 60/120fps 丝滑二次元「晴空星梦丝带」前端主题</strong><br/>
  <em>A ~74 KiB zero-libc Linux x86-64 assembly static blog engine &amp; SSG paired with a silky anime theme, video streaming, and a hidden Author Studio.</em>
</p>

<p align="center">
  <a href="https://jiehua.13-58-183-35.sslip.io/"><img src="https://img.shields.io/badge/Live%20Demo-%E5%9C%A8%E7%BA%BF%E4%BD%93%E9%AA%8C-ff7eb6?style=flat-square&logo=sparkles&logoColor=white" alt="Live Demo"></a>
  <a href="https://github.com/snlyj/asmblog/actions"><img src="https://img.shields.io/github/actions/workflow/status/snlyj/asmblog/ci.yml?style=flat-square&label=CI%20%26%20Tests" alt="CI Status"></a>
  <a href="https://github.com/snlyj/asmblog/releases"><img src="https://img.shields.io/github/v/release/snlyj/asmblog?style=flat-square&color=5cb8ff" alt="Release"></a>
  <img src="https://img.shields.io/badge/Arch-Linux%20x86__64-5cb8ff?style=flat-square" alt="Linux x86_64">
  <img src="https://img.shields.io/badge/libc-ZERO-ff94c2?style=flat-square" alt="Zero libc">
  <img src="https://img.shields.io/badge/Binary-~69%20KiB-b9a4ff?style=flat-square" alt="Binary Size">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-ffd86b?style=flat-square" alt="MIT License"></a>
</p>

> [!TIP]
> **🌐 在线体验 / Live Demo**：👉 **[https://jiehua.13-58-183-35.sslip.io/](https://jiehua.13-58-183-35.sslip.io/)**
> 实际运行于纯 x86-64 `asmblog`（~74 KiB 单文件）+ Caddy 自动 HTTPS（HTTP/2 & HTTP/3），欢迎直接打开体验零白屏 PJAX 切页、双层 WebP/原图插画灯箱、在线视频流式播放、圆形水波纹昼夜模式、桌面/手机双端 60/120fps 顺滑度与站内极速搜索。

---

## ✨ 项目简介 (Overview)

**AsmBlog** 是一个为个人写作与二次元同好打造的**纯 x86-64 Linux 汇编静态博客框架**——整个服务端、Markdown 解析器、模板引擎、静态站生成器（SSG）、HTTP 206 视频流服务、SHA-256 认证与隐藏写作后台全部由手写 Intel 语法汇编构建，直接调用 Linux `syscall`，**不依赖 `glibc`、不依赖任何第三方库、不需要数据库**。

- **硬核到极致的内核**：静态链接剥离后仅 **~74 KiB**，单线程 `epoll` + 零拷贝 `sendfile`（支持 HTTP `Range` / `206` 视频拖拽播放与 256 KiB 公平分片防阻塞）+ `inotify` 热重载，空闲内存 **`300 KiB`**，20 并发压测 **`2,100–2,400+ req/s`**，文件句柄零泄漏；支持 **`FROM scratch`** 极简 Docker 镜像。
- **软萌到极致的前端**：内置二次元少女风主题 **「晴空星梦丝带 (Sky Ribbon)」**，附带原创晴空插画头图、蝴蝶结头像与 404 萌图，严格杜绝 `backdrop-filter` / `filter: blur` / `100dvh` 滚动卡顿，在手机和桌面端都能保持 60/120fps 顺滑体验。

---

## 🌟 核心特性详览 (Features)

### 🎀 前台二次元体验（`sky-ribbon` 主题）
- **PC 双列画廊网格 + 手机首屏优化**：PC 端自动对齐 `880px` 宽双列等高卡片（文章数为奇数时首页第 1 篇自动横跨两列做精选横排大卡，绝无半格留白），有封面图时自动隐藏斜丝带保证高清二次元插画完整无遮挡；手机端紧致首屏、单行横滑分类胶囊条（带渐隐提示）与纯自然文档流底部护栏。
- **宽屏悬浮目录 + 手机折叠目录**：长文自动从标题生成目录导航——宽屏（`>= 1180px`）右侧固定悬浮并随滚动高亮当前章节，手机端默认收起为轻巧胶囊条，零滚动回流。
- **零硬切丝滑切页（PJAX + 智能预加载 + 动态弱 ETag / 304）**：悬停链接即提前预取 HTML，所有动态页面自动计算 FNV-1a 内容哈希并支持 RFC 9110 弱 ETag / `304 Not Modified`，复访零重复下载。
- **昼夜双模式圆形水波纹切换**：基于 View Transitions API 的扩散切换，暗黑模式自带晴空星夜微光点缀（纯静态 CSS，零帧率损耗）。
- **零依赖高清插画灯箱（轻巧预览 + 点击秒升高清原图 + 双击 2 倍放大）**：日常浏览列表与正文自动加载极轻 WebP 预览图（首屏图片体积直降 ~85%），用户手动点击首页头图、文章封面或正文任意插画进入灯箱后，立即无感加载并切换为完整无损/高清原图（带「⏳ 加载高清原图中 → ✦ 已加载高清原图」提示），支持手机/桌面**双击放大 2x 看细节**、左右滑屏切图与一键打开原图；后台上传图文和裁剪封面/头像时会自动双份生成「WebP 预览图 + 高清原图」并用 `?orig=...` 关联。
- **极速离线感搜索 + 星光年份归档 + 社交分享大卡片**：站内搜索支持关键词糖果高亮与热门标签快捷搜；归档页自动按年份分组；每篇文章自带 Open Graph / Twitter Card 大图元信息（发到 QQ/微信/Discord/Telegram/X 自动呈现二次元封面卡片）、代码块语言徽标、轻小说风插图图注与一键复制链接。
- **可选零入侵评论区（Giscus）**：基于 GitHub Discussions，留空则零脚本加载保持纯粹静态；开启后仅在滚动到文章底部时懒加载，并自动跟随站点昼夜模式切换。
- **精致小彩蛋**：点击首页头像触发软萌弹跳与星心气泡；右下角回到顶部按钮内置 SVG 实时阅读进度环；一键开关点击星光动效（带底部软萌 Toast 提示）。

### ✍️ 隐藏作者写作后台（前后台完全解耦）
前台首页、导航栏、页脚及 `sitemap.xml` **均不暴露、不链接**后台入口，仅博主本人通过隐藏路径访问（默认 `/studio`，可在 `config.ini` 自定义如 `/my-secret-room`）：
- **图文 + 视频 Markdown 写作与实时预览**：支持点击批量插图、**点击插入 MP4/WebM/MOV/OGG 视频**（1 MiB 分片流式上传，最高支持 100 MB、自动截取首帧 WebP 封面并实时显示上传进度）、直接拖拽图片或视频进编辑框、`Ctrl+V` 粘贴截图；前台原生 HTML5 `<video controls playsinline>` 在线流畅播放，底层纯汇编完整支持 **HTTP `Range` / `206 Partial Content` 零拷贝 `sendfile` 拖拽进度条**（iOS / Android / 桌面端全兼容）。
- **交互式自由裁剪框（所见即所得）**：上传文章封面（16:9）、首页头图（16:9）或博主头像（1:1 圆形框）时自动弹出裁剪窗，支持手机**单指拖动 + 双指捏合缩放**与桌面鼠标/滚轮微调，内置「顶部对齐（露头部）」快捷按钮，再也不怕竖版二次元插画裁掉角色头部。
- **分类管理**：自由新增或删除帖子分类（删除正在被使用的分类时自动清理文章对应标签而不删文章）。
- **在线站点外观设置（免重启热生效）**：直接在后台修改站名、副标题、博主昵称、底部护栏文字、每页文章数、更换头像/头图、自定义隐藏后台路径与在线改密，原子写入 `config.ini` 并秒级热重载。

### 🔒 开源级安全加固（全纯汇编实现）
- **密码学认证**：纯 x86-64 实现 FIPS 180-4 SHA-256 与常量时间比较 `ct_memeq`；登录时调用 `sys_getrandom` 生成 **256-bit 随机内存会话令牌**（Cookie 不存储口令哈希），登出立即服务端吊销，改密自动踢出其他设备。
- **自动 `Secure` Cookie & 防爆破限速**：检测到 HTTPS（`X-Forwarded-Proto: https` 或 `https://` 站点地址）自动附加 `HttpOnly; SameSite=Lax; Secure`；连续输错 5 次口令自动触发 60 秒冷却锁定（`429 Too Many Requests` + `Retry-After: 60`）。
- **严格内容与文件安全**：上传图片强制校验二进制文件头魔数（仅放行 JPG / PNG / GIF / WebP）并生成随机文件名；Markdown 渲染器自动转义原生 HTML `<script>` 并拦截 `javascript:` XSS 链接；静态文件访问开启 `O_NOFOLLOW` 并严格拦截 `../` 路径穿越。

---

## 📊 性能与体积实测 (Benchmarks)

实测环境：AWS EC2 `2 vCPU / 908 MiB RAM`（Ubuntu Linux x86_64），Caddy HTTP/2 + HTTP/3 反代至本地 `asmblog`：

| 指标 | AsmBlog（实测值） | 传统动态博客 (PHP/Node/Python) |
| :--- | :--- | :--- |
| 静态可执行文件体积 | **`~74 KiB`**（零动态库依赖） | 30 MB – 200+ MB |
| 服务端内存占用 (`VmRSS`) | 空闲 **`300 KiB`** / 压测后 **`392 KiB`** | 80 MB – 500+ MB |
| 20 并发吞吐量（2,000 请求） | **`2,131 – 2,444 req/s`**（`2000/2000 OK`） | 100 – 800 req/s |
| HTTPS 压缩后首屏代码体积 | HTML **`3.2 KB`** + CSS **`10.1 KB`** + JS **`7.8 KB`** ≈ **`21 KB`** | 300 KB – 2+ MB |
| Docker 运行基础层 | **`FROM scratch`** | `node` / `php-fpm` / `python` |
| 压测后文件描述符泄漏 | **`0`** (`FDs 7 → 7`) | 视运行时而定 |

---

## 🚀 快速部署指南 (Quick Start)

### 方式一：下载预编译单文件直接运行（最省事，无需编译器）

```bash
git clone https://github.com/snlyj/asmblog.git
cd asmblog

# 从 GitHub Releases 下载仅 ~74 KiB 的 Linux x86_64 静态二进制
curl -fsSL -o asmblog https://github.com/snlyj/asmblog/releases/latest/download/asmblog-linux-x86_64
chmod +x asmblog

# （可选）生成作者后台口令哈希并写入 site/config.ini
./asmblog hash-pass "your-strong-password"

# 启动博客服务（默认端口 8080）
./asmblog serve -d site
```

### 方式二：本地从纯汇编源码编译（仅需 GNU `as` + `ld`）

```bash
git clone https://github.com/snlyj/asmblog.git
cd asmblog
bash build.sh --strip
./asmblog serve -d site
```

启动后访问：
- **博客前台**：`http://127.0.0.1:8080/`
- **隐藏作者后台**：`http://127.0.0.1:8080/studio`（未配置 `studio_pass_sha256` 时后台保持锁定只读）

### 方式三：超迷你 `FROM scratch` Docker + Caddy 自动免费 HTTPS

```bash
git clone https://github.com/snlyj/asmblog.git
cd asmblog
cp site/config.ini.example site/config.ini
# 按需修改 site/config.ini 中的站名、域名和 studio_pass_sha256

# 仅启动博客容器（监听本机 8080）：
docker compose up -d

# 一键启动自动 HTTPS（复制 Caddyfile.example -> Caddyfile 并填入你的域名）：
cp Caddyfile.example Caddyfile
docker compose --profile https up -d
```

### 方式四：纯静态生成（SSG）托管到 GitHub Pages / Cloudflare Pages

```bash
./asmblog new my-first-post "我的第一篇二次元笔记" -d site
./asmblog build -d site
# 完整静态站点已输出到 site/dist/（含首页、分页、文章、标签、分类、搜索索引、RSS、Sitemap 与上传图片）
```

---

## 💻 CLI 命令行参考

| 命令 | 说明 |
| :--- | :--- |
| `asmblog serve [-d dir] [-c config.ini] [-p port]` | 启动高性能 `epoll` + `inotify` 博客服务 |
| `asmblog build [-d dir] [-c config.ini] [-o dist]` | 导出完整静态站点到输出目录 |
| `asmblog new <slug> [title] [-d dir]` | 快速创建带 Front-Matter 的新 Markdown 文章 |
| `asmblog init [dir]` | 初始化一个全新空白静态站点骨架 |
| `asmblog hash-pass <password>` | 计算 `studio_pass_sha256` 口令哈希 |
| `asmblog --version \| --help` | 查看版本与帮助信息 |

---

## ⚙️ 配置与文章格式说明

### 1. 站点配置 (`site/config.ini`)

完整模板见 [site/config.ini.example](site/config.ini.example)，所有外观项也可在后台「⚙️ 站点设置」在线修改并热重载：

| 字段 | 说明 | 默认值 / 示例 |
| :--- | :--- | :--- |
| `site_name` | 站点标题 | `SkyRibbon Blog` |
| `subtitle` | 首页副标题 / 个性签名 | `Pure x86-64 Assembly Anime Static Blog ✦` |
| `author` | 博主昵称 | `Sakura` |
| `footer_text` | 底部护栏文字（留空则隐藏） | `Made with ♡ · Powered by Pure x86-64 Assembly` |
| `avatar_url` | 博主头像 URL（后台可 1:1 裁剪上传） | `/static/avatar.jpg?v=2` |
| `banner_url` | 首页头图 URL（后台可 16:9 裁剪上传） | `/static/hero-banner.jpg?v=2` |
| `site_url` | 公网完整网址（用于 RSS / Sitemap） | `https://your-domain.example` |
| `port` | 监听端口（配合 Caddy 反代推荐 `8080`） | `8080` |
| `per_page` | 首页每页文章数 (`1–50`) | `6` |
| `theme` | 主题目录名（位于 `site/themes/` 下） | `sky-ribbon` |
| `studio_path` | 自定义隐藏后台入口路径 | `/studio`（可改为 `/my-secret-room`） |
| `studio_pass_sha256` | 口令 SHA-256（用 `asmblog hash-pass` 生成） | 留空则禁用后台 |
| `giscus_repo` / `giscus_repo_id` / `giscus_category` / `giscus_category_id` | 可选 Giscus 评论配置（支持后台一键粘贴代码自动识别） | 留空则关闭评论区（零外部请求） |

### 2. 文章 Markdown Front-Matter (`site/content/posts/<slug>.md`)

```markdown
---
title: "晴空下的二次元随笔"
slug: sunny-anime-note
date: 2026-11-24
category: "日常随笔"
tags: 二次元, 插画, 随笔
cover: "/uploads/your-cover.jpg"
summary: "记录今天喜欢的插画与心情。"
draft: false
---

## 正文标题

支持 **粗体**、*斜体*、`行内代码`、代码块、引用、列表以及图文插图：

![插画示例](/uploads/your-image.jpg)
```

---

## 🧩 纯汇编模块架构 (`src/`)

项目由 16 个结构清晰的 x86-64 Intel 语法汇编模块构成，零 C 文件、零外部库依赖：

| 模块 | 职责 |
| :--- | :--- |
| `main.s` / `cli.s` | 裸 `_start` 入口、命令行参数解析、`serve` / `build` / `new` / `init` / `hash-pass` |
| `syscall.s` | Linux x86-64 系统调用薄封装与原子文件替换 (`write_file_atomic`) |
| `mem.s` | 16 MiB `mmap` Bump Arena 分配器、有界缓冲区 `sbuf_t`、HTML/JSON/URL 编解码 |
| `config.s` | `config.ini` 解析与 URL / 路径安全校验 |
| `markdown.s` | Front-Matter 解析与流式 Markdown→HTML 渲染器（自动 XSS 清洗 + HTML5 `<video>` 视频渲染） |
| `template.s` | 轻量 Mustache 风格模板引擎（变量转义、原样输出、条件块、循环与 Partial） |
| `store.s` | 内存文章 / 标签 / 分类 / 模板索引与 `inotify` 无停机热重载 |
| `http.s` | HTTP/1.1 增量解析、RFC 8259 JSON 解码（含 `\uXXXX` 代理对）、RFC 9110 弱 ETag、`Range` & Cookie |
| `router.s` | 声明式路由表与动态 `studio_path` 匹配 |
| `handlers.s` | 首页、分页、文章、归档、标签、分类、搜索索引、RSS、Sitemap、OG 大卡片与动态弱 ETag/304 |
| `static.s` | `/static/*` 与 `/uploads/*` 零拷贝 `sendfile`、HTTP `Range`/`206` 视频流式传输、强 `ETag`/`304` 与隐藏文件拦截 |
| `sha256.s` | 纯 x86-64 FIPS 180-4 SHA-256 与常量时间内存比较 `ct_memeq` |
| `studio.s` | 隐藏作者后台：随机 256-bit 会话表、429 防爆破、文章/分类/外观/Giscus CRUD、魔数图片与 100MB 分片视频上传 |
| `net_epoll.s` | 非阻塞单线程 `epoll` 事件循环、`TCP_NODELAY`、256 KiB 公平 `sendfile` 分片流式发送、优雅 `SIGTERM` 退出 |

---

## 🧪 运行全量自动化测试

```bash
bash build.sh --strip
python3 tests/test_all.py
```

测试套件完整覆盖：零 `libc` ELF 验证、CLI 命令与 `hash-pass`、SSG 导出、HTTP 协议与 10x Pipeline、`ETag`/`304`、路径穿越 `403`、前端零卡顿 CSS 规则检查、`inotify` 热重载、Markdown XSS 拦截、后台随机 Token / 伪造哈希拦截 / 登出吊销 / 429 防爆破 / 自定义路径 / 外观热修改 / 图片魔数上传与文章分类 CRUD、2,000 并发压测及内存/FD 零泄漏检查。

---

## 📄 开源协议与素材版权 (License)

- 本项目全部源码以及内置原创二次元主题插画（`hero-banner.jpg`、`avatar.jpg`、`notfound.jpg`、`favicon-ribbon.svg`）均基于 **MIT License** 开源，可自由个人使用、二次开发与自托管，详见 [LICENSE](LICENSE)。
