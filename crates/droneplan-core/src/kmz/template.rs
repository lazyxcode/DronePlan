//! Copyright (c) 2026 acche. All rights reserved.
//! Template KML generation
//!
//! Generates the template.kml file for business attributes and route display.

use crate::models::FlightPlan;

/// Generate the template.kml XML content
pub fn generate_template_kml(plan: &FlightPlan) -> String {
    let template_id = plan.id.to_string().replace('-', "")[..8].to_uppercase();
    let mut xml = String::new();
    
    xml.push_str(r#"<?xml version="1.0" encoding="UTF-8"?>"#);
    xml.push('\n');
    xml.push_str(r#"<kml xmlns="http://www.opengis.net/kml/2.2" xmlns:wpml="http://www.dji.com/wpmz/1.0.6">"#);
    xml.push('\n');
    
    xml.push_str("  <Document>\n");
    
    // Author info
    xml.push_str("    <wpml:author>DronePlan</wpml:author>\n");
    xml.push_str(&format!(
        "    <wpml:createTime>{}</wpml:createTime>\n",
        plan.created_at.format("%Y-%m-%dT%H:%M:%S%.3fZ")
    ));
    xml.push_str(&format!(
        "    <wpml:updateTime>{}</wpml:updateTime>\n",
        plan.updated_at.format("%Y-%m-%dT%H:%M:%S%.3fZ")
    ));
    
    // Mission config (same as wpml)
    xml.push_str("    <wpml:missionConfig>\n");
    xml.push_str("      <wpml:flyToWaylineMode>safely</wpml:flyToWaylineMode>\n");
    xml.push_str("      <wpml:finishAction>goHome</wpml:finishAction>\n");
    xml.push_str("      <wpml:exitOnRCLost>executeLostAction</wpml:exitOnRCLost>\n");
    xml.push_str("      <wpml:executeRCLostAction>goBack</wpml:executeRCLostAction>\n");
    xml.push_str(&format!(
        "      <wpml:globalTransitionalSpeed>{:.1}</wpml:globalTransitionalSpeed>\n",
        plan.cruise_speed
    ));
    xml.push_str("      <wpml:droneInfo>\n");
    xml.push_str("        <wpml:droneEnumValue>89</wpml:droneEnumValue>\n");
    xml.push_str("        <wpml:droneSubEnumValue>0</wpml:droneSubEnumValue>\n");
    xml.push_str("      </wpml:droneInfo>\n");
    xml.push_str("      <wpml:payloadInfo>\n");
    xml.push_str("        <wpml:payloadEnumValue>66</wpml:payloadEnumValue>\n");
    xml.push_str("        <wpml:payloadSubEnumValue>0</wpml:payloadSubEnumValue>\n");
    xml.push_str("        <wpml:payloadPositionIndex>0</wpml:payloadPositionIndex>\n");
    xml.push_str("      </wpml:payloadInfo>\n");
    xml.push_str("    </wpml:missionConfig>\n");
    
    // Folder with template info
    xml.push_str("    <Folder>\n");
    xml.push_str(&format!(
        "      <wpml:templateId>{}</wpml:templateId>\n",
        template_id
    ));
    xml.push_str("      <wpml:templateType>waypoint</wpml:templateType>\n");
    xml.push_str(&format!(
        "      <wpml:waylineCoordinateSysParam>\n        <wpml:coordinateMode>WGS84</wpml:coordinateMode>\n        <wpml:heightMode>relativeToStartPoint</wpml:heightMode>\n      </wpml:waylineCoordinateSysParam>\n"
    ));
    xml.push_str(&format!(
        "      <wpml:autoFlightSpeed>{:.1}</wpml:autoFlightSpeed>\n",
        plan.cruise_speed
    ));
    xml.push_str("      <wpml:globalWaypointHeadingParam>\n");
    xml.push_str("        <wpml:waypointHeadingMode>followWayline</wpml:waypointHeadingMode>\n");
    xml.push_str("      </wpml:globalWaypointHeadingParam>\n");
    xml.push_str("      <wpml:globalWaypointTurnMode>toPointAndStopWithDiscontinuityCurvature</wpml:globalWaypointTurnMode>\n");
    xml.push_str("      <wpml:globalUseStraightLine>1</wpml:globalUseStraightLine>\n");
    
    // Placemarks for display
    for (index, waypoint) in plan.waypoints.iter().enumerate() {
        xml.push_str("      <Placemark>\n");
        xml.push_str("        <Point>\n");
        xml.push_str(&format!(
            "          <coordinates>{:.8},{:.8}</coordinates>\n",
            waypoint.longitude, waypoint.latitude
        ));
        xml.push_str("        </Point>\n");
        xml.push_str(&format!("        <wpml:index>{}</wpml:index>\n", index));
        xml.push_str(&format!(
            "        <wpml:ellipsoidHeight>{:.1}</wpml:ellipsoidHeight>\n",
            waypoint.altitude
        ));
        xml.push_str(&format!(
            "        <wpml:height>{:.1}</wpml:height>\n",
            waypoint.altitude
        ));
        xml.push_str("        <wpml:useGlobalHeight>1</wpml:useGlobalHeight>\n");
        xml.push_str("        <wpml:useGlobalSpeed>1</wpml:useGlobalSpeed>\n");
        xml.push_str("        <wpml:useGlobalHeadingParam>1</wpml:useGlobalHeadingParam>\n");
        xml.push_str("        <wpml:useGlobalTurnParam>1</wpml:useGlobalTurnParam>\n");
        xml.push_str("      </Placemark>\n");
    }
    
    xml.push_str("    </Folder>\n");
    xml.push_str("  </Document>\n");
    xml.push_str("</kml>\n");
    
    xml
}
