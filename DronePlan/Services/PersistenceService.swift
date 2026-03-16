// Copyright (c) 2026 acche. All rights reserved.
//
//  PersistenceService.swift
//  DronePlan
//
//  Created by Codex on 2026-01-19.
//

import Foundation

actor PersistenceService {
    private let fileName = "flight_plans.json"

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    func save(plans: [FlightPlan]) throws {
        let data = try JSONEncoder().encode(plans)
        try data.write(to: fileURL, options: [.atomic])
    }

    func load() throws -> [FlightPlan] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([FlightPlan].self, from: data)
    }
}
