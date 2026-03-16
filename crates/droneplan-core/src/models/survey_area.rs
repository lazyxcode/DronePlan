//! Copyright (c) 2026 acche. All rights reserved.
//! Survey area data model
//!
//! Represents a polygonal mapping/survey area with auto-generated flight lines.

use geo::{Coord, LineString, Polygon};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// A survey/mapping area defined by corner points
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SurveyArea {
    /// Unique identifier
    pub id: Uuid,
    /// Area name
    pub name: String,
    /// Corner points defining the polygon (lat, lon)
    pub corner_points: Vec<(f64, f64)>,
    /// Flight altitude (meters)
    pub altitude: f64,
    /// Image overlap percentage (0-100)
    pub overlap_percent: f64,
    /// Side overlap percentage (0-100)
    pub sidelap_percent: f64,
    /// Flight line angle (degrees from north)
    pub flight_angle: f64,
    /// Camera sensor width (mm)
    pub sensor_width: f64,
    /// Camera focal length (mm)
    pub focal_length: f64,
    /// Image width (pixels)
    pub image_width: u32,
}

impl SurveyArea {
    /// Default sensor parameters for DJI Mini 4 Pro (1/1.3" CMOS)
    pub const DEFAULT_SENSOR_WIDTH: f64 = 9.8;    // mm
    pub const DEFAULT_FOCAL_LENGTH: f64 = 6.72;   // mm (24mm equiv)
    pub const DEFAULT_IMAGE_WIDTH: u32 = 4032;    // pixels (48MP mode)

    /// Create a new survey area with default parameters
    pub fn new(name: impl Into<String>, corner_points: Vec<(f64, f64)>, altitude: f64) -> Self {
        Self {
            id: Uuid::new_v4(),
            name: name.into(),
            corner_points,
            altitude,
            overlap_percent: 70.0,
            sidelap_percent: 60.0,
            flight_angle: 0.0,
            sensor_width: Self::DEFAULT_SENSOR_WIDTH,
            focal_length: Self::DEFAULT_FOCAL_LENGTH,
            image_width: Self::DEFAULT_IMAGE_WIDTH,
        }
    }

    /// Calculate Ground Sample Distance (GSD) in cm/pixel
    pub fn gsd(&self) -> f64 {
        // GSD = (sensor_width * altitude * 100) / (focal_length * image_width)
        (self.sensor_width * self.altitude * 100.0) 
            / (self.focal_length * self.image_width as f64)
    }

    /// Calculate ground coverage width (meters)
    pub fn ground_coverage_width(&self) -> f64 {
        (self.sensor_width * self.altitude) / self.focal_length
    }

    /// Calculate line spacing based on sidelap (meters)
    pub fn calculated_spacing(&self) -> f64 {
        let coverage = self.ground_coverage_width();
        coverage * (1.0 - self.sidelap_percent / 100.0)
    }

    /// Calculate photo interval distance based on overlap (meters)
    pub fn photo_interval_distance(&self) -> f64 {
        let coverage = self.ground_coverage_width();
        coverage * (1.0 - self.overlap_percent / 100.0)
    }

    /// Check if area has enough points to form a valid polygon
    pub fn is_valid(&self) -> bool {
        self.corner_points.len() >= 3 && self.altitude > 0.0
    }

    /// Convert to geo crate Polygon for calculations
    pub fn to_polygon(&self) -> Option<Polygon<f64>> {
        if self.corner_points.len() < 3 {
            return None;
        }

        let coords: Vec<Coord<f64>> = self.corner_points
            .iter()
            .map(|(lat, lon)| Coord { x: *lon, y: *lat })
            .collect();

        let mut ring_coords = coords.clone();
        ring_coords.push(coords[0]); // Close the ring
        
        let line_string = LineString::new(ring_coords);
        Some(Polygon::new(line_string, vec![]))
    }

    /// Calculate area in square meters (approximate)
    pub fn area_sqm(&self) -> f64 {
        use geo::Area;
        
        self.to_polygon()
            .map(|poly| {
                // geo crate returns area in square degrees
                // Convert approximately to square meters
                // This is a rough approximation; for precision, use proper projection
                let center_lat = self.corner_points
                    .iter()
                    .map(|(lat, _)| *lat)
                    .sum::<f64>() / self.corner_points.len() as f64;
                
                let lat_meters = 111_320.0; // meters per degree latitude
                let lon_meters = 111_320.0 * center_lat.to_radians().cos();
                
                let area_degrees = poly.unsigned_area();
                area_degrees * lat_meters * lon_meters
            })
            .unwrap_or(0.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_survey_area_creation() {
        let corners = vec![
            (39.90, 116.40),
            (39.90, 116.41),
            (39.91, 116.41),
            (39.91, 116.40),
        ];
        let area = SurveyArea::new("Test Area", corners, 100.0);
        
        assert_eq!(area.name, "Test Area");
        assert_eq!(area.altitude, 100.0);
        assert!(area.is_valid());
    }

    #[test]
    fn test_gsd_calculation() {
        let area = SurveyArea::new("Test", vec![(0.0, 0.0); 3], 100.0);
        let gsd = area.gsd();
        
        // At 100m with default camera (1/1.3" sensor), GSD should be around 3.6 cm/px
        assert!(gsd > 3.0 && gsd < 4.0, "GSD was {}", gsd);
    }

    #[test]
    fn test_line_spacing() {
        let area = SurveyArea::new("Test", vec![(0.0, 0.0); 3], 100.0);
        let spacing = area.calculated_spacing();
        
        // With 60% sidelap, spacing should be 40% of coverage width
        let expected = area.ground_coverage_width() * 0.4;
        assert!((spacing - expected).abs() < 0.001);
    }

    #[test]
    fn test_invalid_area() {
        let area = SurveyArea::new("Test", vec![(0.0, 0.0); 2], 100.0);
        assert!(!area.is_valid()); // Only 2 points

        let area = SurveyArea::new("Test", vec![(0.0, 0.0); 3], -10.0);
        assert!(!area.is_valid()); // Negative altitude
    }
}
