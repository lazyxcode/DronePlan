// Copyright (c) 2026 acche. All rights reserved.
// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    droneplan_desktop_lib::run()
}
