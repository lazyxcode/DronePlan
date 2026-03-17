//! Copyright (c) 2026 acche. All rights reserved.
//! Tauri backend for DronePlan desktop application

use droneplan_core::{FlightPlan, Waypoint, WaypointAction, KmzGenerator};
use serde::{Deserialize, Serialize};
use std::path::Path;

#[cfg(target_os = "windows")]
use std::path::PathBuf;

#[cfg(target_os = "windows")]
const RC2_SYNC_SCRIPT: &str = include_str!("../windows/Sync-RC2Mission.ps1");

#[derive(Debug, Deserialize)]
struct WaypointInput {
    latitude: f64,
    longitude: f64,
    altitude: f64,
    speed: f64,
    #[serde(alias = "holdTime")]
    hold_time: f64,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct BuildInfo {
    app_version: String,
    build_rev: String,
    target_os: String,
}

fn build_flight_plan(
    name: &str,
    waypoints: Vec<WaypointInput>,
    cruise_speed: f64,
    camera_angle: f64,
) -> FlightPlan {
    let mut plan = FlightPlan::new(name);
    plan.set_cruise_speed(cruise_speed);
    plan.set_camera_angle(camera_angle);

    for wp_input in waypoints {
        let wp = Waypoint::new(wp_input.latitude, wp_input.longitude, wp_input.altitude)
            .with_speed(wp_input.speed)
            .with_hold_time(wp_input.hold_time)
            .with_action(WaypointAction::TakePhoto);
        plan.add_waypoint(wp);
    }

    plan
}

fn generate_kmz_bytes(
    name: &str,
    waypoints: Vec<WaypointInput>,
    cruise_speed: f64,
    camera_angle: f64,
) -> Result<(FlightPlan, Vec<u8>), String> {
    let plan = build_flight_plan(name, waypoints, cruise_speed, camera_angle);
    let kmz_bytes = KmzGenerator::generate(&plan)
        .map_err(|e| format!("生成 KMZ 失败: {}", e))?;

    Ok((plan, kmz_bytes))
}

fn ensure_parent_dir(path: &Path) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)
            .map_err(|e| format!("创建目录失败: {}", e))?;
    }
    Ok(())
}

#[tauri::command]
fn build_info() -> BuildInfo {
    BuildInfo {
        app_version: env!("CARGO_PKG_VERSION").to_string(),
        build_rev: option_env!("DRONEPLAN_BUILD_REV").unwrap_or("unknown").to_string(),
        target_os: std::env::consts::OS.to_string(),
    }
}

/// Generate KMZ file and save to user-selected location
#[tauri::command]
async fn generate_kmz(
    app: tauri::AppHandle,
    name: String,
    waypoints: Vec<WaypointInput>,
    cruise_speed: f64,
    camera_angle: f64,
) -> Result<String, String> {
    let (plan, kmz_bytes) = generate_kmz_bytes(&name, waypoints, cruise_speed, camera_angle)?;

    // Get default filename
    let filename = KmzGenerator::default_filename(&plan);

    // Use dialog to pick save location
    use tauri_plugin_dialog::DialogExt;
    
    let file_path = app
        .dialog()
        .file()
        .set_file_name(&filename)
        .add_filter("KMZ Files", &["kmz"])
        .blocking_save_file();

    match file_path {
        Some(file_path) => {
            // Convert FilePath to PathBuf
            let path = file_path.as_path().ok_or("路径转换失败")?;
            ensure_parent_dir(path)?;
            std::fs::write(&path, kmz_bytes)
                .map_err(|e| format!("保存文件失败: {}", e))?;
            Ok(file_path.to_string())
        }
        None => Err("已取消保存".to_string()),
    }
}

/// Replace an existing RC 2 placeholder mission KMZ selected by the user.
#[tauri::command]
async fn replace_placeholder_kmz(
    app: tauri::AppHandle,
    name: String,
    waypoints: Vec<WaypointInput>,
    cruise_speed: f64,
    camera_angle: f64,
) -> Result<String, String> {
    let (_plan, kmz_bytes) = generate_kmz_bytes(&name, waypoints, cruise_speed, camera_angle)?;

    use tauri_plugin_dialog::DialogExt;

    let target = app
        .dialog()
        .file()
        .add_filter("KMZ Files", &["kmz"])
        .set_title("选择 RC 2 或 microSD 上的占位任务 KMZ")
        .blocking_pick_file();

    match target {
        Some(file_path) => {
            let path = file_path.as_path().ok_or("路径转换失败")?;

            if path.extension().and_then(|ext| ext.to_str()) != Some("kmz") {
                return Err("请选择一个现有的 .kmz 占位任务文件".to_string());
            }

            std::fs::write(path, kmz_bytes)
                .map_err(|e| format!("覆盖占位任务失败: {}", e))?;

            Ok(format!("已替换占位任务: {}", path.display()))
        }
        None => Err("已取消选择".to_string()),
    }
}

#[tauri::command]
async fn sync_to_rc2(
    name: String,
    waypoints: Vec<WaypointInput>,
    cruise_speed: f64,
    camera_angle: f64,
) -> Result<String, String> {
    #[cfg(not(target_os = "windows"))]
    {
        let _ = (name, waypoints, cruise_speed, camera_angle);
        return Err("同步到 RC 2 仅支持 Windows 桌面端".to_string());
    }

    #[cfg(target_os = "windows")]
    {
        let (plan, kmz_bytes) = generate_kmz_bytes(&name, waypoints, cruise_speed, camera_angle)?;
        let temp_root = std::env::temp_dir().join("DronePlan").join("rc2-sync");
        std::fs::create_dir_all(&temp_root)
            .map_err(|e| format!("创建临时目录失败: {}", e))?;

        let kmz_path = temp_root.join(KmzGenerator::default_filename(&plan));
        std::fs::write(&kmz_path, kmz_bytes)
            .map_err(|e| format!("写入临时 KMZ 失败: {}", e))?;

        let script_path = write_sync_script(&temp_root)?;
        run_sync_script(&script_path, &kmz_path)
    }
}

#[cfg(target_os = "windows")]
fn write_sync_script(temp_root: &Path) -> Result<PathBuf, String> {
    let script_path = temp_root.join("Sync-RC2Mission.ps1");
    std::fs::write(&script_path, RC2_SYNC_SCRIPT)
        .map_err(|e| format!("写入同步脚本失败: {}", e))?;
    Ok(script_path)
}

#[cfg(target_os = "windows")]
fn run_sync_script(script_path: &Path, kmz_path: &Path) -> Result<String, String> {
    let output = std::process::Command::new("powershell.exe")
        .args([
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
        ])
        .arg(script_path)
        .args(["-SourceKmz"])
        .arg(kmz_path)
        .output()
        .map_err(|e| format!("启动 Windows 同步脚本失败: {}", e))?;

    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();

    if output.status.success() {
        if stdout.is_empty() {
            Ok("已完成 RC 2 同步".to_string())
        } else {
            Ok(stdout)
        }
    } else if !stderr.is_empty() {
        Err(format!("RC 2 同步失败: {}", stderr))
    } else if !stdout.is_empty() {
        Err(format!("RC 2 同步失败: {}", stdout))
    } else {
        Err("RC 2 同步失败，脚本没有返回可读信息".to_string())
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![
            build_info,
            generate_kmz,
            replace_placeholder_kmz,
            sync_to_rc2
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
