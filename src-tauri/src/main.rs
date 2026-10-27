// 防止 Windows 控制台窗口弹出
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use serde_json::json;

// 模拟调用底层核心。实际项目中，这里应调用 native/aether 或加载 Go 编译的 DLL
#[tauri::command]
fn connect_vpn(protocol: String) -> Result<String, String> {
    println!("Backend: Connecting with protocol: {}", protocol);
    
    // 实际逻辑示例：
    // if protocol == "psiphon" {
    //     unsafe { call_go_psiphon_start() }
    // }
    
    Ok(format!("Successfully connected via {}", protocol))
}

#[tauri::command]
fn disconnect_vpn() -> Result<String, String> {
    println!("Backend: Disconnecting VPN...");
    // 实际逻辑：调用底层断开接口，清理 TUN 接口
    Ok("Disconnected".to_string())
}

fn main() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![connect_vpn, disconnect_vpn])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
