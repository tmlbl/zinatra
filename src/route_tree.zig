const std = @import("std");

const types = @import("./types.zig");

pub const RouteTable = struct {
    allocator: std.mem.Allocator,
    nodeList: std.ArrayList(*RouteNode),

    get: RouteNode,

    pub fn init(a: std.mem.Allocator) !RouteTable {
        return RouteTable{
            .allocator = a,
            .nodeList = std.ArrayList(*RouteNode).init(a),
            .get = try RouteNode.init(a, ""),
        };
    }

    pub fn deinit(rt: *RouteTable) void {
        // Clean up nodes
        for (rt.nodeList.items) |np| {
            std.log.debug("Deinitting...", .{});
            np.deinit();
        }
        rt.nodeList.deinit();
    }

    pub fn add(rt: *RouteTable, meth: std.http.Method, path: []const u8) !void {
        var root = switch (meth) {
            std.http.Method.GET => rt.get,
            else => return error.IndexOutOfBounds,
        };
        var piter = std.mem.split(u8, path, "/");
        while (piter.next()) |part| {
            var child = try RouteNode.init(rt.allocator, part);
            try root.addChild(child);
            try rt.nodeList.append(&child);
            root = child;
        }
    }

    pub fn resolve(rt: *RouteTable, meth: std.http.Method, path: []const u8) ?types.Handler {
        _ = rt;
        _ = path;
        _ = meth;
        return null;
    }
};

pub const RouteNode = struct {
    name: std.ArrayList(u8),
    children: std.ArrayList(RouteNode),
    // handler: types.Handler,

    pub fn init(a: std.mem.Allocator, name: []const u8) !RouteNode {
        var n = std.ArrayList(u8).init(a);
        try n.appendSlice(name);
        return RouteNode{
            .name = n,
            .children = std.ArrayList(RouteNode).init(a),
        };
    }

    pub fn deinit(self: *RouteNode) void {
        self.name.deinit();
        self.children.deinit();
    }

    pub fn addChild(self: *RouteNode, c: RouteNode) !void {
        try self.children.append(c);
    }

    pub fn getChild(self: *RouteNode, name: []const u8) ?RouteNode {
        for (self.children.items) |child| {
            if (std.mem.eql(u8, child.name.items, name)) {
                return child;
            }
        }
        return null;
    }
};

const t = @import("testing");

test "routenode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        _ = gpa.deinit();
    }
    var r = try RouteNode.init(gpa.allocator(), "foo");
    defer r.deinit();
    var child = try RouteNode.init(gpa.allocator(), "bar");
    defer child.deinit();

    std.debug.assert(r.getChild("bar") == null);

    _ = try r.addChild(child);
    std.debug.assert(std.mem.eql(u8, r.getChild("bar").?.name.items, child.name.items));
}

test "routing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        _ = gpa.deinit();
    }
    var r = try RouteTable.init(gpa.allocator());
    defer r.deinit();

    const handler = r.resolve(std.http.Method.HEAD, "/foo");

    try r.add(std.http.Method.GET, "/foo");
    std.debug.assert(handler == null);
}
