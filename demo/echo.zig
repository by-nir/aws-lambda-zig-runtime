//! Returns the provided payload.
const lambda = @import("aws-lambda");

pub fn main() void {
    lambda.handle(handler, .{});
}

fn handler(_: lambda.Context, event: []const u8) ![]const u8 {
    return event;
}
