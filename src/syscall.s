.include "defs.inc"

.section .text

# Thin Linux x86-64 syscall helpers
# Note: syscall preserves rbx, rbp, r12-r15; clobbers rcx, r11.

.globl sys_read
sys_read:
    mov eax, SYS_read
    syscall
    ret

.globl sys_write
sys_write:
    mov eax, SYS_write
    syscall
    ret

.globl sys_close
sys_close:
    mov eax, SYS_close
    syscall
    ret

.globl sys_openat
sys_openat:
    # rdi=dirfd, rsi=path, rdx=flags, rcx=mode -> r10=rcx
    mov r10, rcx
    mov eax, SYS_openat
    syscall
    ret

.globl sys_fstat
sys_fstat:
    mov eax, SYS_fstat
    syscall
    ret

.globl sys_stat
sys_stat:
    mov eax, SYS_stat
    syscall
    ret

.globl sys_mmap
sys_mmap:
    # rdi=addr, rsi=len, rdx=prot, rcx=flags, r8=fd, r9=off
    mov r10, rcx
    mov eax, SYS_mmap
    syscall
    ret

.globl sys_munmap
sys_munmap:
    mov eax, SYS_munmap
    syscall
    ret

.globl sys_madvise
sys_madvise:
    mov eax, SYS_madvise
    syscall
    ret

.globl sys_socket
sys_socket:
    mov eax, SYS_socket
    syscall
    ret

.globl sys_bind
sys_bind:
    mov eax, SYS_bind
    syscall
    ret

.globl sys_listen
sys_listen:
    mov eax, SYS_listen
    syscall
    ret

.globl sys_setsockopt
sys_setsockopt:
    mov r10, rcx
    mov eax, SYS_setsockopt
    syscall
    ret

.globl sys_accept4
sys_accept4:
    mov r10, rcx
    mov eax, SYS_accept4
    syscall
    ret

.globl sys_sendfile
sys_sendfile:
    mov r10, rcx
    mov eax, SYS_sendfile
    syscall
    ret

.globl sys_epoll_create1
sys_epoll_create1:
    mov eax, SYS_epoll_create1
    syscall
    ret

.globl sys_epoll_ctl
sys_epoll_ctl:
    mov r10, rcx
    mov eax, SYS_epoll_ctl
    syscall
    ret

.globl sys_epoll_wait
sys_epoll_wait:
    mov r10, rcx
    mov eax, SYS_epoll_wait
    syscall
    ret

.globl sys_signalfd4
sys_signalfd4:
    mov r10, rcx
    mov eax, SYS_signalfd4
    syscall
    ret

.globl sys_rt_sigaction
sys_rt_sigaction:
    mov r10, rcx
    mov eax, SYS_rt_sigaction
    syscall
    ret

.globl sys_rt_sigprocmask
sys_rt_sigprocmask:
    mov r10, rcx
    mov eax, SYS_rt_sigprocmask
    syscall
    ret

.globl sys_inotify_init1
sys_inotify_init1:
    mov eax, SYS_inotify_init1
    syscall
    ret

.globl sys_inotify_add_watch
sys_inotify_add_watch:
    mov eax, SYS_inotify_add_watch
    syscall
    ret

.globl sys_getdents64
sys_getdents64:
    mov eax, SYS_getdents64
    syscall
    ret

.globl sys_clock_gettime
sys_clock_gettime:
    mov eax, SYS_clock_gettime
    syscall
    ret

.globl sys_mkdir
sys_mkdir:
    mov eax, SYS_mkdir
    syscall
    ret

.globl sys_rename
sys_rename:
    mov eax, SYS_rename
    syscall
    ret

.globl sys_unlink
sys_unlink:
    mov eax, SYS_unlink
    syscall
    ret

.globl sys_chdir
sys_chdir:
    mov eax, SYS_chdir
    syscall
    ret

.globl sys_getrandom
sys_getrandom:
    mov eax, SYS_getrandom
    syscall
    ret

.globl sys_exit_group
sys_exit_group:
    mov eax, SYS_exit_group
    syscall
    hlt

# --- Higher-level OS helpers ---

# mono_sec() -> rax (monotonic seconds)
.globl mono_sec
mono_sec:
    sub rsp, 24
    mov edi, CLOCK_MONOTONIC
    mov rsi, rsp
    call sys_clock_gettime
    mov rax, [rsp]
    add rsp, 24
    ret

# real_sec() -> rax (wall-clock unix epoch seconds)
.globl real_sec
real_sec:
    sub rsp, 24
    mov edi, CLOCK_REALTIME
    mov rsi, rsp
    call sys_clock_gettime
    mov rax, [rsp]
    add rsp, 24
    ret

# write_all(rdi=fd, rsi=ptr, rdx=len) -> rax (0 on ok, <0 on err)
.globl write_all
write_all:
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
.Lwa_loop:
    test r14, r14
    jz .Lwa_ok
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    call sys_write
    cmp rax, -EINTR
    je .Lwa_loop
    test rax, rax
    jle .Lwa_err
    add r13, rax
    sub r14, rax
    jmp .Lwa_loop
.Lwa_ok:
    xor eax, eax
    jmp .Lwa_done
.Lwa_err:
    test rax, rax
    jnz .Lwa_done
    mov rax, -1
.Lwa_done:
    pop r14
    pop r13
    pop r12
    ret

# log_cstr(rdi=cstr) -> writes to stderr (fd 2)
.globl log_cstr
log_cstr:
    push r12
    mov r12, rdi
    call xstrlen
    mov rdx, rax
    mov rsi, r12
    mov edi, 2
    call write_all
    pop r12
    ret

# log_slice(rdi=ptr, rsi=len) -> writes to stderr (fd 2)
.globl log_slice
log_slice:
    mov rdx, rsi
    mov rsi, rdi
    mov edi, 2
    jmp write_all

# out_cstr(rdi=cstr) -> writes to stdout (fd 1)
.globl out_cstr
out_cstr:
    push r12
    mov r12, rdi
    call xstrlen
    mov rdx, rax
    mov rsi, r12
    mov edi, 1
    call write_all
    pop r12
    ret

# read_file_buf(rdi=cstr_path, rsi=dst_buf, rdx=max_len) -> rax=bytes_read or <0
.globl read_file_buf
read_file_buf:
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi          # path
    mov r12, rsi          # dst
    mov r13, rdx          # cap
    xor r14, r14          # total read
    mov rdi, AT_FDCWD
    mov rsi, rbx
    mov edx, O_RDONLY | O_CLOEXEC
    xor ecx, ecx
    call sys_openat
    test rax, rax
    js .Lrf_ret
    mov rbx, rax          # fd
.Lrf_loop:
    mov rax, r13
    sub rax, r14
    jle .Lrf_close
    mov rdi, rbx
    lea rsi, [r12 + r14]
    mov rdx, rax
    call sys_read
    cmp rax, -EINTR
    je .Lrf_loop
    test rax, rax
    js .Lrf_close_err
    jz .Lrf_close
    add r14, rax
    jmp .Lrf_loop
.Lrf_close_err:
    mov r14, rax
.Lrf_close:
    mov rdi, rbx
    call sys_close
    mov rax, r14
.Lrf_ret:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# write_file_atomic(rdi=cstr_path, rsi=tmp_path, rdx=data_ptr, rcx=data_len) -> rax=0 ok, <0 err
.globl write_file_atomic
write_file_atomic:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi          # final path
    mov r13, rsi          # tmp path
    mov r14, rdx          # data ptr
    mov r15, rcx          # data len
    mov rdi, AT_FDCWD
    mov rsi, r13
    mov edx, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC
    mov ecx, 0644
    call sys_openat
    test rax, rax
    js .Lwfa_ret
    mov rbx, rax          # fd
    mov rdi, rbx
    mov rsi, r14
    mov rdx, r15
    call write_all
    push rax
    mov rdi, rbx
    call sys_close
    pop rax
    test rax, rax
    js .Lwfa_unlink
    mov rdi, r13
    mov rsi, r12
    call sys_rename
    jmp .Lwfa_ret
.Lwfa_unlink:
    push rax
    mov rdi, r13
    call sys_unlink
    pop rax
.Lwfa_ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
