.include "defs.inc"

# config.ini parser & global configuration state (pure static blog)
.section .bss
.align 8
cfg_raw_buf:           .skip 16384

.globl g_cfg_port
g_cfg_port:            .quad 0
.globl g_cfg_per_page
g_cfg_per_page:        .quad 0

.globl g_cfg_site_name
g_cfg_site_name:       .skip 128
.globl g_cfg_site_name_len
g_cfg_site_name_len:   .quad 0

.globl g_cfg_subtitle
g_cfg_subtitle:        .skip 256
.globl g_cfg_subtitle_len
g_cfg_subtitle_len:    .quad 0

.globl g_cfg_site_url
g_cfg_site_url:        .skip 256
.globl g_cfg_site_url_len
g_cfg_site_url_len:    .quad 0

.globl g_cfg_author
g_cfg_author:          .skip 128
.globl g_cfg_author_len
g_cfg_author_len:      .quad 0

.globl g_cfg_theme
g_cfg_theme:           .skip 64
.globl g_cfg_theme_len
g_cfg_theme_len:       .quad 0

.globl g_cfg_dist_dir
g_cfg_dist_dir:        .skip 128
.globl g_cfg_dist_dir_len
g_cfg_dist_dir_len:    .quad 0

.globl g_cfg_studio_hash
g_cfg_studio_hash:     .skip 128
.globl g_cfg_studio_hash_len
g_cfg_studio_hash_len: .quad 0

.globl g_cfg_footer
g_cfg_footer:          .skip 256
.globl g_cfg_footer_len
g_cfg_footer_len:      .quad 0

.globl g_cfg_avatar
g_cfg_avatar:          .skip 256
.globl g_cfg_avatar_len
g_cfg_avatar_len:      .quad 0

.globl g_cfg_banner
g_cfg_banner:          .skip 256
.globl g_cfg_banner_len
g_cfg_banner_len:      .quad 0

.globl g_cfg_studio_path
g_cfg_studio_path:     .skip 96
.globl g_cfg_studio_path_len
g_cfg_studio_path_len: .quad 0

.globl g_cfg_path
g_cfg_path:            .skip 512
.globl g_cfg_path_len
g_cfg_path_len:        .quad 0

.section .rodata
def_site_name:   .ascii "AsmBlog"
.equ def_site_name_len, . - def_site_name
def_subtitle:    .ascii "Pure x86-64 Assembly Static Blog"
.equ def_subtitle_len, . - def_subtitle
def_site_url:    .ascii "http://localhost:8080"
.equ def_site_url_len, . - def_site_url
def_author:      .ascii "Author"
.equ def_author_len, . - def_author
def_theme:       .ascii "default"
.equ def_theme_len, . - def_theme
def_dist_dir:    .ascii "dist"
.equ def_dist_dir_len, . - def_dist_dir
def_footer:      .ascii "Made with ♡ · Powered by AsmBlog"
.equ def_footer_len, . - def_footer
def_avatar:      .ascii "/static/avatar.jpg?v=2"
.equ def_avatar_len, . - def_avatar
def_banner:      .ascii "/static/hero-banner.jpg?v=2"
.equ def_banner_len, . - def_banner
def_studio_path: .ascii "/studio"
.equ def_studio_path_len, . - def_studio_path

key_port:        .ascii "port"
.equ key_port_len, . - key_port
key_per_page:    .ascii "per_page"
.equ key_per_page_len, . - key_per_page
key_site_name:   .ascii "site_name"
.equ key_site_name_len, . - key_site_name
key_subtitle:    .ascii "subtitle"
.equ key_subtitle_len, . - key_subtitle
key_site_url:    .ascii "site_url"
.equ key_site_url_len, . - key_site_url
key_author:      .ascii "author"
.equ key_author_len, . - key_author
key_theme:       .ascii "theme"
.equ key_theme_len, . - key_theme
key_dist_dir:    .ascii "dist_dir"
.equ key_dist_dir_len, . - key_dist_dir
key_studio_hash: .ascii "studio_pass_sha256"
.equ key_studio_hash_len, . - key_studio_hash
key_footer:      .ascii "footer_text"
.equ key_footer_len, . - key_footer
key_avatar:      .ascii "avatar_url"
.equ key_avatar_len, . - key_avatar
key_banner:      .ascii "banner_url"
.equ key_banner_len, . - key_banner
key_studio_path: .ascii "studio_path"
.equ key_studio_path_len, . - key_studio_path

.section .text

# copy_cfg_str(rdi=dst, rsi=dst_max, rdx=len_var_ptr, rcx=src, r8=src_len)
copy_cfg_str:
    dec rsi
    cmp r8, rsi
    jbe .Lccs_ok
    mov r8, rsi
.Lccs_ok:
    mov [rdx], r8
    push rdi
    push r8
    mov rsi, rcx
    mov rdx, r8
    call xmemcpy
    pop r8
    pop rdi
    mov byte ptr [rdi + r8], 0
    ret

# config_init_defaults()
.globl config_init_defaults
config_init_defaults:
    mov qword ptr [rip + g_cfg_port], 8080
    mov qword ptr [rip + g_cfg_per_page], 6
    mov qword ptr [rip + g_cfg_studio_hash_len], 0
    mov byte ptr [rip + g_cfg_studio_hash], 0

    lea rdi, [rip + g_cfg_site_name]
    mov esi, 128
    lea rdx, [rip + g_cfg_site_name_len]
    lea rcx, [rip + def_site_name]
    mov r8d, def_site_name_len
    call copy_cfg_str

    lea rdi, [rip + g_cfg_subtitle]
    mov esi, 256
    lea rdx, [rip + g_cfg_subtitle_len]
    lea rcx, [rip + def_subtitle]
    mov r8d, def_subtitle_len
    call copy_cfg_str

    lea rdi, [rip + g_cfg_site_url]
    mov esi, 256
    lea rdx, [rip + g_cfg_site_url_len]
    lea rcx, [rip + def_site_url]
    mov r8d, def_site_url_len
    call copy_cfg_str

    lea rdi, [rip + g_cfg_author]
    mov esi, 128
    lea rdx, [rip + g_cfg_author_len]
    lea rcx, [rip + def_author]
    mov r8d, def_author_len
    call copy_cfg_str

    lea rdi, [rip + g_cfg_theme]
    mov esi, 64
    lea rdx, [rip + g_cfg_theme_len]
    lea rcx, [rip + def_theme]
    mov r8d, def_theme_len
    call copy_cfg_str

    lea rdi, [rip + g_cfg_dist_dir]
    mov esi, 128
    lea rdx, [rip + g_cfg_dist_dir_len]
    lea rcx, [rip + def_dist_dir]
    mov r8d, def_dist_dir_len
    call copy_cfg_str

    lea rdi, [rip + g_cfg_footer]
    mov esi, 256
    lea rdx, [rip + g_cfg_footer_len]
    lea rcx, [rip + def_footer]
    mov r8d, def_footer_len
    call copy_cfg_str

    lea rdi, [rip + g_cfg_avatar]
    mov esi, 256
    lea rdx, [rip + g_cfg_avatar_len]
    lea rcx, [rip + def_avatar]
    mov r8d, def_avatar_len
    call copy_cfg_str

    lea rdi, [rip + g_cfg_banner]
    mov esi, 256
    lea rdx, [rip + g_cfg_banner_len]
    lea rcx, [rip + def_banner]
    mov r8d, def_banner_len
    call copy_cfg_str

    lea rdi, [rip + g_cfg_studio_path]
    mov esi, 96
    lea rdx, [rip + g_cfg_studio_path_len]
    lea rcx, [rip + def_studio_path]
    mov r8d, def_studio_path_len
    call copy_cfg_str
    ret

# config_load(rdi=cstr_path) -> rax=0 ok
.globl config_load
config_load:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    # Save config path for studio settings writes (avoid aliasing if rdi == g_cfg_path)
    lea rax, [rip + g_cfg_path]
    cmp r12, rax
    je .Lcl_init_def
    mov rdi, r12
    call xstrlen
    mov r8, rax
    lea rdi, [rip + g_cfg_path]
    mov esi, 512
    lea rdx, [rip + g_cfg_path_len]
    mov rcx, r12
    call copy_cfg_str
.Lcl_init_def:
    call config_init_defaults

    mov rdi, r12
    lea rsi, [rip + cfg_raw_buf]
    mov edx, 16383
    call read_file_buf
    test rax, rax
    jle .Lcl_done

    lea r12, [rip + cfg_raw_buf]
    mov r13, rax
    xor r14, r14

.Lcl_line:
    cmp r14, r13
    jae .Lcl_done
    lea rbx, [r12 + r14]
    mov rcx, r13
    sub rcx, r14
    mov rdi, rbx
    mov rsi, rcx
    mov edx, 10
    call xmemchr
    cmp rax, -1
    jne .Lcl_has_nl
    mov r15, r13
    sub r15, r14
    mov r14, r13
    jmp .Lcl_parse_line
.Lcl_has_nl:
    mov r15, rax
    add r14, rax
    inc r14
.Lcl_parse_line:
    mov rdi, rbx
    mov rsi, r15
    call trim_ws
    mov rbx, rax
    mov r15, rdx
    test r15, r15
    jz .Lcl_line
    mov al, [rbx]
    cmp al, '#'
    je .Lcl_line
    cmp al, ';'
    je .Lcl_line
    cmp al, '['
    je .Lcl_line

    mov rdi, rbx
    mov rsi, r15
    mov edx, '='
    call xmemchr
    cmp rax, -1
    je .Lcl_line
    push rax
    mov rdi, rbx
    mov rsi, rax
    call trim_ws
    pop rcx
    push rax
    push rdx
    lea rdi, [rbx + rcx + 1]
    mov rsi, r15
    sub rsi, rcx
    dec rsi
    call trim_ws
    mov r8, rax
    mov r9, rdx
    pop rdx
    pop rdi

    push rdi              # [rsp+24] key_ptr
    push rdx              # [rsp+16] key_len
    push r8               # [rsp+8]  val_ptr
    push r9               # [rsp+0]  val_len

    # port
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 16]
    lea rdx, [rip + key_port]
    mov ecx, key_port_len
    call xslice_eq_ci
    test eax, eax
    jz .Lcl_k_pp
    mov rdi, [rsp + 8]
    mov rsi, [rsp + 0]
    call parse_uint
    test edx, edx
    jz .Lcl_next_kv
    cmp rax, 1
    jb .Lcl_next_kv
    cmp rax, 65535
    ja .Lcl_next_kv
    mov [rip + g_cfg_port], rax
    jmp .Lcl_next_kv

.Lcl_k_pp:
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 16]
    lea rdx, [rip + key_per_page]
    mov ecx, key_per_page_len
    call xslice_eq_ci
    test eax, eax
    jz .Lcl_k_sn
    mov rdi, [rsp + 8]
    mov rsi, [rsp + 0]
    call parse_uint
    test edx, edx
    jz .Lcl_next_kv
    cmp rax, 1
    jb .Lcl_next_kv
    cmp rax, 100
    ja .Lcl_next_kv
    mov [rip + g_cfg_per_page], rax
    jmp .Lcl_next_kv

.Lcl_k_sn:
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 16]
    lea rdx, [rip + key_site_name]
    mov ecx, key_site_name_len
    call xslice_eq_ci
    test eax, eax
    jz .Lcl_k_sub
    lea rdi, [rip + g_cfg_site_name]
    mov esi, 128
    lea rdx, [rip + g_cfg_site_name_len]
    mov rcx, [rsp + 8]
    mov r8, [rsp + 0]
    call copy_cfg_str
    jmp .Lcl_next_kv

.Lcl_k_sub:
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 16]
    lea rdx, [rip + key_subtitle]
    mov ecx, key_subtitle_len
    call xslice_eq_ci
    test eax, eax
    jz .Lcl_k_url
    lea rdi, [rip + g_cfg_subtitle]
    mov esi, 256
    lea rdx, [rip + g_cfg_subtitle_len]
    mov rcx, [rsp + 8]
    mov r8, [rsp + 0]
    call copy_cfg_str
    jmp .Lcl_next_kv

.Lcl_k_url:
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 16]
    lea rdx, [rip + key_site_url]
    mov ecx, key_site_url_len
    call xslice_eq_ci
    test eax, eax
    jz .Lcl_k_auth
    lea rdi, [rip + g_cfg_site_url]
    mov esi, 256
    lea rdx, [rip + g_cfg_site_url_len]
    mov rcx, [rsp + 8]
    mov r8, [rsp + 0]
    call copy_cfg_str
    jmp .Lcl_next_kv

.Lcl_k_auth:
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 16]
    lea rdx, [rip + key_author]
    mov ecx, key_author_len
    call xslice_eq_ci
    test eax, eax
    jz .Lcl_k_th
    lea rdi, [rip + g_cfg_author]
    mov esi, 128
    lea rdx, [rip + g_cfg_author_len]
    mov rcx, [rsp + 8]
    mov r8, [rsp + 0]
    call copy_cfg_str
    jmp .Lcl_next_kv

.Lcl_k_th:
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 16]
    lea rdx, [rip + key_theme]
    mov ecx, key_theme_len
    call xslice_eq_ci
    test eax, eax
    jz .Lcl_k_dist
    mov rdi, [rsp + 8]
    mov rsi, [rsp + 0]
    call is_safe_slug
    test eax, eax
    jz .Lcl_next_kv
    lea rdi, [rip + g_cfg_theme]
    mov esi, 64
    lea rdx, [rip + g_cfg_theme_len]
    mov rcx, [rsp + 8]
    mov r8, [rsp + 0]
    call copy_cfg_str
    jmp .Lcl_next_kv

.Lcl_k_dist:
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 16]
    lea rdx, [rip + key_dist_dir]
    mov ecx, key_dist_dir_len
    call xslice_eq_ci
    test eax, eax
    jz .Lcl_k_sh
    mov rdi, [rsp + 8]
    mov rsi, [rsp + 0]
    call is_safe_relpath
    test eax, eax
    jz .Lcl_next_kv
    lea rdi, [rip + g_cfg_dist_dir]
    mov esi, 128
    lea rdx, [rip + g_cfg_dist_dir_len]
    mov rcx, [rsp + 8]
    mov r8, [rsp + 0]
    call copy_cfg_str
    jmp .Lcl_next_kv

.Lcl_k_sh:
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 16]
    lea rdx, [rip + key_studio_hash]
    mov ecx, key_studio_hash_len
    call xslice_eq_ci
    test eax, eax
    jz .Lcl_k_foot
    lea rdi, [rip + g_cfg_studio_hash]
    mov esi, 128
    lea rdx, [rip + g_cfg_studio_hash_len]
    mov rcx, [rsp + 8]
    mov r8, [rsp + 0]
    call copy_cfg_str
    jmp .Lcl_next_kv

.Lcl_k_foot:
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 16]
    lea rdx, [rip + key_footer]
    mov ecx, key_footer_len
    call xslice_eq_ci
    test eax, eax
    jz .Lcl_k_ava
    lea rdi, [rip + g_cfg_footer]
    mov esi, 256
    lea rdx, [rip + g_cfg_footer_len]
    mov rcx, [rsp + 8]
    mov r8, [rsp + 0]
    call copy_cfg_str
    jmp .Lcl_next_kv

.Lcl_k_ava:
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 16]
    lea rdx, [rip + key_avatar]
    mov ecx, key_avatar_len
    call xslice_eq_ci
    test eax, eax
    jz .Lcl_k_ban
    mov rdi, [rsp + 8]
    mov rsi, [rsp + 0]
    call is_safe_url
    test eax, eax
    jz .Lcl_next_kv
    lea rdi, [rip + g_cfg_avatar]
    mov esi, 256
    lea rdx, [rip + g_cfg_avatar_len]
    mov rcx, [rsp + 8]
    mov r8, [rsp + 0]
    call copy_cfg_str
    jmp .Lcl_next_kv

.Lcl_k_ban:
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 16]
    lea rdx, [rip + key_banner]
    mov ecx, key_banner_len
    call xslice_eq_ci
    test eax, eax
    jz .Lcl_k_sp
    mov rdi, [rsp + 8]
    mov rsi, [rsp + 0]
    call is_safe_url
    test eax, eax
    jz .Lcl_next_kv
    lea rdi, [rip + g_cfg_banner]
    mov esi, 256
    lea rdx, [rip + g_cfg_banner_len]
    mov rcx, [rsp + 8]
    mov r8, [rsp + 0]
    call copy_cfg_str
    jmp .Lcl_next_kv

.Lcl_k_sp:
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 16]
    lea rdx, [rip + key_studio_path]
    mov ecx, key_studio_path_len
    call xslice_eq_ci
    test eax, eax
    jz .Lcl_next_kv
    # studio_path must start with '/', len 2..64, trailing '/' trimmed, rest safe slug
    mov rcx, [rsp + 8]
    mov r8, [rsp + 0]
    cmp r8, 2
    jb .Lcl_next_kv
    cmp r8, 64
    ja .Lcl_next_kv
    cmp byte ptr [rcx], '/'
    jne .Lcl_next_kv
    cmp byte ptr [rcx + r8 - 1], '/'
    jne .Lcl_sp_chk
    dec r8
    cmp r8, 2
    jb .Lcl_next_kv
.Lcl_sp_chk:
    push rcx
    push r8
    lea rdi, [rcx + 1]
    lea rsi, [r8 - 1]
    call is_safe_slug
    pop r8
    pop rcx
    test eax, eax
    jz .Lcl_next_kv
    lea rdi, [rip + g_cfg_studio_path]
    mov esi, 96
    lea rdx, [rip + g_cfg_studio_path_len]
    call copy_cfg_str

.Lcl_next_kv:
    add rsp, 32
    jmp .Lcl_line

.Lcl_done:
    xor eax, eax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
