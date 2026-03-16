//! Copyright (c) 2026 acche. All rights reserved.
//! Flight plan data model
//!
//! Represents a complete flight mission with waypoints and parameters.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::Waypoint;

/// Flight plan mode
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum PlanMode {
    /// Manual waypoint placement
    #[default]
    Manual,
    /// Survey/mapping mode with generated grid pattern
    Survey,
}

/// Height reference mode for flight altitude
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum HeightMode {
    /// Height relative to takeoff point
    #[default]
    RelativeToTakeoff,
    /// Height using WGS84 ellipsoid
    WGS84,
    /// Real-time terrain following
    TerrainFollow,
}

/// Finish action when mission completes
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum FinishAction {
    /// Return to home point
    #[default]
    GoHome,
    /// Land at last waypoint
    AutoLand,
    /// Hover at last waypoint
    Hover,
    /// No action (continue manual control)
    NoAction,
}

/// A complete flight plan/mission
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FlightPlan {
    /// Unique identifier
    pub id: Uuid,
    /// Plan name
    pub name: String,
    /// Creation timestamp
    pub created_at: DateTime<Utc>,
    /// Last modification timestamp
    pub updated_at: DateTime<Utc>,
    /// Flight mode
    pub mode: PlanMode,
    /// List of waypoints
    pub waypoints: Vec<Waypoint>,
    /// Cruise speed (m/s)
    pub cruise_speed: f64,
    /// Maximum altitude (meters)
    pub max_altitude: f64,
    /// Camera/gimbal angle (degrees, -90 to 0)
    pub camera_angle: f64,
    /// Photo interval (seconds)
    pub photo_interval: f64,
    /// Height reference mode
    pub height_mode: HeightMode,
    /// Action on mission complete
    pub finish_action: FinishAction,
    /// Auto takeoff enabled
    pub auto_takeoff: bool,
    /// Return to home altitude (meters)
    pub rth_altitude: f64,
}

impl FlightPlan {
    /// Create a new flight plan with default parameters
    pub fn new(name: impl Into<String>) -> Self {
        let now = Utc::now();
        Self {
            id: Uuid::new_v4(),
            name: name.into(),
            created_at: now,
            updated_at: now,
            mode: PlanMode::default(),
            waypoints: Vec::new(),
            cruise_speed: 8.0,       // 8 m/s default
            max_altitude: 120.0,     // 120m (common limit)
            camera_angle: -45.0,     // 45 degrees down
            photo_interval: 2.0,     // 2 seconds
            height_mode: HeightMode::default(),
            finish_action: FinishAction::default(),
            auto_takeoff: false,
            rth_altitude: 50.0,      // 50m RTH altitude
        }
    }

    /// Add a waypoint to the plan
    pub fn add_waypoint(&mut self, waypoint: Waypoint) {
        self.waypoints.push(waypoint);
        self.updated_at = Utc::now();
    }

    /// Remove a waypoint by index
    pub fn remove_waypoint(&mut self, index: usize) -> Option<Waypoint> {
        if index < self.waypoints.len() {
            let removed = self.waypoints.remove(index);
            self.updated_at = Utc::now();
            Some(removed)
        } else {
            None
        }
    }

    /// Update cruise speed
    pub fn set_cruise_speed(&mut self, speed: f64) {
        self.cruise_speed = speed.clamp(2.0, 25.0);
        self.updated_at = Utc::now();
    }

    /// Update maximum altitude
    pub fn set_max_altitude(&mut self, altitude: f64) {
        self.max_altitude = altitude.clamp(20.0, 500.0);
        self.updated_at = Utc::now();
    }

    /// Update camera angle
    pub fn set_camera_angle(&mut self, angle: f64) {
        self.camera_angle = angle.clamp(-90.0, 0.0);
        self.updated_at = Utc::now();
    }

    /// Get total number of waypoints
    pub fn waypoint_count(&self) -> usize {
        self.waypoints.len()
    }

    /// Check if the plan has enough waypoints for a valid mission
    pub fn is_valid(&self) -> bool {
        self.waypoints.len() >= 2 && self.waypoints.iter().all(|wp| wp.is_valid())
    }

    /// Calculate estimated flight distance (meters)
    pub fn estimated_distance(&self) -> f64 {
        if self.waypoints.len() < 2 {
            return 0.0;
        }
        
        let mut total = 0.0;
        for i in 1..self.waypoints.len() {
            let prev = &self.waypoints[i - 1];
            let curr = &self.waypoints[i];
            total += crate::geo::haversine_distance(
                prev.latitude, prev.longitude,
                curr.latitude, curr.longitude,
            );
        }
        total
    }

    /// Calculate estimated flight time (seconds)
    pub fn estimated_flight_time(&self) -> f64 {
        let distance = self.estimated_distance();
        let hold_time: f64 = self.waypoints.iter().map(|wp| wp.hold_time).sum();
        
        if self.cruise_speed > 0.0 {
            (distance / self.cruise_speed) + hold_time
        } else {
            hold_time
        }
    }
}

impl Default for FlightPlan {
    fn default() -> Self {
        Self::new("Untitled Plan")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_flight_plan_creation() {
        let plan = FlightPlan::new("Test Mission");
        assert_eq!(plan.name, "Test Mission");
        assert_eq!(plan.waypoint_count(), 0);
        assert!(!plan.is_valid()); // No waypoints yet
    }

    #[test]
    fn test_add_waypoints() {
        let mut plan = FlightPlan::new("Test");
        plan.add_waypoint(Waypoint::new(39.9, 116.4, 100.0));
        plan.add_waypoint(Waypoint::new(39.91, 116.41, 100.0));
        
        assert_eq!(plan.waypoint_count(), 2);
        assert!(plan.is_valid());
    }

    #[test]
    fn test_parameter_clamping() {
        let mut plan = FlightPlan::new("Test");
        
        plan.set_cruise_speed(100.0);
        assert_eq!(plan.cruise_speed, 25.0); // Clamped to max
        
        plan.set_cruise_speed(0.5);
        assert_eq!(plan.cruise_speed, 2.0); // Clamped to min
        
        plan.set_max_altitude(1000.0);
        assert_eq!(plan.max_altitude, 500.0); // Clamped to max
    }
}
