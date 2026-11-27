.include "defs.inc"

# Zero-Tracker Post Views & Heart Likes Engine
# Pure x86-64 assembly: in-memory table (up to 512 posts), atomic persistence in content/stats.txt,
# strict published-post validation (prevents junk slug pollution), and 60s sliding-window like limiter.

.equ MAX_STATS,       512
.equ STAT_ENT_SIZE,   160      # [0..127]=slug, [128]=slug_len, [136]=views, [144]=likes
.equ STAT_SLUG_LEN,   128
.equ STAT_VIEWS,      136
.equ STAT_LIKES,      144
.equ LIKE_WIN_LIMIT,  30       # max 30 likes per 60s window server-wide

.section .bss
.align 8
g_stats_entries:  .skip MAX_STATS * STAT_ENT_SIZE
g_stats_cnt:      .quad 0
g_stats_loaded:   .quad 0
g_like_win_sec:   .quad 0
g_like_win_cnt:   .quad 0
stats_io_buf:     .skip 65536
stats_slug_buf:   .skip 256

.section .rodata
st_f_stats:       .asciz "content/stats.txt"
st_f_stats_tmp:   .asciz "content/.stats.txt.tmp"
st_d_cnt:         .asciz "content"
st_hdr_ns:        .asciz "\r\nCache-Control: no-store"
st_hdr_rl:        .asciz "\r\nCache-Control: no-store\r\nRetry-After: 60"

js_k_slug:        .ascii "slug"
.equ js_k_slug_len, . - js_k_slug

js_one_1:         .ascii "{\"slug\":\""
.equ js_one_1_len, . - js_one_1
js_one_2:         .ascii "\",\"views\":"
.equ js_one_2_len, . - js_one_2
js_one_3:         .ascii ",\"likes\":"
.equ js_one_3_len, . - js_one_3

js_all_1:         .ascii "{\"total_views\":"
.equ js_all_1_len, . - js_all_1
js_all_2:         .ascii ",\"total_likes\":"
.equ js_all_2_len, . - js_all_2
js_all_3:         .ascii ",\"items\":["
.equ js_all_3_len, . - js_all_3
js_all_end:       .ascii "]}"
.equ js_all_end_len, . - js_all_end

j_err_bad_slug:   .ascii "{\"error\":\"invalid post slug\"}"
.equ j_err_bad_slug_len, . - j_err_bad_slug
j_err_not_found:  .ascii "{\"error\":\"post not found\"}"
.equ j_err_not_found_len, . - j_err_not_found
j_err_rate_like:  .ascii "{\"error\":\"too many likes, please wait a moment\"}"
.equ j_err_rate_like_len, . - j_err_rate_like

.section .text

# stats_find_or_add(rdi=slug_ptr, rsi=slug_len, rdx=create) -> rax=&entry or 0
stats_find_or_add:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx

    test r13, r13
    jz .Lsfa_zero
    cmp r13, 127
    ja .Lsfa_zero

    xor ebx, ebx
.Lsfa_loop:
    cmp rbx, [rip + g_stats_cnt]
    jae .Lsfa_create
    imul rax, rbx, STAT_ENT_SIZE
    lea r8, [rip + g_stats_entries]
    add r8, rax
    cmp [r8 + STAT_SLUG_LEN], r13
    jne .Lsfa_next
    push r8
    mov rdi, r8
    mov rsi, r13
    mov rdx, r12
    mov rcx, r13
    call xslice_eq
    pop r8
    test eax, eax
    jnz .Lsfa_found
.Lsfa_next:
    inc rbx
    jmp .Lsfa_loop

.Lsfa_found:
    mov rax, r8
    jmp .Lsfa_ret

.Lsfa_create:
    test r14, r14
    jz .Lsfa_zero
    mov rbx, [rip + g_stats_cnt]
    cmp rbx, MAX_STATS
    jae .Lsfa_zero
    imul rax, rbx, STAT_ENT_SIZE
    lea r8, [rip + g_stats_entries]
    add r8, rax
    push r8
    mov rdi, r8
    mov rsi, r12
    mov rdx, r13
    call xmemcpy
    pop r8
    mov byte ptr [r8 + r13], 0
    mov [r8 + STAT_SLUG_LEN], r13
    mov qword ptr [r8 + STAT_VIEWS], 0
    mov qword ptr [r8 + STAT_LIKES], 0
    inc qword ptr [rip + g_stats_cnt]
    mov rax, r8
    jmp .Lsfa_ret

.Lsfa_zero:
    xor eax, eax
.Lsfa_ret:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# stats_ensure_loaded() -> lazy-loads content/stats.txt once on first request
stats_ensure_loaded:
    cmp qword ptr [rip + g_stats_loaded], 0
    jne .Lsel_done
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16           # 5 pushes + ret = 48, +16 = 64 aligned

    mov qword ptr [rip + g_stats_loaded], 1
    lea rdi, [rip + st_f_stats]
    lea rsi, [rip + stats_io_buf]
    mov edx, 65535
    call read_file_buf
    test rax, rax
    jle .Lsel_ret

    lea r12, [rip + stats_io_buf]     # cur ptr
    lea r13, [r12 + rax]              # end ptr

.Lsel_line:
    cmp r12, r13
    jae .Lsel_ret
    # Find end of line
    mov rdi, r12
    mov rsi, r13
    sub rsi, r12
    mov edx, 10
    call xmemchr
    cmp rax, -1
    jne .Lsel_got_nl
    mov r14, r13
    mov r15, r13
    jmp .Lsel_parse
.Lsel_got_nl:
    lea r14, [r12 + rax]              # line end (before \n)
    lea r15, [r14 + 1]                # next line start

.Lsel_parse:
    mov rdi, r12
    mov rsi, r14
    sub rsi, r12
    call trim_ws
    # rax=line_ptr, rdx=line_len
    test rdx, rdx
    jz .Lsel_next_line
    mov rbx, rax                      # line_ptr
    mov [rsp + 0], rdx                # line_len

    # Token 1: slug (up to space)
    mov rdi, rbx
    mov rsi, rdx
    mov edx, ' '
    call xmemchr
    cmp rax, -1
    je .Lsel_next_line
    mov r12, rax                      # slug_len
    mov rdi, rbx
    mov rsi, r12
    call is_safe_slug
    test eax, eax
    jz .Lsel_next_line

    # Create/find entry
    mov rdi, rbx
    mov rsi, r12
    mov edx, 1
    call stats_find_or_add
    test rax, rax
    jz .Lsel_next_line
    mov [rsp + 8], rax                # &entry

    # Advance past slug + space
    lea rdi, [rbx + r12 + 1]
    mov rsi, [rsp + 0]
    sub rsi, r12
    dec rsi
    call trim_ws
    test rdx, rdx
    jz .Lsel_next_line
    mov rbx, rax                      # rest_ptr
    mov [rsp + 0], rdx                # rest_len

    # Token 2: views (up to space or end)
    mov rdi, rbx
    mov rsi, rdx
    mov edx, ' '
    call xmemchr
    cmp rax, -1
    jne .Lsel_has_likes
    mov rdi, rbx
    mov rsi, [rsp + 0]
    call parse_uint
    test edx, edx
    jz .Lsel_next_line
    mov r8, [rsp + 8]
    mov [r8 + STAT_VIEWS], rax
    jmp .Lsel_next_line

.Lsel_has_likes:
    mov r12, rax                      # views_len
    mov rdi, rbx
    mov rsi, r12
    call parse_uint
    test edx, edx
    jz .Lsel_next_line
    mov r8, [rsp + 8]
    mov [r8 + STAT_VIEWS], rax

    # Token 3: likes
    lea rdi, [rbx + r12 + 1]
    mov rsi, [rsp + 0]
    sub rsi, r12
    dec rsi
    call trim_ws
    test rdx, rdx
    jz .Lsel_next_line
    mov rdi, rax
    mov rsi, rdx
    call parse_uint
    test edx, edx
    jz .Lsel_next_line
    mov r8, [rsp + 8]
    mov [r8 + STAT_LIKES], rax

.Lsel_next_line:
    mov r12, r15
    jmp .Lsel_line

.Lsel_ret:
    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
.Lsel_done:
    ret

# stats_save() -> atomically writes content/stats.txt
stats_save:
    push rbx
    push r12
    sub rsp, 40           # [rsp+0..23]=sbuf (2 pushes + ret = 24, +40 = 64 aligned)

    mov rdi, rsp
    lea rsi, [rip + stats_io_buf]
    mov edx, 65535
    call sb_init

    xor ebx, ebx
.Lssv_loop:
    cmp rbx, [rip + g_stats_cnt]
    jae .Lssv_write
    cmp qword ptr [rsp + SB_LEN], 65300
    jae .Lssv_write
    imul rax, rbx, STAT_ENT_SIZE
    lea r12, [rip + g_stats_entries]
    add r12, rax
    mov rdi, rsp; mov rsi, r12; mov rdx, [r12 + STAT_SLUG_LEN]; call sb_mem
    mov rdi, rsp; mov esi, ' '; call sb_byte
    mov rdi, rsp; mov rsi, [r12 + STAT_VIEWS]; call sb_uint
    mov rdi, rsp; mov esi, ' '; call sb_byte
    mov rdi, rsp; mov rsi, [r12 + STAT_LIKES]; call sb_uint
    mov rdi, rsp; mov esi, 10; call sb_byte
    inc rbx
    jmp .Lssv_loop

.Lssv_write:
    lea rdi, [rip + st_d_cnt]; mov esi, 0755; call sys_mkdir
    lea rdi, [rip + st_f_stats]
    lea rsi, [rip + st_f_stats_tmp]
    lea rdx, [rip + stats_io_buf]
    mov rcx, [rsp + SB_LEN]
    call write_file_atomic

    add rsp, 40
    pop r12
    pop rbx
    ret

# stats_send_one(rdi=conn, rsi=slug_ptr, rdx=slug_len, rcx=views, r8=likes)
stats_send_one:
    push r12
    push r13
    push r14
    push r15
    push rbx
    sub rsp, 32           # 5 pushes + ret = 48, +32 = 80 aligned
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    mov rbx, r8

    mov rdi, rsp; lea rsi, [rip + stats_io_buf]; mov edx, 1023; call sb_init
    mov rdi, rsp; lea rsi, [rip + js_one_1]; mov edx, js_one_1_len; call sb_mem
    mov rdi, rsp; mov rsi, r13; mov rdx, r14; call sb_esc_json
    mov rdi, rsp; lea rsi, [rip + js_one_2]; mov edx, js_one_2_len; call sb_mem
    mov rdi, rsp; mov rsi, r15; call sb_uint
    mov rdi, rsp; lea rsi, [rip + js_one_3]; mov edx, js_one_3_len; call sb_mem
    mov rdi, rsp; mov rsi, rbx; call sb_uint
    mov rdi, rsp; mov esi, '}'; call sb_byte

    mov rdi, r12
    lea rsi, [rip + st_200]
    lea rdx, [rip + ct_json]
    lea rcx, [rip + stats_io_buf]
    mov r8, [rsp + SB_LEN]
    lea r9, [rip + st_hdr_ns]
    call http_send_resp

    add rsp, 32
    pop rbx
    pop r15
    pop r14
    pop r13
    pop r12
    ret

# GET /api/stats -> returns site-wide totals & per-post views/likes
.globl handle_stats_all
handle_stats_all:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 32           # 5 pushes + ret = 48, +32 = 80 aligned
    mov r12, rdi

    call stats_ensure_loaded

    # Sum totals across all entries
    xor r13d, r13d        # total_views
    xor r14d, r14d        # total_likes
    xor ebx, ebx
.Lhsa_sum:
    cmp rbx, [rip + g_stats_cnt]
    jae .Lhsa_build
    imul rax, rbx, STAT_ENT_SIZE
    lea r8, [rip + g_stats_entries]
    add r13, [r8 + rax + STAT_VIEWS]
    add r14, [r8 + rax + STAT_LIKES]
    inc rbx
    jmp .Lhsa_sum

.Lhsa_build:
    mov rdi, rsp; lea rsi, [rip + stats_io_buf]; mov edx, 65535; call sb_init
    mov rdi, rsp; lea rsi, [rip + js_all_1]; mov edx, js_all_1_len; call sb_mem
    mov rdi, rsp; mov rsi, r13; call sb_uint
    mov rdi, rsp; lea rsi, [rip + js_all_2]; mov edx, js_all_2_len; call sb_mem
    mov rdi, rsp; mov rsi, r14; call sb_uint
    mov rdi, rsp; lea rsi, [rip + js_all_3]; mov edx, js_all_3_len; call sb_mem

    xor ebx, ebx
.Lhsa_loop:
    cmp rbx, [rip + g_stats_cnt]
    jae .Lhsa_end
    cmp qword ptr [rsp + SB_LEN], 65200
    jae .Lhsa_end
    test rbx, rbx
    jz .Lhsa_first
    mov rdi, rsp; mov esi, ','; call sb_byte
.Lhsa_first:
    imul rax, rbx, STAT_ENT_SIZE
    lea r15, [rip + g_stats_entries]
    add r15, rax
    mov rdi, rsp; lea rsi, [rip + js_one_1]; mov edx, js_one_1_len; call sb_mem
    mov rdi, rsp; mov rsi, r15; mov rdx, [r15 + STAT_SLUG_LEN]; call sb_esc_json
    mov rdi, rsp; lea rsi, [rip + js_one_2]; mov edx, js_one_2_len; call sb_mem
    mov rdi, rsp; mov rsi, [r15 + STAT_VIEWS]; call sb_uint
    mov rdi, rsp; lea rsi, [rip + js_one_3]; mov edx, js_one_3_len; call sb_mem
    mov rdi, rsp; mov rsi, [r15 + STAT_LIKES]; call sb_uint
    mov rdi, rsp; mov esi, '}'; call sb_byte
    inc rbx
    jmp .Lhsa_loop

.Lhsa_end:
    mov rdi, rsp; lea rsi, [rip + js_all_end]; mov edx, js_all_end_len; call sb_mem
    mov rdi, r12
    lea rsi, [rip + st_200]
    lea rdx, [rip + ct_json]
    lea rcx, [rip + stats_io_buf]
    mov r8, [rsp + SB_LEN]
    lea r9, [rip + st_hdr_ns]
    call http_send_resp

    add rsp, 32
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# GET /api/stats/:slug -> returns views & likes for one post without incrementing
.globl handle_stats_one
handle_stats_one:
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, [rsi + REQ_PARAM_PTR]
    mov r14, [rsi + REQ_PARAM_LEN]

    call stats_ensure_loaded

    mov rdi, r13
    mov rsi, r14
    call is_safe_slug
    test eax, eax
    jnz .Lhso_find
    mov rdi, r12
    lea rsi, [rip + st_400]
    lea rdx, [rip + ct_json]
    lea rcx, [rip + j_err_bad_slug]
    mov r8d, j_err_bad_slug_len
    lea r9, [rip + st_hdr_ns]
    call http_send_resp
    jmp .Lhso_ret

.Lhso_find:
    mov rdi, r13
    mov rsi, r14
    xor edx, edx
    call stats_find_or_add
    xor ecx, ecx
    xor r8d, r8d
    test rax, rax
    jz .Lhso_send
    mov rcx, [rax + STAT_VIEWS]
    mov r8, [rax + STAT_LIKES]
.Lhso_send:
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    call stats_send_one

.Lhso_ret:
    pop r14
    pop r13
    pop r12
    ret

# stats_hit_common(rdi=conn, rsi=&req, rdx=is_like)
stats_hit_common:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 32           # [rsp+0..23]=sbuf (5 pushes + ret = 48, +32 = 80 aligned)
    mov r12, rdi
    mov r13, rsi
    mov rbx, rdx          # is_like

    call stats_ensure_loaded

    # Rate-limit likes (max LIKE_WIN_LIMIT per 60s window)
    test rbx, rbx
    jz .Lshc_parse
    call mono_sec
    mov rcx, rax
    sub rcx, [rip + g_like_win_sec]
    cmp rcx, 60
    jb .Lshc_chk_lim
    mov [rip + g_like_win_sec], rax
    mov qword ptr [rip + g_like_win_cnt], 0
.Lshc_chk_lim:
    cmp qword ptr [rip + g_like_win_cnt], LIKE_WIN_LIMIT
    jb .Lshc_parse
    mov rdi, r12
    lea rsi, [rip + st_429]
    lea rdx, [rip + ct_json]
    lea rcx, [rip + j_err_rate_like]
    mov r8d, j_err_rate_like_len
    lea r9, [rip + st_hdr_rl]
    call http_send_resp
    jmp .Lshc_ret

.Lshc_parse:
    mov rdi, rsp; lea rsi, [rip + stats_slug_buf]; mov edx, 255; call sb_init
    mov rdi, [r13 + REQ_BODY_PTR]
    mov rsi, [r13 + REQ_BODY_LEN]
    lea rdx, [rip + js_k_slug]
    mov ecx, js_k_slug_len
    mov r8, rsp
    call json_get_str
    lea rdi, [rip + stats_slug_buf]; mov rsi, [rsp + SB_LEN]; call trim_ws
    mov r14, rax
    mov r15, rdx

    mov rdi, r14
    mov rsi, r15
    call is_safe_slug
    test eax, eax
    jnz .Lshc_chk_post
    mov rdi, r12
    lea rsi, [rip + st_400]
    lea rdx, [rip + ct_json]
    lea rcx, [rip + j_err_bad_slug]
    mov r8d, j_err_bad_slug_len
    lea r9, [rip + st_hdr_ns]
    call http_send_resp
    jmp .Lshc_ret

.Lshc_chk_post:
    # Only count views/likes on real PUBLISHED posts (blocks junk pollution & draft probing!)
    mov rdi, r14
    mov rsi, r15
    xor edx, edx
    call store_find_post
    test rax, rax
    jnz .Lshc_inc
    mov rdi, r12
    lea rsi, [rip + st_404]
    lea rdx, [rip + ct_json]
    lea rcx, [rip + j_err_not_found]
    mov r8d, j_err_not_found_len
    lea r9, [rip + st_hdr_ns]
    call http_send_resp
    jmp .Lshc_ret

.Lshc_inc:
    mov rdi, r14
    mov rsi, r15
    mov edx, 1
    call stats_find_or_add
    test rax, rax
    jnz .Lshc_got_ent
    # Table full (512 entries): still send a valid JSON response so connection never hangs
    mov rdi, r12
    mov rsi, r14
    mov rdx, r15
    xor ecx, ecx
    xor r8d, r8d
    call stats_send_one
    jmp .Lshc_ret
.Lshc_got_ent:
    mov r13, rax          # &entry
    test rbx, rbx
    jnz .Lshc_do_like
    inc qword ptr [r13 + STAT_VIEWS]
    jmp .Lshc_save
.Lshc_do_like:
    inc qword ptr [rip + g_like_win_cnt]
    inc qword ptr [r13 + STAT_LIKES]

.Lshc_save:
    call stats_save
    mov rdi, r12
    mov rsi, r14
    mov rdx, r15
    mov rcx, [r13 + STAT_VIEWS]
    mov r8, [r13 + STAT_LIKES]
    call stats_send_one

.Lshc_ret:
    add rsp, 32
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.globl handle_stats_view
handle_stats_view:
    xor edx, edx
    jmp stats_hit_common

.globl handle_stats_like
handle_stats_like:
    mov edx, 1
    jmp stats_hit_common
