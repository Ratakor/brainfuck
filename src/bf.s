; tiny brainfuck interpreter for x86_64 linux
; copywrong c) 2023 Ratakor
; compile with `nasm -f elf64 bf.s && ld -o bf bf.o`
; no check performed for matching [ / ]

bits 64
default rel

%define SYS_read  0x00
%define SYS_write 0x01
%define SYS_open  0x02
%define SYS_close 0x03
%define SYS_mmap  0x09
%define SYS_exit  0x3c

section .rodata
	max_codesize equ 32768 ; must be an integral multiple of the page size
	error_input_str db "usage: bf file.b", 0x0a
	error_input_str_len equ $ - error_input_str
	error_open_failed db "bf: failed to open file", 0x0a
	error_open_failed_len equ $ - error_open_failed

section .bss
	data resb 65536

section .text
global _start

_start:
	cmp dword [rsp], 2 ; exit with error if argc != 2
	je .has_args

	mov rsi, error_input_str_len
	mov rdi, error_input_str
	call die

.has_args:
	xor rsi, rsi ; O_RDONLY = 00
	mov rdi, [rsp + 8 + 8] ; argv[1] = filename
	mov rax, SYS_open
	syscall

	cmp rax, 0
	jge .open_success

	mov rsi, error_open_failed_len
	mov rdi, error_open_failed
	call die

.open_success:
	mov r13, rax ; r13 = fd
	xor r12, r12 ; r12 = data_idx = 0

	xor r9, r9; offset = 0
	mov r8, r13 ; fd
	mov r10, 0x02 ; flags = MAP_PRIVATE
	mov rdx, 0x1 ; prot = PROT_READ
	mov rsi, max_codesize ; length
	xor rdi, rdi ; addr = 0
	mov rax, SYS_mmap ; no munmap because rbp is used until exit
	syscall

	mov rbp, rax ; rbp = instructions
	mov bl, [rbp] ; bl = current instruction

	mov rdi, r13 ; fd
	mov rax, SYS_close
	syscall

.main_loop:
	; switch [instruction]

.case1: ; case '>'
	cmp bl, 0x3e
	jne .case2
	inc r12w ; data_idx++
	jmp .switch_end

.case2: ; case '<'
	cmp bl, 0x3c
	jne .case3
	dec r12w ; data_idx--
	jmp .switch_end

.case3: ; case '+'
	cmp bl, 0x2b
	jne .case4
	inc byte [data + r12] ; data[data_idx]++
	jmp .switch_end

.case4: ; case '-'
	cmp bl, 0x2d
	jne .case5
	dec byte [data + r12] ; data[data_idx]--
	jmp .switch_end

.case5: ; case '['
	cmp bl, 0x5b
	jne .case6
	cmp byte [data + r12], 0
	jne .case5.else ; data[data_idx] == 0
	mov rcx, 1 ; bracket_counter = 1
.case5.loop:
	inc rbp ; rbp = & next instruction
	mov bl, [rbp] ; bl = current instruction

	cmp bl, 0x5b ; '['
	jne .case5.loop.elseif
	inc rcx ; bracket_counter++
	jmp .case5.loop
.case5.loop.elseif:
	cmp bl, 0x5d ; ']'
	jne .case5.loop
	dec rcx ; bracket_counter--
	cmp rcx, 0
	je .switch_end ; if bracket_counter == 0 -> goto main loop
	jmp .case5.loop

.case5.else: ; data[data_idx] != 0
	sub rsp, 8 ; grow stack
	mov [rsp], rbp ; save address for matching ']'
	jmp .switch_end

.case6: ; case ']'
	cmp bl, 0x5d
	jne .case7
	cmp byte [data + r12], 0
	je .case6.else ; data[data_idx] != 0
	mov rbp, [rsp] ; get corresponding '[' from stack
	jmp .switch_end
.case6.else: ; data[data_idx] == 0
	add rsp, 8 ; discard saved instruction address
	jmp .switch_end

.case7: ; case '.'
	cmp bl, 0x2e
	jne .case8
	mov rdx, 1 ; count
	lea rsi, [data + r12] ; buf = &data[data_idx]
	mov rdi, 1 ; stdout fd = 1
	mov rax, SYS_write
	syscall
	jmp .switch_end

.case8: ; case ','
	cmp bl, 0x2c
	jne .switch_end
	mov rdx, 1 ; count
	lea rsi, [data + r12] ; buf = &data[data_idx]
	xor rdi, rdi ; stdin fd = 0
	mov rax, SYS_read
	syscall

.switch_end:
	inc rbp ; rbp = & next instruction
	mov bl, [rbp] ; bl = current instruction
	cmp bl, 0
	jne .main_loop ; while (instruction != 0)

	xor rdi, rdi ; status = 0
	mov rax, SYS_exit
	syscall

; print a message to stderr and exit
; rdi: string to print
; rsi: length of string
die:
	mov rdx, rsi ; count
	mov rsi, rdi ; buf
	mov rdi, 2 ; stderr fd = 2
	mov rax, SYS_write
	syscall

	mov rdi, 1 ; status
	mov rax, SYS_exit
	syscall
