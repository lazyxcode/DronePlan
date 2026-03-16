//! Copyright (c) 2026 acche. All rights reserved.
//! Geospatial utilities
//!
//! This module provides coordinate calculations and polygon operations.

mod distance;
mod polygon;

pub use distance::{bearing, destination_point, haversine_distance};
pub use polygon::{point_in_polygon, polygon_centroid, polygon_bounds, Bounds};
