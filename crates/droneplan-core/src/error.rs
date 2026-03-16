//! Copyright (c) 2026 acche. All rights reserved.
//! Error types for the droneplan-core library

use thiserror::Error;

/// Errors that can occur during droneplan operations
#[derive(Error, Debug)]
pub enum DronePlanError {
    /// Error during KMZ file generation
    #[error("KMZ generation error: {0}")]
    KmzGeneration(String),

    /// Error during XML serialization
    #[error("XML serialization error: {0}")]
    XmlSerialization(#[from] quick_xml::Error),

    /// Error during ZIP file operations
    #[error("ZIP error: {0}")]
    Zip(#[from] zip::result::ZipError),

    /// IO error
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    /// Invalid flight plan data
    #[error("Invalid flight plan: {0}")]
    InvalidFlightPlan(String),

    /// Invalid coordinates
    #[error("Invalid coordinates: {0}")]
    InvalidCoordinates(String),

    /// Insufficient waypoints for operation
    #[error("Insufficient waypoints: expected at least {expected}, got {actual}")]
    InsufficientWaypoints { expected: usize, actual: usize },
}
