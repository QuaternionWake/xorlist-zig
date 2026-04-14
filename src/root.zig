const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn XorList(T: type) type {
    return struct {
        first: ?*Node,
        last: ?*Node,

        pub const empty: XorList(T) = .{ .first = null, .last = null };

        pub fn deinit(self: *XorList(T), ally: Allocator) void {
            var iter = self.iterateForwards();
            while (iter.next()) |node| {
                ally.destroy(node);
            }
            self.first = null;
            self.last = null;
        }

        pub fn append(self: *XorList(T), ally: Allocator, value: T) Allocator.Error!void {
            const new_node = try ally.create(Node);
            if (self.last) |last| {
                last.insertBetween(new_node, null);
                self.last = new_node;
            } else {
                self.first = new_node;
                self.last = new_node;
                new_node.xptr = 0;
            }
            new_node.value = value;
        }

        pub fn prepend(self: *XorList(T), ally: Allocator, value: T) Allocator.Error!void {
            const new_node = try ally.create(Node);
            if (self.first) |first| {
                first.insertBetween(new_node, null);
                self.first = new_node;
            } else {
                self.first = new_node;
                self.last = new_node;
                new_node.xptr = 0;
            }
            new_node.value = value;
        }

        pub fn insertAfter(self: *XorList(T), ally: Allocator, node: *Node, prev_addr: usize, value: T) Allocator.Error!void {
            if (node == self.first and prev_addr != 0) {
                return self.prepend(ally, value);
            } else if (node == self.last and prev_addr != 0) {
                return self.append(ally, value);
            }
            const new_node = try ally.create(Node);
            new_node.value = value;
            return node.insertAfter(new_node, prev_addr);
        }

        pub fn deleteFirst(self: *XorList(T), ally: Allocator) void {
            if (self.first) |first| {
                self.first = first.nextNode(0);
                first.delete(ally, 0);
                if (first == self.last) {
                    self.last = null;
                }
            }
        }

        pub fn deleteLast(self: *XorList(T), ally: Allocator) void {
            if (self.last) |last| {
                self.last = last.nextNode(0);
                last.delete(ally, 0);
                if (last == self.first) {
                    self.first = null;
                }
            }
        }

        pub fn delete(self: *XorList(T), ally: Allocator, node: *Node, prev_addr: usize) void {
            if (node == self.first) {
                self.deleteFirst(ally);
            } else if (node == self.last) {
                self.deleteLast(ally);
            } else {
                node.delete(ally, prev_addr);
            }
        }

        pub fn findForwards(self: XorList(T), value: T) ?struct { *Node, usize } {
            const first = self.first orelse return null;
            return first.find(0, value);
        }

        pub fn findBackwards(self: XorList(T), value: T) ?struct { *Node, usize } {
            const last = self.last orelse return null;
            return last.find(0, value);
        }

        pub fn iterateForwards(self: XorList(T)) Iterator {
            return .init(self.first, 0);
        }

        pub fn iterateBackwards(self: XorList(T)) Iterator {
            return .init(self.last, 0);
        }

        pub const Node = struct {
            value: T,
            xptr: usize,

            fn nextNode(self: Node, prev_addr: usize) ?*Node {
                const next_addr = prev_addr ^ self.xptr;

                return @ptrFromInt(next_addr);
            }

            fn insertAfter(self: *Node, node: *Node, prev_addr: usize) void {
                const self_addr = @intFromPtr(self);
                const node_addr = @intFromPtr(node);
                const next_addr = prev_addr ^ self.xptr;

                const next_ptr: ?*Node = @ptrFromInt(next_addr);

                self.xptr ^= next_addr ^ node_addr;
                node.xptr = self_addr ^ next_addr;
                if (next_ptr) |n| {
                    n.xptr ^= self_addr ^ node_addr;
                }
            }

            fn insertBetween(self: *Node, node: *Node, next: ?*Node) void {
                const self_addr = @intFromPtr(self);
                const node_addr = @intFromPtr(node);
                const next_addr = @intFromPtr(next);

                self.xptr ^= next_addr ^ node_addr;
                node.xptr = self_addr ^ next_addr;
                if (next) |n| {
                    n.xptr ^= self_addr ^ node_addr;
                }
            }

            fn find(self: *Node, prev_addr: usize, value: T) ?struct { *Node, usize } {
                var current = self;
                var prev = prev_addr;
                if (current.value == value) return .{ current, prev };
                while (current.nextNode(prev)) |next| {
                    prev = @intFromPtr(current);
                    current = next;
                    if (current.value == value) return .{ current, prev };
                }
                return null;
            }

            fn delete(self: *Node, ally: Allocator, prev_addr: usize) void {
                const self_addr = @intFromPtr(self);
                const next_addr = prev_addr ^ self.xptr;

                const prev_ptr: ?*Node = @ptrFromInt(prev_addr);
                const next_ptr: ?*Node = @ptrFromInt(next_addr);
                if (prev_ptr) |n| {
                    n.xptr ^= self_addr ^ next_addr;
                }
                if (next_ptr) |n| {
                    n.xptr ^= self_addr ^ prev_addr;
                }

                ally.destroy(self);
            }
        };

        pub const Iterator = struct {
            current_ptr: ?*Node,
            previous_addr: usize,

            pub fn init(first_node: ?*Node, previous_addr: usize) Iterator {
                return .{
                    .current_ptr = first_node,
                    .previous_addr = previous_addr,
                };
            }

            pub fn next(self: *Iterator) ?*Node {
                if (self.current_ptr) |current| {
                    const result = self.current_ptr;
                    const next_ptr = current.nextNode(self.previous_addr);
                    self.previous_addr = @intFromPtr(current);
                    self.current_ptr = next_ptr;

                    return result;
                }
                return null;
            }
        };
    };
}

test "XorList" {
    const t = std.testing;

    var list: XorList(i32) = .empty;
    defer list.deinit(t.allocator);

    for ([_]i32{ 0, 1, 1, 2, 3, 5, 8, 13 }) |x| {
        try list.append(t.allocator, x);
    }

    for ([_]i32{ 1, 2, 6, 24, 125 }) |x| {
        try list.prepend(t.allocator, x);
    }

    var iter = list.iterateForwards();
    var i: usize = 0;
    const expected_1 = [_]i32{ 125, 24, 6, 2, 1, 0, 1, 1, 2, 3, 5, 8, 13 };
    while (iter.next()) |node| : (i += 1) {
        try t.expectEqual(expected_1[i], node.value);
    }
    try t.expectEqual(expected_1.len, i);

    iter = list.iterateBackwards();
    while (iter.next()) |node| : (i -= 1) {
        try t.expectEqual(expected_1[i - 1], node.value);
    }

    var find_res = list.findForwards(5) orelse return error.Null;
    try t.expect(find_res.@"0".value == 5);

    const new_node = try t.allocator.create(XorList(i32).Node);
    new_node.value = 999;
    find_res.@"0".insertAfter(new_node, find_res.@"1");

    iter = list.iterateForwards();
    const expected_2 = [_]i32{ 125, 24, 6, 2, 1, 0, 1, 1, 2, 3, 5, 999, 8, 13 };
    while (iter.next()) |node| : (i += 1) {
        try t.expectEqual(expected_2[i], node.value);
    }

    find_res = list.findForwards(3) orelse return error.Null;
    list.delete(t.allocator, find_res.@"0", find_res.@"1");

    find_res = list.findForwards(13) orelse return error.Null;
    list.delete(t.allocator, find_res.@"0", find_res.@"1");

    list.deleteFirst(t.allocator);

    iter = list.iterateForwards();
    i = 0;
    const expected_3 = [_]i32{ 24, 6, 2, 1, 0, 1, 1, 2, 5, 999, 8 };
    while (iter.next()) |node| : (i += 1) {
        try t.expectEqual(expected_3[i], node.value);
    }

    list.deinit(t.allocator);
    try list.append(t.allocator, 5);
    try list.append(t.allocator, 6);
    list.deleteFirst(t.allocator);
    list.deleteFirst(t.allocator);
    list.deleteFirst(t.allocator);
    list.deleteLast(t.allocator);

    try list.append(t.allocator, 5);
    try list.append(t.allocator, 6);
    find_res = list.findForwards(5) orelse return error.Null;
    list.delete(t.allocator, find_res.@"0", find_res.@"1");
    find_res = list.findForwards(6) orelse return error.Null;
    list.delete(t.allocator, find_res.@"0", find_res.@"1");
    list.deleteFirst(t.allocator);
    list.deleteLast(t.allocator);
}
