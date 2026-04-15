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
            var iter = self.iterateBackwards();
            iter.insertBefore(new_node);
            self.last = new_node;
            if (self.first == null) {
                self.first = new_node;
            }
            new_node.value = value;
        }

        pub fn prepend(self: *XorList(T), ally: Allocator, value: T) Allocator.Error!void {
            const new_node = try ally.create(Node);
            var iter = self.iterateForwards();
            iter.insertBefore(new_node);
            self.first = new_node;
            if (self.last == null) {
                self.last = new_node;
            }
            new_node.value = value;
        }

        pub fn insertAfter(self: *XorList(T), ally: Allocator, iter: *Iterator, value: T) !void {
            if (iter.next_ptr == self.first and iter.prev_addr != 0) {
                return self.prepend(ally, value);
            } else if (iter.next_ptr == self.last and iter.prev_addr != 0) {
                return self.append(ally, value);
            }
            const new_node = try ally.create(Node);
            new_node.value = value;
            return iter.insertAfter(new_node);
        }

        pub fn insertBefore(self: *XorList(T), ally: Allocator, iter: *Iterator, value: T) !void {
            if (iter.next_ptr == self.first and iter.prev_addr == 0) {
                try self.prepend(ally, value);
                iter.* = self.iterateForwards();
            } else if (iter.next_ptr == self.last and iter.prev_addr == 0) {
                try self.append(ally, value);
                iter.* = self.iterateBackwards();
            }
            const new_node = try ally.create(Node);
            new_node.value = value;
            return iter.insertBefore(new_node);
        }

        pub fn deleteFirst(self: *XorList(T), ally: Allocator) void {
            if (self.first) |first| {
                var iter = self.iterateForwards();
                iter.delete(ally);
                self.first = iter.next();
                if (first == self.last) {
                    self.last = null;
                }
            }
        }

        pub fn deleteLast(self: *XorList(T), ally: Allocator) void {
            if (self.last) |last| {
                var iter = self.iterateBackwards();
                iter.delete(ally);
                self.last = iter.next();
                if (last == self.first) {
                    self.first = null;
                }
            }
        }

        pub fn delete(self: *XorList(T), ally: Allocator, iter: *Iterator) void {
            if (iter.next_ptr == self.first) {
                self.deleteFirst(ally);
                iter.* = self.iterateForwards();
            } else if (iter.next_ptr == self.last) {
                self.deleteLast(ally);
                iter.* = self.iterateBackwards();
            } else {
                iter.delete(ally);
            }
        }

        pub fn findForwards(self: XorList(T), value: T) ?Iterator {
            return self.iterateForwards().find(value);
        }

        pub fn findBackwards(self: XorList(T), value: T) ?Iterator {
            return self.iterateBackwards().find(value);
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
        };

        pub const Iterator = struct {
            next_ptr: ?*Node,
            prev_addr: usize,

            // Iterator functions
            pub fn init(first_node: ?*Node, previous_addr: usize) Iterator {
                return .{
                    .next_ptr = first_node,
                    .prev_addr = previous_addr,
                };
            }

            pub fn next(self: *Iterator) ?*Node {
                const result = self.next_ptr;
                if (self.next_ptr) |next_ptr| {
                    const curr_addr = @intFromPtr(next_ptr);
                    const next_addr = self.prev_addr ^ next_ptr.xptr;
                    self.next_ptr = @ptrFromInt(next_addr);
                    self.prev_addr = curr_addr;
                }
                return result;
            }

            pub fn prev(self: *Iterator) ?*Node {
                const result: ?*Node = @ptrFromInt(self.prev_addr);
                if (self.prev_addr != 0) {
                    const previous: *Node = @ptrFromInt(self.prev_addr);
                    const curr_addr = @intFromPtr(self.next_ptr);
                    const previouser_addr = previous.xptr ^ curr_addr;
                    self.next_ptr = previous;
                    self.prev_addr = previouser_addr;
                }
                return result;
            }

            pub fn flip(self: *Iterator) void {
                if (self.next_ptr) |next_ptr| {
                    self.prev_addr ^= next_ptr.xptr;
                }
            }

            // Node functions
            fn insertAfter(self: *Iterator, node: *Node) !void {
                const parent = self.next_ptr orelse return error.Null;
                const parent_addr = @intFromPtr(parent);
                const node_addr = @intFromPtr(node);
                const next_addr = self.prev_addr ^ parent.xptr;

                const next_ptr: ?*Node = @ptrFromInt(next_addr);

                parent.xptr ^= next_addr ^ node_addr;
                node.xptr = parent_addr ^ next_addr;
                if (next_ptr) |n| {
                    n.xptr ^= parent_addr ^ node_addr;
                }
            }

            fn insertBefore(self: *Iterator, node: *Node) void {
                const parent_addr = @intFromPtr(self.next_ptr);
                const node_addr = @intFromPtr(node);
                const prev_ptr: ?*Node = @ptrFromInt(self.prev_addr);

                if (self.next_ptr) |n| {
                    n.xptr ^= self.prev_addr ^ node_addr;
                }
                node.xptr = parent_addr ^ self.prev_addr;
                if (prev_ptr) |n| {
                    n.xptr ^= parent_addr ^ node_addr;
                }
                self.prev_addr = node_addr;
            }

            pub fn find(self: Iterator, value: T) ?Iterator {
                var iter = self;
                while (iter.next_ptr) |n| {
                    if (n.value == value) return iter;
                    _ = iter.next();
                }
                return null;
            }

            fn delete(self: *Iterator, ally: Allocator) void {
                const node = self.next_ptr orelse return;
                const node_addr = @intFromPtr(node);
                const next_addr = self.prev_addr ^ node.xptr;

                const prev_ptr: ?*Node = @ptrFromInt(self.prev_addr);
                const next_ptr: ?*Node = @ptrFromInt(next_addr);
                if (prev_ptr) |n| {
                    n.xptr ^= node_addr ^ next_addr;
                }
                if (next_ptr) |n| {
                    n.xptr ^= node_addr ^ self.prev_addr;
                }

                _ = self.next();
                ally.destroy(node);
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
    try t.expect(find_res.next_ptr.?.value == 5);

    const new_node = try t.allocator.create(XorList(i32).Node);
    new_node.value = 999;
    try find_res.insertAfter(new_node);

    iter = list.iterateForwards();
    const expected_2 = [_]i32{ 125, 24, 6, 2, 1, 0, 1, 1, 2, 3, 5, 999, 8, 13 };
    while (iter.next()) |node| : (i += 1) {
        try t.expectEqual(expected_2[i], node.value);
    }

    find_res = list.findForwards(3) orelse return error.Null;
    list.delete(t.allocator, &find_res);

    find_res = list.findForwards(13) orelse return error.Null;
    list.delete(t.allocator, &find_res);

    list.deleteFirst(t.allocator);

    iter = list.iterateForwards();
    i = 0;
    const expected_3 = [_]i32{ 24, 6, 2, 1, 0, 1, 1, 2, 5, 999, 8 };
    while (iter.next()) |node| : (i += 1) {
        try t.expectEqual(expected_3[i], node.value);
    }

    while (iter.prev()) |node| : (i -= 1) {
        try t.expectEqual(expected_3[i - 1], node.value);
    }

    iter = list.iterateForwards();
    i = 0;
    const expected_4 = [_]i32{ 24, 6, 2, 1, 0, 1, 2, 6, 24 };
    while (iter.next()) |node| : (i += 1) {
        try t.expectEqual(expected_4[i], node.value);
        if (iter.next_ptr != null and iter.next_ptr.?.value == 0) {
            iter.flip();
        }
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
    list.delete(t.allocator, &find_res);
    find_res = list.findForwards(6) orelse return error.Null;
    list.delete(t.allocator, &find_res);
    list.deleteFirst(t.allocator);
    list.deleteLast(t.allocator);
}
