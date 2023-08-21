const std = @import("std");

pub fn RouteNode(comptime T: type) type {
    return struct {
        name: []const u8,
        children: std.ArrayList(Self),
        value: T,

        const Self = @This();

        pub fn init(a: std.mem.Allocator, name: []const u8, value: T) !Self {
            return Self{
                .name = name,
                .children = std.ArrayList(Self).init(a),
                .value = value,
            };
        }

        pub fn deinit(self: *Self) void {
            self.children.deinit();
        }

        pub fn addChild(self: *Self, c: Self) !void {
            try self.children.append(c);
        }

        pub fn getChild(self: *Self, name: []const u8) ?Self {
            for (self.children.items) |child| {
                if (std.mem.eql(u8, child.name, name)) {
                    return child;
                }
            }
            return null;
        }
    };
}

const t = @import("testing");

test "routenode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        _ = gpa.deinit();
    }
    var r = try RouteNode(i32).init(gpa.allocator(), "foo", 12);
    defer r.deinit();
    var child = try RouteNode(i32).init(gpa.allocator(), "bar", 13);
    defer child.deinit();

    std.debug.assert(r.getChild("bar") == null);

    _ = try r.addChild(child);
    std.debug.assert(std.mem.eql(u8, r.getChild("bar").?.name, child.name));
}
