.include "defs.inc"

# Hidden Single-Author Studio Backend (/studio & /api/studio/*)
# Pure x86-64 assembly: SHA-256 cookie/Bearer auth, post CRUD, category CRUD, magic-byte image upload.

.equ MAX_SESSIONS,   16
.equ SESS_SIZE,      72       # 64-byte ASCII hex token + 8-byte monotonic expire sec
.equ SESS_TTL_SEC,   2592000  # 30 days
.equ MAX_VIDEO_BYTES, 104857600  # 100 MiB max chunked video upload

.section .bss
.align 8
st_resp_buf:    .skip 262144
st_file_buf:    .skip 262144
st_hdr_buf:     .skip 512
st_path_buf:    .skip 512
st_tmp_buf:     .skip 512
st_hash_buf:    .skip 65
st_date_buf:    .skip 16
st_rand_buf:    .skip 8

# Random session tokens & brute-force login limiter
g_sessions:          .skip MAX_SESSIONS * SESS_SIZE
g_sess_next:         .quad 0
g_sess_rand32:       .skip 32
g_sess_hex64:        .skip 64
g_login_fail_cnt:    .quad 0
g_login_lock_until:  .quad 0

st_f_title:     .skip 512
st_f_slug:      .skip 256
st_f_date:      .skip 64
st_f_cat:       .skip 256
st_f_tags:      .skip 512
st_f_summary:   .skip 1024
st_f_cover:     .skip 512
st_f_draft:     .skip 32
st_f_content:   .skip 196608
st_f_pass:      .skip 256
st_f_name:      .skip 256
st_s_site_name: .skip 256
st_s_subtitle:  .skip 512
st_s_author:    .skip 256
st_s_footer:    .skip 512
st_s_site_url:  .skip 512
st_s_avatar:    .skip 512
st_s_banner:    .skip 512
st_s_spath:     .skip 128
st_s_perpage:   .skip 32
st_s_newpass:   .skip 256
st_s_newhash:   .skip 65
st_s_g_repo:    .skip 128
st_s_g_rid:     .skip 128
st_s_g_cat:     .skip 128
st_s_g_cid:     .skip 128

.section .rodata
st_tpl_name:    .ascii "studio"
.equ st_tpl_name_len, . - st_tpl_name

st_ck_name:     .ascii "asmblog_studio"
.equ st_ck_name_len, . - st_ck_name

st_bearer_pre:  .ascii "Bearer "
.equ st_bearer_pre_len, . - st_bearer_pre

hdr_nostore:    .asciz "\r\nCache-Control: no-store"
hdr_retry60:    .asciz "\r\nCache-Control: no-store\r\nRetry-After: 60"
hdr_setck_1:    .ascii "\r\nCache-Control: no-store\r\nSet-Cookie: asmblog_studio="
.equ hdr_setck_1_len, . - hdr_setck_1
hdr_setck_2:    .ascii "; Path=/; HttpOnly; SameSite=Lax; Max-Age=2592000"
.equ hdr_setck_2_len, . - hdr_setck_2
hdr_setck_sec:  .ascii "; Secure"
.equ hdr_setck_sec_len, . - hdr_setck_sec
hdr_clrck_1:    .ascii "\r\nCache-Control: no-store\r\nSet-Cookie: asmblog_studio=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0"
.equ hdr_clrck_1_len, . - hdr_clrck_1
s_https_pre:    .ascii "https://"
.equ s_https_pre_len, . - s_https_pre

# JSON keys
jk_pass:        .ascii "password"
.equ jk_pass_len, . - jk_pass
jk_title:       .ascii "title"
.equ jk_title_len, . - jk_title
jk_slug:        .ascii "slug"
.equ jk_slug_len, . - jk_slug
jk_date:        .ascii "date"
.equ jk_date_len, . - jk_date
jk_cat:         .ascii "category"
.equ jk_cat_len, . - jk_cat
jk_tags:        .ascii "tags"
.equ jk_tags_len, . - jk_tags
jk_summary:     .ascii "summary"
.equ jk_summary_len, . - jk_summary
jk_cover:       .ascii "cover"
.equ jk_cover_len, . - jk_cover
jk_draft:       .ascii "draft"
.equ jk_draft_len, . - jk_draft
jk_content:     .ascii "content"
.equ jk_content_len, . - jk_content
jk_name:        .ascii "name"
.equ jk_name_len, . - jk_name
jk_site_name:   .ascii "site_name"
.equ jk_site_name_len, . - jk_site_name
jk_subtitle:    .ascii "subtitle"
.equ jk_subtitle_len, . - jk_subtitle
jk_author:      .ascii "author"
.equ jk_author_len, . - jk_author
jk_footer:      .ascii "footer_text"
.equ jk_footer_len, . - jk_footer
jk_site_url:    .ascii "site_url"
.equ jk_site_url_len, . - jk_site_url
jk_avatar:      .ascii "avatar_url"
.equ jk_avatar_len, . - jk_avatar
jk_banner:      .ascii "banner_url"
.equ jk_banner_len, . - jk_banner
jk_spath:       .ascii "studio_path"
.equ jk_spath_len, . - jk_spath
jk_per_page:    .ascii "per_page"
.equ jk_per_page_len, . - jk_per_page
jk_new_pass:    .ascii "new_password"
.equ jk_new_pass_len, . - jk_new_pass
jk_g_repo:      .ascii "giscus_repo"
.equ jk_g_repo_len, . - jk_g_repo
jk_g_rid:       .ascii "giscus_repo_id"
.equ jk_g_rid_len, . - jk_g_rid
jk_g_cat:       .ascii "giscus_category"
.equ jk_g_cat_len, . - jk_g_cat
jk_g_cid:       .ascii "giscus_category_id"
.equ jk_g_cid_len, . - jk_g_cid
jv_true:        .ascii "true"
.equ jv_true_len, . - jv_true
jv_one:         .ascii "1"
.equ jv_one_len, . - jv_one

# JSON response literals
j_ok:           .ascii "{\"ok\":true}"
.equ j_ok_len, . - j_ok
j_ok_exists:    .ascii "{\"ok\":true,\"exists\":true}"
.equ j_ok_exists_len, . - j_ok_exists
j_ok_slug_1:    .ascii "{\"ok\":true,\"slug\":\""
.equ j_ok_slug_1_len, . - j_ok_slug_1
j_ok_url_1:     .ascii "{\"ok\":true,\"url\":\"/uploads/"
.equ j_ok_url_1_len, . - j_ok_url_1
j_ok_id_1:      .ascii "{\"ok\":true,\"id\":\""
.equ j_ok_id_1_len, . - j_ok_id_1
j_ok_spath_1:   .ascii "{\"ok\":true,\"studio_path\":\""
.equ j_ok_spath_1_len, . - j_ok_spath_1
j_close_obj:    .ascii "\"}"
.equ j_close_obj_len, . - j_close_obj

j_err_unauth:   .ascii "{\"error\":\"请先输入口令解锁后台\"}"
.equ j_err_unauth_len, . - j_err_unauth
j_err_nocfg:    .ascii "{\"error\":\"服务器尚未配置 studio_pass_sha256（请运行 asmblog hash-pass 生成）\"}"
.equ j_err_nocfg_len, . - j_err_nocfg
j_err_nopass:   .ascii "{\"error\":\"请输入口令\"}"
.equ j_err_nopass_len, . - j_err_nopass
j_err_badpass:  .ascii "{\"error\":\"口令不对，再试一次吧\"}"
.equ j_err_badpass_len, . - j_err_badpass
j_err_locked:   .ascii "{\"error\":\"口令输错次数过多，请 60 秒后再试\"}"
.equ j_err_locked_len, . - j_err_locked
j_err_url:      .ascii "{\"error\":\"图片或站点链接地址不合法\"}"
.equ j_err_url_len, . - j_err_url
j_err_spath:    .ascii "{\"error\":\"后台路径必须以 / 开头，且仅含字母、数字、- 和 _\"}"
.equ j_err_spath_len, . - j_err_spath
j_err_shortpw:  .ascii "{\"error\":\"新口令长度至少需要 4 个字符\"}"
.equ j_err_shortpw_len, . - j_err_shortpw
j_err_slug:     .ascii "{\"error\":\"文章链接(slug)仅支持字母、数字、- 和 _\"}"
.equ j_err_slug_len, . - j_err_slug
j_err_title:    .ascii "{\"error\":\"文章标题不能为空\"}"
.equ j_err_title_len, . - j_err_title
j_err_cover:    .ascii "{\"error\":\"封面图地址不合法\"}"
.equ j_err_cover_len, . - j_err_cover
j_err_notfound: .ascii "{\"error\":\"文章不存在\"}"
.equ j_err_notfound_len, . - j_err_notfound
j_err_write:    .ascii "{\"error\":\"文件写入失败\"}"
.equ j_err_write_len, . - j_err_write
j_err_cat:      .ascii "{\"error\":\"分类名称不合法（1-60字节，不能含 / 或特殊控制字符）\"}"
.equ j_err_cat_len, . - j_err_cat
j_err_catmax:   .ascii "{\"error\":\"分类数量已达上限\"}"
.equ j_err_catmax_len, . - j_err_catmax
j_err_imgsize:  .ascii "{\"error\":\"图片大小无效（最大约 3.8MB）\"}"
.equ j_err_imgsize_len, . - j_err_imgsize
j_err_imgtype:  .ascii "{\"error\":\"仅支持 JPG / PNG / GIF / WebP 图片\"}"
.equ j_err_imgtype_len, . - j_err_imgtype
j_err_vidtype:  .ascii "{\"error\":\"仅支持 MP4 / WebM / MOV / OGG 视频\"}"
.equ j_err_vidtype_len, . - j_err_vidtype
j_err_vidsize:  .ascii "{\"error\":\"视频大小超过 100MB 限制或分片无效\"}"
.equ j_err_vidsize_len, . - j_err_vidsize
j_err_vidid:    .ascii "{\"error\":\"无效的视频上传会话，请重试\"}"
.equ j_err_vidid_len, . - j_err_vidid
st_msg_404:     .asciz "404 Not Found"

# JSON serialization fragments
jp_1:           .ascii "{\"slug\":\""
.equ jp_1_len, . - jp_1
jp_2:           .ascii "\",\"title\":\""
.equ jp_2_len, . - jp_2
jp_3:           .ascii "\",\"date\":\""
.equ jp_3_len, . - jp_3
jp_4:           .ascii "\",\"category\":\""
.equ jp_4_len, . - jp_4
jp_5:           .ascii "\",\"tags\":\""
.equ jp_5_len, . - jp_5
jp_6:           .ascii "\",\"cover\":\""
.equ jp_6_len, . - jp_6
jp_7:           .ascii "\",\"summary\":\""
.equ jp_7_len, . - jp_7
jp_8:           .ascii "\",\"draft\":"
.equ jp_8_len, . - jp_8
jp_true:        .ascii "true"
.equ jp_true_len, . - jp_true
jp_false:       .ascii "false"
.equ jp_false_len, . - jp_false
jp_9_content:   .ascii ",\"content\":\""
.equ jp_9_content_len, . - jp_9_content

jc_1:           .ascii "{\"name\":\""
.equ jc_1_len, . - jc_1
jc_2:           .ascii "\",\"count\":"
.equ jc_2_len, . - jc_2

# Settings JSON serialization fragments
js_1:           .ascii "{\"site_name\":\""
.equ js_1_len, . - js_1
js_2:           .ascii "\",\"subtitle\":\""
.equ js_2_len, . - js_2
js_3:           .ascii "\",\"author\":\""
.equ js_3_len, . - js_3
js_4:           .ascii "\",\"footer_text\":\""
.equ js_4_len, . - js_4
js_5:           .ascii "\",\"site_url\":\""
.equ js_5_len, . - js_5
js_6:           .ascii "\",\"avatar_url\":\""
.equ js_6_len, . - js_6
js_7:           .ascii "\",\"banner_url\":\""
.equ js_7_len, . - js_7
js_8:           .ascii "\",\"studio_path\":\""
.equ js_8_len, . - js_8
js_9:           .ascii "\",\"per_page\":"
.equ js_9_len, . - js_9
js_10:          .ascii ",\"giscus_repo\":\""
.equ js_10_len, . - js_10
js_11:          .ascii "\",\"giscus_repo_id\":\""
.equ js_11_len, . - js_11
js_12:          .ascii "\",\"giscus_category\":\""
.equ js_12_len, . - js_12
js_13:          .ascii "\",\"giscus_category_id\":\""
.equ js_13_len, . - js_13

# config.ini writer fragments
ci_head:        .ascii "# AsmBlog Configuration\nsite_name = "
.equ ci_head_len, . - ci_head
ci_sub:         .ascii "\nsubtitle = "
.equ ci_sub_len, . - ci_sub
ci_url:         .ascii "\nsite_url = "
.equ ci_url_len, . - ci_url
ci_author:      .ascii "\nauthor = "
.equ ci_author_len, . - ci_author
ci_footer:      .ascii "\nfooter_text = "
.equ ci_footer_len, . - ci_footer
ci_avatar:      .ascii "\navatar_url = "
.equ ci_avatar_len, . - ci_avatar
ci_banner:      .ascii "\nbanner_url = "
.equ ci_banner_len, . - ci_banner
ci_port:        .ascii "\nport = "
.equ ci_port_len, . - ci_port
ci_pp:          .ascii "\nper_page = "
.equ ci_pp_len, . - ci_pp
ci_theme:       .ascii "\ntheme = "
.equ ci_theme_len, . - ci_theme
ci_dist:        .ascii "\ndist_dir = "
.equ ci_dist_len, . - ci_dist
ci_spath:       .ascii "\nstudio_path = "
.equ ci_spath_len, . - ci_spath
ci_shash:       .ascii "\nstudio_pass_sha256 = "
.equ ci_shash_len, . - ci_shash
ci_g_repo:      .ascii "\ngiscus_repo = "
.equ ci_g_repo_len, . - ci_g_repo
ci_g_rid:       .ascii "\ngiscus_repo_id = "
.equ ci_g_rid_len, . - ci_g_rid
ci_g_cat:       .ascii "\ngiscus_category = "
.equ ci_g_cat_len, . - ci_g_cat
ci_g_cid:       .ascii "\ngiscus_category_id = "
.equ ci_g_cid_len, . - ci_g_cid
st_def_cfg:     .asciz "config.ini"

# Front-Matter fragments
fm_s_1:         .ascii "---\ntitle: \""
.equ fm_s_1_len, . - fm_s_1
fm_s_slug:      .ascii "\"\nslug: "
.equ fm_s_slug_len, . - fm_s_slug
fm_s_date:      .ascii "\ndate: "
.equ fm_s_date_len, . - fm_s_date
fm_s_cat:       .ascii "\ncategory: \""
.equ fm_s_cat_len, . - fm_s_cat
fm_s_tags:      .ascii "\ntags: "
.equ fm_s_tags_len, . - fm_s_tags
fm_s_cover:     .ascii "\ncover: \""
.equ fm_s_cover_len, . - fm_s_cover
fm_s_sum:       .ascii "\nsummary: \""
.equ fm_s_sum_len, . - fm_s_sum
fm_s_draft_t:   .ascii "\"\ndraft: true\n---\n\n"
.equ fm_s_draft_t_len, . - fm_s_draft_t
fm_s_draft_f:   .ascii "\"\ndraft: false\n---\n\n"
.equ fm_s_draft_f_len, . - fm_s_draft_f

# Filesystem paths
st_d_content:   .asciz "content"
st_d_posts:     .asciz "content/posts"
st_d_uploads:   .asciz "content/uploads"
st_f_cats:      .asciz "content/categories.txt"
st_f_cats_tmp:  .asciz "content/.categories.txt.tmp"
st_p_posts_pre: .ascii "content/posts/"
.equ st_p_posts_pre_len, . - st_p_posts_pre
st_p_posts_dot: .ascii "content/posts/."
.equ st_p_posts_dot_len, . - st_p_posts_dot
st_p_md_ext:    .ascii ".md"
.equ st_p_md_ext_len, . - st_p_md_ext
st_p_md_tmp:    .ascii ".md.tmp"
.equ st_p_md_tmp_len, . - st_p_md_tmp
st_p_up_pre:    .ascii "content/uploads/"
.equ st_p_up_pre_len, . - st_p_up_pre
st_p_up_dot:    .ascii "content/uploads/."
.equ st_p_up_dot_len, . - st_p_up_dot
st_p_tmp_suf:   .ascii ".tmp"
.equ st_p_tmp_suf_len, . - st_p_tmp_suf
st_p_part_suf:  .ascii ".part"
.equ st_p_part_suf_len, . - st_p_part_suf
qk_id:          .ascii "id"
qk_done:        .ascii "done"

ext_jpg_s:      .ascii ".jpg"
ext_png_s:      .ascii ".png"
ext_gif_s:      .ascii ".gif"
ext_webp_s:     .ascii ".webp"
ext_mp4_s:      .ascii ".mp4"
ext_webm_s:     .ascii ".webm"
ext_mov_s:      .ascii ".mov"
ext_ogg_s:      .ascii ".ogg"

.section .text

# studio_send_json(rdi=conn, rsi=status_cstr, rdx=body_ptr, rcx=body_len, r8=extra_hdr_or_0)
studio_send_json:
    test r8, r8
    jnz .Lssj_go
    lea r8, [rip + hdr_nostore]
.Lssj_go:
    mov r9, r8
    mov r8, rcx
    mov rcx, rdx
    lea rdx, [rip + ct_json]
    jmp http_send_resp

# should_set_secure_cookie(rdi=&req) -> rax=1 if HTTPS else 0
should_set_secure_cookie:
    cmp qword ptr [rdi + REQ_HTTPS], 0
    jne .Lssc_yes
    cmp qword ptr [rip + g_cfg_site_url_len], s_https_pre_len
    jb .Lssc_no
    lea rdi, [rip + g_cfg_site_url]
    mov esi, s_https_pre_len
    lea rdx, [rip + s_https_pre]
    mov ecx, s_https_pre_len
    jmp xslice_eq_ci
.Lssc_yes:
    mov eax, 1
    ret
.Lssc_no:
    xor eax, eax
    ret

# session_create(rdi=out_64hex_ptr) -> generates random 32B token, stores in g_sessions
session_create:
    push rbx
    push r12
    push r13
    sub rsp, 32           # [rsp+0..23]=sbuf (3 pushes + ret = 32, +32 = 64 aligned)
    mov r12, rdi

    lea rdi, [rip + g_sess_rand32]
    mov esi, 32
    xor edx, edx
    call sys_getrandom
    cmp rax, 32
    je .Lsc_hex
    # Fallback entropy mix if getrandom short
    call mono_sec
    mov [rip + g_sess_rand32], rax
    call real_sec
    mov [rip + g_sess_rand32 + 8], rax
    movabs rcx, 0x9e3779b97f4a7c15
    xor rax, rcx
    mov [rip + g_sess_rand32 + 16], rax
    rol rax, 19
    mov [rip + g_sess_rand32 + 24], rax

.Lsc_hex:
    mov rdi, rsp; mov rsi, r12; mov edx, 64; call sb_init
    mov rdi, rsp; lea rsi, [rip + g_sess_rand32]; mov edx, 32; call sb_hex

    call mono_sec
    mov r13, rax          # now

    # Find an empty/expired slot
    xor ebx, ebx
.Lsc_find:
    cmp rbx, MAX_SESSIONS
    jae .Lsc_evict
    imul rax, rbx, SESS_SIZE
    lea r8, [rip + g_sessions]
    cmp [r8 + rax + 64], r13
    jbe .Lsc_use
    inc rbx
    jmp .Lsc_find

.Lsc_evict:
    mov rbx, [rip + g_sess_next]
    and rbx, MAX_SESSIONS - 1
    inc qword ptr [rip + g_sess_next]

.Lsc_use:
    imul rax, rbx, SESS_SIZE
    lea rbx, [rip + g_sessions]
    add rbx, rax
    mov rdi, rbx
    mov rsi, r12
    mov edx, 64
    call xmemcpy
    add r13, SESS_TTL_SEC
    mov [rbx + 64], r13

    add rsp, 32
    pop r13
    pop r12
    pop rbx
    ret

# session_verify(rdi=tok_ptr, rsi=tok_len) -> rax=1 valid, 0 invalid
session_verify:
    cmp rsi, 64
    jne .Lsv_no_fast
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    call mono_sec
    mov r13, rax
    xor ebx, ebx
.Lsv_loop:
    cmp rbx, MAX_SESSIONS
    jae .Lsv_no
    imul rax, rbx, SESS_SIZE
    lea r14, [rip + g_sessions]
    add r14, rax
    cmp [r14 + 64], r13
    jbe .Lsv_next
    mov rdi, r12
    mov rsi, r14
    mov edx, 64
    call ct_memeq
    test eax, eax
    jnz .Lsv_yes
.Lsv_next:
    inc rbx
    jmp .Lsv_loop
.Lsv_yes:
    mov eax, 1
    jmp .Lsv_ret
.Lsv_no:
    xor eax, eax
.Lsv_ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.Lsv_no_fast:
    xor eax, eax
    ret

# studio_get_req_token(rdi=&req) -> rax=tok_ptr (0 if none), rdx=64
studio_get_req_token:
    push r12
    mov r12, rdi
    mov rdi, r12
    lea rsi, [rip + st_ck_name]
    mov edx, st_ck_name_len
    call http_cookie_get
    test rax, rax
    jz .Lsrt_bearer
    cmp rdx, 64
    je .Lsrt_done
.Lsrt_bearer:
    mov rax, [r12 + REQ_AUTH_PTR]
    mov rdx, [r12 + REQ_AUTH_LEN]
    test rax, rax
    jz .Lsrt_none
    cmp rdx, 71
    jne .Lsrt_none
    push rax
    mov rdi, rax
    mov esi, st_bearer_pre_len
    lea rdx, [rip + st_bearer_pre]
    mov ecx, st_bearer_pre_len
    call xslice_eq_ci
    pop rcx
    test eax, eax
    jz .Lsrt_none
    lea rax, [rcx + 7]
    mov edx, 64
    jmp .Lsrt_done
.Lsrt_none:
    xor eax, eax
    xor edx, edx
.Lsrt_done:
    pop r12
    ret

# session_revoke_req(rdi=&req)
session_revoke_req:
    push rbx
    push r12
    push r13
    call studio_get_req_token
    test rax, rax
    jz .Lsrr_done
    mov r12, rax
    xor ebx, ebx
.Lsrr_loop:
    cmp rbx, MAX_SESSIONS
    jae .Lsrr_done
    imul rax, rbx, SESS_SIZE
    lea r13, [rip + g_sessions]
    add r13, rax
    cmp qword ptr [r13 + 64], 0
    je .Lsrr_next
    mov rdi, r12
    mov rsi, r13
    mov edx, 64
    call ct_memeq
    test eax, eax
    jz .Lsrr_next
    mov qword ptr [r13 + 64], 0
.Lsrr_next:
    inc rbx
    jmp .Lsrr_loop
.Lsrr_done:
    pop r13
    pop r12
    pop rbx
    ret

# session_revoke_others(rdi=keep_tok_ptr_or_0)
session_revoke_others:
    push rbx
    push r12
    push r13
    mov r12, rdi
    xor ebx, ebx
.Lsro_loop:
    cmp rbx, MAX_SESSIONS
    jae .Lsro_done
    imul rax, rbx, SESS_SIZE
    lea r13, [rip + g_sessions]
    add r13, rax
    cmp qword ptr [r13 + 64], 0
    je .Lsro_next
    test r12, r12
    jz .Lsro_clr
    mov rdi, r12
    mov rsi, r13
    mov edx, 64
    call ct_memeq
    test eax, eax
    jnz .Lsro_next
.Lsro_clr:
    mov qword ptr [r13 + 64], 0
.Lsro_next:
    inc rbx
    jmp .Lsro_loop
.Lsro_done:
    pop r13
    pop r12
    pop rbx
    ret

# studio_is_authed(rdi=&req) -> rax=1 authed, 0 not authed
studio_is_authed:
    push r12
    mov r12, rdi
    cmp qword ptr [rip + g_cfg_studio_hash_len], 64
    jne .Lsia_no
    mov rdi, r12
    call studio_get_req_token
    test rax, rax
    jz .Lsia_no
    mov rdi, rax
    mov rsi, rdx
    call session_verify
    pop r12
    ret
.Lsia_no:
    xor eax, eax
    pop r12
    ret

# sb_ini_safe(rdi=&sb, rsi=ptr, rdx=len) -> strips \r, \n, and control chars < 32
sb_ini_safe:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    xor ebx, ebx
.Linis_loop:
    cmp rbx, r14
    jae .Linis_done
    movzx eax, byte ptr [r13 + rbx]
    cmp al, 10
    je .Linis_sp
    cmp al, 13
    je .Linis_sp
    cmp al, 32
    jb .Linis_next
    mov rdi, r12; mov esi, eax; call sb_byte
    jmp .Linis_next
.Linis_sp:
    mov rdi, r12; mov esi, ' '; call sb_byte
.Linis_next:
    inc rbx
    jmp .Linis_loop
.Linis_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# sb_fm_safe(rdi=&sb, rsi=ptr, rdx=len) -> appends single-line Front-Matter safe bytes (strips \r,\n,",ctrl)
sb_fm_safe:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    xor ebx, ebx
.Lfms_loop:
    cmp rbx, r14
    jae .Lfms_done
    movzx eax, byte ptr [r13 + rbx]
    cmp al, '"'
    je .Lfms_sp
    cmp al, 10
    je .Lfms_sp
    cmp al, 13
    je .Lfms_sp
    cmp al, 32
    jb .Lfms_next
    mov rdi, r12
    mov esi, eax
    call sb_byte
    jmp .Lfms_next
.Lfms_sp:
    mov rdi, r12
    mov esi, ' '
    call sb_byte
.Lfms_next:
    inc rbx
    jmp .Lfms_loop
.Lfms_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# append_post_json(rdi=&sb, rsi=&post, rdx=include_content)
append_post_json:
    push r12
    push r13
    push r14
    mov r12, rdi          # &sb
    mov r13, rsi          # &post
    mov r14, rdx          # include_content

    mov rdi, r12; lea rsi, [rip + jp_1]; mov edx, jp_1_len; call sb_mem
    mov rdi, r12; mov rsi, [r13 + POST_SLUG_PTR]; mov rdx, [r13 + POST_SLUG_LEN]; call sb_esc_json
    mov rdi, r12; lea rsi, [rip + jp_2]; mov edx, jp_2_len; call sb_mem
    mov rdi, r12; mov rsi, [r13 + POST_TITLE_PTR]; mov rdx, [r13 + POST_TITLE_LEN]; call sb_esc_json
    mov rdi, r12; lea rsi, [rip + jp_3]; mov edx, jp_3_len; call sb_mem
    mov rdi, r12; mov rsi, [r13 + POST_DATE_PTR]; mov rdx, [r13 + POST_DATE_LEN]; call sb_esc_json
    mov rdi, r12; lea rsi, [rip + jp_4]; mov edx, jp_4_len; call sb_mem
    mov rdi, r12; mov rsi, [r13 + POST_CAT_PTR]; mov rdx, [r13 + POST_CAT_LEN]; call sb_esc_json
    mov rdi, r12; lea rsi, [rip + jp_5]; mov edx, jp_5_len; call sb_mem
    mov rdi, r12; mov rsi, [r13 + POST_TAGS_RAW_PTR]; mov rdx, [r13 + POST_TAGS_RAW_LEN]; call sb_esc_json
    mov rdi, r12; lea rsi, [rip + jp_6]; mov edx, jp_6_len; call sb_mem
    mov rdi, r12; mov rsi, [r13 + POST_COVER_PTR]; mov rdx, [r13 + POST_COVER_LEN]; call sb_esc_json
    mov rdi, r12; lea rsi, [rip + jp_7]; mov edx, jp_7_len; call sb_mem
    mov rdi, r12; mov rsi, [r13 + POST_SUMMARY_PTR]; mov rdx, [r13 + POST_SUMMARY_LEN]; call sb_esc_json
    mov rdi, r12; lea rsi, [rip + jp_8]; mov edx, jp_8_len; call sb_mem
    cmp qword ptr [r13 + POST_DRAFT], 0
    je .Lapj_df
    mov rdi, r12; lea rsi, [rip + jp_true]; mov edx, jp_true_len; call sb_mem
    jmp .Lapj_cnt
.Lapj_df:
    mov rdi, r12; lea rsi, [rip + jp_false]; mov edx, jp_false_len; call sb_mem
.Lapj_cnt:
    test r14, r14
    jz .Lapj_end
    mov rdi, r12; lea rsi, [rip + jp_9_content]; mov edx, jp_9_content_len; call sb_mem
    mov rdi, r12; mov rsi, [r13 + POST_MD_PTR]; mov rdx, [r13 + POST_MD_LEN]; call sb_esc_json
    mov rdi, r12; mov esi, '"'; call sb_byte
.Lapj_end:
    mov rdi, r12; mov esi, '}'; call sb_byte
    pop r14
    pop r13
    pop r12
    ret

# studio_write_post_struct(rdi=&post, rsi=clear_cat) -> rax=0 ok, <0 err
# Rewrites an existing post_t atomically (used when clearing a deleted category from posts).
studio_write_post_struct:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 40           # [rsp+0..23]=sbuf, [rsp+24]=clear_cat
    mov r12, rdi
    mov [rsp + 24], rsi

    mov rdi, rsp; lea rsi, [rip + st_file_buf]; mov edx, 262143; call sb_init
    mov rdi, rsp; lea rsi, [rip + fm_s_1]; mov edx, fm_s_1_len; call sb_mem
    mov rdi, rsp; mov rsi, [r12 + POST_TITLE_PTR]; mov rdx, [r12 + POST_TITLE_LEN]; call sb_fm_safe
    mov rdi, rsp; lea rsi, [rip + fm_s_slug]; mov edx, fm_s_slug_len; call sb_mem
    mov rdi, rsp; mov rsi, [r12 + POST_SLUG_PTR]; mov rdx, [r12 + POST_SLUG_LEN]; call sb_mem
    mov rdi, rsp; lea rsi, [rip + fm_s_date]; mov edx, fm_s_date_len; call sb_mem
    mov rdi, rsp; mov rsi, [r12 + POST_DATE_PTR]; mov rdx, [r12 + POST_DATE_LEN]; call sb_fm_safe

    cmp qword ptr [rsp + 24], 0
    jne .Lswps_tags
    cmp qword ptr [r12 + POST_CAT_LEN], 0
    je .Lswps_tags
    mov rdi, rsp; lea rsi, [rip + fm_s_cat]; mov edx, fm_s_cat_len; call sb_mem
    mov rdi, rsp; mov rsi, [r12 + POST_CAT_PTR]; mov rdx, [r12 + POST_CAT_LEN]; call sb_fm_safe
    mov rdi, rsp; mov esi, '"'; call sb_byte

.Lswps_tags:
    cmp qword ptr [r12 + POST_TAGS_RAW_LEN], 0
    je .Lswps_cover
    mov rdi, rsp; lea rsi, [rip + fm_s_tags]; mov edx, fm_s_tags_len; call sb_mem
    mov rdi, rsp; mov rsi, [r12 + POST_TAGS_RAW_PTR]; mov rdx, [r12 + POST_TAGS_RAW_LEN]; call sb_fm_safe

.Lswps_cover:
    cmp qword ptr [r12 + POST_COVER_LEN], 0
    je .Lswps_sum
    mov rdi, rsp; lea rsi, [rip + fm_s_cover]; mov edx, fm_s_cover_len; call sb_mem
    mov rdi, rsp; mov rsi, [r12 + POST_COVER_PTR]; mov rdx, [r12 + POST_COVER_LEN]; call sb_fm_safe
    mov rdi, rsp; mov esi, '"'; call sb_byte

.Lswps_sum:
    mov rdi, rsp; lea rsi, [rip + fm_s_sum]; mov edx, fm_s_sum_len; call sb_mem
    mov rdi, rsp; mov rsi, [r12 + POST_SUMMARY_PTR]; mov rdx, [r12 + POST_SUMMARY_LEN]; call sb_fm_safe

    cmp qword ptr [r12 + POST_DRAFT], 0
    je .Lswps_df
    mov rdi, rsp; lea rsi, [rip + fm_s_draft_t]; mov edx, fm_s_draft_t_len; call sb_mem
    jmp .Lswps_body
.Lswps_df:
    mov rdi, rsp; lea rsi, [rip + fm_s_draft_f]; mov edx, fm_s_draft_f_len; call sb_mem
.Lswps_body:
    mov rdi, rsp; mov rsi, [r12 + POST_MD_PTR]; mov rdx, [r12 + POST_MD_LEN]; call sb_mem
    mov r13, [rsp + SB_LEN]

    # Build final path content/posts/<slug>.md\0
    mov rdi, rsp; lea rsi, [rip + st_path_buf]; mov edx, 511; call sb_init
    mov rdi, rsp; lea rsi, [rip + st_p_posts_pre]; mov edx, st_p_posts_pre_len; call sb_mem
    mov rdi, rsp; mov rsi, [r12 + POST_SLUG_PTR]; mov rdx, [r12 + POST_SLUG_LEN]; call sb_mem
    mov rdi, rsp; lea rsi, [rip + st_p_md_ext]; mov edx, st_p_md_ext_len; call sb_mem
    mov rdi, rsp; xor esi, esi; call sb_byte

    # Build tmp path content/posts/.<slug>.md.tmp\0
    mov rdi, rsp; lea rsi, [rip + st_tmp_buf]; mov edx, 511; call sb_init
    mov rdi, rsp; lea rsi, [rip + st_p_posts_dot]; mov edx, st_p_posts_dot_len; call sb_mem
    mov rdi, rsp; mov rsi, [r12 + POST_SLUG_PTR]; mov rdx, [r12 + POST_SLUG_LEN]; call sb_mem
    mov rdi, rsp; lea rsi, [rip + st_p_md_tmp]; mov edx, st_p_md_tmp_len; call sb_mem
    mov rdi, rsp; xor esi, esi; call sb_byte

    lea rdi, [rip + st_path_buf]
    lea rsi, [rip + st_tmp_buf]
    lea rdx, [rip + st_file_buf]
    mov rcx, r13
    call write_file_atomic

    add rsp, 40
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

# =========================================================================
# 1. GET /studio -> serves themes/<theme>/studio.html with Cache-Control: no-store
# =========================================================================
.globl handle_studio_page
handle_studio_page:
    push r12
    mov r12, rdi
    lea rdi, [rip + st_tpl_name]
    mov esi, st_tpl_name_len
    call store_find_tpl
    test rax, rax
    jz .Lhsp_404
    mov r8, rdx
    mov rcx, rax
    mov rdi, r12
    lea rsi, [rip + st_200]
    lea rdx, [rip + ct_html]
    lea r9, [rip + hdr_nostore]
    call http_send_resp
    pop r12
    ret
.Lhsp_404:
    mov rdi, r12
    lea rsi, [rip + st_404]
    lea rdx, [rip + st_msg_404]
    call http_send_error
    pop r12
    ret

# =========================================================================
# 2. POST /api/studio/login (with random session token + brute-force 429 lockout)
# =========================================================================
.globl handle_studio_login
handle_studio_login:
    push r12
    push r13
    sub rsp, 40           # [rsp+0..23]=sbuf (16-byte aligned: 2 pushes + ret = 24, +40 = 64)
    mov r12, rdi          # conn
    mov r13, rsi          # &req

    cmp qword ptr [rip + g_cfg_studio_hash_len], 64
    je .Lhsl_chk_lock
    mov rdi, r12
    lea rsi, [rip + st_403]
    lea rdx, [rip + j_err_nocfg]
    mov ecx, j_err_nocfg_len
    xor r8d, r8d
    call studio_send_json
    jmp .Lhsl_ret

.Lhsl_chk_lock:
    call mono_sec
    cmp rax, [rip + g_login_lock_until]
    jb .Lhsl_locked

    mov rdi, rsp; lea rsi, [rip + st_f_pass]; mov edx, 255; call sb_init
    mov rdi, [r13 + REQ_BODY_PTR]
    mov rsi, [r13 + REQ_BODY_LEN]
    lea rdx, [rip + jk_pass]
    mov ecx, jk_pass_len
    mov r8, rsp
    call json_get_str
    test eax, eax
    jz .Lhsl_nopass
    mov rsi, [rsp + SB_LEN]
    test rsi, rsi
    jz .Lhsl_nopass

    lea rdi, [rip + st_f_pass]
    lea rdx, [rip + st_hash_buf]
    call sha256_hex

    lea rdi, [rip + st_hash_buf]
    lea rsi, [rip + g_cfg_studio_hash]
    mov edx, 64
    call ct_memeq
    test eax, eax
    jz .Lhsl_bad

    # Valid passphrase -> clear fail counter, mint fresh cryptographic session token
    mov qword ptr [rip + g_login_fail_cnt], 0
    mov qword ptr [rip + g_login_lock_until], 0
    lea rdi, [rip + g_sess_hex64]
    call session_create

    # Build Set-Cookie header (auto-append ; Secure when over HTTPS)
    mov rdi, rsp; lea rsi, [rip + st_hdr_buf]; mov edx, 511; call sb_init
    mov rdi, rsp; lea rsi, [rip + hdr_setck_1]; mov edx, hdr_setck_1_len; call sb_mem
    mov rdi, rsp; lea rsi, [rip + g_sess_hex64]; mov edx, 64; call sb_mem
    mov rdi, rsp; lea rsi, [rip + hdr_setck_2]; mov edx, hdr_setck_2_len; call sb_mem
    mov rdi, r13
    call should_set_secure_cookie
    test eax, eax
    jz .Lhsl_ck_nul
    mov rdi, rsp; lea rsi, [rip + hdr_setck_sec]; mov edx, hdr_setck_sec_len; call sb_mem
.Lhsl_ck_nul:
    mov rdi, rsp; xor esi, esi; call sb_byte

    mov rdi, r12
    lea rsi, [rip + st_200]
    lea rdx, [rip + j_ok]
    mov ecx, j_ok_len
    lea r8, [rip + st_hdr_buf]
    call studio_send_json
    jmp .Lhsl_ret

.Lhsl_nopass:
    mov rdi, r12; lea rsi, [rip + st_400]; lea rdx, [rip + j_err_nopass]; mov ecx, j_err_nopass_len; xor r8d, r8d
    call studio_send_json
    jmp .Lhsl_ret

.Lhsl_bad:
    inc qword ptr [rip + g_login_fail_cnt]
    cmp qword ptr [rip + g_login_fail_cnt], 5
    jb .Lhsl_401
    mov qword ptr [rip + g_login_fail_cnt], 0
    call mono_sec
    add rax, 60
    mov [rip + g_login_lock_until], rax
.Lhsl_locked:
    mov rdi, r12; lea rsi, [rip + st_429]; lea rdx, [rip + j_err_locked]; mov ecx, j_err_locked_len
    lea r8, [rip + hdr_retry60]
    call studio_send_json
    jmp .Lhsl_ret

.Lhsl_401:
    mov rdi, r12; lea rsi, [rip + st_401]; lea rdx, [rip + j_err_badpass]; mov ecx, j_err_badpass_len; xor r8d, r8d
    call studio_send_json

.Lhsl_ret:
    add rsp, 40
    pop r13
    pop r12
    ret

# =========================================================================
# 3. POST /api/studio/logout (revokes server-side session token + expires cookie)
# =========================================================================
.globl handle_studio_logout
handle_studio_logout:
    push r12
    push r13
    sub rsp, 40
    mov r12, rdi
    mov r13, rsi

    mov rdi, r13
    call session_revoke_req

    mov rdi, rsp; lea rsi, [rip + st_hdr_buf]; mov edx, 511; call sb_init
    mov rdi, rsp; lea rsi, [rip + hdr_clrck_1]; mov edx, hdr_clrck_1_len; call sb_mem
    mov rdi, r13
    call should_set_secure_cookie
    test eax, eax
    jz .Lhslo_nul
    mov rdi, rsp; lea rsi, [rip + hdr_setck_sec]; mov edx, hdr_setck_sec_len; call sb_mem
.Lhslo_nul:
    mov rdi, rsp; xor esi, esi; call sb_byte

    mov rdi, r12
    lea rsi, [rip + st_200]
    lea rdx, [rip + j_ok]
    mov ecx, j_ok_len
    lea r8, [rip + st_hdr_buf]
    call studio_send_json
    add rsp, 40
    pop r13
    pop r12
    ret

# =========================================================================
# 4. GET /api/studio/posts (lists all posts including drafts)
# =========================================================================
.globl handle_studio_posts_list
handle_studio_posts_list:
    push rbx
    push r12
    push r13
    sub rsp, 32           # 3 pushes + ret = 32, +32 = 64 (16B aligned)
    mov r12, rdi
    mov r13, rsi

    mov rdi, r13
    call studio_is_authed
    test eax, eax
    jnz .Lhspl_ok
    mov rdi, r12; lea rsi, [rip + st_401]; lea rdx, [rip + j_err_unauth]; mov ecx, j_err_unauth_len; xor r8d, r8d
    call studio_send_json
    jmp .Lhspl_ret

.Lhspl_ok:
    mov rdi, rsp; lea rsi, [rip + st_resp_buf]; mov edx, 262143; call sb_init
    mov rdi, rsp; mov esi, '['; call sb_byte
    xor ebx, ebx
.Lhspl_loop:
    cmp rbx, [rip + g_post_count]
    jae .Lhspl_end
    test rbx, rbx
    jz .Lhspl_first
    mov rdi, rsp; mov esi, ','; call sb_byte
.Lhspl_first:
    lea r8, [rip + g_post_ptrs]
    mov rsi, [r8 + rbx*8]
    mov rdi, rsp
    xor edx, edx          # no full content in list
    call append_post_json
    inc rbx
    jmp .Lhspl_loop
.Lhspl_end:
    mov rdi, rsp; mov esi, ']'; call sb_byte
    mov rdi, r12
    lea rsi, [rip + st_200]
    lea rdx, [rip + st_resp_buf]
    mov rcx, [rsp + SB_LEN]
    xor r8d, r8d
    call studio_send_json

.Lhspl_ret:
    add rsp, 32
    pop r13
    pop r12
    pop rbx
    ret

# =========================================================================
# 5. GET /api/studio/posts/:slug (returns full post + raw markdown content)
# =========================================================================
.globl handle_studio_post_get
handle_studio_post_get:
    push r12
    push r13
    sub rsp, 40
    mov r12, rdi
    mov r13, rsi

    mov rdi, r13
    call studio_is_authed
    test eax, eax
    jnz .Lhspg_slug
    mov rdi, r12; lea rsi, [rip + st_401]; lea rdx, [rip + j_err_unauth]; mov ecx, j_err_unauth_len; xor r8d, r8d
    call studio_send_json
    jmp .Lhspg_ret

.Lhspg_slug:
    mov rdi, [r13 + REQ_PARAM_PTR]
    mov rsi, [r13 + REQ_PARAM_LEN]
    call is_safe_slug
    test eax, eax
    jnz .Lhspg_find
    mov rdi, r12; lea rsi, [rip + st_400]; lea rdx, [rip + j_err_slug]; mov ecx, j_err_slug_len; xor r8d, r8d
    call studio_send_json
    jmp .Lhspg_ret

.Lhspg_find:
    mov rdi, [r13 + REQ_PARAM_PTR]
    mov rsi, [r13 + REQ_PARAM_LEN]
    mov edx, 1            # include drafts
    call store_find_post
    test rax, rax
    jnz .Lhspg_emit
    mov rdi, r12; lea rsi, [rip + st_404]; lea rdx, [rip + j_err_notfound]; mov ecx, j_err_notfound_len; xor r8d, r8d
    call studio_send_json
    jmp .Lhspg_ret

.Lhspg_emit:
    push rax
    lea rdi, [rsp + 8]; lea rsi, [rip + st_resp_buf]; mov edx, 262143; call sb_init
    pop rsi
    mov rdi, rsp
    mov edx, 1            # include full markdown content
    call append_post_json
    mov rdi, r12
    lea rsi, [rip + st_200]
    lea rdx, [rip + st_resp_buf]
    mov rcx, [rsp + SB_LEN]
    xor r8d, r8d
    call studio_send_json

.Lhspg_ret:
    add rsp, 40
    pop r13
    pop r12
    ret

# =========================================================================
# 6. POST /api/studio/posts (create or update post)
# =========================================================================
.globl handle_studio_post_save
handle_studio_post_save:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    # 6 pushes + ret = 56 bytes -> sub rsp, 184 gives 16-byte aligned rsp
    # Layout:
    # [rsp+0..23]   sbuf
    # [rsp+24]      title_ptr,   [rsp+32]  title_len
    # [rsp+40]      slug_ptr,    [rsp+48]  slug_len
    # [rsp+56]      date_ptr,    [rsp+64]  date_len
    # [rsp+72]      cat_ptr,     [rsp+80]  cat_len
    # [rsp+88]      tags_ptr,    [rsp+96]  tags_len
    # [rsp+104]     sum_ptr,     [rsp+112] sum_len
    # [rsp+120]     cover_ptr,   [rsp+128] cover_len
    # [rsp+136]     is_draft
    # [rsp+144]     content_len
    # [rsp+152]     md_total_len
    sub rsp, 184

    mov r12, rdi          # conn
    mov r13, rsi          # &req

    mov rdi, r13
    call studio_is_authed
    test eax, eax
    jnz .Lhsps_authed
    mov rdi, r12; lea rsi, [rip + st_401]; lea rdx, [rip + j_err_unauth]; mov ecx, j_err_unauth_len; xor r8d, r8d
    call studio_send_json
    jmp .Lhsps_ret

.Lhsps_authed:
    mov r14, [r13 + REQ_BODY_PTR]
    mov r15, [r13 + REQ_BODY_LEN]

    # 1) title (required)
    mov rdi, rsp; lea rsi, [rip + st_f_title]; mov edx, 511; call sb_init
    mov rdi, r14; mov rsi, r15; lea rdx, [rip + jk_title]; mov ecx, jk_title_len; mov r8, rsp; call json_get_str
    lea rdi, [rip + st_f_title]; mov rsi, [rsp + SB_LEN]; call trim_ws
    mov [rsp + 24], rax; mov [rsp + 32], rdx
    test rdx, rdx
    jnz .Lhsps_slug
    mov rdi, r12; lea rsi, [rip + st_400]; lea rdx, [rip + j_err_title]; mov ecx, j_err_title_len; xor r8d, r8d
    call studio_send_json
    jmp .Lhsps_ret

.Lhsps_slug:
    # 2) slug (required & safe)
    mov rdi, rsp; lea rsi, [rip + st_f_slug]; mov edx, 255; call sb_init
    mov rdi, r14; mov rsi, r15; lea rdx, [rip + jk_slug]; mov ecx, jk_slug_len; mov r8, rsp; call json_get_str
    lea rdi, [rip + st_f_slug]; mov rsi, [rsp + SB_LEN]; call trim_ws
    mov [rsp + 40], rax; mov [rsp + 48], rdx
    mov rdi, rax; mov rsi, rdx; call is_safe_slug
    test eax, eax
    jnz .Lhsps_date
    mov rdi, r12; lea rsi, [rip + st_400]; lea rdx, [rip + j_err_slug]; mov ecx, j_err_slug_len; xor r8d, r8d
    call studio_send_json
    jmp .Lhsps_ret

.Lhsps_date:
    # 3) date (default to today UTC YYYY-MM-DD if empty)
    mov rdi, rsp; lea rsi, [rip + st_f_date]; mov edx, 63; call sb_init
    mov rdi, r14; mov rsi, r15; lea rdx, [rip + jk_date]; mov ecx, jk_date_len; mov r8, rsp; call json_get_str
    lea rdi, [rip + st_f_date]; mov rsi, [rsp + SB_LEN]; call trim_ws
    test rdx, rdx
    jnz .Lhsps_date_ok
    call real_sec
    mov rdi, rax
    lea rsi, [rip + st_date_buf]
    call format_iso_date
    lea rax, [rip + st_date_buf]
    mov edx, 10
.Lhsps_date_ok:
    mov [rsp + 56], rax; mov [rsp + 64], rdx

    # 4) category (optional)
    mov rdi, rsp; lea rsi, [rip + st_f_cat]; mov edx, 255; call sb_init
    mov rdi, r14; mov rsi, r15; lea rdx, [rip + jk_cat]; mov ecx, jk_cat_len; mov r8, rsp; call json_get_str
    lea rdi, [rip + st_f_cat]; mov rsi, [rsp + SB_LEN]; call trim_ws
    mov [rsp + 72], rax; mov [rsp + 80], rdx

    # 5) tags (optional)
    mov rdi, rsp; lea rsi, [rip + st_f_tags]; mov edx, 511; call sb_init
    mov rdi, r14; mov rsi, r15; lea rdx, [rip + jk_tags]; mov ecx, jk_tags_len; mov r8, rsp; call json_get_str
    lea rdi, [rip + st_f_tags]; mov rsi, [rsp + SB_LEN]; call trim_ws
    mov [rsp + 88], rax; mov [rsp + 96], rdx

    # 6) summary (optional)
    mov rdi, rsp; lea rsi, [rip + st_f_summary]; mov edx, 1023; call sb_init
    mov rdi, r14; mov rsi, r15; lea rdx, [rip + jk_summary]; mov ecx, jk_summary_len; mov r8, rsp; call json_get_str
    lea rdi, [rip + st_f_summary]; mov rsi, [rsp + SB_LEN]; call trim_ws
    mov [rsp + 104], rax; mov [rsp + 112], rdx

    # 7) cover (optional, validated via is_safe_url if non-empty)
    mov rdi, rsp; lea rsi, [rip + st_f_cover]; mov edx, 511; call sb_init
    mov rdi, r14; mov rsi, r15; lea rdx, [rip + jk_cover]; mov ecx, jk_cover_len; mov r8, rsp; call json_get_str
    lea rdi, [rip + st_f_cover]; mov rsi, [rsp + SB_LEN]; call trim_ws
    mov [rsp + 120], rax; mov [rsp + 128], rdx
    test rdx, rdx
    jz .Lhsps_draft
    mov rdi, rax; mov rsi, rdx; call is_safe_url
    test eax, eax
    jnz .Lhsps_draft
    mov rdi, r12; lea rsi, [rip + st_400]; lea rdx, [rip + j_err_cover]; mov ecx, j_err_cover_len; xor r8d, r8d
    call studio_send_json
    jmp .Lhsps_ret

.Lhsps_draft:
    # 8) draft ("true" or "1")
    mov qword ptr [rsp + 136], 0
    mov rdi, rsp; lea rsi, [rip + st_f_draft]; mov edx, 31; call sb_init
    mov rdi, r14; mov rsi, r15; lea rdx, [rip + jk_draft]; mov ecx, jk_draft_len; mov r8, rsp; call json_get_str
    lea rdi, [rip + st_f_draft]; mov rsi, [rsp + SB_LEN]; call trim_ws
    test rdx, rdx
    jz .Lhsps_content
    push rax; push rdx
    mov rdi, rax; mov rsi, rdx; lea rdx, [rip + jv_true]; mov ecx, jv_true_len; call xslice_eq_ci
    pop rdx; pop rdi
    test eax, eax
    jnz .Lhsps_is_draft
    mov rsi, rdx; lea rdx, [rip + jv_one]; mov ecx, jv_one_len; call xslice_eq
    test eax, eax
    jz .Lhsps_content
.Lhsps_is_draft:
    mov qword ptr [rsp + 136], 1

.Lhsps_content:
    # 9) content (markdown body)
    mov rdi, rsp; lea rsi, [rip + st_f_content]; mov edx, 196607; call sb_init
    mov rdi, r14; mov rsi, r15; lea rdx, [rip + jk_content]; mov ecx, jk_content_len; mov r8, rsp; call json_get_str
    mov rax, [rsp + SB_LEN]
    mov [rsp + 144], rax

    # Assemble Markdown file into st_file_buf
    mov rdi, rsp; lea rsi, [rip + st_file_buf]; mov edx, 262143; call sb_init
    mov rdi, rsp; lea rsi, [rip + fm_s_1]; mov edx, fm_s_1_len; call sb_mem
    mov rdi, rsp; mov rsi, [rsp + 24]; mov rdx, [rsp + 32]; call sb_fm_safe
    mov rdi, rsp; lea rsi, [rip + fm_s_slug]; mov edx, fm_s_slug_len; call sb_mem
    mov rdi, rsp; mov rsi, [rsp + 40]; mov rdx, [rsp + 48]; call sb_mem
    mov rdi, rsp; lea rsi, [rip + fm_s_date]; mov edx, fm_s_date_len; call sb_mem
    mov rdi, rsp; mov rsi, [rsp + 56]; mov rdx, [rsp + 64]; call sb_fm_safe

    cmp qword ptr [rsp + 80], 0
    je .Lhsps_w_tags
    mov rdi, rsp; lea rsi, [rip + fm_s_cat]; mov edx, fm_s_cat_len; call sb_mem
    mov rdi, rsp; mov rsi, [rsp + 72]; mov rdx, [rsp + 80]; call sb_fm_safe
    mov rdi, rsp; mov esi, '"'; call sb_byte

.Lhsps_w_tags:
    cmp qword ptr [rsp + 96], 0
    je .Lhsps_w_cover
    mov rdi, rsp; lea rsi, [rip + fm_s_tags]; mov edx, fm_s_tags_len; call sb_mem
    mov rdi, rsp; mov rsi, [rsp + 88]; mov rdx, [rsp + 96]; call sb_fm_safe

.Lhsps_w_cover:
    cmp qword ptr [rsp + 128], 0
    je .Lhsps_w_sum
    mov rdi, rsp; lea rsi, [rip + fm_s_cover]; mov edx, fm_s_cover_len; call sb_mem
    mov rdi, rsp; mov rsi, [rsp + 120]; mov rdx, [rsp + 128]; call sb_fm_safe
    mov rdi, rsp; mov esi, '"'; call sb_byte

.Lhsps_w_sum:
    mov rdi, rsp; lea rsi, [rip + fm_s_sum]; mov edx, fm_s_sum_len; call sb_mem
    mov rdi, rsp; mov rsi, [rsp + 104]; mov rdx, [rsp + 112]; call sb_fm_safe

    cmp qword ptr [rsp + 136], 0
    je .Lhsps_w_df
    mov rdi, rsp; lea rsi, [rip + fm_s_draft_t]; mov edx, fm_s_draft_t_len; call sb_mem
    jmp .Lhsps_w_body
.Lhsps_w_df:
    mov rdi, rsp; lea rsi, [rip + fm_s_draft_f]; mov edx, fm_s_draft_f_len; call sb_mem
.Lhsps_w_body:
    mov rdi, rsp; lea rsi, [rip + st_f_content]; mov rdx, [rsp + 144]; call sb_mem
    # Append trailing newline if missing
    mov rax, [rsp + SB_LEN]
    test rax, rax
    jz .Lhsps_w_nl
    lea rcx, [rip + st_file_buf]
    cmp byte ptr [rcx + rax - 1], 10
    je .Lhsps_w_go
.Lhsps_w_nl:
    mov rdi, rsp; mov esi, 10; call sb_byte
.Lhsps_w_go:
    mov rax, [rsp + SB_LEN]
    mov [rsp + 152], rax

    # Ensure content/ and content/posts/ exist
    lea rdi, [rip + st_d_content]; mov esi, 0755; call sys_mkdir
    lea rdi, [rip + st_d_posts];   mov esi, 0755; call sys_mkdir

    # Build final & tmp paths
    mov rdi, rsp; lea rsi, [rip + st_path_buf]; mov edx, 511; call sb_init
    mov rdi, rsp; lea rsi, [rip + st_p_posts_pre]; mov edx, st_p_posts_pre_len; call sb_mem
    mov rdi, rsp; mov rsi, [rsp + 40]; mov rdx, [rsp + 48]; call sb_mem
    mov rdi, rsp; lea rsi, [rip + st_p_md_ext]; mov edx, st_p_md_ext_len; call sb_mem
    mov rdi, rsp; xor esi, esi; call sb_byte

    mov rdi, rsp; lea rsi, [rip + st_tmp_buf]; mov edx, 511; call sb_init
    mov rdi, rsp; lea rsi, [rip + st_p_posts_dot]; mov edx, st_p_posts_dot_len; call sb_mem
    mov rdi, rsp; mov rsi, [rsp + 40]; mov rdx, [rsp + 48]; call sb_mem
    mov rdi, rsp; lea rsi, [rip + st_p_md_tmp]; mov edx, st_p_md_tmp_len; call sb_mem
    mov rdi, rsp; xor esi, esi; call sb_byte

    lea rdi, [rip + st_path_buf]
    lea rsi, [rip + st_tmp_buf]
    lea rdx, [rip + st_file_buf]
    mov rcx, [rsp + 152]
    call write_file_atomic
    test rax, rax
    jns .Lhsps_reload
    mov rdi, r12; lea rsi, [rip + st_500]; lea rdx, [rip + j_err_write]; mov ecx, j_err_write_len; xor r8d, r8d
    call studio_send_json
    jmp .Lhsps_ret

.Lhsps_reload:
    call store_reload

    mov rdi, rsp; lea rsi, [rip + st_resp_buf]; mov edx, 511; call sb_init
    mov rdi, rsp; lea rsi, [rip + j_ok_slug_1]; mov edx, j_ok_slug_1_len; call sb_mem
    mov rdi, rsp; mov rsi, [rsp + 40]; mov rdx, [rsp + 48]; call sb_mem
    mov rdi, rsp; lea rsi, [rip + j_close_obj]; mov edx, j_close_obj_len; call sb_mem

    mov rdi, r12
    lea rsi, [rip + st_200]
    lea rdx, [rip + st_resp_buf]
    mov rcx, [rsp + SB_LEN]
    xor r8d, r8d
    call studio_send_json

.Lhsps_ret:
    add rsp, 184
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

# =========================================================================
# 7. DELETE /api/studio/posts/:slug
# =========================================================================
.globl handle_studio_post_del
handle_studio_post_del:
    push r12
    push r13
    sub rsp, 40
    mov r12, rdi
    mov r13, rsi

    mov rdi, r13
    call studio_is_authed
    test eax, eax
    jnz .Lhspd_slug
    mov rdi, r12; lea rsi, [rip + st_401]; lea rdx, [rip + j_err_unauth]; mov ecx, j_err_unauth_len; xor r8d, r8d
    call studio_send_json
    jmp .Lhspd_ret

.Lhspd_slug:
    mov rdi, [r13 + REQ_PARAM_PTR]
    mov rsi, [r13 + REQ_PARAM_LEN]
    call is_safe_slug
    test eax, eax
    jnz .Lhspd_del
    mov rdi, r12; lea rsi, [rip + st_400]; lea rdx, [rip + j_err_slug]; mov ecx, j_err_slug_len; xor r8d, r8d
    call studio_send_json
    jmp .Lhspd_ret

.Lhspd_del:
    mov rdi, rsp; lea rsi, [rip + st_path_buf]; mov edx, 511; call sb_init
    mov rdi, rsp; lea rsi, [rip + st_p_posts_pre]; mov edx, st_p_posts_pre_len; call sb_mem
    mov rdi, rsp; mov rsi, [r13 + REQ_PARAM_PTR]; mov rdx, [r13 + REQ_PARAM_LEN]; call sb_mem
    mov rdi, rsp; lea rsi, [rip + st_p_md_ext]; mov edx, st_p_md_ext_len; call sb_mem
    mov rdi, rsp; xor esi, esi; call sb_byte

    lea rdi, [rip + st_path_buf]
    call sys_unlink
    test rax, rax
    jns .Lhspd_ok
    mov rdi, r12; lea rsi, [rip + st_404]; lea rdx, [rip + j_err_notfound]; mov ecx, j_err_notfound_len; xor r8d, r8d
    call studio_send_json
    jmp .Lhspd_ret

.Lhspd_ok:
    call store_reload
    mov rdi, r12; lea rsi, [rip + st_200]; lea rdx, [rip + j_ok]; mov ecx, j_ok_len; xor r8d, r8d
    call studio_send_json

.Lhspd_ret:
    add rsp, 40
    pop r13
    pop r12
    ret

# =========================================================================
# 8. GET /api/studio/categories
# =========================================================================
.globl handle_studio_cats_list
handle_studio_cats_list:
    push rbx
    push r12
    push r13
    sub rsp, 32
    mov r12, rdi
    mov r13, rsi

    mov rdi, r13
    call studio_is_authed
    test eax, eax
    jnz .Lhscl_ok
    mov rdi, r12; lea rsi, [rip + st_401]; lea rdx, [rip + j_err_unauth]; mov ecx, j_err_unauth_len; xor r8d, r8d
    call studio_send_json
    jmp .Lhscl_ret

.Lhscl_ok:
    mov rdi, rsp; lea rsi, [rip + st_resp_buf]; mov edx, 262143; call sb_init
    mov rdi, rsp; mov esi, '['; call sb_byte
    xor ebx, ebx
.Lhscl_loop:
    cmp rbx, [rip + g_cat_count]
    jae .Lhscl_end
    test rbx, rbx
    jz .Lhscl_first
    mov rdi, rsp; mov esi, ','; call sb_byte
.Lhscl_first:
    imul rax, rbx, CAT_SIZE
    lea r8, [rip + g_cats]
    add r8, rax
    push r8
    lea rdi, [rsp + 8]; lea rsi, [rip + jc_1]; mov edx, jc_1_len; call sb_mem
    mov r8, [rsp]
    lea rdi, [rsp + 8]; mov rsi, [r8 + CAT_NAME_PTR]; mov rdx, [r8 + CAT_NAME_LEN]; call sb_esc_json
    lea rdi, [rsp + 8]; lea rsi, [rip + jc_2]; mov edx, jc_2_len; call sb_mem
    mov r8, [rsp]
    lea rdi, [rsp + 8]; mov rsi, [r8 + CAT_COUNT]; call sb_uint
    lea rdi, [rsp + 8]; mov esi, '}'; call sb_byte
    pop r8
    inc rbx
    jmp .Lhscl_loop
.Lhscl_end:
    mov rdi, rsp; mov esi, ']'; call sb_byte
    mov rdi, r12
    lea rsi, [rip + st_200]
    lea rdx, [rip + st_resp_buf]
    mov rcx, [rsp + SB_LEN]
    xor r8d, r8d
    call studio_send_json

.Lhscl_ret:
    add rsp, 32
    pop r13
    pop r12
    pop rbx
    ret

# validate_cat_name(rdi=ptr, rsi=len) -> rax=1 valid, 0 invalid
validate_cat_name:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    test r13, r13
    jz .Lvcn_no
    cmp r13, 60
    ja .Lvcn_no
    cmp byte ptr [r12], '#'
    je .Lvcn_no
    mov rdi, r12; mov rsi, r13; call is_safe_relpath
    test eax, eax
    jz .Lvcn_no
    xor ebx, ebx
.Lvcn_loop:
    cmp rbx, r13
    jae .Lvcn_yes
    movzx eax, byte ptr [r12 + rbx]
    cmp al, '/'
    je .Lvcn_no
    cmp al, '"'
    je .Lvcn_no
    cmp al, 32
    jb .Lvcn_no
    inc rbx
    jmp .Lvcn_loop
.Lvcn_yes:
    mov eax, 1
    jmp .Lvcn_ret
.Lvcn_no:
    xor eax, eax
.Lvcn_ret:
    pop r13
    pop r12
    pop rbx
    ret

# =========================================================================
# 9. POST /api/studio/categories (add category)
# =========================================================================
.globl handle_studio_cat_add
handle_studio_cat_add:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 32           # 5 pushes + ret = 48, +32 = 80 (16B aligned)
    mov r12, rdi
    mov r13, rsi

    mov rdi, r13
    call studio_is_authed
    test eax, eax
    jnz .Lhsca_parse
    mov rdi, r12; lea rsi, [rip + st_401]; lea rdx, [rip + j_err_unauth]; mov ecx, j_err_unauth_len; xor r8d, r8d
    call studio_send_json
    jmp .Lhsca_ret

.Lhsca_parse:
    mov rdi, rsp; lea rsi, [rip + st_f_name]; mov edx, 255; call sb_init
    mov rdi, [r13 + REQ_BODY_PTR]
    mov rsi, [r13 + REQ_BODY_LEN]
    lea rdx, [rip + jk_name]
    mov ecx, jk_name_len
    mov r8, rsp
    call json_get_str
    lea rdi, [rip + st_f_name]; mov rsi, [rsp + SB_LEN]; call trim_ws
    mov r14, rax          # name_ptr
    mov r15, rdx          # name_len

    mov rdi, r14; mov rsi, r15; call validate_cat_name
    test eax, eax
    jnz .Lhsca_dup
    mov rdi, r12; lea rsi, [rip + st_400]; lea rdx, [rip + j_err_cat]; mov ecx, j_err_cat_len; xor r8d, r8d
    call studio_send_json
    jmp .Lhsca_ret

.Lhsca_dup:
    # Check duplicate (case-insensitive)
    xor ebx, ebx
.Lhsca_dloop:
    cmp rbx, [rip + g_cat_count]
    jae .Lhsca_cap
    imul rax, rbx, CAT_SIZE
    lea r8, [rip + g_cats]
    mov rdi, [r8 + rax + CAT_NAME_PTR]
    mov rsi, [r8 + rax + CAT_NAME_LEN]
    mov rdx, r14
    mov rcx, r15
    call xslice_eq_ci
    test eax, eax
    jnz .Lhsca_exists
    inc rbx
    jmp .Lhsca_dloop

.Lhsca_exists:
    mov rdi, r12; lea rsi, [rip + st_200]; lea rdx, [rip + j_ok_exists]; mov ecx, j_ok_exists_len; xor r8d, r8d
    call studio_send_json
    jmp .Lhsca_ret

.Lhsca_cap:
    cmp qword ptr [rip + g_cat_count], MAX_CATEGORIES
    jb .Lhsca_write
    mov rdi, r12; lea rsi, [rip + st_400]; lea rdx, [rip + j_err_catmax]; mov ecx, j_err_catmax_len; xor r8d, r8d
    call studio_send_json
    jmp .Lhsca_ret

.Lhsca_write:
    mov rdi, rsp; lea rsi, [rip + st_file_buf]; mov edx, 65535; call sb_init
    xor ebx, ebx
.Lhsca_wloop:
    cmp rbx, [rip + g_cat_count]
    jae .Lhsca_wnew
    imul rax, rbx, CAT_SIZE
    lea r8, [rip + g_cats]
    mov rdi, rsp; mov rsi, [r8 + rax + CAT_NAME_PTR]; mov rdx, [r8 + rax + CAT_NAME_LEN]; call sb_mem
    mov rdi, rsp; mov esi, 10; call sb_byte
    inc rbx
    jmp .Lhsca_wloop
.Lhsca_wnew:
    mov rdi, rsp; mov rsi, r14; mov rdx, r15; call sb_mem
    mov rdi, rsp; mov esi, 10; call sb_byte

    lea rdi, [rip + st_d_content]; mov esi, 0755; call sys_mkdir
    lea rdi, [rip + st_f_cats]
    lea rsi, [rip + st_f_cats_tmp]
    lea rdx, [rip + st_file_buf]
    mov rcx, [rsp + SB_LEN]
    call write_file_atomic
    test rax, rax
    jns .Lhsca_ok
    mov rdi, r12; lea rsi, [rip + st_500]; lea rdx, [rip + j_err_write]; mov ecx, j_err_write_len; xor r8d, r8d
    call studio_send_json
    jmp .Lhsca_ret

.Lhsca_ok:
    call store_reload
    mov rdi, r12; lea rsi, [rip + st_200]; lea rdx, [rip + j_ok]; mov ecx, j_ok_len; xor r8d, r8d
    call studio_send_json

.Lhsca_ret:
    add rsp, 32
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# =========================================================================
# 10. POST /api/studio/categories/delete (removes category + clears it from matching posts)
# =========================================================================
.globl handle_studio_cat_del
handle_studio_cat_del:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 32
    mov r12, rdi
    mov r13, rsi

    mov rdi, r13
    call studio_is_authed
    test eax, eax
    jnz .Lhscd_parse
    mov rdi, r12; lea rsi, [rip + st_401]; lea rdx, [rip + j_err_unauth]; mov ecx, j_err_unauth_len; xor r8d, r8d
    call studio_send_json
    jmp .Lhscd_ret

.Lhscd_parse:
    mov rdi, rsp; lea rsi, [rip + st_f_name]; mov edx, 255; call sb_init
    mov rdi, [r13 + REQ_BODY_PTR]
    mov rsi, [r13 + REQ_BODY_LEN]
    lea rdx, [rip + jk_name]
    mov ecx, jk_name_len
    mov r8, rsp
    call json_get_str
    lea rdi, [rip + st_f_name]; mov rsi, [rsp + SB_LEN]; call trim_ws
    mov r14, rax
    mov r15, rdx
    test r15, r15
    jnz .Lhscd_cats
    mov rdi, r12; lea rsi, [rip + st_400]; lea rdx, [rip + j_err_cat]; mov ecx, j_err_cat_len; xor r8d, r8d
    call studio_send_json
    jmp .Lhscd_ret

.Lhscd_cats:
    # 1) Rewrite content/categories.txt omitting matching category
    mov rdi, rsp; lea rsi, [rip + st_file_buf]; mov edx, 65535; call sb_init
    xor ebx, ebx
.Lhscd_cloop:
    cmp rbx, [rip + g_cat_count]
    jae .Lhscd_cwrite
    imul rax, rbx, CAT_SIZE
    lea r8, [rip + g_cats]
    add r8, rax
    push r8
    mov rdi, [r8 + CAT_NAME_PTR]
    mov rsi, [r8 + CAT_NAME_LEN]
    mov rdx, r14
    mov rcx, r15
    call xslice_eq_ci
    pop r8
    test eax, eax
    jnz .Lhscd_cnext
    mov rdi, rsp; mov rsi, [r8 + CAT_NAME_PTR]; mov rdx, [r8 + CAT_NAME_LEN]; call sb_mem
    mov rdi, rsp; mov esi, 10; call sb_byte
.Lhscd_cnext:
    inc rbx
    jmp .Lhscd_cloop

.Lhscd_cwrite:
    lea rdi, [rip + st_d_content]; mov esi, 0755; call sys_mkdir
    lea rdi, [rip + st_f_cats]
    lea rsi, [rip + st_f_cats_tmp]
    lea rdx, [rip + st_file_buf]
    mov rcx, [rsp + SB_LEN]
    call write_file_atomic
    test rax, rax
    jns .Lhscd_posts
    mov rdi, r12; lea rsi, [rip + st_500]; lea rdx, [rip + j_err_write]; mov ecx, j_err_write_len; xor r8d, r8d
    call studio_send_json
    jmp .Lhscd_ret

.Lhscd_posts:
    # 2) Clear this category from any existing posts so store_reload won't resurrect it
    xor ebx, ebx
.Lhscd_ploop:
    cmp rbx, [rip + g_post_count]
    jae .Lhscd_reload
    lea r8, [rip + g_post_ptrs]
    mov r9, [r8 + rbx*8]
    cmp qword ptr [r9 + POST_CAT_LEN], 0
    je .Lhscd_pnext
    push r9
    mov rdi, [r9 + POST_CAT_PTR]
    mov rsi, [r9 + POST_CAT_LEN]
    mov rdx, r14
    mov rcx, r15
    call xslice_eq_ci
    pop r9
    test eax, eax
    jz .Lhscd_pnext
    mov rdi, r9
    mov esi, 1            # clear_cat = 1
    call studio_write_post_struct
.Lhscd_pnext:
    inc rbx
    jmp .Lhscd_ploop

.Lhscd_reload:
    call store_reload
    mov rdi, r12; lea rsi, [rip + st_200]; lea rdx, [rip + j_ok]; mov ecx, j_ok_len; xor r8d, r8d
    call studio_send_json

.Lhscd_ret:
    add rsp, 32
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# =========================================================================
# 11. POST /api/studio/upload (raw binary image upload with magic-byte check)
# =========================================================================
.globl handle_studio_upload
handle_studio_upload:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 48           # [rsp+0..23]=sbuf, [rsp+24]=ext_ptr, [rsp+32]=ext_len, [rsp+40]=fname_len
    mov r12, rdi
    mov r13, rsi

    mov rdi, r13
    call studio_is_authed
    test eax, eax
    jnz .Lhsu_size
    mov rdi, r12; lea rsi, [rip + st_401]; lea rdx, [rip + j_err_unauth]; mov ecx, j_err_unauth_len; xor r8d, r8d
    call studio_send_json
    jmp .Lhsu_ret

.Lhsu_size:
    mov r14, [r13 + REQ_BODY_PTR]
    mov r15, [r13 + REQ_BODY_LEN]
    cmp r15, 12
    jb .Lhsu_badsize
    cmp r15, MAX_BODY_BYTES
    jbe .Lhsu_magic
.Lhsu_badsize:
    mov rdi, r12; lea rsi, [rip + st_400]; lea rdx, [rip + j_err_imgsize]; mov ecx, j_err_imgsize_len; xor r8d, r8d
    call studio_send_json
    jmp .Lhsu_ret

.Lhsu_magic:
    # Check JPEG: FF D8 FF
    cmp byte ptr [r14 + 0], 0xff
    jne .Lhsu_png
    cmp byte ptr [r14 + 1], 0xd8
    jne .Lhsu_png
    cmp byte ptr [r14 + 2], 0xff
    jne .Lhsu_png
    lea rax, [rip + ext_jpg_s]
    mov qword ptr [rsp + 24], rax
    mov qword ptr [rsp + 32], 4
    jmp .Lhsu_save

.Lhsu_png:
    # Check PNG: 89 50 4E 47
    cmp dword ptr [r14 + 0], 0x474e5089
    jne .Lhsu_gif
    lea rax, [rip + ext_png_s]
    mov qword ptr [rsp + 24], rax
    mov qword ptr [rsp + 32], 4
    jmp .Lhsu_save

.Lhsu_gif:
    # Check GIF: 47 49 46 38 ("GIF8")
    cmp dword ptr [r14 + 0], 0x38464947
    jne .Lhsu_webp
    lea rax, [rip + ext_gif_s]
    mov qword ptr [rsp + 24], rax
    mov qword ptr [rsp + 32], 4
    jmp .Lhsu_save

.Lhsu_webp:
    # Check WebP: "RIFF" ... "WEBP"
    cmp dword ptr [r14 + 0], 0x46464952
    jne .Lhsu_badtype
    cmp dword ptr [r14 + 8], 0x50424557
    jne .Lhsu_badtype
    lea rax, [rip + ext_webp_s]
    mov qword ptr [rsp + 24], rax
    mov qword ptr [rsp + 32], 5
    jmp .Lhsu_save

.Lhsu_badtype:
    mov rdi, r12; lea rsi, [rip + st_400]; lea rdx, [rip + j_err_imgtype]; mov ecx, j_err_imgtype_len; xor r8d, r8d
    call studio_send_json
    jmp .Lhsu_ret

.Lhsu_save:
    lea rdi, [rip + st_d_content]; mov esi, 0755; call sys_mkdir
    lea rdi, [rip + st_d_uploads]; mov esi, 0755; call sys_mkdir

    # Generate random 4 bytes
    lea rdi, [rip + st_rand_buf]
    mov esi, 4
    xor edx, edx
    call sys_getrandom
    cmp rax, 4
    je .Lhsu_fname
    call mono_sec
    mov [rip + st_rand_buf], eax

.Lhsu_fname:
    call real_sec
    mov rbx, rax
    mov rdi, rsp; lea rsi, [rip + st_f_slug]; mov edx, 127; call sb_init
    mov rdi, rsp; mov rsi, rbx; call sb_uint
    mov rdi, rsp; mov esi, '-'; call sb_byte
    mov rdi, rsp; lea rsi, [rip + st_rand_buf]; mov edx, 4; call sb_hex
    mov rdi, rsp; mov rsi, [rsp + 24]; mov rdx, [rsp + 32]; call sb_mem
    mov rax, [rsp + SB_LEN]
    mov [rsp + 40], rax

    # Final path content/uploads/<fname>\0
    mov rdi, rsp; lea rsi, [rip + st_path_buf]; mov edx, 511; call sb_init
    mov rdi, rsp; lea rsi, [rip + st_p_up_pre]; mov edx, st_p_up_pre_len; call sb_mem
    mov rdi, rsp; lea rsi, [rip + st_f_slug]; mov rdx, [rsp + 40]; call sb_mem
    mov rdi, rsp; xor esi, esi; call sb_byte

    # Tmp path content/uploads/.<fname>.tmp\0
    mov rdi, rsp; lea rsi, [rip + st_tmp_buf]; mov edx, 511; call sb_init
    mov rdi, rsp; lea rsi, [rip + st_p_up_dot]; mov edx, st_p_up_dot_len; call sb_mem
    mov rdi, rsp; lea rsi, [rip + st_f_slug]; mov rdx, [rsp + 40]; call sb_mem
    mov rdi, rsp; lea rsi, [rip + st_p_tmp_suf]; mov edx, st_p_tmp_suf_len; call sb_mem
    mov rdi, rsp; xor esi, esi; call sb_byte

    lea rdi, [rip + st_path_buf]
    lea rsi, [rip + st_tmp_buf]
    mov rdx, r14
    mov rcx, r15
    call write_file_atomic
    test rax, rax
    jns .Lhsu_ok
    mov rdi, r12; lea rsi, [rip + st_500]; lea rdx, [rip + j_err_write]; mov ecx, j_err_write_len; xor r8d, r8d
    call studio_send_json
    jmp .Lhsu_ret

.Lhsu_ok:
    mov rdi, rsp; lea rsi, [rip + st_resp_buf]; mov edx, 511; call sb_init
    mov rdi, rsp; lea rsi, [rip + j_ok_url_1]; mov edx, j_ok_url_1_len; call sb_mem
    mov rdi, rsp; lea rsi, [rip + st_f_slug]; mov rdx, [rsp + 40]; call sb_mem
    mov rdi, rsp; lea rsi, [rip + j_close_obj]; mov edx, j_close_obj_len; call sb_mem

    mov rdi, r12
    lea rsi, [rip + st_201]
    lea rdx, [rip + st_resp_buf]
    mov rcx, [rsp + SB_LEN]
    xor r8d, r8d
    call studio_send_json

.Lhsu_ret:
    add rsp, 48
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# is_safe_vid_id(rdi=ptr, rsi=len) -> eax=1 if safe video upload id (no traversal, valid video ext)
is_safe_vid_id:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    cmp r13, 10
    jb .Lsvi_no
    cmp r13, 64
    ja .Lsvi_no
    xor ebx, ebx
.Lsvi_loop:
    cmp rbx, r13
    jae .Lsvi_ext
    movzx eax, byte ptr [r12 + rbx]
    cmp al, '0'
    jb .Lsvi_chk_sym
    cmp al, '9'
    jbe .Lsvi_next
.Lsvi_chk_sym:
    cmp al, 'a'
    jb .Lsvi_chk_dash
    cmp al, 'z'
    jbe .Lsvi_next
.Lsvi_chk_dash:
    cmp al, '-'
    je .Lsvi_next
    cmp al, '.'
    jne .Lsvi_no
    # Reject leading dot or consecutive ".."
    test rbx, rbx
    jz .Lsvi_no
    cmp byte ptr [r12 + rbx - 1], '.'
    je .Lsvi_no
.Lsvi_next:
    inc rbx
    jmp .Lsvi_loop
.Lsvi_ext:
    lea rdi, [r12 + r13 - 4]; mov esi, 4; lea rdx, [rip + ext_mp4_s]; mov ecx, 4; call xslice_eq
    test eax, eax; jnz .Lsvi_yes
    lea rdi, [r12 + r13 - 4]; mov esi, 4; lea rdx, [rip + ext_mov_s]; mov ecx, 4; call xslice_eq
    test eax, eax; jnz .Lsvi_yes
    lea rdi, [r12 + r13 - 4]; mov esi, 4; lea rdx, [rip + ext_ogg_s]; mov ecx, 4; call xslice_eq
    test eax, eax; jnz .Lsvi_yes
    lea rdi, [r12 + r13 - 5]; mov esi, 5; lea rdx, [rip + ext_webm_s]; mov ecx, 5; call xslice_eq
    test eax, eax; jnz .Lsvi_yes
.Lsvi_no:
    xor eax, eax
    jmp .Lsvi_ret
.Lsvi_yes:
    mov eax, 1
.Lsvi_ret:
    pop r13
    pop r12
    pop rbx
    ret

# =========================================================================
# 11b. POST /api/studio/upload-video (chunked streaming video upload <= 100 MiB)
#   Query: ?done=1 (finalize) and optional ?id=<fname> (append chunk)
# =========================================================================
.globl handle_studio_upload_video
handle_studio_upload_video:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 216          # [0..23]=sbuf, [24]=ext_ptr, [32]=ext_len, [40]=fname_len, [48]=done, [56]=fd, [64..207]=stat
    mov r12, rdi
    mov r13, rsi

    mov rdi, r13
    call studio_is_authed
    test eax, eax
    jnz .Lhsuv_chk_sz
    mov rdi, r12; lea rsi, [rip + st_401]; lea rdx, [rip + j_err_unauth]; mov ecx, j_err_unauth_len; xor r8d, r8d
    call studio_send_json
    jmp .Lhsuv_ret

.Lhsuv_chk_sz:
    mov r14, [r13 + REQ_BODY_PTR]
    mov r15, [r13 + REQ_BODY_LEN]
    test r15, r15
    jz .Lhsuv_badsize
    cmp r15, MAX_BODY_BYTES
    ja .Lhsuv_badsize

    # Parse ?done=1
    mov qword ptr [rsp + 48], 0
    mov rdi, rsp; lea rsi, [rip + st_f_draft]; mov edx, 15; call sb_init
    mov rdi, r13; lea rsi, [rip + qk_done]; mov edx, 4; mov rcx, rsp; call http_query_get
    cmp qword ptr [rsp + SB_LEN], 1
    jne .Lhsuv_get_id
    cmp byte ptr [rip + st_f_draft], '1'
    jne .Lhsuv_get_id
    mov qword ptr [rsp + 48], 1

.Lhsuv_get_id:
    mov rdi, rsp; lea rsi, [rip + st_f_slug]; mov edx, 127; call sb_init
    mov rdi, r13; lea rsi, [rip + qk_id]; mov edx, 2; mov rcx, rsp; call http_query_get
    mov rbx, [rsp + SB_LEN]
    test rbx, rbx
    jnz .Lhsuv_append

    # --- Chunk 0: verify video magic bytes ---
    cmp r15, 12
    jb .Lhsuv_badtype
    # MP4 / MOV: bytes[4..7] == "ftyp" (0x70797466)
    cmp dword ptr [r14 + 4], 0x70797466
    jne .Lhsuv_chk_webm
    cmp dword ptr [r14 + 8], 0x20207471       # "qt  " -> QuickTime .mov
    je .Lhsuv_is_mov
    lea rax, [rip + ext_mp4_s]; mov [rsp + 24], rax; mov qword ptr [rsp + 32], 4
    jmp .Lhsuv_newfile
.Lhsuv_is_mov:
    lea rax, [rip + ext_mov_s]; mov [rsp + 24], rax; mov qword ptr [rsp + 32], 4
    jmp .Lhsuv_newfile

.Lhsuv_chk_webm:
    # WebM / MKV EBML header: 1A 45 DF A3
    cmp dword ptr [r14 + 0], 0xa3df451a
    jne .Lhsuv_chk_ogg
    lea rax, [rip + ext_webm_s]; mov [rsp + 24], rax; mov qword ptr [rsp + 32], 5
    jmp .Lhsuv_newfile

.Lhsuv_chk_ogg:
    # OGG / OGV header: "OggS"
    cmp dword ptr [r14 + 0], 0x5367674f
    jne .Lhsuv_badtype
    lea rax, [rip + ext_ogg_s]; mov [rsp + 24], rax; mov qword ptr [rsp + 32], 4

.Lhsuv_newfile:
    lea rdi, [rip + st_d_content]; mov esi, 0755; call sys_mkdir
    lea rdi, [rip + st_d_uploads]; mov esi, 0755; call sys_mkdir

    lea rdi, [rip + st_rand_buf]; mov esi, 4; xor edx, edx; call sys_getrandom
    cmp rax, 4
    je .Lhsuv_mkname
    call mono_sec
    mov [rip + st_rand_buf], eax
.Lhsuv_mkname:
    call real_sec
    mov rbx, rax
    mov rdi, rsp; lea rsi, [rip + st_f_slug]; mov edx, 127; call sb_init
    mov rdi, rsp; mov rsi, rbx; call sb_uint
    mov rdi, rsp; mov esi, '-'; call sb_byte
    mov rdi, rsp; lea rsi, [rip + st_rand_buf]; mov edx, 4; call sb_hex
    mov rdi, rsp; mov rsi, [rsp + 24]; mov rdx, [rsp + 32]; call sb_mem
    mov rax, [rsp + SB_LEN]
    mov [rsp + 40], rax

    # Build final path & hidden .part path
    mov rdi, rsp; lea rsi, [rip + st_path_buf]; mov edx, 511; call sb_init
    mov rdi, rsp; lea rsi, [rip + st_p_up_pre]; mov edx, st_p_up_pre_len; call sb_mem
    mov rdi, rsp; lea rsi, [rip + st_f_slug]; mov rdx, [rsp + 40]; call sb_mem
    mov rdi, rsp; xor esi, esi; call sb_byte

    mov rdi, rsp; lea rsi, [rip + st_tmp_buf]; mov edx, 511; call sb_init
    mov rdi, rsp; lea rsi, [rip + st_p_up_dot]; mov edx, st_p_up_dot_len; call sb_mem
    mov rdi, rsp; lea rsi, [rip + st_f_slug]; mov rdx, [rsp + 40]; call sb_mem
    mov rdi, rsp; lea rsi, [rip + st_p_part_suf]; mov edx, st_p_part_suf_len; call sb_mem
    mov rdi, rsp; xor esi, esi; call sb_byte

    mov rdi, AT_FDCWD
    lea rsi, [rip + st_tmp_buf]
    mov edx, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW | O_CLOEXEC
    mov ecx, 0644
    call sys_openat
    test rax, rax
    js .Lhsuv_wrerr
    mov [rsp + 56], rax
    mov rdi, rax; mov rsi, r14; mov rdx, r15; call write_all
    push rax
    mov rdi, [rsp + 64]; call sys_close
    pop rax
    test rax, rax
    js .Lhsuv_unlink_err
    jmp .Lhsuv_finish

.Lhsuv_append:
    lea rdi, [rip + st_f_slug]
    mov rsi, rbx
    call is_safe_vid_id
    test eax, eax
    jz .Lhsuv_badid
    mov [rsp + 40], rbx

    mov rdi, rsp; lea rsi, [rip + st_path_buf]; mov edx, 511; call sb_init
    mov rdi, rsp; lea rsi, [rip + st_p_up_pre]; mov edx, st_p_up_pre_len; call sb_mem
    mov rdi, rsp; lea rsi, [rip + st_f_slug]; mov rdx, [rsp + 40]; call sb_mem
    mov rdi, rsp; xor esi, esi; call sb_byte

    mov rdi, rsp; lea rsi, [rip + st_tmp_buf]; mov edx, 511; call sb_init
    mov rdi, rsp; lea rsi, [rip + st_p_up_dot]; mov edx, st_p_up_dot_len; call sb_mem
    mov rdi, rsp; lea rsi, [rip + st_f_slug]; mov rdx, [rsp + 40]; call sb_mem
    mov rdi, rsp; lea rsi, [rip + st_p_part_suf]; mov edx, st_p_part_suf_len; call sb_mem
    mov rdi, rsp; xor esi, esi; call sb_byte

    mov rdi, AT_FDCWD
    lea rsi, [rip + st_tmp_buf]
    mov edx, O_WRONLY | O_APPEND | O_NOFOLLOW | O_CLOEXEC
    xor ecx, ecx
    call sys_openat
    test rax, rax
    js .Lhsuv_badid
    mov [rsp + 56], rax

    mov rdi, rax
    lea rsi, [rsp + 64]
    call sys_fstat
    test rax, rax
    js .Lhsuv_close_wrerr
    mov rax, [rsp + 64 + STAT_SIZE]
    add rax, r15
    cmp rax, MAX_VIDEO_BYTES
    ja .Lhsuv_too_big

    mov rdi, [rsp + 56]; mov rsi, r14; mov rdx, r15; call write_all
    push rax
    mov rdi, [rsp + 64]; call sys_close
    pop rax
    test rax, rax
    js .Lhsuv_wrerr

.Lhsuv_finish:
    cmp qword ptr [rsp + 48], 0
    je .Lhsuv_more

    lea rdi, [rip + st_tmp_buf]
    lea rsi, [rip + st_path_buf]
    call sys_rename
    test rax, rax
    js .Lhsuv_unlink_err

    mov rdi, rsp; lea rsi, [rip + st_resp_buf]; mov edx, 511; call sb_init
    mov rdi, rsp; lea rsi, [rip + j_ok_url_1]; mov edx, j_ok_url_1_len; call sb_mem
    mov rdi, rsp; lea rsi, [rip + st_f_slug]; mov rdx, [rsp + 40]; call sb_mem
    mov rdi, rsp; lea rsi, [rip + j_close_obj]; mov edx, j_close_obj_len; call sb_mem
    mov rdi, r12; lea rsi, [rip + st_200]; lea rdx, [rip + st_resp_buf]; mov rcx, [rsp + SB_LEN]; xor r8d, r8d
    call studio_send_json
    jmp .Lhsuv_ret

.Lhsuv_more:
    mov rdi, rsp; lea rsi, [rip + st_resp_buf]; mov edx, 511; call sb_init
    mov rdi, rsp; lea rsi, [rip + j_ok_id_1]; mov edx, j_ok_id_1_len; call sb_mem
    mov rdi, rsp; lea rsi, [rip + st_f_slug]; mov rdx, [rsp + 40]; call sb_mem
    mov rdi, rsp; lea rsi, [rip + j_close_obj]; mov edx, j_close_obj_len; call sb_mem
    mov rdi, r12; lea rsi, [rip + st_200]; lea rdx, [rip + st_resp_buf]; mov rcx, [rsp + SB_LEN]; xor r8d, r8d
    call studio_send_json
    jmp .Lhsuv_ret

.Lhsuv_too_big:
    mov rdi, [rsp + 56]; call sys_close
    lea rdi, [rip + st_tmp_buf]; call sys_unlink
.Lhsuv_badsize:
    mov rdi, r12; lea rsi, [rip + st_400]; lea rdx, [rip + j_err_vidsize]; mov ecx, j_err_vidsize_len; xor r8d, r8d
    call studio_send_json
    jmp .Lhsuv_ret
.Lhsuv_badtype:
    mov rdi, r12; lea rsi, [rip + st_400]; lea rdx, [rip + j_err_vidtype]; mov ecx, j_err_vidtype_len; xor r8d, r8d
    call studio_send_json
    jmp .Lhsuv_ret
.Lhsuv_badid:
    mov rdi, r12; lea rsi, [rip + st_400]; lea rdx, [rip + j_err_vidid]; mov ecx, j_err_vidid_len; xor r8d, r8d
    call studio_send_json
    jmp .Lhsuv_ret
.Lhsuv_close_wrerr:
    mov rdi, [rsp + 56]; call sys_close
    jmp .Lhsuv_wrerr
.Lhsuv_unlink_err:
    lea rdi, [rip + st_tmp_buf]; call sys_unlink
.Lhsuv_wrerr:
    mov rdi, r12; lea rsi, [rip + st_500]; lea rdx, [rip + j_err_write]; mov ecx, j_err_write_len; xor r8d, r8d
    call studio_send_json
.Lhsuv_ret:
    add rsp, 216
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

# =========================================================================
# 12. GET /api/studio/settings (returns current site & appearance config)
# =========================================================================
.globl handle_studio_settings_get
handle_studio_settings_get:
    push r12
    push r13
    sub rsp, 40
    mov r12, rdi
    mov r13, rsi

    mov rdi, r13
    call studio_is_authed
    test eax, eax
    jnz .Lhssg_ok
    mov rdi, r12; lea rsi, [rip + st_401]; lea rdx, [rip + j_err_unauth]; mov ecx, j_err_unauth_len; xor r8d, r8d
    call studio_send_json
    jmp .Lhssg_ret

.Lhssg_ok:
    mov rdi, rsp; lea rsi, [rip + st_resp_buf]; mov edx, 16383; call sb_init
    mov rdi, rsp; lea rsi, [rip + js_1]; mov edx, js_1_len; call sb_mem
    mov rdi, rsp; lea rsi, [rip + g_cfg_site_name]; mov rdx, [rip + g_cfg_site_name_len]; call sb_esc_json
    mov rdi, rsp; lea rsi, [rip + js_2]; mov edx, js_2_len; call sb_mem
    mov rdi, rsp; lea rsi, [rip + g_cfg_subtitle]; mov rdx, [rip + g_cfg_subtitle_len]; call sb_esc_json
    mov rdi, rsp; lea rsi, [rip + js_3]; mov edx, js_3_len; call sb_mem
    mov rdi, rsp; lea rsi, [rip + g_cfg_author]; mov rdx, [rip + g_cfg_author_len]; call sb_esc_json
    mov rdi, rsp; lea rsi, [rip + js_4]; mov edx, js_4_len; call sb_mem
    mov rdi, rsp; lea rsi, [rip + g_cfg_footer]; mov rdx, [rip + g_cfg_footer_len]; call sb_esc_json
    mov rdi, rsp; lea rsi, [rip + js_5]; mov edx, js_5_len; call sb_mem
    mov rdi, rsp; lea rsi, [rip + g_cfg_site_url]; mov rdx, [rip + g_cfg_site_url_len]; call sb_esc_json
    mov rdi, rsp; lea rsi, [rip + js_6]; mov edx, js_6_len; call sb_mem
    mov rdi, rsp; lea rsi, [rip + g_cfg_avatar]; mov rdx, [rip + g_cfg_avatar_len]; call sb_esc_json
    mov rdi, rsp; lea rsi, [rip + js_7]; mov edx, js_7_len; call sb_mem
    mov rdi, rsp; lea rsi, [rip + g_cfg_banner]; mov rdx, [rip + g_cfg_banner_len]; call sb_esc_json
    mov rdi, rsp; lea rsi, [rip + js_8]; mov edx, js_8_len; call sb_mem
    mov rdi, rsp; lea rsi, [rip + g_cfg_studio_path]; mov rdx, [rip + g_cfg_studio_path_len]; call sb_esc_json
    mov rdi, rsp; lea rsi, [rip + js_9]; mov edx, js_9_len; call sb_mem
    mov rdi, rsp; mov rsi, [rip + g_cfg_per_page]; call sb_uint
    mov rdi, rsp; lea rsi, [rip + js_10]; mov edx, js_10_len; call sb_mem
    mov rdi, rsp; lea rsi, [rip + g_cfg_giscus_repo]; mov rdx, [rip + g_cfg_giscus_repo_len]; call sb_esc_json
    mov rdi, rsp; lea rsi, [rip + js_11]; mov edx, js_11_len; call sb_mem
    mov rdi, rsp; lea rsi, [rip + g_cfg_giscus_repo_id]; mov rdx, [rip + g_cfg_giscus_repo_id_len]; call sb_esc_json
    mov rdi, rsp; lea rsi, [rip + js_12]; mov edx, js_12_len; call sb_mem
    mov rdi, rsp; lea rsi, [rip + g_cfg_giscus_cat]; mov rdx, [rip + g_cfg_giscus_cat_len]; call sb_esc_json
    mov rdi, rsp; lea rsi, [rip + js_13]; mov edx, js_13_len; call sb_mem
    mov rdi, rsp; lea rsi, [rip + g_cfg_giscus_cat_id]; mov rdx, [rip + g_cfg_giscus_cat_id_len]; call sb_esc_json
    mov rdi, rsp; lea rsi, [rip + j_close_obj]; mov edx, j_close_obj_len; call sb_mem

    mov rdi, r12
    lea rsi, [rip + st_200]
    lea rdx, [rip + st_resp_buf]
    mov rcx, [rsp + SB_LEN]
    xor r8d, r8d
    call studio_send_json

.Lhssg_ret:
    add rsp, 40
    pop r13
    pop r12
    ret

# =========================================================================
# 13. POST /api/studio/settings (updates config.ini atomically & hot-reloads)
# =========================================================================
.globl handle_studio_settings_save
handle_studio_settings_save:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 264
    mov r12, rdi
    mov r13, rsi

    mov rdi, r13
    call studio_is_authed
    test eax, eax
    jnz .Lhsss_init
    mov rdi, r12; lea rsi, [rip + st_401]; lea rdx, [rip + j_err_unauth]; mov ecx, j_err_unauth_len; xor r8d, r8d
    call studio_send_json
    jmp .Lhsss_ret

.Lhsss_init:
    mov r14, [r13 + REQ_BODY_PTR]
    mov r15, [r13 + REQ_BODY_LEN]

    # Seed defaults from current live config
    lea rax, [rip + g_cfg_site_name];   mov [rsp + 24], rax;  mov rax, [rip + g_cfg_site_name_len];   mov [rsp + 32], rax
    lea rax, [rip + g_cfg_subtitle];    mov [rsp + 40], rax;  mov rax, [rip + g_cfg_subtitle_len];    mov [rsp + 48], rax
    lea rax, [rip + g_cfg_author];      mov [rsp + 56], rax;  mov rax, [rip + g_cfg_author_len];      mov [rsp + 64], rax
    lea rax, [rip + g_cfg_footer];      mov [rsp + 72], rax;  mov rax, [rip + g_cfg_footer_len];      mov [rsp + 80], rax
    lea rax, [rip + g_cfg_site_url];    mov [rsp + 88], rax;  mov rax, [rip + g_cfg_site_url_len];    mov [rsp + 96], rax
    lea rax, [rip + g_cfg_avatar];      mov [rsp + 104], rax; mov rax, [rip + g_cfg_avatar_len];      mov [rsp + 112], rax
    lea rax, [rip + g_cfg_banner];      mov [rsp + 120], rax; mov rax, [rip + g_cfg_banner_len];      mov [rsp + 128], rax
    lea rax, [rip + g_cfg_studio_path]; mov [rsp + 136], rax; mov rax, [rip + g_cfg_studio_path_len]; mov [rsp + 144], rax
    mov rax, [rip + g_cfg_per_page];    mov [rsp + 152], rax
    lea rax, [rip + g_cfg_studio_hash]; mov [rsp + 160], rax
    mov qword ptr [rsp + 168], 0
    lea rax, [rip + g_cfg_giscus_repo];    mov [rsp + 184], rax; mov rax, [rip + g_cfg_giscus_repo_len];    mov [rsp + 192], rax
    lea rax, [rip + g_cfg_giscus_repo_id]; mov [rsp + 200], rax; mov rax, [rip + g_cfg_giscus_repo_id_len]; mov [rsp + 208], rax
    lea rax, [rip + g_cfg_giscus_cat];     mov [rsp + 216], rax; mov rax, [rip + g_cfg_giscus_cat_len];     mov [rsp + 224], rax
    lea rax, [rip + g_cfg_giscus_cat_id];  mov [rsp + 232], rax; mov rax, [rip + g_cfg_giscus_cat_id_len];  mov [rsp + 240], rax

    # site_name (non-empty)
    mov rdi, rsp; lea rsi, [rip + st_s_site_name]; mov edx, 127; call sb_init
    mov rdi, r14; mov rsi, r15; lea rdx, [rip + jk_site_name]; mov ecx, jk_site_name_len; mov r8, rsp; call json_get_str
    test eax, eax
    jz .Lhsss_sub
    lea rdi, [rip + st_s_site_name]; mov rsi, [rsp + SB_LEN]; call trim_ws
    test rdx, rdx
    jz .Lhsss_sub
    mov [rsp + 24], rax; mov [rsp + 32], rdx

.Lhsss_sub:
    mov rdi, rsp; lea rsi, [rip + st_s_subtitle]; mov edx, 255; call sb_init
    mov rdi, r14; mov rsi, r15; lea rdx, [rip + jk_subtitle]; mov ecx, jk_subtitle_len; mov r8, rsp; call json_get_str
    test eax, eax
    jz .Lhsss_auth
    lea rdi, [rip + st_s_subtitle]; mov rsi, [rsp + SB_LEN]; call trim_ws
    mov [rsp + 40], rax; mov [rsp + 48], rdx

.Lhsss_auth:
    mov rdi, rsp; lea rsi, [rip + st_s_author]; mov edx, 127; call sb_init
    mov rdi, r14; mov rsi, r15; lea rdx, [rip + jk_author]; mov ecx, jk_author_len; mov r8, rsp; call json_get_str
    test eax, eax
    jz .Lhsss_foot
    lea rdi, [rip + st_s_author]; mov rsi, [rsp + SB_LEN]; call trim_ws
    test rdx, rdx
    jz .Lhsss_foot
    mov [rsp + 56], rax; mov [rsp + 64], rdx

.Lhsss_foot:
    mov rdi, rsp; lea rsi, [rip + st_s_footer]; mov edx, 255; call sb_init
    mov rdi, r14; mov rsi, r15; lea rdx, [rip + jk_footer]; mov ecx, jk_footer_len; mov r8, rsp; call json_get_str
    test eax, eax
    jz .Lhsss_url
    lea rdi, [rip + st_s_footer]; mov rsi, [rsp + SB_LEN]; call trim_ws
    mov [rsp + 72], rax; mov [rsp + 80], rdx

.Lhsss_url:
    mov rdi, rsp; lea rsi, [rip + st_s_site_url]; mov edx, 255; call sb_init
    mov rdi, r14; mov rsi, r15; lea rdx, [rip + jk_site_url]; mov ecx, jk_site_url_len; mov r8, rsp; call json_get_str
    test eax, eax
    jz .Lhsss_ava
    lea rdi, [rip + st_s_site_url]; mov rsi, [rsp + SB_LEN]; call trim_ws
    test rdx, rdx
    jz .Lhsss_ava
    push rax; push rdx
    mov rdi, rax; mov rsi, rdx; call is_safe_url
    pop rdx; pop rcx
    test eax, eax
    jz .Lhsss_badurl
    mov [rsp + 88], rcx; mov [rsp + 96], rdx

.Lhsss_ava:
    mov rdi, rsp; lea rsi, [rip + st_s_avatar]; mov edx, 255; call sb_init
    mov rdi, r14; mov rsi, r15; lea rdx, [rip + jk_avatar]; mov ecx, jk_avatar_len; mov r8, rsp; call json_get_str
    test eax, eax
    jz .Lhsss_ban
    lea rdi, [rip + st_s_avatar]; mov rsi, [rsp + SB_LEN]; call trim_ws
    test rdx, rdx
    jz .Lhsss_ban
    push rax; push rdx
    mov rdi, rax; mov rsi, rdx; call is_safe_url
    pop rdx; pop rcx
    test eax, eax
    jz .Lhsss_badurl
    mov [rsp + 104], rcx; mov [rsp + 112], rdx

.Lhsss_ban:
    mov rdi, rsp; lea rsi, [rip + st_s_banner]; mov edx, 255; call sb_init
    mov rdi, r14; mov rsi, r15; lea rdx, [rip + jk_banner]; mov ecx, jk_banner_len; mov r8, rsp; call json_get_str
    test eax, eax
    jz .Lhsss_sp
    lea rdi, [rip + st_s_banner]; mov rsi, [rsp + SB_LEN]; call trim_ws
    test rdx, rdx
    jz .Lhsss_sp
    push rax; push rdx
    mov rdi, rax; mov rsi, rdx; call is_safe_url
    pop rdx; pop rcx
    test eax, eax
    jz .Lhsss_badurl
    mov [rsp + 120], rcx; mov [rsp + 128], rdx

.Lhsss_sp:
    mov rdi, rsp; lea rsi, [rip + st_s_spath]; mov edx, 95; call sb_init
    mov rdi, r14; mov rsi, r15; lea rdx, [rip + jk_spath]; mov ecx, jk_spath_len; mov r8, rsp; call json_get_str
    test eax, eax
    jz .Lhsss_pp
    lea rdi, [rip + st_s_spath]; mov rsi, [rsp + SB_LEN]; call trim_ws
    test rdx, rdx
    jz .Lhsss_pp
    cmp rdx, 2
    jb .Lhsss_badsp
    cmp rdx, 64
    ja .Lhsss_badsp
    cmp byte ptr [rax], '/'
    jne .Lhsss_badsp
    cmp byte ptr [rax + rdx - 1], '/'
    jne .Lhsss_sp_v
    dec rdx
    cmp rdx, 2
    jb .Lhsss_badsp
.Lhsss_sp_v:
    push rax; push rdx
    lea rdi, [rax + 1]
    lea rsi, [rdx - 1]
    call is_safe_slug
    pop rdx; pop rcx
    test eax, eax
    jz .Lhsss_badsp
    mov [rsp + 136], rcx; mov [rsp + 144], rdx

.Lhsss_pp:
    mov rdi, rsp; lea rsi, [rip + st_s_perpage]; mov edx, 31; call sb_init
    mov rdi, r14; mov rsi, r15; lea rdx, [rip + jk_per_page]; mov ecx, jk_per_page_len; mov r8, rsp; call json_get_str
    test eax, eax
    jz .Lhsss_np
    lea rdi, [rip + st_s_perpage]; mov rsi, [rsp + SB_LEN]; call trim_ws
    test rdx, rdx
    jz .Lhsss_np
    mov rdi, rax; mov rsi, rdx; call parse_uint
    test edx, edx
    jz .Lhsss_np
    cmp rax, 1
    jb .Lhsss_np
    cmp rax, 50
    ja .Lhsss_np
    mov [rsp + 152], rax

.Lhsss_np:
    mov rdi, rsp; lea rsi, [rip + st_s_newpass]; mov edx, 255; call sb_init
    mov rdi, r14; mov rsi, r15; lea rdx, [rip + jk_new_pass]; mov ecx, jk_new_pass_len; mov r8, rsp; call json_get_str
    test eax, eax
    jz .Lhsss_g_repo
    mov rsi, [rsp + SB_LEN]
    test rsi, rsi
    jz .Lhsss_g_repo
    cmp rsi, 4
    jb .Lhsss_shortpw
    lea rdi, [rip + st_s_newpass]
    lea rdx, [rip + st_s_newhash]
    call sha256_hex
    lea rax, [rip + st_s_newhash]
    mov [rsp + 160], rax
    mov qword ptr [rsp + 168], 1

.Lhsss_g_repo:
    mov rdi, rsp; lea rsi, [rip + st_s_g_repo]; mov edx, 127; call sb_init
    mov rdi, r14; mov rsi, r15; lea rdx, [rip + jk_g_repo]; mov ecx, jk_g_repo_len; mov r8, rsp; call json_get_str
    test eax, eax
    jz .Lhsss_g_rid
    lea rdi, [rip + st_s_g_repo]; mov rsi, [rsp + SB_LEN]; call trim_ws
    mov [rsp + 184], rax; mov [rsp + 192], rdx

.Lhsss_g_rid:
    mov rdi, rsp; lea rsi, [rip + st_s_g_rid]; mov edx, 127; call sb_init
    mov rdi, r14; mov rsi, r15; lea rdx, [rip + jk_g_rid]; mov ecx, jk_g_rid_len; mov r8, rsp; call json_get_str
    test eax, eax
    jz .Lhsss_g_cat
    lea rdi, [rip + st_s_g_rid]; mov rsi, [rsp + SB_LEN]; call trim_ws
    mov [rsp + 200], rax; mov [rsp + 208], rdx

.Lhsss_g_cat:
    mov rdi, rsp; lea rsi, [rip + st_s_g_cat]; mov edx, 127; call sb_init
    mov rdi, r14; mov rsi, r15; lea rdx, [rip + jk_g_cat]; mov ecx, jk_g_cat_len; mov r8, rsp; call json_get_str
    test eax, eax
    jz .Lhsss_g_cid
    lea rdi, [rip + st_s_g_cat]; mov rsi, [rsp + SB_LEN]; call trim_ws
    mov [rsp + 216], rax; mov [rsp + 224], rdx

.Lhsss_g_cid:
    mov rdi, rsp; lea rsi, [rip + st_s_g_cid]; mov edx, 127; call sb_init
    mov rdi, r14; mov rsi, r15; lea rdx, [rip + jk_g_cid]; mov ecx, jk_g_cid_len; mov r8, rsp; call json_get_str
    test eax, eax
    jz .Lhsss_build
    lea rdi, [rip + st_s_g_cid]; mov rsi, [rsp + SB_LEN]; call trim_ws
    mov [rsp + 232], rax; mov [rsp + 240], rdx

.Lhsss_build:
    mov rdi, rsp; lea rsi, [rip + st_file_buf]; mov edx, 16383; call sb_init
    mov rdi, rsp; lea rsi, [rip + ci_head];   mov edx, ci_head_len;   call sb_mem
    mov rdi, rsp; mov rsi, [rsp + 24];        mov rdx, [rsp + 32];    call sb_ini_safe
    mov rdi, rsp; lea rsi, [rip + ci_sub];    mov edx, ci_sub_len;    call sb_mem
    mov rdi, rsp; mov rsi, [rsp + 40];        mov rdx, [rsp + 48];    call sb_ini_safe
    mov rdi, rsp; lea rsi, [rip + ci_url];    mov edx, ci_url_len;    call sb_mem
    mov rdi, rsp; mov rsi, [rsp + 88];        mov rdx, [rsp + 96];    call sb_ini_safe
    mov rdi, rsp; lea rsi, [rip + ci_author]; mov edx, ci_author_len; call sb_mem
    mov rdi, rsp; mov rsi, [rsp + 56];        mov rdx, [rsp + 64];    call sb_ini_safe
    mov rdi, rsp; lea rsi, [rip + ci_footer]; mov edx, ci_footer_len; call sb_mem
    mov rdi, rsp; mov rsi, [rsp + 72];        mov rdx, [rsp + 80];    call sb_ini_safe
    mov rdi, rsp; lea rsi, [rip + ci_avatar]; mov edx, ci_avatar_len; call sb_mem
    mov rdi, rsp; mov rsi, [rsp + 104];       mov rdx, [rsp + 112];   call sb_ini_safe
    mov rdi, rsp; lea rsi, [rip + ci_banner]; mov edx, ci_banner_len; call sb_mem
    mov rdi, rsp; mov rsi, [rsp + 120];       mov rdx, [rsp + 128];   call sb_ini_safe
    mov rdi, rsp; lea rsi, [rip + ci_port];   mov edx, ci_port_len;   call sb_mem
    mov rdi, rsp; mov rsi, [rip + g_cfg_port]; call sb_uint
    mov rdi, rsp; lea rsi, [rip + ci_pp];     mov edx, ci_pp_len;     call sb_mem
    mov rdi, rsp; mov rsi, [rsp + 152];       call sb_uint
    mov rdi, rsp; lea rsi, [rip + ci_theme];  mov edx, ci_theme_len;  call sb_mem
    mov rdi, rsp; lea rsi, [rip + g_cfg_theme]; mov rdx, [rip + g_cfg_theme_len]; call sb_ini_safe
    mov rdi, rsp; lea rsi, [rip + ci_dist];   mov edx, ci_dist_len;   call sb_mem
    mov rdi, rsp; lea rsi, [rip + g_cfg_dist_dir]; mov rdx, [rip + g_cfg_dist_dir_len]; call sb_ini_safe
    mov rdi, rsp; lea rsi, [rip + ci_spath];  mov edx, ci_spath_len;  call sb_mem
    mov rdi, rsp; mov rsi, [rsp + 136];       mov rdx, [rsp + 144];   call sb_ini_safe
    mov rdi, rsp; lea rsi, [rip + ci_shash];  mov edx, ci_shash_len;  call sb_mem
    mov rdi, rsp; mov rsi, [rsp + 160];       mov edx, 64;            call sb_mem
    mov rdi, rsp; lea rsi, [rip + ci_g_repo]; mov edx, ci_g_repo_len; call sb_mem
    mov rdi, rsp; mov rsi, [rsp + 184];       mov rdx, [rsp + 192];   call sb_ini_safe
    mov rdi, rsp; lea rsi, [rip + ci_g_rid];  mov edx, ci_g_rid_len;  call sb_mem
    mov rdi, rsp; mov rsi, [rsp + 200];       mov rdx, [rsp + 208];   call sb_ini_safe
    mov rdi, rsp; lea rsi, [rip + ci_g_cat];  mov edx, ci_g_cat_len;  call sb_mem
    mov rdi, rsp; mov rsi, [rsp + 216];       mov rdx, [rsp + 224];   call sb_ini_safe
    mov rdi, rsp; lea rsi, [rip + ci_g_cid];  mov edx, ci_g_cid_len;  call sb_mem
    mov rdi, rsp; mov rsi, [rsp + 232];       mov rdx, [rsp + 240];   call sb_ini_safe
    mov rdi, rsp; mov esi, 10;                call sb_byte
    mov rax, [rsp + SB_LEN]
    mov [rsp + 176], rax

    # Target path = g_cfg_path (or "config.ini"), tmp = target + ".tmp"
    cmp qword ptr [rip + g_cfg_path_len], 0
    jne .Lhsss_has_path
    lea rbx, [rip + st_def_cfg]
    mov rdi, rbx
    call xstrlen
    mov r14, rax
    jmp .Lhsss_mk_tmp
.Lhsss_has_path:
    lea rbx, [rip + g_cfg_path]
    mov r14, [rip + g_cfg_path_len]
.Lhsss_mk_tmp:
    mov rdi, rsp; lea rsi, [rip + st_tmp_buf]; mov edx, 511; call sb_init
    mov rdi, rsp; mov rsi, rbx; mov rdx, r14; call sb_mem
    mov rdi, rsp; lea rsi, [rip + st_p_tmp_suf]; mov edx, st_p_tmp_suf_len; call sb_mem
    mov rdi, rsp; xor esi, esi; call sb_byte

    mov rdi, rbx
    lea rsi, [rip + st_tmp_buf]
    lea rdx, [rip + st_file_buf]
    mov rcx, [rsp + 176]
    call write_file_atomic
    test rax, rax
    jns .Lhsss_reload
    mov rdi, r12; lea rsi, [rip + st_500]; lea rdx, [rip + j_err_write]; mov ecx, j_err_write_len; xor r8d, r8d
    call studio_send_json
    jmp .Lhsss_ret

.Lhsss_reload:
    mov rdi, rbx
    call config_load
    call store_reload

    cmp qword ptr [rsp + 168], 0
    je .Lhsss_ok
    mov rdi, r13
    call studio_get_req_token
    mov rdi, rax
    call session_revoke_others

.Lhsss_ok:
    mov rdi, rsp; lea rsi, [rip + st_resp_buf]; mov edx, 511; call sb_init
    mov rdi, rsp; lea rsi, [rip + j_ok_spath_1]; mov edx, j_ok_spath_1_len; call sb_mem
    mov rdi, rsp; lea rsi, [rip + g_cfg_studio_path]; mov rdx, [rip + g_cfg_studio_path_len]; call sb_esc_json
    mov rdi, rsp; lea rsi, [rip + j_close_obj]; mov edx, j_close_obj_len; call sb_mem
    mov rdi, r12; lea rsi, [rip + st_200]; lea rdx, [rip + st_resp_buf]; mov rcx, [rsp + SB_LEN]; xor r8d, r8d
    call studio_send_json
    jmp .Lhsss_ret

.Lhsss_badurl:
    mov rdi, r12; lea rsi, [rip + st_400]; lea rdx, [rip + j_err_url]; mov ecx, j_err_url_len; xor r8d, r8d
    call studio_send_json
    jmp .Lhsss_ret

.Lhsss_badsp:
    mov rdi, r12; lea rsi, [rip + st_400]; lea rdx, [rip + j_err_spath]; mov ecx, j_err_spath_len; xor r8d, r8d
    call studio_send_json
    jmp .Lhsss_ret

.Lhsss_shortpw:
    mov rdi, r12; lea rsi, [rip + st_400]; lea rdx, [rip + j_err_shortpw]; mov ecx, j_err_shortpw_len; xor r8d, r8d
    call studio_send_json

.Lhsss_ret:
    add rsp, 264
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
