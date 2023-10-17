const std = @import("std");

fn readNBytes(allocator: *const std.mem.Allocator, filename: []const u8, n: usize) ![]const u8 {
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    var data = try allocator.alloc(u8, n);
    var buf = try allocator.alloc(u8, 4096);

    var written: usize = 0;
    while (data.len < n) {
        var nwritten = try file.read(buf);
        @memcpy(data[written..], buf[0..nwritten]);
        written += nwritten;
    }

    std.debug.assert(data.len == n);
    return data;
}

const ThreadInfo = struct {
    file: *const std.fs.File,
    data: []const u8,
    offset: usize,
    workSize: usize,
    allocator: *const std.mem.Allocator,
};

const outFile = "out.bin";
const chunkSize = 4096;

fn pwriteWorker(info: *ThreadInfo) void {
    var i: usize = info.offset;
    var written: usize = 0;
    while (i < info.offset + info.workSize) : (i += chunkSize) {
        const size = @min(chunkSize, (info.offset + info.workSize) - i);
        const n = info.file.pwrite(info.data[i .. i + size], i) catch unreachable;
        written += n;
        std.debug.assert(n <= chunkSize);
        std.debug.assert(n == size);
    }
    std.debug.assert(written == info.workSize);
}

fn threadsAndPwrite(comptime nWorkers: u8, allocator: *const std.mem.Allocator, x: []const u8) !void {
    const file = try std.fs.cwd().createFile(outFile, .{ .truncate = true });

    const t1 = try std.time.Instant.now();

    var workers: [nWorkers]std.Thread = undefined;
    var workerInfo: [nWorkers]ThreadInfo = undefined;
    const workSize = x.len / nWorkers;
    for (&workers, 0..) |*worker, i| {
        workerInfo[i] = ThreadInfo{
            .file = &file,
            .data = x,
            .offset = i * workSize,
            .workSize = workSize,
            .allocator = allocator,
        };
        worker.* = try std.Thread.spawn(.{}, pwriteWorker, .{&workerInfo[i]});
    }

    for (&workers) |*worker| {
        worker.join();
    }

    const t2 = try std.time.Instant.now();
    const s = @as(f64, @floatFromInt(t2.since(t1))) / std.time.ns_per_s;
    try std.io.getStdOut().writer().print(
        "{}_threads_pwrite,{d},{d}\n",
        .{ nWorkers, s, @as(f64, @floatFromInt(x.len)) / s },
    );

    file.close();

    std.debug.assert(std.mem.eql(u8, try readNBytes(allocator, outFile, x.len), x));
}

fn pwriteIOUringWorker(info: *ThreadInfo, nEntries: u13) void {
    var ring = std.os.linux.IO_Uring.init(nEntries, 0) catch |err| {
        std.debug.panic("Failed to initialize io_uring: {}\n", .{err});
        return;
    };
    defer ring.deinit();

    var i: usize = info.offset;
    var written: i32 = 0;
    std.debug.assert(chunkSize == 4096);

    std.debug.assert(nEntries == 128 or nEntries == 1);

    var copy = nEntries;
    // I broke arithmetic in Zig.
    // const entryChunk: u64 = chunkSize * nEntries; // this causes a nonsensical integer overflow.
    var entryChunk: u64 = 0;
    while (copy > 0) : (copy -= 1) {
        entryChunk += chunkSize;
    }

    while (i < info.offset + info.workSize) : (i += entryChunk) {
        var j: usize = 0;
        while (j < nEntries) : (j += 1) {
            const base = i + j * chunkSize;
            if (base >= info.offset + info.workSize) {
                break;
            }
            const size = @min(chunkSize, (info.offset + info.workSize) - base);
            _ = ring.write(0, info.file.handle, info.data[base .. base + size], base) catch unreachable;
        }

        // In the final round of calls, there may be less than
        // nEntries and that's ok.
        const submitted = ring.submit() catch unreachable;
        std.debug.assert(submitted <= nEntries);

        var entries: usize = 0;
        while (entries < submitted) : (entries += 1) {
            const cqe = ring.copy_cqe() catch unreachable;
            if (cqe.err() != .SUCCESS) {
                @panic("Request failed");
            }

            const n = cqe.res;
            written += n;
            std.debug.assert(n <= chunkSize);
        }
    }
    std.debug.assert(written == info.workSize);
}

fn threadsAndIOUringPwrite(comptime nWorkers: u8, allocator: *const std.mem.Allocator, x: []const u8, entries: u13) !void {
    const file = try std.fs.cwd().createFile(outFile, .{ .truncate = true });

    const t1 = try std.time.Instant.now();

    var workers: [nWorkers]std.Thread = undefined;
    var workerInfo: [nWorkers]ThreadInfo = undefined;
    const workSize = x.len / nWorkers;
    for (&workers, 0..) |*worker, i| {
        workerInfo[i] = ThreadInfo{
            .file = &file,
            .data = x,
            .offset = i * workSize,
            .workSize = workSize,
            .allocator = allocator,
        };
        worker.* = try std.Thread.spawn(.{}, pwriteIOUringWorker, .{ &workerInfo[i], entries });
    }

    for (&workers) |*worker| {
        worker.join();
    }

    const t2 = try std.time.Instant.now();
    const s = @as(f64, @floatFromInt(t2.since(t1))) / std.time.ns_per_s;
    try std.io.getStdOut().writer().print(
        "{}_threads_iouring_pwrite_{}_entries,{d},{d}\n",
        .{ nWorkers, entries, s, @as(f64, @floatFromInt(x.len)) / s },
    );

    file.close();

    std.debug.assert(std.mem.eql(u8, try readNBytes(allocator, outFile, x.len), x));
}

pub fn main() !void {
    var allocator = &std.heap.page_allocator;

    var x = try readNBytes(allocator, "/dev/random", 4096 * 100_000);
    defer allocator.free(x);

    std.debug.assert(x.len == 4096 * 100_000);

    var run: usize = 0;
    while (run < 10) : (run += 1) {
        {
            const file = try std.fs.cwd().createFile(outFile, .{ .truncate = true });

            const t1 = try std.time.Instant.now();

            var i: usize = 0;
            while (i < x.len) : (i += chunkSize) {
                const n = try file.write(x[i .. i + chunkSize]);
                std.debug.assert(n == chunkSize);
            }

            const t2 = try std.time.Instant.now();
            const s = @as(f64, @floatFromInt(t2.since(t1))) / std.time.ns_per_s;
            try std.io.getStdOut().writer().print(
                "blocking,{d},{d}\n",
                .{ s, @as(f64, @floatFromInt(x.len)) / s },
            );

            file.close();

            std.debug.assert(std.mem.eql(u8, try readNBytes(allocator, outFile, x.len), x));
        }

        try threadsAndPwrite(1, allocator, x);
        try threadsAndPwrite(10, allocator, x);

        try threadsAndIOUringPwrite(1, allocator, x, 1);
        try threadsAndIOUringPwrite(1, allocator, x, 128);

        try threadsAndIOUringPwrite(10, allocator, x, 1);
        try threadsAndIOUringPwrite(10, allocator, x, 128);

        try threadsAndIOUringPwrite(100, allocator, x, 1);
        try threadsAndIOUringPwrite(100, allocator, x, 128);
    }
}
