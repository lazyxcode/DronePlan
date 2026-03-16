//! Copyright (c) 2026 acche. All rights reserved.
//! Polygon operations for survey areas

/// Bounding box structure
#[derive(Debug, Clone, Copy)]
pub struct Bounds {
    pub min_lat: f64,
    pub max_lat: f64,
    pub min_lon: f64,
    pub max_lon: f64,
}

impl Bounds {
    /// Create bounds from a list of points
    pub fn from_points(points: &[(f64, f64)]) -> Option<Self> {
        if points.is_empty() {
            return None;
        }

        let mut min_lat = f64::MAX;
        let mut max_lat = f64::MIN;
        let mut min_lon = f64::MAX;
        let mut max_lon = f64::MIN;

        for (lat, lon) in points {
            min_lat = min_lat.min(*lat);
            max_lat = max_lat.max(*lat);
            min_lon = min_lon.min(*lon);
            max_lon = max_lon.max(*lon);
        }

        Some(Self {
            min_lat,
            max_lat,
            min_lon,
            max_lon,
        })
    }

    /// Get the center point of the bounds
    pub fn center(&self) -> (f64, f64) {
        (
            (self.min_lat + self.max_lat) / 2.0,
            (self.min_lon + self.max_lon) / 2.0,
        )
    }

    /// Get width in degrees
    pub fn width(&self) -> f64 {
        self.max_lon - self.min_lon
    }

    /// Get height in degrees
    pub fn height(&self) -> f64 {
        self.max_lat - self.min_lat
    }
}

/// Calculate the centroid (center of mass) of a polygon
pub fn polygon_centroid(points: &[(f64, f64)]) -> Option<(f64, f64)> {
    if points.is_empty() {
        return None;
    }

    let n = points.len() as f64;
    let sum_lat: f64 = points.iter().map(|(lat, _)| lat).sum();
    let sum_lon: f64 = points.iter().map(|(_, lon)| lon).sum();

    Some((sum_lat / n, sum_lon / n))
}

/// Calculate the bounding box of a polygon
pub fn polygon_bounds(points: &[(f64, f64)]) -> Option<Bounds> {
    Bounds::from_points(points)
}

/// Check if a point is inside a polygon using ray casting algorithm
pub fn point_in_polygon(point: (f64, f64), polygon: &[(f64, f64)]) -> bool {
    let (py, px) = point;
    let n = polygon.len();
    
    if n < 3 {
        return false;
    }

    let mut inside = false;
    let mut j = n - 1;

    for i in 0..n {
        let (yi, xi) = polygon[i];
        let (yj, xj) = polygon[j];

        if ((yi > py) != (yj > py))
            && (px < (xj - xi) * (py - yi) / (yj - yi) + xi)
        {
            inside = !inside;
        }
        j = i;
    }

    inside
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bounds() {
        let points = vec![
            (39.90, 116.40),
            (39.90, 116.42),
            (39.92, 116.42),
            (39.92, 116.40),
        ];
        
        let bounds = Bounds::from_points(&points).unwrap();
        assert!((bounds.min_lat - 39.90).abs() < 0.001);
        assert!((bounds.max_lat - 39.92).abs() < 0.001);
        assert!((bounds.min_lon - 116.40).abs() < 0.001);
        assert!((bounds.max_lon - 116.42).abs() < 0.001);
    }

    #[test]
    fn test_centroid() {
        let points = vec![
            (0.0, 0.0),
            (0.0, 2.0),
            (2.0, 2.0),
            (2.0, 0.0),
        ];
        
        let (lat, lon) = polygon_centroid(&points).unwrap();
        assert!((lat - 1.0).abs() < 0.001);
        assert!((lon - 1.0).abs() < 0.001);
    }

    #[test]
    fn test_point_in_polygon() {
        let square = vec![
            (0.0, 0.0),
            (0.0, 10.0),
            (10.0, 10.0),
            (10.0, 0.0),
        ];

        assert!(point_in_polygon((5.0, 5.0), &square));
        assert!(!point_in_polygon((15.0, 5.0), &square));
        assert!(!point_in_polygon((-1.0, 5.0), &square));
    }
}
