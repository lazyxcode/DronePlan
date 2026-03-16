//! Copyright (c) 2026 acche. All rights reserved.
//! Waypoint data model
//!
//! Represents a single point in a flight path with associated parameters.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// A single waypoint in a flight plan
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Waypoint {
    /// Unique identifier for the waypoint
    pub id: Uuid,
    /// Latitude in WGS84 (degrees)
    pub latitude: f64,
    /// Longitude in WGS84 (degrees)
    pub longitude: f64,
    /// Altitude above takeoff point (meters)
    pub altitude: f64,
    /// Flight speed to this waypoint (m/s)
    pub speed: f64,
    /// Time to hover at this waypoint (seconds)
    pub hold_time: f64,
    /// Heading angle (degrees, 0-360, 0=North)
    pub heading: Option<f64>,
    /// Gimbal pitch angle (degrees, -90 to 0)
    pub gimbal_pitch: Option<f64>,
    /// Actions to perform at this waypoint
    pub actions: Vec<WaypointAction>,
}

impl Waypoint {
    /// Create a new waypoint with default parameters
    pub fn new(latitude: f64, longitude: f64, altitude: f64) -> Self {
        Self {
            id: Uuid::new_v4(),
            latitude,
            longitude,
            altitude,
            speed: 5.0,       // Default 5 m/s
            hold_time: 0.0,   // No hover by default
            heading: None,    // Auto heading
            gimbal_pitch: Some(-45.0), // 45 degrees down
            actions: Vec::new(),
        }
    }

    /// Set the flight speed
    pub fn with_speed(mut self, speed: f64) -> Self {
        self.speed = speed;
        self
    }

    /// Set the hold/hover time
    pub fn with_hold_time(mut self, seconds: f64) -> Self {
        self.hold_time = seconds;
        self
    }

    /// Set the heading angle
    pub fn with_heading(mut self, degrees: f64) -> Self {
        self.heading = Some(degrees);
        self
    }

    /// Set the gimbal pitch angle
    pub fn with_gimbal_pitch(mut self, degrees: f64) -> Self {
        self.gimbal_pitch = Some(degrees);
        self
    }

    /// Add an action to perform at this waypoint
    pub fn with_action(mut self, action: WaypointAction) -> Self {
        self.actions.push(action);
        self
    }

    /// Validate the waypoint coordinates
    pub fn is_valid(&self) -> bool {
        self.latitude >= -90.0
            && self.latitude <= 90.0
            && self.longitude >= -180.0
            && self.longitude <= 180.0
            && self.altitude > 0.0
            && self.speed > 0.0
    }
}

/// Actions that can be performed at a waypoint
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum WaypointAction {
    /// Take a photo
    TakePhoto,
    /// Start recording video
    StartRecording,
    /// Stop recording video
    StopRecording,
    /// Rotate aircraft to specific heading (degrees)
    RotateAircraft(f64),
    /// Set gimbal pitch angle (degrees)
    SetGimbalPitch(f64),
    /// Hover for a duration (seconds)
    Hover(f64),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_waypoint_creation() {
        let wp = Waypoint::new(39.9042, 116.4074, 100.0);
        assert_eq!(wp.latitude, 39.9042);
        assert_eq!(wp.longitude, 116.4074);
        assert_eq!(wp.altitude, 100.0);
        assert_eq!(wp.speed, 5.0);
        assert!(wp.is_valid());
    }

    #[test]
    fn test_waypoint_builder() {
        let wp = Waypoint::new(39.9042, 116.4074, 100.0)
            .with_speed(10.0)
            .with_hold_time(5.0)
            .with_heading(90.0)
            .with_action(WaypointAction::TakePhoto);

        assert_eq!(wp.speed, 10.0);
        assert_eq!(wp.hold_time, 5.0);
        assert_eq!(wp.heading, Some(90.0));
        assert_eq!(wp.actions.len(), 1);
    }

    #[test]
    fn test_invalid_waypoint() {
        let wp = Waypoint::new(91.0, 116.4074, 100.0); // Invalid latitude
        assert!(!wp.is_valid());

        let wp = Waypoint::new(39.9042, 181.0, 100.0); // Invalid longitude
        assert!(!wp.is_valid());

        let wp = Waypoint::new(39.9042, 116.4074, -10.0); // Negative altitude
        assert!(!wp.is_valid());
    }
}
