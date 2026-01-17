use keyring::Entry;

const SERVICE_NAME: &str = "com.valet.mac";

/// Store a key in the macOS Keychain
#[tauri::command]
pub fn store_key_command(key_name: String, key_value: String) -> Result<(), String> {
    let entry = Entry::new(SERVICE_NAME, &key_name)
        .map_err(|e| format!("Failed to create keychain entry: {}", e))?;

    entry.set_password(&key_value)
        .map_err(|e| format!("Failed to store key in keychain: {}", e))?;

    Ok(())
}

/// Retrieve a key from the macOS Keychain
#[tauri::command]
pub fn get_key_command(key_name: String) -> Result<Option<String>, String> {
    let entry = Entry::new(SERVICE_NAME, &key_name)
        .map_err(|e| format!("Failed to create keychain entry: {}", e))?;

    match entry.get_password() {
        Ok(password) => Ok(Some(password)),
        Err(keyring::Error::NoEntry) => Ok(None),
        Err(e) => Err(format!("Failed to retrieve key from keychain: {}", e)),
    }
}

/// Delete a key from the macOS Keychain
#[tauri::command]
pub fn delete_key_command(key_name: String) -> Result<(), String> {
    let entry = Entry::new(SERVICE_NAME, &key_name)
        .map_err(|e| format!("Failed to create keychain entry: {}", e))?;

    match entry.delete_credential() {
        Ok(()) => Ok(()),
        Err(keyring::Error::NoEntry) => Ok(()), // Already deleted or never existed
        Err(e) => Err(format!("Failed to delete key from keychain: {}", e)),
    }
}

/// Check if a key exists in the macOS Keychain
#[tauri::command]
pub fn has_key_command(key_name: String) -> Result<bool, String> {
    let entry = Entry::new(SERVICE_NAME, &key_name)
        .map_err(|e| format!("Failed to create keychain entry: {}", e))?;

    match entry.get_password() {
        Ok(_) => Ok(true),
        Err(keyring::Error::NoEntry) => Ok(false),
        Err(e) => Err(format!("Failed to check key in keychain: {}", e)),
    }
}
