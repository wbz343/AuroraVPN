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
        return Ok("Core engine is already running.".to_string());
    }

    println!("[Backend] Starting core engine from: {:?}", core_exe);

    // 启动 mihomo 核心
    // 注意: mihomo 启动需要配置文件。这里假设你在 resource_dir 下放了一个基础的 config.yaml
    // 实际生产中，你可能需要先由 Rust 动态生成 config.yaml 到 app_data_dir，然后传给它
    let mut child = Command::new(&core_exe)
        .arg("-d") // 指定配置目录
        .arg(resource_dir.to_str().unwrap()) 
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .map_err(|e| format!("Failed to start core engine: {}", e))?;

    *core_proc_guard = Some(child);
    let core_pid = core_proc_guard.as_ref().unwrap().id();

    // 2. 如果选择了 Tor 协议，额外启动 Snowflake 传输层
    let mut transport_pid: Option<u32> = None;
    if protocol == "tor" {
        let snowflake_exe = resource_dir.join("snowflake.exe");
        if snowflake_exe.exists() {
            println!("[Backend] Starting Snowflake transport...");
            let mut transport_proc_guard = state.transport_process.lock().unwrap();
            
            let mut transport_child = Command::new(&snowflake_exe)
                // 根据 snowflake 的实际 CLI 参数调整，例如指定 broker 或日志级别
                .arg("-logLevel=info") 
                .stdout(std::process::Stdio::piped())
                .stderr(std::process::Stdio::piped())
                .spawn()
                .map_err(|e| format!("Failed to start snowflake: {}", e))?;
                
            transport_pid = Some(transport_child.id());
            *transport_proc_guard = Some(transport_child);
        } else {
            return Err("Snowflake executable not found, cannot use Tor protocol.".to_string());
        }
    }

    Ok(format!(
        "Connected via {}. Core PID: {}, Transport PID: {:?}",
        protocol, core_pid, transport_pid
    ))
}

#[tauri::command]
fn disconnect_vpn(state: tauri::State<VpnState>) -> Result<String, String> {
    println!("[Backend] Disconnecting VPN and cleaning up resources...");

    // 1. 终止传输层进程 (如 Snowflake)
    if let Some(mut child) = state.transport_process.lock().unwrap().take() {
        println!("[Backend] Terminating transport process (PID: {})", child.id());
        let _ = child.kill();
        let _ = child.wait(); // 等待进程完全退出，清理系统资源
    }

    // 2. 终止核心代理进程
    if let Some(mut child) = state.core_process.lock().unwrap().take() {
        println!("[Backend] Terminating core process (PID: {})", child.id());
        let _ = child.kill();
        let _ = child.wait();
    }

    // 3. (可选) 在这里添加清理 TUN 接口或重置系统代理的逻辑
    
    Ok("Disconnected and cleaned up successfully.".to_string())
}

// ==========================================
// 3. 主函数入口
// ==========================================
fn main() {
    tauri::Builder::default()
        // 注册全局状态，供所有 commands 共享和修改
        .manage(VpnState::default())
        // 注册前端可调用的命令
        .invoke_handler(tauri::generate_handler![connect_vpn, disconnect_vpn])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
