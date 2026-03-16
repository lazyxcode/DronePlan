//! Copyright (c) 2026 acche. All rights reserved.
//! WPML (Waypoint Markup Language) XML generation
//!
//! Generates the waylines.wpml file content for DJI drone missions.

use crate::models::{FlightPlan, HeightMode, FinishAction, WaypointAction};

/// WPML namespace
pub const WPML_NAMESPACE: &str = "http://www.dji.com/wpmz/1.0.6";

/// Generate the waylines.wpml XML content
pub fn generate_wpml(plan: &FlightPlan) -> String {
    let mut xml = String::new();
    
    xml.push_str(r#"<?xml version="1.0" encoding="UTF-8"?>"#);
    xml.push('\n');
    xml.push_str(&format!(
        r#"<kml xmlns="http://www.opengis.net/kml/2.2" xmlns:wpml="{}">"#,
        WPML_NAMESPACE
    ));
    xml.push('\n');
    
    // Document
    xml.push_str("  <Document>\n");
    
    // Mission config
    xml.push_str(&generate_mission_config(plan));
    
    // Waylines folder
    xml.push_str(&generate_waylines_folder(plan));
    
    xml.push_str("  </Document>\n");
    xml.push_str("</kml>\n");
    
    xml
}

fn generate_mission_config(plan: &FlightPlan) -> String {
    let finish_action_str = match plan.finish_action {
        FinishAction::GoHome => "goHome",
        FinishAction::AutoLand => "autoLand",
        FinishAction::Hover => "hover",
        FinishAction::NoAction => "noAction",
    };

    format!(
        r#"    <wpml:missionConfig>
      <wpml:flyToWaylineMode>safely</wpml:flyToWaylineMode>
      <wpml:finishAction>{finish_action}</wpml:finishAction>
      <wpml:exitOnRCLost>executeLostAction</wpml:exitOnRCLost>
      <wpml:executeRCLostAction>goBack</wpml:executeRCLostAction>
      <wpml:globalTransitionalSpeed>{speed:.1}</wpml:globalTransitionalSpeed>
      <wpml:droneInfo>
        <wpml:droneEnumValue>89</wpml:droneEnumValue>
        <wpml:droneSubEnumValue>0</wpml:droneSubEnumValue>
      </wpml:droneInfo>
      <wpml:payloadInfo>
        <wpml:payloadEnumValue>66</wpml:payloadEnumValue>
        <wpml:payloadSubEnumValue>0</wpml:payloadSubEnumValue>
        <wpml:payloadPositionIndex>0</wpml:payloadPositionIndex>
      </wpml:payloadInfo>
    </wpml:missionConfig>
"#,
        finish_action = finish_action_str,
        speed = plan.cruise_speed,
    )
}

fn generate_waylines_folder(plan: &FlightPlan) -> String {
    let mut folder = String::new();
    let execute_height_mode = match plan.height_mode {
        HeightMode::RelativeToTakeoff => "relativeToStartPoint",
        HeightMode::WGS84 => "WGS84",
        HeightMode::TerrainFollow => "realTimeFollowSurface",
    };
    
    folder.push_str("    <Folder>\n");
    folder.push_str(&format!(
        "      <wpml:templateId>{}</wpml:templateId>\n",
        plan.id.to_string().replace('-', "")[..8].to_uppercase()
    ));
    folder.push_str(&format!(
        "      <wpml:executeHeightMode>{}</wpml:executeHeightMode>\n",
        execute_height_mode
    ));
    folder.push_str(&format!(
        "      <wpml:waylineId>{}</wpml:waylineId>\n",
        1
    ));
    folder.push_str("      <wpml:distance>0</wpml:distance>\n");
    folder.push_str("      <wpml:duration>0</wpml:duration>\n");
    folder.push_str(&format!(
        "      <wpml:autoFlightSpeed>{:.1}</wpml:autoFlightSpeed>\n",
        plan.cruise_speed
    ));
    
    // Generate placemarks for each waypoint
    for (index, waypoint) in plan.waypoints.iter().enumerate() {
        folder.push_str(&generate_placemark(waypoint, index, plan));
    }
    
    folder.push_str("    </Folder>\n");
    
    folder
}

fn generate_placemark(
    waypoint: &crate::models::Waypoint,
    index: usize,
    plan: &FlightPlan,
) -> String {
    let mut pm = String::new();
    
    pm.push_str("      <Placemark>\n");
    pm.push_str(&format!("        <Point>\n"));
    pm.push_str(&format!(
        "          <coordinates>{:.8},{:.8}</coordinates>\n",
        waypoint.longitude, waypoint.latitude
    ));
    pm.push_str("        </Point>\n");
    
    pm.push_str(&format!(
        "        <wpml:index>{}</wpml:index>\n",
        index
    ));
    pm.push_str(&format!(
        "        <wpml:executeHeight>{:.1}</wpml:executeHeight>\n",
        waypoint.altitude
    ));
    pm.push_str(&format!(
        "        <wpml:waypointSpeed>{:.1}</wpml:waypointSpeed>\n",
        waypoint.speed
    ));
    
    // Heading mode
    if let Some(heading) = waypoint.heading {
        pm.push_str("        <wpml:waypointHeadingParam>\n");
        pm.push_str("          <wpml:waypointHeadingMode>toPointAndStopRotate</wpml:waypointHeadingMode>\n");
        pm.push_str(&format!(
            "          <wpml:waypointHeadingAngle>{:.1}</wpml:waypointHeadingAngle>\n",
            heading
        ));
        pm.push_str("        </wpml:waypointHeadingParam>\n");
    } else {
        pm.push_str("        <wpml:waypointHeadingParam>\n");
        pm.push_str("          <wpml:waypointHeadingMode>followWayline</wpml:waypointHeadingMode>\n");
        pm.push_str("        </wpml:waypointHeadingParam>\n");
    }
    
    // Turn mode
    pm.push_str("        <wpml:waypointTurnParam>\n");
    pm.push_str("          <wpml:waypointTurnMode>toPointAndStopWithDiscontinuityCurvature</wpml:waypointTurnMode>\n");
    pm.push_str(&format!(
        "          <wpml:waypointTurnDampingDist>{:.1}</wpml:waypointTurnDampingDist>\n",
        0.2
    ));
    pm.push_str("        </wpml:waypointTurnParam>\n");
    
    // Gimbal pitch
    let gimbal_pitch = waypoint.gimbal_pitch.unwrap_or(plan.camera_angle);
    pm.push_str("        <wpml:waypointGimbalHeadingParam>\n");
    pm.push_str(&format!(
        "          <wpml:waypointGimbalPitchAngle>{:.1}</wpml:waypointGimbalPitchAngle>\n",
        gimbal_pitch
    ));
    pm.push_str("          <wpml:waypointGimbalYawAngle>0</wpml:waypointGimbalYawAngle>\n");
    pm.push_str("        </wpml:waypointGimbalHeadingParam>\n");
    
    // Actions
    if !waypoint.actions.is_empty() || waypoint.hold_time > 0.0 {
        pm.push_str(&generate_actions(&waypoint.actions, waypoint.hold_time));
    }
    
    pm.push_str("      </Placemark>\n");
    
    pm
}

fn generate_actions(actions: &[WaypointAction], hold_time: f64) -> String {
    let mut action_xml = String::new();
    let mut action_id = 0;
    
    action_xml.push_str("        <wpml:actionGroup>\n");
    action_xml.push_str("          <wpml:actionGroupId>0</wpml:actionGroupId>\n");
    action_xml.push_str("          <wpml:actionGroupStartIndex>0</wpml:actionGroupStartIndex>\n");
    action_xml.push_str("          <wpml:actionGroupEndIndex>0</wpml:actionGroupEndIndex>\n");
    action_xml.push_str("          <wpml:actionGroupMode>sequence</wpml:actionGroupMode>\n");
    action_xml.push_str("          <wpml:actionTrigger>\n");
    action_xml.push_str("            <wpml:actionTriggerType>reachPoint</wpml:actionTriggerType>\n");
    action_xml.push_str("          </wpml:actionTrigger>\n");
    
    // Add hover action if hold_time > 0
    if hold_time > 0.0 {
        action_xml.push_str(&format!(
            r#"          <wpml:action>
            <wpml:actionId>{}</wpml:actionId>
            <wpml:actionActuatorFunc>hover</wpml:actionActuatorFunc>
            <wpml:actionActuatorFuncParam>
              <wpml:hoverTime>{:.0}</wpml:hoverTime>
            </wpml:actionActuatorFuncParam>
          </wpml:action>
"#,
            action_id, hold_time
        ));
        action_id += 1;
    }
    
    // Add other actions
    for action in actions {
        match action {
            WaypointAction::TakePhoto => {
                action_xml.push_str(&format!(
                    r#"          <wpml:action>
            <wpml:actionId>{}</wpml:actionId>
            <wpml:actionActuatorFunc>takePhoto</wpml:actionActuatorFunc>
            <wpml:actionActuatorFuncParam>
              <wpml:payloadPositionIndex>0</wpml:payloadPositionIndex>
            </wpml:actionActuatorFuncParam>
          </wpml:action>
"#,
                    action_id
                ));
                action_id += 1;
            }
            WaypointAction::StartRecording => {
                action_xml.push_str(&format!(
                    r#"          <wpml:action>
            <wpml:actionId>{}</wpml:actionId>
            <wpml:actionActuatorFunc>startRecord</wpml:actionActuatorFunc>
            <wpml:actionActuatorFuncParam>
              <wpml:payloadPositionIndex>0</wpml:payloadPositionIndex>
            </wpml:actionActuatorFuncParam>
          </wpml:action>
"#,
                    action_id
                ));
                action_id += 1;
            }
            WaypointAction::StopRecording => {
                action_xml.push_str(&format!(
                    r#"          <wpml:action>
            <wpml:actionId>{}</wpml:actionId>
            <wpml:actionActuatorFunc>stopRecord</wpml:actionActuatorFunc>
            <wpml:actionActuatorFuncParam>
              <wpml:payloadPositionIndex>0</wpml:payloadPositionIndex>
            </wpml:actionActuatorFuncParam>
          </wpml:action>
"#,
                    action_id
                ));
                action_id += 1;
            }
            WaypointAction::RotateAircraft(heading) => {
                action_xml.push_str(&format!(
                    r#"          <wpml:action>
            <wpml:actionId>{}</wpml:actionId>
            <wpml:actionActuatorFunc>rotateYaw</wpml:actionActuatorFunc>
            <wpml:actionActuatorFuncParam>
              <wpml:aircraftHeading>{:.1}</wpml:aircraftHeading>
              <wpml:aircraftPathMode>counterClockwise</wpml:aircraftPathMode>
            </wpml:actionActuatorFuncParam>
          </wpml:action>
"#,
                    action_id, heading
                ));
                action_id += 1;
            }
            WaypointAction::SetGimbalPitch(pitch) => {
                action_xml.push_str(&format!(
                    r#"          <wpml:action>
            <wpml:actionId>{}</wpml:actionId>
            <wpml:actionActuatorFunc>gimbalRotate</wpml:actionActuatorFunc>
            <wpml:actionActuatorFuncParam>
              <wpml:gimbalRotateMode>absoluteAngle</wpml:gimbalRotateMode>
              <wpml:gimbalPitchRotateAngle>{:.1}</wpml:gimbalPitchRotateAngle>
              <wpml:gimbalRollRotateAngle>0</wpml:gimbalRollRotateAngle>
              <wpml:gimbalYawRotateAngle>0</wpml:gimbalYawRotateAngle>
              <wpml:gimbalRotateTimeEnable>0</wpml:gimbalRotateTimeEnable>
              <wpml:payloadPositionIndex>0</wpml:payloadPositionIndex>
            </wpml:actionActuatorFuncParam>
          </wpml:action>
"#,
                    action_id, pitch
                ));
                action_id += 1;
            }
            WaypointAction::Hover(duration) => {
                action_xml.push_str(&format!(
                    r#"          <wpml:action>
            <wpml:actionId>{}</wpml:actionId>
            <wpml:actionActuatorFunc>hover</wpml:actionActuatorFunc>
            <wpml:actionActuatorFuncParam>
              <wpml:hoverTime>{:.0}</wpml:hoverTime>
            </wpml:actionActuatorFuncParam>
          </wpml:action>
"#,
                    action_id, duration
                ));
                action_id += 1;
            }
        }
    }
    
    action_xml.push_str("        </wpml:actionGroup>\n");
    
    action_xml
}
