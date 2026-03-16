// Copyright (c) 2026 acche. All rights reserved.
//
//  KMZExporter.swift
//  DronePlan
//
//  Created by Codex on 16/10/2025.
//

import Foundation
import Compression
import ZIPFoundation

enum KMZExportError: Error {
    case emptyPlan
    case failedToCreateArchive
}

struct KMZExporter {
    private let fileManager = FileManager.default

    func makeKMZ(for plan: FlightPlan, waypoints: [Waypoint]) async throws -> URL {
        guard !waypoints.isEmpty else {
            throw KMZExportError.emptyPlan
        }

        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: tempRoot)
        }
        let kmlURL = tempRoot.appendingPathComponent("doc.kml")
        try plan.kmlDocumentString(waypoints: waypoints).data(using: .utf8)?.write(to: kmlURL)

        let kmzURL = tempRoot.deletingLastPathComponent().appendingPathComponent("\(plan.name.replacingOccurrences(of: " ", with: "_")).kmz")
        if fileManager.fileExists(atPath: kmzURL.path) {
            try fileManager.removeItem(at: kmzURL)
        }

        guard let archive = Archive(url: kmzURL, accessMode: .create) else {
            throw KMZExportError.failedToCreateArchive
        }

        try archive.addEntry(with: "doc.kml", fileURL: kmlURL, compressionMethod: .deflate)

        return kmzURL
    }
}
