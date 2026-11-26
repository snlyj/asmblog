.include "defs.inc"

# AsmBlog Single-Author Static Blog CLI
# Commands:
#   asmblog build [-d dir] [-c config.ini] [-o dist]
#   asmblog serve [-d dir] [-c config.ini] [-p port]
#   asmblog new <slug> [title] [-d dir]
#   asmblog init [dir]
#   asmblog --version | --help

.section .bss
.align 8
cli_path1:      .skip 1024
cli_path2:      .skip 1024
cli_copy_buf:   .skip 65536
cli_dirent_buf: .skip 16384
cli_out_buf:    .skip 4096
cli_date_buf:   .skip 16
cli_opt_cfg:    .quad 0
cli_opt_dir:    .quad 0
cli_opt_out:    .quad 0
cli_opt_port:   .quad 0

.section .rodata
str_version:
    .asciz "AsmBlog 1.0.0 (pure x86-64 Linux assembly static blog framework)\n"

str_help:
    .ascii "AsmBlog 1.0.0 - Pure x86-64 Linux Assembly Static Blog Framework\n\n"
    .ascii "Usage:\n"
    .ascii "  asmblog build [-d dir] [-c config.ini] [-o dist]   Generate complete static site\n"
    .ascii "  asmblog serve [-d dir] [-c config.ini] [-p port]   Serve static blog (epoll + inotify)\n"
    .ascii "  asmblog new <slug> [title] [-d dir]                Create a new Markdown post\n"
    .ascii "  asmblog init [dir]                                 Scaffold a new static blog site\n"
    .ascii "  asmblog hash-pass <password>                       Generate studio_pass_sha256 for config.ini\n"
    .ascii "  asmblog --version | --help                         Show version or help\n"
    .byte 0

cmd_serve:      .ascii "serve"
cmd_build:      .ascii "build"
cmd_new:        .ascii "new"
cmd_init:       .ascii "init"
cmd_hashpass:   .ascii "hash-pass"
err_hp_usage:   .asciz "Usage: asmblog hash-pass <password>\n"
hp_prefix:      .ascii "studio_pass_sha256 = "
.equ hp_prefix_len, . - hp_prefix
flg_help1:      .ascii "--help"
flg_help2:      .ascii "-h"
flg_ver1:       .ascii "--version"
flg_ver2:       .ascii "-v"
flg_c:          .ascii "-c"
flg_d:          .ascii "-d"
flg_o:          .ascii "-o"
flg_p:          .ascii "-p"

def_cfg_path:   .asciz "config.ini"
err_arena:      .asciz "[asmblog] ERROR: arena mmap failed\n"
err_chdir:      .asciz "[asmblog] ERROR: cannot enter directory\n"
err_bad_slug:   .asciz "[asmblog] ERROR: invalid slug (use a-z, A-Z, 0-9, -, _)\n"
err_new_usage:  .asciz "Usage: asmblog new <slug> [title] [-d dir]\n"
err_bad_cmd:    .asciz "[asmblog] Unknown command. Run `asmblog --help` for usage.\n"
err_write:      .asciz "[asmblog] ERROR: failed to write output file\n"

msg_built_1:    .ascii "[asmblog] built static site -> "
.equ msg_built_1_len, . - msg_built_1
msg_built_2:    .ascii "/ ("
.equ msg_built_2_len, . - msg_built_2
msg_built_3:    .ascii " posts, "
.equ msg_built_3_len, . - msg_built_3
msg_built_4:    .ascii " tags, "
.equ msg_built_4_len, . - msg_built_4
msg_built_5:    .ascii " pages)\n"
.equ msg_built_5_len, . - msg_built_5

msg_new_ok1:    .ascii "[asmblog] created "
.equ msg_new_ok1_len, . - msg_new_ok1
msg_init_ok:    .asciz "[asmblog] initialized static blog site (run `asmblog build` or `asmblog serve`)\n"

# Path fragments for SSG build
p_index_html:   .ascii "/index.html"
.equ p_index_html_len, . - p_index_html
p_post_dir:     .ascii "/post"
.equ p_post_dir_len, . - p_post_dir
p_page_dir:     .ascii "/page"
.equ p_page_dir_len, . - p_page_dir
p_arch_dir:     .ascii "/archive"
.equ p_arch_dir_len, . - p_arch_dir
p_tags_dir:     .ascii "/tags"
.equ p_tags_dir_len, . - p_tags_dir
p_tag_dir:      .ascii "/tag"
.equ p_tag_dir_len, . - p_tag_dir
p_cat_dir:      .ascii "/category"
.equ p_cat_dir_len, . - p_cat_dir
p_search_dir:   .ascii "/search"
.equ p_search_dir_len, . - p_search_dir
p_gallery_dir:  .ascii "/gallery"
.equ p_gallery_dir_len, . - p_gallery_dir
p_about_dir:    .ascii "/about"
.equ p_about_dir_len, . - p_about_dir
p_static_dir:   .ascii "/static"
.equ p_static_dir_len, . - p_static_dir
p_uploads_dir:  .ascii "/uploads"
.equ p_uploads_dir_len, . - p_uploads_dir
p_cnt_uploads:  .ascii "content/uploads"
.equ p_cnt_uploads_len, . - p_cnt_uploads
p_search_json:  .ascii "/search-index.json"
.equ p_search_json_len, . - p_search_json
p_gal_json:     .ascii "/gallery.json"
.equ p_gal_json_len, . - p_gal_json
p_abt_json:     .ascii "/about.json"
.equ p_abt_json_len, . - p_abt_json
p_bgm_json:     .ascii "/bgm.json"
.equ p_bgm_json_len, . - p_bgm_json
src_gal_json:   .asciz "content/gallery.json"
src_abt_json:   .asciz "content/about.json"
src_bgm_json:   .asciz "content/bgm.json"
def_empty_arr:  .ascii "[]"
def_empty_obj:  .ascii "{}"
p_rss_xml:      .ascii "/rss.xml"
.equ p_rss_xml_len, . - p_rss_xml
p_sitemap_xml:  .ascii "/sitemap.xml"
.equ p_sitemap_xml_len, . - p_sitemap_xml
p_404_html:     .ascii "/404.html"
.equ p_404_html_len, . - p_404_html
p_favicon_ico:  .ascii "/favicon.ico"
.equ p_favicon_ico_len, . - p_favicon_ico
p_th_pre:       .ascii "themes/"
.equ p_th_pre_len, . - p_th_pre
p_th_st:        .ascii "/static"
.equ p_th_st_len, . - p_th_st
p_cp_pre:       .ascii "content/posts/"
.equ p_cp_pre_len, . - p_cp_pre
p_md_ext:       .ascii ".md"
.equ p_md_ext_len, . - p_md_ext

# New post Front-Matter template
np_1: .ascii "---\ntitle: \""
.equ np_1_len, . - np_1
np_2: .ascii "\"\nslug: "
.equ np_2_len, . - np_2
np_3: .ascii "\ndate: "
.equ np_3_len, . - np_3
np_4: .ascii "\ntags: notes\nsummary: \"\"\ndraft: false\n---\n\n# "
.equ np_4_len, . - np_4
np_5: .ascii "\n\nStart writing your post here...\n"
.equ np_5_len, . - np_5

# Scaffold directories & starter files for `asmblog init`
d_content:      .asciz "content"
d_posts:        .asciz "content/posts"
d_themes:       .asciz "themes"
d_th_def:       .asciz "themes/default"
d_th_st:        .asciz "themes/default/static"

f_cfg:          .asciz "config.ini"
f_hello:        .asciz "content/posts/hello-world.md"
f_t_layout:     .asciz "themes/default/layout.html"
f_t_index:      .asciz "themes/default/index.html"
f_t_post:       .asciz "themes/default/post.html"
f_t_archive:    .asciz "themes/default/archive.html"
f_t_tags:       .asciz "themes/default/tags.html"
f_t_tag:        .asciz "themes/default/tag.html"
f_t_search:     .asciz "themes/default/search.html"
f_t_404:        .asciz "themes/default/404.html"
f_s_css:        .asciz "themes/default/static/style.css"
f_s_js:         .asciz "themes/default/static/app.js"

init_cfg:
    .ascii "site_name = My AsmBlog\n"
    .ascii "subtitle = Personal Static Blog Built in Pure x86-64 Assembly\n"
    .ascii "site_url = http://localhost:8080\n"
    .ascii "author = Me\n"
    .ascii "port = 8080\n"
    .ascii "per_page = 6\n"
    .ascii "theme = default\n"
    .ascii "dist_dir = dist\n"
.equ init_cfg_len, . - init_cfg

init_hello:
    .ascii "---\n"
    .ascii "title: \"Hello, AsmBlog!\"\n"
    .ascii "slug: hello-world\n"
    .ascii "date: 2026-11-24\n"
    .ascii "tags: asm, blog\n"
    .ascii "summary: \"First static post generated by pure x86-64 Linux assembly.\"\n"
    .ascii "draft: false\n"
    .ascii "---\n\n"
    .ascii "## Welcome\n\n"
    .ascii "This personal static blog is built and served in **pure x86-64 assembly** with zero libc.\n\n"
    .ascii "```bash\n"
    .ascii "asmblog new my-post \"My Second Post\"\n"
    .ascii "asmblog build\n"
    .ascii "```\n"
.equ init_hello_len, . - init_hello

init_layout:
    .ascii "<!doctype html><html lang=\"zh-CN\"><head><meta charset=\"utf-8\">"
    .ascii "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
    .ascii "<title>{{ page_title }} - {{ site_name }}</title>"
    .ascii "<link rel=\"icon\" href=\"/favicon.ico\"><link rel=\"stylesheet\" href=\"/static/style.css\">"
    .ascii "<link rel=\"alternate\" type=\"application/rss+xml\" title=\"{{ site_name }}\" href=\"/rss.xml\">"
    .ascii "</head><body><header class=\"top\"><div class=\"wrap nav\">"
    .ascii "<a class=\"brand\" href=\"/\">{{ site_name }}</a>"
    .ascii "<nav><a href=\"/\">Home</a><a href=\"/archive/\">Archive</a><a href=\"/tags/\">Tags</a>"
    .ascii "<a href=\"/search/\">Search</a><a href=\"/rss.xml\">RSS</a>"
    .ascii "<button id=\"theme-btn\" type=\"button\">Theme</button></nav></div></header>"
    .ascii "<main class=\"wrap\">{{{ body }}}</main>"
    .ascii "<footer class=\"wrap foot\"><p>{{ author }} &middot; Powered by AsmBlog (x86-64 Assembly)</p></footer>"
    .ascii "<script src=\"/static/app.js\" defer></script></body></html>\n"
.equ init_layout_len, . - init_layout

init_index:
    .ascii "<section class=\"hero\"><h1>{{ site_name }}</h1><p>{{ site_subtitle }}</p></section>"
    .ascii "<div class=\"list\">{{#posts}}<article class=\"card\">"
    .ascii "<h2><a href=\"/post/{{ slug }}/\">{{ title }}</a></h2>"
    .ascii "<div class=\"meta\">{{ date }} &middot; {{ read_min }} min {{{ tags_html }}}</div>"
    .ascii "<p>{{ summary }}</p></article>{{/posts}}{{^posts}}<p>No posts yet.</p>{{/posts}}</div>"
    .ascii "<div class=\"pager\">{{#prev_page_url}}<a href=\"{{ prev_page_url }}\">&larr; Newer</a>{{/prev_page_url}}"
    .ascii "<span>Page {{ page_num }} / {{ total_pages }}</span>"
    .ascii "{{#next_page_url}}<a href=\"{{ next_page_url }}\">Older &rarr;</a>{{/next_page_url}}</div>\n"
.equ init_index_len, . - init_index

init_post:
    .ascii "<article class=\"post\"><h1>{{ title }}</h1>"
    .ascii "<div class=\"meta\">{{ date }} &middot; {{ read_min }} min {{{ tags_html }}}</div>"
    .ascii "<div class=\"prose\">{{{ content_html }}}</div></article>"
    .ascii "<div class=\"pager\">{{#prev_slug}}<a href=\"/post/{{ prev_slug }}/\">&larr; {{ prev_title }}</a>{{/prev_slug}}"
    .ascii "{{#next_slug}}<a href=\"/post/{{ next_slug }}/\">{{ next_title }} &rarr;</a>{{/next_slug}}</div>\n"
.equ init_post_len, . - init_post

init_archive:
    .ascii "<h1>Archive ({{ post_count }})</h1><ul class=\"arch\">"
    .ascii "{{#posts}}<li><time>{{ date }}</time> <a href=\"/post/{{ slug }}/\">{{ title }}</a></li>{{/posts}}</ul>\n"
.equ init_archive_len, . - init_archive

init_tags:
    .ascii "<h1>Tags ({{ tag_count }})</h1><div class=\"tag-cloud\">"
    .ascii "{{#tags}}<a class=\"tag-chip\" href=\"/tag/{{ name }}/\">#{{ name }} ({{ count }})</a>{{/tags}}</div>\n"
.equ init_tags_len, . - init_tags

init_tag:
    .ascii "<h1>#{{ active_tag }}</h1><div class=\"list\">"
    .ascii "{{#posts}}<article class=\"card\"><h2><a href=\"/post/{{ slug }}/\">{{ title }}</a></h2>"
    .ascii "<div class=\"meta\">{{ date }}</div><p>{{ summary }}</p></article>{{/posts}}</div>\n"
.equ init_tag_len, . - init_tag

init_search:
    .ascii "<h1>Search</h1><form action=\"/search/\" method=\"get\" class=\"search-form\">"
    .ascii "<input id=\"search-input\" type=\"search\" name=\"q\" value=\"{{ query }}\" placeholder=\"Search posts...\" autofocus>"
    .ascii "</form><div id=\"search-results\" class=\"list\">"
    .ascii "{{#posts}}<article class=\"card\"><h2><a href=\"/post/{{ slug }}/\">{{ title }}</a></h2>"
    .ascii "<div class=\"meta\">{{ date }}</div><p>{{ summary }}</p></article>{{/posts}}</div>\n"
.equ init_search_len, . - init_search

init_404:
    .ascii "<h1>404 Not Found</h1><p>Page not found. <a href=\"/\">Back Home</a></p>\n"
.equ init_404_len, . - init_404

init_css:
    .ascii ":root{--bg:#f8fafc;--fg:#0f172a;--muted:#64748b;--card:#fff;--bd:#e2e8f0;--acc:#0284c7}"
    .ascii "[data-theme=dark]{--bg:#0b1120;--fg:#e2e8f0;--muted:#94a3b8;--card:#111827;--bd:#1e293b;--acc:#38bdf8}"
    .ascii "body{margin:0;font:16px/1.7 system-ui,-apple-system,sans-serif;background:var(--bg);color:var(--fg)}"
    .ascii ".wrap{max-width:780px;margin:0 auto;padding:0 20px}a{color:var(--acc);text-decoration:none}"
    .ascii ".top{border-bottom:1px solid var(--bd);background:var(--card)}.nav{display:flex;justify-content:space-between;align-items:center;height:60px}"
    .ascii ".nav nav{display:flex;gap:14px;align-items:center}.brand{font-weight:700;color:var(--fg)}"
    .ascii ".card{background:var(--card);border:1px solid var(--bd);border-radius:10px;padding:18px;margin:16px 0}"
    .ascii ".meta{color:var(--muted);font-size:14px}.tag-chip{display:inline-block;padding:2px 8px;border:1px solid var(--bd);border-radius:99px;margin:2px;font-size:13px}"
    .ascii "pre{background:#0f172a;color:#e2e8f0;padding:14px;border-radius:8px;overflow:auto}code{font-family:monospace}"
    .ascii ".pager{display:flex;justify-content:space-between;margin:28px 0}.foot{margin:40px auto;color:var(--muted);font-size:14px;text-align:center}\n"
.equ init_css_len, . - init_css

init_js:
    .ascii "(function(){var b=document.getElementById('theme-btn'),r=document.documentElement;"
    .ascii "var t=localStorage.getItem('theme')||'light';r.setAttribute('data-theme',t);"
    .ascii "if(b)b.onclick=function(){t=t==='dark'?'light':'dark';r.setAttribute('data-theme',t);localStorage.setItem('theme',t)};"
    .ascii "var inp=document.getElementById('search-input'),res=document.getElementById('search-results');"
    .ascii "if(inp&&res){var idx=null;inp.oninput=function(){var q=inp.value.trim().toLowerCase();"
    .ascii "if(!q){res.innerHTML='';return;}var run=function(d){res.innerHTML=d.filter(function(p){"
    .ascii "return (p.title+' '+p.summary+' '+p.tags).toLowerCase().indexOf(q)>=0;}).map(function(p){"
    .ascii "return '<article class=\"card\"><h2><a href=\"/post/'+p.slug+'/\">'+p.title+'</a></h2><div class=\"meta\">'+p.date+'</div><p>'+p.summary+'</p></article>';}).join('')||'<p>No results.</p>';};"
    .ascii "if(idx)run(idx);else fetch('/search-index.json').then(function(x){return x.json()}).then(function(d){idx=d;run(d);});};}})();\n"
.equ init_js_len, . - init_js

.section .text

# cstr_eq(rdi=cstr, rsi=lit_ptr, rdx=lit_len) -> rax=1 eq, 0 no
cstr_eq:
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    call xstrlen
    mov rdi, r12
    mov rsi, rax
    mov rdx, r13
    mov rcx, r14
    call xslice_eq
    pop r14
    pop r13
    pop r12
    ret

# ensure_dir(rdi=cstr_path) -> ignores EEXIST
ensure_dir:
    mov esi, 0755
    jmp sys_mkdir

# write_file_direct(rdi=cstr_path, rsi=data_ptr, rdx=data_len) -> rax=0 ok, <0 err
write_file_direct:
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov r13, rdx
    mov rsi, rdi
    mov rdi, AT_FDCWD
    mov edx, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC
    mov ecx, 0644
    call sys_openat
    test rax, rax
    js .Lwfd_ret
    mov rbx, rax
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call write_all
    push rax
    mov rdi, rbx
    call sys_close
    pop rax
.Lwfd_ret:
    pop r13
    pop r12
    pop rbx
    ret

# copy_file_stream(rdi=src_cstr, rsi=dst_cstr) -> rax=0 ok, <0 err
copy_file_stream:
    push rbx
    push r12
    push r13
    mov r13, rsi          # dst path

    mov rsi, rdi
    mov rdi, AT_FDCWD
    mov edx, O_RDONLY | O_NOFOLLOW | O_CLOEXEC
    xor ecx, ecx
    call sys_openat
    test rax, rax
    js .Lcfs_ret
    mov rbx, rax          # in_fd

    mov rdi, AT_FDCWD
    mov rsi, r13
    mov edx, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC
    mov ecx, 0644
    call sys_openat
    test rax, rax
    js .Lcfs_close_in
    mov r12, rax          # out_fd

.Lcfs_loop:
    mov rdi, rbx
    lea rsi, [rip + cli_copy_buf]
    mov edx, 65536
    call sys_read
    cmp rax, -EINTR
    je .Lcfs_loop
    test rax, rax
    js .Lcfs_err
    jz .Lcfs_ok
    mov rdi, r12
    lea rsi, [rip + cli_copy_buf]
    mov rdx, rax
    call write_all
    test rax, rax
    js .Lcfs_err
    jmp .Lcfs_loop

.Lcfs_ok:
    xor eax, eax
.Lcfs_err:
    push rax
    mov rdi, r12
    call sys_close
    pop rax
.Lcfs_close_in:
    push rax
    mov rdi, rbx
    call sys_close
    pop rax
.Lcfs_ret:
    pop r13
    pop r12
    pop rbx
    ret

# copy_dir_files_impl(rdi=src_dir_ptr, rsi=src_dir_len, rdx=dst_dir_ptr, rcx=dst_dir_len)
# Copies all regular non-dot files from <src_dir>/* into <dst_dir>/*
copy_dir_files_impl:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 224
    mov r12, rdi          # src_dir_ptr
    mov r13, rsi          # src_dir_len
    mov r14, rdx          # dst_dir_ptr
    mov r15, rcx          # dst_dir_len

    # Build src dir in cli_path1
    lea rdi, [rsp + 0]; lea rsi, [rip + cli_path1]; mov edx, 1023; call sb_init
    lea rdi, [rsp + 0]; mov rsi, r12; mov rdx, r13; call sb_mem
    mov rax, [rsp + 0 + SB_LEN]
    mov [rsp + 56], rax
    lea rdi, [rsp + 0]; xor esi, esi; call sb_byte

    # Build dst dir in cli_path2
    lea rdi, [rsp + 24]; lea rsi, [rip + cli_path2]; mov edx, 1023; call sb_init
    lea rdi, [rsp + 24]; mov rsi, r14; mov rdx, r15; call sb_mem
    mov rax, [rsp + 24 + SB_LEN]
    mov [rsp + 64], rax

    mov rdi, AT_FDCWD
    lea rsi, [rip + cli_path1]
    mov edx, O_RDONLY | O_DIRECTORY | O_CLOEXEC
    xor ecx, ecx
    call sys_openat
    test rax, rax
    js .Lcsdi_done
    mov [rsp + 48], rax

.Lcsdi_dents:
    mov rdi, [rsp + 48]
    lea rsi, [rip + cli_dirent_buf]
    mov edx, 16384
    call sys_getdents64
    test rax, rax
    jle .Lcsdi_close
    mov r12, rax
    xor r13, r13
.Lcsdi_ent:
    cmp r13, r12
    jae .Lcsdi_dents
    lea r14, [rip + cli_dirent_buf]
    add r14, r13
    movzx ebx, word ptr [r14 + 16]
    add r13, rbx
    lea r15, [r14 + 19]   # d_name
    cmp byte ptr [r15], '.'
    je .Lcsdi_ent         # skip ., .., dotfiles
    mov rdi, r15
    call xstrlen
    mov rbx, rax          # name_len

    # src = <src_dir>/<name>\0
    mov rax, [rsp + 56]
    mov [rsp + 0 + SB_LEN], rax
    lea rdi, [rsp + 0]; mov esi, '/'; call sb_byte
    lea rdi, [rsp + 0]; mov rsi, r15; mov rdx, rbx; call sb_mem
    lea rdi, [rsp + 0]; xor esi, esi; call sb_byte

    # check regular file via stat
    lea rdi, [rip + cli_path1]
    lea rsi, [rsp + 72]
    call sys_stat
    test rax, rax
    js .Lcsdi_ent
    mov eax, [rsp + 72 + STAT_MODE]
    and eax, S_IFMT
    cmp eax, S_IFREG
    jne .Lcsdi_ent

    # dst = <dst_dir>/<name>\0
    mov rax, [rsp + 64]
    mov [rsp + 24 + SB_LEN], rax
    lea rdi, [rsp + 24]; mov esi, '/'; call sb_byte
    lea rdi, [rsp + 24]; mov rsi, r15; mov rdx, rbx; call sb_mem
    lea rdi, [rsp + 24]; xor esi, esi; call sb_byte

    lea rdi, [rip + cli_path1]
    lea rsi, [rip + cli_path2]
    call copy_file_stream
    jmp .Lcsdi_ent

.Lcsdi_close:
    mov rdi, [rsp + 48]
    call sys_close
.Lcsdi_done:
    add rsp, 224
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

# copy_static_dir_impl(rdi=dst_base_ptr, rsi=dst_base_len)
copy_static_dir_impl:
    push r12
    push r13
    sub rsp, 56           # [rsp+0..23]=sb1, [rsp+24..47]=sb2 (2 pushes+ret=24, +56=80)
    mov r12, rdi
    mov r13, rsi

    # Build src: themes/<theme>/static into cli_out_buf[0..511]
    lea rdi, [rsp + 0]; lea rsi, [rip + cli_out_buf]; mov edx, 511; call sb_init
    lea rdi, [rsp + 0]; lea rsi, [rip + p_th_pre]; mov edx, p_th_pre_len; call sb_mem
    lea rdi, [rsp + 0]; lea rsi, [rip + g_cfg_theme]; mov rdx, [rip + g_cfg_theme_len]; call sb_mem
    lea rdi, [rsp + 0]; lea rsi, [rip + p_th_st]; mov edx, p_th_st_len; call sb_mem

    # Build dst: <dst_base>/static into cli_out_buf[512..1023]
    lea rdi, [rsp + 24]; lea rsi, [rip + cli_out_buf + 512]; mov edx, 511; call sb_init
    lea rdi, [rsp + 24]; mov rsi, r12; mov rdx, r13; call sb_mem
    lea rdi, [rsp + 24]; lea rsi, [rip + p_static_dir]; mov edx, p_static_dir_len; call sb_mem

    lea rdi, [rip + cli_out_buf]
    mov rsi, [rsp + 0 + SB_LEN]
    lea rdx, [rip + cli_out_buf + 512]
    mov rcx, [rsp + 24 + SB_LEN]
    call copy_dir_files_impl

    add rsp, 56
    pop r13
    pop r12
    ret

# copy_uploads_dir_impl(rdi=dst_base_ptr, rsi=dst_base_len)
copy_uploads_dir_impl:
    push r12
    push r13
    sub rsp, 40
    mov r12, rdi
    mov r13, rsi

    lea rdi, [rsp + 0]; lea rsi, [rip + cli_out_buf + 512]; mov edx, 511; call sb_init
    lea rdi, [rsp + 0]; mov rsi, r12; mov rdx, r13; call sb_mem
    lea rdi, [rsp + 0]; lea rsi, [rip + p_uploads_dir]; mov edx, p_uploads_dir_len; call sb_mem

    lea rdi, [rip + p_cnt_uploads]
    mov esi, p_cnt_uploads_len
    lea rdx, [rip + cli_out_buf + 512]
    mov rcx, [rsp + 0 + SB_LEN]
    call copy_dir_files_impl

    add rsp, 40
    pop r13
    pop r12
    ret

# build_mkdir_sub(rdi=out_ptr, rsi=out_len, rdx=suf_ptr, rcx=suf_len) -> creates "<out><suf>"
build_mkdir_sub:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov rdi, rsp; lea rsi, [rip + cli_path1]; mov edx, 1023; call sb_init
    mov rdi, rsp; mov rsi, rbx; mov rdx, r12; call sb_mem
    mov rdi, rsp; mov rsi, r13; mov rdx, r14; call sb_mem
    mov rdi, rsp; xor esi, esi; call sb_byte
    lea rdi, [rip + cli_path1]
    call ensure_dir
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# build_write_sub(rdi=out_ptr, rsi=out_len, rdx=suf_ptr, rcx=suf_len, r8=data_ptr, r9=data_len)
build_write_sub:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40           # [rsp+0..23]=sbuf, [rsp+24]=data_ptr, [rsp+32]=data_len
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov [rsp + 24], r8
    mov [rsp + 32], r9
    mov rdi, rsp; lea rsi, [rip + cli_path1]; mov edx, 1023; call sb_init
    mov rdi, rsp; mov rsi, rbx; mov rdx, r12; call sb_mem
    mov rdi, rsp; mov rsi, r13; mov rdx, r14; call sb_mem
    mov rdi, rsp; xor esi, esi; call sb_byte
    lea rdi, [rip + cli_path1]
    mov rsi, [rsp + 24]
    mov rdx, [rsp + 32]
    call write_file_direct
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# parse_common_opts(rdi=argc, rsi=argv, rdx=start_idx)
# Scans flags -c <cfg>, -d <dir>, -o <out>, -p <port>
parse_common_opts:
    push rbx
    push r12
    push r13
    mov r12, rdi          # argc
    mov r13, rsi          # argv
    mov rbx, rdx          # i
.Lpco_loop:
    cmp rbx, r12
    jae .Lpco_done
    mov rdi, [r13 + rbx*8]

    # -c
    lea rsi, [rip + flg_c]; mov edx, 2; call cstr_eq
    test eax, eax
    jz .Lpco_d
    lea rax, [rbx + 1]
    cmp rax, r12
    jae .Lpco_next
    inc rbx
    mov rax, [r13 + rbx*8]
    mov [rip + cli_opt_cfg], rax
    jmp .Lpco_next

.Lpco_d:
    mov rdi, [r13 + rbx*8]
    lea rsi, [rip + flg_d]; mov edx, 2; call cstr_eq
    test eax, eax
    jz .Lpco_o
    lea rax, [rbx + 1]
    cmp rax, r12
    jae .Lpco_next
    inc rbx
    mov rax, [r13 + rbx*8]
    mov [rip + cli_opt_dir], rax
    jmp .Lpco_next

.Lpco_o:
    mov rdi, [r13 + rbx*8]
    lea rsi, [rip + flg_o]; mov edx, 2; call cstr_eq
    test eax, eax
    jz .Lpco_p
    lea rax, [rbx + 1]
    cmp rax, r12
    jae .Lpco_next
    inc rbx
    mov rax, [r13 + rbx*8]
    mov [rip + cli_opt_out], rax
    jmp .Lpco_next

.Lpco_p:
    mov rdi, [r13 + rbx*8]
    lea rsi, [rip + flg_p]; mov edx, 2; call cstr_eq
    test eax, eax
    jz .Lpco_next
    lea rax, [rbx + 1]
    cmp rax, r12
    jae .Lpco_next
    inc rbx
    mov rdi, [r13 + rbx*8]
    push rdi
    call xstrlen
    pop rdi
    mov rsi, rax
    call parse_uint
    test edx, edx
    jz .Lpco_next
    cmp rax, 1
    jb .Lpco_next
    cmp rax, 65535
    ja .Lpco_next
    mov [rip + cli_opt_port], rax

.Lpco_next:
    inc rbx
    jmp .Lpco_loop
.Lpco_done:
    pop r13
    pop r12
    pop rbx
    ret

# build_copy_or_def(rdi=out_ptr, rsi=out_len, rdx=sub_ptr, rcx=sub_len, r8=src_cstr, r9=def_ptr)
build_copy_or_def:
    push r12
    push r13
    sub rsp, 40           # 2 pushes + ret = 24, +40 = 64 (16B aligned)
    mov r12, r8
    mov r13, r9
    push rcx
    push rdx
    push rsi
    push rdi
    lea rdi, [rsp + 32]; lea rsi, [rip + cli_path1]; mov edx, 1023; call sb_init
    pop rsi; pop rdx
    lea rdi, [rsp + 16]; call sb_mem
    pop rsi; pop rdx
    mov rdi, rsp; call sb_mem
    mov rdi, rsp; xor esi, esi; call sb_byte
    mov rdi, r12
    lea rsi, [rip + cli_path1]
    call copy_file_stream
    test rax, rax
    jns .Lbcod_ret
    lea rdi, [rip + cli_path1]
    mov rsi, r13
    mov edx, 2
    call write_file_direct
.Lbcod_ret:
    add rsp, 40
    pop r13
    pop r12
    ret

# do_cmd_serve() -> rax=exit code
do_cmd_serve:
    mov rdi, [rip + cli_opt_dir]
    test rdi, rdi
    jz .Lsv_arena
    call sys_chdir
    test rax, rax
    jns .Lsv_arena
    lea rdi, [rip + err_chdir]; call log_cstr
    mov eax, 1
    ret
.Lsv_arena:
    mov rdi, ARENA_SIZE
    call arena_init
    test rax, rax
    jns .Lsv_cfg
    lea rdi, [rip + err_arena]; call log_cstr
    mov eax, 1
    ret
.Lsv_cfg:
    mov rdi, [rip + cli_opt_cfg]
    test rdi, rdi
    jnz .Lsv_load_cfg
    lea rdi, [rip + def_cfg_path]
.Lsv_load_cfg:
    call config_load
    mov rax, [rip + cli_opt_port]
    test rax, rax
    jz .Lsv_run
    mov [rip + g_cfg_port], rax
.Lsv_run:
    call store_reload
    jmp server_run

# do_cmd_build() -> Static Site Generator (SSG), writes complete site to dist/
do_cmd_build:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40           # [rsp+0..23]=sbuf, [rsp+24]=total_pages

    mov rdi, [rip + cli_opt_dir]
    test rdi, rdi
    jz .Lbd_arena
    call sys_chdir
    test rax, rax
    jns .Lbd_arena
    lea rdi, [rip + err_chdir]; call log_cstr
    mov eax, 1
    jmp .Lbd_ret

.Lbd_arena:
    mov rdi, ARENA_SIZE
    call arena_init
    test rax, rax
    jns .Lbd_cfg
    lea rdi, [rip + err_arena]; call log_cstr
    mov eax, 1
    jmp .Lbd_ret

.Lbd_cfg:
    mov rdi, [rip + cli_opt_cfg]
    test rdi, rdi
    jnz .Lbd_lcfg
    lea rdi, [rip + def_cfg_path]
.Lbd_lcfg:
    call config_load
    call store_reload

    # Determine output directory: -o or g_cfg_dist_dir
    mov r12, [rip + cli_opt_out]
    test r12, r12
    jnz .Lbd_out_custom
    lea r12, [rip + g_cfg_dist_dir]
    mov r13, [rip + g_cfg_dist_dir_len]
    jmp .Lbd_mk_dirs
.Lbd_out_custom:
    mov rdi, r12
    call xstrlen
    mov r13, rax

.Lbd_mk_dirs:
    # Create root and standard subdirs
    mov rdi, r12; call ensure_dir
    mov rdi, r12; mov rsi, r13; lea rdx, [rip + p_post_dir];   mov ecx, p_post_dir_len;   call build_mkdir_sub
    mov rdi, r12; mov rsi, r13; lea rdx, [rip + p_page_dir];   mov ecx, p_page_dir_len;   call build_mkdir_sub
    mov rdi, r12; mov rsi, r13; lea rdx, [rip + p_arch_dir];   mov ecx, p_arch_dir_len;   call build_mkdir_sub
    mov rdi, r12; mov rsi, r13; lea rdx, [rip + p_tags_dir];   mov ecx, p_tags_dir_len;   call build_mkdir_sub
    mov rdi, r12; mov rsi, r13; lea rdx, [rip + p_tag_dir];    mov ecx, p_tag_dir_len;    call build_mkdir_sub
    mov rdi, r12; mov rsi, r13; lea rdx, [rip + p_cat_dir];    mov ecx, p_cat_dir_len;    call build_mkdir_sub
    mov rdi, r12; mov rsi, r13; lea rdx, [rip + p_search_dir]; mov ecx, p_search_dir_len; call build_mkdir_sub
    mov rdi, r12; mov rsi, r13; lea rdx, [rip + p_gallery_dir]; mov ecx, p_gallery_dir_len; call build_mkdir_sub
    mov rdi, r12; mov rsi, r13; lea rdx, [rip + p_about_dir];  mov ecx, p_about_dir_len;  call build_mkdir_sub
    mov rdi, r12; mov rsi, r13; lea rdx, [rip + p_static_dir]; mov ecx, p_static_dir_len; call build_mkdir_sub
    mov rdi, r12; mov rsi, r13; lea rdx, [rip + p_uploads_dir]; mov ecx, p_uploads_dir_len; call build_mkdir_sub

    # 1. dist/index.html
    mov edi, 1
    call render_index_page
    mov r8, rax
    mov r9, rdx
    mov rdi, r12; mov rsi, r13; lea rdx, [rip + p_index_html]; mov ecx, p_index_html_len
    call build_write_sub

    # 2. dist/page/<p>/index.html for p = 1..total_pages
    call get_total_pages
    mov [rsp + 24], rax
    mov rbx, 1
.Lbd_pages:
    cmp rbx, [rsp + 24]
    ja .Lbd_posts_init
    # mkdir <out>/page/<p>
    mov rdi, rsp; lea rsi, [rip + cli_path1]; mov edx, 1023; call sb_init
    mov rdi, rsp; mov rsi, r12; mov rdx, r13; call sb_mem
    mov rdi, rsp; lea rsi, [rip + p_page_dir]; mov edx, p_page_dir_len; call sb_mem
    mov rdi, rsp; mov esi, '/'; call sb_byte
    mov rdi, rsp; mov rsi, rbx; call sb_uint
    mov r14, [rsp + SB_LEN]
    mov rdi, rsp; xor esi, esi; call sb_byte
    lea rdi, [rip + cli_path1]; call ensure_dir
    # write <out>/page/<p>/index.html
    mov [rsp + SB_LEN], r14
    mov rdi, rsp; lea rsi, [rip + p_index_html]; mov edx, p_index_html_len; call sb_mem
    mov rdi, rsp; xor esi, esi; call sb_byte
    mov rdi, rbx
    call render_index_page
    lea rdi, [rip + cli_path1]
    mov rsi, rax
    call write_file_direct
    inc rbx
    jmp .Lbd_pages

.Lbd_posts_init:
    # 3. dist/post/<slug>/index.html for all published posts
    xor ebx, ebx
.Lbd_posts:
    cmp rbx, [rip + g_post_count]
    jae .Lbd_tags_init
    lea r8, [rip + g_post_ptrs]
    mov r15, [r8 + rbx*8]
    cmp qword ptr [r15 + POST_DRAFT], 0
    jne .Lbd_post_next
    # mkdir <out>/post/<slug>
    mov rdi, rsp; lea rsi, [rip + cli_path1]; mov edx, 1023; call sb_init
    mov rdi, rsp; mov rsi, r12; mov rdx, r13; call sb_mem
    mov rdi, rsp; lea rsi, [rip + p_post_dir]; mov edx, p_post_dir_len; call sb_mem
    mov rdi, rsp; mov esi, '/'; call sb_byte
    mov rdi, rsp; mov rsi, [r15 + POST_SLUG_PTR]; mov rdx, [r15 + POST_SLUG_LEN]; call sb_mem
    mov r14, [rsp + SB_LEN]
    mov rdi, rsp; xor esi, esi; call sb_byte
    lea rdi, [rip + cli_path1]; call ensure_dir
    # write <out>/post/<slug>/index.html
    mov [rsp + SB_LEN], r14
    mov rdi, rsp; lea rsi, [rip + p_index_html]; mov edx, p_index_html_len; call sb_mem
    mov rdi, rsp; xor esi, esi; call sb_byte
    mov rdi, r15
    mov rsi, rbx
    call render_post_page
    lea rdi, [rip + cli_path1]
    mov rsi, rax
    call write_file_direct
.Lbd_post_next:
    inc rbx
    jmp .Lbd_posts

.Lbd_tags_init:
    # 4. dist/tag/<name>/index.html for every tag
    xor ebx, ebx
.Lbd_tags:
    cmp rbx, [rip + g_tag_count]
    jae .Lbd_cats_init
    imul rax, rbx, TAG_SIZE
    lea r15, [rip + g_tags]
    add r15, rax
    # Ensure tag name is safe single directory segment (no '/', '..', '\', NUL)
    mov rdi, [r15 + TAG_NAME_PTR]
    mov rsi, [r15 + TAG_NAME_LEN]
    call is_safe_relpath
    test eax, eax
    jz .Lbd_tag_next
    mov rdi, [r15 + TAG_NAME_PTR]
    mov rsi, [r15 + TAG_NAME_LEN]
    mov edx, '/'
    call xmemchr
    cmp rax, -1
    jne .Lbd_tag_next

    mov rdi, rsp; lea rsi, [rip + cli_path1]; mov edx, 1023; call sb_init
    mov rdi, rsp; mov rsi, r12; mov rdx, r13; call sb_mem
    mov rdi, rsp; lea rsi, [rip + p_tag_dir]; mov edx, p_tag_dir_len; call sb_mem
    mov rdi, rsp; mov esi, '/'; call sb_byte
    mov rdi, rsp; mov rsi, [r15 + TAG_NAME_PTR]; mov rdx, [r15 + TAG_NAME_LEN]; call sb_mem
    mov r14, [rsp + SB_LEN]
    mov rdi, rsp; xor esi, esi; call sb_byte
    lea rdi, [rip + cli_path1]; call ensure_dir
    mov [rsp + SB_LEN], r14
    mov rdi, rsp; lea rsi, [rip + p_index_html]; mov edx, p_index_html_len; call sb_mem
    mov rdi, rsp; xor esi, esi; call sb_byte
    mov rdi, [r15 + TAG_NAME_PTR]
    mov rsi, [r15 + TAG_NAME_LEN]
    call render_tag_page
    lea rdi, [rip + cli_path1]
    mov rsi, rax
    call write_file_direct
.Lbd_tag_next:
    inc rbx
    jmp .Lbd_tags

.Lbd_cats_init:
    # 4b. dist/category/<name>/index.html for every category
    xor ebx, ebx
.Lbd_cats:
    cmp rbx, [rip + g_cat_count]
    jae .Lbd_fixed_pages
    imul rax, rbx, CAT_SIZE
    lea r15, [rip + g_cats]
    add r15, rax
    mov rdi, [r15 + CAT_NAME_PTR]
    mov rsi, [r15 + CAT_NAME_LEN]
    call is_safe_relpath
    test eax, eax
    jz .Lbd_cat_next
    mov rdi, [r15 + CAT_NAME_PTR]
    mov rsi, [r15 + CAT_NAME_LEN]
    mov edx, '/'
    call xmemchr
    cmp rax, -1
    jne .Lbd_cat_next

    mov rdi, rsp; lea rsi, [rip + cli_path1]; mov edx, 1023; call sb_init
    mov rdi, rsp; mov rsi, r12; mov rdx, r13; call sb_mem
    mov rdi, rsp; lea rsi, [rip + p_cat_dir]; mov edx, p_cat_dir_len; call sb_mem
    mov rdi, rsp; mov esi, '/'; call sb_byte
    mov rdi, rsp; mov rsi, [r15 + CAT_NAME_PTR]; mov rdx, [r15 + CAT_NAME_LEN]; call sb_mem
    mov r14, [rsp + SB_LEN]
    mov rdi, rsp; xor esi, esi; call sb_byte
    lea rdi, [rip + cli_path1]; call ensure_dir
    mov [rsp + SB_LEN], r14
    mov rdi, rsp; lea rsi, [rip + p_index_html]; mov edx, p_index_html_len; call sb_mem
    mov rdi, rsp; xor esi, esi; call sb_byte
    mov rdi, [r15 + CAT_NAME_PTR]
    mov rsi, [r15 + CAT_NAME_LEN]
    call render_category_page
    lea rdi, [rip + cli_path1]
    mov rsi, rax
    call write_file_direct
.Lbd_cat_next:
    inc rbx
    jmp .Lbd_cats

.Lbd_fixed_pages:
    # 5. dist/archive/index.html
    call render_archive_page
    mov r14, rax; mov r15, rdx
    mov rdi, rsp; lea rsi, [rip + cli_path1]; mov edx, 1023; call sb_init
    mov rdi, rsp; mov rsi, r12; mov rdx, r13; call sb_mem
    mov rdi, rsp; lea rsi, [rip + p_arch_dir]; mov edx, p_arch_dir_len; call sb_mem
    mov rdi, rsp; lea rsi, [rip + p_index_html]; mov edx, p_index_html_len; call sb_mem
    mov rdi, rsp; xor esi, esi; call sb_byte
    lea rdi, [rip + cli_path1]; mov rsi, r14; mov rdx, r15; call write_file_direct

    # 6. dist/tags/index.html
    call render_tags_page
    mov r14, rax; mov r15, rdx
    mov rdi, rsp; lea rsi, [rip + cli_path1]; mov edx, 1023; call sb_init
    mov rdi, rsp; mov rsi, r12; mov rdx, r13; call sb_mem
    mov rdi, rsp; lea rsi, [rip + p_tags_dir]; mov edx, p_tags_dir_len; call sb_mem
    mov rdi, rsp; lea rsi, [rip + p_index_html]; mov edx, p_index_html_len; call sb_mem
    mov rdi, rsp; xor esi, esi; call sb_byte
    lea rdi, [rip + cli_path1]; mov rsi, r14; mov rdx, r15; call write_file_direct

    # 7. dist/search/index.html
    xor edi, edi; xor esi, esi
    call render_search_page
    mov r14, rax; mov r15, rdx
    mov rdi, rsp; lea rsi, [rip + cli_path1]; mov edx, 1023; call sb_init
    mov rdi, rsp; mov rsi, r12; mov rdx, r13; call sb_mem
    mov rdi, rsp; lea rsi, [rip + p_search_dir]; mov edx, p_search_dir_len; call sb_mem
    mov rdi, rsp; lea rsi, [rip + p_index_html]; mov edx, p_index_html_len; call sb_mem
    mov rdi, rsp; xor esi, esi; call sb_byte
    lea rdi, [rip + cli_path1]; mov rsi, r14; mov rdx, r15; call write_file_direct

    # 7b. dist/gallery/index.html & dist/about/index.html
    call render_gallery_page
    mov r14, rax; mov r15, rdx
    mov rdi, rsp; lea rsi, [rip + cli_path1]; mov edx, 1023; call sb_init
    mov rdi, rsp; mov rsi, r12; mov rdx, r13; call sb_mem
    mov rdi, rsp; lea rsi, [rip + p_gallery_dir]; mov edx, p_gallery_dir_len; call sb_mem
    mov rdi, rsp; lea rsi, [rip + p_index_html]; mov edx, p_index_html_len; call sb_mem
    mov rdi, rsp; xor esi, esi; call sb_byte
    lea rdi, [rip + cli_path1]; mov rsi, r14; mov rdx, r15; call write_file_direct

    call render_about_page
    mov r14, rax; mov r15, rdx
    mov rdi, rsp; lea rsi, [rip + cli_path1]; mov edx, 1023; call sb_init
    mov rdi, rsp; mov rsi, r12; mov rdx, r13; call sb_mem
    mov rdi, rsp; lea rsi, [rip + p_about_dir]; mov edx, p_about_dir_len; call sb_mem
    mov rdi, rsp; lea rsi, [rip + p_index_html]; mov edx, p_index_html_len; call sb_mem
    mov rdi, rsp; xor esi, esi; call sb_byte
    lea rdi, [rip + cli_path1]; mov rsi, r14; mov rdx, r15; call write_file_direct

    # 7c. dist/gallery.json, dist/about.json, dist/bgm.json (copy if present, else empty JSON)
    mov rdi, r12; mov rsi, r13; lea rdx, [rip + p_gal_json]; mov ecx, p_gal_json_len
    lea r8, [rip + src_gal_json]; lea r9, [rip + def_empty_arr]; call build_copy_or_def
    mov rdi, r12; mov rsi, r13; lea rdx, [rip + p_abt_json]; mov ecx, p_abt_json_len
    lea r8, [rip + src_abt_json]; lea r9, [rip + def_empty_obj]; call build_copy_or_def
    mov rdi, r12; mov rsi, r13; lea rdx, [rip + p_bgm_json]; mov ecx, p_bgm_json_len
    lea r8, [rip + src_bgm_json]; lea r9, [rip + def_empty_arr]; call build_copy_or_def

    # 8. dist/search-index.json
    call render_search_index_json
    mov r8, rax; mov r9, rdx
    mov rdi, r12; mov rsi, r13; lea rdx, [rip + p_search_json]; mov ecx, p_search_json_len
    call build_write_sub

    # 9. dist/rss.xml
    call render_rss_xml
    mov r8, rax; mov r9, rdx
    mov rdi, r12; mov rsi, r13; lea rdx, [rip + p_rss_xml]; mov ecx, p_rss_xml_len
    call build_write_sub

    # 10. dist/sitemap.xml
    call render_sitemap_xml
    mov r8, rax; mov r9, rdx
    mov rdi, r12; mov rsi, r13; lea rdx, [rip + p_sitemap_xml]; mov ecx, p_sitemap_xml_len
    call build_write_sub

    # 11. dist/404.html
    call render_404_page
    mov r8, rax; mov r9, rdx
    mov rdi, r12; mov rsi, r13; lea rdx, [rip + p_404_html]; mov ecx, p_404_html_len
    call build_write_sub

    # 12. dist/favicon.ico
    call get_favicon_svg
    mov r8, rax; mov r9, rdx
    mov rdi, r12; mov rsi, r13; lea rdx, [rip + p_favicon_ico]; mov ecx, p_favicon_ico_len
    call build_write_sub

    # 13. Copy themes/<theme>/static/* -> dist/static/* and content/uploads/* -> dist/uploads/*
    mov rdi, r12
    mov rsi, r13
    call copy_static_dir_impl
    mov rdi, r12
    mov rsi, r13
    call copy_uploads_dir_impl

    # Print summary to stdout
    mov rdi, rsp; lea rsi, [rip + cli_out_buf]; mov edx, 4095; call sb_init
    mov rdi, rsp; lea rsi, [rip + msg_built_1]; mov edx, msg_built_1_len; call sb_mem
    mov rdi, rsp; mov rsi, r12; mov rdx, r13; call sb_mem
    mov rdi, rsp; lea rsi, [rip + msg_built_2]; mov edx, msg_built_2_len; call sb_mem
    mov rdi, rsp; mov rsi, [rip + g_pub_count]; call sb_uint
    mov rdi, rsp; lea rsi, [rip + msg_built_3]; mov edx, msg_built_3_len; call sb_mem
    mov rdi, rsp; mov rsi, [rip + g_tag_count]; call sb_uint
    mov rdi, rsp; lea rsi, [rip + msg_built_4]; mov edx, msg_built_4_len; call sb_mem
    mov rdi, rsp; mov rsi, [rsp + 24]; call sb_uint
    mov rdi, rsp; lea rsi, [rip + msg_built_5]; mov edx, msg_built_5_len; call sb_mem
    mov edi, 1
    lea rsi, [rip + cli_out_buf]
    mov rdx, [rsp + SB_LEN]
    call write_all

    xor eax, eax
.Lbd_ret:
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

# do_cmd_new(rdi=argc, rsi=argv) -> creates content/posts/<slug>.md
do_cmd_new:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40           # [rsp+0..23]=sbuf

    mov r12, rdi          # argc
    mov r13, rsi          # argv
    xor r14d, r14d        # slug_cstr
    xor r15d, r15d        # title_cstr

    # Scan args from index 2: accept -d <dir>, first positional = slug, second = title
    mov rbx, 2
.Lnw_scan:
    cmp rbx, r12
    jae .Lnw_check
    mov rdi, [r13 + rbx*8]
    lea rsi, [rip + flg_d]; mov edx, 2; call cstr_eq
    test eax, eax
    jz .Lnw_pos
    lea rax, [rbx + 1]
    cmp rax, r12
    jae .Lnw_next
    inc rbx
    mov rax, [r13 + rbx*8]
    mov [rip + cli_opt_dir], rax
    jmp .Lnw_next
.Lnw_pos:
    mov rax, [r13 + rbx*8]
    test r14, r14
    jnz .Lnw_t
    mov r14, rax
    jmp .Lnw_next
.Lnw_t:
    test r15, r15
    jnz .Lnw_next
    mov r15, rax
.Lnw_next:
    inc rbx
    jmp .Lnw_scan

.Lnw_check:
    test r14, r14
    jnz .Lnw_has_slug
    lea rdi, [rip + err_new_usage]; call log_cstr
    mov eax, 1
    jmp .Lnw_ret

.Lnw_has_slug:
    mov rdi, r14
    call xstrlen
    mov rbx, rax          # slug_len
    mov rdi, r14
    mov rsi, rbx
    call is_safe_slug
    test eax, eax
    jnz .Lnw_chdir
    lea rdi, [rip + err_bad_slug]; call log_cstr
    mov eax, 1
    jmp .Lnw_ret

.Lnw_chdir:
    mov rdi, [rip + cli_opt_dir]
    test rdi, rdi
    jz .Lnw_mk
    call sys_chdir
    test rax, rax
    jns .Lnw_mk
    lea rdi, [rip + err_chdir]; call log_cstr
    mov eax, 1
    jmp .Lnw_ret

.Lnw_mk:
    lea rdi, [rip + d_content]; call ensure_dir
    lea rdi, [rip + d_posts];   call ensure_dir

    test r15, r15
    jnz .Lnw_tlen
    mov r15, r14          # default title = slug
.Lnw_tlen:
    mov rdi, r15
    call xstrlen
    mov [rsp + 24], rax   # title_len

    # Format today's UTC date
    call real_sec
    mov rdi, rax
    lea rsi, [rip + cli_date_buf]
    call format_iso_date

    # Build Markdown content in cli_out_buf
    mov rdi, rsp; lea rsi, [rip + cli_out_buf]; mov edx, 4095; call sb_init
    mov rdi, rsp; lea rsi, [rip + np_1]; mov edx, np_1_len; call sb_mem
    mov rdi, rsp; mov rsi, r15; mov rdx, [rsp + 24]; call sb_mem
    mov rdi, rsp; lea rsi, [rip + np_2]; mov edx, np_2_len; call sb_mem
    mov rdi, rsp; mov rsi, r14; mov rdx, rbx; call sb_mem
    mov rdi, rsp; lea rsi, [rip + np_3]; mov edx, np_3_len; call sb_mem
    mov rdi, rsp; lea rsi, [rip + cli_date_buf]; mov edx, 10; call sb_mem
    mov rdi, rsp; lea rsi, [rip + np_4]; mov edx, np_4_len; call sb_mem
    mov rdi, rsp; mov rsi, r15; mov rdx, [rsp + 24]; call sb_mem
    mov rdi, rsp; lea rsi, [rip + np_5]; mov edx, np_5_len; call sb_mem
    mov r12, [rsp + SB_LEN]   # md_len

    # Build path content/posts/<slug>.md
    mov rdi, rsp; lea rsi, [rip + cli_path1]; mov edx, 1023; call sb_init
    mov rdi, rsp; lea rsi, [rip + p_cp_pre]; mov edx, p_cp_pre_len; call sb_mem
    mov rdi, rsp; mov rsi, r14; mov rdx, rbx; call sb_mem
    mov rdi, rsp; lea rsi, [rip + p_md_ext]; mov edx, p_md_ext_len; call sb_mem
    mov r13, [rsp + SB_LEN]
    mov rdi, rsp; xor esi, esi; call sb_byte

    lea rdi, [rip + cli_path1]
    lea rsi, [rip + cli_out_buf]
    mov rdx, r12
    call write_file_direct
    test rax, rax
    jns .Lnw_ok
    lea rdi, [rip + err_write]; call log_cstr
    mov eax, 1
    jmp .Lnw_ret

.Lnw_ok:
    mov edi, 1; lea rsi, [rip + msg_new_ok1]; mov edx, msg_new_ok1_len; call write_all
    mov edi, 1; lea rsi, [rip + cli_path1];   mov rdx, r13;             call write_all
    mov byte ptr [rip + cli_date_buf], 10
    mov edi, 1; lea rsi, [rip + cli_date_buf]; mov edx, 1;              call write_all
    xor eax, eax
.Lnw_ret:
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

# do_cmd_init(rdi=argc, rsi=argv) -> scaffolds a standalone static blog site
do_cmd_init:
    push rbx
    cmp rdi, 3
    jb .Lin_mk
    mov rbx, [rsi + 16]   # target dir
    mov rdi, rbx
    call ensure_dir
    mov rdi, rbx
    call sys_chdir
    test rax, rax
    jns .Lin_mk
    lea rdi, [rip + err_chdir]; call log_cstr
    mov eax, 1
    pop rbx
    ret

.Lin_mk:
    lea rdi, [rip + d_content]; call ensure_dir
    lea rdi, [rip + d_posts];   call ensure_dir
    lea rdi, [rip + d_themes];  call ensure_dir
    lea rdi, [rip + d_th_def];  call ensure_dir
    lea rdi, [rip + d_th_st];   call ensure_dir

    lea rdi, [rip + f_cfg];       lea rsi, [rip + init_cfg];     mov edx, init_cfg_len;     call write_file_direct
    lea rdi, [rip + f_hello];     lea rsi, [rip + init_hello];   mov edx, init_hello_len;   call write_file_direct
    lea rdi, [rip + f_t_layout];  lea rsi, [rip + init_layout];  mov edx, init_layout_len;  call write_file_direct
    lea rdi, [rip + f_t_index];   lea rsi, [rip + init_index];   mov edx, init_index_len;   call write_file_direct
    lea rdi, [rip + f_t_post];    lea rsi, [rip + init_post];    mov edx, init_post_len;    call write_file_direct
    lea rdi, [rip + f_t_archive]; lea rsi, [rip + init_archive]; mov edx, init_archive_len; call write_file_direct
    lea rdi, [rip + f_t_tags];    lea rsi, [rip + init_tags];    mov edx, init_tags_len;    call write_file_direct
    lea rdi, [rip + f_t_tag];     lea rsi, [rip + init_tag];     mov edx, init_tag_len;     call write_file_direct
    lea rdi, [rip + f_t_search];  lea rsi, [rip + init_search];  mov edx, init_search_len;  call write_file_direct
    lea rdi, [rip + f_t_404];     lea rsi, [rip + init_404];     mov edx, init_404_len;     call write_file_direct
    lea rdi, [rip + f_s_css];     lea rsi, [rip + init_css];     mov edx, init_css_len;     call write_file_direct
    lea rdi, [rip + f_s_js];      lea rsi, [rip + init_js];      mov edx, init_js_len;      call write_file_direct

    lea rdi, [rip + msg_init_ok]; call out_cstr
    xor eax, eax
    pop rbx
    ret

# do_cmd_hashpass(rdi=argc, rsi=argv) -> prints "studio_pass_sha256 = <64hex>\n"
do_cmd_hashpass:
    push r12
    sub rsp, 96           # [rsp+0..23]=sbuf, [rsp+24..88]=64hex
    cmp rdi, 3
    jae .Lhp_go
    lea rdi, [rip + err_hp_usage]; call log_cstr
    mov eax, 1
    jmp .Lhp_ret
.Lhp_go:
    mov r12, [rsi + 16]   # argv[2]
    mov rdi, r12
    call xstrlen
    test rax, rax
    jnz .Lhp_hash
    lea rdi, [rip + err_hp_usage]; call log_cstr
    mov eax, 1
    jmp .Lhp_ret
.Lhp_hash:
    mov rdi, r12
    mov rsi, rax
    lea rdx, [rsp + 24]
    call sha256_hex

    mov rdi, rsp; lea rsi, [rip + cli_out_buf]; mov edx, 255; call sb_init
    mov rdi, rsp; lea rsi, [rip + hp_prefix]; mov edx, hp_prefix_len; call sb_mem
    mov rdi, rsp; lea rsi, [rsp + 24]; mov edx, 64; call sb_mem
    mov rdi, rsp; mov esi, 10; call sb_byte

    mov edi, 1
    lea rsi, [rip + cli_out_buf]
    mov rdx, [rsp + SB_LEN]
    call write_all
    xor eax, eax
.Lhp_ret:
    add rsp, 96
    pop r12
    ret

# cli_main(rdi=argc, rsi=argv) -> rax=exit_code
.globl cli_main
cli_main:
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi

    mov qword ptr [rip + cli_opt_cfg], 0
    mov qword ptr [rip + cli_opt_dir], 0
    mov qword ptr [rip + cli_opt_out], 0
    mov qword ptr [rip + cli_opt_port], 0

    cmp r12, 2
    jb .Lcm_help

    mov rdi, [r13 + 8]    # argv[1]
    lea rsi, [rip + flg_help1]; mov edx, 6; call cstr_eq; test eax, eax; jnz .Lcm_help
    mov rdi, [r13 + 8]
    lea rsi, [rip + flg_help2]; mov edx, 2; call cstr_eq; test eax, eax; jnz .Lcm_help
    mov rdi, [r13 + 8]
    lea rsi, [rip + flg_ver1];  mov edx, 9; call cstr_eq; test eax, eax; jnz .Lcm_ver
    mov rdi, [r13 + 8]
    lea rsi, [rip + flg_ver2];  mov edx, 2; call cstr_eq; test eax, eax; jnz .Lcm_ver

    mov rdi, [r13 + 8]
    lea rsi, [rip + cmd_serve]; mov edx, 5; call cstr_eq; test eax, eax; jnz .Lcm_serve
    mov rdi, [r13 + 8]
    lea rsi, [rip + cmd_build]; mov edx, 5; call cstr_eq; test eax, eax; jnz .Lcm_build
    mov rdi, [r13 + 8]
    lea rsi, [rip + cmd_new];   mov edx, 3; call cstr_eq; test eax, eax; jnz .Lcm_new
    mov rdi, [r13 + 8]
    lea rsi, [rip + cmd_init];     mov edx, 4; call cstr_eq; test eax, eax; jnz .Lcm_init
    mov rdi, [r13 + 8]
    lea rsi, [rip + cmd_hashpass]; mov edx, 9; call cstr_eq; test eax, eax; jnz .Lcm_hashpass

    lea rdi, [rip + err_bad_cmd]; call log_cstr
    mov eax, 1
    jmp .Lcm_ret

.Lcm_help:
    lea rdi, [rip + str_help]; call out_cstr
    xor eax, eax
    jmp .Lcm_ret

.Lcm_ver:
    lea rdi, [rip + str_version]; call out_cstr
    xor eax, eax
    jmp .Lcm_ret

.Lcm_serve:
    mov rdi, r12; mov rsi, r13; mov edx, 2; call parse_common_opts
    call do_cmd_serve
    jmp .Lcm_ret

.Lcm_build:
    mov rdi, r12; mov rsi, r13; mov edx, 2; call parse_common_opts
    call do_cmd_build
    jmp .Lcm_ret

.Lcm_new:
    mov rdi, r12; mov rsi, r13; call do_cmd_new
    jmp .Lcm_ret

.Lcm_init:
    mov rdi, r12; mov rsi, r13; call do_cmd_init
    jmp .Lcm_ret

.Lcm_hashpass:
    mov rdi, r12; mov rsi, r13; call do_cmd_hashpass

.Lcm_ret:
    pop r13
    pop r12
    ret
