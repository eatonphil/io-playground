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

fn createFile(f: []const u8, directIO: bool) !std.fs.File {
    const file = try std.fs.cwd().createFile(f, .{
        .truncate = true,
    });

    if (directIO) {
        const flags: usize = try std.os.fcntl(file.handle, std.os.linux.F.GETFL, 0);
        _ = try std.os.fcntl(file.handle, std.os.linux.F.SETFL, flags | std.os.O.DIRECT);
    }
    return file;
}

const Benchmark = struct {
    t: std.time.Timer,
    file: std.fs.File,
    data: []const u8,
    allocator: *const std.mem.Allocator,

    fn init(
        allocator: *const std.mem.Allocator,
        name: []const u8,
        directIO: bool,
        data: []const u8,
    ) !Benchmark {
        try std.io.getStdOut().writer().print("{s}", .{name});
        if (directIO) {
            try std.io.getStdOut().writer().print("_directio", .{});
        }

        var file = try createFile(outFile, directIO);

        return Benchmark{
            .t = try std.time.Timer.start(),
            .file = file,
            .data = data,
            .allocator = allocator,
        };
    }

    fn stop(b: *Benchmark) void {
        const s = @as(f64, @floatFromInt(b.t.read())) / std.time.ns_per_s;
        std.io.getStdOut().writer().print(
            ",{d},{d}\n",
            .{ s, @as(f64, @floatFromInt(b.data.len)) / s },
        ) catch unreachable;

        b.file.close();

        var in = readNBytes(b.allocator, outFile, b.data.len) catch unreachable;
        std.debug.assert(std.mem.eql(u8, in, b.data));
        b.allocator.free(in);
    }
};

const ThreadInfo = struct {
    file: *const std.fs.File,
    data: []const u8,
    offset: usize,
    workSize: usize,
    allocator: *const std.mem.Allocator,
};

const outFile = "out.bin";
const bufferSize: u64 = 4096; // 1048576; // 1mib

fn pwriteWorker(info: *ThreadInfo) void {
    var i: usize = info.offset;
    var written: usize = 0;
    while (i < info.offset + info.workSize) : (i += bufferSize) {
        const size = @min(bufferSize, (info.offset + info.workSize) - i);
        const n = info.file.pwrite(info.data[i .. i + size], i) catch unreachable;
        written += n;
        std.debug.assert(n <= bufferSize);
        std.debug.assert(n == size);
    }
    std.debug.assert(written == info.workSize);
}

fn threadsAndPwrite(
    comptime nWorkers: u8,
    allocator: *const std.mem.Allocator,
    x: []const u8,
    directIO: bool,
) !void {
    const name = try std.fmt.allocPrint(allocator.*, "{}_threads_pwrite", .{nWorkers});
    defer allocator.free(name);
    var b = try Benchmark.init(allocator, name, directIO, x);
    defer b.stop();

    var workers: [nWorkers]std.Thread = undefined;
    var workerInfo: [nWorkers]ThreadInfo = undefined;
    const workSize = x.len / nWorkers;
    for (&workers, 0..) |*worker, i| {
        workerInfo[i] = ThreadInfo{
            .file = &b.file,
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
}

fn pwriteIOUringWorker(info: *ThreadInfo, nEntries: u13) void {
    var ring = std.os.linux.IO_Uring.init(nEntries, 0) catch |err| {
        std.debug.panic("Failed to initialize io_uring: {}\n", .{err});
        return;
    };
    defer ring.deinit();

    var i: usize = info.offset;
    var written: usize = 0;

    var cqes = info.allocator.alloc(std.os.linux.io_uring_cqe, nEntries) catch unreachable;
    defer info.allocator.free(cqes);

    var totalSubs: usize = 0;
    while (i < info.offset + info.workSize or written < info.workSize) {
        // Fill in as many submissions as we can.
        while (true) {
            if (i >= info.offset + info.workSize) {
                break;
            }
            const size = @min(bufferSize, (info.offset + info.workSize) - i);
            _ = ring.write(0, info.file.handle, info.data[i .. i + size], i) catch |e| switch (e) {
                error.SubmissionQueueFull => break,
                else => unreachable,
            };
            i += size;
            totalSubs += 1;
        }

        _ = ring.submit_and_wait(0) catch unreachable;

        const received = ring.copy_cqes(cqes, 0) catch unreachable;

        for (cqes[0..received]) |*cqe| {
            if (cqe.err() != .SUCCESS) {
                @panic("Request failed");
            }

            std.debug.assert(cqe.res >= 0);
            const n = @as(usize, @intCast(cqe.res));
            written += n;
            std.debug.assert(n <= bufferSize);
        }
    }
    std.debug.assert(written == info.workSize);
}

fn threadsAndIOUringPwrite(
    comptime nWorkers: u8,
    allocator: *const std.mem.Allocator,
    x: []const u8,
    entries: u13,
    directIO: bool,
) !void {
    const name = try std.fmt.allocPrint(allocator.*, "{}_threads_iouring_pwrite_{}_entries", .{ nWorkers, entries });
    defer allocator.free(name);
    var b = try Benchmark.init(allocator, name, directIO, x);
    defer b.stop();

    var workers: [nWorkers]std.Thread = undefined;
    var workerInfo: [nWorkers]ThreadInfo = undefined;
    const workSize = x.len / nWorkers;
    for (&workers, 0..) |*worker, i| {
        workerInfo[i] = ThreadInfo{
            .file = &b.file,
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
}

pub fn main() !void {
    var allocator = &std.heap.page_allocator;

    const SIZE = 1073741824; // 1GiB
    var x = try readNBytes(allocator, "/dev/random", SIZE);
    defer allocator.free(x);

    var args = std.process.args();
    var directIO = false;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--directio")) {
            directIO = true;
        }
    }

    var run: usize = 0;
    while (run < 10) : (run += 1) {
        {
            var b = try Benchmark.init(allocator, "blocking", directIO, x);
            defer b.stop();

            var i: usize = 0;
            while (i < x.len) : (i += bufferSize) {
                const size = @min(bufferSize, x.len - i);
                const n = try b.file.write(x[i .. i + size]);
                std.debug.assert(n == size);
            }
        }

        try threadsAndPwrite(1, allocator, x, directIO);
        try threadsAndPwrite(10, allocator, x, directIO);

        try threadsAndIOUringPwrite(1, allocator, x, 1, directIO);
        try threadsAndIOUringPwrite(1, allocator, x, 128, directIO);

        try threadsAndIOUringPwrite(10, allocator, x, 1, directIO);
        try threadsAndIOUringPwrite(10, allocator, x, 128, directIO);

        try threadsAndIOUringPwrite(100, allocator, x, 1, directIO);
        try threadsAndIOUringPwrite(100, allocator, x, 128, directIO);
    }
}
