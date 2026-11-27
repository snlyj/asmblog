.include "defs.inc"

# One-Click Full Site Backup (.tar POSIX ustar streaming archive)
# Pure x86-64 assembly: zero external commands, unlinked temp fd + kernel sendfile zero-copy!
# Archives config.ini, content/posts/*, content/uploads/*, and all JSON/text metadata.

.section .bss
.align 8
tar_hdr:        .skip 512
tar_zero_blk:   .skip 1024
tar_buf:        .skip 65536
tar_dents:      .skip 16384
tar_src_path:   .skip 512
tar_arc_path:   .skip 256

.section .rodata
bk_d_content:   .asciz "content"
bk_tmp_file:    .asciz "content/.backup.tar.tmp"
bk_def_cfg:     .asciz "config.ini"
bk_f_cats:      .asciz "content/categories.txt"
bk_f_gal:       .asciz "content/gallery.json"
bk_f_abt:       .asciz "content/about.json"
bk_f_bgm:       .asciz "content/bgm.json"
bk_f_mom:       .asciz "content/moments.json"
bk_f_stats:     .asciz "content/stats.txt"
bk_d_posts:     .asciz "content/posts"
bk_d_uploads:   .asciz "content/uploads"

bk_disk_posts:  .ascii "content/posts/"
.equ bk_disk_posts_len, . - bk_disk_posts
bk_disk_up:     .ascii "content/uploads/"
.equ bk_disk_up_len, . - bk_disk_up

bk_arc_cfg:     .ascii "asmblog-backup/config.ini"
.equ bk_arc_cfg_len, . - bk_arc_cfg
bk_arc_cats:    .ascii "asmblog-backup/content/categories.txt"
.equ bk_arc_cats_len, . - bk_arc_cats
bk_arc_gal:     .ascii "asmblog-backup/content/gallery.json"
.equ bk_arc_gal_len, . - bk_arc_gal
bk_arc_abt:     .ascii "asmblog-backup/content/about.json"
.equ bk_arc_abt_len, . - bk_arc_abt
bk_arc_bgm:     .ascii "asmblog-backup/content/bgm.json"
.equ bk_arc_bgm_len, . - bk_arc_bgm
bk_arc_mom:     .ascii "asmblog-backup/content/moments.json"
.equ bk_arc_mom_len, . - bk_arc_mom
bk_arc_stats:   .ascii "asmblog-backup/content/stats.txt"
.equ bk_arc_stats_len, . - bk_arc_stats
bk_arc_posts:   .ascii "asmblog-backup/content/posts/"
.equ bk_arc_posts_len, . - bk_arc_posts
bk_arc_up:      .ascii "asmblog-backup/content/uploads/"
.equ bk_arc_up_len, . - bk_arc_up

tar_mode_s:     .ascii "0000644"
tar_zero7_s:    .ascii "0000000"
tar_ustar_s:    .ascii "ustar"

ct_tar:         .asciz "application/x-tar"
hdr_tar_dl:     .asciz "\r\nCache-Control: no-store\r\nContent-Disposition: attachment; filename=\"asmblog-backup.tar\""
j_bk_unauth:    .ascii "{\"error\":\"unauthorized\"}"
.equ j_bk_unauth_len, . - j_bk_unauth
j_bk_err:       .ascii "{\"error\":\"backup generation failed\"}"
.equ j_bk_err_len, . - j_bk_err

.section .text

# tar_put_octal(rdi=dst, rsi=val, rdx=num_digits) -> writes zero-padded octal + NUL
tar_put_octal:
    mov byte ptr [rdi + rdx], 0
    mov rcx, rdx
.Ltpo_loop:
    test rcx, rcx
    jz .Ltpo_done
    dec rcx
    mov eax, esi
    and eax, 7
    add al, '0'
    mov [rdi + rcx], al
    shr rsi, 3
    jmp .Ltpo_loop
.Ltpo_done:
    ret

# tar_add_file(rdi=out_fd, rsi=src_cstr, rdx=arc_ptr, rcx=arc_len, r8=&total_written) -> rax=0 ok, <0 write_err
tar_add_file:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    # 6 pushes + ret = 56; +184 = 240 (16B aligned)
    # [0..143]=stat(144), [144]=in_fd, [152]=file_size, [160]=rem, [168]=total_ptr
    sub rsp, 184
    mov r12, rdi          # out_fd
    mov r13, rdx          # arc_ptr
    mov r14, rcx          # arc_len
    mov [rsp + 168], r8   # &total_written

    test r14, r14
    jz .Ltaf_skip_ok
    cmp r14, 250
    ja .Ltaf_skip_ok

    # Open source file safely (no symlink following)
    mov rdi, AT_FDCWD
    # rsi already = src_cstr
    mov edx, O_RDONLY | O_NOFOLLOW | O_CLOEXEC
    xor ecx, ecx
    call sys_openat
    test rax, rax
    js .Ltaf_skip_ok
    mov [rsp + 144], rax

    mov rdi, rax
    mov rsi, rsp
    call sys_fstat
    test rax, rax
    js .Ltaf_close_ok

    mov eax, [rsp + STAT_MODE]
    and eax, S_IFMT
    cmp eax, S_IFREG
    jne .Ltaf_close_ok

    mov rax, [rsp + STAT_SIZE]
    mov [rsp + 152], rax
    mov [rsp + 160], rax

    # Build 512-byte POSIX ustar header (auto-splits >99B paths across ustar prefix[345] + name[0]!)
    lea rdi, [rip + tar_hdr]
    xor esi, esi
    mov edx, 512
    call xmemset

    cmp r14, 99
    jbe .Ltaf_short_name
    # Find last '/' in arc_ptr to split prefix (<=154B) and basename (<=99B)
    mov rcx, r14
.Ltaf_find_sl:
    dec rcx
    js .Ltaf_close_ok
    cmp byte ptr [r13 + rcx], '/'
    jne .Ltaf_find_sl
    test rcx, rcx
    jz .Ltaf_close_ok
    cmp rcx, 154
    ja .Ltaf_close_ok
    mov rbx, r14
    sub rbx, rcx
    dec rbx
    test rbx, rbx
    jz .Ltaf_close_ok
    cmp rbx, 99
    ja .Ltaf_close_ok
    push rcx
    push rbx
    lea rdi, [rip + tar_hdr + 345]
    mov rsi, r13
    mov rdx, rcx
    call xmemcpy
    pop rbx
    pop rcx
    lea rdi, [rip + tar_hdr]
    lea rsi, [r13 + rcx + 1]
    mov rdx, rbx
    call xmemcpy
    jmp .Ltaf_name_done

.Ltaf_short_name:
    lea rdi, [rip + tar_hdr]
    mov rsi, r13
    mov rdx, r14
    call xmemcpy
.Ltaf_name_done:

    lea rdi, [rip + tar_hdr + 100]; lea rsi, [rip + tar_mode_s];  mov edx, 7; call xmemcpy
    lea rdi, [rip + tar_hdr + 108]; lea rsi, [rip + tar_zero7_s]; mov edx, 7; call xmemcpy
    lea rdi, [rip + tar_hdr + 116]; lea rsi, [rip + tar_zero7_s]; mov edx, 7; call xmemcpy
    lea rdi, [rip + tar_hdr + 124]; mov rsi, [rsp + 152];         mov edx, 11; call tar_put_octal
    lea rdi, [rip + tar_hdr + 136]; mov rsi, [rsp + STAT_MTIME];  mov edx, 11; call tar_put_octal
    lea rdi, [rip + tar_hdr + 148]; mov esi, ' ';                 mov edx, 8; call xmemset
    mov byte ptr [rip + tar_hdr + 156], '0'
    lea rdi, [rip + tar_hdr + 257]; lea rsi, [rip + tar_ustar_s]; mov edx, 5; call xmemcpy
    mov byte ptr [rip + tar_hdr + 263], '0'
    mov byte ptr [rip + tar_hdr + 264], '0'

    # Checksum = unsigned sum of all 512 bytes
    xor eax, eax
    xor ecx, ecx
    lea r8, [rip + tar_hdr]
.Ltaf_csum:
    movzx edx, byte ptr [r8 + rcx]
    add rax, rdx
    inc rcx
    cmp rcx, 512
    jb .Ltaf_csum

    lea rdi, [rip + tar_hdr + 148]
    mov rsi, rax
    mov edx, 6
    call tar_put_octal
    mov byte ptr [rip + tar_hdr + 155], ' '

    # Write header block
    mov rdi, r12
    lea rsi, [rip + tar_hdr]
    mov edx, 512
    call write_all
    test rax, rax
    js .Ltaf_close_err
    mov r8, [rsp + 168]
    add qword ptr [r8], 512

    # Stream exact st_size bytes into archive
.Ltaf_copy:
    mov r15, [rsp + 160]
    test r15, r15
    jz .Ltaf_pad
    cmp r15, 65536
    jbe .Ltaf_read
    mov r15, 65536
.Ltaf_read:
    mov rdi, [rsp + 144]
    lea rsi, [rip + tar_buf]
    mov rdx, r15
    call sys_read
    cmp rax, -EINTR
    je .Ltaf_read
    test rax, rax
    js .Ltaf_close_err
    jz .Ltaf_short_pad        # file shrank concurrently -> pad remaining bytes with zeros
    mov rbx, rax
    mov rdi, r12
    lea rsi, [rip + tar_buf]
    mov rdx, rbx
    call write_all
    test rax, rax
    js .Ltaf_close_err
    sub [rsp + 160], rbx
    mov r8, [rsp + 168]
    add [r8], rbx
    jmp .Ltaf_copy

.Ltaf_short_pad:
    mov r15, [rsp + 160]
    test r15, r15
    jz .Ltaf_pad
    cmp r15, 1024
    jbe .Ltaf_sp_wr
    mov r15, 1024
.Ltaf_sp_wr:
    mov rdi, r12
    lea rsi, [rip + tar_zero_blk]
    mov rdx, r15
    call write_all
    test rax, rax
    js .Ltaf_close_err
    sub [rsp + 160], r15
    mov r8, [rsp + 168]
    add [r8], r15
    jmp .Ltaf_short_pad

.Ltaf_pad:
    mov rax, [rsp + 152]
    and rax, 511
    jz .Ltaf_close_ok
    mov rbx, 512
    sub rbx, rax
    mov rdi, r12
    lea rsi, [rip + tar_zero_blk]
    mov rdx, rbx
    call write_all
    test rax, rax
    js .Ltaf_close_err
    mov r8, [rsp + 168]
    add [r8], rbx

.Ltaf_close_ok:
    mov rdi, [rsp + 144]
    call sys_close
.Ltaf_skip_ok:
    xor eax, eax
    jmp .Ltaf_ret

.Ltaf_close_err:
    mov rdi, [rsp + 144]
    call sys_close
    mov rax, -1

.Ltaf_ret:
    add rsp, 184
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

# tar_add_dir(rdi=out_fd, rsi=dir_cstr, rdx=disk_pre_ptr, rcx=disk_pre_len, r8=arc_pre_ptr, r9=arc_pre_len, [rbp+16]=&total_written)
tar_add_dir:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    # 6 pushes + ret = 56; +104 = 160 (16B aligned)
    # [0..23]=sb_src, [24..47]=sb_arc, [48]=dir_fd, [56]=dents_bytes, [64]=dents_off,
    # [72]=disk_pre_ptr, [80]=disk_pre_len, [88]=arc_pre_ptr, [96]=arc_pre_len
    sub rsp, 104
    mov r12, rdi          # out_fd
    mov [rsp + 72], rdx
    mov [rsp + 80], rcx
    mov [rsp + 88], r8
    mov [rsp + 96], r9

    mov rdi, AT_FDCWD
    # rsi = dir_cstr
    mov edx, O_RDONLY | O_DIRECTORY | O_CLOEXEC
    xor ecx, ecx
    call sys_openat
    test rax, rax
    js .Ltad_ok
    mov [rsp + 48], rax

.Ltad_dents:
    mov rdi, [rsp + 48]
    lea rsi, [rip + tar_dents]
    mov edx, 16384
    call sys_getdents64
    test rax, rax
    jle .Ltad_close_ok
    mov [rsp + 56], rax
    mov qword ptr [rsp + 64], 0

.Ltad_entry:
    mov rax, [rsp + 64]
    cmp rax, [rsp + 56]
    jae .Ltad_dents
    lea r13, [rip + tar_dents]
    add r13, rax
    movzx ecx, word ptr [r13 + 16]
    add [rsp + 64], rcx
    lea r14, [r13 + 19]               # d_name
    # Skip hidden files (., .., .gitkeep, .part, .tmp)
    cmp byte ptr [r14], '.'
    je .Ltad_entry
    mov rdi, r14
    call xstrlen
    test rax, rax
    jz .Ltad_entry
    mov r15, rax                      # name_len

    # Build disk source path
    lea rdi, [rsp + 0]; lea rsi, [rip + tar_src_path]; mov edx, 511; call sb_init
    lea rdi, [rsp + 0]; mov rsi, [rsp + 72]; mov rdx, [rsp + 80]; call sb_mem
    lea rdi, [rsp + 0]; mov rsi, r14; mov rdx, r15; call sb_mem
    lea rdi, [rsp + 0]; xor esi, esi; call sb_byte

    # Build archive path
    lea rdi, [rsp + 24]; lea rsi, [rip + tar_arc_path]; mov edx, 255; call sb_init
    lea rdi, [rsp + 24]; mov rsi, [rsp + 88]; mov rdx, [rsp + 96]; call sb_mem
    lea rdi, [rsp + 24]; mov rsi, r14; mov rdx, r15; call sb_mem

    mov rdi, r12
    lea rsi, [rip + tar_src_path]
    lea rdx, [rip + tar_arc_path]
    mov rcx, [rsp + 24 + SB_LEN]
    mov r8, [rbp + 16]
    call tar_add_file
    test rax, rax
    js .Ltad_close_err
    jmp .Ltad_entry

.Ltad_close_ok:
    mov rdi, [rsp + 48]
    call sys_close
.Ltad_ok:
    xor eax, eax
    jmp .Ltad_ret

.Ltad_close_err:
    mov rdi, [rsp + 48]
    call sys_close
    mov rax, -1

.Ltad_ret:
    add rsp, 104
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

# GET /api/studio/backup -> auth-gated full site .tar download via zero-copy sendfile
.globl handle_studio_backup
handle_studio_backup:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    # 6 pushes + ret = 56; +24 = 80 (16B aligned); [rsp+0]=total_written, [rsp+8]=out_fd
    sub rsp, 24
    mov r12, rdi          # conn
    mov r13, rsi          # &req

    mov rdi, r13
    call studio_is_authed
    test eax, eax
    jnz .Lhsb_open
    mov rdi, r12; lea rsi, [rip + st_401]; lea rdx, [rip + j_bk_unauth]; mov ecx, j_bk_unauth_len; xor r8d, r8d
    call studio_send_json
    jmp .Lhsb_ret

.Lhsb_open:
    lea rdi, [rip + bk_d_content]; mov esi, 0755; call sys_mkdir
    mov rdi, AT_FDCWD
    lea rsi, [rip + bk_tmp_file]
    mov edx, O_RDWR | O_CREAT | O_TRUNC | O_NOFOLLOW | O_CLOEXEC
    mov ecx, 0600
    call sys_openat
    test rax, rax
    js .Lhsb_err
    mov r14, rax
    mov [rsp + 8], rax
    mov qword ptr [rsp + 0], 0

    # Immediately unlink temp file so kernel auto-reclaims inode when download finishes or aborts!
    lea rdi, [rip + bk_tmp_file]
    call sys_unlink

    # 1) Live config.ini
    lea rsi, [rip + g_cfg_path]
    cmp qword ptr [rip + g_cfg_path_len], 0
    jne .Lhsb_cfg_go
    lea rsi, [rip + bk_def_cfg]
.Lhsb_cfg_go:
    mov rdi, r14; lea rdx, [rip + bk_arc_cfg]; mov ecx, bk_arc_cfg_len; mov r8, rsp; call tar_add_file
    test rax, rax; js .Lhsb_close_err

    # 2) Site metadata files (optional: skipped automatically if absent)
    mov rdi, r14; lea rsi, [rip + bk_f_cats];  lea rdx, [rip + bk_arc_cats];  mov ecx, bk_arc_cats_len;  mov r8, rsp; call tar_add_file
    test rax, rax; js .Lhsb_close_err
    mov rdi, r14; lea rsi, [rip + bk_f_gal];   lea rdx, [rip + bk_arc_gal];   mov ecx, bk_arc_gal_len;   mov r8, rsp; call tar_add_file
    test rax, rax; js .Lhsb_close_err
    mov rdi, r14; lea rsi, [rip + bk_f_abt];   lea rdx, [rip + bk_arc_abt];   mov ecx, bk_arc_abt_len;   mov r8, rsp; call tar_add_file
    test rax, rax; js .Lhsb_close_err
    mov rdi, r14; lea rsi, [rip + bk_f_bgm];   lea rdx, [rip + bk_arc_bgm];   mov ecx, bk_arc_bgm_len;   mov r8, rsp; call tar_add_file
    test rax, rax; js .Lhsb_close_err
    mov rdi, r14; lea rsi, [rip + bk_f_mom];   lea rdx, [rip + bk_arc_mom];   mov ecx, bk_arc_mom_len;   mov r8, rsp; call tar_add_file
    test rax, rax; js .Lhsb_close_err
    mov rdi, r14; lea rsi, [rip + bk_f_stats]; lea rdx, [rip + bk_arc_stats]; mov ecx, bk_arc_stats_len; mov r8, rsp; call tar_add_file
    test rax, rax; js .Lhsb_close_err

    # 3) All posts (including drafts!) & uploaded media
    # Pass &total_written as 7th arg on stack (keep 16B stack alignment with dummy push!)
    sub rsp, 16
    lea rax, [rsp + 16]
    mov [rsp + 0], rax
    mov rdi, r14; lea rsi, [rip + bk_d_posts]; lea rdx, [rip + bk_disk_posts]; mov ecx, bk_disk_posts_len
    lea r8, [rip + bk_arc_posts]; mov r9d, bk_arc_posts_len
    call tar_add_dir
    add rsp, 16
    test rax, rax; js .Lhsb_close_err

    sub rsp, 16
    lea rax, [rsp + 16]
    mov [rsp + 0], rax
    mov rdi, r14; lea rsi, [rip + bk_d_uploads]; lea rdx, [rip + bk_disk_up]; mov ecx, bk_disk_up_len
    lea r8, [rip + bk_arc_up]; mov r9d, bk_arc_up_len
    call tar_add_dir
    add rsp, 16
    test rax, rax; js .Lhsb_close_err

    # 4) POSIX tar EOF: two 512-byte zero blocks (1024 bytes)
    mov rdi, r14
    lea rsi, [rip + tar_zero_blk]
    mov edx, 1024
    call write_all
    test rax, rax
    js .Lhsb_close_err
    add qword ptr [rsp + 0], 1024

    # 5) Send HTTP 200 headers + attach unlinked fd for non-blocking sendfile streaming
    mov r15, [rsp + 0]
    mov rdi, r12
    lea rsi, [rip + st_200]
    lea rdx, [rip + ct_tar]
    xor ecx, ecx
    mov r8, r15
    lea r9, [rip + hdr_tar_dl]
    call http_send_resp

    cmp qword ptr [r12 + CONN_IS_HEAD], 0
    jne .Lhsb_close_ok
    mov [r12 + CONN_FILE_FD], r14
    mov qword ptr [r12 + CONN_FILE_OFF], 0
    mov [r12 + CONN_FILE_REM], r15
    jmp .Lhsb_ret

.Lhsb_close_ok:
    mov rdi, r14
    call sys_close
    jmp .Lhsb_ret

.Lhsb_close_err:
    mov rdi, r14
    call sys_close
.Lhsb_err:
    mov rdi, r12; lea rsi, [rip + st_500]; lea rdx, [rip + j_bk_err]; mov ecx, j_bk_err_len; xor r8d, r8d
    call studio_send_json

.Lhsb_ret:
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
