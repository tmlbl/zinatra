const std = @import("std");

// MimeMap is a string map from file extensions to HTTP mime types. It is
// lazy-loaded as a global variable on first use
var mimeMap: ?std.StringHashMap([]const u8) = null;

// MimeType represents a mime type header value and its associated extensions
const MimeType = struct {
    name: []const u8,
    extensions: []const []const u8,
};

const mimeTypes = [_]MimeType{
    MimeType{ .name = "text/html", .extensions = &[_][]const u8{ ".html", ".htm" } },
    MimeType{ .name = "text/javascript", .extensions = &[_][]const u8{".js"} },
    MimeType{ .name = "text/css", .extensions = &[_][]const u8{".css"} },
    MimeType{ .name = "image/gif", .extensions = &[_][]const u8{".gif"} },
    MimeType{ .name = "image/jpeg", .extensions = &[_][]const u8{ ".jpeg", ".jpg" } },
    MimeType{ .name = "image/vnd.microsoft.icon", .extensions = &[_][]const u8{".ico"} },
};

// Lazy-load the MimeMap
pub fn getMimeMap() std.StringHashMap([]const u8) {
    if (mimeMap == null) {
        mimeMap = std.StringHashMap([]const u8).init(std.heap.page_allocator);
        for (mimeTypes) |mt| {
            for (mt.extensions) |ext| {
                // if this fails, we just have to bail
                mimeMap.?.put(ext, mt.name) catch unreachable;
            }
        }
    }
    return mimeMap.?;
}
