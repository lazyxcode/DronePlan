// Copyright (c) 2026 acche. All rights reserved.
//
//  KMZDocument.swift
//  DronePlan
//
//  Created by Codex on 2026-01-19.
//

import SwiftUI
import UniformTypeIdentifiers

struct KMZDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.kmz, .kml] }

    var url: URL?

    init(url: URL) {
        self.url = url
    }

    init(configuration: ReadConfiguration) throws {
        // Read implementation is not needed for export-only
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        if let url = url {
            return try FileWrapper(url: url, options: .immediate)
        } else {
            throw CocoaError(.fileReadNoSuchFile)
        }
    }
}

extension UTType {
    static var kml: UTType {
        UTType(filenameExtension: "kml") ?? UTType(importedAs: "com.google.earth.kml")
    }
    static var kmz: UTType {
        UTType(filenameExtension: "kmz") ?? UTType(importedAs: "com.google.earth.kmz")
    }
}
