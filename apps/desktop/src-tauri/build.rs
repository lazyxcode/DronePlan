use std::process::Command;

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-env-changed=DRONEPLAN_BUILD_REV");

    if let Ok(output) = Command::new("git").args(["rev-parse", "--short", "HEAD"]).output() {
        if output.status.success() {
            let revision = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if !revision.is_empty() {
                println!("cargo:rustc-env=DRONEPLAN_BUILD_REV={revision}");
            }
        }
    }

    tauri_build::build()
}
