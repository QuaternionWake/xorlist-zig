const std = @import("std");

const XorList = @import("xorlist").XorList(i32);

pub fn main() !void {
    var dba: std.heap.DebugAllocator(.{}) = .init;
    defer _ = dba.detectLeaks();
    const ally = dba.allocator();

    var stdin_buf: [256]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&stdin_buf);
    const stdin = &stdin_reader.interface;

    var stdout_buf: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;

    var list: XorList = .empty;
    defer list.deinit(ally);
    var curr_node: ?XorList.Iterator = null;
    while (true) {
        try stdout.print("> ", .{});
        try stdout.flush();

        const line = stdin.takeDelimiter('\n') catch |e| switch (e) {
            error.StreamTooLong => {
                try stdout.print("Line too long!!!", .{});
                continue;
            },
            error.ReadFailed => return e,
        } orelse {
            try stdout.writeByte('\n');
            try stdout.flush();
            break;
        };
        var chunks = std.mem.tokenizeScalar(u8, line, ' ');

        const command_str = chunks.next() orelse {
            try stdout.print("No command given\n", .{});
            continue;
        };
        const command = for (commands) |cmd| {
            if (std.ascii.eqlIgnoreCase(cmd.str, command_str)) {
                break cmd.command;
            }
        } else {
            try stdout.print("Unknown command `{s}`\nType help to see avaliable commands\n", .{command_str});
            continue;
        };

        var arg: i32 = undefined;
        if (command.argCount() == 1) {
            const arg_str = chunks.next() orelse {
                try stdout.print("Command `{s}` requires an argument\n", .{command_str});
                continue;
            };
            arg = std.fmt.parseInt(i32, arg_str, 10) catch {
                try stdout.print("Failed to parse `{s}`\n", .{arg_str});
                continue;
            };
        }

        cmd: switch (command) {
            .prepend => {
                try list.prepend(ally, arg);
                while (chunks.next()) |str| {
                    const val = std.fmt.parseInt(i32, str, 10) catch {
                        try stdout.print("Failed to parse `{s}`\n", .{str});
                        continue;
                    };
                    try list.prepend(ally, val);
                }
            },
            .append => {
                try list.append(ally, arg);
                while (chunks.next()) |str| {
                    const val = std.fmt.parseInt(i32, str, 10) catch {
                        try stdout.print("Failed to parse `{s}`\n", .{str});
                        continue;
                    };
                    try list.append(ally, val);
                }
            },
            .delete_first => list.deleteFirst(ally),
            .delete_last => list.deleteLast(ally),
            .clear_list => list.deinit(ally),
            .find_forwards => {
                curr_node = list.findForwards(arg) orelse {
                    try stdout.print("Value {d} not found\n", .{arg});
                    break :cmd;
                };
            },
            .find_backwards => {
                curr_node = list.findBackwards(arg) orelse {
                    try stdout.print("Value {d} not found\n", .{arg});
                    break :cmd;
                };
            },
            .clear_node => {
                curr_node = null;
            },
            .insert_after_node => {
                if (curr_node) |*iter| {
                    try list.insertAfter(ally, iter, arg);
                } else {
                    try stdout.print("No node selected\n", .{});
                }
            },
            .delete_node => {
                if (curr_node) |*iter| {
                    list.delete(ally, iter);
                } else {
                    try stdout.print("No node selected\n", .{});
                }
            },
            .print_forwards => try printList(stdout, list, curr_node, .forwards),
            .print_backwards => try printList(stdout, list, curr_node, .backwards),
            .help => try printHelp(stdout),
            .quit => break,
        }
        if (command.shouldPrint()) {
            try printList(stdout, list, curr_node, .forwards);
        }
    }
}

fn printList(writer: *std.Io.Writer, list: XorList, selected_iter: ?XorList.Iterator, direction: enum { forwards, backwards }) !void {
    var iter, const arrow = switch (direction) {
        .forwards => .{ list.iterateForwards(), "=>" },
        .backwards => .{ list.iterateBackwards(), "<=" },
    };
    const selected = if (selected_iter) |si| si.next_ptr else null;
    if (iter.next()) |node| {
        if (node == selected) {
            try writer.print("({d})", .{node.value});
        } else {
            try writer.print("{d}", .{node.value});
        }
    } else {
        try writer.print("List empty\n", .{});
        return;
    }
    while (iter.next()) |node| {
        if (node == selected) {
            try writer.print(" {s} ({d})", .{ arrow, node.value });
        } else {
            try writer.print(" {s} {d}", .{ arrow, node.value });
        }
    }
    try writer.writeByte('\n');
}

const Command = enum {
    prepend,
    append,
    delete_first,
    delete_last,
    clear_list,
    find_forwards,
    find_backwards,
    clear_node,
    insert_after_node,
    delete_node,
    print_forwards,
    print_backwards,

    help,
    quit,

    fn argCount(self: Command) u8 {
        return switch (self) {
            .delete_first,
            .delete_last,
            .clear_list,
            .print_forwards,
            .print_backwards,
            .clear_node,
            .delete_node,
            .help,
            .quit,
            => 0,
            .prepend,
            .append,
            .find_forwards,
            .find_backwards,
            .insert_after_node,
            => 1,
        };
    }

    fn shouldPrint(self: Command) bool {
        return switch (self) {
            .prepend,
            .append,
            .delete_first,
            .delete_last,
            .clear_list,
            .find_forwards,
            .find_backwards,
            .clear_node,
            .insert_after_node,
            .delete_node,
            => true,
            .print_forwards,
            .print_backwards,
            .help,
            .quit,
            => false,
        };
    }
};

fn printHelp(writer: *std.Io.Writer) !void {
    var prev_command: ?Command = null;
    for (commands) |cmd| {
        if (cmd.command == prev_command) {
            try writer.print(", {s}", .{cmd.str});
        } else {
            if (prev_command != null) {
                try writer.writeByte('\n');
            }
            try writer.print("{s}: {s}", .{ @tagName(cmd.command), cmd.str });
            prev_command = cmd.command;
        }
    }
    try writer.writeByte('\n');
}

const CommandStr = struct {
    str: []const u8,
    command: Command,
};

const commands = [_]CommandStr{
    .{ .command = .prepend, .str = "prepend" },
    .{ .command = .prepend, .str = "pp" },
    .{ .command = .append, .str = "append" },
    .{ .command = .append, .str = "ap" },
    .{ .command = .append, .str = "insert" },
    .{ .command = .append, .str = "i" },
    .{ .command = .delete_first, .str = "delete_first" },
    .{ .command = .delete_first, .str = "df" },
    .{ .command = .delete_last, .str = "delete_last" },
    .{ .command = .delete_last, .str = "dl" },
    .{ .command = .find_forwards, .str = "find_forwards" },
    .{ .command = .find_forwards, .str = "ff" },
    .{ .command = .find_forwards, .str = "find" },
    .{ .command = .find_forwards, .str = "f" },
    .{ .command = .find_backwards, .str = "find_backwards" },
    .{ .command = .find_backwards, .str = "fb" },
    .{ .command = .clear_node, .str = "clear_node" },
    .{ .command = .clear_node, .str = "cn" },
    .{ .command = .clear_node, .str = "unselect" },
    .{ .command = .clear_list, .str = "clear" },
    .{ .command = .clear_list, .str = "c" },
    .{ .command = .insert_after_node, .str = "insert_after_node" },
    .{ .command = .insert_after_node, .str = "iafter" },
    .{ .command = .insert_after_node, .str = "ia" },
    .{ .command = .delete_node, .str = "delete_node" },
    .{ .command = .delete_node, .str = "del" },
    .{ .command = .print_forwards, .str = "print_forwards" },
    .{ .command = .print_forwards, .str = "pf" },
    .{ .command = .print_forwards, .str = "print" },
    .{ .command = .print_backwards, .str = "print_backwards" },
    .{ .command = .print_backwards, .str = "pb" },
    .{ .command = .help, .str = "help" },
    .{ .command = .help, .str = "h" },
    .{ .command = .quit, .str = "exit" },
    .{ .command = .quit, .str = "quit" },
    .{ .command = .quit, .str = "q" },
};
