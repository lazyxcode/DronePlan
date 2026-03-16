//! Copyright (c) 2026 acche. All rights reserved.
//! KMZ file generator
//!
//! Creates the complete KMZ archive with all required files.

use std::io::{Cursor, Write};
use zip::write::{SimpleFileOptions, ZipWriter};
use zip::CompressionMethod;

use crate::error::DronePlanError;
use crate::models::FlightPlan;
use crate::Result;

use super::wpml::generate_wpml;
use super::template::generate_template_kml;

/// Generator for KMZ wayline files
pub struct KmzGenerator;

impl KmzGenerator {
    /// Generate a KMZ file from a flight plan
    /// 
    /// Returns the KMZ file contents as a byte vector
    pub fn generate(plan: &FlightPlan) -> Result<Vec<u8>> {
        if plan.waypoints.len() < 2 {
            return Err(DronePlanError::InsufficientWaypoints {
                expected: 2,
                actual: plan.waypoints.len(),
            });
        }

        if !plan.is_valid() {
            return Err(DronePlanError::InvalidFlightPlan(
                "Flight plan contains invalid waypoints".to_string(),
            ));
        }

        let mut buffer = Cursor::new(Vec::new());
        
        {
            let mut zip = ZipWriter::new(&mut buffer);
            let options = SimpleFileOptions::default()
                .compression_method(CompressionMethod::Deflated);

            // Create wpmz directory and files
            zip.add_directory("wpmz", SimpleFileOptions::default())?;
            zip.add_directory("wpmz/res", SimpleFileOptions::default())?;

            // Write template.kml
            let template_content = generate_template_kml(plan);
            zip.start_file("wpmz/template.kml", options)?;
            zip.write_all(template_content.as_bytes())?;

            // Write waylines.wpml
            let wpml_content = generate_wpml(plan);
            zip.start_file("wpmz/waylines.wpml", options)?;
            zip.write_all(wpml_content.as_bytes())?;

            zip.finish()?;
        }

        Ok(buffer.into_inner())
    }

    /// Generate a KMZ file and write it to a path
    pub fn generate_to_file(plan: &FlightPlan, path: &std::path::Path) -> Result<()> {
        let contents = Self::generate(plan)?;
        std::fs::write(path, contents)?;
        Ok(())
    }

    /// Generate a default filename for the flight plan
    pub fn default_filename(plan: &FlightPlan) -> String {
        let sanitized_name: String = plan
            .name
            .chars()
            .map(|c| if c.is_alphanumeric() || c == '-' || c == '_' { c } else { '_' })
            .collect();
        
        format!(
            "{}_{}.kmz",
            sanitized_name,
            plan.created_at.format("%Y%m%d_%H%M%S")
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::{Waypoint, WaypointAction};
    use std::io::Read;
    use zip::ZipArchive;

    #[test]
    fn test_generate_kmz() {
        let mut plan = FlightPlan::new("Test Mission");
        plan.add_waypoint(
            Waypoint::new(39.9042, 116.4074, 100.0)
                .with_action(WaypointAction::TakePhoto),
        );
        plan.add_waypoint(Waypoint::new(39.9052, 116.4084, 100.0));
        plan.add_waypoint(Waypoint::new(39.9062, 116.4094, 100.0));

        let result = KmzGenerator::generate(&plan);
        assert!(result.is_ok(), "Failed to generate KMZ: {:?}", result);

        let kmz_bytes = result.unwrap();
        assert!(!kmz_bytes.is_empty());

        // Verify it's a valid ZIP
        let cursor = Cursor::new(kmz_bytes);
        let archive = ZipArchive::new(cursor);
        assert!(archive.is_ok(), "Not a valid ZIP archive");

        let mut archive = archive.unwrap();
        
        // Check required files exist
        let file_names: Vec<_> = archive.file_names().collect();
        assert!(
            file_names.iter().any(|n| n.contains("template.kml")),
            "Missing template.kml"
        );
        assert!(
            file_names.iter().any(|n| n.contains("waylines.wpml")),
            "Missing waylines.wpml"
        );

        // Read and verify template.kml content
        {
            let mut template_file = archive.by_name("wpmz/template.kml").unwrap();
            let mut contents = String::new();
            template_file.read_to_string(&mut contents).unwrap();
            assert!(contents.contains("DronePlan"));
            assert!(contents.contains("116.4074"));
        }

        // Read and verify waylines.wpml content
        {
            let mut wpml_file = archive.by_name("wpmz/waylines.wpml").unwrap();
            let mut contents = String::new();
            wpml_file.read_to_string(&mut contents).unwrap();
            assert!(contents.contains("missionConfig"));
            assert!(contents.contains("executeHeight"));
        }
    }

    #[test]
    fn test_insufficient_waypoints() {
        let mut plan = FlightPlan::new("Test");
        plan.add_waypoint(Waypoint::new(39.9, 116.4, 100.0));

        let result = KmzGenerator::generate(&plan);
        assert!(matches!(
            result,
            Err(DronePlanError::InsufficientWaypoints { .. })
        ));
    }

    #[test]
    fn test_default_filename() {
        let plan = FlightPlan::new("Test Mission 测试");
        let filename = KmzGenerator::default_filename(&plan);
        
        assert!(filename.ends_with(".kmz"));
        assert!(filename.starts_with("Test_Mission_"));
    }
}
