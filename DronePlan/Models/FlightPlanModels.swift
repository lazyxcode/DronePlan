// Copyright (c) 2026 acche. All rights reserved.
//
//  FlightPlanModels.swift
//  DronePlan
//
//  Created by Codex on 16/10/2025.
//

import Foundation
import CoreLocation

// Camera parameters for GSD and spacing calculation
struct CameraParameters: Codable, Hashable {
    var sensorWidth: Double // mm
    var sensorHeight: Double // mm
    var focalLength: Double // mm
    var imageWidth: Int // pixels
    var imageHeight: Int // pixels

    // Common drone presets
    static let djiMini2 = CameraParameters(
        sensorWidth: 6.3,
        sensorHeight: 4.7,
        focalLength: 4.49,
        imageWidth: 4000,
        imageHeight: 3000
    )

    static let djiMavic3 = CameraParameters(
        sensorWidth: 17.3,
        sensorHeight: 13.0,
        focalLength: 12.29,
        imageWidth: 5280,
        imageHeight: 3956
    )

    static let `default` = djiMini2

    // Calculate GSD at given altitude
    func gsd(at altitude: Double) -> Double {
        // GSD = (altitude × sensorWidth) / (focalLength × imageWidth)
        return (altitude * sensorWidth) / (focalLength * Double(imageWidth)) * 1000 // convert to cm
    }

    // Calculate image footprint width at given altitude
    func footprintWidth(at altitude: Double) -> Double {
        // footprint = (altitude × sensorWidth) / focalLength
        return (altitude * sensorWidth) / focalLength
    }

    // Calculate image footprint height at given altitude
    func footprintHeight(at altitude: Double) -> Double {
        return (altitude * sensorHeight) / focalLength
    }
}

struct SurveyArea: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var cornerPoints: [CLLocationCoordinate2D]
    var altitude: Double
    var sideOverlap: Double // side overlap percentage (0-1), typically 0.6-0.7
    var frontOverlap: Double // front overlap percentage (0-1), typically 0.7-0.8
    var angle: Double // survey direction in degrees
    var camera: CameraParameters

    init(id: UUID = UUID(),
         name: String = "Survey Area",
         cornerPoints: [CLLocationCoordinate2D],
         altitude: Double = 60,
         sideOverlap: Double = 0.65,
         frontOverlap: Double = 0.75,
         angle: Double = 0,
         camera: CameraParameters = .default) {
        self.id = id
        self.name = name
        self.cornerPoints = cornerPoints
        self.altitude = altitude
        self.sideOverlap = sideOverlap
        self.frontOverlap = frontOverlap
        self.angle = angle
        self.camera = camera
    }

    // Calculate line spacing based on altitude and camera parameters
    var calculatedSpacing: Double {
        let footprintWidth = camera.footprintWidth(at: altitude)
        return footprintWidth * (1.0 - sideOverlap)
    }

    // Calculate GSD for this survey
    var gsd: Double {
        camera.gsd(at: altitude)
    }

    var centerCoordinate: CLLocationCoordinate2D? {
        guard !cornerPoints.isEmpty else { return nil }
        let lat = cornerPoints.map(\.latitude).reduce(0, +) / Double(cornerPoints.count)
        let lon = cornerPoints.map(\.longitude).reduce(0, +) / Double(cornerPoints.count)
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var isValid: Bool {
        cornerPoints.count >= 3
    }

    // Generate waypoints using orthogonal survey pattern with rotation
    func generateWaypoints(speed: Double = 8, holdTime: TimeInterval = 2) -> [Waypoint] {
        guard isValid else { return [] }

        var waypoints: [Waypoint] = []
        
        // Convert angle to radians
        let rotationRadians = angle * .pi / 180.0
        
        // Center for rotation
        let center = centerCoordinate ?? cornerPoints[0]
        
        // Rotate corner points to local grid aligned with survey angle
        let rotatedPoints = cornerPoints.map { rotatePoint($0, center: center, radians: -rotationRadians) }
        
        // Calculate bounds in rotated space
        let minLat = rotatedPoints.map(\.latitude).min() ?? 0
        let maxLat = rotatedPoints.map(\.latitude).max() ?? 0
        let minLon = rotatedPoints.map(\.longitude).min() ?? 0
        let maxLon = rotatedPoints.map(\.longitude).max() ?? 0

        // Calculate spacing in degrees (approximate) - in rotated space
        // Note: This approximation works well for small areas. For large areas, use proper geodesic calculations.
        let metersPerDegreeLat = 111320.0
        let avgLat = (minLat + maxLat) / 2
        let metersPerDegreeLon = metersPerDegreeLat * cos(avgLat * .pi / 180.0)

        // Use calculated spacing based on altitude and camera parameters
        let actualSpacing = calculatedSpacing
        let spacingLat = actualSpacing / metersPerDegreeLat
        let spacingLon = actualSpacing / metersPerDegreeLon // We only need line spacing (lat in our grid)

        // Generate grid lines in rotated space (sweep along latitude)
        var lat = minLat
        var isReverse = false

        while lat <= maxLat {
            // Define line start and end in rotated space
            let startLon = minLon - spacingLon // Add buffer
            let endLon = maxLon + spacingLon   // Add buffer
            
            // Sample points along the line
            let samplingStep = 5.0 / metersPerDegreeLon // 5 meters resolution for checking polygon intersection
            
            var linePoints: [CLLocationCoordinate2D] = []
            
            var lon = startLon
            while lon <= endLon {
                let rotatedPoint = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                // Rotate back to global coordinates to check intersection
                let globalPoint = rotatePoint(rotatedPoint, center: center, radians: rotationRadians)
                
                if isPointInPolygon(point: globalPoint, polygon: cornerPoints) {
                    linePoints.append(globalPoint)
                }
                lon += samplingStep
            }
            
            if !linePoints.isEmpty {
                 // Clean up the line: keep start and end points of segments inside polygon
                 // For simple convex polygons, this is just min and max longitude points
                 if let first = linePoints.first, let last = linePoints.last {
                     if isReverse {
                         waypoints.append(Waypoint(latitude: last.latitude, longitude: last.longitude, altitude: altitude, holdTime: holdTime, speed: speed))
                         waypoints.append(Waypoint(latitude: first.latitude, longitude: first.longitude, altitude: altitude, holdTime: holdTime, speed: speed))
                     } else {
                         waypoints.append(Waypoint(latitude: first.latitude, longitude: first.longitude, altitude: altitude, holdTime: holdTime, speed: speed))
                         waypoints.append(Waypoint(latitude: last.latitude, longitude: last.longitude, altitude: altitude, holdTime: holdTime, speed: speed))
                     }
                 }
            }

            isReverse.toggle()
            lat += spacingLat
        }

        return waypoints
    }
    
    // Rotate a point around a center
    private func rotatePoint(_ point: CLLocationCoordinate2D, center: CLLocationCoordinate2D, radians: Double) -> CLLocationCoordinate2D {
        let latDiff = point.latitude - center.latitude
        let lonDiff = point.longitude - center.longitude
        
        // Simple 2D rotation (equirectangular projection approximation)
        // Adjust longitude for latitude scaling
        let latScale = cos(center.latitude * .pi / 180.0)
        let x = lonDiff * latScale
        let y = latDiff
        
        let xNew = x * cos(radians) - y * sin(radians)
        let yNew = x * sin(radians) + y * cos(radians)
        
        return CLLocationCoordinate2D(
            latitude: center.latitude + yNew,
            longitude: center.longitude + (xNew / latScale)
        )
    }

    // Ray casting algorithm to check if point is inside polygon
    private func isPointInPolygon(point: CLLocationCoordinate2D, polygon: [CLLocationCoordinate2D]) -> Bool {
        var inside = false
        var j = polygon.count - 1

        for i in 0..<polygon.count {
            let xi = polygon[i].longitude
            let yi = polygon[i].latitude
            let xj = polygon[j].longitude
            let yj = polygon[j].latitude

            let intersect = ((yi > point.latitude) != (yj > point.latitude)) &&
                           (point.longitude < (xj - xi) * (point.latitude - yi) / (yj - yi) + xi)

            if intersect {
                inside.toggle()
            }
            j = i
        }

        return inside
    }
}

// Codable conformance for CLLocationCoordinate2D
extension CLLocationCoordinate2D: Codable {
    enum CodingKeys: String, CodingKey {
        case latitude, longitude
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(CLLocationDegrees.self, forKey: .latitude)
        let longitude = try container.decode(CLLocationDegrees.self, forKey: .longitude)
        self.init(latitude: latitude, longitude: longitude)
    }
}

// Hashable and Equatable conformance for CLLocationCoordinate2D
extension CLLocationCoordinate2D: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(latitude)
        hasher.combine(longitude)
    }

    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

struct Waypoint: Identifiable, Hashable, Codable {
    let id: UUID
    var latitude: CLLocationDegrees
    var longitude: CLLocationDegrees
    var altitude: Double
    var holdTime: TimeInterval
    var speed: Double

    init(id: UUID = UUID(),
         latitude: CLLocationDegrees,
         longitude: CLLocationDegrees,
         altitude: Double = 60,
         holdTime: TimeInterval = 2,
         speed: Double = 8) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.holdTime = holdTime
        self.speed = speed
    }

    var coordinate: CLLocationCoordinate2D {
        get { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
        set {
            latitude = newValue.latitude
            longitude = newValue.longitude
        }
    }
}

enum PlanMode: String, Codable {
    case manual = "手动航点"
    case survey = "测绘区域"
}

struct FlightPlan: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var createdAt: Date
    var mode: PlanMode
    var waypoints: [Waypoint]
    var surveyAreas: [SurveyArea]

    // Global parameters
    var cruiseSpeed: Double
    var maxAltitude: Double
    var cameraAngle: Double
    var photoInterval: TimeInterval

    init(id: UUID = UUID(),
         name: String,
         createdAt: Date = .now,
         mode: PlanMode = .manual,
         waypoints: [Waypoint] = [],
         surveyAreas: [SurveyArea] = [],
         cruiseSpeed: Double = 8,
         maxAltitude: Double = 120,
         cameraAngle: Double = -90,
         photoInterval: TimeInterval = 2) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.mode = mode
        self.waypoints = waypoints
        self.surveyAreas = surveyAreas
        self.cruiseSpeed = cruiseSpeed
        self.maxAltitude = maxAltitude
        self.cameraAngle = cameraAngle
        self.photoInterval = photoInterval
    }

    // Get all waypoints based on current mode
    var allWaypoints: [Waypoint] {
        switch mode {
        case .manual:
            return waypoints
        case .survey:
            var all: [Waypoint] = []
            for area in surveyAreas {
                all.append(contentsOf: area.generateWaypoints(speed: cruiseSpeed, holdTime: photoInterval))
            }
            return all
        }
    }

    var centerCoordinate: CLLocationCoordinate2D? {
        guard !waypoints.isEmpty else { return nil }
        let lat = waypoints.map(\.latitude).reduce(0, +) / Double(waypoints.count)
        let lon = waypoints.map(\.longitude).reduce(0, +) / Double(waypoints.count)
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var hasEnoughWaypointsForPolygon: Bool {
        waypoints.count >= 3
    }
}

extension FlightPlan {
    func kmlDocumentString(waypoints waypointsToExport: [Waypoint]? = nil) -> String {
        let waypointsToUse = waypointsToExport ?? allWaypoints

        let header = """
        <?xml version="1.0" encoding="UTF-8"?>
        <kml xmlns="http://www.opengis.net/kml/2.2">
          <Document>
            <name>\(name.xmlEscaped)</name>
        """

        let placemarks = waypointsToUse.enumerated().map { index, waypoint in
            """
            <Placemark>
              <name>WP \(index + 1)</name>
              <description>Altitude: \(waypoint.altitude)m, Speed: \(waypoint.speed)m/s, Hold: \(Int(waypoint.holdTime))s</description>
              <Point>
                <coordinates>\(waypoint.longitude),\(waypoint.latitude),\(waypoint.altitude)</coordinates>
              </Point>
            </Placemark>
            """
        }.joined(separator: "\n")

        let polygon: String
        if hasEnoughWaypointsForPolygon {
            let coords = waypoints + [waypoints.first!]
            let lines = coords.map { "\($0.longitude),\($0.latitude),\($0.altitude)" }.joined(separator: " ")
            polygon = """
            <Placemark>
              <name>Flight Boundary</name>
              <Style>
                <LineStyle><color>ff00ffff</color><width>2</width></LineStyle>
                <PolyStyle><color>3d00ffff</color></PolyStyle>
              </Style>
              <Polygon>
                <outerBoundaryIs>
                  <LinearRing>
                    <coordinates>\(lines)</coordinates>
                  </LinearRing>
                </outerBoundaryIs>
              </Polygon>
            </Placemark>
            <Placemark>
              <name>Flight Path</name>
              <Style>
                <LineStyle><color>ff00ff00</color><width>3</width></LineStyle>
              </Style>
              <LineString>
                <coordinates>\(lines)</coordinates>
              </LineString>
            </Placemark>
            """
        } else {
            polygon = ""
        }

        let footer = """
            <Schema name="FlightParameters">
              <SimpleField name="CruiseSpeed" type="float"></SimpleField>
              <SimpleField name="MaxAltitude" type="float"></SimpleField>
              <SimpleField name="CameraAngle" type="float"></SimpleField>
              <SimpleField name="PhotoInterval" type="float"></SimpleField>
            </Schema>
            <ExtendedData>
              <Data name="CruiseSpeed"><value>\(cruiseSpeed)</value></Data>
              <Data name="MaxAltitude"><value>\(maxAltitude)</value></Data>
              <Data name="CameraAngle"><value>\(cameraAngle)</value></Data>
              <Data name="PhotoInterval"><value>\(photoInterval)</value></Data>
            </ExtendedData>
          </Document>
        </kml>
        """

        return [header, placemarks, polygon, footer].joined(separator: "\n")
    }
}

private extension String {
    var xmlEscaped: String {
        self
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
