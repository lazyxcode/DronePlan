//! Example: Generate a sample KMZ file
//!
//! This example creates a flight plan with several waypoints and generates
//! a KMZ file that can be imported into DJI RC2/DJI Fly.
//!
//! Run with: cargo run --example generate_sample_kmz

use droneplan_core::{FlightPlan, Waypoint, WaypointAction, KmzGenerator};
use std::path::PathBuf;

fn main() {
    // Create a flight plan
    let mut plan = FlightPlan::new("Sample Mission 测试任务");
    
    // Set flight parameters
    plan.set_cruise_speed(8.0);       // 8 m/s
    plan.set_max_altitude(120.0);     // 120m
    plan.set_camera_angle(-45.0);     // 45 degrees down
    
    // Add waypoints (Beijing area coordinates)
    plan.add_waypoint(
        Waypoint::new(39.9042, 116.4074, 80.0)
            .with_hold_time(3.0)
            .with_action(WaypointAction::TakePhoto)
    );
    
    plan.add_waypoint(
        Waypoint::new(39.9052, 116.4084, 80.0)
            .with_action(WaypointAction::TakePhoto)
    );
    
    plan.add_waypoint(
        Waypoint::new(39.9062, 116.4094, 100.0)
            .with_action(WaypointAction::StartRecording)
    );
    
    plan.add_waypoint(
        Waypoint::new(39.9072, 116.4084, 100.0)
            .with_action(WaypointAction::TakePhoto)
    );
    
    plan.add_waypoint(
        Waypoint::new(39.9072, 116.4074, 80.0)
            .with_hold_time(5.0)
            .with_action(WaypointAction::StopRecording)
            .with_action(WaypointAction::TakePhoto)
    );
    
    // Print flight info
    println!("Flight Plan: {}", plan.name);
    println!("Waypoints: {}", plan.waypoint_count());
    println!("Estimated distance: {:.0} m", plan.estimated_distance());
    println!("Estimated flight time: {:.0} s", plan.estimated_flight_time());
    println!();
    
    // Generate KMZ file
    let filename = KmzGenerator::default_filename(&plan);
    let output_path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .parent()
        .unwrap()
        .join(&filename);
    
    match KmzGenerator::generate_to_file(&plan, &output_path) {
        Ok(()) => {
            println!("✓ Generated KMZ file: {}", output_path.display());
            println!();
            println!("To use this file:");
            println!("1. Export the KMZ to Windows or copy it to a microSD card");
            println!("2. Replace the matching DJI Fly mission package on RC 2");
            println!("3. Open DJI Fly and verify the mission before flight");
        }
        Err(e) => {
            eprintln!("✗ Failed to generate KMZ: {}", e);
            std::process::exit(1);
        }
    }
}
