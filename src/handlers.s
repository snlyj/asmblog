.include "defs.inc"

# Static Blog Page Renderers & Read-Only HTTP Handlers
# Every render_* function is shared between `asmblog serve` (HTTP) and `asmblog build` (SSG).

.section .bss
.align 8
.globl g_render_inner
g_render_inner:     .skip 196608    # 192 KiB inner template buffer
.globl g_render_page
g_render_page:      .skip 262144    # 256 KiB full page / RSS / Sitemap / JSON buffer
render_tags_buf:    .skip 4096      # tag chips HTML buffer
render_q_buf:       .skip 512       # decoded query or tag param
render_num_bufs:    .skip 256       # numeric string slots (8 * 32 bytes)
render_url_prev:    .skip 128
render_url_next:    .skip 128

# Active filtered post list for {{#posts}} section rendering
cur_list_ptrs:      .skip MAX_POSTS * 8
cur_list_count:     .quad 0

# Template variable table (up to 64 bindings)
g_vars:             .skip 64 * TV_SIZE
g_vars_cnt:         .quad 0
g_tctx:             .skip TCTX_SIZE

.section .rodata
k_site_name:     .ascii "site_name"
.equ k_site_name_len, . - k_site_name
k_site_subtitle: .ascii "site_subtitle"
.equ k_site_subtitle_len, . - k_site_subtitle
k_site_url:      .ascii "site_url"
.equ k_site_url_len, . - k_site_url
k_author:        .ascii "author"
.equ k_author_len, . - k_author
k_footer_text:   .ascii "footer_text"
.equ k_footer_text_len, . - k_footer_text
k_avatar_url:    .ascii "avatar_url"
.equ k_avatar_url_len, . - k_avatar_url
k_banner_url:    .ascii "banner_url"
.equ k_banner_url_len, . - k_banner_url
k_page_title:    .ascii "page_title"
.equ k_page_title_len, . - k_page_title
k_body:          .ascii "body"
.equ k_body_len, . - k_body
k_post_count:    .ascii "post_count"
.equ k_post_count_len, . - k_post_count
k_tag_count:     .ascii "tag_count"
.equ k_tag_count_len, . - k_tag_count
k_title:         .ascii "title"
.equ k_title_len, . - k_title
k_slug:          .ascii "slug"
.equ k_slug_len, . - k_slug
k_date:          .ascii "date"
.equ k_date_len, . - k_date
k_summary:       .ascii "summary"
.equ k_summary_len, . - k_summary
k_read_min:      .ascii "read_min"
.equ k_read_min_len, . - k_read_min
k_tags_html:     .ascii "tags_html"
.equ k_tags_html_len, . - k_tags_html
k_content_html:  .ascii "content_html"
.equ k_content_html_len, . - k_content_html
k_prev_slug:     .ascii "prev_slug"
.equ k_prev_slug_len, . - k_prev_slug
k_prev_title:    .ascii "prev_title"
.equ k_prev_title_len, . - k_prev_title
k_next_slug:     .ascii "next_slug"
.equ k_next_slug_len, . - k_next_slug
k_next_title:    .ascii "next_title"
.equ k_next_title_len, . - k_next_title
k_prev_page_url: .ascii "prev_page_url"
.equ k_prev_page_url_len, . - k_prev_page_url
k_next_page_url: .ascii "next_page_url"
.equ k_next_page_url_len, . - k_next_page_url
k_page_num:      .ascii "page_num"
.equ k_page_num_len, . - k_page_num
k_total_pages:   .ascii "total_pages"
.equ k_total_pages_len, . - k_total_pages
k_active_tag:    .ascii "active_tag"
.equ k_active_tag_len, . - k_active_tag
k_active_cat:    .ascii "active_category"
.equ k_active_cat_len, . - k_active_cat
k_cat_count:     .ascii "cat_count"
.equ k_cat_count_len, . - k_cat_count
k_cover:         .ascii "cover"
.equ k_cover_len, . - k_cover
k_category:      .ascii "category"
.equ k_category_len, . - k_category
k_query:         .ascii "query"
.equ k_query_len, . - k_query
k_name:          .ascii "name"
.equ k_name_len, . - k_name
k_count:         .ascii "count"
.equ k_count_len, . - k_count
k_sec_posts:     .ascii "posts"
.equ k_sec_posts_len, . - k_sec_posts
k_sec_tags:      .ascii "tags"
.equ k_sec_tags_len, . - k_sec_tags
k_sec_cats:      .ascii "categories"
.equ k_sec_cats_len, . - k_sec_cats

tpl_layout:      .ascii "layout"
.equ tpl_layout_len, . - tpl_layout
tpl_index:       .ascii "index"
.equ tpl_index_len, . - tpl_index
tpl_post:        .ascii "post"
.equ tpl_post_len, . - tpl_post
tpl_archive:     .ascii "archive"
.equ tpl_archive_len, . - tpl_archive
tpl_tags:        .ascii "tags"
.equ tpl_tags_len, . - tpl_tags
tpl_tag:         .ascii "tag"
.equ tpl_tag_len, . - tpl_tag
tpl_category:    .ascii "category"
.equ tpl_category_len, . - tpl_category
tpl_search:      .ascii "search"
.equ tpl_search_len, . - tpl_search
tpl_404:         .ascii "404"
.equ tpl_404_len, . - tpl_404

s_home_title:    .ascii "首页"
.equ s_home_title_len, . - s_home_title
s_arch_title:    .ascii "归档"
.equ s_arch_title_len, . - s_arch_title
s_tags_title:    .ascii "标签"
.equ s_tags_title_len, . - s_tags_title
s_search_title:  .ascii "搜索"
.equ s_search_title_len, . - s_search_title
s_404_title:     .ascii "404 Not Found"
.equ s_404_title_len, . - s_404_title
s_page_pre:      .ascii "/page/"
.equ s_page_pre_len, . - s_page_pre
s_slash:         .ascii "/"
s_q_key:         .ascii "q"

tag_chip_1:      .ascii "<a class=\"tag-chip\" href=\"/tag/"
.equ tag_chip_1_len, . - tag_chip_1
tag_chip_2:      .ascii "/\">#"
.equ tag_chip_2_len, . - tag_chip_2
tag_chip_3:      .ascii "</a>"
.equ tag_chip_3_len, . - tag_chip_3

# RSS 2.0 fragments
rss_head_1:      .ascii "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<rss version=\"2.0\"><channel>\n<title>"
.equ rss_head_1_len, . - rss_head_1
rss_head_2:      .ascii "</title>\n<link>"
.equ rss_head_2_len, . - rss_head_2
rss_head_3:      .ascii "</link>\n<description>"
.equ rss_head_3_len, . - rss_head_3
rss_head_4:      .ascii "</description>\n<generator>AsmBlog x86-64 Static Blog</generator>\n"
.equ rss_head_4_len, . - rss_head_4
rss_item_1:      .ascii "<item><title>"
.equ rss_item_1_len, . - rss_item_1
rss_item_2:      .ascii "</title><link>"
.equ rss_item_2_len, . - rss_item_2
rss_item_3:      .ascii "/post/"
.equ rss_item_3_len, . - rss_item_3
rss_item_4:      .ascii "/</link><guid>"
.equ rss_item_4_len, . - rss_item_4
rss_item_5:      .ascii "/</guid><pubDate>"
.equ rss_item_5_len, . - rss_item_5
rss_item_6:      .ascii "</pubDate><description>"
.equ rss_item_6_len, . - rss_item_6
rss_item_7:      .ascii "</description></item>\n"
.equ rss_item_7_len, . - rss_item_7
rss_foot:        .ascii "</channel></rss>\n"
.equ rss_foot_len, . - rss_foot

# Sitemap XML fragments
sm_head:         .ascii "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n"
.equ sm_head_len, . - sm_head
sm_u1:           .ascii "<url><loc>"
.equ sm_u1_len, . - sm_u1
sm_u2:           .ascii "</loc></url>\n"
.equ sm_u2_len, . - sm_u2
sm_u_lm:         .ascii "/</loc><lastmod>"
.equ sm_u_lm_len, . - sm_u_lm
sm_u_end:        .ascii "</lastmod></url>\n"
.equ sm_u_end_len, . - sm_u_end
sm_foot:         .ascii "</urlset>\n"
.equ sm_foot_len, . - sm_foot

# Static search index JSON fragments
si_open:         .ascii "{\"slug\":\""
.equ si_open_len, . - si_open
si_title:        .ascii "\",\"title\":\""
.equ si_title_len, . - si_title
si_date:         .ascii "\",\"date\":\""
.equ si_date_len, . - si_date
si_tags:         .ascii "\",\"tags\":\""
.equ si_tags_len, . - si_tags
si_cat:          .ascii "\",\"category\":\""
.equ si_cat_len, . - si_cat
si_cover:        .ascii "\",\"cover\":\""
.equ si_cover_len, . - si_cover
si_sum:          .ascii "\",\"summary\":\""
.equ si_sum_len, . - si_sum
si_end:          .ascii "\"}"
.equ si_end_len, . - si_end

# Healthz JSON fragments
hz_1:            .ascii "{\"status\":\"ok\",\"engine\":\"asmblog-x86_64-static\",\"posts\":"
.equ hz_1_len, . - hz_1
hz_2:            .ascii ",\"published\":"
.equ hz_2_len, . - hz_2
hz_3:            .ascii ",\"tags\":"
.equ hz_3_len, . - hz_3
hz_4:            .ascii ",\"reloads\":"
.equ hz_4_len, . - hz_4
hz_5:            .ascii ",\"arena_used\":"
.equ hz_5_len, . - hz_5
hz_6:            .ascii ",\"uptime_sec\":"
.equ hz_6_len, . - hz_6
hz_7:            .ascii ",\"conns_active\":"
.equ hz_7_len, . - hz_7
hz_8:            .ascii "}\n"
.equ hz_8_len, . - hz_8

fallback_404:    .ascii "<!doctype html><meta charset=\"utf-8\"><title>404 Not Found</title><h1>404 Not Found</h1><p><a href=\"/\">Back to Home</a></p>"
.equ fallback_404_len, . - fallback_404

.section .text

# --- Safe HTTP Response Dispatch Helpers (zero register-clobber risk) ---

# send_html_200(rdi=conn, rsi=body_ptr, rdx=body_len)
send_html_200:
    mov r8, rdx
    mov rcx, rsi
    lea rsi, [rip + st_200]
    lea rdx, [rip + ct_html]
    xor r9d, r9d
    jmp http_send_resp

# send_200_ct(rdi=conn, rsi=body_ptr, rdx=body_len, rcx=ctype_cstr)
send_200_ct:
    mov r8, rdx
    mov rdx, rcx
    mov rcx, rsi
    lea rsi, [rip + st_200]
    xor r9d, r9d
    jmp http_send_resp

# --- Template Context Helpers ---

# ctx_reset() -> initializes g_vars with global site variables
ctx_reset:
    push rbx
    mov qword ptr [rip + g_vars_cnt], 0
    lea rax, [rip + g_vars]
    mov [rip + g_tctx + TCTX_VARS_PTR], rax
    mov qword ptr [rip + g_tctx + TCTX_VARS_CNT], 0
    lea rax, [rip + handlers_sec_cb]
    mov [rip + g_tctx + TCTX_SEC_CB], rax
    mov qword ptr [rip + g_tctx + TCTX_USER_PTR], 0
    mov qword ptr [rip + g_tctx + TCTX_DEPTH], 0

    lea rdi, [rip + k_site_name];     mov esi, k_site_name_len
    lea rdx, [rip + g_cfg_site_name]; mov rcx, [rip + g_cfg_site_name_len]; call ctx_set

    lea rdi, [rip + k_site_subtitle]; mov esi, k_site_subtitle_len
    lea rdx, [rip + g_cfg_subtitle];  mov rcx, [rip + g_cfg_subtitle_len];  call ctx_set

    lea rdi, [rip + k_site_url];      mov esi, k_site_url_len
    lea rdx, [rip + g_cfg_site_url];  mov rcx, [rip + g_cfg_site_url_len];  call ctx_set

    lea rdi, [rip + k_author];        mov esi, k_author_len
    lea rdx, [rip + g_cfg_author];    mov rcx, [rip + g_cfg_author_len];    call ctx_set

    lea rdi, [rip + k_footer_text];   mov esi, k_footer_text_len
    lea rdx, [rip + g_cfg_footer];    mov rcx, [rip + g_cfg_footer_len];    call ctx_set

    lea rdi, [rip + k_avatar_url];    mov esi, k_avatar_url_len
    lea rdx, [rip + g_cfg_avatar];    mov rcx, [rip + g_cfg_avatar_len];    call ctx_set

    lea rdi, [rip + k_banner_url];    mov esi, k_banner_url_len
    lea rdx, [rip + g_cfg_banner];    mov rcx, [rip + g_cfg_banner_len];    call ctx_set

    # post_count -> slot 0
    mov rdi, [rip + g_pub_count]
    xor esi, esi
    call fmt_num_slot
    push rax
    push rdx
    lea rdi, [rip + k_post_count]; mov esi, k_post_count_len
    pop rcx
    pop rdx
    call ctx_set

    # tag_count -> slot 1
    mov rdi, [rip + g_tag_count]
    mov esi, 1
    call fmt_num_slot
    push rax
    push rdx
    lea rdi, [rip + k_tag_count]; mov esi, k_tag_count_len
    pop rcx
    pop rdx
    call ctx_set

    # cat_count -> slot 6
    mov rdi, [rip + g_cat_count]
    mov esi, 6
    call fmt_num_slot
    push rax
    push rdx
    lea rdi, [rip + k_cat_count]; mov esi, k_cat_count_len
    pop rcx
    pop rdx
    call ctx_set

    pop rbx
    ret

# fmt_num_slot(rdi=val, esi=slot_0_to_7) -> rax=ptr, rdx=len
fmt_num_slot:
    sub rsp, 32
    mov eax, esi
    shl eax, 5
    lea r8, [rip + render_num_bufs]
    add r8, rax
    push rdi
    push r8
    lea rdi, [rsp + 16]
    mov rsi, r8
    mov edx, 31
    call sb_init
    pop r8
    pop rsi
    push r8
    lea rdi, [rsp + 8]
    call sb_uint
    pop rax
    mov rdx, [rsp + SB_LEN]
    add rsp, 32
    ret

# ctx_set(rdi=kptr, rsi=klen, rdx=vptr, rcx=vlen)
ctx_set:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    lea rbx, [rip + g_vars]
    xor r8d, r8d
.Lcs_scan:
    cmp r8, [rip + g_vars_cnt]
    jae .Lcs_add
    imul rax, r8, TV_SIZE
    push r8
    mov rdi, [rbx + rax + TV_KEY_PTR]
    mov rsi, [rbx + rax + TV_KEY_LEN]
    mov rdx, r12
    mov rcx, r13
    call xslice_eq
    pop r8
    test eax, eax
    jnz .Lcs_upd
    inc r8
    jmp .Lcs_scan
.Lcs_upd:
    imul rax, r8, TV_SIZE
    mov [rbx + rax + TV_VAL_PTR], r14
    mov [rbx + rax + TV_VAL_LEN], r15
    jmp .Lcs_done
.Lcs_add:
    mov r8, [rip + g_vars_cnt]
    cmp r8, 64
    jae .Lcs_done
    imul rax, r8, TV_SIZE
    mov [rbx + rax + TV_KEY_PTR], r12
    mov [rbx + rax + TV_KEY_LEN], r13
    mov [rbx + rax + TV_VAL_PTR], r14
    mov [rbx + rax + TV_VAL_LEN], r15
    inc r8
    mov [rip + g_vars_cnt], r8
    mov [rip + g_tctx + TCTX_VARS_CNT], r8
.Lcs_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# build_tags_html(rdi=&post) -> rax=ptr, rdx=len
build_tags_html:
    push rbx
    push r12
    sub rsp, 32
    mov r12, rdi
    mov rdi, rsp
    lea rsi, [rip + render_tags_buf]
    mov edx, 4095
    call sb_init
    xor ebx, ebx
.Lbth_loop:
    cmp rbx, [r12 + POST_TAG_COUNT]
    jae .Lbth_done
    mov rdi, rsp; lea rsi, [rip + tag_chip_1]; mov edx, tag_chip_1_len; call sb_mem
    mov rdi, rsp; mov rsi, [r12 + POST_TAG_PTRS + rbx*8]; mov rdx, [r12 + POST_TAG_LENS + rbx*8]; call sb_esc_html
    mov rdi, rsp; lea rsi, [rip + tag_chip_2]; mov edx, tag_chip_2_len; call sb_mem
    mov rdi, rsp; mov rsi, [r12 + POST_TAG_PTRS + rbx*8]; mov rdx, [r12 + POST_TAG_LENS + rbx*8]; call sb_esc_html
    mov rdi, rsp; lea rsi, [rip + tag_chip_3]; mov edx, tag_chip_3_len; call sb_mem
    inc rbx
    jmp .Lbth_loop
.Lbth_done:
    lea rax, [rip + render_tags_buf]
    mov rdx, [rsp + SB_LEN]
    add rsp, 32
    pop r12
    pop rbx
    ret

# bind_post_vars(rdi=&post)
bind_post_vars:
    push r12
    mov r12, rdi
    lea rdi, [rip + k_title];    mov esi, k_title_len;    mov rdx, [r12 + POST_TITLE_PTR];   mov rcx, [r12 + POST_TITLE_LEN];   call ctx_set
    lea rdi, [rip + k_slug];     mov esi, k_slug_len;     mov rdx, [r12 + POST_SLUG_PTR];    mov rcx, [r12 + POST_SLUG_LEN];    call ctx_set
    lea rdi, [rip + k_date];     mov esi, k_date_len;     mov rdx, [r12 + POST_DATE_PTR];    mov rcx, [r12 + POST_DATE_LEN];    call ctx_set
    lea rdi, [rip + k_summary];  mov esi, k_summary_len;  mov rdx, [r12 + POST_SUMMARY_PTR]; mov rcx, [r12 + POST_SUMMARY_LEN]; call ctx_set
    lea rdi, [rip + k_cover];    mov esi, k_cover_len;    mov rdx, [r12 + POST_COVER_PTR];   mov rcx, [r12 + POST_COVER_LEN];   call ctx_set
    lea rdi, [rip + k_category]; mov esi, k_category_len; mov rdx, [r12 + POST_CAT_PTR];     mov rcx, [r12 + POST_CAT_LEN];     call ctx_set

    mov rdi, [r12 + POST_READ_MIN]
    mov esi, 2
    call fmt_num_slot
    push rax; push rdx
    lea rdi, [rip + k_read_min]; mov esi, k_read_min_len
    pop rcx; pop rdx
    call ctx_set

    mov rdi, r12
    call build_tags_html
    push rax; push rdx
    lea rdi, [rip + k_tags_html]; mov esi, k_tags_html_len
    pop rcx; pop rdx
    call ctx_set
    pop r12
    ret

# handlers_sec_cb(rdi=sec_ptr, rsi=sec_len, rdx=inner_ptr, rcx=inner_len, r8=inverted, r9=out_sb)
# Handles {{#posts}} and {{#tags}}
handlers_sec_cb:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdx
    mov r13, rcx
    mov r14, r8
    mov r15, r9

    push rdi
    push rsi

    lea rdx, [rip + k_sec_posts]
    mov ecx, k_sec_posts_len
    call xslice_eq
    test eax, eax
    jnz .Lsc_posts

    mov rdi, [rsp + 8]
    mov rsi, [rsp + 0]
    lea rdx, [rip + k_sec_tags]
    mov ecx, k_sec_tags_len
    call xslice_eq
    test eax, eax
    jnz .Lsc_tags

    mov rdi, [rsp + 8]
    mov rsi, [rsp + 0]
    lea rdx, [rip + k_sec_cats]
    mov ecx, k_sec_cats_len
    call xslice_eq
    test eax, eax
    jnz .Lsc_cats

    add rsp, 16
    xor eax, eax
    jmp .Lsc_ret

.Lsc_posts:
    add rsp, 16
    mov rax, [rip + cur_list_count]
    test r14, r14
    jnz .Lsc_posts_inv
    test rax, rax
    jz .Lsc_handled
    xor ebx, ebx
.Lsc_ploop:
    cmp rbx, [rip + cur_list_count]
    jae .Lsc_handled
    lea r8, [rip + cur_list_ptrs]
    mov rdi, [r8 + rbx*8]
    call bind_post_vars
    inc qword ptr [rip + g_tctx + TCTX_DEPTH]
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + g_tctx]
    mov rcx, r15
    call tpl_render
    dec qword ptr [rip + g_tctx + TCTX_DEPTH]
    inc rbx
    jmp .Lsc_ploop
.Lsc_posts_inv:
    test rax, rax
    jnz .Lsc_handled
    inc qword ptr [rip + g_tctx + TCTX_DEPTH]
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + g_tctx]
    mov rcx, r15
    call tpl_render
    dec qword ptr [rip + g_tctx + TCTX_DEPTH]
    jmp .Lsc_handled

.Lsc_tags:
    add rsp, 16
    mov rax, [rip + g_tag_count]
    test r14, r14
    jnz .Lsc_tags_inv
    test rax, rax
    jz .Lsc_handled
    xor ebx, ebx
.Lsc_tloop:
    cmp rbx, [rip + g_tag_count]
    jae .Lsc_handled
    imul rax, rbx, TAG_SIZE
    lea r8, [rip + g_tags]
    lea rdi, [rip + k_name]; mov esi, k_name_len
    mov rdx, [r8 + rax + TAG_NAME_PTR]
    mov rcx, [r8 + rax + TAG_NAME_LEN]
    push r8
    push rax
    call ctx_set
    pop rax
    pop r8
    mov rdi, [r8 + rax + TAG_COUNT]
    mov esi, 3
    call fmt_num_slot
    push rax; push rdx
    lea rdi, [rip + k_count]; mov esi, k_count_len
    pop rcx; pop rdx
    call ctx_set
    inc qword ptr [rip + g_tctx + TCTX_DEPTH]
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + g_tctx]
    mov rcx, r15
    call tpl_render
    dec qword ptr [rip + g_tctx + TCTX_DEPTH]
    inc rbx
    jmp .Lsc_tloop
.Lsc_tags_inv:
    test rax, rax
    jnz .Lsc_handled
    inc qword ptr [rip + g_tctx + TCTX_DEPTH]
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + g_tctx]
    mov rcx, r15
    call tpl_render
    dec qword ptr [rip + g_tctx + TCTX_DEPTH]
    jmp .Lsc_handled

.Lsc_cats:
    add rsp, 16
    mov rax, [rip + g_cat_count]
    test r14, r14
    jnz .Lsc_cats_inv
    test rax, rax
    jz .Lsc_handled
    xor ebx, ebx
.Lsc_cloop:
    cmp rbx, [rip + g_cat_count]
    jae .Lsc_handled
    imul rax, rbx, CAT_SIZE
    lea r8, [rip + g_cats]
    lea rdi, [rip + k_name]; mov esi, k_name_len
    mov rdx, [r8 + rax + CAT_NAME_PTR]
    mov rcx, [r8 + rax + CAT_NAME_LEN]
    push r8
    push rax
    call ctx_set
    pop rax
    pop r8
    mov rdi, [r8 + rax + CAT_COUNT]
    mov esi, 7
    call fmt_num_slot
    push rax; push rdx
    lea rdi, [rip + k_count]; mov esi, k_count_len
    pop rcx; pop rdx
    call ctx_set
    inc qword ptr [rip + g_tctx + TCTX_DEPTH]
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + g_tctx]
    mov rcx, r15
    call tpl_render
    dec qword ptr [rip + g_tctx + TCTX_DEPTH]
    inc rbx
    jmp .Lsc_cloop
.Lsc_cats_inv:
    test rax, rax
    jnz .Lsc_handled
    inc qword ptr [rip + g_tctx + TCTX_DEPTH]
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + g_tctx]
    mov rcx, r15
    call tpl_render
    dec qword ptr [rip + g_tctx + TCTX_DEPTH]

.Lsc_handled:
    mov eax, 1
.Lsc_ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

# render_with_layout(rdi=tpl_name_ptr, rsi=tpl_name_len) -> rax=page_ptr, rdx=page_len
.globl render_with_layout
render_with_layout:
    push r12
    push r13
    sub rsp, 56
    mov r12, rdi
    mov r13, rsi

    mov rdi, rsp
    lea rsi, [rip + g_render_inner]
    mov edx, 196607
    call sb_init

    mov rdi, r12
    mov rsi, r13
    call store_find_tpl
    test rax, rax
    jz .Lrwl_no_inner
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [rip + g_tctx]
    mov rcx, rsp
    call tpl_render

.Lrwl_no_inner:
    lea rdi, [rip + k_body]; mov esi, k_body_len
    lea rdx, [rip + g_render_inner]
    mov rcx, [rsp + SB_LEN]
    call ctx_set

    lea rdi, [rsp + 24]
    lea rsi, [rip + g_render_page]
    mov edx, 262143
    call sb_init

    lea rdi, [rip + tpl_layout]
    mov esi, tpl_layout_len
    call store_find_tpl
    test rax, rax
    jz .Lrwl_raw_inner
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [rip + g_tctx]
    lea rcx, [rsp + 24]
    call tpl_render
    lea rax, [rip + g_render_page]
    mov rdx, [rsp + 24 + SB_LEN]
    jmp .Lrwl_ret

.Lrwl_raw_inner:
    lea rax, [rip + g_render_inner]
    mov rdx, [rsp + SB_LEN]
.Lrwl_ret:
    add rsp, 56
    pop r13
    pop r12
    ret

# --- Shared Page Renderers (used by both HTTP serve and SSG build) ---

# get_total_pages() -> rax = max(1, ceil(g_pub_count / g_cfg_per_page))
.globl get_total_pages
get_total_pages:
    mov rcx, [rip + g_cfg_per_page]
    test rcx, rcx
    jnz .Lgtp_div
    mov rcx, 6
.Lgtp_div:
    mov rax, [rip + g_pub_count]
    test rax, rax
    jz .Lgtp_one
    add rax, rcx
    dec rax
    xor edx, edx
    div rcx
    ret
.Lgtp_one:
    mov eax, 1
    ret

# render_index_page(rdi=page_num_1based) -> rax=html_ptr, rdx=html_len
.globl render_index_page
render_index_page:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 32
    mov r12, rdi
    cmp r12, 1
    jae .Lrip_p1
    mov r12, 1
.Lrip_p1:
    call ctx_reset
    lea rdi, [rip + k_page_title]; mov esi, k_page_title_len
    lea rdx, [rip + s_home_title]; mov ecx, s_home_title_len
    call ctx_set

    mov r13, [rip + g_cfg_per_page]
    call get_total_pages
    mov r14, rax
    cmp r12, r14
    jbe .Lrip_clamp_ok
    mov r12, r14
.Lrip_clamp_ok:
    mov rax, r12
    dec rax
    imul rax, r13
    mov r15, rax
    add rax, r13
    push rax

    xor ebx, ebx
    xor r8d, r8d
    xor r9d, r9d
    lea r10, [rip + g_post_ptrs]
    lea r11, [rip + cur_list_ptrs]
.Lrip_fill:
    cmp rbx, [rip + g_post_count]
    jae .Lrip_filled
    mov rcx, [r10 + rbx*8]
    cmp qword ptr [rcx + POST_DRAFT], 0
    jne .Lrip_fnext
    cmp r8, r15
    jb .Lrip_fpub
    cmp r8, [rsp]
    jae .Lrip_fpub
    mov [r11 + r9*8], rcx
    inc r9
.Lrip_fpub:
    inc r8
.Lrip_fnext:
    inc rbx
    jmp .Lrip_fill
.Lrip_filled:
    pop rax
    mov [rip + cur_list_count], r9

    mov rdi, r12; mov esi, 4; call fmt_num_slot
    push rax; push rdx; lea rdi, [rip + k_page_num]; mov esi, k_page_num_len; pop rcx; pop rdx; call ctx_set
    mov rdi, r14; mov esi, 5; call fmt_num_slot
    push rax; push rdx; lea rdi, [rip + k_total_pages]; mov esi, k_total_pages_len; pop rcx; pop rdx; call ctx_set

    # prev_page_url (trailing slash compatible with dist/page/N/index.html)
    cmp r12, 1
    jbe .Lrip_no_prev
    cmp r12, 2
    je .Lrip_prev_root
    mov rdi, rsp; lea rsi, [rip + render_url_prev]; mov edx, 127; call sb_init
    mov rdi, rsp; lea rsi, [rip + s_page_pre]; mov edx, s_page_pre_len; call sb_mem
    mov rdi, rsp; lea rsi, [r12 - 1]; call sb_uint
    mov rdi, rsp; mov esi, '/'; call sb_byte
    lea rdi, [rip + k_prev_page_url]; mov esi, k_prev_page_url_len
    lea rdx, [rip + render_url_prev]; mov rcx, [rsp + SB_LEN]; call ctx_set
    jmp .Lrip_chk_next
.Lrip_prev_root:
    lea rdi, [rip + k_prev_page_url]; mov esi, k_prev_page_url_len
    lea rdx, [rip + s_slash]; mov ecx, 1; call ctx_set
    jmp .Lrip_chk_next
.Lrip_no_prev:
    lea rdi, [rip + k_prev_page_url]; mov esi, k_prev_page_url_len; xor edx, edx; xor ecx, ecx; call ctx_set

.Lrip_chk_next:
    cmp r12, r14
    jae .Lrip_no_next
    mov rdi, rsp; lea rsi, [rip + render_url_next]; mov edx, 127; call sb_init
    mov rdi, rsp; lea rsi, [rip + s_page_pre]; mov edx, s_page_pre_len; call sb_mem
    mov rdi, rsp; lea rsi, [r12 + 1]; call sb_uint
    mov rdi, rsp; mov esi, '/'; call sb_byte
    lea rdi, [rip + k_next_page_url]; mov esi, k_next_page_url_len
    lea rdx, [rip + render_url_next]; mov rcx, [rsp + SB_LEN]; call ctx_set
    jmp .Lrip_do_render
.Lrip_no_next:
    lea rdi, [rip + k_next_page_url]; mov esi, k_next_page_url_len; xor edx, edx; xor ecx, ecx; call ctx_set

.Lrip_do_render:
    lea rdi, [rip + tpl_index]
    mov esi, tpl_index_len
    call render_with_layout
    add rsp, 32
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# render_archive_page() -> rax=ptr, rdx=len
.globl render_archive_page
render_archive_page:
    push rbx
    call ctx_reset
    lea rdi, [rip + k_page_title]; mov esi, k_page_title_len
    lea rdx, [rip + s_arch_title]; mov ecx, s_arch_title_len
    call ctx_set
    xor ebx, ebx
    xor r9d, r9d
    lea r10, [rip + g_post_ptrs]
    lea r11, [rip + cur_list_ptrs]
.Lrap_loop:
    cmp rbx, [rip + g_post_count]
    jae .Lrap_done
    mov rcx, [r10 + rbx*8]
    cmp qword ptr [rcx + POST_DRAFT], 0
    jne .Lrap_next
    mov [r11 + r9*8], rcx
    inc r9
.Lrap_next:
    inc rbx
    jmp .Lrap_loop
.Lrap_done:
    mov [rip + cur_list_count], r9
    lea rdi, [rip + tpl_archive]
    mov esi, tpl_archive_len
    call render_with_layout
    pop rbx
    ret

# render_tags_page() -> rax=ptr, rdx=len
.globl render_tags_page
render_tags_page:
    call ctx_reset
    lea rdi, [rip + k_page_title]; mov esi, k_page_title_len
    lea rdx, [rip + s_tags_title]; mov ecx, s_tags_title_len
    call ctx_set
    lea rdi, [rip + tpl_tags]
    mov esi, tpl_tags_len
    jmp render_with_layout

# render_tag_page(rdi=tag_ptr, rsi=tag_len) -> rax=ptr, rdx=len
.globl render_tag_page
render_tag_page:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi

    call ctx_reset
    lea rdi, [rip + k_page_title]; mov esi, k_page_title_len; mov rdx, r12; mov rcx, r13; call ctx_set
    lea rdi, [rip + k_active_tag]; mov esi, k_active_tag_len; mov rdx, r12; mov rcx, r13; call ctx_set

    xor ebx, ebx
    xor r14d, r14d
.Lrtp_post:
    cmp rbx, [rip + g_post_count]
    jae .Lrtp_done
    lea r8, [rip + g_post_ptrs]
    mov r9, [r8 + rbx*8]
    cmp qword ptr [r9 + POST_DRAFT], 0
    jne .Lrtp_pnext
    xor ecx, ecx
.Lrtp_tchk:
    cmp rcx, [r9 + POST_TAG_COUNT]
    jae .Lrtp_pnext
    push rcx
    push r9
    mov rdi, [r9 + POST_TAG_PTRS + rcx*8]
    mov rsi, [r9 + POST_TAG_LENS + rcx*8]
    mov rdx, r12
    mov rcx, r13
    call xslice_eq_ci
    pop r9
    pop rcx
    test eax, eax
    jnz .Lrtp_match
    inc rcx
    jmp .Lrtp_tchk
.Lrtp_match:
    lea r10, [rip + cur_list_ptrs]
    mov [r10 + r14*8], r9
    inc r14
.Lrtp_pnext:
    inc rbx
    jmp .Lrtp_post
.Lrtp_done:
    mov [rip + cur_list_count], r14
    lea rdi, [rip + tpl_tag]
    mov esi, tpl_tag_len
    call render_with_layout
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# render_category_page(rdi=cat_ptr, rsi=cat_len) -> rax=ptr, rdx=len
.globl render_category_page
render_category_page:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi

    call ctx_reset
    lea rdi, [rip + k_page_title]; mov esi, k_page_title_len; mov rdx, r12; mov rcx, r13; call ctx_set
    lea rdi, [rip + k_active_cat]; mov esi, k_active_cat_len; mov rdx, r12; mov rcx, r13; call ctx_set

    xor ebx, ebx
    xor r14d, r14d
.Lrcp_post:
    cmp rbx, [rip + g_post_count]
    jae .Lrcp_done
    lea r8, [rip + g_post_ptrs]
    mov r9, [r8 + rbx*8]
    cmp qword ptr [r9 + POST_DRAFT], 0
    jne .Lrcp_pnext
    cmp qword ptr [r9 + POST_CAT_LEN], 0
    je .Lrcp_pnext
    push r9
    mov rdi, [r9 + POST_CAT_PTR]
    mov rsi, [r9 + POST_CAT_LEN]
    mov rdx, r12
    mov rcx, r13
    call xslice_eq_ci
    pop r9
    test eax, eax
    jz .Lrcp_pnext
    lea r10, [rip + cur_list_ptrs]
    mov [r10 + r14*8], r9
    inc r14
.Lrcp_pnext:
    inc rbx
    jmp .Lrcp_post
.Lrcp_done:
    mov [rip + cur_list_count], r14
    lea rdi, [rip + tpl_category]
    mov esi, tpl_category_len
    call render_with_layout
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# render_post_page(rdi=&post, rsi=sorted_idx) -> rax=html_ptr, rdx=html_len
.globl render_post_page
render_post_page:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    call ctx_reset

    lea rdi, [rip + k_page_title]; mov esi, k_page_title_len
    mov rdx, [r12 + POST_TITLE_PTR]; mov rcx, [r12 + POST_TITLE_LEN]; call ctx_set

    mov rdi, r12
    call bind_post_vars

    lea rdi, [rip + k_content_html]; mov esi, k_content_html_len
    mov rdx, [r12 + POST_HTML_PTR]; mov rcx, [r12 + POST_HTML_LEN]; call ctx_set

    # Prev published post (newer)
    mov rbx, r13
    dec rbx
.Lrpp_prev:
    cmp rbx, 0
    jl .Lrpp_no_prev
    lea r8, [rip + g_post_ptrs]
    mov r9, [r8 + rbx*8]
    cmp qword ptr [r9 + POST_DRAFT], 0
    je .Lrpp_set_prev
    dec rbx
    jmp .Lrpp_prev
.Lrpp_set_prev:
    push r9
    lea rdi, [rip + k_prev_slug]; mov esi, k_prev_slug_len; mov rdx, [r9 + POST_SLUG_PTR]; mov rcx, [r9 + POST_SLUG_LEN]; call ctx_set
    pop r9
    lea rdi, [rip + k_prev_title]; mov esi, k_prev_title_len; mov rdx, [r9 + POST_TITLE_PTR]; mov rcx, [r9 + POST_TITLE_LEN]; call ctx_set
    jmp .Lrpp_find_next
.Lrpp_no_prev:
    lea rdi, [rip + k_prev_slug];  mov esi, k_prev_slug_len;  xor edx, edx; xor ecx, ecx; call ctx_set
    lea rdi, [rip + k_prev_title]; mov esi, k_prev_title_len; xor edx, edx; xor ecx, ecx; call ctx_set

.Lrpp_find_next:
    mov rbx, r13
    inc rbx
.Lrpp_next:
    cmp rbx, [rip + g_post_count]
    jae .Lrpp_no_next
    lea r8, [rip + g_post_ptrs]
    mov r9, [r8 + rbx*8]
    cmp qword ptr [r9 + POST_DRAFT], 0
    je .Lrpp_set_next
    inc rbx
    jmp .Lrpp_next
.Lrpp_set_next:
    push r9
    lea rdi, [rip + k_next_slug]; mov esi, k_next_slug_len; mov rdx, [r9 + POST_SLUG_PTR]; mov rcx, [r9 + POST_SLUG_LEN]; call ctx_set
    pop r9
    lea rdi, [rip + k_next_title]; mov esi, k_next_title_len; mov rdx, [r9 + POST_TITLE_PTR]; mov rcx, [r9 + POST_TITLE_LEN]; call ctx_set
    jmp .Lrpp_render
.Lrpp_no_next:
    lea rdi, [rip + k_next_slug];  mov esi, k_next_slug_len;  xor edx, edx; xor ecx, ecx; call ctx_set
    lea rdi, [rip + k_next_title]; mov esi, k_next_title_len; xor edx, edx; xor ecx, ecx; call ctx_set

.Lrpp_render:
    lea rdi, [rip + tpl_post]
    mov esi, tpl_post_len
    call render_with_layout
    pop r13
    pop r12
    pop rbx
    ret

# render_search_page(rdi=q_ptr, rsi=q_len) -> rax=ptr, rdx=len
.globl render_search_page
render_search_page:
    push rbx
    push r12
    push r13
    push r14
    call trim_ws
    mov r12, rax
    mov r13, rdx

    call ctx_reset
    lea rdi, [rip + k_page_title]; mov esi, k_page_title_len; lea rdx, [rip + s_search_title]; mov ecx, s_search_title_len; call ctx_set
    lea rdi, [rip + k_query];      mov esi, k_query_len;      mov rdx, r12; mov rcx, r13; call ctx_set

    xor ebx, ebx
    xor r14d, r14d
    mov qword ptr [rip + cur_list_count], 0
    test r13, r13
    jz .Lrsp_render
.Lrsp_loop:
    cmp rbx, [rip + g_post_count]
    jae .Lrsp_done
    lea r8, [rip + g_post_ptrs]
    mov r9, [r8 + rbx*8]
    cmp qword ptr [r9 + POST_DRAFT], 0
    jne .Lrsp_next
    push r9
    mov rdi, [r9 + POST_TITLE_PTR]; mov rsi, [r9 + POST_TITLE_LEN]; mov rdx, r12; mov rcx, r13; call xmemmem_ci
    pop r9
    test eax, eax; jnz .Lrsp_hit
    push r9
    mov rdi, [r9 + POST_SUMMARY_PTR]; mov rsi, [r9 + POST_SUMMARY_LEN]; mov rdx, r12; mov rcx, r13; call xmemmem_ci
    pop r9
    test eax, eax; jnz .Lrsp_hit
    push r9
    mov rdi, [r9 + POST_TAGS_RAW_PTR]; mov rsi, [r9 + POST_TAGS_RAW_LEN]; mov rdx, r12; mov rcx, r13; call xmemmem_ci
    pop r9
    test eax, eax; jnz .Lrsp_hit
    push r9
    mov rdi, [r9 + POST_MD_PTR]; mov rsi, [r9 + POST_MD_LEN]; mov rdx, r12; mov rcx, r13; call xmemmem_ci
    pop r9
    test eax, eax; jz .Lrsp_next
.Lrsp_hit:
    lea r10, [rip + cur_list_ptrs]
    mov [r10 + r14*8], r9
    inc r14
.Lrsp_next:
    inc rbx
    jmp .Lrsp_loop
.Lrsp_done:
    mov [rip + cur_list_count], r14
.Lrsp_render:
    lea rdi, [rip + tpl_search]
    mov esi, tpl_search_len
    call render_with_layout
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# render_search_index_json() -> rax=ptr, rdx=len (static JSON index for instant client-side search)
.globl render_search_index_json
render_search_index_json:
    push rbx
    push r12
    sub rsp, 32
    mov rdi, rsp; lea rsi, [rip + g_render_page]; mov edx, 262143; call sb_init
    mov rdi, rsp; mov esi, '['; call sb_byte
    xor ebx, ebx
    xor r12d, r12d
.Lsi_loop:
    cmp rbx, [rip + g_post_count]
    jae .Lsi_end
    lea r8, [rip + g_post_ptrs]
    mov r9, [r8 + rbx*8]
    cmp qword ptr [r9 + POST_DRAFT], 0
    jne .Lsi_next
    push r9
    test r12, r12
    jz .Lsi_first
    lea rdi, [rsp + 8]; mov esi, ','; call sb_byte
.Lsi_first:
    lea rdi, [rsp + 8]; lea rsi, [rip + si_open]; mov edx, si_open_len; call sb_mem
    mov r9, [rsp]
    lea rdi, [rsp + 8]; mov rsi, [r9 + POST_SLUG_PTR]; mov rdx, [r9 + POST_SLUG_LEN]; call sb_esc_json
    lea rdi, [rsp + 8]; lea rsi, [rip + si_title]; mov edx, si_title_len; call sb_mem
    mov r9, [rsp]
    lea rdi, [rsp + 8]; mov rsi, [r9 + POST_TITLE_PTR]; mov rdx, [r9 + POST_TITLE_LEN]; call sb_esc_json
    lea rdi, [rsp + 8]; lea rsi, [rip + si_date]; mov edx, si_date_len; call sb_mem
    mov r9, [rsp]
    lea rdi, [rsp + 8]; mov rsi, [r9 + POST_DATE_PTR]; mov rdx, [r9 + POST_DATE_LEN]; call sb_esc_json
    lea rdi, [rsp + 8]; lea rsi, [rip + si_tags]; mov edx, si_tags_len; call sb_mem
    mov r9, [rsp]
    lea rdi, [rsp + 8]; mov rsi, [r9 + POST_TAGS_RAW_PTR]; mov rdx, [r9 + POST_TAGS_RAW_LEN]; call sb_esc_json
    lea rdi, [rsp + 8]; lea rsi, [rip + si_cat]; mov edx, si_cat_len; call sb_mem
    mov r9, [rsp]
    lea rdi, [rsp + 8]; mov rsi, [r9 + POST_CAT_PTR]; mov rdx, [r9 + POST_CAT_LEN]; call sb_esc_json
    lea rdi, [rsp + 8]; lea rsi, [rip + si_cover]; mov edx, si_cover_len; call sb_mem
    mov r9, [rsp]
    lea rdi, [rsp + 8]; mov rsi, [r9 + POST_COVER_PTR]; mov rdx, [r9 + POST_COVER_LEN]; call sb_esc_json
    lea rdi, [rsp + 8]; lea rsi, [rip + si_sum]; mov edx, si_sum_len; call sb_mem
    mov r9, [rsp]
    lea rdi, [rsp + 8]; mov rsi, [r9 + POST_SUMMARY_PTR]; mov rdx, [r9 + POST_SUMMARY_LEN]; call sb_esc_json
    lea rdi, [rsp + 8]; lea rsi, [rip + si_end]; mov edx, si_end_len; call sb_mem
    pop r9
    inc r12
.Lsi_next:
    inc rbx
    jmp .Lsi_loop
.Lsi_end:
    mov rdi, rsp; mov esi, ']'; call sb_byte
    lea rax, [rip + g_render_page]
    mov rdx, [rsp + SB_LEN]
    add rsp, 32
    pop r12
    pop rbx
    ret

# render_rss_xml() -> rax=ptr, rdx=len
.globl render_rss_xml
render_rss_xml:
    push rbx
    push r12
    sub rsp, 32
    mov rdi, rsp; lea rsi, [rip + g_render_page]; mov edx, 262143; call sb_init

    mov rdi, rsp; lea rsi, [rip + rss_head_1]; mov edx, rss_head_1_len; call sb_mem
    mov rdi, rsp; lea rsi, [rip + g_cfg_site_name]; mov rdx, [rip + g_cfg_site_name_len]; call sb_esc_html
    mov rdi, rsp; lea rsi, [rip + rss_head_2]; mov edx, rss_head_2_len; call sb_mem
    mov rdi, rsp; lea rsi, [rip + g_cfg_site_url]; mov rdx, [rip + g_cfg_site_url_len]; call sb_esc_html
    mov rdi, rsp; lea rsi, [rip + rss_head_3]; mov edx, rss_head_3_len; call sb_mem
    mov rdi, rsp; lea rsi, [rip + g_cfg_subtitle]; mov rdx, [rip + g_cfg_subtitle_len]; call sb_esc_html
    mov rdi, rsp; lea rsi, [rip + rss_head_4]; mov edx, rss_head_4_len; call sb_mem

    xor ebx, ebx
    xor r12d, r12d
.Lrr_loop:
    cmp rbx, [rip + g_post_count]
    jae .Lrr_end
    cmp r12, 20
    jae .Lrr_end
    lea r8, [rip + g_post_ptrs]
    mov r9, [r8 + rbx*8]
    cmp qword ptr [r9 + POST_DRAFT], 0
    jne .Lrr_next
    push r9
    lea rdi, [rsp + 8]; lea rsi, [rip + rss_item_1]; mov edx, rss_item_1_len; call sb_mem
    mov r9, [rsp]
    lea rdi, [rsp + 8]; mov rsi, [r9 + POST_TITLE_PTR]; mov rdx, [r9 + POST_TITLE_LEN]; call sb_esc_html
    lea rdi, [rsp + 8]; lea rsi, [rip + rss_item_2]; mov edx, rss_item_2_len; call sb_mem
    lea rdi, [rsp + 8]; lea rsi, [rip + g_cfg_site_url]; mov rdx, [rip + g_cfg_site_url_len]; call sb_esc_html
    lea rdi, [rsp + 8]; lea rsi, [rip + rss_item_3]; mov edx, rss_item_3_len; call sb_mem
    mov r9, [rsp]
    lea rdi, [rsp + 8]; mov rsi, [r9 + POST_SLUG_PTR]; mov rdx, [r9 + POST_SLUG_LEN]; call sb_esc_html
    lea rdi, [rsp + 8]; lea rsi, [rip + rss_item_4]; mov edx, rss_item_4_len; call sb_mem
    lea rdi, [rsp + 8]; lea rsi, [rip + g_cfg_site_url]; mov rdx, [rip + g_cfg_site_url_len]; call sb_esc_html
    lea rdi, [rsp + 8]; lea rsi, [rip + rss_item_3]; mov edx, rss_item_3_len; call sb_mem
    mov r9, [rsp]
    lea rdi, [rsp + 8]; mov rsi, [r9 + POST_SLUG_PTR]; mov rdx, [r9 + POST_SLUG_LEN]; call sb_esc_html
    lea rdi, [rsp + 8]; lea rsi, [rip + rss_item_5]; mov edx, rss_item_5_len; call sb_mem
    mov r9, [rsp]
    lea rdi, [rsp + 8]; mov rsi, [r9 + POST_DATE_PTR]; mov rdx, [r9 + POST_DATE_LEN]; call sb_esc_html
    lea rdi, [rsp + 8]; lea rsi, [rip + rss_item_6]; mov edx, rss_item_6_len; call sb_mem
    mov r9, [rsp]
    lea rdi, [rsp + 8]; mov rsi, [r9 + POST_SUMMARY_PTR]; mov rdx, [r9 + POST_SUMMARY_LEN]; call sb_esc_html
    lea rdi, [rsp + 8]; lea rsi, [rip + rss_item_7]; mov edx, rss_item_7_len; call sb_mem
    pop r9
    inc r12
.Lrr_next:
    inc rbx
    jmp .Lrr_loop
.Lrr_end:
    mov rdi, rsp; lea rsi, [rip + rss_foot]; mov edx, rss_foot_len; call sb_mem
    lea rax, [rip + g_render_page]
    mov rdx, [rsp + SB_LEN]
    add rsp, 32
    pop r12
    pop rbx
    ret

# render_sitemap_xml() -> rax=ptr, rdx=len
.globl render_sitemap_xml
render_sitemap_xml:
    push rbx
    sub rsp, 32
    mov rdi, rsp; lea rsi, [rip + g_render_page]; mov edx, 262143; call sb_init
    mov rdi, rsp; lea rsi, [rip + sm_head]; mov edx, sm_head_len; call sb_mem
    mov rdi, rsp; lea rsi, [rip + sm_u1]; mov edx, sm_u1_len; call sb_mem
    mov rdi, rsp; lea rsi, [rip + g_cfg_site_url]; mov rdx, [rip + g_cfg_site_url_len]; call sb_esc_html
    mov rdi, rsp; lea rsi, [rip + s_slash]; mov edx, 1; call sb_mem
    mov rdi, rsp; lea rsi, [rip + sm_u2]; mov edx, sm_u2_len; call sb_mem

    xor ebx, ebx
.Lsm_loop:
    cmp rbx, [rip + g_post_count]
    jae .Lsm_end
    lea r8, [rip + g_post_ptrs]
    mov r9, [r8 + rbx*8]
    cmp qword ptr [r9 + POST_DRAFT], 0
    jne .Lsm_next
    push r9
    lea rdi, [rsp + 8]; lea rsi, [rip + sm_u1]; mov edx, sm_u1_len; call sb_mem
    lea rdi, [rsp + 8]; lea rsi, [rip + g_cfg_site_url]; mov rdx, [rip + g_cfg_site_url_len]; call sb_esc_html
    lea rdi, [rsp + 8]; lea rsi, [rip + rss_item_3]; mov edx, rss_item_3_len; call sb_mem
    mov r9, [rsp]
    lea rdi, [rsp + 8]; mov rsi, [r9 + POST_SLUG_PTR]; mov rdx, [r9 + POST_SLUG_LEN]; call sb_esc_html
    lea rdi, [rsp + 8]; lea rsi, [rip + sm_u_lm]; mov edx, sm_u_lm_len; call sb_mem
    mov r9, [rsp]
    lea rdi, [rsp + 8]; mov rsi, [r9 + POST_DATE_PTR]; mov rdx, [r9 + POST_DATE_LEN]; call sb_esc_html
    lea rdi, [rsp + 8]; lea rsi, [rip + sm_u_end]; mov edx, sm_u_end_len; call sb_mem
    pop r9
.Lsm_next:
    inc rbx
    jmp .Lsm_loop
.Lsm_end:
    mov rdi, rsp; lea rsi, [rip + sm_foot]; mov edx, sm_foot_len; call sb_mem
    lea rax, [rip + g_render_page]
    mov rdx, [rsp + SB_LEN]
    add rsp, 32
    pop rbx
    ret

# render_404_page() -> rax=ptr, rdx=len
.globl render_404_page
render_404_page:
    call ctx_reset
    lea rdi, [rip + k_page_title]; mov esi, k_page_title_len
    lea rdx, [rip + s_404_title];  mov ecx, s_404_title_len
    call ctx_set
    lea rdi, [rip + tpl_404]
    mov esi, tpl_404_len
    call store_find_tpl
    test rax, rax
    jz .Lr404_fb
    lea rdi, [rip + tpl_404]
    mov esi, tpl_404_len
    jmp render_with_layout
.Lr404_fb:
    lea rax, [rip + fallback_404]
    mov edx, fallback_404_len
    ret

# --- Read-Only HTTP Handlers ---

.globl handle_index
handle_index:
    push r12
    mov r12, rdi
    mov edi, 1
    call render_index_page
    mov rdi, r12
    mov rsi, rax
    call send_html_200
    pop r12
    ret

.globl handle_page
handle_page:
    push r12
    mov r12, rdi
    mov rdi, [rsi + REQ_PARAM_PTR]
    mov rsi, [rsi + REQ_PARAM_LEN]
    call parse_uint
    test edx, edx
    jz .Lhp_404
    test rax, rax
    jz .Lhp_404
    mov rdi, rax
    call render_index_page
    mov rdi, r12
    mov rsi, rax
    call send_html_200
    pop r12
    ret
.Lhp_404:
    mov rdi, r12
    xor esi, esi
    call handle_not_found
    pop r12
    ret

.globl handle_post
handle_post:
    push r12
    mov r12, rdi
    mov rdi, [rsi + REQ_PARAM_PTR]
    mov rsi, [rsi + REQ_PARAM_LEN]
    xor edx, edx
    call store_find_post
    test rax, rax
    jz .Lhpo_404
    mov rdi, rax
    mov rsi, rdx
    call render_post_page
    mov rdi, r12
    mov rsi, rax
    call send_html_200
    pop r12
    ret
.Lhpo_404:
    mov rdi, r12
    xor esi, esi
    call handle_not_found
    pop r12
    ret

.globl handle_archive
handle_archive:
    push r12
    mov r12, rdi
    call render_archive_page
    mov rdi, r12
    mov rsi, rax
    call send_html_200
    pop r12
    ret

.globl handle_tags
handle_tags:
    push r12
    mov r12, rdi
    call render_tags_page
    mov rdi, r12
    mov rsi, rax
    call send_html_200
    pop r12
    ret

.globl handle_tag
handle_tag:
    push r12
    push r13
    sub rsp, 32
    mov r12, rdi
    mov r13, rsi
    mov rdi, rsp; lea rsi, [rip + render_q_buf]; mov edx, 511; call sb_init
    mov rdi, rsp; mov rsi, [r13 + REQ_PARAM_PTR]; mov rdx, [r13 + REQ_PARAM_LEN]; call sb_url_decode
    lea rdi, [rip + render_q_buf]
    mov rsi, [rsp + SB_LEN]
    call render_tag_page
    mov rdi, r12
    mov rsi, rax
    call send_html_200
    add rsp, 32
    pop r13
    pop r12
    ret

.globl handle_category
handle_category:
    push r12
    push r13
    sub rsp, 32
    mov r12, rdi
    mov r13, rsi
    mov rdi, rsp; lea rsi, [rip + render_q_buf]; mov edx, 511; call sb_init
    mov rdi, rsp; mov rsi, [r13 + REQ_PARAM_PTR]; mov rdx, [r13 + REQ_PARAM_LEN]; call sb_url_decode
    lea rdi, [rip + render_q_buf]
    mov rsi, [rsp + SB_LEN]
    call render_category_page
    mov rdi, r12
    mov rsi, rax
    call send_html_200
    add rsp, 32
    pop r13
    pop r12
    ret

.globl handle_search
handle_search:
    push r12
    push r13
    sub rsp, 32
    mov r12, rdi
    mov r13, rsi
    mov rdi, rsp; lea rsi, [rip + render_q_buf]; mov edx, 511; call sb_init
    mov rdi, r13; lea rsi, [rip + s_q_key]; mov edx, 1; mov rcx, rsp; call http_query_get
    lea rdi, [rip + render_q_buf]
    mov rsi, [rsp + SB_LEN]
    call render_search_page
    mov rdi, r12
    mov rsi, rax
    call send_html_200
    add rsp, 32
    pop r13
    pop r12
    ret

.globl handle_search_index
handle_search_index:
    push r12
    mov r12, rdi
    call render_search_index_json
    mov rdi, r12
    mov rsi, rax
    lea rcx, [rip + ct_json]
    call send_200_ct
    pop r12
    ret

.globl handle_rss
handle_rss:
    push r12
    mov r12, rdi
    call render_rss_xml
    mov rdi, r12
    mov rsi, rax
    lea rcx, [rip + ct_rss]
    call send_200_ct
    pop r12
    ret

.globl handle_sitemap
handle_sitemap:
    push r12
    mov r12, rdi
    call render_sitemap_xml
    mov rdi, r12
    mov rsi, rax
    lea rcx, [rip + ct_xml]
    call send_200_ct
    pop r12
    ret

.globl handle_healthz
handle_healthz:
    push r12
    sub rsp, 32
    mov r12, rdi
    mov rdi, rsp; lea rsi, [rip + g_render_page]; mov edx, 4095; call sb_init
    mov rdi, rsp; lea rsi, [rip + hz_1]; mov edx, hz_1_len; call sb_mem
    mov rdi, rsp; mov rsi, [rip + g_post_count]; call sb_uint
    mov rdi, rsp; lea rsi, [rip + hz_2]; mov edx, hz_2_len; call sb_mem
    mov rdi, rsp; mov rsi, [rip + g_pub_count]; call sb_uint
    mov rdi, rsp; lea rsi, [rip + hz_3]; mov edx, hz_3_len; call sb_mem
    mov rdi, rsp; mov rsi, [rip + g_tag_count]; call sb_uint
    mov rdi, rsp; lea rsi, [rip + hz_4]; mov edx, hz_4_len; call sb_mem
    mov rdi, rsp; mov rsi, [rip + g_reload_count]; call sb_uint
    mov rdi, rsp; lea rsi, [rip + hz_5]; mov edx, hz_5_len; call sb_mem
    mov rdi, rsp; mov rsi, [rip + g_arena_used]; call sb_uint
    mov rdi, rsp; lea rsi, [rip + hz_6]; mov edx, hz_6_len; call sb_mem
    call mono_sec
    sub rax, [rip + g_start_sec]
    mov rdi, rsp; mov rsi, rax; call sb_uint
    mov rdi, rsp; lea rsi, [rip + hz_7]; mov edx, hz_7_len; call sb_mem
    mov rdi, rsp; mov rsi, [rip + g_active_conns]; call sb_uint
    mov rdi, rsp; lea rsi, [rip + hz_8]; mov edx, hz_8_len; call sb_mem

    mov rdi, r12
    lea rsi, [rip + g_render_page]
    mov rdx, [rsp + SB_LEN]
    lea rcx, [rip + ct_json]
    call send_200_ct
    add rsp, 32
    pop r12
    ret

.globl handle_not_found
handle_not_found:
    push r12
    mov r12, rdi
    call render_404_page
    mov r8, rdx
    mov rcx, rax
    mov rdi, r12
    lea rsi, [rip + st_404]
    lea rdx, [rip + ct_html]
    xor r9d, r9d
    call http_send_resp
    pop r12
    ret
