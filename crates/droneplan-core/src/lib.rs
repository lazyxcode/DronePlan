//! Copyright (c) 2026 acche. All rights reserved.
//! DronePlan Core Library
//!
//! This library provides the core functionality for drone flight planning,
//! including:
//! - Flight plan data models (waypoints, survey areas)
//! - KMZ/WPML file generation for DJI drones
//! - Geospatial calculations (distance, polygon operations)
//! - Survey line generation algorithms

pub mod models;
pub mod kmz;
pub mod geo;
pub mod error;

pub use models::{FlightPlan, Waypoint, SurveyArea, WaypointAction, PlanMode};
pub use kmz::KmzGenerator;
pub use error::DronePlanError;

/// Result type alias for droneplan operations
pub type Result<T> = std::result::Result<T, DronePlanError>;
