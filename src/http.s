.include "defs.inc"

# HTTP/1.1 request parser, query helper, and response builder (read-only static blog)
.section .rodata
m_get:      .ascii "GET"
m_head:     .ascii "HEAD"
m_post:     .ascii "POST"
m_put:      .ascii "PUT"
m_delete:   .ascii "DELETE"
m_options:  .ascii "OPTIONS"
ver_10:     .ascii "HTTP/1.0"
ver_11:     .ascii "HTTP/1.1"
h_cl:       .ascii "Content-Length"
.equ h_cl_len, . - h_cl
h_conn:     .ascii "Connection"
.equ h_conn_len, . - h_conn
h_inm:      .ascii "If-None-Match"
.equ h_inm_len, . - h_inm
h_auth:     .ascii "Authorization"
.equ h_auth_len, . - h_auth
h_cookie:   .ascii "Cookie"
.equ h_cookie_len, . - h_cookie
h_xfp:      .ascii "X-Forwarded-Proto"
.equ h_xfp_len, . - h_xfp
h_range:    .ascii "Range"
.equ h_range_len, . - h_range
v_https:    .ascii "https"
.equ v_https_len, . - v_https
v_close:    .ascii "close"
v_ka:       .ascii "keep-alive"

resp_prefix: .ascii "HTTP/1.1 "
.equ resp_prefix_len, . - resp_prefix
resp_ct:     .ascii "\r\nContent-Type: "
.equ resp_ct_len, . - resp_ct
resp_cl:     .ascii "\r\nContent-Length: "
.equ resp_cl_len, . - resp_cl
resp_ka_on:  .ascii "\r\nConnection: keep-alive"
.equ resp_ka_on_len, . - resp_ka_on
resp_ka_off: .ascii "\r\nConnection: close"
.equ resp_ka_off_len, . - resp_ka_off
resp_sec:    .ascii "\r\nServer: AsmBlog/1.0 (x86_64-asm)\r\nX-Content-Type-Options: nosniff\r\nX-Frame-Options: SAMEORIGIN\r\nReferrer-Policy: strict-origin-when-cross-origin"
.equ resp_sec_len, . - resp_sec
resp_end:    .ascii "\r\n\r\n"
.equ resp_end_len, . - resp_end

.globl st_200
st_200: .asciz "200 OK"
.globl st_201
st_201: .asciz "201 Created"
.globl st_206
st_206: .asciz "206 Partial Content"
.globl st_304
st_304: .asciz "304 Not Modified"
.globl st_400
st_400: .asciz "400 Bad Request"
.globl st_401
st_401: .asciz "401 Unauthorized"
.globl st_403
st_403: .asciz "403 Forbidden"
.globl st_404
st_404: .asciz "404 Not Found"
.globl st_405
st_405: .asciz "405 Method Not Allowed"
.globl st_413
st_413: .asciz "413 Payload Too Large"
.globl st_414
st_414: .asciz "414 URI Too Long"
.globl st_416
st_416: .asciz "416 Range Not Satisfiable"
.globl st_429
st_429: .asciz "429 Too Many Requests"
.globl st_500
st_500: .asciz "500 Internal Server Error"

.globl ct_html
ct_html: .asciz "text/html; charset=utf-8"
.globl ct_json
ct_json: .asciz "application/json; charset=utf-8"
.globl ct_xml
ct_xml:  .asciz "application/xml; charset=utf-8"
.globl ct_rss
ct_rss:  .asciz "application/rss+xml; charset=utf-8"
.globl ct_txt
ct_txt:  .asciz "text/plain; charset=utf-8"

.section .text

# find_crlfcrlf(rdi=buf, rsi=len) -> rax=offset of \r\n\r\n or -1
find_crlfcrlf:
    cmp rsi, 4
    jb .Lfc_no
    lea rcx, [rsi - 3]
    xor eax, eax
.Lfc_loop:
    cmp rax, rcx
    jae .Lfc_no
    cmp dword ptr [rdi + rax], 0x0a0d0a0d
    je .Lfc_yes
    inc rax
    jmp .Lfc_loop
.Lfc_yes:
    ret
.Lfc_no:
    mov rax, -1
    ret

# http_parse_request(rdi=buf, rsi=len, rdx=&req)
# Returns: >0 bytes consumed, 0 need more data, <0 error (-400, -413, -414)
.globl http_parse_request
http_parse_request:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx

    mov rdi, r14
    xor esi, esi
    mov edx, REQ_SIZE
    call xmemset

    mov rdi, r12
    mov rsi, r13
    call find_crlfcrlf
    cmp rax, -1
    jne .Lhpr_hdr_found
    cmp r13, MAX_HDR_BYTES
    ja .Lhpr_400
    xor eax, eax
    jmp .Lhpr_ret

.Lhpr_hdr_found:
    cmp rax, MAX_HDR_BYTES
    ja .Lhpr_400
    lea r15, [rax + 4]
    mov [r14 + REQ_HDR_LEN], r15

    # Find first \r
    mov rdi, r12
    mov rsi, rax
    mov edx, 13
    call xmemchr
    cmp rax, -1
    jne .Lhpr_rl_ok
    mov rax, r15
    sub rax, 4
.Lhpr_rl_ok:
    mov rbx, rax

    # Method up to first space
    mov rdi, r12
    mov rsi, rbx
    mov edx, ' '
    call xmemchr
    cmp rax, -1
    je .Lhpr_400
    push rax

    mov rdi, r12; mov rsi, rax;     lea rdx, [rip + m_get];     mov ecx, 3; call xslice_eq; test eax, eax; jnz .Lhpr_m_get
    mov rdi, r12; mov rsi, [rsp];   lea rdx, [rip + m_head];    mov ecx, 4; call xslice_eq; test eax, eax; jnz .Lhpr_m_head
    mov rdi, r12; mov rsi, [rsp];   lea rdx, [rip + m_post];    mov ecx, 4; call xslice_eq; test eax, eax; jnz .Lhpr_m_post
    mov rdi, r12; mov rsi, [rsp];   lea rdx, [rip + m_put];     mov ecx, 3; call xslice_eq; test eax, eax; jnz .Lhpr_m_put
    mov rdi, r12; mov rsi, [rsp];   lea rdx, [rip + m_delete];  mov ecx, 6; call xslice_eq; test eax, eax; jnz .Lhpr_m_del
    mov rdi, r12; mov rsi, [rsp];   lea rdx, [rip + m_options]; mov ecx, 7; call xslice_eq; test eax, eax; jnz .Lhpr_m_opt
    pop rax
    jmp .Lhpr_400

.Lhpr_m_get:  mov qword ptr [r14 + REQ_METHOD], METH_GET;     jmp .Lhpr_m_ok
.Lhpr_m_head: mov qword ptr [r14 + REQ_METHOD], METH_HEAD;    jmp .Lhpr_m_ok
.Lhpr_m_post: mov qword ptr [r14 + REQ_METHOD], METH_POST;    jmp .Lhpr_m_ok
.Lhpr_m_put:  mov qword ptr [r14 + REQ_METHOD], METH_PUT;     jmp .Lhpr_m_ok
.Lhpr_m_del:  mov qword ptr [r14 + REQ_METHOD], METH_DELETE;  jmp .Lhpr_m_ok
.Lhpr_m_opt:  mov qword ptr [r14 + REQ_METHOD], METH_OPTIONS; jmp .Lhpr_m_ok

.Lhpr_m_ok:
    pop rcx
    inc rcx
    cmp rcx, rbx
    jae .Lhpr_400
    push rcx
    lea rdi, [r12 + rcx]
    mov rsi, rbx
    sub rsi, rcx
    mov edx, ' '
    call xmemchr
    pop rcx
    cmp rax, -1
    je .Lhpr_400
    cmp rax, MAX_URI_BYTES
    ja .Lhpr_414
    test rax, rax
    jz .Lhpr_400
    cmp byte ptr [r12 + rcx], '/'
    jne .Lhpr_400

    # Check HTTP version
    lea r8, [rcx + rax + 1]
    mov r9, rbx
    sub r9, r8
    cmp r9, 8
    jne .Lhpr_400
    push rcx
    push rax
    push r8
    push r9
    lea rdi, [r12 + r8]; mov rsi, r9; lea rdx, [rip + ver_11]; mov ecx, 8; call xslice_eq
    test eax, eax; jnz .Lhpr_v11
    mov r8, [rsp + 8]
    mov r9, [rsp + 0]
    lea rdi, [r12 + r8]; mov rsi, r9; lea rdx, [rip + ver_10]; mov ecx, 8; call xslice_eq
    test eax, eax; jz .Lhpr_vbad
    mov qword ptr [r14 + REQ_KEEP_ALIVE], 0
    jmp .Lhpr_vok
.Lhpr_v11:
    mov qword ptr [r14 + REQ_KEEP_ALIVE], 1
    jmp .Lhpr_vok
.Lhpr_vbad:
    add rsp, 32
    jmp .Lhpr_400
.Lhpr_vok:
    add rsp, 16
    pop rax
    pop rcx
    lea r8, [r12 + rcx]
    push r8
    push rax
    mov rdi, r8
    mov rsi, rax
    mov edx, '?'
    call xmemchr
    pop r9
    pop r8
    cmp rax, -1
    je .Lhpr_no_q
    mov [r14 + REQ_PATH_PTR], r8
    mov [r14 + REQ_PATH_LEN], rax
    lea rcx, [r8 + rax + 1]
    mov [r14 + REQ_QUERY_PTR], rcx
    sub r9, rax
    dec r9
    mov [r14 + REQ_QUERY_LEN], r9
    jmp .Lhpr_headers
.Lhpr_no_q:
    mov [r14 + REQ_PATH_PTR], r8
    mov [r14 + REQ_PATH_LEN], r9
    mov qword ptr [r14 + REQ_QUERY_PTR], 0
    mov qword ptr [r14 + REQ_QUERY_LEN], 0

.Lhpr_headers:
    lea rcx, [rbx + 2]
    lea r8, [r15 - 2]
.Lhpr_hloop:
    cmp rcx, r8
    jae .Lhpr_hdone
    lea rdi, [r12 + rcx]
    mov rsi, r8
    sub rsi, rcx
    mov edx, 13
    push rcx
    push r8
    call xmemchr
    pop r8
    pop rcx
    cmp rax, -1
    je .Lhpr_hdone
    lea r9, [rcx + rax + 2]
    push r9
    push r8
    lea rbx, [r12 + rcx]
    mov r10, rax
    mov rdi, rbx
    mov rsi, r10
    mov edx, ':'
    push r10
    call xmemchr
    pop r10
    cmp rax, -1
    je .Lhpr_hnext
    push rbx
    push rax
    lea rdi, [rbx + rax + 1]
    mov rsi, r10
    sub rsi, rax
    dec rsi
    call trim_ws
    mov r8, rax
    mov r9, rdx
    pop rsi
    pop rdi

    push rdi              # [rsp+24] name_ptr
    push rsi              # [rsp+16] name_len
    push r8               # [rsp+8]  val_ptr
    push r9               # [rsp+0]  val_len

    # Content-Length
    lea rdx, [rip + h_cl]
    mov ecx, h_cl_len
    call xslice_eq_ci
    test eax, eax
    jz .Lh_chk_conn
    mov rdi, [rsp + 8]
    mov rsi, [rsp + 0]
    call parse_uint
    test edx, edx
    jz .Lh_bad_cl
    cmp rax, MAX_BODY_BYTES
    ja .Lh_413_pop
    mov [r14 + REQ_CONTENT_LEN], rax
    jmp .Lh_pop_kv
.Lh_bad_cl:
    add rsp, 48
    jmp .Lhpr_400
.Lh_413_pop:
    add rsp, 48
    jmp .Lhpr_413

.Lh_chk_conn:
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 16]
    lea rdx, [rip + h_conn]
    mov ecx, h_conn_len
    call xslice_eq_ci
    test eax, eax
    jz .Lh_chk_inm
    mov rdi, [rsp + 8]
    mov rsi, [rsp + 0]
    lea rdx, [rip + v_close]
    mov ecx, 5
    call xslice_eq_ci
    test eax, eax
    jz .Lh_conn_ka
    mov qword ptr [r14 + REQ_KEEP_ALIVE], 0
    jmp .Lh_pop_kv
.Lh_conn_ka:
    mov rdi, [rsp + 8]
    mov rsi, [rsp + 0]
    lea rdx, [rip + v_ka]
    mov ecx, 10
    call xslice_eq_ci
    test eax, eax
    jz .Lh_pop_kv
    mov qword ptr [r14 + REQ_KEEP_ALIVE], 1
    jmp .Lh_pop_kv

.Lh_chk_inm:
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 16]
    lea rdx, [rip + h_inm]
    mov ecx, h_inm_len
    call xslice_eq_ci
    test eax, eax
    jz .Lh_chk_auth
    mov rax, [rsp + 8]
    mov [r14 + REQ_ETAG_PTR], rax
    mov rax, [rsp + 0]
    mov [r14 + REQ_ETAG_LEN], rax
    jmp .Lh_pop_kv

.Lh_chk_auth:
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 16]
    lea rdx, [rip + h_auth]
    mov ecx, h_auth_len
    call xslice_eq_ci
    test eax, eax
    jz .Lh_chk_cookie
    mov rax, [rsp + 8]
    mov [r14 + REQ_AUTH_PTR], rax
    mov rax, [rsp + 0]
    mov [r14 + REQ_AUTH_LEN], rax
    jmp .Lh_pop_kv

.Lh_chk_cookie:
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 16]
    lea rdx, [rip + h_cookie]
    mov ecx, h_cookie_len
    call xslice_eq_ci
    test eax, eax
    jz .Lh_chk_xfp
    mov rax, [rsp + 8]
    mov [r14 + REQ_COOKIE_PTR], rax
    mov rax, [rsp + 0]
    mov [r14 + REQ_COOKIE_LEN], rax
    jmp .Lh_pop_kv

.Lh_chk_xfp:
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 16]
    lea rdx, [rip + h_xfp]
    mov ecx, h_xfp_len
    call xslice_eq_ci
    test eax, eax
    jz .Lh_chk_range
    mov rdi, [rsp + 8]
    mov rsi, [rsp + 0]
    lea rdx, [rip + v_https]
    mov ecx, v_https_len
    call xslice_eq_ci
    test eax, eax
    jz .Lh_pop_kv
    mov qword ptr [r14 + REQ_HTTPS], 1
    jmp .Lh_pop_kv

.Lh_chk_range:
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 16]
    lea rdx, [rip + h_range]
    mov ecx, h_range_len
    call xslice_eq_ci
    test eax, eax
    jz .Lh_pop_kv
    mov rax, [rsp + 8]
    mov [r14 + REQ_RANGE_PTR], rax
    mov rax, [rsp + 0]
    mov [r14 + REQ_RANGE_LEN], rax

.Lh_pop_kv:
    add rsp, 32
.Lhpr_hnext:
    pop r8
    pop rcx
    jmp .Lhpr_hloop

.Lhpr_hdone:
    mov rax, r15
    add rax, [r14 + REQ_CONTENT_LEN]
    cmp rax, CONN_RX_CAP
    ja .Lhpr_413
    cmp r13, rax
    jb .Lhpr_need_more
    lea rcx, [r12 + r15]
    mov [r14 + REQ_BODY_PTR], rcx
    mov rdx, [r14 + REQ_CONTENT_LEN]
    mov [r14 + REQ_BODY_LEN], rdx
    jmp .Lhpr_ret

.Lhpr_need_more:
    xor eax, eax
    jmp .Lhpr_ret
.Lhpr_400:
    mov rax, -400
    jmp .Lhpr_ret
.Lhpr_413:
    mov rax, -413
    jmp .Lhpr_ret
.Lhpr_414:
    mov rax, -414
.Lhpr_ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# http_query_get(rdi=&req, rsi=key_ptr, rdx=key_len, rcx=&out_sb) -> rax=1 found, 0 not found
.globl http_query_get
http_query_get:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, [rdi + REQ_QUERY_PTR]
    mov r13, [rdi + REQ_QUERY_LEN]
    mov r14, rsi
    mov r15, rdx
    mov rbx, rcx
    test r12, r12
    jz .Lqg_no
    test r13, r13
    jz .Lqg_no
    xor ecx, ecx
.Lqg_loop:
    cmp rcx, r13
    jae .Lqg_no
    lea rdi, [r12 + rcx]
    mov rsi, r13
    sub rsi, rcx
    mov edx, '&'
    push rcx
    call xmemchr
    pop rcx
    cmp rax, -1
    jne .Lqg_seg
    mov rax, r13
    sub rax, rcx
.Lqg_seg:
    lea r8, [rcx + rax + 1]
    push r8
    push rcx
    push rax
    lea rdi, [r12 + rcx]
    mov rsi, rax
    mov edx, '='
    call xmemchr
    pop r9
    pop rcx
    cmp rax, -1
    je .Lqg_next
    push rcx
    push rax
    push r9
    lea rdi, [r12 + rcx]
    mov rsi, rax
    mov rdx, r14
    mov rcx, r15
    call xslice_eq
    pop r9
    pop rdx
    pop rcx
    test eax, eax
    jz .Lqg_next
    mov rdi, rbx
    lea rsi, [r12 + rcx + 1]
    add rsi, rdx
    sub r9, rdx
    dec r9
    mov rdx, r9
    call sb_url_decode
    pop r8
    mov eax, 1
    jmp .Lqg_ret
.Lqg_next:
    pop rcx
    jmp .Lqg_loop
.Lqg_no:
    xor eax, eax
.Lqg_ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# http_send_resp(rdi=conn, rsi=status_cstr, rdx=ctype_cstr, rcx=body_ptr, r8=body_len, r9=extra_hdr_cstr_or_0)
.globl http_send_resp
http_send_resp:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 32

    mov r12, rdi
    mov r13, rcx
    mov r14, r8
    mov r15, r9
    mov rbx, rdx
    push rsi

    lea rdi, [rsp + 8]
    mov rsi, [r12 + CONN_TX_PTR]
    mov edx, CONN_TX_CAP
    call sb_init

    lea rdi, [rsp + 8]
    lea rsi, [rip + resp_prefix]
    mov edx, resp_prefix_len
    call sb_mem
    pop rsi
    mov rdi, rsp
    call sb_cstr

    # Content-Type (omitted if ctype == NULL, e.g. 304 Not Modified)
    test rbx, rbx
    jz .Lhsr_skip_cl
    mov rdi, rsp; lea rsi, [rip + resp_ct]; mov edx, resp_ct_len; call sb_mem
    mov rdi, rsp; mov rsi, rbx; call sb_cstr

    # Content-Length
    mov rdi, rsp; lea rsi, [rip + resp_cl]; mov edx, resp_cl_len; call sb_mem
    mov rdi, rsp; mov rsi, r14; call sb_uint

.Lhsr_skip_cl:

    cmp qword ptr [r12 + CONN_KEEP_ALIVE], 0
    je .Lhsr_close
    mov rdi, rsp; lea rsi, [rip + resp_ka_on]; mov edx, resp_ka_on_len; call sb_mem
    jmp .Lhsr_sec
.Lhsr_close:
    mov rdi, rsp; lea rsi, [rip + resp_ka_off]; mov edx, resp_ka_off_len; call sb_mem
.Lhsr_sec:
    mov rdi, rsp; lea rsi, [rip + resp_sec]; mov edx, resp_sec_len; call sb_mem

    test r15, r15
    jz .Lhsr_end_hdr
    mov rdi, rsp; mov rsi, r15; call sb_cstr

.Lhsr_end_hdr:
    mov rdi, rsp; lea rsi, [rip + resp_end]; mov edx, resp_end_len; call sb_mem

    cmp qword ptr [r12 + CONN_IS_HEAD], 0
    jne .Lhsr_finish
    test r14, r14
    jz .Lhsr_finish
    test r13, r13
    jz .Lhsr_finish
    mov rdi, rsp
    mov rsi, r13
    mov rdx, r14
    call sb_mem

.Lhsr_finish:
    mov rax, [rsp + SB_LEN]
    mov [r12 + CONN_TX_LEN], rax
    mov qword ptr [r12 + CONN_TX_OFF], 0
    mov qword ptr [r12 + CONN_STATE], 2

    add rsp, 32
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

# http_send_error(rdi=conn, rsi=status_cstr, rdx=msg_cstr)
.globl http_send_error
http_send_error:
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov rdi, rdx
    call xstrlen
    mov r8, rax
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + ct_txt]
    mov rcx, r14
    xor r9d, r9d
    call http_send_resp
    pop r14
    pop r13
    pop r12
    ret

# http_inm_match(rdi=&req, rsi=etag_ptr, rdx=etag_len) -> rax=1 if If-None-Match matches
# RFC 9110 §13.1.2 weak comparison: optional `W/` prefix is ignored on both sides,
# supports `*` and comma-separated lists of entity-tags.
.globl http_inm_match
http_inm_match:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, [rdi + REQ_ETAG_PTR]
    mov r13, [rdi + REQ_ETAG_LEN]
    test r12, r12
    jz .Linm_no
    mov r14, rsi
    mov r15, rdx
    # strip our own weak prefix
    cmp r15, 2
    jb .Linm_scan
    cmp word ptr [r14], 0x2f57          # "W/"
    jne .Linm_scan
    add r14, 2
    sub r15, 2
.Linm_scan:
    xor ebx, ebx                        # cursor
.Linm_skip:
    cmp rbx, r13
    jae .Linm_no
    movzx eax, byte ptr [r12 + rbx]
    cmp al, ' '
    je .Linm_adv
    cmp al, 9
    je .Linm_adv
    cmp al, ','
    je .Linm_adv
    cmp al, '*'
    je .Linm_yes
    jmp .Linm_item
.Linm_adv:
    inc rbx
    jmp .Linm_skip
.Linm_item:
    lea rax, [rbx + 2]
    cmp rax, r13
    ja .Linm_item_start
    cmp word ptr [r12 + rbx], 0x2f57    # client weak prefix "W/"
    jne .Linm_item_start
    add rbx, 2
.Linm_item_start:
    mov rcx, rbx                        # item start
.Linm_item_end:
    cmp rbx, r13
    jae .Linm_cmp
    movzx eax, byte ptr [r12 + rbx]
    cmp al, ','
    je .Linm_cmp
    cmp al, ' '
    je .Linm_cmp
    cmp al, 9
    je .Linm_cmp
    inc rbx
    jmp .Linm_item_end
.Linm_cmp:
    lea rdi, [r12 + rcx]
    mov rsi, rbx
    sub rsi, rcx
    mov rdx, r14
    mov rcx, r15
    call xslice_eq
    test eax, eax
    jnz .Linm_yes
    jmp .Linm_skip
.Linm_yes:
    mov eax, 1
    jmp .Linm_ret
.Linm_no:
    xor eax, eax
.Linm_ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# http_cookie_get(rdi=&req, rsi=name_ptr, rdx=name_len) -> rax=val_ptr (0 if missing), rdx=val_len
.globl http_cookie_get
http_cookie_get:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, [rdi + REQ_COOKIE_PTR]
    mov r13, [rdi + REQ_COOKIE_LEN]
    mov r14, rsi
    mov r15, rdx
    test r12, r12
    jz .Lck_no
    xor rbx, rbx
.Lck_loop:
    cmp rbx, r13
    jae .Lck_no
    lea rdi, [r12 + rbx]
    mov rsi, r13
    sub rsi, rbx
    mov edx, ';'
    call xmemchr
    cmp rax, -1
    jne .Lck_seg
    mov rax, r13
    sub rax, rbx
.Lck_seg:
    lea r8, [rbx + rax + 1]
    push r8
    lea rdi, [r12 + rbx]
    mov rsi, rax
    call trim_ws
    push rax
    push rdx
    mov rdi, rax
    mov rsi, rdx
    mov edx, '='
    call xmemchr
    pop r9
    pop r8
    cmp rax, -1
    je .Lck_next
    push r8
    push rax
    push r9
    mov rdi, r8
    mov rsi, rax
    mov rdx, r14
    mov rcx, r15
    call xslice_eq
    pop r9
    pop rdx
    pop r8
    test eax, eax
    jz .Lck_next
    lea rdi, [r8 + rdx + 1]
    mov rsi, r9
    sub rsi, rdx
    dec rsi
    call trim_ws
    pop r8
    jmp .Lck_ret
.Lck_next:
    pop rbx
    jmp .Lck_loop
.Lck_no:
    xor eax, eax
    xor edx, edx
.Lck_ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# parse_hex4(rdi=ptr_4_bytes) -> eax=0..0xFFFF or -1
parse_hex4:
    push rbx
    push r12
    mov r12, rdi
    xor ebx, ebx
    xor ecx, ecx
.Lph4_loop:
    cmp ecx, 4
    jae .Lph4_ok
    push rcx
    movzx edi, byte ptr [r12 + rcx]
    call hex_nibble
    pop rcx
    test eax, eax
    js .Lph4_bad
    shl ebx, 4
    or ebx, eax
    inc ecx
    jmp .Lph4_loop
.Lph4_ok:
    mov eax, ebx
    pop r12
    pop rbx
    ret
.Lph4_bad:
    mov eax, -1
    pop r12
    pop rbx
    ret

# sb_utf8_cp(rdi=&sb, esi=unicode_codepoint) -> emits 1..4 UTF-8 bytes
sb_utf8_cp:
    push r12
    push r13
    mov r12, rdi
    mov r13d, esi
    cmp r13d, 0x80
    jae .Lu8_2
    mov rdi, r12; mov esi, r13d; call sb_byte
    jmp .Lu8_done
.Lu8_2:
    cmp r13d, 0x800
    jae .Lu8_3
    mov eax, r13d; shr eax, 6; or eax, 0xc0
    mov rdi, r12; mov esi, eax; call sb_byte
    mov eax, r13d; and eax, 0x3f; or eax, 0x80
    mov rdi, r12; mov esi, eax; call sb_byte
    jmp .Lu8_done
.Lu8_3:
    cmp r13d, 0x10000
    jae .Lu8_4
    mov eax, r13d; shr eax, 12; or eax, 0xe0
    mov rdi, r12; mov esi, eax; call sb_byte
    mov eax, r13d; shr eax, 6; and eax, 0x3f; or eax, 0x80
    mov rdi, r12; mov esi, eax; call sb_byte
    mov eax, r13d; and eax, 0x3f; or eax, 0x80
    mov rdi, r12; mov esi, eax; call sb_byte
    jmp .Lu8_done
.Lu8_4:
    mov eax, r13d; shr eax, 18; or eax, 0xf0
    mov rdi, r12; mov esi, eax; call sb_byte
    mov eax, r13d; shr eax, 12; and eax, 0x3f; or eax, 0x80
    mov rdi, r12; mov esi, eax; call sb_byte
    mov eax, r13d; shr eax, 6; and eax, 0x3f; or eax, 0x80
    mov rdi, r12; mov esi, eax; call sb_byte
    mov eax, r13d; and eax, 0x3f; or eax, 0x80
    mov rdi, r12; mov esi, eax; call sb_byte
.Lu8_done:
    pop r13
    pop r12
    ret

# json_get_str(rdi=json_ptr, rsi=json_len, rdx=key_ptr, rcx=key_len, r8=&out_sb) -> rax=1 found, 0 not found
.globl json_get_str
json_get_str:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    push r8
    xor ebx, ebx
.Ljg_scan:
    cmp rbx, r13
    jae .Ljg_no
    cmp byte ptr [r12 + rbx], '"'
    jne .Ljg_adv
    inc rbx
    mov r8, rbx
.Ljg_k_end:
    cmp rbx, r13
    jae .Ljg_no
    mov al, [r12 + rbx]
    cmp al, '\\'
    jne .Ljg_k_q
    add rbx, 2
    jmp .Ljg_k_end
.Ljg_k_q:
    cmp al, '"'
    je .Ljg_k_got
    inc rbx
    jmp .Ljg_k_end
.Ljg_k_got:
    mov r9, rbx
    sub r9, r8
    inc rbx
.Ljg_ws1:
    cmp rbx, r13
    jae .Ljg_no
    mov al, [r12 + rbx]
    cmp al, ' '
    je .Ljg_ws1_s
    cmp al, 9
    je .Ljg_ws1_s
    cmp al, 10
    je .Ljg_ws1_s
    cmp al, 13
    je .Ljg_ws1_s
    jmp .Ljg_colon
.Ljg_ws1_s:
    inc rbx
    jmp .Ljg_ws1
.Ljg_colon:
    cmp byte ptr [r12 + rbx], ':'
    jne .Ljg_scan
    inc rbx
    push r8
    push r9
    lea rdi, [r12 + r8]
    mov rsi, r9
    mov rdx, r14
    mov rcx, r15
    call xslice_eq
    pop r9
    pop r8
    test eax, eax
    jz .Ljg_scan
.Ljg_ws2:
    cmp rbx, r13
    jae .Ljg_no
    mov al, [r12 + rbx]
    cmp al, ' '
    je .Ljg_ws2_s
    cmp al, 9
    je .Ljg_ws2_s
    cmp al, 10
    je .Ljg_ws2_s
    cmp al, 13
    je .Ljg_ws2_s
    jmp .Ljg_val
.Ljg_ws2_s:
    inc rbx
    jmp .Ljg_ws2
.Ljg_val:
    cmp byte ptr [r12 + rbx], '"'
    je .Ljg_str_val
    # Also accept JSON literal true (4 bytes) so boolean fields like "draft":true work
    lea rcx, [rbx + 4]
    cmp rcx, r13
    ja .Ljg_no
    cmp dword ptr [r12 + rbx], 0x65757274
    jne .Ljg_no
    mov rdi, [rsp]
    lea rsi, [r12 + rbx]
    mov edx, 4
    call sb_mem
    jmp .Ljg_yes
.Ljg_str_val:
    inc rbx
    mov r14, [rsp]
.Ljg_vloop:
    cmp rbx, r13
    jae .Ljg_no
    movzx eax, byte ptr [r12 + rbx]
    cmp al, '"'
    je .Ljg_yes
    cmp al, '\\'
    jne .Ljg_vemit
    inc rbx
    cmp rbx, r13
    jae .Ljg_no
    movzx eax, byte ptr [r12 + rbx]
    cmp al, 'n'
    je .Ljg_esc_n
    cmp al, 'r'
    je .Ljg_esc_r
    cmp al, 't'
    je .Ljg_esc_t
    cmp al, 'b'
    je .Ljg_esc_b
    cmp al, 'f'
    je .Ljg_esc_f
    cmp al, 'u'
    je .Ljg_esc_u
    jmp .Ljg_vemit
.Ljg_esc_n: mov eax, 10; jmp .Ljg_vemit
.Ljg_esc_r: mov eax, 13; jmp .Ljg_vemit
.Ljg_esc_t: mov eax, 9;  jmp .Ljg_vemit
.Ljg_esc_b: mov eax, 8;  jmp .Ljg_vemit
.Ljg_esc_f: mov eax, 12; jmp .Ljg_vemit
.Ljg_esc_u:
    lea rcx, [rbx + 4]
    cmp rcx, r13
    jae .Ljg_vemit
    lea rdi, [r12 + rbx + 1]
    call parse_hex4
    test eax, eax
    js .Ljg_u_fallback
    add rbx, 4
    # Check UTF-16 high surrogate (0xD800..0xDBFF) + trailing \uXXXX low surrogate
    cmp eax, 0xd800
    jb .Ljg_u_emit
    cmp eax, 0xdbff
    ja .Ljg_u_emit
    lea rcx, [rbx + 6]
    cmp rcx, r13
    jae .Ljg_u_emit
    cmp byte ptr [r12 + rbx + 1], '\\'
    jne .Ljg_u_emit
    cmp byte ptr [r12 + rbx + 2], 'u'
    jne .Ljg_u_emit
    push rax
    lea rdi, [r12 + rbx + 3]
    call parse_hex4
    mov edx, eax
    pop rax
    cmp edx, 0xdc00
    jb .Ljg_u_emit
    cmp edx, 0xdfff
    ja .Ljg_u_emit
    sub eax, 0xd800
    shl eax, 10
    sub edx, 0xdc00
    add eax, edx
    add eax, 0x10000
    add rbx, 6
.Ljg_u_emit:
    mov rdi, r14
    mov esi, eax
    call sb_utf8_cp
    inc rbx
    jmp .Ljg_vloop
.Ljg_u_fallback:
    mov eax, 'u'
.Ljg_vemit:
    mov rdi, r14
    mov esi, eax
    call sb_byte
    inc rbx
    jmp .Ljg_vloop
.Ljg_adv:
    inc rbx
    jmp .Ljg_scan
.Ljg_yes:
    pop r8
    mov eax, 1
    jmp .Ljg_ret
.Ljg_no:
    pop r8
    xor eax, eax
.Ljg_ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
