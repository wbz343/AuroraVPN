// 防止 Windows 控制台窗口弹出
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::process::{Child, Command};
use std::sync::{Arc, Mutex};
use tauri::Manager;

// ==========================================
// 1. 全局状态管理
// ==========================================
// 用于跟踪当前正在运行的 VPN 核心进程和传输层进程，防止重复启动和资源泄漏
#[derive(Default)]
struct VpnState {
    core_process: Arc<Mutex<Option<Child>>>,
    transport_process: Arc<Mutex<Option<Child>>>,
}

// ==========================================
// 2. Tauri Commands (前端可调用的后端函数)
// ==========================================

#[tauri::command]
fn connect_vpn(
    protocol: String,
    app_handle: tauri::AppHandle,
    state: tauri::State<VpnState>,
) -> Result<String, String> {
    println!("[Backend] Connecting with protocol: {}", protocol);

    // 获取打包后的 resources 目录绝对路径
    let resource_dir = app_handle
        .path()
        .resource_dir()
        .map_err(|e| format!("Failed to get resource directory: {}", e))?;

    // 1. 启动核心代理引擎 (mihomo / auroravpn-core)
    let core_exe = resource_dir.join("auroravpn-core.exe");
    if !core_exe.exists() {
        return Err(format!("Core executable not found at: {:?}", core_exe));
    }

    // 检查是否已经在运行
    let mut core_proc_guard = state.core_process.lock().unwrap();
    if core_proc_guard.is_some() {
        return Ok("Core engine is already running.".
