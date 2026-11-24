.include "defs.inc"

# In-memory Arena Store for Posts, Tags, and Theme Templates + Hot Reload
.section .bss
.align 8
.globl g_posts
g_posts:         .skip MAX_POSTS * POST_SIZE
.globl g_post_ptrs
g_post_ptrs:     .skip MAX_POSTS * 8
.globl g_post_count
g_post_count:    .quad 0
.globl g_pub_count
g_pub_count:     .quad 0

.globl g_tags
g_tags:          .skip MAX_TAGS * TAG_SIZE
.globl g_tag_count
g_tag_count:     .quad 0

.globl g_cats
g_cats:          .skip MAX_CATEGORIES * CAT_SIZE
.globl g_cat_count
g_cat_count:     .quad 0

.globl g_tpls
g_tpls:          .skip MAX_TEMPLATES * TPL_SIZE
.globl g_tpl_count
g_tpl_count:     .quad 0

.globl g_reload_count
g_reload_count:  .quad 0
.globl g_start_sec
g_start_sec:     .quad 0

store_dirent_buf: .skip 16384
store_file_buf:   .skip 131072
store_html_buf:   .skip 262144
store_path_buf:   .skip 512

.section .rodata
dir_posts:       .asciz "content/posts"
dir_posts_pre:   .ascii "content/posts/"
file_cats:       .asciz "content/categories.txt"
dir_themes_pre:  .ascii "themes/"
ext_md:          .ascii ".md"
ext_html_s:      .ascii ".html"
log_reloaded:    .asciz "[asmblog] store reloaded\n"

.section .text

# store_find_tpl(rdi=name_ptr, rsi=name_len) -> rax=data_ptr (0 if missing), rdx=data_len
.globl store_find_tpl
store_find_tpl:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    xor ebx, ebx
.Lsft_loop:
    cmp rbx, [rip + g_tpl_count]
    jae .Lsft_no
    imul rcx, rbx, TPL_SIZE
    lea r8, [rip + g_tpls]
    mov rdi, [r8 + rcx + TPL_NAME_PTR]
    mov rsi, [r8 + rcx + TPL_NAME_LEN]
    mov rdx, r12
    mov rcx, r13
    call xslice_eq
    test eax, eax
    jnz .Lsft_yes
    inc rbx
    jmp .Lsft_loop
.Lsft_yes:
    imul rcx, rbx, TPL_SIZE
    lea r8, [rip + g_tpls]
    mov rax, [r8 + rcx + TPL_DATA_PTR]
    mov rdx, [r8 + rcx + TPL_DATA_LEN]
    pop r13
    pop r12
    pop rbx
    ret
.Lsft_no:
    xor eax, eax
    xor edx, edx
    pop r13
    pop r12
    pop rbx
    ret

# store_find_post(rdi=slug_ptr, rsi=slug_len, rdx=include_drafts) -> rax=&post (0 if missing), rdx=sorted_index
.globl store_find_post
store_find_post:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    xor ebx, ebx
.Lsfp_loop:
    cmp rbx, [rip + g_post_count]
    jae .Lsfp_no
    lea r8, [rip + g_post_ptrs]
    mov r9, [r8 + rbx*8]
    test r14, r14
    jnz .Lsfp_cmp
    cmp qword ptr [r9 + POST_DRAFT], 0
    jne .Lsfp_next
.Lsfp_cmp:
    mov rdi, [r9 + POST_SLUG_PTR]
    mov rsi, [r9 + POST_SLUG_LEN]
    mov rdx, r12
    mov rcx, r13
    call xslice_eq
    test eax, eax
    jnz .Lsfp_yes
.Lsfp_next:
    inc rbx
    jmp .Lsfp_loop
.Lsfp_yes:
    lea r8, [rip + g_post_ptrs]
    mov rax, [r8 + rbx*8]
    mov rdx, rbx
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.Lsfp_no:
    xor eax, eax
    xor edx, edx
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# add_or_bump_tag(rdi=name_ptr, rsi=name_len)
add_or_bump_tag:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    xor ebx, ebx
.Lbt_loop:
    cmp rbx, [rip + g_tag_count]
    jae .Lbt_new
    imul rcx, rbx, TAG_SIZE
    lea r8, [rip + g_tags]
    mov rdi, [r8 + rcx + TAG_NAME_PTR]
    mov rsi, [r8 + rcx + TAG_NAME_LEN]
    mov rdx, r12
    mov rcx, r13
    call xslice_eq_ci
    test eax, eax
    jnz .Lbt_hit
    inc rbx
    jmp .Lbt_loop
.Lbt_hit:
    imul rcx, rbx, TAG_SIZE
    lea r8, [rip + g_tags]
    inc qword ptr [r8 + rcx + TAG_COUNT]
    jmp .Lbt_done
.Lbt_new:
    mov rbx, [rip + g_tag_count]
    cmp rbx, MAX_TAGS
    jae .Lbt_done
    imul rcx, rbx, TAG_SIZE
    lea r8, [rip + g_tags]
    mov [r8 + rcx + TAG_NAME_PTR], r12
    mov [r8 + rcx + TAG_NAME_LEN], r13
    mov qword ptr [r8 + rcx + TAG_COUNT], 1
    inc qword ptr [rip + g_tag_count]
.Lbt_done:
    pop r13
    pop r12
    pop rbx
    ret

# add_or_bump_cat(rdi=name_ptr, rsi=name_len, rdx=delta_0_or_1)
add_or_bump_cat:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    test r13, r13
    jz .Lbc_done
    xor ebx, ebx
.Lbc_loop:
    cmp rbx, [rip + g_cat_count]
    jae .Lbc_new
    imul rcx, rbx, CAT_SIZE
    lea r8, [rip + g_cats]
    mov rdi, [r8 + rcx + CAT_NAME_PTR]
    mov rsi, [r8 + rcx + CAT_NAME_LEN]
    mov rdx, r12
    mov rcx, r13
    call xslice_eq_ci
    test eax, eax
    jnz .Lbc_hit
    inc rbx
    jmp .Lbc_loop
.Lbc_hit:
    imul rcx, rbx, CAT_SIZE
    lea r8, [rip + g_cats]
    add [r8 + rcx + CAT_COUNT], r14
    jmp .Lbc_done
.Lbc_new:
    mov rbx, [rip + g_cat_count]
    cmp rbx, MAX_CATEGORIES
    jae .Lbc_done
    mov rdi, r12
    mov rsi, r13
    call arena_dup
    test rax, rax
    jz .Lbc_done
    mov rbx, [rip + g_cat_count]
    imul rcx, rbx, CAT_SIZE
    lea r8, [rip + g_cats]
    mov [r8 + rcx + CAT_NAME_PTR], rax
    mov [r8 + rcx + CAT_NAME_LEN], r13
    mov [r8 + rcx + CAT_COUNT], r14
    inc qword ptr [rip + g_cat_count]
.Lbc_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# load_categories_file() -> loads content/categories.txt (1 line per category)
load_categories_file:
    push rbx
    push r12
    push r13
    push r14
    lea rdi, [rip + file_cats]
    lea rsi, [rip + store_file_buf]
    mov edx, 16383
    call read_file_buf
    test rax, rax
    jle .Llcf_done
    lea r12, [rip + store_file_buf]
    mov r13, rax
    xor r14, r14
.Llcf_line:
    cmp r14, r13
    jae .Llcf_done
    lea rbx, [r12 + r14]
    mov rdi, rbx
    mov rsi, r13
    sub rsi, r14
    mov edx, 10
    call xmemchr
    cmp rax, -1
    jne .Llcf_nl
    mov rax, r13
    sub rax, r14
    mov r14, r13
    jmp .Llcf_trim
.Llcf_nl:
    add r14, rax
    inc r14
.Llcf_trim:
    mov rdi, rbx
    mov rsi, rax
    call trim_ws
    test rdx, rdx
    jz .Llcf_line
    cmp byte ptr [rax], '#'
    je .Llcf_line
    mov rdi, rax
    mov rsi, rdx
    xor edx, edx          # initial count 0
    call add_or_bump_cat
    jmp .Llcf_line
.Llcf_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# load_theme_templates() -> loads themes/<theme>/*.html into arena & g_tpls
load_theme_templates:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 48           # [rsp+0..23]=sbuf, [rsp+24]=dir_fd, [rsp+32]=dir_len

    # Build "themes/<theme>\0" into store_path_buf
    mov rdi, rsp
    lea rsi, [rip + store_path_buf]
    mov edx, 511
    call sb_init
    mov rdi, rsp
    lea rsi, [rip + dir_themes_pre]
    mov edx, 7
    call sb_mem
    mov rdi, rsp
    lea rsi, [rip + g_cfg_theme]
    mov rdx, [rip + g_cfg_theme_len]
    call sb_mem
    mov rax, [rsp + SB_LEN]
    mov [rsp + 32], rax
    mov rdi, rsp
    xor esi, esi
    call sb_byte

    mov rdi, AT_FDCWD
    lea rsi, [rip + store_path_buf]
    mov edx, O_RDONLY | O_DIRECTORY | O_CLOEXEC
    xor ecx, ecx
    call sys_openat
    test rax, rax
    js .Lltt_done
    mov [rsp + 24], rax

.Lltt_dents:
    mov rdi, [rsp + 24]
    lea rsi, [rip + store_dirent_buf]
    mov edx, 16384
    call sys_getdents64
    test rax, rax
    jle .Lltt_close
    mov r12, rax          # bytes
    xor r13, r13          # off
.Lltt_entry:
    cmp r13, r12
    jae .Lltt_dents
    lea r14, [rip + store_dirent_buf]
    add r14, r13
    movzx ebx, word ptr [r14 + 16]   # d_reclen
    add r13, rbx
    lea r15, [r14 + 19]              # d_name
    mov rdi, r15
    call xstrlen
    cmp rax, 6
    jb .Lltt_entry
    # check ends with ".html"
    push rax
    lea rdi, [r15 + rax - 5]
    mov esi, 5
    lea rdx, [rip + ext_html_s]
    mov ecx, 5
    call xslice_eq
    pop rcx               # name_len
    test eax, eax
    jz .Lltt_entry
    cmp qword ptr [rip + g_tpl_count], MAX_TEMPLATES
    jae .Lltt_entry

    # Build full path "themes/<theme>/<name>\0"
    push rcx
    mov rax, [rsp + 40]   # dir_len (shifted +8 by push rcx)
    mov [rsp + 8 + SB_LEN], rax
    lea rdi, [rsp + 8]
    mov esi, '/'
    call sb_byte
    lea rdi, [rsp + 8]
    mov rsi, r15
    mov rdx, [rsp]
    call sb_mem
    lea rdi, [rsp + 8]
    xor esi, esi
    call sb_byte

    lea rdi, [rip + store_path_buf]
    lea rsi, [rip + store_file_buf]
    mov edx, 131071
    call read_file_buf
    pop rcx               # name_len
    test rax, rax
    js .Lltt_entry

    # Store name (without .html) and content in arena
    push rax              # file_len
    sub rcx, 5
    push rcx              # base_len
    mov rdi, r15
    mov rsi, rcx
    call arena_dup
    pop rcx
    pop rdx               # file_len
    test rax, rax
    jz .Lltt_entry
    push rax              # name_ptr
    push rcx              # name_len
    push rdx              # file_len
    lea rdi, [rip + store_file_buf]
    mov rsi, rdx
    call arena_dup
    pop rdx
    pop rcx
    pop r8                # name_ptr
    test rax, rax
    jz .Lltt_entry

    mov r9, [rip + g_tpl_count]
    imul r10, r9, TPL_SIZE
    lea r11, [rip + g_tpls]
    mov [r11 + r10 + TPL_NAME_PTR], r8
    mov [r11 + r10 + TPL_NAME_LEN], rcx
    mov [r11 + r10 + TPL_DATA_PTR], rax
    mov [r11 + r10 + TPL_DATA_LEN], rdx
    inc qword ptr [rip + g_tpl_count]
    jmp .Lltt_entry

.Lltt_close:
    mov rdi, [rsp + 24]
    call sys_close
.Lltt_done:
    add rsp, 48
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

# make_auto_summary(rdi=md_ptr, rsi=md_len) -> rax=ptr, rdx=len (allocated in arena)
make_auto_summary:
    push rbx
    push r12
    push r13
    sub rsp, 200          # [rsp..191]=tmp buf (192 bytes)
    mov r12, rdi
    mov r13, rsi
    xor ebx, ebx          # src idx
    xor ecx, ecx          # dst len
.Lmas_loop:
    cmp rbx, r13
    jae .Lmas_done
    cmp rcx, 160
    jae .Lmas_done
    mov al, [r12 + rbx]
    inc rbx
    # Strip Markdown images ![alt](url)
    cmp al, '!'
    jne .Lmas_chk_lbr
    cmp rbx, r13
    jae .Lmas_put
    cmp byte ptr [r12 + rbx], '['
    jne .Lmas_put
    inc rbx
.Lmas_skip_img_alt:
    cmp rbx, r13
    jae .Lmas_done
    mov dl, [r12 + rbx]
    inc rbx
    cmp dl, 10
    je .Lmas_loop
    cmp dl, ']'
    jne .Lmas_skip_img_alt
    jmp .Lmas_maybe_url
.Lmas_chk_lbr:
    # Keep link text from [text](url), strip brackets and (url)
    cmp al, '['
    je .Lmas_loop
    cmp al, ']'
    jne .Lmas_chk_md
.Lmas_maybe_url:
    cmp rbx, r13
    jae .Lmas_done
    cmp byte ptr [r12 + rbx], '('
    jne .Lmas_loop
    inc rbx
.Lmas_skip_url:
    cmp rbx, r13
    jae .Lmas_done
    mov dl, [r12 + rbx]
    inc rbx
    cmp dl, 10
    je .Lmas_loop
    cmp dl, ')'
    jne .Lmas_skip_url
    jmp .Lmas_loop
.Lmas_chk_md:
    cmp al, '#'
    je .Lmas_loop
    cmp al, '*'
    je .Lmas_loop
    cmp al, '`'
    je .Lmas_loop
    cmp al, '>'
    je .Lmas_loop
    cmp al, 13
    je .Lmas_loop
    cmp al, 10
    jne .Lmas_put
    mov al, ' '
.Lmas_put:
    # collapse leading/duplicate spaces
    cmp al, ' '
    jne .Lmas_store
    test rcx, rcx
    jz .Lmas_loop
    cmp byte ptr [rsp + rcx - 1], ' '
    je .Lmas_loop
.Lmas_store:
    mov [rsp + rcx], al
    inc rcx
    jmp .Lmas_loop
.Lmas_done:
    # UTF-8 safety: don't cut in middle of multi-byte continuation byte (0x80..0xBF)
.Lmas_utf8:
    test rcx, rcx
    jz .Lmas_dup
    movzx eax, byte ptr [rsp + rcx - 1]
    and eax, 0xc0
    cmp eax, 0x80
    jne .Lmas_dup
    dec rcx
    jmp .Lmas_utf8
.Lmas_dup:
    push rcx
    mov rdi, rsp
    add rdi, 8
    mov rsi, rcx
    call arena_dup
    pop rdx
    add rsp, 200
    pop r13
    pop r12
    pop rbx
    ret

# sort_posts_desc() -> insertion sort g_post_ptrs by date DESC
sort_posts_desc:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, [rip + g_post_count]
    cmp r12, 2
    jb .Lsp_done
    lea r13, [rip + g_post_ptrs]
    mov rbx, 1            # i = 1
.Lsp_outer:
    cmp rbx, r12
    jae .Lsp_done
    mov r14, [r13 + rbx*8]    # key = post_ptrs[i]
    mov r15, rbx
    dec r15                   # j = i - 1
.Lsp_inner:
    cmp r15, 0
    jl .Lsp_place
    mov r8, [r13 + r15*8]
    # Compare date(post[j]) vs date(key): want date DESC (so shift if post[j].date < key.date)
    mov rdi, [r8 + POST_DATE_PTR]
    mov rsi, [r8 + POST_DATE_LEN]
    mov rdx, [r14 + POST_DATE_PTR]
    mov rcx, [r14 + POST_DATE_LEN]
    push r8
    call xslice_cmp
    pop r8
    cmp rax, 0
    jg .Lsp_place
    jl .Lsp_shift
    # Same date -> tie-break by slug ASC (shift if post[j].slug > key.slug)
    mov rdi, [r8 + POST_SLUG_PTR]
    mov rsi, [r8 + POST_SLUG_LEN]
    mov rdx, [r14 + POST_SLUG_PTR]
    mov rcx, [r14 + POST_SLUG_LEN]
    push r8
    call xslice_cmp
    pop r8
    cmp rax, 0
    jle .Lsp_place
.Lsp_shift:
    mov [r13 + r15*8 + 8], r8
    dec r15
    jmp .Lsp_inner
.Lsp_place:
    mov [r13 + r15*8 + 8], r14
    inc rbx
    jmp .Lsp_outer
.Lsp_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# store_reload() -> reloads themes + posts into arena cleanly
.globl store_reload
store_reload:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    # [rsp+0..23]   path sbuf
    # [rsp+24..47]  html sbuf
    # [rsp+48..191] struct stat (144)
    # [rsp+192]     dir_fd
    # [rsp+200..215] date tmp buf (16)
    sub rsp, 224

    call arena_reset
    mov qword ptr [rip + g_post_count], 0
    mov qword ptr [rip + g_pub_count], 0
    mov qword ptr [rip + g_tag_count], 0
    mov qword ptr [rip + g_cat_count], 0
    mov qword ptr [rip + g_tpl_count], 0

    call load_theme_templates
    call load_categories_file

    mov rdi, AT_FDCWD
    lea rsi, [rip + dir_posts]
    mov edx, O_RDONLY | O_DIRECTORY | O_CLOEXEC
    xor ecx, ecx
    call sys_openat
    test rax, rax
    js .Lsr_finish
    mov [rsp + 192], rax

.Lsr_dents:
    mov rdi, [rsp + 192]
    lea rsi, [rip + store_dirent_buf]
    mov edx, 16384
    call sys_getdents64
    test rax, rax
    jle .Lsr_close
    mov r12, rax          # bytes
    xor r13, r13          # off
.Lsr_entry:
    cmp r13, r12
    jae .Lsr_dents
    lea r14, [rip + store_dirent_buf]
    add r14, r13
    movzx ebx, word ptr [r14 + 16]
    add r13, rbx
    lea r15, [r14 + 19]              # d_name
    mov rdi, r15
    call xstrlen
    cmp rax, 4
    jb .Lsr_entry
    # Check ends with ".md"
    push rax
    lea rdi, [r15 + rax - 3]
    mov esi, 3
    lea rdx, [rip + ext_md]
    mov ecx, 3
    call xslice_eq
    pop rcx               # name_len
    test eax, eax
    jz .Lsr_entry

    mov rax, [rip + g_post_count]
    cmp rax, MAX_POSTS
    jae .Lsr_entry

    # Build path "content/posts/<name>\0"
    push rcx
    lea rdi, [rsp + 8]
    lea rsi, [rip + store_path_buf]
    mov edx, 511
    call sb_init
    lea rdi, [rsp + 8]
    lea rsi, [rip + dir_posts_pre]
    mov edx, 14
    call sb_mem
    lea rdi, [rsp + 8]
    mov rsi, r15
    mov rdx, [rsp]
    call sb_mem
    lea rdi, [rsp + 8]
    xor esi, esi
    call sb_byte

    # stat file for mtime & regular-file check
    lea rdi, [rip + store_path_buf]
    lea rsi, [rsp + 56]   # shifted +8
    call sys_stat
    test rax, rax
    js .Lsr_skip_pop
    mov eax, [rsp + 56 + STAT_MODE]
    and eax, S_IFMT
    cmp eax, S_IFREG
    jne .Lsr_skip_pop

    # read file
    lea rdi, [rip + store_path_buf]
    lea rsi, [rip + store_file_buf]
    mov edx, 131071
    call read_file_buf
    test rax, rax
    js .Lsr_skip_pop
    mov rbx, rax          # raw_len

    # Allocate next post_t slot
    mov r8, [rip + g_post_count]
    imul r9, r8, POST_SIZE
    lea r10, [rip + g_posts]
    add r10, r9           # r10 = &post
    push r10
    mov rdi, r10
    xor esi, esi
    mov edx, POST_SIZE
    call xmemset
    pop r10

    mov rax, [rsp + 56 + STAT_MTIME]
    mov [r10 + POST_MTIME], rax

    # Parse frontmatter
    push r10
    lea rdi, [rip + store_file_buf]
    mov rsi, rbx
    mov rdx, r10
    call parse_frontmatter
    pop r10
    # rax = body_ptr, rdx = body_len
    push rax              # [rsp+8] body_ptr
    push rdx              # [rsp+0] body_len
    # Note: stack now has +24 from entry: [rsp+16] = filename_len

    # Default slug = filename without ".md" if missing
    cmp qword ptr [r10 + POST_SLUG_PTR], 0
    jne .Lsr_has_slug
    mov rcx, [rsp + 16]
    sub rcx, 3
    push r10
    push rcx
    mov rdi, r15
    mov rsi, rcx
    call arena_dup
    pop rcx
    pop r10
    mov [r10 + POST_SLUG_PTR], rax
    mov [r10 + POST_SLUG_LEN], rcx
.Lsr_has_slug:
    # Default title = slug if missing
    cmp qword ptr [r10 + POST_TITLE_PTR], 0
    jne .Lsr_has_title
    mov rax, [r10 + POST_SLUG_PTR]
    mov [r10 + POST_TITLE_PTR], rax
    mov rax, [r10 + POST_SLUG_LEN]
    mov [r10 + POST_TITLE_LEN], rax
.Lsr_has_title:
    # Default date = format_iso_date(mtime) if missing
    cmp qword ptr [r10 + POST_DATE_PTR], 0
    jne .Lsr_has_date
    push r10
    mov rdi, [r10 + POST_MTIME]
    lea rsi, [rsp + 200 + 32]   # date tmp buf (+24 +8 = +32)
    call format_iso_date
    lea rdi, [rsp + 200 + 32]
    mov esi, 10
    call arena_dup
    pop r10
    mov [r10 + POST_DATE_PTR], rax
    mov qword ptr [r10 + POST_DATE_LEN], 10
.Lsr_has_date:
    # Store raw markdown body in arena
    push r10
    mov rdi, [rsp + 16]   # body_ptr (+8)
    mov rsi, [rsp + 8]    # body_len (+8)
    call arena_dup
    pop r10
    mov [r10 + POST_MD_PTR], rax
    mov rdx, [rsp + 0]
    mov [r10 + POST_MD_LEN], rdx

    # Word count / read minutes estimate
    mov [r10 + POST_WORD_COUNT], rdx
    mov rax, rdx
    xor edx, edx
    mov rcx, 600
    div rcx
    inc rax
    mov [r10 + POST_READ_MIN], rax

    # Auto summary if missing
    cmp qword ptr [r10 + POST_SUMMARY_PTR], 0
    jne .Lsr_has_sum
    push r10
    mov rdi, [rsp + 16]
    mov rsi, [rsp + 8]
    call make_auto_summary
    pop r10
    mov [r10 + POST_SUMMARY_PTR], rax
    mov [r10 + POST_SUMMARY_LEN], rdx
.Lsr_has_sum:
    # Render Markdown -> HTML into store_html_buf, then copy to arena
    push r10
    lea rdi, [rsp + 24 + 32]   # html sbuf (+24 +8 = +32)
    lea rsi, [rip + store_html_buf]
    mov edx, 262143
    call sb_init
    mov rdi, [rsp + 16]        # body_ptr
    mov rsi, [rsp + 8]         # body_len
    lea rdx, [rsp + 24 + 32]   # html sbuf
    call md_to_html
    lea rdi, [rip + store_html_buf]
    mov rsi, [rsp + 24 + 32 + SB_LEN]
    push rsi
    call arena_dup
    pop rdx
    pop r10
    mov [r10 + POST_HTML_PTR], rax
    mov [r10 + POST_HTML_LEN], rdx

    # Pop body_len, body_ptr, filename_len
    add rsp, 24

    # Register pointer & bump counts
    mov r8, [rip + g_post_count]
    lea r9, [rip + g_post_ptrs]
    mov [r9 + r8*8], r10
    inc qword ptr [rip + g_post_count]

    cmp qword ptr [r10 + POST_DRAFT], 0
    jne .Lsr_entry
    inc qword ptr [rip + g_pub_count]
    # Add category to global index if present
    cmp qword ptr [r10 + POST_CAT_LEN], 0
    je .Lsr_tags_start
    push r10
    mov rdi, [r10 + POST_CAT_PTR]
    mov rsi, [r10 + POST_CAT_LEN]
    mov edx, 1
    call add_or_bump_cat
    pop r10
.Lsr_tags_start:
    # Add tags to global index
    xor rbx, rbx
.Lsr_tloop:
    cmp rbx, [r10 + POST_TAG_COUNT]
    jae .Lsr_entry
    push r10
    mov rdi, [r10 + POST_TAG_PTRS + rbx*8]
    mov rsi, [r10 + POST_TAG_LENS + rbx*8]
    call add_or_bump_tag
    pop r10
    inc rbx
    jmp .Lsr_tloop

.Lsr_skip_pop:
    pop rcx
    jmp .Lsr_entry

.Lsr_close:
    mov rdi, [rsp + 192]
    call sys_close

.Lsr_finish:
    call sort_posts_desc
    inc qword ptr [rip + g_reload_count]
    lea rdi, [rip + log_reloaded]
    call log_cstr

    add rsp, 224
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
