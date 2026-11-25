# AsmBlog x86-64 Linux ABI constants & struct layouts
.intel_syntax noprefix

# --- Linux x86-64 syscall numbers ---
.equ SYS_read,              0
.equ SYS_write,             1
.equ SYS_open,              2
.equ SYS_close,             3
.equ SYS_stat,              4
.equ SYS_fstat,             5
.equ SYS_lstat,             6
.equ SYS_mmap,              9
.equ SYS_munmap,            11
.equ SYS_rt_sigaction,      13
.equ SYS_rt_sigprocmask,    14
.equ SYS_writev,            20
.equ SYS_sendfile,          40
.equ SYS_socket,            41
.equ SYS_accept,            43
.equ SYS_bind,              49
.equ SYS_listen,            50
.equ SYS_setsockopt,        54
.equ SYS_fork,              57
.equ SYS_exit,              60
.equ SYS_wait4,             61
.equ SYS_kill,              62
.equ SYS_fcntl,             72
.equ SYS_chdir,             80
.equ SYS_rename,            82
.equ SYS_mkdir,             83
.equ SYS_unlink,            87
.equ SYS_getdents64,        217
.equ SYS_clock_gettime,     228
.equ SYS_exit_group,        231
.equ SYS_epoll_wait,        232
.equ SYS_epoll_ctl,         233
.equ SYS_inotify_add_watch, 254
.equ SYS_openat,            257
.equ SYS_mkdirat,           258
.equ SYS_newfstatat,        262
.equ SYS_unlinkat,          263
.equ SYS_accept4,           288
.equ SYS_signalfd4,         289
.equ SYS_epoll_create1,     291
.equ SYS_inotify_init1,     294
.equ SYS_getrandom,         318

# --- Open / FD / Socket / Epoll flags ---
.equ AT_FDCWD,              -100
.equ O_RDONLY,              0
.equ O_WRONLY,              1
.equ O_RDWR,                2
.equ O_CREAT,               0x40
.equ O_TRUNC,               0x200
.equ O_APPEND,              0x400
.equ O_NONBLOCK,            0x800
.equ O_DIRECTORY,           0x10000
.equ O_NOFOLLOW,            0x20000
.equ O_CLOEXEC,             0x80000

.equ AF_INET,               2
.equ SOCK_STREAM,           1
.equ SOCK_NONBLOCK,         0x800
.equ SOCK_CLOEXEC,          0x80000
.equ SOL_SOCKET,            1
.equ SO_REUSEADDR,          2
.equ SO_REUSEPORT,          15
.equ IPPROTO_TCP,           6
.equ TCP_NODELAY,           1
.equ TCP_DEFER_ACCEPT,      9

.equ EPOLL_CLOEXEC,         0x80000
.equ EPOLL_CTL_ADD,         1
.equ EPOLL_CTL_DEL,         2
.equ EPOLL_CTL_MOD,         3
.equ EPOLLIN,               0x1
.equ EPOLLOUT,              0x4
.equ EPOLLERR,              0x8
.equ EPOLLHUP,              0x10
.equ EPOLLRDHUP,            0x2000

.equ SFD_NONBLOCK,          0x800
.equ SFD_CLOEXEC,           0x80000
.equ IN_NONBLOCK,           0x800
.equ IN_CLOEXEC,            0x80000
.equ IN_CLOSE_WRITE,        0x8
.equ IN_MOVED_FROM,         0x40
.equ IN_MOVED_TO,           0x80
.equ IN_CREATE,             0x100
.equ IN_DELETE,             0x200
.equ IN_WATCH_MASK,         0x3c8

.equ SIG_BLOCK,             0
.equ SIGHUP,                1
.equ SIGINT,                2
.equ SIGPIPE,               13
.equ SIGTERM,               15
.equ SIG_IGN,               1

.equ PROT_READ,             1
.equ PROT_WRITE,            2
.equ MAP_PRIVATE,           0x2
.equ MAP_ANONYMOUS,         0x20

.equ CLOCK_REALTIME,        0
.equ CLOCK_MONOTONIC,       1

.equ EAGAIN,                11
.equ EINTR,                 4

# --- struct stat offsets (Linux x86_64, 144 bytes) ---
.equ STAT_SIZE_STRUCT,      144
.equ STAT_INO,              8
.equ STAT_MODE,             24
.equ STAT_SIZE,             48
.equ STAT_MTIME,            88
.equ S_IFMT,                0xf000
.equ S_IFREG,               0x8000
.equ S_IFDIR,               0x4000

# --- HTTP Method IDs ---
.equ METH_UNKNOWN,          0
.equ METH_GET,              1
.equ METH_HEAD,             2
.equ METH_POST,             3
.equ METH_PUT,              4
.equ METH_DELETE,           5
.equ METH_OPTIONS,          6

# --- sbuf_t (24 bytes): safe bounded byte buffer ---
.equ SB_PTR,                0
.equ SB_LEN,                8
.equ SB_CAP,                16
.equ SB_SIZE,               24

# --- Capacity limits ---
.equ MAX_CONNS,             128
.equ CONN_RX_CAP,           4194304   # 4 MiB read buf (demand-paged: 0 RAM when idle; supports full-res original uploads)
.equ CONN_TX_CAP,           262144    # 256 KiB write buf per conn (demand paged!)
.equ MAX_HDR_BYTES,         8192
.equ MAX_URI_BYTES,         2048
.equ MAX_BODY_BYTES,        4000000   # ~3.8 MiB max upload/post body
.equ IDLE_TIMEOUT_SEC,      30

.equ ARENA_SIZE,            16777216  # 16 MiB mmap arena for posts/html/templates
.equ MAX_POSTS,             512
.equ MAX_TAGS,              256
.equ MAX_CATEGORIES,        64
.equ MAX_TEMPLATES,         24
.equ MAX_POST_TAGS,         8

# --- conn_t (128 bytes) ---
.equ CONN_FD,               0         # i64 (-1 if unused)
.equ CONN_STATE,            8         # u64 (0=FREE, 1=READ, 2=WRITE)
.equ CONN_RX_PTR,           16        # u64
.equ CONN_RX_LEN,           24        # u64
.equ CONN_TX_PTR,           32        # u64
.equ CONN_TX_LEN,           40        # u64
.equ CONN_TX_OFF,           48        # u64
.equ CONN_FILE_FD,          56        # i64 (-1 if no sendfile)
.equ CONN_FILE_OFF,         64        # i64
.equ CONN_FILE_REM,         72        # u64
.equ CONN_KEEP_ALIVE,       80        # u64
.equ CONN_LAST_ACTIVE,      88        # i64 (monotonic sec)
.equ CONN_PEER_IP,          96        # u32 (network byte order IPv4)
.equ CONN_IS_HEAD,          104       # u64 (1 if HEAD request)
.equ CONN_SIZE,             128

# --- req_t (256 bytes): parsed HTTP request ---
.equ REQ_METHOD,            0         # u64
.equ REQ_PATH_PTR,          8
.equ REQ_PATH_LEN,          16
.equ REQ_QUERY_PTR,         24
.equ REQ_QUERY_LEN,         32
.equ REQ_BODY_PTR,          40
.equ REQ_BODY_LEN,          48
.equ REQ_PARAM_PTR,         56        # captured :slug / :name / *path
.equ REQ_PARAM_LEN,         64
.equ REQ_ETAG_PTR,          72        # If-None-Match value
.equ REQ_ETAG_LEN,          80
.equ REQ_AUTH_PTR,          88        # Authorization header value
.equ REQ_AUTH_LEN,          96
.equ REQ_COOKIE_PTR,        104       # Cookie header value
.equ REQ_COOKIE_LEN,        112
.equ REQ_KEEP_ALIVE,        120       # u64 (1 or 0)
.equ REQ_HDR_LEN,           128       # u64
.equ REQ_CONTENT_LEN,       136       # u64
.equ REQ_PEER_IP,           144       # u32
.equ REQ_HTTPS,             152       # u64 (1 if X-Forwarded-Proto: https)
.equ REQ_RANGE_PTR,         160       # Range header value (e.g. "bytes=0-1023")
.equ REQ_RANGE_LEN,         168
.equ REQ_SIZE,              256

# --- post_t (320 bytes) ---
.equ POST_TITLE_PTR,        0
.equ POST_TITLE_LEN,        8
.equ POST_SLUG_PTR,         16
.equ POST_SLUG_LEN,         24
.equ POST_DATE_PTR,         32
.equ POST_DATE_LEN,         40
.equ POST_SUMMARY_PTR,      48
.equ POST_SUMMARY_LEN,      56
.equ POST_MD_PTR,           64
.equ POST_MD_LEN,           72
.equ POST_HTML_PTR,         80
.equ POST_HTML_LEN,         88
.equ POST_TAGS_RAW_PTR,     96
.equ POST_TAGS_RAW_LEN,     104
.equ POST_MTIME,            112
.equ POST_DRAFT,            120       # u64 (1 if draft)
.equ POST_TAG_COUNT,        128       # u64 (0..8)
.equ POST_TAG_PTRS,         136       # 8 * 8 = 64 bytes (136..199)
.equ POST_TAG_LENS,         200       # 8 * 8 = 64 bytes (200..263)
.equ POST_WORD_COUNT,       264       # u64 (approx char/word count)
.equ POST_READ_MIN,         272       # u64 (estimated reading minutes)
.equ POST_COVER_PTR,        280       # optional cover image URL
.equ POST_COVER_LEN,        288
.equ POST_CAT_PTR,          296       # optional category name
.equ POST_CAT_LEN,          304
.equ POST_SIZE,             320

# --- tag_t / cat_t (24 bytes) ---
.equ TAG_NAME_PTR,          0
.equ TAG_NAME_LEN,          8
.equ TAG_COUNT,             16
.equ TAG_SIZE,              24
.equ CAT_NAME_PTR,          0
.equ CAT_NAME_LEN,          8
.equ CAT_COUNT,             16
.equ CAT_SIZE,              24

# --- tpl_file_t (32 bytes) ---
.equ TPL_NAME_PTR,          0
.equ TPL_NAME_LEN,          8
.equ TPL_DATA_PTR,          16
.equ TPL_DATA_LEN,          24
.equ TPL_SIZE,              32

# --- tpl_var_t (32 bytes): key/val binding for template context ---
.equ TV_KEY_PTR,            0
.equ TV_KEY_LEN,            8
.equ TV_VAL_PTR,            16
.equ TV_VAL_LEN,            24
.equ TV_SIZE,               32

# --- tpl_ctx_t (96 bytes) ---
.equ TCTX_VARS_PTR,         0         # ptr to tpl_var_t array
.equ TCTX_VARS_CNT,         8         # u64
.equ TCTX_SEC_CB,           16        # fn(sec_name_ptr, sec_name_len, body_ptr, body_len, inverted, out_sb, user_ptr) -> rax (1 if handled)
.equ TCTX_USER_PTR,         24        # opaque user ptr passed to callback
.equ TCTX_DEPTH,            32        # recursion depth guard
.equ TCTX_SIZE,             64

# --- route_t (40 bytes) ---
.equ RT_METHOD,             0
.equ RT_PAT_PTR,            8
.equ RT_PAT_LEN,            16
.equ RT_HANDLER,            24
.equ RT_FLAGS,              32
.equ RT_SIZE,               40

# --- Special epoll data tags ---
.equ EPOLL_TAG_LISTEN,      0x10000001
.equ EPOLL_TAG_SIGNAL,      0x10000002
.equ EPOLL_TAG_INOTIFY,     0x10000003
