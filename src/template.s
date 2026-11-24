.include "defs.inc"

# Pure x86-64 Lightweight Mustache-like HTML Template Engine
# Syntax:
#   {{ key }}          -> HTML-escaped variable substitution
#   {{{ key }}}        -> Raw trusted HTML substitution
#   {{> partial }}     -> Partial template include (from theme templates)
#   {{#sec}}...{{/sec}} -> Loop or truthy conditional section
#   {{^sec}}...{{/sec}} -> Inverted section (renders if empty/false)

.section .text

# tpl_lookup_var(rdi=&ctx, rsi=key_ptr, rdx=key_len) -> rax=val_ptr (0 if missing), rdx=val_len
.globl tpl_lookup_var
tpl_lookup_var:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, [rdi + TCTX_VARS_PTR]
    mov r13, [rdi + TCTX_VARS_CNT]
    mov r14, rsi
    mov r15, rdx
    xor ebx, ebx
.Ltlv_loop:
    cmp rbx, r13
    jae .Ltlv_miss
    imul rax, rbx, TV_SIZE
    mov rdi, [r12 + rax + TV_KEY_PTR]
    mov rsi, [r12 + rax + TV_KEY_LEN]
    mov rdx, r14
    mov rcx, r15
    call xslice_eq
    test eax, eax
    jnz .Ltlv_hit
    inc rbx
    jmp .Ltlv_loop
.Ltlv_hit:
    imul rcx, rbx, TV_SIZE
    mov rax, [r12 + rcx + TV_VAL_PTR]
    mov rdx, [r12 + rcx + TV_VAL_LEN]
    jmp .Ltlv_ret
.Ltlv_miss:
    xor eax, eax
    xor edx, edx
.Ltlv_ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# find_close_braces(rdi=ptr, rsi=len, edx=count_2_or_3) -> rax=offset of '}}' or '}}}' or -1
find_close_braces:
    cmp edx, 3
    je .Lfcb_3
    cmp rsi, 2
    jb .Lfcb_no
    lea rcx, [rsi - 1]
    xor eax, eax
.Lfcb_2l:
    cmp rax, rcx
    jae .Lfcb_no
    cmp word ptr [rdi + rax], 0x7d7d    # "}}"
    je .Lfcb_yes
    inc rax
    jmp .Lfcb_2l
.Lfcb_3:
    cmp rsi, 3
    jb .Lfcb_no
    lea rcx, [rsi - 2]
    xor eax, eax
.Lfcb_3l:
    cmp rax, rcx
    jae .Lfcb_no
    cmp word ptr [rdi + rax], 0x7d7d
    jne .Lfcb_3n
    cmp byte ptr [rdi + rax + 2], '}'
    je .Lfcb_yes
.Lfcb_3n:
    inc rax
    jmp .Lfcb_3l
.Lfcb_yes:
    ret
.Lfcb_no:
    mov rax, -1
    ret

# find_section_end(rdi=ptr, rsi=len, rdx=sec_ptr, rcx=sec_len)
# Returns rax=offset of "{{/sec}}" start, rdx=offset right after "}}" (or rax=-1 if not found)
find_section_end:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi          # hay
    mov r13, rsi          # hay_len
    mov r14, rdx          # sec_name
    mov r15, rcx          # sec_len
    xor ebx, ebx
.Lfse_loop:
    lea rax, [rbx + 5]
    cmp rax, r13
    jae .Lfse_no
    cmp word ptr [r12 + rbx], 0x7b7b    # "{{"
    jne .Lfse_adv
    cmp byte ptr [r12 + rbx + 2], '/'
    jne .Lfse_adv
    # find closing "}}"
    lea rdi, [r12 + rbx + 3]
    mov rsi, r13
    sub rsi, rbx
    sub rsi, 3
    mov edx, 2
    call find_close_braces
    cmp rax, -1
    je .Lfse_no
    push rax
    lea rdi, [r12 + rbx + 3]
    mov rsi, rax
    call trim_ws
    mov rdi, rax
    mov rsi, rdx
    mov rdx, r14
    mov rcx, r15
    call xslice_eq
    pop r8                # close_off relative to rbx+3
    test eax, eax
    jnz .Lfse_found
.Lfse_adv:
    inc rbx
    jmp .Lfse_loop
.Lfse_found:
    mov rax, rbx
    lea rdx, [rbx + 3 + r8 + 2]
    jmp .Lfse_ret
.Lfse_no:
    mov rax, -1
    xor edx, edx
.Lfse_ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# tpl_render(rdi=tpl_ptr, rsi=tpl_len, rdx=&ctx, rcx=&out_sb)
.globl tpl_render
tpl_render:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi          # tpl
    mov r13, rsi          # len
    mov r14, rdx          # &ctx
    mov r15, rcx          # &out_sb

    # Recursion guard
    cmp qword ptr [r14 + TCTX_DEPTH], 8
    jae .Ltr_done

    xor rbx, rbx          # cursor
.Ltr_loop:
    cmp rbx, r13
    jae .Ltr_done
    # Scan for "{{"
    mov r8, rbx
.Ltr_scan:
    lea rax, [r8 + 1]
    cmp rax, r13
    jae .Ltr_tail
    cmp word ptr [r12 + r8], 0x7b7b
    je .Ltr_found_open
    inc r8
    jmp .Ltr_scan

.Ltr_tail:
    # Emit remaining literal
    mov rdi, r15
    lea rsi, [r12 + rbx]
    mov rdx, r13
    sub rdx, rbx
    call sb_mem
    jmp .Ltr_done

.Ltr_found_open:
    # Emit literal [rbx .. r8)
    cmp r8, rbx
    jbe .Ltr_parse_tag
    push r8
    mov rdi, r15
    lea rsi, [r12 + rbx]
    mov rdx, r8
    sub rdx, rbx
    call sb_mem
    pop r8

.Ltr_parse_tag:
    mov rbx, r8           # at "{{"
    lea rax, [rbx + 3]
    cmp rax, r13
    jae .Ltr_tail

    movzx eax, byte ptr [r12 + rbx + 2]
    # Case 1: Triple braces {{{ key }}}
    cmp al, '{'
    je .Ltr_triple
    # Case 2: Partial {{> name }}
    cmp al, '>'
    je .Ltr_partial
    # Case 3: Section {{# name }} or Inverted {{^ name }}
    cmp al, '#'
    je .Ltr_section
    cmp al, '^'
    je .Ltr_section_inv

    # Case 4: Standard escaped variable {{ key }}
    lea rdi, [r12 + rbx + 2]
    mov rsi, r13
    sub rsi, rbx
    sub rsi, 2
    mov edx, 2
    call find_close_braces
    cmp rax, -1
    je .Ltr_tail
    push rax
    lea rdi, [r12 + rbx + 2]
    mov rsi, rax
    call trim_ws
    mov rdi, r14
    mov rsi, rax
    call tpl_lookup_var
    test rax, rax
    jz .Ltr_v_adv
    mov rdi, r15
    mov rsi, rax
    call sb_esc_html
.Ltr_v_adv:
    pop rax
    lea rbx, [rbx + 2 + rax + 2]
    jmp .Ltr_loop

.Ltr_triple:
    lea rdi, [r12 + rbx + 3]
    mov rsi, r13
    sub rsi, rbx
    sub rsi, 3
    mov edx, 3
    call find_close_braces
    cmp rax, -1
    je .Ltr_tail
    push rax
    lea rdi, [r12 + rbx + 3]
    mov rsi, rax
    call trim_ws
    mov rdi, r14
    mov rsi, rax
    call tpl_lookup_var
    test rax, rax
    jz .Ltr_t_adv
    mov rdi, r15
    mov rsi, rax
    call sb_mem
.Ltr_t_adv:
    pop rax
    lea rbx, [rbx + 3 + rax + 3]
    jmp .Ltr_loop

.Ltr_partial:
    lea rdi, [r12 + rbx + 3]
    mov rsi, r13
    sub rsi, rbx
    sub rsi, 3
    mov edx, 2
    call find_close_braces
    cmp rax, -1
    je .Ltr_tail
    push rax
    lea rdi, [r12 + rbx + 3]
    mov rsi, rax
    call trim_ws
    mov rdi, rax
    mov rsi, rdx
    call store_find_tpl
    test rax, rax
    jz .Ltr_p_adv
    inc qword ptr [r14 + TCTX_DEPTH]
    mov rdi, rax
    mov rsi, rdx
    mov rdx, r14
    mov rcx, r15
    call tpl_render
    dec qword ptr [r14 + TCTX_DEPTH]
.Ltr_p_adv:
    pop rax
    lea rbx, [rbx + 3 + rax + 2]
    jmp .Ltr_loop

.Ltr_section:
    xor r9d, r9d          # inverted = 0
    jmp .Ltr_sec_go
.Ltr_section_inv:
    mov r9d, 1            # inverted = 1
.Ltr_sec_go:
    push r9               # [rsp] = inverted
    lea rdi, [r12 + rbx + 3]
    mov rsi, r13
    sub rsi, rbx
    sub rsi, 3
    mov edx, 2
    call find_close_braces
    cmp rax, -1
    je .Ltr_sec_eof
    # sec_name = trim(r12+rbx+3, rax)
    lea r8, [rbx + 3 + rax + 2]  # inner start offset
    push r8                      # [rsp] = inner_off, [rsp+8] = inverted
    lea rdi, [r12 + rbx + 3]
    mov rsi, rax
    call trim_ws
    push rax                     # [rsp+8] = sec_ptr (after next push)
    push rdx                     # [rsp+0] = sec_len
    # Find matching {{/sec}} starting from inner_off
    mov r8, [rsp + 16]
    lea rdi, [r12 + r8]
    mov rsi, r13
    sub rsi, r8
    mov rdx, [rsp + 8]
    mov rcx, [rsp + 0]
    call find_section_end
    cmp rax, -1
    je .Ltr_sec_unclosed
    # rax = inner_len, rdx = end_off relative to inner_off
    mov r8, [rsp + 16]
    add rdx, r8                  # new rbx after {{/sec}}
    push rdx                     # [rsp+0] = next_rbx
    push rax                     # [rsp+8] = inner_len -> wait: push order:
    # Stack right now:
    # [rsp+0]  = inner_len
    # [rsp+8]  = next_rbx
    # [rsp+16] = sec_len
    # [rsp+24] = sec_ptr
    # [rsp+32] = inner_off
    # [rsp+40] = inverted

    # Try custom section callback first if present
    mov rax, [r14 + TCTX_SEC_CB]
    test rax, rax
    jz .Ltr_sec_fallback
    mov rdi, [rsp + 24]          # sec_ptr
    mov rsi, [rsp + 16]          # sec_len
    mov r8,  [rsp + 32]
    lea rdx, [r12 + r8]          # inner_ptr
    mov rcx, [rsp + 0]           # inner_len
    mov r8,  [rsp + 40]          # inverted
    mov r9,  r15                 # out_sb
    sub rsp, 16
    mov r10, [r14 + TCTX_USER_PTR]
    mov [rsp], r10               # 7th arg on stack
    call rax
    add rsp, 16
    test eax, eax
    jnz .Ltr_sec_done

.Ltr_sec_fallback:
    # Check variable in ctx->vars
    mov rdi, r14
    mov rsi, [rsp + 24]
    mov rdx, [rsp + 16]
    call tpl_lookup_var
    # truthy if rax != 0 && rdx != 0
    xor ecx, ecx
    test rax, rax
    jz .Ltr_sf_eval
    test rdx, rdx
    jz .Ltr_sf_eval
    mov ecx, 1
.Ltr_sf_eval:
    xor rcx, [rsp + 40]          # flip if inverted
    test ecx, ecx
    jz .Ltr_sec_done
    inc qword ptr [r14 + TCTX_DEPTH]
    mov r8, [rsp + 32]
    lea rdi, [r12 + r8]
    mov rsi, [rsp + 0]
    mov rdx, r14
    mov rcx, r15
    call tpl_render
    dec qword ptr [r14 + TCTX_DEPTH]

.Ltr_sec_done:
    mov rbx, [rsp + 8]           # next_rbx
    add rsp, 48
    jmp .Ltr_loop

.Ltr_sec_unclosed:
    add rsp, 32
    jmp .Ltr_tail
.Ltr_sec_eof:
    add rsp, 8
    jmp .Ltr_tail

.Ltr_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
