//! Copyright (c) 2026 acche. All rights reserved.
//! Distance calculations using the Haversine formula

use std::f64::consts::PI;

/// Earth's radius in meters (WGS84 mean radius)
const EARTH_RADIUS_M: f64 = 6_371_008.8;

/// Calculate the great-circle distance between two points using the Haversine formula.
/// 
/// # Arguments
/// * `lat1`, `lon1` - First point coordinates in degrees
/// * `lat2`, `lon2` - Second point coordinates in degrees
/// 
/// # Returns
/// Distance in meters
pub fn haversine_distance(lat1: f64, lon1: f64, lat2: f64, lon2: f64) -> f64 {
    let lat1_rad = lat1 * PI / 180.0;
    let lat2_rad = lat2 * PI / 180.0;
    let delta_lat = (lat2 - lat1) * PI / 180.0;
    let delta_lon = (lon2 - lon1) * PI / 180.0;

    let a = (delta_lat / 2.0).sin().powi(2)
        + lat1_rad.cos() * lat2_rad.cos() * (delta_lon / 2.0).sin().powi(2);
    
    let c = 2.0 * a.sqrt().atan2((1.0 - a).sqrt());
    
    EARTH_RADIUS_M * c
}

/// Calculate bearing from point 1 to point 2
/// 
/// # Returns
/// Bearing in degrees (0-360, 0 = North)
pub fn bearing(lat1: f64, lon1: f64, lat2: f64, lon2: f64) -> f64 {
    let lat1_rad = lat1 * PI / 180.0;
    let lat2_rad = lat2 * PI / 180.0;
    let delta_lon = (lon2 - lon1) * PI / 180.0;

    let y = delta_lon.sin() * lat2_rad.cos();
    let x = lat1_rad.cos() * lat2_rad.sin() 
        - lat1_rad.sin() * lat2_rad.cos() * delta_lon.cos();
    
    let bearing_rad = y.atan2(x);
    (bearing_rad * 180.0 / PI + 360.0) % 360.0
}

/// Calculate destination point given start point, bearing, and distance
/// 
/// # Arguments
/// * `lat`, `lon` - Starting point in degrees
/// * `bearing_deg` - Bearing in degrees
/// * `distance_m` - Distance in meters
/// 
/// # Returns
/// (latitude, longitude) of destination point
pub fn destination_point(lat: f64, lon: f64, bearing_deg: f64, distance_m: f64) -> (f64, f64) {
    let lat_rad = lat * PI / 180.0;
    let lon_rad = lon * PI / 180.0;
    let bearing_rad = bearing_deg * PI / 180.0;
    let angular_distance = distance_m / EARTH_RADIUS_M;

    let dest_lat_rad = (lat_rad.sin() * angular_distance.cos()
        + lat_rad.cos() * angular_distance.sin() * bearing_rad.cos())
        .asin();
    
    let dest_lon_rad = lon_rad
        + (bearing_rad.sin() * angular_distance.sin() * lat_rad.cos())
            .atan2(angular_distance.cos() - lat_rad.sin() * dest_lat_rad.sin());

    (dest_lat_rad * 180.0 / PI, dest_lon_rad * 180.0 / PI)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_haversine_same_point() {
        let d = haversine_distance(39.9042, 116.4074, 39.9042, 116.4074);
        assert!(d.abs() < 0.001, "Distance should be 0, got {}", d);
    }

    #[test]
    fn test_haversine_known_distance() {
        // Beijing to Shanghai: approximately 1068 km
        let d = haversine_distance(39.9042, 116.4074, 31.2304, 121.4737);
        assert!(d > 1_060_000.0 && d < 1_080_000.0, "Distance was {}", d);
    }

    #[test]
    fn test_bearing_north() {
        let b = bearing(39.0, 116.0, 40.0, 116.0);
        assert!((b - 0.0).abs() < 1.0, "Bearing should be ~0 (north), got {}", b);
    }

    #[test]
    fn test_bearing_east() {
        let b = bearing(39.0, 116.0, 39.0, 117.0);
        assert!((b - 90.0).abs() < 5.0, "Bearing should be ~90 (east), got {}", b);
    }

    #[test]
    fn test_destination_point() {
        let (lat, lon) = destination_point(39.9, 116.4, 0.0, 1000.0);
        // Moving 1km north should increase latitude
        assert!(lat > 39.9, "Latitude should increase when moving north");
        assert!((lon - 116.4).abs() < 0.001, "Longitude should stay same");
    }
}
