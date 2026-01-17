use serde::{Deserialize, Serialize};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tauri::{AppHandle, Emitter, Manager};
use tokio::sync::mpsc;
use tokio::time::interval;

/// Load monitoring settings from persisted settings
fn load_monitoring_settings() -> (bool, u64) {
    // Try to load from settings file
    if let Ok(settings) = crate::settings::load_settings() {
        let enabled = settings
            .get("monitoring_enabled")
            .and_then(|v| v.parse::<bool>().ok())
            .unwrap_or(true);

        let interval_minutes = settings
            .get("monitoring_interval_minutes")
            .and_then(|v| v.parse::<u64>().ok())
            .unwrap_or(30);

        (enabled, interval_minutes)
    } else {
        // Fall back to defaults if loading fails
        (true, 30)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MonitoringStatus {
    pub health: String,
    pub last_update: String,
    pub status_json: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MonitoringState {
    pub enabled: bool,
    pub interval_minutes: u64,
    pub last_status: Option<MonitoringStatus>,
    #[serde(skip)]
    pub config_tx: Option<mpsc::UnboundedSender<u64>>,
}

impl Default for MonitoringState {
    fn default() -> Self {
        Self {
            enabled: true,
            interval_minutes: 30,
            last_status: None,
            config_tx: None,
        }
    }
}

/// Start the background monitoring loop
pub fn start_monitoring(app: AppHandle) {
    // Load persisted settings
    let (initial_enabled, initial_interval) = load_monitoring_settings();

    let mut initial_state = MonitoringState::default();
    initial_state.enabled = initial_enabled;
    initial_state.interval_minutes = initial_interval;

    let state = Arc::new(Mutex::new(initial_state));

    // Create a channel for interval updates
    let (config_tx, mut config_rx) = mpsc::unbounded_channel::<u64>();

    // Store the sender in state
    {
        let mut state_guard = state.lock().unwrap();
        state_guard.config_tx = Some(config_tx);
    }

    // Store state in Tauri's state manager
    app.manage(state.clone());

    let app_clone = app.clone();

    tauri::async_runtime::spawn(async move {
        let mut current_interval = initial_interval;
        let mut ticker = interval(Duration::from_secs(current_interval * 60));

        loop {
            tokio::select! {
                // Handle interval updates
                Some(new_interval) = config_rx.recv() => {
                    if new_interval != current_interval {
                        current_interval = new_interval;
                        ticker = interval(Duration::from_secs(current_interval * 60));
                        log::info!("Monitoring interval updated to {} minutes", current_interval);
                    }
                }
                // Handle ticker ticks
                _ = ticker.tick() => {
                    let should_run = {
                        let state_guard = state.lock().unwrap();
                        state_guard.enabled
                    };

                    if should_run {
                        if let Err(e) = run_status_check(&app_clone, &state).await {
                            log::error!("Failed to run status check: {}", e);
                            let _ = app_clone.emit("monitoring:error", e);
                        }
                    }
                }
            }
        }
    });

    log::info!("Background monitoring started");
}

/// Run a single status check
async fn run_status_check(
    app: &AppHandle,
    state: &Arc<Mutex<MonitoringState>>,
) -> Result<(), String> {
    let mole_path = crate::mole::ensure_mole_installed(app)?;
    let workspace_path = crate::workspace::ensure_workspace(app)?;

    // Run mo status --json
    let output = tokio::process::Command::new(&mole_path)
        .arg("status")
        .arg("--json")
        .current_dir(&workspace_path)
        .output()
        .await
        .map_err(|e| format!("Failed to execute mo status: {}", e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("mo status failed: {}", stderr));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let status_json: serde_json::Value = serde_json::from_str(&stdout)
        .map_err(|e| format!("Failed to parse mo status output: {}", e))?;

    // Extract health status
    let health = status_json
        .get("health")
        .and_then(|v| v.as_str())
        .unwrap_or("unknown")
        .to_string();

    let monitoring_status = MonitoringStatus {
        health: health.clone(),
        last_update: chrono::Utc::now().to_rfc3339(),
        status_json: status_json.clone(),
    };

    // Update state
    {
        let mut state_guard = state.lock().unwrap();
        state_guard.last_status = Some(monitoring_status.clone());
    }

    // Emit event to frontend
    let _ = app.emit("monitoring:status", monitoring_status);

    log::info!("Status check completed, health: {}", health);

    Ok(())
}

/// Get the current cached status
#[tauri::command]
pub fn get_cached_status(app: AppHandle) -> Result<Option<MonitoringStatus>, String> {
    // Retrieve state from app state manager
    let state: tauri::State<Arc<Mutex<MonitoringState>>> = app.state();
    let state_guard = state.lock().unwrap();
    Ok(state_guard.last_status.clone())
}

/// Update monitoring configuration
#[tauri::command]
pub fn update_monitoring_config(
    app: AppHandle,
    enabled: bool,
    interval_minutes: u64,
) -> Result<(), String> {
    let state: tauri::State<Arc<Mutex<MonitoringState>>> = app.state();
    let mut state_guard = state.lock().unwrap();
    state_guard.enabled = enabled;

    // If interval changed, send update to the monitoring loop
    if state_guard.interval_minutes != interval_minutes {
        state_guard.interval_minutes = interval_minutes;
        if let Some(ref tx) = state_guard.config_tx {
            let _ = tx.send(interval_minutes);
        }
    }

    // Persist settings to disk
    drop(state_guard); // Release lock before calling settings
    crate::settings::set_setting_command("monitoring_enabled".to_string(), enabled.to_string())?;
    crate::settings::set_setting_command("monitoring_interval_minutes".to_string(), interval_minutes.to_string())?;

    Ok(())
}

/// Trigger an immediate status check
#[tauri::command]
pub async fn trigger_status_check(app: AppHandle) -> Result<MonitoringStatus, String> {
    let state: tauri::State<'_, Arc<Mutex<MonitoringState>>> = app.state();
    run_status_check(&app, &state).await?;

    let state_guard = state.lock().unwrap();
    state_guard
        .last_status
        .clone()
        .ok_or_else(|| "Status check completed but no status available".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_monitoring_state_default() {
        let state = MonitoringState::default();
        assert_eq!(state.enabled, true);
        assert_eq!(state.interval_minutes, 30);
        assert!(state.last_status.is_none());
        assert!(state.config_tx.is_none());
    }

    #[test]
    fn test_update_monitoring_config_updates_interval() {
        let state = Arc::new(Mutex::new(MonitoringState::default()));
        let (config_tx, mut config_rx) = mpsc::unbounded_channel::<u64>();

        // Set the config_tx in state
        {
            let mut state_guard = state.lock().unwrap();
            state_guard.config_tx = Some(config_tx);
        }

        // Simulate update_monitoring_config behavior
        {
            let mut state_guard = state.lock().unwrap();
            let new_interval = 15u64;

            // This mimics what update_monitoring_config does
            if state_guard.interval_minutes != new_interval {
                state_guard.interval_minutes = new_interval;
                if let Some(ref tx) = state_guard.config_tx {
                    let _ = tx.send(new_interval);
                }
            }
        }

        // Verify the interval was updated in state
        {
            let state_guard = state.lock().unwrap();
            assert_eq!(state_guard.interval_minutes, 15);
        }

        // Verify the message was sent to the channel
        let received = config_rx.try_recv();
        assert!(received.is_ok());
        assert_eq!(received.unwrap(), 15);
    }

    #[test]
    fn test_update_monitoring_config_no_send_if_same_interval() {
        let state = Arc::new(Mutex::new(MonitoringState::default()));
        let (config_tx, mut config_rx) = mpsc::unbounded_channel::<u64>();

        // Set the config_tx in state
        {
            let mut state_guard = state.lock().unwrap();
            state_guard.config_tx = Some(config_tx);
            state_guard.interval_minutes = 30; // Already at 30
        }

        // Try to update to the same interval
        {
            let mut state_guard = state.lock().unwrap();
            let new_interval = 30u64;

            if state_guard.interval_minutes != new_interval {
                state_guard.interval_minutes = new_interval;
                if let Some(ref tx) = state_guard.config_tx {
                    let _ = tx.send(new_interval);
                }
            }
        }

        // Verify no message was sent (because interval didn't change)
        let received = config_rx.try_recv();
        assert!(received.is_err()); // Should be empty
    }

    #[test]
    fn test_monitoring_state_enabled_toggle() {
        let state = Arc::new(Mutex::new(MonitoringState::default()));

        // Verify default is enabled
        {
            let state_guard = state.lock().unwrap();
            assert_eq!(state_guard.enabled, true);
        }

        // Toggle to disabled
        {
            let mut state_guard = state.lock().unwrap();
            state_guard.enabled = false;
        }

        // Verify it's disabled
        {
            let state_guard = state.lock().unwrap();
            assert_eq!(state_guard.enabled, false);
        }
    }
}
