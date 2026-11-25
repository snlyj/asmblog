.include "defs.inc"

# Non-blocking epoll HTTP/1.1 Keep-Alive server + signalfd4 + inotify hot-reload + sendfile
.section .data
.align 8
g_epoll_fd:      .quad -1
g_listen_fd:     .quad -1
g_sig_fd:        .quad -1
g_inotify_fd:    .quad -1
g_running:       .quad 1

.section .bss
.align 8
conns:           .skip MAX_CONNS * CONN_SIZE
conn_rx_pool:    .skip MAX_CONNS * CONN_RX_CAP
conn_tx_pool:    .skip MAX_CONNS * CONN_TX_CAP

.globl g_active_conns
g_active_conns:  .quad 0

epoll_events:    .skip 64 * 12       # 64 packed struct epoll_event (12 bytes each!)
sig_read_buf:    .skip 128
inotify_buf:     .skip 4096
.globl cur_req
cur_req:         .skip REQ_SIZE
inotify_th_path: .skip 256

.section .rodata
log_start_1:     .asciz "[asmblog] listening on http://0.0.0.0:"
log_start_2:     .asciz " (pure x86-64 asm, epoll+inotify)\n"
log_bind_err:    .asciz "[asmblog] ERROR: failed to bind port\n"
log_stop:        .asciz "[asmblog] graceful shutdown complete\n"
log_sighup:      .asciz "[asmblog] SIGHUP received -> reloading store\n"
log_inotify:     .asciz "[asmblog] file change detected -> reloading store\n"
w_posts_dir:     .asciz "content/posts"
w_themes_pre:    .ascii "themes/"
err_400_msg:     .asciz "400 Bad Request"
err_413_msg:     .asciz "413 Payload Too Large"
err_414_msg:     .asciz "414 URI Too Long"

.section .text

# conn_init_pool() -> initializes all MAX_CONNS slots
conn_init_pool:
    xor ecx, ecx
    lea r8, [rip + conns]
    lea r9, [rip + conn_rx_pool]
    lea r10, [rip + conn_tx_pool]
.Lcip_loop:
    cmp ecx, MAX_CONNS
    jae .Lcip_done
    imul rax, rcx, CONN_SIZE
    mov qword ptr [r8 + rax + CONN_FD], -1
    mov qword ptr [r8 + rax + CONN_STATE], 0
    mov qword ptr [r8 + rax + CONN_FILE_FD], -1
    imul rdx, rcx, CONN_RX_CAP
    lea r11, [r9 + rdx]
    mov [r8 + rax + CONN_RX_PTR], r11
    imul rdx, rcx, CONN_TX_CAP
    lea r11, [r10 + rdx]
    mov [r8 + rax + CONN_TX_PTR], r11
    inc ecx
    jmp .Lcip_loop
.Lcip_done:
    mov qword ptr [rip + g_active_conns], 0
    ret

# conn_alloc(rdi=fd, esi=peer_ip) -> rax=&conn or 0 if full
conn_alloc:
    push rbx
    push r12
    mov r12, rdi
    mov ebx, esi
    xor ecx, ecx
    lea r8, [rip + conns]
.Lca_loop:
    cmp ecx, MAX_CONNS
    jae .Lca_full
    imul rax, rcx, CONN_SIZE
    cmp qword ptr [r8 + rax + CONN_FD], -1
    je .Lca_found
    inc ecx
    jmp .Lca_loop
.Lca_found:
    lea r12, [r8 + rax]
    mov [r12 + CONN_FD], rdi
    mov qword ptr [r12 + CONN_STATE], 1   # READ
    mov qword ptr [r12 + CONN_RX_LEN], 0
    mov qword ptr [r12 + CONN_TX_LEN], 0
    mov qword ptr [r12 + CONN_TX_OFF], 0
    mov qword ptr [r12 + CONN_FILE_FD], -1
    mov qword ptr [r12 + CONN_FILE_OFF], 0
    mov qword ptr [r12 + CONN_FILE_REM], 0
    mov qword ptr [r12 + CONN_KEEP_ALIVE], 1
    mov [r12 + CONN_PEER_IP], ebx
    mov qword ptr [r12 + CONN_IS_HEAD], 0
    call mono_sec
    mov [r12 + CONN_LAST_ACTIVE], rax
    inc qword ptr [rip + g_active_conns]
    mov rax, r12
    pop r12
    pop rbx
    ret
.Lca_full:
    xor eax, eax
    pop r12
    pop rbx
    ret

# conn_close(rdi=&conn)
conn_close:
    push r12
    mov r12, rdi
    mov rax, [r12 + CONN_FILE_FD]
    cmp rax, 0
    jl .Lcc_sock
    mov rdi, rax
    call sys_close
    mov qword ptr [r12 + CONN_FILE_FD], -1
.Lcc_sock:
    mov rax, [r12 + CONN_FD]
    cmp rax, 0
    jl .Lcc_done
    push rax
    mov rdi, [rip + g_epoll_fd]
    mov esi, EPOLL_CTL_DEL
    mov rdx, rax
    xor ecx, ecx
    call sys_epoll_ctl
    pop rdi
    call sys_close
    mov qword ptr [r12 + CONN_FD], -1
    mov qword ptr [r12 + CONN_STATE], 0
    dec qword ptr [rip + g_active_conns]
.Lcc_done:
    pop r12
    ret

# epoll_mod_conn(rdi=&conn, esi=events_mask)
epoll_mod_conn:
    sub rsp, 16           # packed 12-byte epoll_event at [rsp]
    mov [rsp + 0], esi
    mov [rsp + 4], rdi
    mov rdx, [rdi + CONN_FD]
    mov rdi, [rip + g_epoll_fd]
    mov esi, EPOLL_CTL_MOD
    mov rcx, rsp
    call sys_epoll_ctl
    add rsp, 16
    ret

# conn_try_write(rdi=&conn) -> writes tx_buf and sendfile non-blocking
# Caps sendfile to 256 KiB per epoll tick for multi-user fairness and refreshes
# CONN_LAST_ACTIVE on forward progress so long video streams never idle-timeout.
conn_try_write:
    push rbx
    push r12
    mov r12, rdi
    xor ebx, ebx                          # made_progress flag
.Lctw_buf:
    mov rdx, [r12 + CONN_TX_LEN]
    mov rcx, [r12 + CONN_TX_OFF]
    sub rdx, rcx
    jbe .Lctw_file
    mov rdi, [r12 + CONN_FD]
    mov rsi, [r12 + CONN_TX_PTR]
    add rsi, rcx
    call sys_write
    cmp rax, -EINTR
    je .Lctw_buf
    cmp rax, -EAGAIN
    je .Lctw_want_out
    test rax, rax
    jle .Lctw_err
    mov ebx, 1
    add [r12 + CONN_TX_OFF], rax
    jmp .Lctw_buf

.Lctw_file:
    mov rax, [r12 + CONN_FILE_FD]
    cmp rax, 0
    jl .Lctw_finished
    mov rcx, [r12 + CONN_FILE_REM]
    test rcx, rcx
    jz .Lctw_close_file
    # Fair burst cap (256 KiB per epoll tick) so large video streams never starve other clients
    cmp rcx, 262144
    jbe .Lctw_sf_go
    mov ecx, 262144
.Lctw_sf_go:
    mov rdi, [r12 + CONN_FD]
    mov rsi, rax
    lea rdx, [r12 + CONN_FILE_OFF]
    call sys_sendfile
    cmp rax, -EINTR
    je .Lctw_file
    cmp rax, -EAGAIN
    je .Lctw_want_out
    test rax, rax
    jle .Lctw_err
    mov ebx, 1
    sub [r12 + CONN_FILE_REM], rax
    cmp qword ptr [r12 + CONN_FILE_REM], 0
    jne .Lctw_want_out

.Lctw_close_file:
    mov rdi, [r12 + CONN_FILE_FD]
    call sys_close
    mov qword ptr [r12 + CONN_FILE_FD], -1

.Lctw_finished:
    call mono_sec
    mov [r12 + CONN_LAST_ACTIVE], rax
    # Keep-Alive or close?
    cmp qword ptr [r12 + CONN_KEEP_ALIVE], 0
    je .Lctw_err
    mov qword ptr [r12 + CONN_STATE], 1   # back to READ
    mov qword ptr [r12 + CONN_TX_LEN], 0
    mov qword ptr [r12 + CONN_TX_OFF], 0
    mov qword ptr [r12 + CONN_IS_HEAD], 0
    # If pipelined bytes remain in rx_buf, signal caller to continue iteratively (zero recursion)
    cmp qword ptr [r12 + CONN_RX_LEN], 0
    jne .Lctw_has_pipe
    mov rdi, r12
    mov esi, EPOLLIN | EPOLLRDHUP
    call epoll_mod_conn
    xor eax, eax
    pop r12
    pop rbx
    ret

.Lctw_has_pipe:
    mov eax, 1
    pop r12
    pop rbx
    ret

.Lctw_want_out:
    test ebx, ebx
    jz .Lctw_arm_out
    call mono_sec
    mov [r12 + CONN_LAST_ACTIVE], rax
.Lctw_arm_out:
    mov rdi, r12
    mov esi, EPOLLOUT | EPOLLRDHUP
    call epoll_mod_conn
    xor eax, eax
    pop r12
    pop rbx
    ret

.Lctw_err:
    mov rdi, r12
    call conn_close
    xor eax, eax
    pop r12
    pop rbx
    ret

# conn_process_rx(rdi=&conn) -> iteratively parses & dispatches queued HTTP requests
conn_process_rx:
    push rbx
    push r12
    mov r12, rdi

.Lcpr_loop:
    mov rdi, [r12 + CONN_RX_PTR]
    mov rsi, [r12 + CONN_RX_LEN]
    lea rdx, [rip + cur_req]
    call http_parse_request
    test rax, rax
    jz .Lcpr_need_more
    js .Lcpr_parse_err

    # rax = consumed bytes
    mov rbx, rax
    mov rcx, [r12 + CONN_RX_LEN]
    sub rcx, rbx
    mov [r12 + CONN_RX_LEN], rcx
    mov eax, [r12 + CONN_PEER_IP]
    mov [rip + cur_req + REQ_PEER_IP], eax
    mov rax, [rip + cur_req + REQ_KEEP_ALIVE]
    mov [r12 + CONN_KEEP_ALIVE], rax
    xor eax, eax
    cmp qword ptr [rip + cur_req + REQ_METHOD], METH_HEAD
    sete al
    mov [r12 + CONN_IS_HEAD], rax

    push rbx
    push rcx
    mov rdi, r12
    lea rsi, [rip + cur_req]
    call router_dispatch
    pop rcx
    pop rbx

    # Shift leftover bytes now that handler finished reading cur_req
    test rcx, rcx
    jz .Lcpr_send
    mov rdi, [r12 + CONN_RX_PTR]
    lea rsi, [rdi + rbx]
    mov rdx, rcx
    call xmemcpy
.Lcpr_send:
    mov rdi, r12
    call conn_try_write
    test eax, eax
    jnz .Lcpr_loop
    pop r12
    pop rbx
    ret

.Lcpr_parse_err:
    mov qword ptr [r12 + CONN_KEEP_ALIVE], 0
    mov qword ptr [r12 + CONN_RX_LEN], 0
    cmp rax, -413
    je .Lcpr_413
    cmp rax, -414
    je .Lcpr_414
    mov rdi, r12; lea rsi, [rip + st_400]; lea rdx, [rip + err_400_msg]; call http_send_error
    jmp .Lcpr_send
.Lcpr_413:
    mov rdi, r12; lea rsi, [rip + st_413]; lea rdx, [rip + err_413_msg]; call http_send_error
    jmp .Lcpr_send
.Lcpr_414:
    mov rdi, r12; lea rsi, [rip + st_414]; lea rdx, [rip + err_414_msg]; call http_send_error
    jmp .Lcpr_send

.Lcpr_need_more:
    mov rdi, r12
    mov esi, EPOLLIN | EPOLLRDHUP
    call epoll_mod_conn
    pop r12
    pop rbx
    ret

# conn_on_read(rdi=&conn)
conn_on_read:
    push r12
    mov r12, rdi
.Lcor_loop:
    mov rax, CONN_RX_CAP
    sub rax, [r12 + CONN_RX_LEN]
    jbe .Lcor_overflow
    mov rdi, [r12 + CONN_FD]
    mov rsi, [r12 + CONN_RX_PTR]
    add rsi, [r12 + CONN_RX_LEN]
    mov rdx, rax
    call sys_read
    cmp rax, -EINTR
    je .Lcor_loop
    cmp rax, -EAGAIN
    je .Lcor_parse
    test rax, rax
    jle .Lcor_close
    add [r12 + CONN_RX_LEN], rax
    call mono_sec
    mov [r12 + CONN_LAST_ACTIVE], rax
    # Try parsing immediately once we have bytes
.Lcor_parse:
    cmp qword ptr [r12 + CONN_RX_LEN], 0
    je .Lcor_done
    mov rdi, r12
    call conn_process_rx
    pop r12
    ret
.Lcor_overflow:
    mov qword ptr [r12 + CONN_KEEP_ALIVE], 0
    mov rdi, r12; lea rsi, [rip + st_413]; lea rdx, [rip + err_413_msg]; call http_send_error
    mov rdi, r12; call conn_try_write
    pop r12
    ret
.Lcor_close:
    mov rdi, r12
    call conn_close
.Lcor_done:
    pop r12
    ret

# accept_pending() -> drains listen_fd
accept_pending:
    push rbx
    sub rsp, 40           # [rsp+0..15]=sockaddr_in, [rsp+16..19]=addrlen, [rsp+24..35]=epoll_event
.Lap_loop:
    mov dword ptr [rsp + 16], 16
    mov rdi, [rip + g_listen_fd]
    mov rsi, rsp
    lea rdx, [rsp + 16]
    mov ecx, SOCK_NONBLOCK | SOCK_CLOEXEC
    call sys_accept4
    cmp rax, -EINTR
    je .Lap_loop
    test rax, rax
    js .Lap_done
    mov rbx, rax          # client_fd
    mov rdi, rbx
    mov esi, [rsp + 4]    # peer IPv4
    call conn_alloc
    test rax, rax
    jz .Lap_full
    # Register in epoll
    mov dword ptr [rsp + 24], EPOLLIN | EPOLLRDHUP
    mov [rsp + 28], rax
    mov rdi, [rip + g_epoll_fd]
    mov esi, EPOLL_CTL_ADD
    mov rdx, rbx
    lea rcx, [rsp + 24]
    call sys_epoll_ctl
    test rax, rax
    jns .Lap_loop
    # epoll_ctl failed -> close
    mov rdi, [rsp + 28]
    call conn_close
    jmp .Lap_loop
.Lap_full:
    mov rdi, rbx
    call sys_close
    jmp .Lap_loop
.Lap_done:
    add rsp, 40
    pop rbx
    ret

# sweep_idle_conns() -> closes connections idle > IDLE_TIMEOUT_SEC
sweep_idle_conns:
    push rbx
    push r12
    call mono_sec
    mov r12, rax
    xor ebx, ebx
.Lsic_loop:
    cmp ebx, MAX_CONNS
    jae .Lsic_done
    imul rax, rbx, CONN_SIZE
    lea r8, [rip + conns]
    add r8, rax
    cmp qword ptr [r8 + CONN_FD], -1
    je .Lsic_next
    mov rcx, r12
    sub rcx, [r8 + CONN_LAST_ACTIVE]
    cmp rcx, IDLE_TIMEOUT_SEC
    jl .Lsic_next
    mov rdi, r8
    call conn_close
.Lsic_next:
    inc ebx
    jmp .Lsic_loop
.Lsic_done:
    pop r12
    pop rbx
    ret

# setup_signals() -> ignore SIGPIPE, block SIGINT/SIGTERM/SIGHUP into signalfd4
setup_signals:
    sub rsp, 48
    # Ignore SIGPIPE via rt_sigaction(SIGPIPE, {handler=SIG_IGN, 0, 0, 0}, NULL, 8)
    mov qword ptr [rsp + 0], SIG_IGN
    mov qword ptr [rsp + 8], 0
    mov qword ptr [rsp + 16], 0
    mov qword ptr [rsp + 24], 0
    mov edi, SIGPIPE
    mov rsi, rsp
    xor edx, edx
    mov ecx, 8
    call sys_rt_sigaction

    # Mask bits for SIGHUP(1), SIGINT(2), SIGTERM(15): (1<<0)|(1<<1)|(1<<14) = 0x4003
    mov qword ptr [rsp + 32], 0x4003
    mov edi, SIG_BLOCK
    lea rsi, [rsp + 32]
    xor edx, edx
    mov ecx, 8
    call sys_rt_sigprocmask

    mov edi, -1
    lea rsi, [rsp + 32]
    mov edx, 8
    mov ecx, SFD_NONBLOCK | SFD_CLOEXEC
    call sys_signalfd4
    mov [rip + g_sig_fd], rax
    add rsp, 48
    ret

# setup_inotify() -> watches content/posts and themes/<theme>
setup_inotify:
    sub rsp, 32
    mov edi, IN_NONBLOCK | IN_CLOEXEC
    call sys_inotify_init1
    mov [rip + g_inotify_fd], rax
    test rax, rax
    js .Lsin_done

    mov rdi, rax
    lea rsi, [rip + w_posts_dir]
    mov edx, IN_WATCH_MASK
    call sys_inotify_add_watch

    # Build "themes/<theme>\0"
    mov rdi, rsp; lea rsi, [rip + inotify_th_path]; mov edx, 255; call sb_init
    mov rdi, rsp; lea rsi, [rip + w_themes_pre]; mov edx, 7; call sb_mem
    mov rdi, rsp; lea rsi, [rip + g_cfg_theme]; mov rdx, [rip + g_cfg_theme_len]; call sb_mem
    mov rdi, rsp; xor esi, esi; call sb_byte

    mov rdi, [rip + g_inotify_fd]
    lea rsi, [rip + inotify_th_path]
    mov edx, IN_WATCH_MASK
    call sys_inotify_add_watch
.Lsin_done:
    add rsp, 32
    ret

# server_run() -> main event loop entry point, returns 0 on graceful shutdown, 1 on bind err
.globl server_run
server_run:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 64           # [rsp+0..15]=sockaddr_in, [rsp+16..19]=optval, [rsp+24..35]=epoll_event, [rsp+40..63]=port sb

    call mono_sec
    mov [rip + g_start_sec], rax
    call conn_init_pool
    call setup_signals
    call setup_inotify

    # Create listening TCP socket
    mov edi, AF_INET
    mov esi, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC
    xor edx, edx
    call sys_socket
    test rax, rax
    js .Lsr_bind_fail
    mov [rip + g_listen_fd], rax

    # SO_REUSEADDR, SO_REUSEPORT, TCP_NODELAY (eliminates Nagle 40ms sendfile stall), TCP_DEFER_ACCEPT
    mov dword ptr [rsp + 16], 1
    mov rdi, [rip + g_listen_fd]
    mov esi, SOL_SOCKET
    mov edx, SO_REUSEADDR
    lea rcx, [rsp + 16]
    mov r8d, 4
    call sys_setsockopt

    mov rdi, [rip + g_listen_fd]
    mov esi, SOL_SOCKET
    mov edx, SO_REUSEPORT
    lea rcx, [rsp + 16]
    mov r8d, 4
    call sys_setsockopt

    mov rdi, [rip + g_listen_fd]
    mov esi, IPPROTO_TCP
    mov edx, TCP_NODELAY
    lea rcx, [rsp + 16]
    mov r8d, 4
    call sys_setsockopt

    mov dword ptr [rsp + 16], 3
    mov rdi, [rip + g_listen_fd]
    mov esi, IPPROTO_TCP
    mov edx, TCP_DEFER_ACCEPT
    lea rcx, [rsp + 16]
    mov r8d, 4
    call sys_setsockopt

    # sockaddr_in
    mov qword ptr [rsp + 0], 0
    mov qword ptr [rsp + 8], 0
    mov word ptr [rsp + 0], AF_INET
    mov rax, [rip + g_cfg_port]
    rol ax, 8             # htons
    mov word ptr [rsp + 2], ax

    mov rdi, [rip + g_listen_fd]
    mov rsi, rsp
    mov edx, 16
    call sys_bind
    test rax, rax
    js .Lsr_bind_fail

    mov rdi, [rip + g_listen_fd]
    mov esi, 512
    call sys_listen
    test rax, rax
    js .Lsr_bind_fail

    # Create epoll instance
    mov edi, EPOLL_CLOEXEC
    call sys_epoll_create1
    test rax, rax
    js .Lsr_bind_fail
    mov [rip + g_epoll_fd], rax

    # Add listen_fd
    mov dword ptr [rsp + 24], EPOLLIN
    mov qword ptr [rsp + 28], EPOLL_TAG_LISTEN
    mov rdi, [rip + g_epoll_fd]
    mov esi, EPOLL_CTL_ADD
    mov rdx, [rip + g_listen_fd]
    lea rcx, [rsp + 24]
    call sys_epoll_ctl

    # Add sig_fd
    cmp qword ptr [rip + g_sig_fd], 0
    jl .Lsr_add_ino
    mov dword ptr [rsp + 24], EPOLLIN
    mov qword ptr [rsp + 28], EPOLL_TAG_SIGNAL
    mov rdi, [rip + g_epoll_fd]
    mov esi, EPOLL_CTL_ADD
    mov rdx, [rip + g_sig_fd]
    lea rcx, [rsp + 24]
    call sys_epoll_ctl

.Lsr_add_ino:
    cmp qword ptr [rip + g_inotify_fd], 0
    jl .Lsr_log_up
    mov dword ptr [rsp + 24], EPOLLIN
    mov qword ptr [rsp + 28], EPOLL_TAG_INOTIFY
    mov rdi, [rip + g_epoll_fd]
    mov esi, EPOLL_CTL_ADD
    mov rdx, [rip + g_inotify_fd]
    lea rcx, [rsp + 24]
    call sys_epoll_ctl

.Lsr_log_up:
    lea rdi, [rip + log_start_1]; call log_cstr
    lea rdi, [rsp + 40]; lea rsi, [rip + inotify_th_path]; mov edx, 31; call sb_init
    lea rdi, [rsp + 40]; mov rsi, [rip + g_cfg_port]; call sb_uint
    lea rdi, [rip + inotify_th_path]; mov rsi, [rsp + 40 + SB_LEN]; call log_slice
    lea rdi, [rip + log_start_2]; call log_cstr

    mov qword ptr [rip + g_running], 1
    call mono_sec
    mov r15, rax          # last sweep sec

.Lsr_loop:
    cmp qword ptr [rip + g_running], 0
    je .Lsr_shutdown

    mov rdi, [rip + g_epoll_fd]
    lea rsi, [rip + epoll_events]
    mov edx, 64
    mov ecx, 1000         # 1s timeout for periodic idle sweep
    call sys_epoll_wait
    cmp rax, -EINTR
    je .Lsr_loop
    test rax, rax
    js .Lsr_shutdown

    mov r12, rax          # nfds
    xor r13d, r13d        # i
.Lsr_ev:
    cmp r13, r12
    jae .Lsr_sweep
    imul rax, r13, 12
    lea r8, [rip + epoll_events]
    mov ebx, [r8 + rax + 0]     # events
    mov r14, [r8 + rax + 4]     # data (tag or &conn)

    cmp r14, EPOLL_TAG_LISTEN
    je .Lsr_ev_listen
    cmp r14, EPOLL_TAG_SIGNAL
    je .Lsr_ev_signal
    cmp r14, EPOLL_TAG_INOTIFY
    je .Lsr_ev_inotify

    # Connection event (r14 = &conn)
    cmp qword ptr [r14 + CONN_FD], -1
    je .Lsr_ev_next
    test ebx, EPOLLERR | EPOLLHUP
    jnz .Lsr_ev_close
    test ebx, EPOLLOUT
    jz .Lsr_ev_chk_in
    mov rdi, r14
    call conn_try_write
    test eax, eax
    jz .Lsr_ev_next
    mov rdi, r14
    call conn_process_rx
    jmp .Lsr_ev_next
.Lsr_ev_chk_in:
    test ebx, EPOLLIN
    jz .Lsr_ev_chk_rdhup
    mov rdi, r14
    call conn_on_read
    jmp .Lsr_ev_next
.Lsr_ev_chk_rdhup:
    test ebx, EPOLLRDHUP
    jz .Lsr_ev_next
.Lsr_ev_close:
    mov rdi, r14
    call conn_close
    jmp .Lsr_ev_next

.Lsr_ev_listen:
    call accept_pending
    jmp .Lsr_ev_next

.Lsr_ev_signal:
    mov rdi, [rip + g_sig_fd]
    lea rsi, [rip + sig_read_buf]
    mov edx, 128
    call sys_read
    cmp rax, 128
    jne .Lsr_ev_next
    mov eax, [rip + sig_read_buf]   # ssi_signo
    cmp eax, SIGHUP
    je .Lsr_do_sighup
    mov qword ptr [rip + g_running], 0
    jmp .Lsr_ev_next
.Lsr_do_sighup:
    lea rdi, [rip + log_sighup]; call log_cstr
    call store_reload
    jmp .Lsr_ev_next

.Lsr_ev_inotify:
    # Drain all pending inotify events, then reload once
    xor ebx, ebx
.Lsr_ino_drain:
    mov rdi, [rip + g_inotify_fd]
    lea rsi, [rip + inotify_buf]
    mov edx, 4096
    call sys_read
    test rax, rax
    jle .Lsr_ino_done
    mov ebx, 1
    jmp .Lsr_ino_drain
.Lsr_ino_done:
    test ebx, ebx
    jz .Lsr_ev_next
    lea rdi, [rip + log_inotify]; call log_cstr
    call store_reload
    jmp .Lsr_ev_next

.Lsr_ev_next:
    inc r13
    jmp .Lsr_ev

.Lsr_sweep:
    call mono_sec
    mov rcx, rax
    sub rcx, r15
    cmp rcx, 5
    jl .Lsr_loop
    mov r15, rax
    call sweep_idle_conns
    jmp .Lsr_loop

.Lsr_shutdown:
    # Close all active connections & server FDs
    xor ebx, ebx
.Lsr_cl_conns:
    cmp ebx, MAX_CONNS
    jae .Lsr_cl_fds
    imul rax, rbx, CONN_SIZE
    lea rdi, [rip + conns]
    add rdi, rax
    cmp qword ptr [rdi + CONN_FD], -1
    je .Lsr_cl_next
    call conn_close
.Lsr_cl_next:
    inc ebx
    jmp .Lsr_cl_conns
.Lsr_cl_fds:
    mov rdi, [rip + g_listen_fd];  cmp rdi, 0; jl 1f; call sys_close
1:  mov rdi, [rip + g_sig_fd];     cmp rdi, 0; jl 2f; call sys_close
2:  mov rdi, [rip + g_inotify_fd]; cmp rdi, 0; jl 3f; call sys_close
3:  mov rdi, [rip + g_epoll_fd];   cmp rdi, 0; jl 4f; call sys_close
4:  lea rdi, [rip + log_stop]; call log_cstr
    xor eax, eax
    jmp .Lsr_ret

.Lsr_bind_fail:
    lea rdi, [rip + log_bind_err]; call log_cstr
    mov eax, 1
.Lsr_ret:
    add rsp, 64
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
