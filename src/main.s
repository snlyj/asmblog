.include "defs.inc"

# ELF entry point (_start) — zero libc, pure Linux x86-64 kernel ABI
# On Linux process entry:
#   [rsp]      = argc
#   [rsp + 8]  = argv[0]
#   ...
.section .text
.globl _start
_start:
    xor ebp, ebp
    mov rdi, [rsp]          # argc
    lea rsi, [rsp + 8]      # argv
    and rsp, -16            # ensure 16-byte stack alignment
    call cli_main
    mov rdi, rax
    call sys_exit_group
