const std = @import("std");
const reader = @import("reader.zig");
const cfg = @import("cfg.zig");
const translator = @import("translator.zig");
const emitter = @import("emitter.zig");
const optimizer = @import("optimizer.zig");

const profile = @import("profile.zig");

pub const Mode = enum {
    emulation,
    native,
};

pub const Options = struct {
    input: ?[]const u8 = null,
    cpu: profile.CpuProfile = .nmos6502,
    mode: Mode = .emulation,
    output: ?[]const u8 = null,
    report: ?[]const u8 = null,
    no_runtime_helpers: bool = false,
    emit_symbol_map: bool = false,
    opt_level: u8 = 1,
    format: Format = .auto,
    schema: bool = false,
    schema_filter: []const u8 = "",
    show_version: bool = false,
    show_help: bool = false,
};

const release = "0.1.0";

const Format = enum { auto, text, json };

const help_text =
    \\Usage: avr2mos --input <file> --output <file> [options]
    \\       avr2mos schema [command]
    \\       avr2mos version
    \\
    \\--output is the translated file. --format selects auto, text, or json.
    \\auto stays text when stdout is not a terminal.
    \\
    \\Options:
    \\  --input <file>     Input AVR ELF or binary
    \\  --output <file>    Translated 6502 binary
    \\  --cpu <profile>    nmos6502, 65c02, or 65816
    \\  --mode <mode>      emulation or native
    \\  --report <file>    Write a translation report
    \\  --format <FMT>     auto, text, or json
    \\  --no-runtime-helpers
    \\  --emit-symbol-map
    \\  -O0 -O1 -O2 -O3 -Os
    \\  schema [command]   Print the CLI Spec document
    \\  version            Print the version
    \\  -h, --help         Show this help
    \\
;

var wants_json = false;

fn usageExit(msg: []const u8) noreturn {
    std.debug.print("{s}", .{msg});
    if (wants_json) {
        std.debug.print("{s}", .{"{\"error\":{\"kind\":\"usage\",\"message\":\"invalid arguments\"}}\n"});
    }
    std.process.exit(2);
}

fn setFormat(options: *Options, value: []const u8) void {
    if (std.mem.eql(u8, value, "auto")) {
        options.format = .auto;
    } else if (std.mem.eql(u8, value, "text")) {
        options.format = .text;
    } else if (std.mem.eql(u8, value, "json")) {
        options.format = .json;
    } else {
        wants_json = false;
        usageExit("Error: --format requires auto, text, or json\n");
    }
    wants_json = options.format == .json;
}

fn schemaSelected(name: []const u8, filter: []const u8) bool {
    if (filter.len == 0) return true;
    if (std.mem.eql(u8, name, filter)) return true;
    return name.len > filter.len and std.mem.startsWith(u8, name, filter) and name[filter.len] == ' ';
}

const SpecCmd = struct {
    name: []const u8,
    description: []const u8,
    effects: []const u8,
    body: []const u8,
};

const spec_cmds = [_]SpecCmd{
    .{
        .name = "schema",
        .effects = "read_only",
        .description = "Print this CLI Spec document. schema <command> returns the same document filtered to that command.",
        .body = "\"output_kind\":\"opaque\",\"media_type\":\"application/json\"",
    },
    .{
        .name = "version",
        .effects = "read_only",
        .description = "Print the avr2mos version.",
        .body = "\"cardinality\":\"single\",\"output_fields\":[{\"name\":\"version\",\"type\":\"string\"}]",
    },
    .{
        .name = "translate",
        .effects = "idempotent",
        .description = "Translate an AVR program to a 6502 binary. The word translate is optional. --output is the destination file, not a format flag. A repeat that leaves the same bytes exits 0 and reports changed false. Progress stays on stderr.",
        .body = "\"cardinality\":\"single\",\"output_fields\":[{\"name\":\"input\",\"type\":\"string\"},{\"name\":\"output\",\"type\":\"string\"},{\"name\":\"bytes\",\"type\":\"integer\"},{\"name\":\"changed\",\"type\":\"boolean\"}]",
    },
};

fn jsonEscape(buf: []u8, s: []const u8) []const u8 {
    var n: usize = 0;
    for (s) |ch| {
        if (ch == '"' or ch == '\\' or ch == '\n' or ch < 0x20) {
            const piece: []const u8 = if (ch == '"') "\\\"" else if (ch == '\\') "\\\\" else if (ch == '\n') "\\n" else "?";
            if (n + piece.len > buf.len) return "?";
            @memcpy(buf[n..][0..piece.len], piece);
            n += piece.len;
        } else {
            if (n >= buf.len) return "?";
            buf[n] = ch;
            n += 1;
        }
    }
    return buf[0..n];
}

fn writeSchema(filter: []const u8) !void {
    var count: usize = 0;
    for (spec_cmds) |cmd| {
        if (schemaSelected(cmd.name, filter)) count += 1;
    }
    if (count == 0) {
        usageExit("unknown command path\n");
    }
    const stdout = std.fs.File.stdout();
    try stdout.writeAll("{\"clispec\":\"0.3\",\"name\":\"avr2mos\",\"version\":\"" ++ release ++ "\",\"description\":\"AVR to 6502 static binary translator.\",\"output\":{\"tty\":\"text\",\"piped\":\"text\"},\"global_args\":[{\"name\":\"--format\",\"type\":\"string\",\"required\":false,\"description\":\"auto, text, or json. auto stays text when piped. --output remains the destination file.\",\"default\":\"auto\",\"enum\":[\"auto\",\"text\",\"json\"]}],\"commands\":[");
    var emitted: usize = 0;
    for (spec_cmds) |cmd| {
        if (!schemaSelected(cmd.name, filter)) continue;
        if (emitted != 0) try stdout.writeAll(",");
        try stdout.writeAll("{\"name\":\"");
        try stdout.writeAll(cmd.name);
        try stdout.writeAll("\",\"description\":\"");
        try stdout.writeAll(cmd.description);
        try stdout.writeAll("\",\"effects\":\"");
        try stdout.writeAll(cmd.effects);
        try stdout.writeAll("\",");
        try stdout.writeAll(cmd.body);
        try stdout.writeAll("}");
        emitted += 1;
    }
    try stdout.writeAll("],\"errors\":[{\"kind\":\"usage\",\"exit_code\":2,\"retryable\":false,\"description\":\"The arguments are not valid.\"},{\"kind\":\"failure\",\"exit_code\":1,\"retryable\":false,\"description\":\"The translation failed.\"}]}\n");
}

fn sameBytes(allocator: std.mem.Allocator, path: []const u8, bytes: []const u8) bool {
    const file = std.fs.cwd().openFile(path, .{}) catch return false;
    defer file.close();
    const stat = file.stat() catch return false;
    if (stat.size != bytes.len) return false;
    const existing = file.readToEndAlloc(allocator, bytes.len) catch return false;
    defer allocator.free(existing);
    return std.mem.eql(u8, existing, bytes);
}

pub fn main() !void {
    run() catch |err| {
        if (wants_json) {
            std.debug.print("{s}", .{"{\"error\":{\"kind\":\"failure\",\"message\":\"command failed\"}}\n"});
            std.process.exit(1);
        }
        return err;
    };
}

fn run() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip executable name
    _ = args.next();

    var options = Options{};

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--input")) {
            options.input = args.next() orelse return error.MissingArgumentForInput;
        } else if (std.mem.eql(u8, arg, "--output")) {
            options.output = args.next() orelse return error.MissingArgumentForOutput;
        } else if (std.mem.eql(u8, arg, "--cpu")) {
            const cpu_str = args.next() orelse return error.MissingArgumentForCpu;
            if (std.mem.eql(u8, cpu_str, "nmos6502")) {
                options.cpu = .nmos6502;
            } else if (std.mem.eql(u8, cpu_str, "65c02")) {
                options.cpu = .c6502;
            } else if (std.mem.eql(u8, cpu_str, "65816")) {
                options.cpu = .c65816;
            } else {
                std.debug.print("Unknown CPU profile: {s}\n", .{cpu_str});
                return error.InvalidCpuProfile;
            }
        } else if (std.mem.eql(u8, arg, "--mode")) {
            const mode_str = args.next() orelse return error.MissingArgumentForMode;
            if (std.mem.eql(u8, mode_str, "emulation")) {
                options.mode = .emulation;
            } else if (std.mem.eql(u8, mode_str, "native")) {
                options.mode = .native;
            } else {
                std.debug.print("Unknown mode: {s}\n", .{mode_str});
                return error.InvalidMode;
            }
        } else if (std.mem.eql(u8, arg, "--report")) {
            options.report = args.next() orelse return error.MissingArgumentForReport;
        } else if (std.mem.eql(u8, arg, "--no-runtime-helpers")) {
            options.no_runtime_helpers = true;
        } else if (std.mem.eql(u8, arg, "--emit-symbol-map")) {
            options.emit_symbol_map = true;
        } else if (std.mem.eql(u8, arg, "-O0")) {
            options.opt_level = 0;
        } else if (std.mem.eql(u8, arg, "-O1")) {
            options.opt_level = 1;
        } else if (std.mem.eql(u8, arg, "-O2")) {
            options.opt_level = 2;
        } else if (std.mem.eql(u8, arg, "-O3")) {
            options.opt_level = 3;
        } else if (std.mem.eql(u8, arg, "-Os")) {
            options.opt_level = 4;
        } else if (std.mem.eql(u8, arg, "--format")) {
            const fmt = args.next() orelse usageExit("Error: --format requires auto, text, or json\n");
            setFormat(&options, fmt);
        } else if (std.mem.startsWith(u8, arg, "--format=")) {
            setFormat(&options, arg["--format=".len..]);
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            options.show_help = true;
        } else if (options.schema and options.schema_filter.len == 0 and arg.len > 0 and arg[0] != '-') {
            options.schema_filter = arg;
        } else if (std.mem.eql(u8, arg, "schema")) {
            options.schema = true;
        } else if (std.mem.eql(u8, arg, "version")) {
            options.show_version = true;
        } else if (std.mem.eql(u8, arg, "translate")) {
            // Optional command word. Flags still select the translation.
        } else {
            usageExit("Unknown argument\n");
        }
    }

    if (options.show_help) {
        std.fs.File.stdout().writeAll(help_text) catch return error.StdoutFailed;
        return;
    }
    if (options.show_version) {
        if (wants_json) {
            std.fs.File.stdout().writeAll("{\"version\":\"" ++ release ++ "\"}\n") catch return error.StdoutFailed;
        } else {
            std.fs.File.stdout().writeAll("avr2mos " ++ release ++ "\n") catch return error.StdoutFailed;
        }
        return;
    }
    if (options.schema) {
        try writeSchema(options.schema_filter);
        return;
    }

    const input_path = options.input orelse usageExit("Usage: avr2mos --input <file> --output <file> [--cpu nmos6502|65c02|65816]\n");
    const output_path = options.output orelse usageExit("Usage: avr2mos --input <file> --output <file> [--cpu nmos6502|65c02|65816]\n");

    std.debug.print("Input: {s}\n", .{input_path});
    std.debug.print("Output: {s}\n", .{output_path});
    std.debug.print("CPU: {s}\n", .{@tagName(options.cpu)});
    std.debug.print("Mode: {s}\n", .{@tagName(options.mode)});

    // 1. Read the input program
    var prog = reader.readInput(allocator, input_path) catch |err| {
        std.debug.print("Failed to read input file: {}\n", .{err});
        return err;
    };
    defer prog.deinit(allocator);

    std.debug.print("Read program: {} bytes of text\n", .{prog.text.len});

    // 2. Build the control flow graph
    var prog_cfg = cfg.buildCFG(allocator, prog.text, prog.text_vma) catch |err| {
        std.debug.print("Failed to build CFG: {}\n", .{err});
        return err;
    };
    defer prog_cfg.deinit(allocator);

    std.debug.print("Built CFG with {} basic blocks\n", .{prog_cfg.blocks.items.len});

    // 3. Translate the program
    var out_emit = emitter.Emitter.init(allocator);
    defer out_emit.deinit();

    for (prog_cfg.blocks.items) |block| {
        translator.translateBlock(block, options.cpu, &out_emit, prog.text_vma) catch |err| {
            std.debug.print("Failed to translate block: {}\n", .{err});
            return err;
        };
    }

    // 4. Optimize Output Machine Code Sequence
    try optimizer.Optimizer.optimize(&out_emit, options.opt_level);

    const base_vma: u16 = @truncate(prog.text_vma);

    // Data section initialization
    if (prog.data.len > 0) {
        std.debug.print("Emitting .data section ({} bytes) at 0x{X:04}\n", .{ prog.data.len, prog.data_vma });
        try out_emit.emitDataSection(base_vma, @truncate(prog.data_vma), prog.data);
    }
    if (prog.rodata.len > 0) {
        std.debug.print("Emitting .rodata section ({} bytes) at 0x{X:04}\n", .{ prog.rodata.len, prog.rodata_vma });
        try out_emit.emitDataSection(base_vma, @truncate(prog.rodata_vma), prog.rodata);
    }

    // 5. Generate Jump Table and Trampoline for indirect control flow
    // Only emit if IJMP/ICALL was actually used (check for fixup targeting 0xFFFE)
    var needs_trampoline = false;
    for (out_emit.fixups.items) |fixup| {
        if (fixup.target_addr == 0xFFFE) {
            needs_trampoline = true;
            break;
        }
    }
    if (needs_trampoline) {
        const table_addr = try out_emit.generateJumpTable(base_vma);
        const table_len = out_emit.labels.count();
        try out_emit.defineLabel(0xFFFE); // Map special address to trampoline
        _ = try out_emit.emitTrampoline(base_vma, table_addr, table_len);
    }

    // 6. Emit Runtime Helpers
    if (!options.no_runtime_helpers) {
        _ = try out_emit.emitRuntime();
    }

    // 7. Resolve labels and fixups
    try out_emit.resolveFixups(base_vma);

    std.debug.print("Translated output: {} bytes\n", .{out_emit.bytes.items.len});

    // 8. Write back the finished binary. A repeat with the same bytes is success.
    const changed = !sameBytes(allocator, output_path, out_emit.bytes.items);
    const out_file = try std.fs.cwd().createFile(output_path, .{ .read = false });
    defer out_file.close();

    try out_file.writeAll(out_emit.bytes.items);
    std.debug.print("Wrote output to {s}\n", .{output_path});
    if (wants_json) {
        var in_buf: [1024]u8 = undefined;
        var out_buf: [1024]u8 = undefined;
        const in_esc = jsonEscape(&in_buf, input_path);
        const out_esc = jsonEscape(&out_buf, output_path);
        var line_buf: [2200]u8 = undefined;
        const line = std.fmt.bufPrint(&line_buf, "{{\"input\":\"{s}\",\"output\":\"{s}\",\"bytes\":{d},\"changed\":{s}}}\n", .{ in_esc, out_esc, out_emit.bytes.items.len, if (changed) "true" else "false" }) catch return error.StdoutFailed;
        std.fs.File.stdout().writeAll(line) catch return error.StdoutFailed;
    }

    // 9. Generate reports if requested
    if (options.report) |report_path| {
        const report_str = try out_emit.generateReport(base_vma);
        defer allocator.free(report_str);
        const report_file = try std.fs.cwd().createFile(report_path, .{});
        defer report_file.close();
        try report_file.writeAll(report_str);
        std.debug.print("Wrote report to {s}\n", .{report_path});
    }

    if (options.emit_symbol_map) {
        const map_path = try std.mem.concat(allocator, u8, &[_][]const u8{ output_path, ".map" });
        defer allocator.free(map_path);
        const map_str = try out_emit.generateSymbolMap(base_vma);
        defer allocator.free(map_str);
        const map_file = try std.fs.cwd().createFile(map_path, .{});
        defer map_file.close();
        try map_file.writeAll(map_str);
        std.debug.print("Wrote symbol map to {s}\n", .{map_path});
    }
}
