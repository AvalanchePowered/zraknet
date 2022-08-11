const std = @import("std");
const os = std.os;
const net = std.net;
const log = std.log;
const testing = std.testing;

const RakNetError = error{ AlreadyStarted, AddressInUse, BindingError, SocketError, NoSocket };

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
        defer self.alive = true;

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
    }

    /// Safely closes the socket if it's running
    /// and frees resources if there are any
    pub fn close(self: *RakNet) RakNetError!void {
        if (!self.isAlive()) {
            log.debug("Cannot close an unitialized socket!", .{});
            return RakNetError.NoSocket;
        }

        self.alive = false;

        os.closeSocket(self.socket.?);
    }

    pub fn isAlive(self: *RakNet) bool {
        return self.alive;
    }
};

/// Creates a raknet instance listening on the given address and port
pub fn startup(max_connections: usize, hostname: []const u8, port: u16) !*RakNet {
    var instance = &RakNet{ .max_connections = max_connections };

    // Tries to parse the given address
    const address = try net.Address.parseIp4(hostname, port);
    try instance.listen(address);

    return instance;
}

test "test singleton" {
    _ = try startup(10, "0.0.0.0", 19132);
    try testing.expectError(RakNetError.AddressInUse, startup(10, "0.0.0.0", 19132));
}
