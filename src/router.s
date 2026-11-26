.include "defs.inc"

# Declarative Route Table & Pattern Matcher
# Public routes (read-only) + Hidden Author Studio (/studio & /api/studio/*)

.section .rodata
pat_root:          .ascii "/"
.equ pat_root_len, . - pat_root
pat_page:          .ascii "/page/:n"
.equ pat_page_len, . - pat_page
pat_post:          .ascii "/post/:slug"
.equ pat_post_len, . - pat_post
pat_archive:       .ascii "/archive"
.equ pat_archive_len, . - pat_archive
pat_tags:          .ascii "/tags"
.equ pat_tags_len, . - pat_tags
pat_tag:           .ascii "/tag/:name"
.equ pat_tag_len, . - pat_tag
pat_category:      .ascii "/category/:name"
.equ pat_category_len, . - pat_category
pat_search:        .ascii "/search"
.equ pat_search_len, . - pat_search
pat_gallery:       .ascii "/gallery"
.equ pat_gallery_len, . - pat_gallery
pat_about:         .ascii "/about"
.equ pat_about_len, . - pat_about
pat_gallery_json:  .ascii "/gallery.json"
.equ pat_gallery_json_len, . - pat_gallery_json
pat_about_json:    .ascii "/about.json"
.equ pat_about_json_len, . - pat_about_json
pat_bgm_json:      .ascii "/bgm.json"
.equ pat_bgm_json_len, . - pat_bgm_json
pat_search_idx:    .ascii "/search-index.json"
.equ pat_search_idx_len, . - pat_search_idx
pat_rss:           .ascii "/rss.xml"
.equ pat_rss_len, . - pat_rss
pat_sitemap:       .ascii "/sitemap.xml"
.equ pat_sitemap_len, . - pat_sitemap
pat_healthz:       .ascii "/healthz"
.equ pat_healthz_len, . - pat_healthz
pat_static:        .ascii "/static/*path"
.equ pat_static_len, . - pat_static
pat_uploads:       .ascii "/uploads/*path"
.equ pat_uploads_len, . - pat_uploads
pat_favicon:       .ascii "/favicon.ico"
.equ pat_favicon_len, . - pat_favicon

# Hidden Author Studio API routes (entry page matched dynamically via g_cfg_studio_path)
pat_st_login:      .ascii "/api/studio/login"
.equ pat_st_login_len, . - pat_st_login
pat_st_logout:     .ascii "/api/studio/logout"
.equ pat_st_logout_len, . - pat_st_logout
pat_st_posts:      .ascii "/api/studio/posts"
.equ pat_st_posts_len, . - pat_st_posts
pat_st_post_one:   .ascii "/api/studio/posts/:slug"
.equ pat_st_post_one_len, . - pat_st_post_one
pat_st_cats:       .ascii "/api/studio/categories"
.equ pat_st_cats_len, . - pat_st_cats
pat_st_cats_del:   .ascii "/api/studio/categories/delete"
.equ pat_st_cats_del_len, . - pat_st_cats_del
pat_st_upload:     .ascii "/api/studio/upload"
.equ pat_st_upload_len, . - pat_st_upload
pat_st_up_vid:     .ascii "/api/studio/upload-video"
.equ pat_st_up_vid_len, . - pat_st_up_vid
pat_st_up_aud:     .ascii "/api/studio/upload-audio"
.equ pat_st_up_aud_len, . - pat_st_up_aud
pat_st_settings:   .ascii "/api/studio/settings"
.equ pat_st_settings_len, . - pat_st_settings
pat_st_gallery:    .ascii "/api/studio/gallery"
.equ pat_st_gallery_len, . - pat_st_gallery
pat_st_about:      .ascii "/api/studio/about"
.equ pat_st_about_len, . - pat_st_about
pat_st_bgm:        .ascii "/api/studio/bgm"
.equ pat_st_bgm_len, . - pat_st_bgm
pat_st_media:      .ascii "/api/studio/media"
.equ pat_st_media_len, . - pat_st_media
pat_st_media_del:  .ascii "/api/studio/media/delete"
.equ pat_st_media_del_len, . - pat_st_media_del

.align 8
route_table:
    .quad METH_GET,    pat_root,        pat_root_len,        handle_index,              0
    .quad METH_GET,    pat_page,        pat_page_len,        handle_page,               0
    .quad METH_GET,    pat_post,        pat_post_len,        handle_post,               0
    .quad METH_GET,    pat_archive,     pat_archive_len,     handle_archive,            0
    .quad METH_GET,    pat_tags,        pat_tags_len,        handle_tags,               0
    .quad METH_GET,    pat_tag,         pat_tag_len,         handle_tag,                0
    .quad METH_GET,    pat_category,    pat_category_len,    handle_category,           0
    .quad METH_GET,    pat_search,      pat_search_len,      handle_search,             0
    .quad METH_GET,    pat_gallery,     pat_gallery_len,     handle_gallery,            0
    .quad METH_GET,    pat_about,       pat_about_len,       handle_about,              0
    .quad METH_GET,    pat_gallery_json, pat_gallery_json_len, handle_gallery_json,     0
    .quad METH_GET,    pat_about_json,  pat_about_json_len,  handle_about_json,         0
    .quad METH_GET,    pat_bgm_json,    pat_bgm_json_len,    handle_bgm_json,           0
    .quad METH_GET,    pat_search_idx,  pat_search_idx_len,  handle_search_index,       0
    .quad METH_GET,    pat_rss,         pat_rss_len,         handle_rss,                0
    .quad METH_GET,    pat_sitemap,     pat_sitemap_len,     handle_sitemap,            0
    .quad METH_GET,    pat_healthz,     pat_healthz_len,     handle_healthz,            0
    .quad METH_GET,    pat_static,      pat_static_len,      handle_static,             0
    .quad METH_GET,    pat_uploads,     pat_uploads_len,     handle_upload_file,        0
    .quad METH_GET,    pat_favicon,     pat_favicon_len,     handle_favicon,            0
    .quad METH_POST,   pat_st_login,    pat_st_login_len,    handle_studio_login,       0
    .quad METH_POST,   pat_st_logout,   pat_st_logout_len,   handle_studio_logout,      0
    .quad METH_GET,    pat_st_posts,    pat_st_posts_len,    handle_studio_posts_list,  0
    .quad METH_POST,   pat_st_posts,    pat_st_posts_len,    handle_studio_post_save,   0
    .quad METH_GET,    pat_st_post_one, pat_st_post_one_len, handle_studio_post_get,    0
    .quad METH_DELETE, pat_st_post_one, pat_st_post_one_len, handle_studio_post_del,    0
    .quad METH_GET,    pat_st_cats,     pat_st_cats_len,     handle_studio_cats_list,   0
    .quad METH_POST,   pat_st_cats,     pat_st_cats_len,     handle_studio_cat_add,     0
    .quad METH_POST,   pat_st_cats_del, pat_st_cats_del_len, handle_studio_cat_del,     0
    .quad METH_POST,   pat_st_upload,   pat_st_upload_len,   handle_studio_upload,       0
    .quad METH_POST,   pat_st_up_vid,   pat_st_up_vid_len,   handle_studio_upload_video, 0
    .quad METH_POST,   pat_st_up_aud,   pat_st_up_aud_len,   handle_studio_upload_video, 0
    .quad METH_GET,    pat_st_settings, pat_st_settings_len, handle_studio_settings_get, 0
    .quad METH_POST,   pat_st_settings, pat_st_settings_len, handle_studio_settings_save, 0
    .quad METH_POST,   pat_st_gallery,  pat_st_gallery_len,  handle_studio_gallery_save, 0
    .quad METH_POST,   pat_st_about,    pat_st_about_len,    handle_studio_about_save,   0
    .quad METH_POST,   pat_st_bgm,      pat_st_bgm_len,      handle_studio_bgm_save,     0
    .quad METH_GET,    pat_st_media,    pat_st_media_len,    handle_studio_media_list,   0
    .quad METH_POST,   pat_st_media_del, pat_st_media_del_len, handle_studio_media_del,  0
    .quad 0, 0, 0, 0, 0

msg_405: .asciz "405 Method Not Allowed"

.section .text

match_pattern:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    mov rbx, r8

    mov qword ptr [rbx + REQ_PARAM_PTR], 0
    mov qword ptr [rbx + REQ_PARAM_LEN], 0

    xor r8d, r8d
    xor r9d, r9d

.Lmp_loop:
    cmp r8, r13
    jae .Lmp_pat_end
    movzx eax, byte ptr [r12 + r8]
    cmp al, '*'
    je .Lmp_wild
    cmp al, ':'
    je .Lmp_param
    cmp r9, r15
    jae .Lmp_no
    cmp al, [r14 + r9]
    jne .Lmp_no
    inc r8
    inc r9
    jmp .Lmp_loop

.Lmp_wild:
    mov rax, r15
    sub rax, r9
    jbe .Lmp_no
    lea rcx, [r14 + r9]
    mov [rbx + REQ_PARAM_PTR], rcx
    mov [rbx + REQ_PARAM_LEN], rax
    mov eax, 1
    jmp .Lmp_ret

.Lmp_param:
    inc r8
.Lmp_pskip:
    cmp r8, r13
    jae .Lmp_pcap
    cmp byte ptr [r12 + r8], '/'
    je .Lmp_pcap
    inc r8
    jmp .Lmp_pskip
.Lmp_pcap:
    mov r10, r9
.Lmp_qscan:
    cmp r9, r15
    jae .Lmp_qgot
    cmp byte ptr [r14 + r9], '/'
    je .Lmp_qgot
    inc r9
    jmp .Lmp_qscan
.Lmp_qgot:
    mov rax, r9
    sub rax, r10
    jz .Lmp_no
    lea rcx, [r14 + r10]
    mov [rbx + REQ_PARAM_PTR], rcx
    mov [rbx + REQ_PARAM_LEN], rax
    jmp .Lmp_loop

.Lmp_pat_end:
    cmp r9, r15
    jne .Lmp_no
    mov eax, 1
    jmp .Lmp_ret

.Lmp_no:
    xor eax, eax
.Lmp_ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.globl router_dispatch
router_dispatch:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    xor r14d, r14d

    mov r15, [r13 + REQ_METHOD]
    cmp r15, METH_HEAD
    jne .Lrd_norm_slash
    mov r15, METH_GET

.Lrd_norm_slash:
    mov rcx, [r13 + REQ_PATH_LEN]
    cmp rcx, 1
    jbe .Lrd_start
    mov rax, [r13 + REQ_PATH_PTR]
    cmp byte ptr [rax + rcx - 1], '/'
    jne .Lrd_start
    dec rcx
    mov [r13 + REQ_PATH_LEN], rcx

.Lrd_start:
    lea rbx, [rip + route_table]
.Lrd_loop:
    mov rax, [rbx + RT_HANDLER]
    test rax, rax
    jz .Lrd_not_found
    mov rdi, [rbx + RT_PAT_PTR]
    mov rsi, [rbx + RT_PAT_LEN]
    mov rdx, [r13 + REQ_PATH_PTR]
    mov rcx, [r13 + REQ_PATH_LEN]
    mov r8, r13
    call match_pattern
    test eax, eax
    jz .Lrd_next
    cmp [rbx + RT_METHOD], r15
    je .Lrd_invoke
    mov r14d, 1
.Lrd_next:
    add rbx, RT_SIZE
    jmp .Lrd_loop

.Lrd_invoke:
    mov rdi, r12
    mov rsi, r13
    mov rax, [rbx + RT_HANDLER]
    call rax
    jmp .Lrd_done

.Lrd_not_found:
    # Dynamic match for configurable hidden studio path (e.g. /studio or custom studio_path)
    mov rcx, [rip + g_cfg_studio_path_len]
    test rcx, rcx
    jz .Lrd_really_404
    mov rdi, [r13 + REQ_PATH_PTR]
    mov rsi, [r13 + REQ_PATH_LEN]
    lea rdx, [rip + g_cfg_studio_path]
    call xslice_eq
    test eax, eax
    jz .Lrd_really_404
    cmp r15, METH_GET
    jne .Lrd_studio_405
    mov rdi, r12
    mov rsi, r13
    call handle_studio_page
    jmp .Lrd_done
.Lrd_studio_405:
    mov r14d, 1

.Lrd_really_404:
    test r14d, r14d
    jnz .Lrd_405
    mov rdi, r12
    mov rsi, r13
    call handle_not_found
    jmp .Lrd_done
.Lrd_405:
    mov rdi, r12
    lea rsi, [rip + st_405]
    lea rdx, [rip + msg_405]
    call http_send_error
.Lrd_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
