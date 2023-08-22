const std = @import("std");

pub fn RouteTree(comptime T: type) type {
    return struct {
        a: std.mem.Allocator,
        name: []const u8,
        children: std.ArrayList(*Self),
        value: ?T,

        const Self = @This();

        pub fn init(a: std.mem.Allocator, name: []const u8, value: ?T) Self {
            return Self{
                .a = a,
                .name = name,
                .children = std.ArrayList(*Self).init(a),
                .value = value,
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.children.items) |child| {
                child.deinit();
                self.a.free(child);
            }
            self.children.deinit();
        }

        pub fn add(self: *Self, path: []const u8, value: T) !void {
            _ = value;
            var it = std.mem.split(u8, path, "/");
            var cur = self;

            while (it.next()) |part| {
                if (part.len == 0) {
                    continue;
                }
                if (!cur.hasChild(part)) {
                    var new = Self.init(self.a, part, null);
                    try cur.children.append(&new);
                    cur = &new;
                }
            }

            std.debug.print("leaf node: {s}\n", .{cur.name});
        }

        fn hasChild(self: *Self, name: []const u8) bool {
            for (self.children.items) |child| {
                if (std.mem.eql(u8, child.name, name)) {
                    return true;
                }
            }
            return false;
        }
    };
}

const t = @import("testing");

test "RouteTree" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        _ = gpa.deinit();
    }
    var r = RouteTree(i32).init(gpa.allocator(), "/", 12);
    defer r.deinit();

    try r.add("/api/foo/bar", 37);
}
