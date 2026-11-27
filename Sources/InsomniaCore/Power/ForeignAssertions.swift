// ForeignAssertions.swift — InsomniaCore
//
// Reads the power assertions that other processes hold (the things that keep
// the Mac awake when Insomnia is decaffeinated) and works out which app is
// really behind each one. macOS offers no API to cancel another process's
// assertion, so this is read-only: it feeds the menu and the SleepEnforcer.

import Foundation
import IOKit.pwr_mgt
import Darwin
import os

// MARK: - Model

/// A power assertion held by a process other than Insomnia.
public struct ForeignAssertion: Equatable, Sendable {
    /// Pid of the process that holds the assertion.
    public let pid: Int32
    /// Executable name of the holder (e.g. `caffeinate`).
    public let processName: String
    /// The app that is really responsible (e.g. `claude` for a `caffeinate` it spawned).
    public let owningAppName: String
    /// The IOKit assertion type string (e.g. `PreventUserIdleSystemSleep`).
    public let type: String
    /// The reason string the holder supplied, if any.
    public let name: String

    /// Creates a foreign assertion record.
    public init(pid: Int32, processName: String, owningAppName: String, type: String, name: String) {
        self.pid = pid
        self.processName = processName
        self.owningAppName = owningAppName
        self.type = type
        self.name = name
    }

    /// Assertion types that can keep the Mac from idle-sleeping.
    static let idleBlockingTypes: Set<String> = [
        "PreventUserIdleSystemSleep",
        "PreventUserIdleDisplaySleep",
        "NoIdleSleepAssertion",
        "PreventSystemSleep",
    ]

    /// Whether this assertion's type can keep the Mac from idle-sleeping.
    /// Other types (e.g. backupd's BackgroundTask) don't block sleep but still signal real work.
    public var blocksIdleSleep: Bool {
        Self.idleBlockingTypes.contains(type)
    }

    /// Process names whose assertions are macOS's own sleep policy, not an app choosing to stay awake.
    /// `powerd` always holds "Prevent sleep while display is on", so listing it would be permanent noise.
    static let systemPolicyProcessNames: Set<String> = ["powerd"]

    /// Whether this assertion is macOS's own policy and should be hidden from the user.
    public var isSystemPolicy: Bool {
        Self.systemPolicyProcessNames.contains(processName)
    }

    /// Short human description of what the assertion prevents.
    public var typeDescription: String {
        switch type {
        case "PreventUserIdleDisplaySleep": return "prevent display sleep"
        case "PreventSystemSleep": return "prevent system sleep"
        case "NoIdleSleepAssertion": return "prevent idle sleep"
        default: return "prevent idle sleep"
        }
    }
}

// MARK: - Reader Protocol

/// Abstracts reading other processes' assertions so tests never touch IOKit.
public protocol ForeignAssertionReading: Sendable {
    /// Returns every assertion (any type) held by processes other than ours, minus macOS's own policy holders.
    /// Callers filter on `blocksIdleSleep`; the unfiltered list lets the enforcer see work like backups.
    func readAssertions() throws -> [ForeignAssertion]
}

/// Errors from reading the system assertion table.
public enum ForeignAssertionError: Error, LocalizedError {
    /// `IOPMCopyAssertionsByProcess` returned a failure code.
    case copyFailed(ioReturn: Int32)
    /// The returned dictionary didn't have the documented pid -> assertions shape.
    case unexpectedShape

    /// Description including the IOReturn for logs.
    public var errorDescription: String? {
        switch self {
        case .copyFailed(let code): return "IOPMCopyAssertionsByProcess failed (IOReturn: \(code))"
        case .unexpectedShape: return "IOPMCopyAssertionsByProcess returned an unexpected structure"
        }
    }
}

// MARK: - Owning App Resolution

/// Resolves which app is really behind a helper process such as `caffeinate`.
public enum OwningAppResolver {
    /// Names that are only plumbing: the walk keeps climbing past them.
    static let plumbingNames: Set<String> = [
        "caffeinate", "launchd", "sh", "bash", "zsh", "fish", "dash", "ksh", "tcsh", "login", "sudo", "env",
    ]

    /// Walks parent pids from `pid` until it finds a process that isn't plumbing.
    ///
    /// - Parameters:
    ///   - pid: The starting process.
    ///   - parentOf: Returns the parent pid, or nil if unknown.
    ///   - nameOf: Returns a process name, or nil if unknown.
    /// - Returns: The first non-plumbing name, or the starting process's own name when none is found.
    public static func resolve(
        pid: Int32,
        parentOf: (Int32) -> Int32?,
        nameOf: (Int32) -> String?
    ) -> String {
        let ownName = nameOf(pid) ?? "pid \(pid)"
        var current = pid
        // The depth cap guards against a malformed (cyclic) parent chain.
        for _ in 0..<16 {
            guard let name = nameOf(current) else { break }
            if !plumbingNames.contains(name) { return name }
            guard let parent = parentOf(current), parent > 1, parent != current else { break }
            current = parent
        }
        return ownName
    }
}

// MARK: - Process Identity

/// A process identified by pid and start time, so a recycled pid is never mistaken for the original.
public struct ProcessIdentity: Equatable, Hashable, Sendable {
    /// The process id.
    public let pid: Int32
    /// Start time, seconds part.
    public let startSeconds: UInt64
    /// Start time, microseconds part.
    public let startMicroseconds: UInt64

    /// Creates an identity.
    public init(pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64) {
        self.pid = pid
        self.startSeconds = startSeconds
        self.startMicroseconds = startMicroseconds
    }
}

// MARK: - Process Table

/// Thin wrappers over libproc/sysctl for process names, parents and owners.
public enum ProcessTable {
    /// The executable name for a pid, or nil when the process is gone or unreadable.
    public static func name(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    /// A display name for a pid: `proc_name`, except when that is just a version number
    /// (Claude Code's versioned binary shows as `2.1.332`), where argv[0]'s basename is used instead.
    public static func displayName(of pid: Int32) -> String? {
        guard let name = name(of: pid) else { return nil }
        let isVersion = !name.isEmpty && name.allSatisfy { $0.isNumber || $0 == "." }
        guard isVersion, let argv0 = argv0(of: pid) else { return name }
        let base = (argv0 as NSString).lastPathComponent
        return base.isEmpty ? name : base
    }

    /// argv[0] of a process via `sysctl KERN_PROCARGS2`, or nil when unreadable.
    static func argv0(of pid: Int32) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &size, nil, 0) == 0 else { return nil }
        // Layout: argc (Int32), exec path, NUL padding, then argv[0], argv[1], ... each NUL-terminated.
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }
        guard index < size else { return nil }
        let end = buffer[index..<size].firstIndex(of: 0) ?? size
        return String(decoding: buffer[index..<end], as: UTF8.self)
    }

    /// The parent pid via `sysctl KERN_PROC_PID`, or nil when it can't be read.
    public static func parentPid(of pid: Int32) -> Int32? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard result == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    /// The BSD info (real uid, start time) for a pid, or nil when unreadable.
    static func bsdInfo(of pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let written = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        return written == size ? info : nil
    }

    /// The real user id that owns a pid, or nil when unreadable.
    public static func realUid(of pid: Int32) -> uid_t? {
        bsdInfo(of: pid)?.pbi_ruid
    }

    /// When the process started, or nil when unreadable. Used to tell a pid's original owner from a reuse.
    public static func startDate(of pid: Int32) -> Date? {
        guard let info = bsdInfo(of: pid) else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1_000_000)
    }

    /// Full executable path via `proc_pidpath`, or nil when unreadable.
    public static func path(of pid: Int32) -> String? {
        // PROC_PIDPATHINFO_MAXSIZE is 4 * MAXPATHLEN; spelled out because the macro isn't imported.
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    /// The pid plus its start time, which together identify one process even if the pid is reused.
    public static func identity(of pid: Int32) -> ProcessIdentity? {
        guard let info = bsdInfo(of: pid) else { return nil }
        return ProcessIdentity(pid: pid, startSeconds: info.pbi_start_tvsec, startMicroseconds: info.pbi_start_tvusec)
    }

    /// Every pid visible to the current user.
    public static func allPids() -> [Int32] {
        let needed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard needed > 0 else { return [] }
        // Headroom because processes can spawn between the size query and the fill.
        var pids = [Int32](repeating: 0, count: Int(needed) / MemoryLayout<Int32>.size + 32)
        let filled = proc_listpids(
            UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<Int32>.size)
        )
        guard filled > 0 else { return [] }
        return pids.prefix(Int(filled) / MemoryLayout<Int32>.size).filter { $0 > 0 }
    }
}

// MARK: - IOKit Reader

/// Reads assertions from `IOPMCopyAssertionsByProcess`.
public final class IOKitForeignAssertionReader: ForeignAssertionReading, @unchecked Sendable {
    /// Pid excluded from results (ours, so we never list our own assertion).
    private let ownPid: Int32

    /// Creates a reader that omits `ownPid`'s assertions.
    public init(ownPid: Int32 = getpid()) {
        self.ownPid = ownPid
    }

    /// Returns the assertions held by every other process, minus macOS policy holders.
    public func readAssertions() throws -> [ForeignAssertion] {
        var unmanaged: Unmanaged<CFDictionary>?
        let result = IOPMCopyAssertionsByProcess(&unmanaged)
        guard result == kIOReturnSuccess, let byProcess = unmanaged?.takeRetainedValue() else {
            throw ForeignAssertionError.copyFailed(ioReturn: result)
        }
        // The dictionary maps NSNumber pid -> array of assertion dictionaries.
        guard let table = byProcess as? [NSNumber: [[String: Any]]] else {
            throw ForeignAssertionError.unexpectedShape
        }
        return Self.parse(
            table, ownPid: ownPid, nameOf: ProcessTable.name(of:),
            parentOf: ProcessTable.parentPid(of:), displayNameOf: ProcessTable.displayName(of:),
            startDateOf: ProcessTable.startDate(of:)
        )
    }

    /// Key in each assertion dictionary naming the holding process.
    static let processNameKey = "Process Name"
    /// Key holding the CFDate the assertion was created.
    static let assertStartKey = "AssertStartWhen"
    /// Key naming the pid an assertion was taken on behalf of (e.g. by runningboardd for an app).
    static let onBehalfOfPidKey = "AssertionOnBehalfOfPID"

    /// Pure parse of the IOKit table; process lookups are injected so tests can feed fixtures.
    static func parse(
        _ table: [NSNumber: [[String: Any]]],
        ownPid: Int32,
        nameOf: (Int32) -> String?,
        parentOf: (Int32) -> Int32?,
        displayNameOf: (Int32) -> String?,
        startDateOf: (Int32) -> Date? = { _ in nil }
    ) -> [ForeignAssertion] {
        var found: [ForeignAssertion] = []
        for (pidNumber, assertions) in table {
            let pid = pidNumber.int32Value
            if pid == ownPid { continue }
            // The assertion table carries the holder's name itself. A notarized app can't proc_name
            // root daemons (powerd, runningboardd), so that lookup is only the fallback.
            let processName = assertions.compactMap { $0[processNameKey] as? String }.first
                ?? nameOf(pid) ?? "pid \(pid)"
            // System policy holders (powerd) never reach the menu or the enforcer.
            if ForeignAssertion.systemPolicyProcessNames.contains(processName) { continue }
            let holderOwner = OwningAppResolver.resolve(pid: pid, parentOf: parentOf, nameOf: displayNameOf)
            for assertion in assertions {
                guard let type = assertion[kIOPMAssertionTypeKey as String] as? String else { continue }
                let name = assertion[kIOPMAssertionNameKey as String] as? String ?? ""
                // runningboardd and friends hold assertions on behalf of an app; that app is who the user cares about.
                var owner = holderOwner
                // The beneficiary pid may have been reused since the assertion was created. Only trust it when
                // that process demonstrably started no later than the assertion; a missing timestamp means unknown.
                if let behalf = (assertion[onBehalfOfPidKey] as? NSNumber)?.int32Value, behalf > 0,
                   displayNameOf(behalf) != nil,
                   let assertionStart = assertion[assertStartKey] as? Date,
                   let processStart = startDateOf(behalf), processStart <= assertionStart {
                    owner = OwningAppResolver.resolve(pid: behalf, parentOf: parentOf, nameOf: displayNameOf)
                } else if holderOwner.hasPrefix("pid ") {
                    // Neither lookup could name the holder; the table's own name beats "pid N".
                    owner = processName
                }
                found.append(ForeignAssertion(
                    pid: pid, processName: processName, owningAppName: owner, type: type, name: name
                ))
            }
        }
        return found.sorted { ($0.owningAppName, $0.pid, $0.type) < ($1.owningAppName, $1.pid, $1.type) }
    }
}

// MARK: - Menu Summary

/// Turns holders into the short rows the menu shows.
public enum ForeignHolderSummary {
    /// Idle-blocking holders grouped by owning app, in first-seen order.
    /// The menu lists only what can block idle sleep; other types (backup tasks etc.) are not "keeping it awake".
    private static func groups(for holders: [ForeignAssertion]) -> [(app: String, items: [ForeignAssertion])] {
        var order: [String] = []
        var grouped: [String: [ForeignAssertion]] = [:]
        for holder in holders where holder.blocksIdleSleep {
            if grouped[holder.owningAppName] == nil { order.append(holder.owningAppName) }
            grouped[holder.owningAppName, default: []].append(holder)
        }
        return order.map { ($0, grouped[$0] ?? []) }
    }

    /// The number of distinct apps keeping the Mac awake (what the menu title counts).
    public static func groupCount(for holders: [ForeignAssertion]) -> Int {
        groups(for: holders).count
    }

    /// Groups holders by owning app and caps the list.
    ///
    /// - Parameters:
    ///   - holders: Assertions to summarise.
    ///   - limit: Maximum rows before collapsing the rest into "+N more".
    /// - Returns: One row per app (e.g. `ClaudeBar — runningboardd (prevent idle sleep)`; just
    ///   `sharingd (prevent idle sleep)` when the process is the app itself) plus an optional overflow row.
    public static func rows(for holders: [ForeignAssertion], limit: Int = 5) -> [String] {
        let lines: [String] = groups(for: holders).map { group in
            let processes = Set(group.items.map(\.processName)).sorted().joined(separator: ", ")
            let kinds = Set(group.items.map(\.typeDescription)).sorted().joined(separator: ", ")
            // Repeating the name ("sharingd — sharingd") says nothing, so collapse it.
            return processes == group.app ? "\(group.app) (\(kinds))" : "\(group.app) \u{2014} \(processes) (\(kinds))"
        }
        guard lines.count > limit else { return lines }
        return Array(lines.prefix(limit)) + ["+\(lines.count - limit) more"]
    }
}
