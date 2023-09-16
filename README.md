brainfuck
=========
This repository contains an interpreter (`bf`) in x86_64 assembly for linux and
a compiler (`bfc`) in zig for x86_64 linux, both are a little bit optimized.

build
-----
Make sure to have `nasm` installed and run

    zig build -Doptimize=ReleaseSafe

executables will be at `zig-out/bin/`.

usage
-----
```console
    $ bf
    usage: bf file.bf

    $ bfc --help
    Usage: bfc [options] file
    Options:
      -h, --help       Print this help message.
      -v, --version    Print version information.
      -o <file>        Place the output into <file>.
      -S               Compile only, do not assemble or link.
      -c               Compile and assemble, but do not link.
      -g               Produce debugging information.
      -s               Strip the output file.
```
