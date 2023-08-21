const std = @import("std");

const Request = std.http.Server.Request;
const Response = std.http.Server.Response;

pub const Handler = *const fn (*Request, *Response) anyerror!void;
