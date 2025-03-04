const std = @import("std");
const Allocator = std.mem.Allocator;

const deep_seek_base_url = "https://api.deepseek.com";
const api_path_chat_completions = "/chat/completions";

const DeepSeek = @This();

api_key: []const u8,
allocator: Allocator,

client: std.http.Client = undefined,
header_buf: []u8 = undefined,
resp_body_buf: []u8 = undefined,

pub fn init(api_key: []const u8, allocator: Allocator) !DeepSeek {
    return DeepSeek{
        .api_key = api_key,
        .allocator = allocator,

        .client = .{ .allocator = allocator },
        .header_buf = try allocator.alloc(u8, 8192),
        .resp_body_buf = try allocator.alloc(u8, 1024 * 8),
    };
}

pub fn deinit(ds: *DeepSeek) void {
    ds.allocator.free(ds.resp_body_buf);
    ds.allocator.free(ds.header_buf);
    ds.client.deinit();
}

const RequestModel = struct {
    model: []const u8,
    messages: []ModelMessage,
    stream: bool = false,

    fn create(content: []const u8, allocator: Allocator) !RequestModel {
        var messages = try allocator.alloc(ModelMessage, 1);
        messages[0] = ModelMessage{
            .role = .user,
            .content = content,
        };

        return RequestModel{
            .model = "deepseek-chat",
            .messages = messages,
        };
    }
};

pub const ModelMessage = struct {
    role: ModelMessageRole,
    content: []const u8,
};

pub const ResponseModel = struct {
    id: []const u8,
    object: []const u8,
    created: u32,
    model: []const u8,
    choices: []ModelChoice,
    usage: ModelUsage,
};

const ModelChoice = struct {
    index: u8,
    message: ModelMessage,
    finish_reason: []const u8,
};

const ModelUsage = struct {
    prompt_tokens: u32,
    completion_tokens: u32,
    total_tokens: u32,

    // prompt_tokens_details

    prompt_cache_hit_tokens: u32,
    prompt_cache_miss_tokens: u32,
};

pub const ModelMessageRole = enum {
    user,
    assistant,
};

pub fn chatCompletion(ds: *DeepSeek, question: []const u8) !std.json.Parsed(ResponseModel) {
    var full_api_path: [deep_seek_base_url.len + api_path_chat_completions.len]u8 = undefined;
    const uri = std.Uri.parse(std.fmt.bufPrint(&full_api_path, "{s}{s}", .{ deep_seek_base_url, api_path_chat_completions }) catch unreachable) catch unreachable;

    var bearer: [100]u8 = undefined;
    var request = try ds.client.open(.POST, uri, .{ .server_header_buffer = ds.header_buf, .headers = .{
        .authorization = .{ .override = std.fmt.bufPrint(&bearer, "Bearer {s}", .{ds.api_key}) catch unreachable },
        .content_type = .{ .override = "application/json" },
    } });
    defer request.deinit();

    const model = try RequestModel.create(question, ds.allocator);
    defer ds.allocator.free(model.messages);

    var json_buffer = std.ArrayList(u8).init(ds.allocator);
    defer json_buffer.deinit();

    try std.json.stringify(model, .{}, json_buffer.writer());
    const body = json_buffer.items;

    std.log.debug("Request body: {s}", .{body});

    request.transfer_encoding = .{ .content_length = body.len };

    try request.send();

    try request.writeAll(body);

    try request.finish();

    try request.wait();

    const resp_body_size = try request.reader().readAll(ds.resp_body_buf);
    const resp_text = ds.resp_body_buf[0..resp_body_size];

    std.log.debug("Response body: {s}", .{resp_text});

    return try std.json.parseFromSlice(ResponseModel, ds.allocator, resp_text, .{ .ignore_unknown_fields = true });
}
