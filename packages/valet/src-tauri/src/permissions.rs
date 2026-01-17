use serde::{Deserialize, Serialize};
use std::process::Command;

#[derive(Debug, Serialize, Deserialize)]
pub struct PermissionStatus {
    pub microphone: bool,
    #[serde(rename = "fullDiskAccess")]
    pub full_disk_access: bool,
    pub accessibility: bool,
}

/// Check the status of all required permissions
#[tauri::command]
pub fn check_permissions_command() -> Result<PermissionStatus, String> {
    Ok(PermissionStatus {
        microphone: check_microphone_permission(),
        full_disk_access: check_full_disk_access(),
        accessibility: check_accessibility_permission(),
    })
}

/// Request microphone permission (will trigger system prompt)
#[tauri::command]
pub fn request_microphone_permission_command() -> Result<(), String> {
    // On macOS, microphone permission is requested automatically when the app tries to access the microphone
    // The frontend will handle this through the browser's getUserMedia API
    // This command is a no-op on the Rust side
    Ok(())
}

/// Open System Preferences to a specific privacy pane
#[tauri::command]
pub fn open_system_preferences_command(pane: String) -> Result<(), String> {
    let url = match pane.as_str() {
        "privacy_microphone" => "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
        "privacy_full_disk_access" => "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
        "privacy_accessibility" => "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        _ => return Err(format!("Unknown preference pane: {}", pane)),
    };

    #[cfg(target_os = "macos")]
    {
        Command::new("open")
            .arg(url)
            .spawn()
            .map_err(|e| format!("Failed to open System Preferences: {}", e))?;
    }

    Ok(())
}

/// Check if microphone permission is granted
fn check_microphone_permission() -> bool {
    #[cfg(target_os = "macos")]
    {
        // On macOS 10.14+, we need to check AVCaptureDevice authorization status
        // For now, we'll use a heuristic approach via tccutil
        let output = Command::new("sqlite3")
            .arg(format!("{}/Library/Application Support/com.apple.TCC/TCC.db", std::env::var("HOME").unwrap_or_default()))
            .arg("SELECT allowed FROM access WHERE service='kTCCServiceMicrophone' AND client='com.valet.mac';")
            .output();

        if let Ok(output) = output {
            let result = String::from_utf8_lossy(&output.stdout);
            return result.trim() == "1";
        }
    }

    // Default to false if we can't check
    false
}

/// Check if Full Disk Access is granted
fn check_full_disk_access() -> bool {
    #[cfg(target_os = "macos")]
    {
        // Try multiple protected files that require Full Disk Access
        // This avoids relying on Safari-specific files
        let home = std::env::var("HOME").unwrap_or_default();
        let test_paths = vec![
            format!("{}/Library/Safari/History.db", home),
            format!("{}/Library/Mail", home),
            format!("{}/Library/Messages", home),
        ];

        // If any of these protected paths can be accessed, Full Disk Access is granted
        test_paths.iter().any(|path| std::fs::metadata(path).is_ok())
    }

    #[cfg(not(target_os = "macos"))]
    {
        true // Not applicable on other platforms
    }
}

/// Check if Accessibility permission is granted
fn check_accessibility_permission() -> bool {
    #[cfg(target_os = "macos")]
    {
        // Use AXIsProcessTrusted API to check accessibility permission
        // For now, we'll use a simpler heuristic
        let output = Command::new("sqlite3")
            .arg(format!("{}/Library/Application Support/com.apple.TCC/TCC.db", std::env::var("HOME").unwrap_or_default()))
            .arg("SELECT allowed FROM access WHERE service='kTCCServiceAccessibility' AND client='com.valet.mac';")
            .output();

        if let Ok(output) = output {
            let result = String::from_utf8_lossy(&output.stdout);
            return result.trim() == "1";
        }
    }

    // Default to false if we can't check
    false
}
