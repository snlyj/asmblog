.include "defs.inc"

# Static file server: strict path check + ETag (304) + kernel sendfile zero-copy
.section .rodata
st_dir_prefix:  .ascii "themes/"
.equ st_dir_prefix_len, . - st_dir_prefix
st_dir_mid:     .ascii "/static/"
.equ st_dir_mid_len, . - st_dir_mid
up_dir_prefix:  .ascii "content/uploads/"
.equ up_dir_prefix_len, . - up_dir_prefix
etag_hdr_pre:       .ascii "\r\nCache-Control: public, max-age=0, must-revalidate\r\nETag: \""
.equ etag_hdr_pre_len, . - etag_hdr_pre
etag_hdr_imm:       .ascii "\r\nCache-Control: public, max-age=31536000, immutable\r\nETag: \""
.equ etag_hdr_imm_len, . - etag_hdr_imm
etag_hdr_end:       .ascii "\""

mime_css:       .asciz "text/css; charset=utf-8"
mime_js:        .asciz "application/javascript; charset=utf-8"
mime_svg:       .asciz "image/svg+xml"
mime_png:       .asciz "image/png"
mime_jpg:       .asciz "image/jpeg"
mime_webp:      .asciz "image/webp"
mime_gif:       .asciz "image/gif"
mime_ico:       .asciz "image/x-icon"
mime_woff2:     .asciz "font/woff2"
mime_html:      .asciz "text/html; charset=utf-8"
mime_json:      .asciz "application/json; charset=utf-8"
mime_bin:       .asciz "application/octet-stream"

ext_css:   .ascii ".css"
ext_js:    .ascii ".js"
ext_svg:   .ascii ".svg"
ext_png:   .ascii ".png"
ext_jpg:   .ascii ".jpg"
ext_jpeg:  .ascii ".jpeg"
ext_webp:  .ascii ".webp"
ext_gif:   .ascii ".gif"
ext_ico:   .ascii ".ico"
ext_woff2: .ascii ".woff2"
ext_html:  .ascii ".html"
ext_json:  .ascii ".json"

fav_svg:
    .ascii "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 64 64\"><rect width=\"64\" height=\"64\" rx=\"14\" fill=\"#0f172a\"/><text x=\"32\" y=\"43\" font-family=\"monospace\" font-size=\"28\" font-weight=\"bold\" fill=\"#38bdf8\" text-anchor=\"middle\">0x</text></svg>"
.equ fav_svg_len, . - fav_svg

msg_forbidden: .asciz "403 Forbidden"
msg_notfound:  .asciz "404 Not Found"

.section .text

# get_favicon_svg() -> rax=ptr, rdx=len (used by handle_favicon & SSG build)
.globl get_favicon_svg
get_favicon_svg:
    lea rax, [rip + fav_svg]
    mov edx, fav_svg_len
    ret

# ends_with_ci(rdi=path, rsi=len, rdx=ext, rcx=ext_len) -> rax=1/0
ends_with_ci:
    cmp rsi, rcx
    jb .Lew_no
    add rdi, rsi
    sub rdi, rcx
    mov rsi, rcx
    jmp xslice_eq_ci
.Lew_no:
    xor eax, eax
    ret

# mime_for_path(rdi=path_ptr, rsi=path_len) -> rax=cstr
mime_for_path:
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi

    mov rdi, r12; mov rsi, r13; lea rdx, [rip + ext_css];   mov ecx, 4; call ends_with_ci
    test eax, eax; jnz .Lm_css
    mov rdi, r12; mov rsi, r13; lea rdx, [rip + ext_js];    mov ecx, 3; call ends_with_ci
    test eax, eax; jnz .Lm_js
    mov rdi, r12; mov rsi, r13; lea rdx, [rip + ext_svg];   mov ecx, 4; call ends_with_ci
    test eax, eax; jnz .Lm_svg
    mov rdi, r12; mov rsi, r13; lea rdx, [rip + ext_png];   mov ecx, 4; call ends_with_ci
    test eax, eax; jnz .Lm_png
    mov rdi, r12; mov rsi, r13; lea rdx, [rip + ext_jpg];   mov ecx, 4; call ends_with_ci
    test eax, eax; jnz .Lm_jpg
    mov rdi, r12; mov rsi, r13; lea rdx, [rip + ext_jpeg];  mov ecx, 5; call ends_with_ci
    test eax, eax; jnz .Lm_jpg
    mov rdi, r12; mov rsi, r13; lea rdx, [rip + ext_webp];  mov ecx, 5; call ends_with_ci
    test eax, eax; jnz .Lm_webp
    mov rdi, r12; mov rsi, r13; lea rdx, [rip + ext_gif];   mov ecx, 4; call ends_with_ci
    test eax, eax; jnz .Lm_gif
    mov rdi, r12; mov rsi, r13; lea rdx, [rip + ext_ico];   mov ecx, 4; call ends_with_ci
    test eax, eax; jnz .Lm_ico
    mov rdi, r12; mov rsi, r13; lea rdx, [rip + ext_woff2]; mov ecx, 6; call ends_with_ci
    test eax, eax; jnz .Lm_woff2
    mov rdi, r12; mov rsi, r13; lea rdx, [rip + ext_html];  mov ecx, 5; call ends_with_ci
    test eax, eax; jnz .Lm_html
    mov rdi, r12; mov rsi, r13; lea rdx, [rip + ext_json];  mov ecx, 5; call ends_with_ci
    test eax, eax; jnz .Lm_json
    lea rax, [rip + mime_bin]; jmp .Lm_ret
.Lm_css:   lea rax, [rip + mime_css];   jmp .Lm_ret
.Lm_js:    lea rax, [rip + mime_js];    jmp .Lm_ret
.Lm_svg:   lea rax, [rip + mime_svg];   jmp .Lm_ret
.Lm_png:   lea rax, [rip + mime_png];   jmp .Lm_ret
.Lm_jpg:   lea rax, [rip + mime_jpg];   jmp .Lm_ret
.Lm_webp:  lea rax, [rip + mime_webp];  jmp .Lm_ret
.Lm_gif:   lea rax, [rip + mime_gif];   jmp .Lm_ret
.Lm_ico:   lea rax, [rip + mime_ico];   jmp .Lm_ret
.Lm_woff2: lea rax, [rip + mime_woff2]; jmp .Lm_ret
.Lm_html:  lea rax, [rip + mime_html];  jmp .Lm_ret
.Lm_json:  lea rax, [rip + mime_json]
.Lm_ret:
    pop r13
    pop r12
    ret

# handle_favicon(rdi=conn, rsi=&req)
.globl handle_favicon
handle_favicon:
    lea rsi, [rip + st_200]
    lea rdx, [rip + mime_svg]
    lea rcx, [rip + fav_svg]
    mov r8d, fav_svg_len
    xor r9d, r9d
    jmp http_send_resp

# handle_static(rdi=conn, rsi=&req) -> serves themes/<theme>/static/<param>
.globl handle_static
handle_static:
    xor edx, edx          # mode 0 = theme static
    jmp serve_file_common

# handle_upload_file(rdi=conn, rsi=&req) -> serves content/uploads/<param>
.globl handle_upload_file
handle_upload_file:
    mov edx, 1            # mode 1 = uploads (always immutable cache)
    jmp serve_file_common

# serve_file_common(rdi=conn, rsi=&req, edx=mode_0_static_1_upload)
serve_file_common:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 1272         # [rsp+1256] = mode

    mov r12, rdi
    mov r13, rsi
    mov [rsp + 1256], rdx

    # URL-decode param first (so %2e%2e traversal is caught!)
    lea rdi, [rsp + 24]
    lea rsi, [rsp + 216]
    mov edx, 319
    call sb_init
    lea rdi, [rsp + 24]
    mov rsi, [r13 + REQ_PARAM_PTR]
    mov rdx, [r13 + REQ_PARAM_LEN]
    call sb_url_decode

    lea rdi, [rsp + 216]
    mov rsi, [rsp + 24 + SB_LEN]
    call is_safe_relpath
    test eax, eax
    jz .Lst_403

    # Build path: mode 0 -> themes/<theme>/static/<relpath>, mode 1 -> content/uploads/<relpath>
    lea rdi, [rsp + 0]
    lea rsi, [rsp + 536]
    mov edx, 511
    call sb_init

    cmp qword ptr [rsp + 1256], 0
    jne .Lst_path_up

    lea rdi, [rsp + 0]
    lea rsi, [rip + st_dir_prefix]
    mov edx, st_dir_prefix_len
    call sb_mem

    lea rdi, [rsp + 0]
    lea rsi, [rip + g_cfg_theme]
    mov rdx, [rip + g_cfg_theme_len]
    call sb_mem

    lea rdi, [rsp + 0]
    lea rsi, [rip + st_dir_mid]
    mov edx, st_dir_mid_len
    call sb_mem
    jmp .Lst_path_rel

.Lst_path_up:
    lea rdi, [rsp + 0]
    lea rsi, [rip + up_dir_prefix]
    mov edx, up_dir_prefix_len
    call sb_mem

.Lst_path_rel:
    lea rdi, [rsp + 0]
    lea rsi, [rsp + 216]
    mov rdx, [rsp + 24 + SB_LEN]
    call sb_mem

    lea rdi, [rsp + 0]
    xor esi, esi
    call sb_byte

    # Open with O_RDONLY | O_NOFOLLOW | O_CLOEXEC
    mov rdi, AT_FDCWD
    lea rsi, [rsp + 536]
    mov edx, O_RDONLY | O_NOFOLLOW | O_CLOEXEC
    xor ecx, ecx
    call sys_openat
    test rax, rax
    js .Lst_404
    mov r14, rax

    # fstat
    mov rdi, r14
    lea rsi, [rsp + 72]
    call sys_fstat
    test rax, rax
    js .Lst_close_404
    mov eax, [rsp + 72 + STAT_MODE]
    and eax, S_IFMT
    cmp eax, S_IFREG
    jne .Lst_close_404

    mov r15, [rsp + 72 + STAT_SIZE]

    # Use long-term immutable cache for uploads (mode==1) or versioned URLs (?v=...)
    lea rdi, [rsp + 48]
    lea rsi, [rsp + 1048]
    mov edx, 159
    call sb_init
    cmp qword ptr [rsp + 1256], 0
    jne .Lst_cc_imm
    cmp qword ptr [r13 + REQ_QUERY_LEN], 0
    jnz .Lst_cc_imm
    lea rdi, [rsp + 48]
    lea rsi, [rip + etag_hdr_pre]
    mov edx, etag_hdr_pre_len
    call sb_mem
    jmp .Lst_cc_done
.Lst_cc_imm:
    lea rdi, [rsp + 48]
    lea rsi, [rip + etag_hdr_imm]
    mov edx, etag_hdr_imm_len
    call sb_mem
.Lst_cc_done:
    mov rbx, [rsp + 48 + SB_LEN]
    dec rbx
    lea rdi, [rsp + 48]
    mov rsi, r15
    call sb_uint
    lea rdi, [rsp + 48]
    mov esi, '-'
    call sb_byte
    lea rdi, [rsp + 48]
    mov rsi, [rsp + 72 + STAT_MTIME]
    call sb_uint
    lea rdi, [rsp + 48]
    lea rsi, [rip + etag_hdr_end]
    mov edx, 1
    call sb_mem
    lea rdi, [rsp + 48]
    xor esi, esi
    call sb_byte

    # Compare If-None-Match against quoted ETag (RFC 9110 weak comparison)
    cmp qword ptr [r13 + REQ_ETAG_PTR], 0
    je .Lst_send_file
    mov rdx, [rsp + 48 + SB_LEN]
    dec rdx
    sub rdx, rbx
    lea rsi, [rsp + 1048 + rbx]
    mov rdi, r13
    call http_inm_match
    test eax, eax
    jz .Lst_send_file

    # 304 Not Modified! (RFC 9110: omit Content-Type & Content-Length)
    mov rdi, r14
    call sys_close
    mov rdi, r12
    lea rsi, [rip + st_304]
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    lea r9, [rsp + 1048]
    call http_send_resp
    jmp .Lst_done

.Lst_send_file:
    lea rdi, [rsp + 216]
    mov rsi, [rsp + 24 + SB_LEN]
    call mime_for_path
    mov rbx, rax

    mov rdi, r12
    lea rsi, [rip + st_200]
    mov rdx, rbx
    xor ecx, ecx
    mov r8, r15
    lea r9, [rsp + 1048]
    call http_send_resp

    cmp qword ptr [r12 + CONN_IS_HEAD], 0
    jne .Lst_close_ok
    test r15, r15
    jz .Lst_close_ok

    mov [r12 + CONN_FILE_FD], r14
    mov qword ptr [r12 + CONN_FILE_OFF], 0
    mov [r12 + CONN_FILE_REM], r15
    jmp .Lst_done

.Lst_close_ok:
    mov rdi, r14
    call sys_close
    jmp .Lst_done

.Lst_close_404:
    mov rdi, r14
    call sys_close
.Lst_404:
    mov rdi, r12
    lea rsi, [rip + st_404]
    lea rdx, [rip + msg_notfound]
    call http_send_error
    jmp .Lst_done

.Lst_403:
    mov rdi, r12
    lea rsi, [rip + st_403]
    lea rdx, [rip + msg_forbidden]
    call http_send_error

.Lst_done:
    add rsp, 1272
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
