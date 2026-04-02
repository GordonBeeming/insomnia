// IPCClient.swift — InsomniaCore
//
// Unix domain socket client for sending IPC commands to the GUI server.
// Used by the CLI to communicate with the running GUI application.
// Uses the same 4-byte big-endian length prefix + JSON wire format as the server.

import Foundation

/// Unix domain socket client for sending commands to the Insomnia GUI.
///
/// Connects to the IPC server's Unix domain socket, sends a command,
/// and reads the response. Each `send` call creates a new connection
/// (the server closes connections after each request/response pair).
public final class IPCClient {
    // MARK: - Properties

    /// The path to the Unix domain socket to connect to.
    public let socketPath: String

    // MARK: - Initialization

    /// Creates an IPC client targeting the given socket path.
    ///
    /// - Parameter socketPath: The Unix domain socket path. Defaults to the standard location.
    public init(socketPath: String = IPCServer.defaultSocketPath) {
        self.socketPath = socketPath
    }

    // MARK: - Sending Commands

    /// Sends a command to the IPC server and returns the response.
    ///
    /// Creates a new socket connection, serializes the command as JSON with
    /// a 4-byte big-endian length prefix, sends it, reads the response in
    /// the same format, and returns the decoded response.
    ///
    /// - Parameter command: The IPC command to send.
    /// - Returns: The server's response.
    /// - Throws: `IPCError` if connection, send, or receive fails.
    public func send(_ command: IPCCommand) throws -> IPCResponse {
        // Create a Unix domain socket
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw IPCError.socketCreationFailed(errno: errno)
        }
        // Ensure the socket is closed when we exit this scope
        defer { close(fd) }

        // Configure the socket address
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        // Copy the socket path into the sockaddr structure
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: maxLen) { dest in
                for i in 0..<min(pathBytes.count, maxLen) {
                    dest[i] = pathBytes[i]
                }
            }
        }

        // Connect to the server
        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            throw IPCError.connectionFailed(errno: errno)
        }

        // Encode the command as JSON
        let encoder = JSONEncoder()
        let commandData = try encoder.encode(command)

        // Write the 4-byte big-endian length prefix
        let length = UInt32(commandData.count)
        var lengthBytes: [UInt8] = [
            UInt8((length >> 24) & 0xFF),
            UInt8((length >> 16) & 0xFF),
            UInt8((length >> 8) & 0xFF),
            UInt8(length & 0xFF),
        ]
        // Send the length prefix
        guard write(fd, &lengthBytes, 4) == 4 else {
            throw IPCError.sendFailed
        }
        // Send the JSON payload
        let written = commandData.withUnsafeBytes { ptr in
            write(fd, ptr.baseAddress!, commandData.count)
        }
        guard written == commandData.count else {
            throw IPCError.sendFailed
        }

        // Read the response length prefix (4 bytes)
        var responseLengthBytes = [UInt8](repeating: 0, count: 4)
        guard read(fd, &responseLengthBytes, 4) == 4 else {
            throw IPCError.receiveFailed
        }

        // Decode the big-endian response length
        let responseLength = Int(
            UInt32(responseLengthBytes[0]) << 24
            | UInt32(responseLengthBytes[1]) << 16
            | UInt32(responseLengthBytes[2]) << 8
            | UInt32(responseLengthBytes[3])
        )

        // Read the response payload
        var responsePayload = [UInt8](repeating: 0, count: responseLength)
        guard read(fd, &responsePayload, responseLength) == responseLength else {
            throw IPCError.receiveFailed
        }

        // Decode and return the response
        let decoder = JSONDecoder()
        let responseData = Data(responsePayload)
        guard let response = try? decoder.decode(IPCResponse.self, from: responseData) else {
            throw IPCError.decodingFailed
        }
        return response
    }

    // MARK: - Status Checks

    /// Checks whether the GUI application is running by testing socket connectivity.
    ///
    /// Attempts to connect to the Unix domain socket. If the connection succeeds,
    /// the GUI is considered to be running. This does not send any commands.
    ///
    /// - Returns: `true` if the GUI's IPC server is accessible.
    public var isGUIRunning: Bool {
        // Create a test socket
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        // Close the socket when done
        defer { close(fd) }

        // Try to connect to the server socket
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        // Copy the path
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: maxLen) { dest in
                for i in 0..<min(pathBytes.count, maxLen) {
                    dest[i] = pathBytes[i]
                }
            }
        }

        // Attempt connection — success means the server is running
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        // Return true if the connection succeeded
        return result == 0
    }
}
