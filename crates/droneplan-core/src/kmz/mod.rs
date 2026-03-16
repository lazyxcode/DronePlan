//! Copyright (c) 2026 acche. All rights reserved.
//! KMZ file generation for DJI drones
//!
//! This module generates KMZ files in DJI's WPML format for wayline missions.

mod generator;
mod wpml;
mod template;

pub use generator::KmzGenerator;
