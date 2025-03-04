const std = @import("std");
const DeepSeek = @import("DeepSeek.zig");

pub fn main() !void {
    const std_out = std.io.getStdOut().writer();
    const std_in = std.io.getStdIn().reader();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const api_key = try std.process.getEnvVarOwned(allocator, "LLM_CLIENT_API_KEY");
    defer allocator.free(api_key);

    var ds = try DeepSeek.init(api_key, allocator);
    defer ds.deinit();

    var buf: [1024]u8 = undefined;

    while (true) {
        _ = try std_out.write("Ask> ");

        // Ctrl+D on Unix or Ctrl+Z on Windows to signal EOF
        const line = try std_in.readUntilDelimiterOrEof(&buf, '\n') orelse break;

        if (line.len != 0) {
            const model = try ds.chatCompletion(line);
            defer model.deinit();

            _ = try std_out.writeAll(model.value.choices[0].message.content);
        } else continue;

        _ = try std_out.write("\n");
    }

    _ = try std_out.write("Bye!");
}
