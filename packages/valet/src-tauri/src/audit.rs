use serde::{Deserialize, Serialize};
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::PathBuf;
use tauri::AppHandle;

/// Audit event types
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum AuditEventType {
    CommandApproved,
    CommandRejected,
    CommandExecuted,
}

/// Audit event structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditEvent {
    #[serde(rename = "type")]
    pub event_type: String,
    pub command: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", rename = "exitCode")]
    pub exit_code: Option<i32>,
    pub timestamp: String,
}

/// Get the path to the audit log file
pub fn get_audit_log_path() -> Result<PathBuf, String> {
    let home_dir = dirs::home_dir()
        .ok_or_else(|| "Failed to get home directory".to_string())?;

    let valet_dir = home_dir.join("Library/Application Support/Valet");

    // Ensure the Valet directory exists
    fs::create_dir_all(&valet_dir)
        .map_err(|e| format!("Failed to create Valet directory: {}", e))?;

    Ok(valet_dir.join("audit.log"))
}

/// Write an audit event to the log file
pub fn write_audit_event(event: &AuditEvent) -> Result<(), String> {
    let log_path = get_audit_log_path()?;

    // Serialize event to JSON
    let json = serde_json::to_string(event)
        .map_err(|e| format!("Failed to serialize audit event: {}", e))?;

    // Open log file in append mode
    let mut file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(&log_path)
        .map_err(|e| format!("Failed to open audit log file: {}", e))?;

    // Write event as a single line
    writeln!(file, "{}", json)
        .map_err(|e| format!("Failed to write to audit log: {}", e))?;

    log::info!("Audit event logged: {}", event.event_type);

    Ok(())
}

/// Tauri command to log an audit event from the frontend
#[tauri::command]
pub fn log_audit_event(event: AuditEvent) -> Result<(), String> {
    write_audit_event(&event)
}

/// Read recent audit events from the log file
/// Returns the last `limit` events (default: 100)
pub fn read_audit_events(limit: Option<usize>) -> Result<Vec<AuditEvent>, String> {
    let log_path = get_audit_log_path()?;

    // If the log file doesn't exist, return empty vector
    if !log_path.exists() {
        return Ok(Vec::new());
    }

    // Read the log file
    let contents = fs::read_to_string(&log_path)
        .map_err(|e| format!("Failed to read audit log: {}", e))?;

    // Parse each line as a JSON event
    let mut events = Vec::new();
    for line in contents.lines() {
        if line.trim().is_empty() {
            continue;
        }

        match serde_json::from_str::<AuditEvent>(line) {
            Ok(event) => events.push(event),
            Err(e) => {
                log::warn!("Failed to parse audit log line: {}", e);
                continue;
            }
        }
    }

    // Return the last `limit` events
    let limit = limit.unwrap_or(100);
    let start = events.len().saturating_sub(limit);
    Ok(events[start..].to_vec())
}

/// Tauri command to get recent audit events
#[tauri::command]
pub fn get_audit_events(limit: Option<usize>) -> Result<Vec<AuditEvent>, String> {
    read_audit_events(limit)
}

/// Clear the audit log file
pub fn clear_audit_log() -> Result<(), String> {
    let log_path = get_audit_log_path()?;

    if log_path.exists() {
        fs::remove_file(&log_path)
            .map_err(|e| format!("Failed to clear audit log: {}", e))?;
    }

    Ok(())
}

/// Tauri command to clear the audit log
#[tauri::command]
pub fn clear_audit_log_command() -> Result<(), String> {
    clear_audit_log()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_audit_event_serialization() {
        let event = AuditEvent {
            event_type: "command_approved".to_string(),
            command: "mo status".to_string(),
            reason: None,
            exit_code: None,
            timestamp: "2024-01-01T00:00:00Z".to_string(),
        };

        let json = serde_json::to_string(&event).unwrap();
        let parsed: AuditEvent = serde_json::from_str(&json).unwrap();

        assert_eq!(parsed.event_type, event.event_type);
        assert_eq!(parsed.command, event.command);
    }

    #[test]
    fn test_audit_event_with_exit_code() {
        let event = AuditEvent {
            event_type: "command_executed".to_string(),
            command: "mo clean".to_string(),
            reason: None,
            exit_code: Some(0),
            timestamp: "2024-01-01T00:00:00Z".to_string(),
        };

        let json = serde_json::to_string(&event).unwrap();
        assert!(json.contains("exitCode"));
    }
}
