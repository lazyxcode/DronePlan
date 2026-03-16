// Copyright (c) 2026 acche. All rights reserved.
//
//  DronePlanApp.swift
//  DronePlan
//
//  Created by DronePlan contributors on 15/10/2025.
//

import SwiftUI

@available(macOS 14.0, iOS 17.0, visionOS 2.0, *)
@main
struct DronePlanApp: App {
    @StateObject private var store = FlightPlanStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
