.include "defs.inc"

# Pure x86-64 FIPS 180-4 SHA-256 + Constant-Time Memory Compare
# Used exclusively for single-author /studio passphrase verification.

.section .rodata
.align 4
sha256_k:
    .long 0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5
    .long 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174
    .long 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da
    .long 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967
    .long 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85
    .long 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070
    .long 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3
    .long 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2

sha256_iv:
    .long 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a
    .long 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19

.section .text

# sha256_compress(rdi=state_8u32, rsi=block_64bytes)
sha256_compress:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 296          # [rsp..255]=W[64] (256B), [rsp+256]=state_ptr, [rsp+264..295]=a..h

    mov [rsp + 256], rdi
    xor ecx, ecx
.Lsc_loadw:
    cmp ecx, 16
    jae .Lsc_expw
    mov eax, [rsi + rcx*4]
    bswap eax
    mov [rsp + rcx*4], eax
    inc ecx
    jmp .Lsc_loadw

.Lsc_expw:
    cmp ecx, 64
    jae .Lsc_init
    # s0 = ror(w[i-15],7) ^ ror(w[i-15],18) ^ (w[i-15]>>3)
    mov eax, [rsp + rcx*4 - 60]
    mov edx, eax
    mov r8d, eax
    ror eax, 7
    ror edx, 18
    shr r8d, 3
    xor eax, edx
    xor eax, r8d
    # s1 = ror(w[i-2],17) ^ ror(w[i-2],19) ^ (w[i-2]>>10)
    mov r9d, [rsp + rcx*4 - 8]
    mov r10d, r9d
    mov r11d, r9d
    ror r9d, 17
    ror r10d, 19
    shr r11d, 10
    xor r9d, r10d
    xor r9d, r11d
    add eax, [rsp + rcx*4 - 64]
    add eax, [rsp + rcx*4 - 28]
    add eax, r9d
    mov [rsp + rcx*4], eax
    inc ecx
    jmp .Lsc_expw

.Lsc_init:
    mov rdi, [rsp + 256]
    mov r8d,  [rdi + 0]   # a
    mov r9d,  [rdi + 4]   # b
    mov r10d, [rdi + 8]   # c
    mov r11d, [rdi + 12]  # d
    mov r12d, [rdi + 16]  # e
    mov r13d, [rdi + 20]  # f
    mov r14d, [rdi + 24]  # g
    mov r15d, [rdi + 28]  # h

    lea rbx, [rip + sha256_k]
    xor ecx, ecx
.Lsc_round:
    cmp ecx, 64
    jae .Lsc_add
    # S1 = ror(e,6) ^ ror(e,11) ^ ror(e,25)
    mov eax, r12d
    mov edx, r12d
    mov esi, r12d
    ror eax, 6
    ror edx, 11
    ror esi, 25
    xor eax, edx
    xor eax, esi
    # ch = (e & f) ^ (~e & g)
    mov edx, r12d
    and edx, r13d
    mov esi, r12d
    not esi
    and esi, r14d
    xor edx, esi
    # t1 = h + S1 + ch + k[i] + w[i]
    add eax, r15d
    add eax, edx
    add eax, [rbx + rcx*4]
    add eax, [rsp + rcx*4]
    mov edi, eax          # edi = t1

    # S0 = ror(a,2) ^ ror(a,13) ^ ror(a,22)
    mov eax, r8d
    mov edx, r8d
    mov esi, r8d
    ror eax, 2
    ror edx, 13
    ror esi, 22
    xor eax, edx
    xor eax, esi
    # maj = (a&b) ^ (a&c) ^ (b&c)
    mov edx, r8d
    and edx, r9d
    mov esi, r8d
    and esi, r10d
    xor edx, esi
    mov esi, r9d
    and esi, r10d
    xor edx, esi
    add eax, edx          # eax = t2

    mov r15d, r14d        # h = g
    mov r14d, r13d        # g = f
    mov r13d, r12d        # f = e
    lea r12d, [r11d + edi]# e = d + t1
    mov r11d, r10d        # d = c
    mov r10d, r9d         # c = b
    mov r9d,  r8d         # b = a
    lea r8d,  [edi + eax] # a = t1 + t2
    inc ecx
    jmp .Lsc_round

.Lsc_add:
    mov rdi, [rsp + 256]
    add [rdi + 0],  r8d
    add [rdi + 4],  r9d
    add [rdi + 8],  r10d
    add [rdi + 12], r11d
    add [rdi + 16], r12d
    add [rdi + 20], r13d
    add [rdi + 24], r14d
    add [rdi + 28], r15d

    add rsp, 296
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

# sha256_hex(rdi=msg_ptr, rsi=msg_len, rdx=out_64_hex_buf)
.globl sha256_hex
sha256_hex:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    # [rsp+0..31]   state (32B)
    # [rsp+32..95]  pad block (64B)
    # [rsp+96..127] digest bytes (32B)
    # [rsp+128..151] sbuf (24B)
    sub rsp, 160

    mov r12, rdi          # msg_ptr
    mov r13, rsi          # msg_len
    mov r14, rdx          # out_hex_buf

    # Init state from IV
    mov rdi, rsp
    lea rsi, [rip + sha256_iv]
    mov edx, 32
    call xmemcpy

    # Process full 64-byte blocks
    mov rbx, r12
    mov r15, r13
.Lsh_full:
    cmp r15, 64
    jb .Lsh_tail
    mov rdi, rsp
    mov rsi, rbx
    call sha256_compress
    add rbx, 64
    sub r15, 64
    jmp .Lsh_full

.Lsh_tail:
    # Zero pad block
    lea rdi, [rsp + 32]
    xor esi, esi
    mov edx, 64
    call xmemset
    # Copy remaining bytes
    lea rdi, [rsp + 32]
    mov rsi, rbx
    mov rdx, r15
    call xmemcpy
    mov byte ptr [rsp + 32 + r15], 0x80
    cmp r15, 56
    jb .Lsh_putlen
    # Need an extra block
    mov rdi, rsp
    lea rsi, [rsp + 32]
    call sha256_compress
    lea rdi, [rsp + 32]
    xor esi, esi
    mov edx, 64
    call xmemset
.Lsh_putlen:
    mov rax, r13
    shl rax, 3            # bit length
    bswap rax
    mov [rsp + 32 + 56], rax
    mov rdi, rsp
    lea rsi, [rsp + 32]
    call sha256_compress

    # Convert 8 u32 state words to big-endian 32 bytes
    xor ecx, ecx
.Lsh_be:
    cmp ecx, 8
    jae .Lsh_tohex
    mov eax, [rsp + rcx*4]
    bswap eax
    mov [rsp + 96 + rcx*4], eax
    inc ecx
    jmp .Lsh_be

.Lsh_tohex:
    lea rdi, [rsp + 128]
    mov rsi, r14
    mov edx, 64
    call sb_init
    lea rdi, [rsp + 128]
    lea rsi, [rsp + 96]
    mov edx, 32
    call sb_hex

    add rsp, 160
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

# ct_memeq(rdi=a, rsi=b, rdx=len) -> rax=1 if equal else 0 (constant-time)
.globl ct_memeq
ct_memeq:
    xor eax, eax
    xor ecx, ecx
.Lct_loop:
    cmp rcx, rdx
    jae .Lct_done
    movzx r8d, byte ptr [rdi + rcx]
    movzx r9d, byte ptr [rsi + rcx]
    xor r8d, r9d
    or eax, r8d
    inc rcx
    jmp .Lct_loop
.Lct_done:
    test eax, eax
    sete al
    movzx eax, al
    ret
