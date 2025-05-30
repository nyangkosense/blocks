const std = @import("std");
const time = std.time;
const fs = std.fs;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const StatusBlock = struct {
    name: []const u8,
    content: []const u8,
    separator: []const u8,

    pub fn format(self: StatusBlock, allocator: Allocator) ![]const u8 {
        return try std.fmt.allocPrint(allocator, "{s}{s}", .{ self.content, self.separator });
    }
};

const StatusBar = struct {
    blocks: ArrayList(StatusBlock),
    allocator: Allocator,

    pub fn init(allocator: Allocator) StatusBar {
        return StatusBar{
            .blocks = ArrayList(StatusBlock).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *StatusBar) void {
        for (self.blocks.items) |block| {
            self.allocator.free(block.content);
        }
        self.blocks.deinit();
    }

    pub fn addBlock(self: *StatusBar, name: []const u8, content: []const u8, separator: []const u8) !void {
        const contentDup = try self.allocator.dupe(u8, content);
        try self.blocks.append(StatusBlock{
            .name = name,
            .content = contentDup,
            .separator = separator,
        });
    }

    pub fn updateBlock(self: *StatusBar, name: []const u8, content: []const u8) !void {
        for (self.blocks.items, 0..) |block, i| {
            if (std.mem.eql(u8, block.name, name)) {
                self.allocator.free(self.blocks.items[i].content);
                self.blocks.items[i].content = try self.allocator.dupe(u8, content);
                return;
            }
        }

        try self.addBlock(name, content, " | ");
    }

    pub fn toString(self: StatusBar) ![]const u8 {
        var result = ArrayList(u8).init(self.allocator);
        defer result.deinit();

        for (self.blocks.items) |block| {
            const formatted = try block.format(self.allocator);
            defer self.allocator.free(formatted);
            try result.appendSlice(formatted);
        }

        return result.toOwnedSlice();
    }

    pub fn setRoot(self: StatusBar) !void {
        const text = try self.toString();
        defer self.allocator.free(text);

        const args = [_][]const u8{ "xsetroot", "-name", text };

        var child = std.ChildProcess.init(&args, self.allocator);
        const term = try child.spawnAndWait();

        if (term.Exited != 0) {
            return error.CommandFailed;
        }
    }
};

fn getBatteryPercentage(allocator: Allocator) ![]const u8 {
    const file = fs.openFileAbsolute("/sys/class/power_supply/BAT0/capacity", .{}) catch |err| {
        if (err == error.FileNotFound) {
            return try allocator.dupe(u8, "No battery");
        }
        return err;
    };
    defer file.close();

    var buffer: [10]u8 = undefined;
    const bytes_read = try file.readAll(&buffer);
    const battery_str = std.mem.trimRight(u8, buffer[0..bytes_read], "\n");

    return try std.fmt.allocPrint(allocator, "BAT: {s}%", .{battery_str});
}

fn getDateTime(allocator: Allocator) ![]const u8 {
    const c = @cImport({
        @cInclude("time.h");
    });

    var t: c.time_t = c.time(null);
    const tm = c.localtime(&t);

    return try std.fmt.allocPrint(allocator, "{d:0>4}/{d:0>2}/{d:0>2} {d:0>2}:{d:0>2}", .{
        @as(u16, @intCast(tm.*.tm_year + 1900)),
        @as(u8, @intCast(tm.*.tm_mon + 1)),
        @as(u8, @intCast(tm.*.tm_mday)),
        @as(u8, @intCast(tm.*.tm_hour)),
        @as(u8, @intCast(tm.*.tm_min)),
    });
}

fn getMemoryInfo(allocator: Allocator) ![]const u8 {
    const file = fs.openFileAbsolute("/proc/meminfo", .{}) catch |err| {
        if (err == error.FileNotFound) {
            return try allocator.dupe(u8, "MEM: unknown");
        }
        return err;
    };
    defer file.close();

    var buffer: [4096]u8 = undefined;
    const bytes_read = try file.readAll(&buffer);
    const content = buffer[0..bytes_read];

    var total_kb: u64 = 0;
    var available_kb: u64 = 0;

    var lines = mem.split(u8, content, "\n");
    while (lines.next()) |line| {
        if (mem.startsWith(u8, line, "MemTotal:")) {
            var parts = mem.split(u8, line, " ");
            _ = parts.next(); // Skip "MemTotal:"
            while (parts.next()) |part| {
                if (part.len == 0) continue;
                total_kb = std.fmt.parseInt(u64, part, 10) catch 0;
                break;
            }
        } else if (mem.startsWith(u8, line, "MemAvailable:")) {
            var parts = mem.split(u8, line, " ");
            _ = parts.next(); // Skip "MemAvailable:"
            while (parts.next()) |part| {
                if (part.len == 0) continue;
                available_kb = std.fmt.parseInt(u64, part, 10) catch 0;
                break;
            }
        }
    }

    const usage_percent = if (total_kb > 0)
        @as(u64, @intFromFloat(@as(f64, @floatFromInt(total_kb - available_kb)) / @as(f64, @floatFromInt(total_kb)) * 100))
    else
        0;

    return try std.fmt.allocPrint(allocator, "MEM: {d}%", .{usage_percent});
}

fn getCpuLoad(allocator: Allocator) ![]const u8 {
    const file = fs.openFileAbsolute("/proc/loadavg", .{}) catch |err| {
        if (err == error.FileNotFound) {
            return try allocator.dupe(u8, "CPU: unknown");
        }
        return err;
    };
    defer file.close();

    var buffer: [100]u8 = undefined;
    const bytes_read = try file.readAll(&buffer);
    const content = buffer[0..bytes_read];

    var parts = mem.split(u8, content, " ");
    const load1 = parts.next() orelse "0";

    return try std.fmt.allocPrint(allocator, "CPU: {s}", .{load1});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var status_bar = StatusBar.init(allocator);
    defer status_bar.deinit();

    try status_bar.addBlock("cpu", try getCpuLoad(allocator), " | ");
    try status_bar.addBlock("memory", try getMemoryInfo(allocator), " | ");
    try status_bar.addBlock("battery", try getBatteryPercentage(allocator), " | ");
    try status_bar.addBlock("date", try getDateTime(allocator), "");

    try status_bar.setRoot();

    while (true) {
        std.time.sleep(1 * std.time.ns_per_s);

        try status_bar.updateBlock("cpu", try getCpuLoad(allocator));
        try status_bar.updateBlock("memory", try getMemoryInfo(allocator));
        try status_bar.updateBlock("battery", try getBatteryPercentage(allocator));
        try status_bar.updateBlock("date", try getDateTime(allocator));

        try status_bar.setRoot();
    }
}
