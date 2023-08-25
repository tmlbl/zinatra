const std = @import("std");

pub fn RouteTree(comptime T: type) type {
    return struct {
        a: std.mem.Allocator,
        name: []const u8,
        children: std.ArrayList(*Self),
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
                if (cur.getChild(part) == null) {
                    var new = try Self.init(self.a, part, null);
                    try cur.children.append(new);
                    cur = new;
                }
            }
            cur.value = value;
        }

        pub fn resolve(self: *Self, path: []const u8, params: std.StringHashMap([]const u8)) ?T {
            var it = std.mem.split(u8, path, "/");
            var cur = self;

            while (it.next()) |part| {
                if (part.len == 0) {
                    continue;
                }
                var child = cur.getChild(part);
                if (child != null) {
                    cur = child.?;
                } else {
                    return null;
                }
            }
            _ = params;
            return cur.value;
        }

        fn getChild(self: *Self, name: []const u8) ?*Self {
            for (self.children.items) |child| {
                if (std.mem.eql(u8, child.name, name)) {
                    return child;
                }
            }
            return null;
        }
    };
}

test "RouteTree" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        _ = gpa.deinit();
    }
    var r = try RouteTree(i32).init(gpa.allocator(), "/", 12);
    defer r.deinit();

    try r.add("/api/foo/bar", 37);
    var params = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer params.deinit();
    try std.testing.expect(r.resolve("/api/foo/bar", params) != null);
    try std.testing.expect(r.resolve("/api/foo/bar", params).? == 37);
}
