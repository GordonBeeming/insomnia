// IPCServer.swift — InsomniaCore
//
// Unix domain socket server for receiving IPC commands from the CLI.
// Listens on ~/Library/Application Support/Insomnia/insomnia.sock
// using DispatchSource for non-blocking I/O. Messages use a 4-byte
// big-endian length prefix followed by JSON-encoded command/response data.

import Foundation

/// Unix domain socket server for the Insomnia IPC protocol.
///
/// The server listens for incoming connections from CLI clients,
/// reads commands, dispatches them to the CaffeinationScheduler,
/// and sends back responses. All I/O is non-blocking via DispatchSource.
public final class IPCServer {
    // MARK: - Properties

    /// The path to the Unix domain socket file.
    public let socketPath: String

    /// The scheduler that handles incoming commands.
    private let scheduler: CaffeinationScheduler

    /// The file descriptor for the listening socket.
    private var listenFD: Int32 = -1

    /// DispatchSource monitoring the listening socket for incoming connections.
    private var listenSource: DispatchSourceRead?

    /// Active client sources being tracked for cleanup on stop.
    private var clientSources: [DispatchSourceRead] = []

    /// Default socket directory path inside Application Support.
    /// Uses BuildEnvironment to separate dev and prod socket locations.
    public static var defaultSocketDirectory: String {
        // Delegate to BuildEnvironment for variant-aware path
        BuildEnvironment.socketDirectory
    }

    /// Default socket file path.
    /// Uses BuildEnvironment to separate dev and prod socket files.
    public static var defaultSocketPath: String {
        // Delegate to BuildEnvironment for variant-aware path
        BuildEnvironment.socketPath
    }

    // MARK: - Initialization

    /// Creates an IPC server with the given scheduler and socket path.
    ///
    /// - Parameters:
    ///   - scheduler: The caffeination scheduler to dispatch commands to.
    ///   - socketPath: The Unix domain socket path. Defaults to the standard location.
    public init(
        scheduler: CaffeinationScheduler,
        socketPath: String = IPCServer.defaultSocketPath
    ) {
        self.scheduler = scheduler
        self.socketPath = socketPath
    }

    // MARK: - Server Lifecycle

    /// Starts the IPC server, creating the socket and listening for connections.
    ///
    /// Creates the socket directory if needed, removes any stale socket file,
    /// binds to the Unix domain socket, and begins accepting connections.
    ///
    /// - Throws: `IPCError` if the socket cannot be created or bound.
    public func start() throws {
        // Ensure the socket directory exists
        let directory = (socketPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )
        // Remove any stale socket file from a previous run
        if FileManager.default.fileExists(atPath: socketPath) {
            try FileManager.default.removeItem(atPath: socketPath)
        }

        // Create the Unix domain socket
        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else {
            throw IPCError.socketCreationFailed(errno: errno)
        }

        // Configure the socket address structure
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        // Copy the socket path into the sun_path field
        let pathBytes = socketPath.utf8CString
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes.count <= maxLen else {
            throw IPCError.pathTooLong
        }
        // Use withUnsafeMutablePointer to write path bytes into the sockaddr_un
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: maxLen) { dest in
                for i in 0..<pathBytes.count {
                    dest[i] = pathBytes[i]
                }
            }
        }

        // Bind the socket to the address
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(listenFD, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            close(listenFD)
            throw IPCError.bindFailed(errno: errno)
        }

        // Start listening with a small backlog
        guard listen(listenFD, 5) == 0 else {
            close(listenFD)
            throw IPCError.listenFailed(errno: errno)
        }

        // Create a DispatchSource to accept connections asynchronously
        let source = DispatchSource.makeReadSource(fileDescriptor: listenFD, queue: .main)
        source.setEventHandler { [weak self] in
            self?.acceptConnection()
        }
        source.setCancelHandler { [weak self] in
            // Close the listening socket when cancelled
            if let fd = self?.listenFD, fd >= 0 {
                close(fd)
                self?.listenFD = -1
            }
        }
        // Store and activate the source
        listenSource = source
        source.activate()
    }

    /// Stops the IPC server and cleans up resources.
    ///
    /// Cancels the listening source, closes all client connections,
    /// and removes the socket file from disk.
    public func stop() {
        // Cancel the listening dispatch source
        listenSource?.cancel()
        listenSource = nil
        // Cancel all active client sources
        for source in clientSources {
            source.cancel()
        }
        clientSources.removeAll()
        // Remove the socket file so it doesn't block future starts
        try? FileManager.default.removeItem(atPath: socketPath)
    }

    // MARK: - Command Handling

    /// Handles an incoming IPC command and returns the appropriate response.
    ///
    /// Dispatches the command to the caffeination scheduler and returns
    /// a success/error/status response as appropriate.
    ///
    /// - Parameter command: The decoded IPC command to handle.
    /// - Returns: The response to send back to the client.
    public func handle(_ command: IPCCommand) -> IPCResponse {
        switch command {
        case .caffeinate:
            // Start indefinite caffeination
            do {
                try scheduler.powerManager.caffeinate()
                return .success(message: "Caffeinated indefinitely")
            } catch {
                return .error(message: "Failed to caffeinate: \(error.localizedDescription)")
            }

        case .decaffeinate:
            // Stop all caffeination
            do {
                try scheduler.cancelAll()
                return .success(message: "Decaffeinated")
            } catch {
                return .error(message: "Failed to decaffeinate: \(error.localizedDescription)")
            }

        case .toggle:
            // Toggle caffeination state
            do {
                try scheduler.powerManager.toggle()
                let newState = scheduler.powerManager.state.displayDescription
                return .success(message: "Toggled: \(newState)")
            } catch {
                return .error(message: "Failed to toggle: \(error.localizedDescription)")
            }

        case .caffeinateFor(let seconds):
            // Start timed caffeination for the specified duration
            do {
                try scheduler.startTimed(.custom(seconds))
                return .success(message: "Caffeinated for \(Int(seconds)) seconds")
            } catch {
                return .error(message: "Failed to caffeinate: \(error.localizedDescription)")
            }

        case .caffeinateUntil(let date):
            // Start timed caffeination until the specified date
            do {
                try scheduler.startUntil(date)
                return .success(message: "Caffeinated until \(date)")
            } catch {
                return .error(message: "Failed to caffeinate: \(error.localizedDescription)")
            }

        case .caffeinateWhile(let bundleID):
            // Start app-watching caffeination
            do {
                try scheduler.startWhileAppRunning(bundleIdentifier: bundleID)
                return .success(message: "Caffeinated while \(bundleID) is running")
            } catch {
                return .error(message: "Failed to caffeinate: \(error.localizedDescription)")
            }

        case .status:
            // Return current state and schedule rules
            let state = scheduler.powerManager.state
            let schedules = scheduler.scheduleRules
            return .status(state, schedules: schedules)

        case .addSchedule(let rule):
            // Add a new schedule rule
            scheduler.addScheduleRule(rule)
            return .success(message: "Schedule rule added: \(rule.displaySummary)")

        case .removeSchedule(let id):
            // Remove a schedule rule by ID
            scheduler.removeScheduleRule(id: id)
            return .success(message: "Schedule rule removed")

        case .listSchedules:
            // Return all schedule rules
            return .scheduleList(scheduler.scheduleRules)
        }
    }

    // MARK: - Private Methods

    /// Accepts an incoming client connection and sets up a read source for it.
    private func acceptConnection() {
        // Accept the incoming connection
        let clientFD = accept(listenFD, nil, nil)
        guard clientFD >= 0 else { return }

        // Create a DispatchSource to read data from the client
        let clientSource = DispatchSource.makeReadSource(fileDescriptor: clientFD, queue: .main)
        clientSource.setEventHandler { [weak self] in
            self?.handleClientData(fd: clientFD)
        }
        clientSource.setCancelHandler {
            // Close the client socket when the source is cancelled
            close(clientFD)
        }
        // Track and activate the client source
        clientSources.append(clientSource)
        clientSource.activate()
    }

    /// Reads data from a client connection, processes the command, and sends a response.
    ///
    /// Wire format: 4-byte big-endian length prefix + JSON payload.
    ///
    /// - Parameter fd: The file descriptor of the client connection.
    private func handleClientData(fd: Int32) {
        // Read the 4-byte length prefix
        var lengthBytes = [UInt8](repeating: 0, count: 4)
        let lengthRead = read(fd, &lengthBytes, 4)
        guard lengthRead == 4 else {
            // Client disconnected or read error — clean up
            cleanupClient(fd: fd)
            return
        }

        // Decode the big-endian length
        let length = Int(UInt32(lengthBytes[0]) << 24
            | UInt32(lengthBytes[1]) << 16
            | UInt32(lengthBytes[2]) << 8
            | UInt32(lengthBytes[3]))

        // Reject unreasonably large messages (limit to 1MB)
        guard length > 0, length < 1_048_576 else {
            cleanupClient(fd: fd)
            return
        }

        // Read the JSON payload
        var payload = [UInt8](repeating: 0, count: length)
        let payloadRead = read(fd, &payload, length)
        guard payloadRead == length else {
            cleanupClient(fd: fd)
            return
        }

        // Decode the command from JSON
        let data = Data(payload)
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()

        let response: IPCResponse
        do {
            let command = try decoder.decode(IPCCommand.self, from: data)
            // Handle the command and get a response
            response = handle(command)
        } catch {
            // Failed to decode the command — send an error response
            response = .error(message: "Invalid command: \(error.localizedDescription)")
        }

        // Encode the response as JSON
        guard let responseData = try? encoder.encode(response) else {
            cleanupClient(fd: fd)
            return
        }

        // Write the 4-byte length prefix
        let responseLength = UInt32(responseData.count)
        var responseLengthBytes: [UInt8] = [
            UInt8((responseLength >> 24) & 0xFF),
            UInt8((responseLength >> 16) & 0xFF),
            UInt8((responseLength >> 8) & 0xFF),
            UInt8(responseLength & 0xFF),
        ]
        write(fd, &responseLengthBytes, 4)
        // Write the JSON response payload
        responseData.withUnsafeBytes { ptr in
            _ = write(fd, ptr.baseAddress!, responseData.count)
        }

        // Clean up the client connection after handling
        cleanupClient(fd: fd)
    }

    /// Removes and cancels the dispatch source for a client file descriptor.
    ///
    /// - Parameter fd: The file descriptor of the client to clean up.
    private func cleanupClient(fd: Int32) {
        // Find and cancel the client source for this file descriptor
        if let index = clientSources.firstIndex(where: { source in
            // DispatchSource doesn't expose its FD, so we close via cancel
            return true
        }) {
            let source = clientSources.remove(at: index)
            source.cancel()
        }
    }
}

// MARK: - IPC Errors

/// Errors that can occur during IPC server operations.
public enum IPCError: Error, LocalizedError {
    /// The Unix domain socket could not be created.
    case socketCreationFailed(errno: Int32)
    /// The socket path exceeds the maximum length for sockaddr_un.
    case pathTooLong
    /// The socket could not be bound to the address.
    case bindFailed(errno: Int32)
    /// The socket could not begin listening.
    case listenFailed(errno: Int32)
    /// Failed to connect to the server socket.
    case connectionFailed(errno: Int32)
    /// Failed to send data over the socket.
    case sendFailed
    /// Failed to receive data from the socket.
    case receiveFailed
    /// The received data could not be decoded.
    case decodingFailed

    /// Human-readable error description for logging and display.
    public var errorDescription: String? {
        switch self {
        case .socketCreationFailed(let code):
            return "Failed to create socket (errno: \(code))"
        case .pathTooLong:
            return "Socket path exceeds maximum length"
        case .bindFailed(let code):
            return "Failed to bind socket (errno: \(code))"
        case .listenFailed(let code):
            return "Failed to listen on socket (errno: \(code))"
        case .connectionFailed(let code):
            return "Failed to connect to server (errno: \(code))"
        case .sendFailed:
            return "Failed to send data"
        case .receiveFailed:
            return "Failed to receive data"
        case .decodingFailed:
            return "Failed to decode response"
        }
    }
}
