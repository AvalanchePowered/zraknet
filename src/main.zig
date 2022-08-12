const std = @import("std");
const os = std.os;
const net = std.net;
const log = std.log;
const fmt = std.fmt;
const time = std.time;
const testing = std.testing;

const conn = @import("conn.zig");

const RakNetError = error{ AlreadyStarted, AddressInUse, BindingError, SocketError, NoSocket };

// Still under heavy development
// pub const io_mode = .evented;

pub const MAX_MTU_SIZE: u16 = 1500;

const RakNet = struct {
    // Whatever the raknet instance is running or not
    alive: bool = false,
    // Defines the maximum clients that can connect to the instance
    max_connections: usize,
    // For this use case null might be better than undefined
    // because the socket HAS to be an actual socket later then
    // while undefined may have 0 as value, and we want to avoid
    // this behaviour
    socket: ?os.socket_t = null,

    /// Creates the socket instance and starts listening for packets on a new thread
    pub fn listen(self: *RakNet, address: net.Address) RakNetError!void {
        // Handle twice listening, better to handle every case
        if (self.isAlive()) return RakNetError.AlreadyStarted;
        // Listen can be only called once!
        self.alive = true;

        self.socket = os.socket(os.AF.INET, os.SOCK.DGRAM | os.SOCK.NONBLOCK, 0) catch {
            log.debug("Failed to create socket resource!", .{});
            return RakNetError.SocketError;
        };

        os.bind(self.socket.?, &address.any, @sizeOf(os.sockaddr.in)) catch |err| switch (err) {
            os.BindError.AddressInUse, os.BindError.AlreadyBound => {
                log.debug("Failed to bind, address already in use!", .{});
                return RakNetError.AddressInUse;
            },
            else => {
                log.debug("Failed to bind! generic reason", .{});
                return RakNetError.BindingError;
            },
        };

        // TODO: handle error cases
        // When the thread finishes to run the given method, it will automatically freed up from memory
        // we will lose any reference to that thread but whe don't care
        const thread = std.Thread.spawn(.{}, receive, .{ self, std.Thread.getCurrentId() }) catch unreachable;
        thread.setName("zRakNet: socket") catch unreachable;
        thread.detach();
    }

    /// Reads packets continuously in a new thread
    fn receive(self: *RakNet, caller_thread_id: std.Thread.Id) RakNetError!void {
        if (!self.isAlive()) {
            log.err("Cannot read packets without a socket!", .{});
            return RakNetError.NoSocket;
        }

        // Make sure we are not in the main thread for some unknown reasons
        const currentThreadId = std.Thread.getCurrentId();
        if (caller_thread_id == currentThreadId) {
            log.err("Cannot receive packets from the main thread!", .{});
            return;
        }

        log.debug("Listening for packets on thread id={d}", .{currentThreadId});
        var buffer: [1024]u8 = undefined;
        while (self.isAlive()) {
            const len = os.recv(self.socket.?, &buffer, 0) catch continue;
            log.debug("{any}", .{fmt.fmtSliceHexLower(buffer[0..len])});
        }
    }

    /// Accept is used to retrive connected clients from a Fifo queue
    pub fn accept(self: *RakNet) RakNetError!?*conn.Conn {
        if (!self.isAlive()) {
            log.debug("Cannot accept connections without a socket!", .{});
            return RakNetError.NoSocket;
        }
        return null;
    }

    /// Safely closes the socket if it's running
    /// and frees resources if there are any
    pub fn close(self: *RakNet) RakNetError!void {
        if (!self.isAlive()) {
            log.debug("Cannot close an unitialized socket!", .{});
            return RakNetError.NoSocket;
        }

        self.alive = false;

        // Free resources
        os.closeSocket(self.socket.?);
        self.socket = null;
    }

    pub fn isAlive(self: *RakNet) bool {
        return self.alive;
    }
};

/// Creates a raknet instance listening on the given address and port
pub fn startup(max_connections: usize, hostname: []const u8, port: u16) !RakNet {
    var instance = RakNet{ .max_connections = max_connections };

    // Tries to parse the given address
    const address = try net.Address.parseIp4(hostname, port);
    try instance.listen(address);

    return instance;
}

test "test intance init & close" {
    var instance = try startup(10, "0.0.0.0", 19132);
    try testing.expectEqual(RakNet, @TypeOf(instance));
    try instance.close();
    try testing.expect(instance.isAlive() == false);
}
