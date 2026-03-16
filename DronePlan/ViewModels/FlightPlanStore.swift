// Copyright (c) 2026 acche. All rights reserved.
//
//  FlightPlanStore.swift
//  DronePlan
//
//  Created by Codex on 16/10/2025.
//

import Foundation
import Combine
import SwiftUI
import MapKit

@available(macOS 14.0, iOS 17.0, visionOS 2.0, *)
@MainActor
final class FlightPlanStore: ObservableObject {
    @Published var plans: [FlightPlan]
    @Published var selectedPlanID: FlightPlan.ID? {
        didSet {
            guard selectedPlanID != oldValue else { return }
            generatedWaypointsCache.removeAll()
            focusOnSelectedPlan()
        }
    }
    @Published var cameraPosition: MapCameraPosition = .automatic
    @Published var isFloatingPanelVisible: Bool = true
    @Published var isUploading: Bool = false
    @Published var lastExportURL: URL?
    @Published var exportErrorMessage: String?
    @Published var uploadMessage: String?
    @Published var usbDiagnosticMessage: String?
    @Published var isDiagnosingUSB: Bool = false
    @Published var surveyAreaPoints: [CLLocationCoordinate2D] = []

    @Published var showFileExporter = false
    @Published var kmzDocument: KMZDocument?

    private let kmzExporter = KMZExporter()
    private let uploader = USBFlightPlanUploader()
    private let persistenceService = PersistenceService()

    // Cache for generated waypoints to avoid recalculation
    private var generatedWaypointsCache: [UUID: [Waypoint]] = [:]

    init() {
        let samplePlan = FlightPlan(
            name: "演示飞行计划",
            waypoints: [
                Waypoint(latitude: 37.333, longitude: -122.009, altitude: 80),
                Waypoint(latitude: 37.3345, longitude: -122.0105, altitude: 80),
                Waypoint(latitude: 37.3338, longitude: -122.012, altitude: 80)
            ],
            cruiseSpeed: 10,
            maxAltitude: 120,
            cameraAngle: -80,
            photoInterval: 2.5
        )
        plans = [samplePlan]
        selectedPlanID = samplePlan.id

        cameraPosition = MapCameraPosition.region(MKCoordinateRegion(center: samplePlan.centerCoordinate ?? CLLocationCoordinate2D(latitude: 37.333, longitude: -122.009),
                                                                     span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
        
        Task { await loadPlans() }
    }

    var selectedPlan: FlightPlan? {
        guard let id = selectedPlanID else { return nil }
        return plans.first { $0.id == id }
    }

    // Get all waypoints for the selected plan (cached)
    var allWaypoints: [Waypoint] {
        guard let plan = selectedPlan else { return [] }
        switch plan.mode {
        case .manual:
            return plan.waypoints
        case .survey:
            var all: [Waypoint] = []
            for area in plan.surveyAreas {
                all.append(contentsOf: getWaypoints(for: area))
            }
            return all
        }
    }

    func selectPlan(_ plan: FlightPlan?) {
        selectedPlanID = plan?.id
    }

    func addPlan(named name: String) {
        let plan = FlightPlan(name: name)
        plans.append(plan)
        selectPlan(plan)
        savePlans()
    }

    func addPlan() {
        let defaultName = "飞行计划 \(plans.count + 1)"
        addPlan(named: defaultName)
    }

    func deletePlan(_ plan: FlightPlan) {
        plans.removeAll { $0.id == plan.id }
        if selectedPlanID == plan.id {
            selectedPlanID = plans.first?.id
        }
        savePlans()
    }

    func renameSelectedPlan(to name: String) {
        updateSelectedPlan { plan in
            plan.name = name
        }
    }

    func switchMode(to mode: PlanMode) {
        updateSelectedPlan { plan in
            plan.mode = mode
        }
        // Clear survey area points when switching modes
        surveyAreaPoints.removeAll()
        generatedWaypointsCache.removeAll()
    }

    func addWaypoint(at coordinate: CLLocationCoordinate2D) {
        guard let plan = selectedPlan else { return }

        switch plan.mode {
        case .manual:
            updateSelectedPlan { plan in
                let waypoint = Waypoint(latitude: coordinate.latitude,
                                        longitude: coordinate.longitude,
                                        altitude: plan.maxAltitude)
                plan.waypoints.append(waypoint)
            }
        case .survey:
            // Directly add corner point in survey mode
            surveyAreaPoints.append(coordinate)
        }
    }

    func clearSurveyArea() {
        surveyAreaPoints.removeAll()
        generatedWaypointsCache.removeAll()
    }

    // Check if a coordinate is near any existing corner point (within tap radius)
    func cornerPointIndex(near coordinate: CLLocationCoordinate2D, radius: Double = 0.0001) -> Int? {
        for (index, point) in surveyAreaPoints.enumerated() {
            let latDiff = abs(point.latitude - coordinate.latitude)
            let lonDiff = abs(point.longitude - coordinate.longitude)
            let distance = sqrt(latDiff * latDiff + lonDiff * lonDiff)
            if distance < radius {
                return index
            }
        }
        return nil
    }

    // Remove a corner point at the specified index
    func removeCornerPoint(at index: Int) {
        guard index >= 0 && index < surveyAreaPoints.count else { return }
        surveyAreaPoints.remove(at: index)
    }

    func removeSurveyArea(_ area: SurveyArea) {
        updateSelectedPlan { plan in
            plan.surveyAreas.removeAll { $0.id == area.id }
        }
    }

    func updateSurveyArea(_ area: SurveyArea, altitude: Double? = nil, angle: Double? = nil, sideOverlap: Double? = nil, frontOverlap: Double? = nil) {
        // Clear cache for this area
        generatedWaypointsCache.removeValue(forKey: area.id)

        updateSelectedPlan { plan in
            guard let index = plan.surveyAreas.firstIndex(where: { $0.id == area.id }) else { return }
            if let altitude { plan.surveyAreas[index].altitude = altitude }
            if let angle { plan.surveyAreas[index].angle = angle }
            if let sideOverlap { plan.surveyAreas[index].sideOverlap = sideOverlap }
            if let frontOverlap { plan.surveyAreas[index].frontOverlap = frontOverlap }
        }
    }

    // Get cached or generate waypoints for a survey area
    func getWaypoints(for area: SurveyArea) -> [Waypoint] {
        if let cached = generatedWaypointsCache[area.id] {
            return cached
        }

        guard let plan = selectedPlan else { return [] }
        let waypoints = area.generateWaypoints(speed: plan.cruiseSpeed, holdTime: plan.photoInterval)
        generatedWaypointsCache[area.id] = waypoints
        return waypoints
    }

    // Get waypoints for current editing survey area (from surveyAreaPoints)
    var currentSurveyAreaWaypoints: [Waypoint] {
        guard let plan = selectedPlan, surveyAreaPoints.count >= 3 else { return [] }

        let tempArea = SurveyArea(
            name: "临时区域",
            cornerPoints: surveyAreaPoints,
            altitude: plan.maxAltitude
        )

        return tempArea.generateWaypoints(speed: plan.cruiseSpeed, holdTime: plan.photoInterval)
    }

    func updateWaypoint(_ waypoint: Waypoint, with newValue: Waypoint) {
        updateSelectedPlan { plan in
            if let index = plan.waypoints.firstIndex(where: { $0.id == waypoint.id }) {
                plan.waypoints[index] = newValue
            }
        }
    }

    func removeWaypoint(_ waypoint: Waypoint) {
        updateSelectedPlan { plan in
            plan.waypoints.removeAll { $0.id == waypoint.id }
        }
    }

    func updateWaypointAltitude(_ waypoint: Waypoint, altitude: Double) {
        updateSelectedPlan { plan in
            guard let index = plan.waypoints.firstIndex(where: { $0.id == waypoint.id }) else { return }
            plan.waypoints[index].altitude = altitude
        }
    }

    func updateWaypointHoldTime(_ waypoint: Waypoint, holdTime: TimeInterval) {
        updateSelectedPlan { plan in
            guard let index = plan.waypoints.firstIndex(where: { $0.id == waypoint.id }) else { return }
            plan.waypoints[index].holdTime = holdTime
        }
    }

    func updateWaypointSpeed(_ waypoint: Waypoint, speed: Double) {
        updateSelectedPlan { plan in
            guard let index = plan.waypoints.firstIndex(where: { $0.id == waypoint.id }) else { return }
            plan.waypoints[index].speed = speed
        }
    }

    func updateParameters(cruiseSpeed: Double? = nil,
                          maxAltitude: Double? = nil,
                          cameraAngle: Double? = nil,
                          photoInterval: TimeInterval? = nil) {
        updateSelectedPlan { plan in
            if let cruiseSpeed { plan.cruiseSpeed = cruiseSpeed }
            if let maxAltitude { plan.maxAltitude = maxAltitude }
            if let cameraAngle { plan.cameraAngle = cameraAngle }
            if let photoInterval { plan.photoInterval = photoInterval }
        }
    }

    func toggleFloatingPanel(visible: Bool? = nil) {
        if let visible {
            isFloatingPanelVisible = visible
        } else {
            isFloatingPanelVisible.toggle()
        }
    }

    func exportSelectedPlan() async {
        guard let plan = selectedPlan else { return }
        let waypoints = allWaypoints
        do {
            exportErrorMessage = nil
            let url = try await kmzExporter.makeKMZ(for: plan, waypoints: waypoints)
            lastExportURL = url
            kmzDocument = KMZDocument(url: url)
            showFileExporter = true
            exportErrorMessage = nil
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    func uploadSelectedPlan() async {
        guard let plan = selectedPlan else { return }
        let waypoints = allWaypoints
        uploadMessage = nil
        isUploading = true
        defer { isUploading = false }
        do {
            let targetURL = try await uploader.upload(plan: plan, waypoints: waypoints)
            uploadMessage = "已上传到: \(targetURL.lastPathComponent)"
        } catch {
            uploadMessage = "上传失败: \(error.localizedDescription)"
        }
    }

    func runUSBDiagnostics() async {
        usbDiagnosticMessage = nil
        isDiagnosingUSB = true
        defer { isDiagnosingUSB = false }

        let report = await uploader.diagnose()
        usbDiagnosticMessage = report.text
    }

    private func updateSelectedPlan(_ mutate: (inout FlightPlan) -> Void) {
        guard let id = selectedPlanID,
              let index = plans.firstIndex(where: { $0.id == id }) else { return }
        var plan = plans[index]
        mutate(&plan)
        plans[index] = plan
        savePlans()
    }

    private func savePlans() {
        Task {
            do {
                try await persistenceService.save(plans: plans)
            } catch {
                print("Failed to save plans: \(error)")
            }
        }
    }

    private func loadPlans() async {
        do {
            let loadedPlans = try await persistenceService.load()
            if !loadedPlans.isEmpty {
                self.plans = loadedPlans
                if selectedPlanID == nil {
                    selectedPlanID = self.plans.first?.id
                    focusOnSelectedPlan()
                }
            }
        } catch {
            print("Failed to load plans: \(error)")
        }
    }

    private func focusOnSelectedPlan() {
        guard let plan = selectedPlan,
              let center = plan.centerCoordinate else { return }
        cameraPosition = MapCameraPosition.region(MKCoordinateRegion(center: center,
                                                                     span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
    }
}
