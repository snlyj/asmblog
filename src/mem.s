.include "defs.inc"

.section .bss
.align 8
.globl g_arena_base
g_arena_base: .quad 0
.globl g_arena_used
g_arena_used: .quad 0
.globl g_arena_cap
g_arena_cap:  .quad 0

.section .rodata
hex_chars: .ascii "0123456789abcdef"
esc_amp:   .ascii "&amp;"
esc_lt:    .ascii "&lt;"
esc_gt:    .ascii "&gt;"
esc_quot:  .ascii "&quot;"
esc_apos:  .ascii "&#39;"
month_days: .byte 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31

.section .text

# --- Arena Allocator (mmap backed, O(1) reset) ---

# arena_init(rdi=cap_bytes) -> rax=0 ok, <0 err
.globl arena_init
arena_init:
    push rbx
    mov rbx, rdi
    xor edi, edi
    mov rsi, rbx
    mov edx, PROT_READ | PROT_WRITE
    mov ecx, MAP_PRIVATE | MAP_ANONYMOUS
    mov r8, -1
    xor r9d, r9d
    call sys_mmap
    cmp rax, -4095
    jae .Lai_err
    mov [rip + g_arena_base], rax
    mov qword ptr [rip + g_arena_used], 0
    mov [rip + g_arena_cap], rbx
    xor eax, eax
    pop rbx
    ret
.Lai_err:
    pop rbx
    ret

# arena_reset() -> resets bump pointer
.globl arena_reset
arena_reset:
    mov qword ptr [rip + g_arena_used], 0
    ret

# arena_alloc(rdi=size) -> rax=ptr (8-byte aligned) or 0 if OOM
.globl arena_alloc
arena_alloc:
    mov rcx, [rip + g_arena_used]
    add rcx, 7
    and rcx, -8
    mov rax, rcx
    add rax, rdi
    cmp rax, [rip + g_arena_cap]
    ja .Laa_oom
    mov [rip + g_arena_used], rax
    mov rax, [rip + g_arena_base]
    add rax, rcx
    ret
.Laa_oom:
    xor eax, eax
    ret

# arena_dup(rdi=src_ptr, rsi=len) -> rax=dst_ptr (NUL-terminated copy) or 0
.globl arena_dup
arena_dup:
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    lea rdi, [r13 + 1]
    call arena_alloc
    test rax, rax
    jz .Lad_done
    push rax
    mov rdi, rax
    mov rsi, r12
    mov rdx, r13
    call xmemcpy
    pop rax
    mov byte ptr [rax + r13], 0
.Lad_done:
    pop r13
    pop r12
    ret

# --- Core memory / string functions ---

# xmemcpy(rdi=dst, rsi=src, rdx=len) -> rax=dst
.globl xmemcpy
xmemcpy:
    mov rax, rdi
    mov rcx, rdx
    cld
    rep movsb
    ret

# xmemset(rdi=dst, rsi=byte_val, rdx=len) -> rax=dst
.globl xmemset
xmemset:
    mov r8, rdi
    mov eax, esi
    mov rcx, rdx
    cld
    rep stosb
    mov rax, r8
    ret

# xstrlen(rdi=cstr) -> rax=len
.globl xstrlen
xstrlen:
    xor eax, eax
.Lxlen_loop:
    cmp byte ptr [rdi + rax], 0
    je .Lxlen_done
    inc rax
    jmp .Lxlen_loop
.Lxlen_done:
    ret

# xmemeq(rdi=a, rsi=b, rdx=len) -> rax=1 if equal else 0
.globl xmemeq
xmemeq:
    xor ecx, ecx
.Lxmeq_loop:
    cmp rcx, rdx
    jae .Lxmeq_yes
    mov al, [rdi + rcx]
    cmp al, [rsi + rcx]
    jne .Lxmeq_no
    inc rcx
    jmp .Lxmeq_loop
.Lxmeq_yes:
    mov eax, 1
    ret
.Lxmeq_no:
    xor eax, eax
    ret

# xslice_eq(rdi=a_ptr, rsi=a_len, rdx=b_ptr, rcx=b_len) -> rax=1 if eq else 0
.globl xslice_eq
xslice_eq:
    cmp rsi, rcx
    jne .Lxseq_no
    mov rcx, rsi
    mov rsi, rdx
    mov rdx, rcx
    jmp xmemeq
.Lxseq_no:
    xor eax, eax
    ret

# xslice_eq_ci(rdi=a_ptr, rsi=a_len, rdx=b_ptr, rcx=b_len) -> rax=1 if ascii case-insensitive eq
.globl xslice_eq_ci
xslice_eq_ci:
    cmp rsi, rcx
    jne .Lci_no
    xor r8d, r8d
.Lci_loop:
    cmp r8, rsi
    jae .Lci_yes
    movzx eax, byte ptr [rdi + r8]
    movzx ecx, byte ptr [rdx + r8]
    cmp al, 'A'
    jb .Lci_a_ok
    cmp al, 'Z'
    ja .Lci_a_ok
    add al, 32
.Lci_a_ok:
    cmp cl, 'A'
    jb .Lci_b_ok
    cmp cl, 'Z'
    ja .Lci_b_ok
    add cl, 32
.Lci_b_ok:
    cmp al, cl
    jne .Lci_no
    inc r8
    jmp .Lci_loop
.Lci_yes:
    mov eax, 1
    ret
.Lci_no:
    xor eax, eax
    ret

# xmemcmp(rdi=a, rsi=b, rdx=len) -> rax (<0, 0, >0)
.globl xmemcmp
xmemcmp:
    xor ecx, ecx
.Lmc_loop:
    cmp rcx, rdx
    jae .Lmc_eq
    movzx eax, byte ptr [rdi + rcx]
    movzx r8d, byte ptr [rsi + rcx]
    sub eax, r8d
    jnz .Lmc_ret
    inc rcx
    jmp .Lmc_loop
.Lmc_eq:
    xor eax, eax
.Lmc_ret:
    movsxd rax, eax
    ret

# xslice_cmp(rdi=a_ptr, rsi=a_len, rdx=b_ptr, rcx=b_len) -> rax (<0, 0, >0)
.globl xslice_cmp
xslice_cmp:
    push r12
    push r13
    mov r12, rsi
    mov r13, rcx
    mov r8, rsi
    cmp r8, rcx
    jbe .Lsc_min
    mov r8, rcx
.Lsc_min:
    mov rsi, rdx
    mov rdx, r8
    call xmemcmp
    test rax, rax
    jnz .Lsc_done
    mov rax, r12
    sub rax, r13
.Lsc_done:
    pop r13
    pop r12
    ret

# xmemchr(rdi=ptr, rsi=len, rdx=byte) -> rax=offset or -1
.globl xmemchr
xmemchr:
    xor ecx, ecx
.Lmch_loop:
    cmp rcx, rsi
    jae .Lmch_no
    cmp byte ptr [rdi + rcx], dl
    je .Lmch_yes
    inc rcx
    jmp .Lmch_loop
.Lmch_yes:
    mov rax, rcx
    ret
.Lmch_no:
    mov rax, -1
    ret

# xmemmem_ci(rdi=hay_ptr, rsi=hay_len, rdx=ned_ptr, rcx=ned_len) -> rax=1 if found else 0
.globl xmemmem_ci
xmemmem_ci:
    test rcx, rcx
    jz .Lmm_yes
    cmp rcx, rsi
    ja .Lmm_no
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    sub r13, rcx
    mov r14, rdx
    mov r15, rcx
    xor ebx, ebx
.Lmm_outer:
    cmp rbx, r13
    ja .Lmm_fail
    lea rdi, [r12 + rbx]
    mov rsi, r15
    mov rdx, r14
    mov rcx, r15
    call xslice_eq_ci
    test eax, eax
    jnz .Lmm_ok
    inc rbx
    jmp .Lmm_outer
.Lmm_ok:
    mov eax, 1
    jmp .Lmm_pop
.Lmm_fail:
    xor eax, eax
.Lmm_pop:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.Lmm_yes:
    mov eax, 1
    ret
.Lmm_no:
    xor eax, eax
    ret

# trim_ws(rdi=ptr, rsi=len) -> rax=new_ptr, rdx=new_len
.globl trim_ws
trim_ws:
    mov rax, rdi
    mov rdx, rsi
.Ltw_lead:
    test rdx, rdx
    jz .Ltw_done
    mov cl, [rax]
    cmp cl, ' '
    je .Ltw_lskip
    cmp cl, 9
    je .Ltw_lskip
    cmp cl, 13
    je .Ltw_lskip
    cmp cl, 10
    je .Ltw_lskip
    jmp .Ltw_trail
.Ltw_lskip:
    inc rax
    dec rdx
    jmp .Ltw_lead
.Ltw_trail:
    test rdx, rdx
    jz .Ltw_done
    mov cl, [rax + rdx - 1]
    cmp cl, ' '
    je .Ltw_tskip
    cmp cl, 9
    je .Ltw_tskip
    cmp cl, 13
    je .Ltw_tskip
    cmp cl, 10
    je .Ltw_tskip
    jmp .Ltw_done
.Ltw_tskip:
    dec rdx
    jmp .Ltw_trail
.Ltw_done:
    ret

# parse_uint(rdi=ptr, rsi=len) -> rax=value, rdx=1 ok / 0 invalid
.globl parse_uint
parse_uint:
    test rsi, rsi
    jz .Lpu_bad
    xor eax, eax
    xor ecx, ecx
.Lpu_loop:
    cmp rcx, rsi
    jae .Lpu_ok
    movzx r8d, byte ptr [rdi + rcx]
    sub r8d, '0'
    cmp r8d, 9
    ja .Lpu_bad
    imul rax, rax, 10
    add rax, r8
    inc rcx
    jmp .Lpu_loop
.Lpu_ok:
    mov edx, 1
    ret
.Lpu_bad:
    xor eax, eax
    xor edx, edx
    ret

# --- Safe Byte Buffer (sbuf_t) ---

# sb_init(rdi=&sb, rsi=buf_ptr, rdx=cap)
.globl sb_init
sb_init:
    mov [rdi + SB_PTR], rsi
    mov qword ptr [rdi + SB_LEN], 0
    mov [rdi + SB_CAP], rdx
    ret

# sb_byte(rdi=&sb, sil=byte)
.globl sb_byte
sb_byte:
    mov rax, [rdi + SB_LEN]
    cmp rax, [rdi + SB_CAP]
    jae .Lsbb_full
    mov rcx, [rdi + SB_PTR]
    mov [rcx + rax], sil
    inc rax
    mov [rdi + SB_LEN], rax
.Lsbb_full:
    ret

# sb_mem(rdi=&sb, rsi=src, rdx=len)
.globl sb_mem
sb_mem:
    test rdx, rdx
    jz .Lsbm_done
    mov rax, [rdi + SB_CAP]
    mov r8, [rdi + SB_LEN]
    sub rax, r8
    jbe .Lsbm_done
    cmp rdx, rax
    jbe .Lsbm_fit
    mov rdx, rax
.Lsbm_fit:
    push rdi
    push rdx
    mov rdi, [rdi + SB_PTR]
    add rdi, r8
    call xmemcpy
    pop rdx
    pop rdi
    add [rdi + SB_LEN], rdx
.Lsbm_done:
    ret

# sb_cstr(rdi=&sb, rsi=cstr)
.globl sb_cstr
sb_cstr:
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    mov rdi, rsi
    call xstrlen
    mov rdi, r12
    mov rsi, r13
    mov rdx, rax
    call sb_mem
    pop r13
    pop r12
    ret

# sb_uint(rdi=&sb, rsi=val)
.globl sb_uint
sb_uint:
    push r12
    sub rsp, 32
    mov r12, rdi
    mov rax, rsi
    lea r9, [rsp + 31]
    xor ecx, ecx
    test rax, rax
    jnz .Lsbu_div
    mov byte ptr [r9], '0'
    mov ecx, 1
    jmp .Lsbu_emit
.Lsbu_div:
    mov r10, 10
.Lsbu_loop:
    xor edx, edx
    div r10
    add dl, '0'
    mov [r9], dl
    dec r9
    inc ecx
    test rax, rax
    jnz .Lsbu_loop
    inc r9
.Lsbu_emit:
    mov rdi, r12
    mov rsi, r9
    mov rdx, rcx
    call sb_mem
    add rsp, 32
    pop r12
    ret

# sb_hex(rdi=&sb, rsi=bytes_ptr, rdx=bytes_len)
.globl sb_hex
sb_hex:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    xor ebx, ebx
    lea r9, [rip + hex_chars]
.Lsbh_loop:
    cmp rbx, r14
    jae .Lsbh_done
    movzx eax, byte ptr [r13 + rbx]
    mov edx, eax
    shr edx, 4
    and eax, 0x0f
    lea r9, [rip + hex_chars]
    movzx esi, byte ptr [r9 + rdx]
    push rax
    mov rdi, r12
    call sb_byte
    pop rax
    lea r9, [rip + hex_chars]
    movzx esi, byte ptr [r9 + rax]
    mov rdi, r12
    call sb_byte
    inc rbx
    jmp .Lsbh_loop
.Lsbh_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# sb_esc_html(rdi=&sb, rsi=ptr, rdx=len)
.globl sb_esc_html
sb_esc_html:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    xor ebx, ebx
.Lsh_loop:
    cmp rbx, r14
    jae .Lsh_done
    movzx eax, byte ptr [r13 + rbx]
    cmp al, '&'
    je .Lsh_amp
    cmp al, '<'
    je .Lsh_lt
    cmp al, '>'
    je .Lsh_gt
    cmp al, '"'
    je .Lsh_quot
    cmp al, 39
    je .Lsh_apos
    mov rdi, r12
    mov esi, eax
    call sb_byte
    jmp .Lsh_next
.Lsh_amp:
    mov rdi, r12
    lea rsi, [rip + esc_amp]
    mov edx, 5
    call sb_mem
    jmp .Lsh_next
.Lsh_lt:
    mov rdi, r12
    lea rsi, [rip + esc_lt]
    mov edx, 4
    call sb_mem
    jmp .Lsh_next
.Lsh_gt:
    mov rdi, r12
    lea rsi, [rip + esc_gt]
    mov edx, 4
    call sb_mem
    jmp .Lsh_next
.Lsh_quot:
    mov rdi, r12
    lea rsi, [rip + esc_quot]
    mov edx, 6
    call sb_mem
    jmp .Lsh_next
.Lsh_apos:
    mov rdi, r12
    lea rsi, [rip + esc_apos]
    mov edx, 5
    call sb_mem
.Lsh_next:
    inc rbx
    jmp .Lsh_loop
.Lsh_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# sb_esc_json(rdi=&sb, rsi=ptr, rdx=len)
.globl sb_esc_json
sb_esc_json:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    xor ebx, ebx
.Lsj_loop:
    cmp rbx, r14
    jae .Lsj_done
    movzx eax, byte ptr [r13 + rbx]
    cmp al, '"'
    je .Lsj_bs
    cmp al, '\\'
    je .Lsj_bs
    cmp al, 10
    je .Lsj_nl
    cmp al, 13
    je .Lsj_cr
    cmp al, 9
    je .Lsj_tab
    cmp al, 32
    jb .Lsj_ctrl
    mov rdi, r12
    mov esi, eax
    call sb_byte
    jmp .Lsj_next
.Lsj_bs:
    push rax
    mov rdi, r12
    mov esi, '\\'
    call sb_byte
    pop rax
    mov rdi, r12
    mov esi, eax
    call sb_byte
    jmp .Lsj_next
.Lsj_nl:
    mov rdi, r12
    mov esi, '\\'
    call sb_byte
    mov rdi, r12
    mov esi, 'n'
    call sb_byte
    jmp .Lsj_next
.Lsj_cr:
    mov rdi, r12
    mov esi, '\\'
    call sb_byte
    mov rdi, r12
    mov esi, 'r'
    call sb_byte
    jmp .Lsj_next
.Lsj_tab:
    mov rdi, r12
    mov esi, '\\'
    call sb_byte
    mov rdi, r12
    mov esi, 't'
    call sb_byte
    jmp .Lsj_next
.Lsj_ctrl:
    # skip control char < 0x20
.Lsj_next:
    inc rbx
    jmp .Lsj_loop
.Lsj_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# hex_nibble(dil=char) -> eax=0..15 or -1
.globl hex_nibble
hex_nibble:
    movzx eax, dil
    cmp al, '0'
    jb .Lhn_bad
    cmp al, '9'
    jbe .Lhn_dig
    cmp al, 'A'
    jb .Lhn_bad
    cmp al, 'F'
    jbe .Lhn_up
    cmp al, 'a'
    jb .Lhn_bad
    cmp al, 'f'
    jbe .Lhn_lo
.Lhn_bad:
    mov eax, -1
    ret
.Lhn_dig:
    sub eax, '0'
    ret
.Lhn_up:
    sub eax, 'A' - 10
    ret
.Lhn_lo:
    sub eax, 'a' - 10
    ret

# sb_url_decode(rdi=&sb, rsi=src, rdx=len) -> decodes %XX and '+'
.globl sb_url_decode
sb_url_decode:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    xor ebx, ebx
.Lud_loop:
    cmp rbx, r14
    jae .Lud_done
    movzx eax, byte ptr [r13 + rbx]
    cmp al, '+'
    je .Lud_plus
    cmp al, '%'
    jne .Lud_emit
    lea rcx, [rbx + 2]
    cmp rcx, r14
    jae .Lud_emit
    movzx edi, byte ptr [r13 + rbx + 1]
    call hex_nibble
    test eax, eax
    js .Lud_pct_raw
    shl eax, 4
    push rax
    movzx edi, byte ptr [r13 + rbx + 2]
    call hex_nibble
    pop rcx
    test eax, eax
    js .Lud_pct_raw
    or eax, ecx
    add rbx, 2
    jmp .Lud_emit
.Lud_pct_raw:
    mov eax, '%'
    jmp .Lud_emit
.Lud_plus:
    mov eax, ' '
.Lud_emit:
    mov rdi, r12
    mov esi, eax
    call sb_byte
    inc rbx
    jmp .Lud_loop
.Lud_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# --- Security validators ---

# is_safe_slug(rdi=ptr, rsi=len) -> rax=1 valid [a-zA-Z0-9_-]{1..120}, 0 invalid
.globl is_safe_slug
is_safe_slug:
    test rsi, rsi
    jz .Lss_no
    cmp rsi, 120
    ja .Lss_no
    xor ecx, ecx
.Lss_loop:
    cmp rcx, rsi
    jae .Lss_yes
    movzx eax, byte ptr [rdi + rcx]
    cmp al, 'a'
    jb .Lss_chk_up
    cmp al, 'z'
    jbe .Lss_ok
.Lss_chk_up:
    cmp al, 'A'
    jb .Lss_chk_dig
    cmp al, 'Z'
    jbe .Lss_ok
.Lss_chk_dig:
    cmp al, '0'
    jb .Lss_chk_sym
    cmp al, '9'
    jbe .Lss_ok
.Lss_chk_sym:
    cmp al, '-'
    je .Lss_ok
    cmp al, '_'
    je .Lss_ok
    jmp .Lss_no
.Lss_ok:
    inc rcx
    jmp .Lss_loop
.Lss_yes:
    mov eax, 1
    ret
.Lss_no:
    xor eax, eax
    ret

# is_safe_relpath(rdi=ptr, rsi=len) -> rax=1 if safe relative path (no leading '/', no '..', no '\', no NUL)
.globl is_safe_relpath
is_safe_relpath:
    test rsi, rsi
    jz .Lsr_no
    cmp rsi, 256
    ja .Lsr_no
    cmp byte ptr [rdi], '/'
    je .Lsr_no
    cmp byte ptr [rdi], '.'
    je .Lsr_no
    xor ecx, ecx
.Lsr_loop:
    cmp rcx, rsi
    jae .Lsr_yes
    movzx eax, byte ptr [rdi + rcx]
    test al, al
    jz .Lsr_no
    cmp al, '\\'
    je .Lsr_no
    cmp al, '.'
    jne .Lsr_next
    # Block hidden dotfiles (e.g. sub/.part, .gitkeep) and ".." traversal
    test rcx, rcx
    jz .Lsr_no
    cmp byte ptr [rdi + rcx - 1], '/'
    je .Lsr_no
    lea rdx, [rcx + 1]
    cmp rdx, rsi
    jae .Lsr_next
    cmp byte ptr [rdi + rdx], '.'
    je .Lsr_no
.Lsr_next:
    inc rcx
    jmp .Lsr_loop
.Lsr_yes:
    mov eax, 1
    ret
.Lsr_no:
    xor eax, eax
    ret

# format_iso_date(rdi=unix_epoch_sec, rsi=out_10bytes) -> writes "YYYY-MM-DD"
.globl format_iso_date
format_iso_date:
    push rbx
    push r12
    mov r12, rsi
    mov rax, rdi
    xor edx, edx
    mov rcx, 86400
    div rcx               # rax = days since 1970-01-01
    mov rbx, 1970
.Lfid_yr:
    mov rcx, 365
    # leap year check: (y%4==0 && y%100!=0) || (y%400==0)
    mov r8, rbx
    and r8, 3
    jnz .Lfid_noleap
    push rax
    mov rax, rbx
    xor edx, edx
    mov r9, 100
    div r9
    test rdx, rdx
    jnz .Lfid_isleap_pop
    mov rax, rbx
    xor edx, edx
    mov r9, 400
    div r9
    test rdx, rdx
    jnz .Lfid_noleap_pop
.Lfid_isleap_pop:
    pop rax
    mov rcx, 366
    jmp .Lfid_ycmp
.Lfid_noleap_pop:
    pop rax
.Lfid_noleap:
.Lfid_ycmp:
    cmp rax, rcx
    jb .Lfid_yr_done
    sub rax, rcx
    inc rbx
    jmp .Lfid_yr
.Lfid_yr_done:
    # rbx = year, rax = day of year (0-based), rcx = 365 or 366
    xor r8d, r8d          # month 0..11
    lea r9, [rip + month_days]
.Lfid_mo:
    movzx r10d, byte ptr [r9 + r8]
    cmp r8d, 1
    jne .Lfid_mcmp
    cmp rcx, 366
    jne .Lfid_mcmp
    mov r10d, 29
.Lfid_mcmp:
    cmp rax, r10
    jb .Lfid_mo_done
    sub rax, r10
    inc r8d
    cmp r8d, 12
    jb .Lfid_mo
.Lfid_mo_done:
    inc r8d               # month 1..12
    inc eax               # day 1..31
    push rax              # save day
    push r8               # save month
    # format YYYY
    mov rax, rbx
    mov r10, 10
    xor edx, edx
    div r10
    add dl, '0'
    mov [r12 + 3], dl
    xor edx, edx
    div r10
    add dl, '0'
    mov [r12 + 2], dl
    xor edx, edx
    div r10
    add dl, '0'
    mov [r12 + 1], dl
    xor edx, edx
    div r10
    add dl, '0'
    mov [r12 + 0], dl
    mov byte ptr [r12 + 4], '-'
    pop rax               # month
    xor edx, edx
    div r10
    add al, '0'
    add dl, '0'
    mov [r12 + 5], al
    mov [r12 + 6], dl
    mov byte ptr [r12 + 7], '-'
    pop rax               # day
    xor edx, edx
    div r10
    add al, '0'
    add dl, '0'
    mov [r12 + 8], al
    mov [r12 + 9], dl
    pop r12
    pop rbx
    ret
