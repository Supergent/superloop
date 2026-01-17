use serde_json::Value;
use std::collections::HashMap;
use std::fs::{self, File};
use std::io::{Read, Write};
use std::path::PathBuf;
use std::sync::Mutex;

/// Lazy static settings store
static SETTINGS: Mutex<Option<HashMap<String, String>>> = Mutex::new(None);

/// Get the path to the settings file
pub fn get_settings_path() -> Result<PathBuf, String> {
    let home_dir = dirs::home_dir()
        .ok_or_else(|| "Failed to get home directory".to_string())?;

    let valet_dir = home_dir.join("Library/Application Support/Valet");

    // Ensure the Valet directory exists
    fs::create_dir_all(&valet_dir)
        .map_err(|e| format!("Failed to create Valet directory: {}", e))?;

    Ok(valet_dir.join("settings.json"))
}

/// Load settings from disk
pub fn load_settings() -> Result<HashMap<String, String>, String> {
    let settings_path = get_settings_path()?;

    if !settings_path.exists() {
        return Ok(HashMap::new());
    }

    let mut file = File::open(&settings_path)
        .map_err(|e| format!("Failed to open settings file: {}", e))?;

    let mut contents = String::new();
    file.read_to_string(&mut contents)
        .map_err(|e| format!("Failed to read settings file: {}", e))?;

    if contents.trim().is_empty() {
        return Ok(HashMap::new());
    }

    let settings: HashMap<String, String> = serde_json::from_str(&contents)
        .map_err(|e| format!("Failed to parse settings file: {}", e))?;

    Ok(settings)
}

/// Save settings to disk
fn save_settings(settings: &HashMap<String, String>) -> Result<(), String> {
    let settings_path = get_settings_path()?;

    let json = serde_json::to_string_pretty(settings)
        .map_err(|e| format!("Failed to serialize settings: {}", e))?;

    let mut file = File::create(&settings_path)
        .map_err(|e| format!("Failed to create settings file: {}", e))?;

    file.write_all(json.as_bytes())
        .map_err(|e| format!("Failed to write settings file: {}", e))?;

    Ok(())
}

/// Get a setting value
#[tauri::command]
pub fn get_setting_command(key: String) -> Result<Option<String>, String> {
    let mut settings_lock = SETTINGS.lock()
        .map_err(|e| format!("Failed to lock settings: {}", e))?;

    // Load settings if not already loaded
    if settings_lock.is_none() {
        *settings_lock = Some(load_settings()?);
    }

    let settings = settings_lock.as_ref().unwrap();
    Ok(settings.get(&key).cloned())
}

/// Set a setting value
#[tauri::command]
pub fn set_setting_command(key: String, value: String) -> Result<(), String> {
    let mut settings_lock = SETTINGS.lock()
        .map_err(|e| format!("Failed to lock settings: {}", e))?;

    // Load settings if not already loaded
    if settings_lock.is_none() {
        *settings_lock = Some(load_settings()?);
    }

    let settings = settings_lock.as_mut().unwrap();
    settings.insert(key, value);

    // Save to disk
    save_settings(settings)?;

    Ok(())
}

/// Delete a setting
#[tauri::command]
pub fn delete_setting_command(key: String) -> Result<(), String> {
    let mut settings_lock = SETTINGS.lock()
        .map_err(|e| format!("Failed to lock settings: {}", e))?;

    // Load settings if not already loaded
    if settings_lock.is_none() {
        *settings_lock = Some(load_settings()?);
    }

    let settings = settings_lock.as_mut().unwrap();
    settings.remove(&key);

    // Save to disk
    save_settings(settings)?;

    Ok(())
}

/// Get all settings
#[tauri::command]
pub fn get_all_settings_command() -> Result<HashMap<String, String>, String> {
    let mut settings_lock = SETTINGS.lock()
        .map_err(|e| format!("Failed to lock settings: {}", e))?;

    // Load settings if not already loaded
    if settings_lock.is_none() {
        *settings_lock = Some(load_settings()?);
    }

    Ok(settings_lock.as_ref().unwrap().clone())
}
