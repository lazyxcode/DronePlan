// Copyright (c) 2026 acche. All rights reserved.
//
//  USBFlightPlanUploader.swift
//  DronePlan
//
//  Created by Codex on 16/10/2025.
//

import Foundation

enum USBUploadError: LocalizedError {
    case adbNotFound(paths: [String])
    case adbExecutionBlocked(path: String, reason: String)
    case deviceNotDetected
    case deviceOffline
    case deviceUnauthorized
    case pushFailed(String)
    case commandTimeout(command: String)
    case unableToCreateDirectory

    var errorDescription: String? {
        switch self {
        case let .adbNotFound(paths):
            let searched = paths.isEmpty ? "" : "（已检查: \(paths.joined(separator: ", "))）"
            return "未找到 adb，请先安装 Android platform-tools（如 brew install android-platform-tools），并确保在 PATH 中可用。\(searched)"
        case let .adbExecutionBlocked(path, reason):
            return "已找到 adb 但无法执行：\(path)。原因：\(reason)。如果是本机调试版，请在 Xcode 的 Signing & Capabilities 中关闭 App Sandbox 后重试。"
        case .deviceNotDetected:
            return "未检测到已授权的 DJI RC 2。请在遥控器上开启开发者选项与 USB 调试，使用数据线连接 Mac 后在遥控器上点击“允许 USB 调试”。"
        case .deviceOffline:
            return "DJI RC 2 处于 offline 状态。请重新插拔数据线、在遥控器上选择文件传输/MTP，并确保屏幕常亮后重试。必要时在 RC 2 的开发者选项里“撤销 USB 调试授权”后重新允许。"
        case .deviceUnauthorized:
            return "DJI RC 2 未授权 USB 调试。请在遥控器弹窗中点“允许”，并勾选“始终允许”，然后重试。"
        case .pushFailed(let message):
            return "通过 USB 传输 KMZ 失败：\(message)"
        case .commandTimeout(let command):
            return "执行命令超时：\(command)。请检查 RC 2 连接状态后重试。"
        case .unableToCreateDirectory:
            return "无法在本地创建 USB 挂载目录。"
        }
    }
}

struct USBDiagnosticReport {
    let createdAt: Date
    let summary: String
    let details: [String]

    var text: String {
        let dateText = ISO8601DateFormatter().string(from: createdAt)
        return ([summary, "时间: \(dateText)"] + details).joined(separator: "\n")
    }
}

struct USBFlightPlanUploader {
    private let fileManager = FileManager.default
    private let exporter = KMZExporter()
    /// DJI Fly（DJI RC 2 内置）读取航线的默认目录
    private let remoteWaylineDirectory = "/sdcard/Android/data/dji.go.v5/files/wayline_mission"

    func upload(plan: FlightPlan, waypoints: [Waypoint]) async throws -> URL {
        let kmzURL = try await exporter.makeKMZ(for: plan, waypoints: waypoints)

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let url = try pushToRC2(kmzURL: kmzURL)
                    continuation.resume(returning: url)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - ADB Path & Device

    private func pushToRC2(kmzURL: URL) throws -> URL {
        let adbPath = try resolveADBPath()
        try ensureDeviceConnected(adbPath: adbPath, attempts: 3)

        // 确保遥控器上存在目标目录
        _ = try run(adbPath, arguments: ["shell", "mkdir", "-p", remoteWaylineDirectory])

        let remotePath = "\(remoteWaylineDirectory)/\(kmzURL.lastPathComponent)"
        _ = try run(adbPath, arguments: ["push", kmzURL.path, remotePath])

        // 仅用于向用户展示写入到哪
        return URL(fileURLWithPath: remotePath)
    }

    private func resolveADBPath() throws -> String {
        var attemptedPaths: [String] = []
        let home = fileManager.homeDirectoryForCurrentUser.path

        // 1) common Homebrew + Android SDK installs (GUI app可能没有继承Shell的PATH)
        var commonPaths = [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "/usr/bin/adb",
            "\(home)/Library/Android/sdk/platform-tools/adb",
            "/opt/homebrew/Caskroom/android-platform-tools/latest/platform-tools/adb"
        ]

        // 额外扫描 Homebrew Cask 目录中的版本号路径
        if let caskEntries = try? fileManager.contentsOfDirectory(atPath: "/opt/homebrew/Caskroom/android-platform-tools") {
            let versioned = caskEntries
                .map { "/opt/homebrew/Caskroom/android-platform-tools/\($0)/platform-tools/adb" }
            commonPaths.append(contentsOf: versioned)
        }

        if let path = commonPaths.first(where: { fileManager.fileExists(atPath: $0) }) {
            return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        }

        // 2) honor PATH in current process
        if let envPath = try? run("/usr/bin/env", arguments: ["which", "adb"])
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !envPath.isEmpty,
           fileManager.fileExists(atPath: envPath) {
            return URL(fileURLWithPath: envPath).resolvingSymlinksInPath().path
        }

        // 3) fallback: login shell lookup
        if let shellPath = try? run("/bin/zsh", arguments: ["-lc", "command -v adb"])
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !shellPath.isEmpty,
           fileManager.fileExists(atPath: shellPath) {
            return URL(fileURLWithPath: shellPath).resolvingSymlinksInPath().path
        }

        attemptedPaths.append(contentsOf: commonPaths)
        throw USBUploadError.adbNotFound(paths: attemptedPaths)
    }

    func diagnose() async -> USBDiagnosticReport {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var details: [String] = []
                details.append("USB 诊断开始")

                // 使用定点查询避免 ioreg 全量输出导致阻塞/超时
                let usbResult = runAllowFailure("/usr/sbin/ioreg", arguments: ["-p", "IOUSB", "-l", "-w0", "-n", "KATMAI-IDP"])
                if usbResult.status == 0 {
                    if usbResult.output.contains("KATMAI-IDP") || usbResult.output.contains("\"USB Vendor Name\" = \"DJI\"") {
                        details.append("USB 枚举: 已检测到 DJI 设备")
                    } else {
                        details.append("USB 枚举: 未检测到 DJI 设备")
                    }
                } else {
                    details.append("USB 枚举命令失败: \(trimmed(usbResult.output))")
                }

                guard let adbPath = try? resolveADBPath() else {
                    details.append("ADB: 未找到 adb 可执行文件")
                    continuation.resume(returning: USBDiagnosticReport(
                        createdAt: Date(),
                        summary: "诊断结果: 缺少 adb",
                        details: details
                    ))
                    return
                }

                details.append("ADB 路径: \(adbPath)")
                let adbVersion = runAllowFailure(adbPath, arguments: ["version"])
                details.append("ADB version: \(trimmed(adbVersion.output))")

                _ = runAllowFailure(adbPath, arguments: ["start-server"])
                let before = runAllowFailure(adbPath, arguments: ["devices", "-l"])
                details.append("ADB devices(初始): \(singleLine(before.output))")

                if before.output.contains("\toffline") {
                    _ = runAllowFailure(adbPath, arguments: ["reconnect", "offline"])
                    Thread.sleep(forTimeInterval: 1.0)
                }

                let after = runAllowFailure(adbPath, arguments: ["devices", "-l"])
                details.append("ADB devices(重连后): \(singleLine(after.output))")

                let summary = buildSummary(fromADBOutput: after.output)
                continuation.resume(returning: USBDiagnosticReport(
                    createdAt: Date(),
                    summary: summary,
                    details: details
                ))
            }
        }
    }

    private func ensureDeviceConnected(adbPath: String, attempts: Int) throws {
        _ = runAllowFailure(adbPath, arguments: ["start-server"])

        for attempt in 1...max(attempts, 1) {
            let output = runAllowFailure(adbPath, arguments: ["devices", "-l"]).output
            let status = parseDeviceStatus(from: output)

            switch status {
            case .device:
                return
            case .unauthorized:
                throw USBUploadError.deviceUnauthorized
            case .offline:
                _ = runAllowFailure(adbPath, arguments: ["reconnect", "offline"])
                _ = runAllowFailure(adbPath, arguments: ["usb"])
                if attempt < attempts {
                    Thread.sleep(forTimeInterval: 1.0)
                    continue
                }
                throw USBUploadError.deviceOffline
            case .none:
                _ = runAllowFailure(adbPath, arguments: ["usb"])
                if attempt < attempts {
                    Thread.sleep(forTimeInterval: 1.0)
                    continue
                }
                throw USBUploadError.deviceNotDetected
            }
        }

        throw USBUploadError.deviceNotDetected
    }

    // MARK: - Process Helpers

    private enum ADBDeviceStatus {
        case device
        case offline
        case unauthorized
        case none
    }

    private func parseDeviceStatus(from adbDevicesOutput: String) -> ADBDeviceStatus {
        for line in adbDevicesOutput.split(separator: "\n") {
            if line.contains("\tdevice") { return .device }
            if line.contains("\toffline") { return .offline }
            if line.contains("\tunauthorized") { return .unauthorized }
        }
        return .none
    }

    private func buildSummary(fromADBOutput output: String) -> String {
        switch parseDeviceStatus(from: output) {
        case .device:
            return "诊断结果: 可同步（ADB 已连接）"
        case .offline:
            return "诊断结果: ADB offline（通常为 USB 调试授权/固件限制）"
        case .unauthorized:
            return "诊断结果: ADB unauthorized（需在设备上授权 USB 调试）"
        case .none:
            return "诊断结果: 未检测到可用 ADB 会话"
        }
    }

    private func singleLine(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r", with: "")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " | ")
        return normalized.isEmpty ? "(empty)" : normalized
    }

    private func trimmed(_ text: String) -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "(empty)" : value
    }

    private func runAllowFailure(_ executable: String, arguments: [String]) -> (status: Int32, output: String) {
        do {
            let result = try execute(executable, arguments: arguments, timeout: 12.0)
            if result.timedOut {
                return (124, "timeout")
            } else {
                return (result.status, result.output)
            }
        } catch {
            return (127, "failed to execute \(executable): \(error.localizedDescription)")
        }
    }

    private func run(_ executable: String, arguments: [String]) throws -> String {
        let result = try execute(executable, arguments: arguments, timeout: 20.0)
        if result.timedOut {
            throw USBUploadError.commandTimeout(command: ([executable] + arguments).joined(separator: " "))
        }

        let output = result.output
        guard result.status == 0 else {
            throw USBUploadError.pushFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return output
    }

    private func execute(_ executable: String, arguments: [String], timeout: TimeInterval) throws -> (status: Int32, output: String, timedOut: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let readHandle = pipe.fileHandleForReading
        var collected = Data()
        let readQueue = DispatchQueue(label: "usb.uploader.process.read")
        let readGroup = DispatchGroup()
        readGroup.enter()
        readQueue.async {
            while true {
                let chunk = readHandle.availableData
                if chunk.isEmpty { break }
                collected.append(chunk)
            }
            readGroup.leave()
        }

        do {
            try process.run()
        } catch {
            if fileManager.fileExists(atPath: executable) {
                throw USBUploadError.adbExecutionBlocked(path: executable, reason: error.localizedDescription)
            }
            // 当可执行文件不存在时，向上抛出 adbNotFound 以提示安装
            throw USBUploadError.adbNotFound(paths: [executable])
        }

        var didTimeout = false
        let deadline = DispatchTime.now() + timeout
        while process.isRunning {
            if DispatchTime.now() >= deadline {
                didTimeout = true
                process.terminate()
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        process.waitUntilExit()
        readHandle.closeFile()
        _ = readGroup.wait(timeout: .now() + 1.0)
        let output = String(data: collected, encoding: .utf8) ?? ""
        return (process.terminationStatus, output, didTimeout)
    }
}
