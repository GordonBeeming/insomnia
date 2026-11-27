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
    /// Returns every idle-sleep-relevant assertion held by processes other than ours.
    func readAssertions() throws -> [ForeignAssertion]
}

/// Errors from reading the system assertion table.
public enum ForeignAssertionError: Error, LocalizedError {
    /// `IOPMCopyAssertionsByProcess` returned a failure code.
    case copyFailed(ioReturn: Int32)

    /// Description including the IOReturn for logs.
    public var errorDescription: String? {
        switch self {
        case .copyFailed(let code): return "IOPMCopyAssertionsByProcess failed (IOReturn: \(code))"
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

    /// The real user id that owns a pid, or nil when unreadable.
    public static func ownerUid(of pid: Int32) -> uid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let written = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        guard written == size else { return nil }
        return info.pbi_uid
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
    /// Assertion types that can keep the Mac from idle-sleeping.
    static let relevantTypes: Set<String> = [
        "PreventUserIdleSystemSleep",
        "PreventUserIdleDisplaySleep",
        "NoIdleSleepAssertion",
        "PreventSystemSleep",
    ]

    /// Pid excluded from results (ours, so we never list our own assertion).
    private let ownPid: Int32

    /// Creates a reader that omits `ownPid`'s assertions.
    public init(ownPid: Int32 = getpid()) {
        self.ownPid = ownPid
    }

    /// Returns the relevant assertions held by every other process.
    public func readAssertions() throws -> [ForeignAssertion] {
        var unmanaged: Unmanaged<CFDictionary>?
        let result = IOPMCopyAssertionsByProcess(&unmanaged)
        guard result == kIOReturnSuccess, let byProcess = unmanaged?.takeRetainedValue() else {
            throw ForeignAssertionError.copyFailed(ioReturn: result)
        }
        // The dictionary maps NSNumber pid -> array of assertion dictionaries.
        guard let table = byProcess as? [NSNumber: [[String: Any]]] else { return [] }

        var found: [ForeignAssertion] = []
        for (pidNumber, assertions) in table {
            let pid = pidNumber.int32Value
            if pid == ownPid { continue }
            let processName = ProcessTable.name(of: pid) ?? "pid \(pid)"
            // System policy holders never reach the menu or the enforcer.
            if ForeignAssertion.systemPolicyProcessNames.contains(processName) { continue }
            let owner = OwningAppResolver.resolve(
                pid: pid, parentOf: ProcessTable.parentPid(of:), nameOf: ProcessTable.displayName(of:)
            )
            for assertion in assertions {
                guard let type = assertion[kIOPMAssertionTypeKey as String] as? String,
                      Self.relevantTypes.contains(type) else { continue }
                let name = assertion[kIOPMAssertionNameKey as String] as? String ?? ""
                found.append(ForeignAssertion(
                    pid: pid, processName: processName, owningAppName: owner, type: type, name: name
                ))
            }
        }
        return found.sorted { ($0.owningAppName, $0.pid) < ($1.owningAppName, $1.pid) }
    }
}

// MARK: - Menu Summary

/// Turns holders into the short rows the menu shows.
public enum ForeignHolderSummary {
    /// Groups holders by owning app and caps the list.
    ///
    /// - Parameters:
    ///   - holders: Assertions to summarise.
    ///   - limit: Maximum rows before collapsing the rest into "+N more".
    /// - Returns: One row per app (e.g. `claude — caffeinate (prevent idle sleep)`) plus an optional overflow row.
    public static func rows(for holders: [ForeignAssertion], limit: Int = 5) -> [String] {
        var order: [String] = []
        var grouped: [String: [ForeignAssertion]] = [:]
        for holder in holders {
            if grouped[holder.owningAppName] == nil { order.append(holder.owningAppName) }
            grouped[holder.owningAppName, default: []].append(holder)
        }
        let lines: [String] = order.map { app in
            let items = grouped[app] ?? []
            let processes = Set(items.map(\.processName)).sorted().joined(separator: ", ")
            let kinds = Set(items.map(\.typeDescription)).sorted().joined(separator: ", ")
            return "\(app) \u{2014} \(processes) (\(kinds))"
        }
        guard lines.count > limit else { return lines }
        return Array(lines.prefix(limit)) + ["+\(lines.count - limit) more"]
    }
}
