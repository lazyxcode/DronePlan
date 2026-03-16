// Copyright (c) 2026 acche. All rights reserved.
//
//  ContentView.swift
//  DronePlan
//
//  Created by DronePlan contributors on 15/10/2025.
//

import SwiftUI
import MapKit
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

@available(macOS 14.0, iOS 17.0, visionOS 2.0, *)
struct ContentView: View {
    @EnvironmentObject private var store: FlightPlanStore

    var body: some View {
        #if os(macOS)
        MacSplitLayout()
            .environmentObject(store)
        #else
        AdaptiveMobileLayout()
            .environmentObject(store)
        #endif
    }
}

#if os(macOS)
@available(macOS 14.0, iOS 17.0, visionOS 2.0, *)
struct MacSplitLayout: View {
    @EnvironmentObject private var store: FlightPlanStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isDetailCollapsed = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            PlanSidebarView()
                .frame(minWidth: 180, idealWidth: 200, maxWidth: 220)
        } content: {
            ZStack(alignment: .center) {
                FlightMapView()

                if isDetailCollapsed {
                    collapseRestoreButton
                }
            }
            .toolbar {
                ToolbarItemGroup {
                    ExportButtons()
                }
            }
        } detail: {
            MacDetailPanelContainer(isDetailCollapsed: $isDetailCollapsed, columnVisibility: $columnVisibility)
                .environmentObject(store)
                .navigationSplitViewColumnWidth(
                    min: MacDetailPanelMetrics.minWidth,
                    ideal: MacDetailPanelMetrics.defaultWidth,
                    max: MacDetailPanelMetrics.maxWidth
                )
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var collapseRestoreButton: some View {
        VStack {
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    columnVisibility = .all
                    isDetailCollapsed = false
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.45))
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("展开参数工具栏")
            .padding(.trailing, 16)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .allowsHitTesting(true)
    }
}
#else
@available(macOS 14.0, iOS 17.0, visionOS 2.0, *)
struct AdaptiveMobileLayout: View {
    @EnvironmentObject private var store: FlightPlanStore

    var body: some View {
        GeometryReader { proxy in
            if DeviceClass.current == .iPad {
                if proxy.size.width > proxy.size.height {
                    HStack(spacing: 0) {
                        FlightMapView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        FlightParameterPanel(layout: .tabletHorizontal)
                            .frame(width: max(proxy.size.width * 0.28, 300))
                            .background(Color(.systemBackground))
                            .shadow(radius: 8)
                    }
                } else {
                    VStack(spacing: 0) {
                        FlightMapView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        FlightParameterPanel(layout: .tabletVertical)
                            .frame(height: max(proxy.size.height * 0.30, 300))
                            .background(Color(.systemBackground))
                            .shadow(radius: 4)
                    }
                }
            } else {
                ZStack(alignment: .bottomTrailing) {
                    FlightMapView(onMapInteraction: {
                        store.toggleFloatingPanel(visible: false)
                    })
                    if store.isFloatingPanelVisible {
                        FloatingParameterOverlay()
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    } else {
                        Button {
                            store.toggleFloatingPanel(visible: true)
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .padding(10)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .padding()
                        .accessibilityLabel("显示参数工具")
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ExportButtons()
            }
        }
        .ignoresSafeArea(edges: DeviceClass.current == .iPhone ? .all : [])
        .background(Color(.systemGroupedBackground))
    }
}
#endif

@available(macOS 14.0, iOS 17.0, visionOS 2.0, *)
struct FlightMapView: View {
    @EnvironmentObject private var store: FlightPlanStore
    var onMapInteraction: (() -> Void)?
    @State private var hasTriggeredInteraction = false

    var body: some View {
        MapReader { proxy in
            Map(position: $store.cameraPosition, interactionModes: .all) {
                if let plan = store.selectedPlan {
                    switch plan.mode {
                    case .manual:
                        // Display manual waypoints
                        if plan.hasEnoughWaypointsForPolygon {
                            MapPolygon(plan.mkPolygon)
                                .foregroundStyle(Color.cyan.opacity(0.2))
                                .stroke(Color.cyan, lineWidth: 2)
                        }
                        ForEach(plan.waypoints) { waypoint in
                            Annotation("WP", coordinate: waypoint.coordinate) {
                                VStack(spacing: 2) {
                                    Text("\(plan.waypointIndex(of: waypoint) + 1)")
                                        .font(.caption2)
                                        .padding(6)
                                        .background(.thinMaterial, in: Circle())
                                    Image(systemName: "smallcircle.filled.circle")
                                        .foregroundStyle(.cyan)
                                }
                            }
                        }

                    case .survey:
                        // Show real-time survey area boundary if there are at least 3 points
                        if store.surveyAreaPoints.count >= 3 {
                            MapPolygon(coordinates: store.surveyAreaPoints)
                                .foregroundStyle(Color.green.opacity(0.15))
                                .stroke(Color.green, lineWidth: 2)

                            // Show generated waypoints
                            let waypoints = store.currentSurveyAreaWaypoints
                            ForEach(waypoints) { waypoint in
                                Annotation("", coordinate: waypoint.coordinate) {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 8, height: 8)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: 1)
                                        )
                                }
                            }
                        }

                        // Show corner points with numbers (always visible)
                        ForEach(Array(store.surveyAreaPoints.enumerated()), id: \.offset) { index, point in
                            Annotation("", coordinate: point) {
                                ZStack {
                                    Circle()
                                        .fill(Color.orange)
                                        .frame(width: 20, height: 20)
                                    Text("\(index + 1)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                                .onTapGesture {
                                    // Tap to delete this corner point
                                    store.removeCornerPoint(at: index)
                                }
                            }
                        }
                    }
                }
            }
            .mapControls {
                MapCompass()
                MapPitchToggle()
                MapUserLocationButton()
            }
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        guard let coordinate = proxy.convert(value.location, from: .local) else { return }
                        guard let plan = store.selectedPlan else { return }

                        switch plan.mode {
                        case .manual:
                            store.addWaypoint(at: coordinate)
                        case .survey:
                            // Check if clicking near an existing corner point - if so, don't add new point
                            // (deletion is handled by corner point tap gesture)
                            if store.cornerPointIndex(near: coordinate, radius: 0.0002) == nil {
                                store.addWaypoint(at: coordinate)
                            }
                        }
                        onMapInteraction?()
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { _ in
                        guard !hasTriggeredInteraction else { return }
                        onMapInteraction?()
                        hasTriggeredInteraction = true
                    }
                    .onEnded { _ in
                        hasTriggeredInteraction = false
                    }
            )
        }
    }
}

enum PanelLayoutContext {
    case macSidebar
    case tabletHorizontal
    case tabletVertical
    case floating

    var horizontalPadding: CGFloat {
        switch self {
        case .macSidebar:
            return 8
        case .tabletHorizontal, .tabletVertical:
            return 16
        case .floating:
            return 20
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .macSidebar:
            return 20
        case .tabletHorizontal, .tabletVertical:
            return 16
        case .floating:
            return 24
        }
    }

    var sectionSpacing: CGFloat {
        switch self {
        case .macSidebar:
            return 18
        case .tabletHorizontal, .tabletVertical:
            return 16
        case .floating:
            return 20
        }
    }
}

@available(macOS 14.0, iOS 17.0, visionOS 2.0, *)
struct FlightParameterPanel: View {
    @EnvironmentObject private var store: FlightPlanStore
    let layout: PanelLayoutContext

    var body: some View {
        if let plan = store.selectedPlan {
            ScrollView {
                VStack(spacing: layout.sectionSpacing) {
                    planInfoSection(plan: plan)
                    Divider()
                    modeSection(plan: plan)
                    Divider()
                    globalSettingsSection(plan: plan)
                    Divider()
                    contentSection(plan: plan)
                    Divider()
                    exportSection()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.vertical, layout.verticalPadding)
        } else {
            ContentUnavailableView("没有选中的飞行计划", systemImage: "airplane")
        }
    }

    private func modeSection(plan: FlightPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section title - outside content
            Text("工作模式")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            // Content - edge-to-edge
            VStack(alignment: .leading, spacing: 8) {
                Picker("模式", selection: Binding(
                    get: { plan.mode },
                    set: { store.switchMode(to: $0) }
                )) {
                    Text("手动航点").tag(PlanMode.manual)
                    Text("测绘区域").tag(PlanMode.survey)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)

                switch plan.mode {
                case .manual:
                    Text("点击地图添加单个航点")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .survey:
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(store.surveyAreaPoints.count) 个角点")
                                .font(.caption)
                                .foregroundStyle(store.surveyAreaPoints.count >= 3 ? .green : .secondary)

                            Spacer()

                            if !store.surveyAreaPoints.isEmpty {
                                Button("清空") {
                                    store.clearSurveyArea()
                                }
                                .font(.caption2)
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                            }
                        }

                        if store.surveyAreaPoints.count >= 3 {
                            Text("✓ 区域已生成")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func planInfoSection(plan: FlightPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section title - outside content
            Text("飞行计划")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            // Content - edge-to-edge
            VStack(alignment: .leading, spacing: 6) {
                TextField("名称", text: Binding(
                    get: { plan.name },
                    set: { store.renameSelectedPlan(to: $0) }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity)

                Text(plan.createdAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func globalSettingsSection(plan: FlightPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section title - outside content
            Text("全局参数")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            // Content - edge-to-edge
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("巡航速度")
                            .font(.caption)
                        Spacer()
                        Text("\(plan.cruiseSpeed, specifier: "%.1f") m/s")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { plan.cruiseSpeed },
                        set: { store.updateParameters(cruiseSpeed: $0) }
                    ), in: 2...25, step: 0.5)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("最大高度")
                            .font(.caption)
                        Spacer()
                        Text("\(Int(plan.maxAltitude)) 米")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { plan.maxAltitude },
                        set: { store.updateParameters(maxAltitude: $0) }
                    ), in: 20...500, step: 5)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("云台俯仰角")
                            .font(.caption)
                        Spacer()
                        Text("\(Int(plan.cameraAngle))°")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { plan.cameraAngle },
                        set: { store.updateParameters(cameraAngle: $0) }
                    ), in: -90...0, step: 5)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                }

                HStack {
                    Text("拍照间隔")
                        .font(.caption)
                    Spacer()
                    Stepper(value: Binding(
                        get: { plan.photoInterval },
                        set: { store.updateParameters(photoInterval: $0) }
                    ), in: 1...10, step: 0.5) {
                        Text("\(plan.photoInterval, specifier: "%.1f") 秒")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .labelsHidden()
                    Text("\(plan.photoInterval, specifier: "%.1f") 秒")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func contentSection(plan: FlightPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch plan.mode {
            case .manual:
                manualWaypointsContent(plan: plan)
            case .survey:
                surveyAreasContent(plan: plan)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func manualWaypointsContent(plan: FlightPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section title - outside content
            Text("航点")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            // Content - edge-to-edge
            VStack(alignment: .leading, spacing: 8) {
                if plan.waypoints.isEmpty {
                    Text("还没有航点")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(plan.waypoints) { waypoint in
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("纬度 \(waypoint.latitude, specifier: "%.5f"), 经度 \(waypoint.longitude, specifier: "%.5f")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Stepper(value: Binding(
                                    get: { waypoint.altitude },
                                    set: { store.updateWaypointAltitude(waypoint, altitude: $0) }
                                ), in: 10...500, step: 5) {
                                    Text("高度 \(Int(waypoint.altitude)) 米")
                                        .font(.caption)
                                }
                                .controlSize(.small)
                                Stepper(value: Binding(
                                    get: { waypoint.speed },
                                    set: { store.updateWaypointSpeed(waypoint, speed: $0) }
                                ), in: 2...25, step: 0.5) {
                                    Text("速度 \(waypoint.speed, specifier: "%.1f") m/s")
                                        .font(.caption)
                                }
                                .controlSize(.small)
                                Stepper(value: Binding(
                                    get: { waypoint.holdTime },
                                    set: { store.updateWaypointHoldTime(waypoint, holdTime: $0) }
                                ), in: 0...30, step: 1) {
                                    Text("悬停 \(Int(waypoint.holdTime)) 秒")
                                        .font(.caption)
                                }
                                .controlSize(.small)
                                Button(role: .destructive) {
                                    store.removeWaypoint(waypoint)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                        .font(.caption)
                                }
                                .controlSize(.small)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundStyle(.cyan)
                                Text("航点 \(plan.waypointIndex(of: waypoint) + 1)")
                                    .font(.caption)
                                Spacer()
                                Text("\(Int(waypoint.altitude))m")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func surveyAreasContent(plan: FlightPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section title - outside content
            Text("测绘区域")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            // Content - edge-to-edge
            VStack(alignment: .leading, spacing: 8) {
                if store.surveyAreaPoints.isEmpty {
                    Text("还没有角点")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    let waypointCount = store.currentSurveyAreaWaypoints.count
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "rectangle.fill")
                                .foregroundStyle(.green)
                            Text("当前区域")
                                .font(.caption)
                            Spacer()
                            if waypointCount > 0 {
                                Text("\(waypointCount)点")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if store.surveyAreaPoints.count >= 3 {
                            let tempArea = SurveyArea(
                                name: "临时区域",
                                cornerPoints: store.surveyAreaPoints,
                                altitude: plan.maxAltitude
                            )

                            VStack(alignment: .leading, spacing: 4) {
                                Text("GSD: \(tempArea.gsd, specifier: "%.2f") cm/px")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                                Text("计算航线间距: \(tempArea.calculatedSpacing, specifier: "%.1f") 米")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func exportSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section title - outside content
            Text("导出")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            // Content - edge-to-edge
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Button {
                        Task { await store.exportSelectedPlan() }
                    } label: {
                        Label("导出 KMZ", systemImage: "square.and.arrow.up")
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.small)
                    .disabled(store.allWaypoints.isEmpty)

                    Button {
                        Task { await store.uploadSelectedPlan() }
                    } label: {
                        Label("USB 上传", systemImage: "externaldrive")
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.small)
                    .disabled(store.allWaypoints.isEmpty)
                }
                .frame(maxWidth: .infinity)

                Button {
                    Task { await store.runUSBDiagnostics() }
                } label: {
                    Label("USB 诊断", systemImage: "stethoscope")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.small)
                .disabled(store.isDiagnosingUSB)
                .overlay {
                    if store.isDiagnosingUSB {
                        ProgressView()
                            .scaleEffect(0.6)
                    }
                }

                if let url = store.lastExportURL {
                    Text(url.lastPathComponent)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                if let message = store.uploadMessage {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let diagnostic = store.usbDiagnosticMessage {
                    Text(diagnostic)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(nil)
                }

                if let error = store.exportErrorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@available(macOS 14.0, iOS 17.0, visionOS 2.0, *)
struct PlanSidebarView: View {
    @EnvironmentObject private var store: FlightPlanStore
    @State private var newPlanName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $store.selectedPlanID) {
                Section("飞行计划") {
                    ForEach(store.plans) { plan in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(plan.name)
                            Text(plan.createdAt, style: .date)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .tag(plan.id)
                    }
                    .onDelete { indices in
                        for index in indices {
                            let plan = store.plans[index]
                            store.deletePlan(plan)
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            VStack(alignment: .leading, spacing: 8) {
                TextField("新建计划名称", text: $newPlanName)
                Button {
                    guard !newPlanName.isEmpty else { return }
                    store.addPlan(named: newPlanName)
                    newPlanName = ""
                } label: {
                    Label("创建计划", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}

@available(macOS 14.0, iOS 17.0, visionOS 2.0, *)
struct FloatingParameterOverlay: View {
    @EnvironmentObject private var store: FlightPlanStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("参数")
                    .font(.headline)
                Spacer()
                Button {
                    store.toggleFloatingPanel(visible: false)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }

            FlightParameterPanel(layout: .floating)
                .frame(width: 320, height: 420)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 12)
        .padding()
    }
}

@available(macOS 14.0, iOS 17.0, visionOS 2.0, *)
struct ExportButtons: View {
    @EnvironmentObject private var store: FlightPlanStore
    private enum Metrics {
        static let spacing: CGFloat = 12
        static let buttonMinWidth: CGFloat = 80
        static let buttonIdealWidth: CGFloat = 100
        static let buttonMaxWidth: CGFloat = 280
        static let collapsedControlWidth: CGFloat = 32
    }
    @State private var isCollapsed = false
    @State private var isCollapsedPopoverPresented = false
    private let collapseThreshold: CGFloat = 10

    private var totalIdealWidth: CGFloat {
        Metrics.buttonIdealWidth * 2 + Metrics.spacing
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if !isCollapsed {
                toolbarButtons
            }

            collapsedArrow
        }
        .animation(.easeInOut(duration: 0.2), value: isCollapsed)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: ToolbarWidthPreferenceKey.self, value: proxy.size.width)
            }
        )
        .fileExporter(
            isPresented: $store.showFileExporter,
            document: store.kmzDocument,
            contentType: UTType.kmz,
            defaultFilename: store.kmzDocument?.url?.deletingPathExtension().lastPathComponent ?? "flight_plan"
        ) { result in
            switch result {
            case .success(let url):
                store.exportErrorMessage = nil
                store.lastExportURL = url
            case .failure(let error):
                store.exportErrorMessage = error.localizedDescription
            }
        }
        .onPreferenceChange(ToolbarWidthPreferenceKey.self) { width in
            let shouldCollapse = width <= collapseThreshold
            if shouldCollapse != isCollapsed {
                isCollapsed = shouldCollapse
            }
        }
    }

    private var collapsedArrow: some View {
        Button {
            isCollapsedPopoverPresented = true
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.35))
                .frame(width: Metrics.collapsedControlWidth, height: 32)
        }
        .buttonStyle(.plain)
        .background(Color.clear)
        .accessibilityLabel("展开工具栏")
        .opacity(isCollapsed ? 1 : 0)
        .allowsHitTesting(isCollapsed)
        .popover(isPresented: $isCollapsedPopoverPresented, arrowEdge: .top) {
            buttonStack
                .frame(width: totalIdealWidth, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
    }

    private var toolbarButtons: some View {
        buttonStack
            .frame(
                minWidth: Metrics.buttonMinWidth * 2 + Metrics.spacing,
                idealWidth: totalIdealWidth,
                maxWidth: Metrics.buttonMaxWidth * 2 + Metrics.spacing,
                alignment: .leading
            )
    }

    private var buttonStack: some View {
        HStack(spacing: Metrics.spacing) {
            exportButton
            uploadButton
        }
    }

    private var exportButton: some View {
        Button {
            Task { await store.exportSelectedPlan() }
        } label: {
            Label("KMZ", systemImage: "square.and.arrow.down")
                .frame(
                    minWidth: Metrics.buttonMinWidth,
                    idealWidth: Metrics.buttonIdealWidth,
                    maxWidth: Metrics.buttonMaxWidth
                )
        }
        .disabled(store.allWaypoints.isEmpty)
        .controlSize(.large)
    }

    private var uploadButton: some View {
        Button {
            Task { await store.uploadSelectedPlan() }
        } label: {
            Label("USB", systemImage: "externaldrive.fill")
                .frame(
                    minWidth: Metrics.buttonMinWidth,
                    idealWidth: Metrics.buttonIdealWidth,
                    maxWidth: Metrics.buttonMaxWidth
                )
        }
        .disabled(store.allWaypoints.isEmpty)
        .controlSize(.large)
        .overlay {
            if store.isUploading {
                ProgressView()
                    .scaleEffect(0.6)
            }
        }
    }
}

private enum MacDetailPanelMetrics {
    static let minWidth: CGFloat = 80
    static let defaultWidth: CGFloat = 100
    static let maxWidth: CGFloat = 280
    static let collapseThreshold: CGFloat = 72
}

@available(macOS 14.0, iOS 17.0, visionOS 2.0, *)
private struct MacDetailPanelContainer: View {
    @EnvironmentObject private var store: FlightPlanStore
    @Binding var isDetailCollapsed: Bool
    @Binding var columnVisibility: NavigationSplitViewVisibility

    var body: some View {
        GeometryReader { proxy in
            FlightParameterPanel(layout: .macSidebar)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(
                    Color.clear
                        .onAppear { handleWidth(proxy.size.width) }
                        .onChange(of: proxy.size.width) { handleWidth($0) }
                )
        }
        .frame(
            minWidth: MacDetailPanelMetrics.minWidth,
            idealWidth: MacDetailPanelMetrics.defaultWidth,
            maxWidth: MacDetailPanelMetrics.maxWidth,
            maxHeight: .infinity,
            alignment: .leading
        )
    }

    private func handleWidth(_ width: CGFloat) {
        guard width > 1 else { return }
        if width <= MacDetailPanelMetrics.collapseThreshold {
            if columnVisibility == .all {
                isDetailCollapsed = true
                columnVisibility = .doubleColumn
            }
        } else {
            if isDetailCollapsed {
                isDetailCollapsed = false
            }
        }
    }
}

private struct ToolbarWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .infinity

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private enum DeviceClass {
    case iPhone
    case iPad
    case unknown

#if os(iOS)
    static var current: DeviceClass {
        switch UIDevice.current.userInterfaceIdiom {
        case .phone: return .iPhone
        case .pad: return .iPad
        default: return .unknown
        }
    }
#else
    static var current: DeviceClass { .unknown }
#endif
}

private extension FlightPlan {
    func waypointIndex(of waypoint: Waypoint) -> Int {
        waypoints.firstIndex(of: waypoint) ?? 0
    }

    var mkPolygon: MKPolygon {
        let coordinates = waypoints.map { $0.coordinate }
        return MKPolygon(coordinates: coordinates, count: coordinates.count)
    }
}

@available(macOS 14.0, iOS 17.0, visionOS 2.0, *)
#Preview {
    ContentView()
        .environmentObject(FlightPlanStore())
}
