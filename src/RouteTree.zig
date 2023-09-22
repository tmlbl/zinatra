const std = @import("std");

pub const Params = std.StringHashMap([]const u8);

pub fn RouteTree(comptime T: type) type {
    return struct {
        a: std.mem.Allocator,
        name: []const u8,
        children: std.ArrayList(*Self),
        wildcard: bool,
        value: ?T,

        const Self = @This();

        pub fn init(a: std.mem.Allocator, name: []const u8, value: ?T) !*Self {
            var buf = try a.alloc(u8, name.len);
            std.mem.copy(u8, buf, name);

            var self = try a.create(Self);
            self.a = a;
            self.name = buf;
            self.children = std.ArrayList(*Self).init(a);
            self.value = value;

            if (buf[0] == ':') {
                self.wildcard = true;
            }

            return self;
        }

        pub fn deinit(self: *Self) void {
            for (self.children.items) |child| {
                child.deinit();
            }
            self.children.deinit();
            self.a.free(self.name);
            self.a.destroy(self);
        }

        pub fn add(self: *Self, path: []const u8, value: T) !void {
            var it = std.mem.split(u8, path, "/");
            var cur = self;

            while (it.next()) |part| {
                if (part.len == 0) {
                    continue;
                }
                if (cur.getChild(part, true) == null) {
                    var new = try Self.init(self.a, part, null);
                    try cur.children.append(new);
                    cur = new;
                } else {
                    cur = cur.getChild(part, true).?;
                }
            }
            cur.value = value;
        }

        pub fn resolve(self: *Self, target: []const u8, params: *Params) ?T {
            var path = target;
            const qix = std.mem.indexOf(u8, path, "?");
            if (qix != null) {
                path = path[1..qix.?];

                // Extract query string parameters
                var query = target[qix.? + 1 ..];
                var pairs = std.mem.split(u8, query, "&");
                while (pairs.next()) |pair| {
                    const eix = std.mem.indexOf(u8, pair, "=");
                    const key = pair[0..eix.?];
                    const val = pair[eix.? + 1 ..];
                    params.put(key, val) catch unreachable;
                }
            }
            var it = std.mem.split(u8, path, "/");
            var cur = self;

            while (it.next()) |part| {
                if (part.len == 0) {
                    continue;
                }
                var child = cur.getChild(part, false);
                if (child != null) {
                    if (child.?.wildcard) {
                        // TODO: graceful handling of this...
                        params.put(child.?.name[1..], part) catch unreachable;
                    }
                    cur = child.?;
                } else {
                    return null;
                }
            }
            return cur.value;
        }

        fn getChild(self: *Self, name: []const u8, exact: bool) ?*Self {
            var wild: ?*Self = null;
            for (self.children.items) |child| {
                if (std.mem.eql(u8, child.name, name)) {
                    return child;
                }
                if (child.wildcard) {
                    wild = child;
                }
            }
            if (wild != null and !exact) {
                return wild.?;
            }
            return null;
        }
    };
}

test "basic route" {
    var r = try RouteTree(i32).init(std.testing.allocator, "/", 12);
    defer r.deinit();

    try r.add("/api/foo/bar", 37);
    var params = Params.init(std.testing.allocator);
    defer params.deinit();
    try std.testing.expect(r.resolve("/api/foo/bar", &params) != null);
    try std.testing.expect(r.resolve("/api/foo/bar", &params).? == 37);
}

test "ambiguous wildcard" {
    var r = try RouteTree(usize).init(std.testing.allocator, "/", 33);
    defer r.deinit();

    try r.add("/api/foo/bar", 77);
    try r.add("/api/foo/:zoop", 21);
    try r.add("/api/foo/doot", 73);

    var params = Params.init(std.testing.allocator);
    defer params.deinit();
    try std.testing.expectEqual(r.resolve("/api/foo/bar", &params).?, 77);
    try std.testing.expectEqual(r.resolve("/api/foo/abc", &params).?, 21);
    try std.testing.expectEqual(r.resolve("/api/foo/doot", &params).?, 73);
}

test "with params" {
    var r = try RouteTree(i32).init(std.testing.allocator, "/", 12);
    defer r.deinit();

    try r.add("/blobs/:id", 15);
    var params = Params.init(std.testing.allocator);
    defer params.deinit();
    try std.testing.expect(r.resolve("/blobs/abc", &params) != null);
    try std.testing.expect(params.get("id") != null);
    try std.testing.expectEqualStrings("abc", params.get("id").?);
}

test "query string parameters" {
    var r = try RouteTree(usize).init(std.testing.allocator, "/", 12);
    defer r.deinit();

    try r.add("/search", 99);

    var params = Params.init(std.testing.allocator);
    defer params.deinit();

    try std.testing.expect(r.resolve("/search?q=foo&bar=baz", &params).? == 99);
    try std.testing.expect(std.mem.eql(u8, params.get("q").?, "foo"));
    try std.testing.expect(std.mem.eql(u8, params.get("bar").?, "baz"));
}
