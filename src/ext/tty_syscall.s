# src/ext/tty_syscall.s
    .text
    .globl  tty_syscall
    .type   tty_syscall, @function
tty_syscall:
    movq    %rdi, %rax
    movq    %rsi, %rdi
    movq    %rdx, %rsi
    movq    %rcx, %rdx
    movq    %r8,  %r10
    movq    %r9,  %r8
    movq    8(%rsp), %r9
    syscall
    ret
    .size   tty_syscall, .-tty_syscall
    .section .note.GNU-stack,"",@progbits
