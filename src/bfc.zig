//! brainfuck compiler for x86_64 Linux

const std = @import("std");
const eql = std.mem.eql;

const version = "0.1.0";
const usage =
    \\Usage: {s} [options] file
    \\Options:
    \\  -h, --help       Print this help message.
    \\  -v, --version    Print version information.
    \\  -o <file>        Place the output into <file>.
    \\  -S               Compile only, do not assemble or link.
    \\  -c               Compile and assemble, but do not link.
    \\  -s               Strip the output file.
    \\
;

const Stack = struct {
    stack: std.ArrayList(usize),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{ .stack = std.ArrayList(usize).init(allocator) };
    }

    pub fn deinit(self: *Self) void {
        self.stack.deinit();
    }

    pub fn push(self: *Self, val: usize) !void {
        try self.stack.append(val);
    }

    pub fn pop(self: *Self) ?usize {
        return self.stack.popOrNull();
    }

    pub fn isEmpty(self: *Self) bool {
        return self.stack.items.len == 0;
    }
};

fn die(status: u8, comptime fmt: []const u8, args: anytype) noreturn {
    const stderr = std.io.getStdErr().writer();
    stderr.print(fmt, args) catch {};
    std.os.exit(status);
}

fn unrollBasic(instruction: u8, reader: anytype, writer: anytype) !u8 {
    var counter: u16 = 1;
    var byte = try reader.readByte();

    while (true) {
        if (byte == instruction) {
            counter += 1;
        } else switch (byte) {
            '>', '<', '+', '-', '[', ']', '.', ',' => break,
            else => {},
        }
        byte = try reader.readByte();
    }

    if (counter == 1) {
        switch (instruction) {
            '>' => try writer.writeAll("    inc r12w\n"),
            '<' => try writer.writeAll("    dec r12w\n"),
            '+' => try writer.writeAll("    inc byte [data + r12]\n"),
            '-' => try writer.writeAll("    dec byte [data + r12]\n"),
            else => unreachable,
        }
    } else {
        switch (instruction) {
            '>' => try writer.print("    add r12w, 0x{x:0>4}\n", .{counter}),
            '<' => try writer.print("    sub r12w, 0x{x:0>4}\n", .{counter}),
            '+' => try writer.print("    add byte [data + r12], 0x{x:0>2}\n", .{counter}),
            '-' => try writer.print("    sub byte [data + r12], 0x{x:0>2}\n", .{counter}),
            else => unreachable,
        }
    }

    return byte;
}

pub fn main() !void {
    var null_input_filename: ?[]const u8 = null;
    var output_filename: []const u8 = "a.out"[0..];
    var Sflag = false;
    var cflag = false;
    var sflag = false;
    var oflag = false;

    const cwd = std.fs.cwd();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    const progname = args.next().?;
    while (args.next()) |arg| {
        if (eql(u8, arg, "-h") or eql(u8, arg, "--help")) {
            die(0, usage, .{progname});
        } else if (eql(u8, arg, "-v") or eql(u8, arg, "--version")) {
            die(0, "{s} {s}\n", .{ progname, version });
        } else if (eql(u8, arg, "-o")) {
            oflag = true;
            output_filename = args.next() orelse {
                die(1, "{s}: missing filename after `-o`\n", .{progname});
            };
        } else if (eql(u8, arg, "-S")) {
            Sflag = true;
        } else if (eql(u8, arg, "-c")) {
            cflag = true;
        } else if (eql(u8, arg, "-s")) {
            sflag = true;
        } else if (eql(u8, arg[0..1], "-")) {
            die(1, "{s}: unknown option {s}\n" ++ usage, .{ progname, arg, progname });
        } else {
            null_input_filename = arg;
        }
    }

    if (null_input_filename == null) {
        die(1, "{s}: no input file\n", .{progname});
    }
    const input_filename = null_input_filename.?;
    const input_file = cwd.openFile(input_filename, .{}) catch |err| {
        die(1, "{s}: failed to open `{s}`: {s}\n", .{ progname, input_filename, @errorName(err) });
    };
    defer input_file.close();
    var reader = input_file.reader();
    // var br = std.io.bufferedReader(input_file.reader());
    // const reader = br.reader();

    var asm_filename: []u8 = undefined;
    if (Sflag and oflag) {
        asm_filename = @constCast(output_filename);
    } else {
        asm_filename = try allocator.alloc(u8, input_filename.len + 2);
        const i = std.mem.lastIndexOfLinear(u8, input_filename, ".") orelse input_filename.len;
        const s = try std.fmt.bufPrint(asm_filename, "{s}.s", .{input_filename[0..i]});
        asm_filename = try allocator.realloc(asm_filename, s.len);
    }

    const asm_file = try cwd.createFile(asm_filename, .{});
    defer asm_file.close();
    errdefer cwd.deleteFile(asm_filename) catch {};
    var bw = std.io.bufferedWriter(asm_file.writer());
    const writer = bw.writer();

    // r12 is the index for the data, we use it as index instead of pointer to
    // wrap around data instead of overflowing
    try writer.writeAll(
        \\bits 64
        \\default rel
        \\
        \\section .bss
        \\    data resb 65536
        \\
        \\section .text
        \\global _start
        \\
        \\_start:
        \\    xor r12, r12
        \\    mov rdx, 1
        \\
    );

    var bracket_counter: usize = 0;
    var stack = Stack.init(allocator);
    defer stack.deinit();

    while (true) {
        var byte = reader.readByte() catch |err| switch (err) {
            error.EndOfStream => break,
            else => |e| return e,
        };

        while (byte == '>' or byte == '<' or byte == '+' or byte == '-') {
            byte = unrollBasic(byte, reader, writer) catch |err| switch (err) {
                error.EndOfStream => break,
                else => |e| return e,
            };
        }

        switch (byte) {
            '[' => {
                const next = try reader.readByte();
                if (next == '+' or next == '-') {
                    if (try reader.readByte() == ']') {
                        try writer.writeAll("    mov byte [data + r12], 0\n");
                        continue;
                    }
                    try input_file.seekBy(-1);
                }
                try input_file.seekBy(-1);
                reader = input_file.reader();

                try writer.print(
                    \\    cmp byte [data + r12], 0
                    \\    je .Le{d}
                    \\.Ls{d}:
                    \\
                , .{ bracket_counter, bracket_counter });
                try stack.push(bracket_counter);
                bracket_counter += 1;
            },
            ']' => {
                const label = stack.pop() orelse {
                    die(1, "{s}: unmatched brackets\n", .{progname});
                };
                try writer.print(
                    \\    cmp byte [data + r12], 0
                    \\    jne .Ls{d}
                    \\.Le{d}:
                    \\
                , .{ label, label });
            },
            '.' => try writer.writeAll(
                \\    lea rsi, [data + r12]
                \\    mov rdi, 1
                \\    mov rax, 0x01
                \\    syscall
                \\
            ),
            ',' => try writer.writeAll(
                \\    lea rsi, [data + r12]
                \\    xor rdi, rdi
                \\    xor rax, rax
                \\    syscall
                \\
            ),
            else => {},
        }
    }

    if (!stack.isEmpty()) {
        die(1, "{s}: unmatched brackets\n", .{progname});
    }

    try writer.writeAll(
        \\    xor rdi, rdi
        \\    mov rax, 0x3c
        \\    syscall
        \\
    );
    try bw.flush();

    if (Sflag) {
        if (!oflag) {
            allocator.free(asm_filename);
        }
        std.os.exit(0);
    }

    var obj_filename: []u8 = undefined;
    if (cflag and oflag) {
        obj_filename = @constCast(output_filename);
    } else {
        obj_filename = try allocator.alloc(u8, input_filename.len + 2);
        const i = std.mem.lastIndexOfLinear(u8, input_filename, ".") orelse input_filename.len;
        const s = try std.fmt.bufPrint(obj_filename, "{s}.o", .{input_filename[0..i]});
        obj_filename = try allocator.realloc(obj_filename, s.len);
    }

    var res = try std.ChildProcess.exec(.{
        .argv = &[_][]const u8{ "nasm", "-f", "elf64", "-o", obj_filename, asm_filename },
        .allocator = allocator,
    });
    cwd.deleteFile(asm_filename) catch {};
    allocator.free(asm_filename);
    if (res.term.Exited > 0) {
        cwd.deleteFile(obj_filename) catch {};
        die(1, "{s}: nasm failed with status {d}\n", .{ progname, res.term.Exited });
    }

    if (!cflag) {
        res = try std.ChildProcess.exec(.{
            .argv = &[_][]const u8{ "ld", "-o", output_filename, obj_filename },
            .allocator = allocator,
        });
        cwd.deleteFile(obj_filename) catch {};
        if (res.term.Exited > 0) {
            die(1, "{s}: linker failed with status {d}\n", .{ progname, res.term.Exited });
        }
    }

    if (sflag) {
        if (cflag) {
            output_filename = obj_filename;
        }
        _ = try std.ChildProcess.exec(.{
            .argv = &[_][]const u8{ "strip", "-s", output_filename },
            .allocator = allocator,
        });
    }

    if (!cflag or !oflag) {
        allocator.free(obj_filename);
    }
}
