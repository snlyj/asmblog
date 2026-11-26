.include "defs.inc"

# Pure x86-64 Front-Matter & Streaming Markdown -> HTML Parser
# Supports: headings (#..######), fenced code blocks (```), blockquotes (>),
# unordered/ordered lists (- /* / 1.), horizontal rules (---), paragraphs,
# inline code (`...`), bold (**...**), italic (*...*), links [t](u), images ![a](u)
# with strict HTML escaping and URL scheme sanitization (blocks javascript: XSS).

.section .rodata
fm_delim:       .ascii "---"
fm_k_title:     .ascii "title"
fm_k_slug:      .ascii "slug"
fm_k_date:      .ascii "date"
fm_k_summary:   .ascii "summary"
fm_k_tags:      .ascii "tags"
fm_k_draft:     .ascii "draft"
fm_k_pinned:    .ascii "pinned"
fm_k_cover:     .ascii "cover"
fm_k_category:  .ascii "category"
fm_v_true:      .ascii "true"
fm_v_one:       .ascii "1"

tag_p_open:     .ascii "<p>"
tag_p_close:    .ascii "</p>\n"
tag_ul_open:    .ascii "<ul>\n"
tag_ul_close:   .ascii "</ul>\n"
tag_ol_open:    .ascii "<ol>\n"
tag_ol_close:   .ascii "</ol>\n"
tag_li_open:    .ascii "<li>"
tag_li_close:   .ascii "</li>\n"
tag_bq_open:    .ascii "<blockquote><p>"
tag_bq_close:   .ascii "</p></blockquote>\n"
tag_pre_open:   .ascii "<pre><code"
tag_pre_cls:    .ascii " class=\"lang-"
tag_pre_end:    .ascii "\">"
tag_pre_gt:     .ascii ">"
tag_pre_close:  .ascii "</code></pre>\n"
tag_hr:         .ascii "<hr>\n"
tag_h_open:     .ascii "<h"
tag_h_id:       .ascii " id=\"h-"
tag_h_mid:      .ascii "\">"
tag_h_close1:   .ascii "</h"
tag_h_close2:   .ascii ">\n"
tag_code_o:     .ascii "<code>"
tag_code_c:     .ascii "</code>"
tag_str_o:      .ascii "<strong>"
tag_str_c:      .ascii "</strong>"
tag_em_o:       .ascii "<em>"
tag_em_c:       .ascii "</em>"
tag_a_o:        .ascii "<a href=\""
tag_a_m:        .ascii "\">"
tag_a_c:        .ascii "</a>"
tag_img_o:      .ascii "<img src=\""
tag_img_m:      .ascii "\" alt=\""
tag_img_c:      .ascii "\" loading=\"lazy\">"
tag_vid_o:      .ascii "<video class=\"prose-video\" src=\""
.equ tag_vid_o_len, . - tag_vid_o
tag_vid_m:      .ascii "\" title=\""
.equ tag_vid_m_len, . - tag_vid_m
tag_vid_c:      .ascii "\" controls playsinline preload=\"metadata\"></video>"
.equ tag_vid_c_len, . - tag_vid_c

vext_mp4:       .ascii ".mp4"
vext_m4v:       .ascii ".m4v"
vext_webm:      .ascii ".webm"
vext_mov:       .ascii ".mov"
vext_ogg:       .ascii ".ogg"
vext_ogv:       .ascii ".ogv"

sch_http:       .ascii "http://"
sch_https:      .ascii "https://"

.section .text

# strip_quotes(rdi=ptr, rsi=len) -> rax=ptr, rdx=len
strip_quotes:
    mov rax, rdi
    mov rdx, rsi
    cmp rdx, 2
    jb .Lsq_done
    mov cl, [rax]
    cmp cl, '"'
    je .Lsq_chk
    cmp cl, 39
    jne .Lsq_done
.Lsq_chk:
    cmp byte ptr [rax + rdx - 1], cl
    jne .Lsq_done
    inc rax
    sub rdx, 2
.Lsq_done:
    ret

# parse_tags_list(rdi=val_ptr, rsi=val_len, rdx=&post)
# Parses "asm, linux, http" or "[asm, linux]" into post->tag_ptrs/lens
parse_tags_list:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx          # &post

    # strip optional [ ]
    cmp r13, 2
    jb .Lpt_go
    cmp byte ptr [r12], '['
    jne .Lpt_go
    cmp byte ptr [r12 + r13 - 1], ']'
    jne .Lpt_go
    inc r12
    sub r13, 2
.Lpt_go:
    xor rbx, rbx          # offset
    xor r15d, r15d        # count
.Lpt_loop:
    cmp rbx, r13
    jae .Lpt_done
    cmp r15d, MAX_POST_TAGS
    jae .Lpt_done
    lea rdi, [r12 + rbx]
    mov rsi, r13
    sub rsi, rbx
    mov edx, ','
    call xmemchr
    cmp rax, -1
    jne .Lpt_got
    mov rax, r13
    sub rax, rbx
.Lpt_got:
    lea r8, [rbx + rax + 1]
    push r8
    lea rdi, [r12 + rbx]
    mov rsi, rax
    call trim_ws
    mov rdi, rax
    mov rsi, rdx
    call strip_quotes
    test rdx, rdx
    jz .Lpt_next
    push rdx
    mov rdi, rax
    mov rsi, rdx
    call arena_dup
    pop rdx
    test rax, rax
    jz .Lpt_next
    mov [r14 + POST_TAG_PTRS + r15*8], rax
    mov [r14 + POST_TAG_LENS + r15*8], rdx
    inc r15
.Lpt_next:
    pop rbx
    jmp .Lpt_loop
.Lpt_done:
    mov [r14 + POST_TAG_COUNT], r15
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# parse_frontmatter(rdi=raw_ptr, rsi=raw_len, rdx=&post) -> rax=body_ptr, rdx=body_len
.globl parse_frontmatter
parse_frontmatter:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi          # raw
    mov r13, rsi          # total len
    mov r14, rdx          # &post

    # Check starts with "---\n" or "---\r\n"
    cmp r13, 4
    jb .Lpf_none
    cmp byte ptr [r12 + 0], '-'
    jne .Lpf_none
    cmp byte ptr [r12 + 1], '-'
    jne .Lpf_none
    cmp byte ptr [r12 + 2], '-'
    jne .Lpf_none
    cmp byte ptr [r12 + 3], 10
    je .Lpf_s4
    cmp r13, 5
    jb .Lpf_none
    cmp byte ptr [r12 + 3], 13
    jne .Lpf_none
    cmp byte ptr [r12 + 4], 10
    jne .Lpf_none
    mov rbx, 5
    jmp .Lpf_loop
.Lpf_s4:
    mov rbx, 4

.Lpf_loop:
    cmp rbx, r13
    jae .Lpf_none         # unclosed front-matter -> treat whole file as body
    lea rdi, [r12 + rbx]
    mov rsi, r13
    sub rsi, rbx
    mov edx, 10
    call xmemchr
    cmp rax, -1
    jne .Lpf_hasnl
    mov r15, r13
    sub r15, rbx
    mov r8, r13
    jmp .Lpf_line
.Lpf_hasnl:
    mov r15, rax
    lea r8, [rbx + rax + 1]
.Lpf_line:
    push r8               # next offset
    lea rdi, [r12 + rbx]
    mov rsi, r15
    call trim_ws
    mov rbx, rax          # trimmed line ptr
    mov r15, rdx          # trimmed line len

    # Check closing "---"
    mov rdi, rbx
    mov rsi, r15
    lea rdx, [rip + fm_delim]
    mov ecx, 3
    call xslice_eq
    test eax, eax
    jnz .Lpf_closed

    test r15, r15
    jz .Lpf_next
    # Find ':'
    mov rdi, rbx
    mov rsi, r15
    mov edx, ':'
    call xmemchr
    cmp rax, -1
    je .Lpf_next
    push rax              # colon off
    mov rdi, rbx
    mov rsi, rax
    call trim_ws
    pop rcx
    push rax              # [rsp+24] kptr
    push rdx              # [rsp+16] klen
    lea rdi, [rbx + rcx + 1]
    mov rsi, r15
    sub rsi, rcx
    dec rsi
    call trim_ws
    mov rdi, rax
    mov rsi, rdx
    call strip_quotes
    push rax              # [rsp+8] vptr
    push rdx              # [rsp+0] vlen

    # title
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 16]
    lea rdx, [rip + fm_k_title]
    mov ecx, 5
    call xslice_eq_ci
    test eax, eax
    jz .Lpf_k_slug
    mov rdi, [rsp + 8]
    mov rsi, [rsp + 0]
    call arena_dup
    mov [r14 + POST_TITLE_PTR], rax
    mov rax, [rsp + 0]
    mov [r14 + POST_TITLE_LEN], rax
    jmp .Lpf_kv_done

.Lpf_k_slug:
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 16]
    lea rdx, [rip + fm_k_slug]
    mov ecx, 4
    call xslice_eq_ci
    test eax, eax
    jz .Lpf_k_date
    mov rdi, [rsp + 8]
    mov rsi, [rsp + 0]
    call is_safe_slug
    test eax, eax
    jz .Lpf_kv_done
    mov rdi, [rsp + 8]
    mov rsi, [rsp + 0]
    call arena_dup
    mov [r14 + POST_SLUG_PTR], rax
    mov rax, [rsp + 0]
    mov [r14 + POST_SLUG_LEN], rax
    jmp .Lpf_kv_done

.Lpf_k_date:
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 16]
    lea rdx, [rip + fm_k_date]
    mov ecx, 4
    call xslice_eq_ci
    test eax, eax
    jz .Lpf_k_sum
    mov rdi, [rsp + 8]
    mov rsi, [rsp + 0]
    call arena_dup
    mov [r14 + POST_DATE_PTR], rax
    mov rax, [rsp + 0]
    mov [r14 + POST_DATE_LEN], rax
    jmp .Lpf_kv_done

.Lpf_k_sum:
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 16]
    lea rdx, [rip + fm_k_summary]
    mov ecx, 7
    call xslice_eq_ci
    test eax, eax
    jz .Lpf_k_tags
    mov rdi, [rsp + 8]
    mov rsi, [rsp + 0]
    call arena_dup
    mov [r14 + POST_SUMMARY_PTR], rax
    mov rax, [rsp + 0]
    mov [r14 + POST_SUMMARY_LEN], rax
    jmp .Lpf_kv_done

.Lpf_k_tags:
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 16]
    lea rdx, [rip + fm_k_tags]
    mov ecx, 4
    call xslice_eq_ci
    test eax, eax
    jz .Lpf_k_draft
    mov rdi, [rsp + 8]
    mov rsi, [rsp + 0]
    call arena_dup
    mov [r14 + POST_TAGS_RAW_PTR], rax
    mov rax, [rsp + 0]
    mov [r14 + POST_TAGS_RAW_LEN], rax
    mov rdi, [rsp + 8]
    mov rsi, [rsp + 0]
    mov rdx, r14
    call parse_tags_list
    jmp .Lpf_kv_done

.Lpf_k_draft:
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 16]
    lea rdx, [rip + fm_k_draft]
    mov ecx, 5
    call xslice_eq_ci
    test eax, eax
    jz .Lpf_k_cover
    mov rdi, [rsp + 8]
    mov rsi, [rsp + 0]
    lea rdx, [rip + fm_v_true]
    mov ecx, 4
    call xslice_eq_ci
    test eax, eax
    jnz .Lpf_set_draft
    mov rdi, [rsp + 8]
    mov rsi, [rsp + 0]
    lea rdx, [rip + fm_v_one]
    mov ecx, 1
    call xslice_eq
    test eax, eax
    jz .Lpf_kv_done
.Lpf_set_draft:
    mov qword ptr [r14 + POST_DRAFT], 1
    jmp .Lpf_kv_done

.Lpf_k_cover:
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 16]
    lea rdx, [rip + fm_k_cover]
    mov ecx, 5
    call xslice_eq_ci
    test eax, eax
    jz .Lpf_k_cat
    mov rdi, [rsp + 8]
    mov rsi, [rsp + 0]
    call is_safe_url
    test eax, eax
    jz .Lpf_kv_done
    mov rdi, [rsp + 8]
    mov rsi, [rsp + 0]
    call arena_dup
    mov [r14 + POST_COVER_PTR], rax
    mov rax, [rsp + 0]
    mov [r14 + POST_COVER_LEN], rax
    jmp .Lpf_kv_done

.Lpf_k_cat:
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 16]
    lea rdx, [rip + fm_k_category]
    mov ecx, 8
    call xslice_eq_ci
    test eax, eax
    jz .Lpf_k_pinned
    cmp qword ptr [rsp + 0], 0
    je .Lpf_kv_done
    mov rdi, [rsp + 8]
    mov rsi, [rsp + 0]
    call arena_dup
    mov [r14 + POST_CAT_PTR], rax
    mov rax, [rsp + 0]
    mov [r14 + POST_CAT_LEN], rax
    jmp .Lpf_kv_done

.Lpf_k_pinned:
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 16]
    lea rdx, [rip + fm_k_pinned]
    mov ecx, 6
    call xslice_eq_ci
    test eax, eax
    jz .Lpf_kv_done
    mov rdi, [rsp + 8]
    mov rsi, [rsp + 0]
    lea rdx, [rip + fm_v_true]
    mov ecx, 4
    call xslice_eq_ci
    test eax, eax
    jnz .Lpf_set_pin
    mov rdi, [rsp + 8]
    mov rsi, [rsp + 0]
    lea rdx, [rip + fm_v_one]
    mov ecx, 1
    call xslice_eq
    test eax, eax
    jz .Lpf_kv_done
.Lpf_set_pin:
    mov qword ptr [r14 + POST_PINNED], 1

.Lpf_kv_done:
    add rsp, 32
.Lpf_next:
    pop rbx
    jmp .Lpf_loop

.Lpf_closed:
    pop rbx               # body starts at r12 + rbx
    lea rax, [r12 + rbx]
    mov rdx, r13
    sub rdx, rbx
    jmp .Lpf_ret

.Lpf_none:
    mov rax, r12
    mov rdx, r13
.Lpf_ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# --- URL sanitizer for Markdown links/images ---
# is_safe_url(rdi=ptr, rsi=len) -> rax=1 if starts with http://, https://, /, or #
.globl is_safe_url
is_safe_url:
    test rsi, rsi
    jz .Lsu_no
    mov al, [rdi]
    cmp al, '/'
    je .Lsu_yes
    cmp al, '#'
    je .Lsu_yes
    cmp rsi, 7
    jb .Lsu_no
    push rdi
    push rsi
    mov rsi, 7
    lea rdx, [rip + sch_http]
    mov ecx, 7
    call xslice_eq_ci
    pop rsi
    pop rdi
    test eax, eax
    jnz .Lsu_yes
    cmp rsi, 8
    jb .Lsu_no
    mov rsi, 8
    lea rdx, [rip + sch_https]
    mov ecx, 8
    call xslice_eq_ci
    ret
.Lsu_yes:
    mov eax, 1
    ret
.Lsu_no:
    xor eax, eax
    ret

# is_video_url(rdi=url_ptr, rsi=url_len) -> eax=1 if path before ?/# ends with video ext
is_video_url:
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi

    mov rdi, r12; mov rsi, r13; mov edx, '?'; call xmemchr
    cmp rax, -1
    je .Livu_hash
    mov r13, rax
.Livu_hash:
    mov rdi, r12; mov rsi, r13; mov edx, '#'; call xmemchr
    cmp rax, -1
    je .Livu_chk
    mov r13, rax
.Livu_chk:
    cmp r13, 4
    jb .Livu_no
    lea rdi, [r12 + r13 - 4]; mov esi, 4; lea rdx, [rip + vext_mp4]; mov ecx, 4; call xslice_eq_ci
    test eax, eax; jnz .Livu_yes
    lea rdi, [r12 + r13 - 4]; mov esi, 4; lea rdx, [rip + vext_m4v]; mov ecx, 4; call xslice_eq_ci
    test eax, eax; jnz .Livu_yes
    lea rdi, [r12 + r13 - 4]; mov esi, 4; lea rdx, [rip + vext_mov]; mov ecx, 4; call xslice_eq_ci
    test eax, eax; jnz .Livu_yes
    lea rdi, [r12 + r13 - 4]; mov esi, 4; lea rdx, [rip + vext_ogg]; mov ecx, 4; call xslice_eq_ci
    test eax, eax; jnz .Livu_yes
    lea rdi, [r12 + r13 - 4]; mov esi, 4; lea rdx, [rip + vext_ogv]; mov ecx, 4; call xslice_eq_ci
    test eax, eax; jnz .Livu_yes
    cmp r13, 5
    jb .Livu_no
    lea rdi, [r12 + r13 - 5]; mov esi, 5; lea rdx, [rip + vext_webm]; mov ecx, 5; call xslice_eq_ci
    test eax, eax; jnz .Livu_yes
.Livu_no:
    xor eax, eax
    jmp .Livu_ret
.Livu_yes:
    mov eax, 1
.Livu_ret:
    pop r13
    pop r12
    ret

# --- Inline Markdown Renderer ---
# md_render_inline(rdi=ptr, rsi=len, rdx=&sb)
.globl md_render_inline
md_render_inline:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi          # ptr
    mov r13, rsi          # len
    mov r14, rdx          # &sb
    xor rbx, rbx          # i

.Lmi_loop:
    cmp rbx, r13
    jae .Lmi_done
    movzx eax, byte ptr [r12 + rbx]

    # 1) Inline code `...`
    cmp al, '`'
    jne .Lmi_chk_bold
    lea rdi, [r12 + rbx + 1]
    mov rsi, r13
    sub rsi, rbx
    dec rsi
    mov edx, '`'
    call xmemchr
    cmp rax, -1
    je .Lmi_plain
    push rax
    mov rdi, r14
    lea rsi, [rip + tag_code_o]
    mov edx, 6
    call sb_mem
    mov rdi, r14
    lea rsi, [r12 + rbx + 1]
    mov rdx, [rsp]
    call sb_esc_html
    mov rdi, r14
    lea rsi, [rip + tag_code_c]
    mov edx, 7
    call sb_mem
    pop rax
    add rbx, rax
    add rbx, 2
    jmp .Lmi_loop

.Lmi_chk_bold:
    # 2) Bold **...**
    cmp al, '*'
    jne .Lmi_chk_img
    lea rcx, [rbx + 3]
    cmp rcx, r13
    jae .Lmi_chk_em
    cmp byte ptr [r12 + rbx + 1], '*'
    jne .Lmi_chk_em
    # Search for closing **
    lea r15, [rbx + 2]
.Lmi_bscan:
    lea rcx, [r15 + 1]
    cmp rcx, r13
    jae .Lmi_chk_em
    cmp byte ptr [r12 + r15], '*'
    jne .Lmi_bnext
    cmp byte ptr [r12 + r15 + 1], '*'
    je .Lmi_bgot
.Lmi_bnext:
    inc r15
    jmp .Lmi_bscan
.Lmi_bgot:
    mov rdi, r14
    lea rsi, [rip + tag_str_o]
    mov edx, 8
    call sb_mem
    lea rdi, [r12 + rbx + 2]
    mov rsi, r15
    sub rsi, rbx
    sub rsi, 2
    mov rdx, r14
    call md_render_inline
    mov rdi, r14
    lea rsi, [rip + tag_str_c]
    mov edx, 9
    call sb_mem
    lea rbx, [r15 + 2]
    jmp .Lmi_loop

.Lmi_chk_em:
    # 3) Italic *...*
    lea rdi, [r12 + rbx + 1]
    mov rsi, r13
    sub rsi, rbx
    dec rsi
    mov edx, '*'
    call xmemchr
    cmp rax, -1
    je .Lmi_plain
    test rax, rax
    jz .Lmi_plain
    push rax
    mov rdi, r14
    lea rsi, [rip + tag_em_o]
    mov edx, 4
    call sb_mem
    mov rdi, r14
    lea rsi, [r12 + rbx + 1]
    mov rdx, [rsp]
    call sb_esc_html
    mov rdi, r14
    lea rsi, [rip + tag_em_c]
    mov edx, 5
    call sb_mem
    pop rax
    add rbx, rax
    add rbx, 2
    jmp .Lmi_loop

.Lmi_chk_img:
    # 4) Image ![alt](url)
    cmp al, '!'
    jne .Lmi_chk_link
    lea rcx, [rbx + 1]
    cmp rcx, r13
    jae .Lmi_plain
    cmp byte ptr [r12 + rcx], '['
    jne .Lmi_plain
    # find ']'
    lea rdi, [r12 + rbx + 2]
    mov rsi, r13
    sub rsi, rbx
    sub rsi, 2
    mov edx, ']'
    call xmemchr
    cmp rax, -1
    je .Lmi_plain
    lea r15, [rbx + 2 + rax]   # pos of ']'
    lea rcx, [r15 + 1]
    cmp rcx, r13
    jae .Lmi_plain
    cmp byte ptr [r12 + rcx], '('
    jne .Lmi_plain
    # find ')'
    lea rdi, [r12 + r15 + 2]
    mov rsi, r13
    sub rsi, r15
    sub rsi, 2
    mov edx, ')'
    call xmemchr
    cmp rax, -1
    je .Lmi_plain
    # alt = (r12+rbx+2, r15-rbx-2), url = (r12+r15+2, rax)
    push rax              # url_len
    lea rdi, [r12 + r15 + 2]
    mov rsi, rax
    call is_safe_url
    pop rcx               # url_len
    test eax, eax
    jz .Lmi_plain
    push rcx
    lea rdi, [r12 + r15 + 2]
    mov rsi, rcx
    call is_video_url
    test eax, eax
    jnz .Lmi_emit_video

    mov rdi, r14
    lea rsi, [rip + tag_img_o]
    mov edx, 10
    call sb_mem
    mov rdi, r14
    lea rsi, [r12 + r15 + 2]
    mov rdx, [rsp]
    call sb_esc_html
    mov rdi, r14
    lea rsi, [rip + tag_img_m]
    mov edx, 7
    call sb_mem
    mov rdi, r14
    lea rsi, [r12 + rbx + 2]
    mov rdx, r15
    sub rdx, rbx
    sub rdx, 2
    call sb_esc_html
    mov rdi, r14
    lea rsi, [rip + tag_img_c]
    mov edx, 17
    call sb_mem
    pop rcx
    lea rbx, [r15 + 2 + rcx + 1]
    jmp .Lmi_loop

.Lmi_emit_video:
    mov rdi, r14
    lea rsi, [rip + tag_vid_o]
    mov edx, tag_vid_o_len
    call sb_mem
    mov rdi, r14
    lea rsi, [r12 + r15 + 2]
    mov rdx, [rsp]
    call sb_esc_html
    mov rdi, r14
    lea rsi, [rip + tag_vid_m]
    mov edx, tag_vid_m_len
    call sb_mem
    mov rdi, r14
    lea rsi, [r12 + rbx + 2]
    mov rdx, r15
    sub rdx, rbx
    sub rdx, 2
    call sb_esc_html
    mov rdi, r14
    lea rsi, [rip + tag_vid_c]
    mov edx, tag_vid_c_len
    call sb_mem
    pop rcx
    lea rbx, [r15 + 2 + rcx + 1]
    jmp .Lmi_loop

.Lmi_chk_link:
    # 5) Link [text](url)
    cmp al, '['
    jne .Lmi_plain
    lea rdi, [r12 + rbx + 1]
    mov rsi, r13
    sub rsi, rbx
    dec rsi
    mov edx, ']'
    call xmemchr
    cmp rax, -1
    je .Lmi_plain
    lea r15, [rbx + 1 + rax]   # pos of ']'
    lea rcx, [r15 + 1]
    cmp rcx, r13
    jae .Lmi_plain
    cmp byte ptr [r12 + rcx], '('
    jne .Lmi_plain
    lea rdi, [r12 + r15 + 2]
    mov rsi, r13
    sub rsi, r15
    sub rsi, 2
    mov edx, ')'
    call xmemchr
    cmp rax, -1
    je .Lmi_plain
    # text = (r12+rbx+1, r15-rbx-1), url = (r12+r15+2, rax)
    push rax
    lea rdi, [r12 + r15 + 2]
    mov rsi, rax
    call is_safe_url
    pop rcx
    test eax, eax
    jz .Lmi_unsafe_link
    push rcx
    mov rdi, r14
    lea rsi, [rip + tag_a_o]
    mov edx, 9
    call sb_mem
    mov rdi, r14
    lea rsi, [r12 + r15 + 2]
    mov rdx, [rsp]
    call sb_esc_html
    mov rdi, r14
    lea rsi, [rip + tag_a_m]
    mov edx, 2
    call sb_mem
    mov rdi, r14
    lea rsi, [r12 + rbx + 1]
    mov rdx, r15
    sub rdx, rbx
    sub rdx, 1
    call sb_esc_html
    mov rdi, r14
    lea rsi, [rip + tag_a_c]
    mov edx, 4
    call sb_mem
    pop rcx
    lea rbx, [r15 + 2 + rcx + 1]
    jmp .Lmi_loop

.Lmi_unsafe_link:
    # Unsafe URL scheme (e.g. javascript:): emit only escaped link text, strip URL!
    push rcx
    mov rdi, r14
    lea rsi, [r12 + rbx + 1]
    mov rdx, r15
    sub rdx, rbx
    sub rdx, 1
    call sb_esc_html
    pop rcx
    lea rbx, [r15 + 2 + rcx + 1]
    jmp .Lmi_loop

.Lmi_plain:
    mov rdi, r14
    lea rsi, [r12 + rbx]
    mov edx, 1
    call sb_esc_html
    inc rbx
    jmp .Lmi_loop

.Lmi_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# --- Block-level Markdown -> HTML ---
# States: 0=NONE, 1=PARA, 2=UL, 3=OL, 4=BQ, 5=CODE

# close_block(rdi=&state_var, rsi=&sb)
close_block:
    push r12
    mov r12, rdi
    mov rax, [r12]
    mov qword ptr [r12], 0
    cmp rax, 1
    je .Lcb_p
    cmp rax, 2
    je .Lcb_ul
    cmp rax, 3
    je .Lcb_ol
    cmp rax, 4
    je .Lcb_bq
    cmp rax, 5
    je .Lcb_code
    pop r12
    ret
.Lcb_p:
    mov rdi, rsi; lea rsi, [rip + tag_p_close];   mov edx, 5;  call sb_mem; pop r12; ret
.Lcb_ul:
    mov rdi, rsi; lea rsi, [rip + tag_ul_close];  mov edx, 6;  call sb_mem; pop r12; ret
.Lcb_ol:
    mov rdi, rsi; lea rsi, [rip + tag_ol_close];  mov edx, 6;  call sb_mem; pop r12; ret
.Lcb_bq:
    mov rdi, rsi; lea rsi, [rip + tag_bq_close];  mov edx, 18; call sb_mem; pop r12; ret
.Lcb_code:
    mov rdi, rsi; lea rsi, [rip + tag_pre_close]; mov edx, 14; call sb_mem; pop r12; ret

# md_to_html(rdi=md_ptr, rsi=md_len, rdx=&out_sb)
.globl md_to_html
md_to_html:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 32           # [rsp+0]=state, [rsp+8]=heading_seq, [rsp+16]=cur_off

    mov r12, rdi          # md_ptr
    mov r13, rsi          # md_len
    mov r14, rdx          # &out_sb
    mov qword ptr [rsp + 0], 0
    mov qword ptr [rsp + 8], 0
    mov qword ptr [rsp + 16], 0

.Lmd_line_loop:
    mov rbx, [rsp + 16]
    cmp rbx, r13
    jae .Lmd_eof

    # Extract line [r12+rbx .. nl)
    lea rdi, [r12 + rbx]
    mov rsi, r13
    sub rsi, rbx
    mov edx, 10
    call xmemchr
    cmp rax, -1
    jne .Lmd_hasnl
    mov r15, r13
    sub r15, rbx
    mov [rsp + 16], r13
    jmp .Lmd_strip_cr
.Lmd_hasnl:
    mov r15, rax
    lea rcx, [rbx + rax + 1]
    mov [rsp + 16], rcx
.Lmd_strip_cr:
    lea rbx, [r12 + rbx]  # rbx = line_ptr, r15 = line_len
    test r15, r15
    jz .Lmd_cr_done
    cmp byte ptr [rbx + r15 - 1], 13
    jne .Lmd_cr_done
    dec r15
.Lmd_cr_done:

    # If in fenced code block (state == 5)
    cmp qword ptr [rsp + 0], 5
    jne .Lmd_not_code
    cmp r15, 3
    jb .Lmd_code_emit
    cmp byte ptr [rbx + 0], '`'
    jne .Lmd_code_emit
    cmp byte ptr [rbx + 1], '`'
    jne .Lmd_code_emit
    cmp byte ptr [rbx + 2], '`'
    jne .Lmd_code_emit
    # Closing fence!
    lea rdi, [rsp + 0]
    mov rsi, r14
    call close_block
    jmp .Lmd_line_loop
.Lmd_code_emit:
    mov rdi, r14
    mov rsi, rbx
    mov rdx, r15
    call sb_esc_html
    mov rdi, r14
    mov esi, 10
    call sb_byte
    jmp .Lmd_line_loop

.Lmd_not_code:
    # Check opening code fence ```
    cmp r15, 3
    jb .Lmd_chk_blank
    cmp byte ptr [rbx + 0], '`'
    jne .Lmd_chk_blank
    cmp byte ptr [rbx + 1], '`'
    jne .Lmd_chk_blank
    cmp byte ptr [rbx + 2], '`'
    jne .Lmd_chk_blank
    lea rdi, [rsp + 0]
    mov rsi, r14
    call close_block
    mov qword ptr [rsp + 0], 5
    mov rdi, r14
    lea rsi, [rip + tag_pre_open]
    mov edx, 10
    call sb_mem
    # optional language name after ```
    lea rdi, [rbx + 3]
    mov rsi, r15
    sub rsi, 3
    call trim_ws
    test rdx, rdx
    jz .Lmd_code_nolang
    push rax
    push rdx
    mov rdi, r14
    lea rsi, [rip + tag_pre_cls]
    mov edx, 13
    call sb_mem
    pop rdx
    pop rsi
    mov rdi, r14
    call sb_esc_html
    mov rdi, r14
    lea rsi, [rip + tag_pre_end]
    mov edx, 2
    call sb_mem
    jmp .Lmd_line_loop
.Lmd_code_nolang:
    mov rdi, r14
    lea rsi, [rip + tag_pre_gt]
    mov edx, 1
    call sb_mem
    jmp .Lmd_line_loop

.Lmd_chk_blank:
    mov rdi, rbx
    mov rsi, r15
    call trim_ws
    test rdx, rdx
    jnz .Lmd_chk_hr
    # blank line closes active block
    lea rdi, [rsp + 0]
    mov rsi, r14
    call close_block
    jmp .Lmd_line_loop

.Lmd_chk_hr:
    # Horizontal rule: --- or ***
    cmp rdx, 3
    jne .Lmd_chk_heading
    mov cl, [rax]
    cmp cl, '-'
    je .Lmd_hr_chk
    cmp cl, '*'
    jne .Lmd_chk_heading
.Lmd_hr_chk:
    cmp byte ptr [rax + 1], cl
    jne .Lmd_chk_heading
    cmp byte ptr [rax + 2], cl
    jne .Lmd_chk_heading
    lea rdi, [rsp + 0]
    mov rsi, r14
    call close_block
    mov rdi, r14
    lea rsi, [rip + tag_hr]
    mov edx, 5
    call sb_mem
    jmp .Lmd_line_loop

.Lmd_chk_heading:
    # ATX headings: 1..6 '#' followed by ' '
    cmp byte ptr [rbx], '#'
    jne .Lmd_chk_bq
    xor ecx, ecx
.Lmd_hcnt:
    cmp rcx, r15
    jae .Lmd_chk_bq
    cmp ecx, 6
    jae .Lmd_hsp
    cmp byte ptr [rbx + rcx], '#'
    jne .Lmd_hsp
    inc ecx
    jmp .Lmd_hcnt
.Lmd_hsp:
    cmp rcx, r15
    jae .Lmd_chk_bq
    cmp byte ptr [rbx + rcx], ' '
    jne .Lmd_chk_bq
    # Valid heading level rcx (1..6)
    push rcx
    lea rdi, [rsp + 8]    # &state
    mov rsi, r14
    call close_block
    inc qword ptr [rsp + 16]  # heading_seq
    mov rdi, r14
    lea rsi, [rip + tag_h_open]
    mov edx, 2
    call sb_mem
    mov rax, [rsp]
    add al, '0'
    mov rdi, r14
    mov esi, eax
    call sb_byte
    mov rdi, r14
    lea rsi, [rip + tag_h_id]
    mov edx, 7
    call sb_mem
    mov rdi, r14
    mov rsi, [rsp + 16]
    call sb_uint
    mov rdi, r14
    lea rsi, [rip + tag_h_mid]
    mov edx, 2
    call sb_mem
    pop rcx
    push rcx
    lea rdi, [rbx + rcx + 1]
    mov rsi, r15
    sub rsi, rcx
    dec rsi
    mov rdx, r14
    call md_render_inline
    mov rdi, r14
    lea rsi, [rip + tag_h_close1]
    mov edx, 3
    call sb_mem
    pop rcx
    add cl, '0'
    mov rdi, r14
    mov esi, ecx
    call sb_byte
    mov rdi, r14
    lea rsi, [rip + tag_h_close2]
    mov edx, 2
    call sb_mem
    jmp .Lmd_line_loop

.Lmd_chk_bq:
    cmp byte ptr [rbx], '>'
    jne .Lmd_chk_ul
    cmp qword ptr [rsp + 0], 4
    je .Lmd_bq_cont
    lea rdi, [rsp + 0]
    mov rsi, r14
    call close_block
    mov qword ptr [rsp + 0], 4
    mov rdi, r14
    lea rsi, [rip + tag_bq_open]
    mov edx, 15
    call sb_mem
    jmp .Lmd_bq_text
.Lmd_bq_cont:
    mov rdi, r14
    mov esi, ' '
    call sb_byte
.Lmd_bq_text:
    lea rdi, [rbx + 1]
    mov rsi, r15
    dec rsi
    call trim_ws
    mov rdi, rax
    mov rsi, rdx
    mov rdx, r14
    call md_render_inline
    jmp .Lmd_line_loop

.Lmd_chk_ul:
    xor ecx, ecx
.Lmd_ul_lead:
    cmp rcx, r15
    jae .Lmd_chk_ol
    mov al, [rbx + rcx]
    cmp al, ' '
    je .Lmd_ul_ladv
    cmp al, 9
    jne .Lmd_ul_mark
.Lmd_ul_ladv:
    inc rcx
    jmp .Lmd_ul_lead
.Lmd_ul_mark:
    lea r8, [rcx + 2]
    cmp r8, r15
    ja .Lmd_chk_ol
    cmp al, '-'
    je .Lmd_ul_sp
    cmp al, '*'
    jne .Lmd_chk_ol
.Lmd_ul_sp:
    cmp byte ptr [rbx + rcx + 1], ' '
    jne .Lmd_chk_ol
    push rcx
    cmp qword ptr [rsp + 8], 2
    je .Lmd_ul_item
    lea rdi, [rsp + 8]
    mov rsi, r14
    call close_block
    mov qword ptr [rsp + 8], 2
    mov rdi, r14
    lea rsi, [rip + tag_ul_open]
    mov edx, 5
    call sb_mem
.Lmd_ul_item:
    mov rdi, r14
    lea rsi, [rip + tag_li_open]
    mov edx, 4
    call sb_mem
    pop rcx
    lea rdi, [rbx + rcx + 2]
    mov rsi, r15
    sub rsi, rcx
    sub rsi, 2
    mov rdx, r14
    call md_render_inline
    mov rdi, r14
    lea rsi, [rip + tag_li_close]
    mov edx, 6
    call sb_mem
    jmp .Lmd_line_loop

.Lmd_chk_ol:
    # Digits followed by ". "
    xor ecx, ecx
.Lmd_oldig:
    cmp rcx, r15
    jae .Lmd_para
    mov al, [rbx + rcx]
    cmp al, '0'
    jb .Lmd_ol_dot
    cmp al, '9'
    ja .Lmd_ol_dot
    inc rcx
    jmp .Lmd_oldig
.Lmd_ol_dot:
    test rcx, rcx
    jz .Lmd_para
    lea r8, [rcx + 2]
    cmp r8, r15
    ja .Lmd_para
    cmp byte ptr [rbx + rcx], '.'
    jne .Lmd_para
    cmp byte ptr [rbx + rcx + 1], ' '
    jne .Lmd_para
    push rcx
    cmp qword ptr [rsp + 8], 3
    je .Lmd_ol_item
    lea rdi, [rsp + 8]
    mov rsi, r14
    call close_block
    mov qword ptr [rsp + 8], 3
    mov rdi, r14
    lea rsi, [rip + tag_ol_open]
    mov edx, 5
    call sb_mem
.Lmd_ol_item:
    mov rdi, r14
    lea rsi, [rip + tag_li_open]
    mov edx, 4
    call sb_mem
    pop rcx
    lea rdi, [rbx + rcx + 2]
    mov rsi, r15
    sub rsi, rcx
    sub rsi, 2
    mov rdx, r14
    call md_render_inline
    mov rdi, r14
    lea rsi, [rip + tag_li_close]
    mov edx, 6
    call sb_mem
    jmp .Lmd_line_loop

.Lmd_para:
    cmp qword ptr [rsp + 0], 1
    je .Lmd_p_cont
    lea rdi, [rsp + 0]
    mov rsi, r14
    call close_block
    mov qword ptr [rsp + 0], 1
    mov rdi, r14
    lea rsi, [rip + tag_p_open]
    mov edx, 3
    call sb_mem
    jmp .Lmd_p_emit
.Lmd_p_cont:
    mov rdi, r14
    mov esi, ' '
    call sb_byte
.Lmd_p_emit:
    mov rdi, rbx
    mov rsi, r15
    mov rdx, r14
    call md_render_inline
    jmp .Lmd_line_loop

.Lmd_eof:
    lea rdi, [rsp + 0]
    mov rsi, r14
    call close_block
    add rsp, 32
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
