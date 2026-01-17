use std::fs;
use std::path::PathBuf;
use tauri::{AppHandle, Manager};

/// Get the path to the bundled Mole resources directory
fn get_bundled_mole_path(app: &AppHandle) -> Result<PathBuf, String> {
    let resource_path = app
        .path()
        .resource_dir()
        .map_err(|e| format!("Failed to get resource directory: {}", e))?;

    Ok(resource_path.join("mole"))
}

/// Get the installation directory for Mole in Application Support
fn get_mole_install_dir() -> Result<PathBuf, String> {
    let home_dir = dirs::home_dir()
        .ok_or_else(|| "Failed to get home directory".to_string())?;

    Ok(home_dir.join("Library/Application Support/Valet/bin"))
}

/// Ensure the Mole binary is installed and executable
pub fn ensure_mole_installed(app: &AppHandle) -> Result<PathBuf, String> {
    let bundled_mole_dir = get_bundled_mole_path(app)?;
    let install_dir = get_mole_install_dir()?;
    let install_path = install_dir.join("mo");

    // Create installation directory if it doesn't exist
    fs::create_dir_all(&install_dir)
        .map_err(|e| format!("Failed to create installation directory: {}", e))?;

    // Check if mo is already installed and up to date
    if install_path.exists() {
        // TODO: Add version checking here in the future
        // For now, we'll just return the existing installation
        return Ok(install_path);
    }

    // Copy the entire bundled mole directory to the installation location
    let install_mole_dir = install_dir.parent()
        .ok_or_else(|| "Failed to get parent directory".to_string())?
        .join("mole");

    // Remove existing installation if present
    if install_mole_dir.exists() {
        fs::remove_dir_all(&install_mole_dir)
            .map_err(|e| format!("Failed to remove existing Mole directory: {}", e))?;
    }

    // Copy the bundled mole directory
    copy_dir_recursive(&bundled_mole_dir, &install_mole_dir)?;

    // Create a symlink from bin/mo to mole/mo
    let mole_binary = install_mole_dir.join("mo");

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;

        // Set executable permissions on the mo script
        let mut perms = fs::metadata(&mole_binary)
            .map_err(|e| format!("Failed to get metadata for mo: {}", e))?
            .permissions();
        perms.set_mode(0o755);
        fs::set_permissions(&mole_binary, perms)
            .map_err(|e| format!("Failed to set permissions on mo: {}", e))?;

        // Set executable permissions on all bin scripts
        let bin_dir = install_mole_dir.join("bin");
        if bin_dir.exists() {
            for entry in fs::read_dir(&bin_dir)
                .map_err(|e| format!("Failed to read bin directory: {}", e))?
            {
                let entry = entry.map_err(|e| format!("Failed to read directory entry: {}", e))?;
                let path = entry.path();
                if path.is_file() {
                    let mut perms = fs::metadata(&path)
                        .map_err(|e| format!("Failed to get metadata: {}", e))?
                        .permissions();
                    perms.set_mode(0o755);
                    fs::set_permissions(&path, perms)
                        .map_err(|e| format!("Failed to set permissions: {}", e))?;
                }
            }
        }

        // Create symlink
        std::os::unix::fs::symlink(&mole_binary, &install_path)
            .map_err(|e| format!("Failed to create symlink: {}", e))?;
    }

    #[cfg(not(unix))]
    {
        // On non-Unix systems, just copy the file
        fs::copy(&mole_binary, &install_path)
            .map_err(|e| format!("Failed to copy mo binary: {}", e))?;
    }

    Ok(install_path)
}

/// Recursively copy a directory
fn copy_dir_recursive(src: &PathBuf, dst: &PathBuf) -> Result<(), String> {
    fs::create_dir_all(dst)
        .map_err(|e| format!("Failed to create directory {}: {}", dst.display(), e))?;

    for entry in fs::read_dir(src)
        .map_err(|e| format!("Failed to read directory {}: {}", src.display(), e))?
    {
        let entry = entry.map_err(|e| format!("Failed to read directory entry: {}", e))?;
        let path = entry.path();
        let file_name = entry.file_name();
        let dst_path = dst.join(&file_name);

        if path.is_dir() {
            copy_dir_recursive(&path, &dst_path)?;
        } else {
            fs::copy(&path, &dst_path)
                .map_err(|e| format!("Failed to copy file {} to {}: {}", path.display(), dst_path.display(), e))?;

            // Preserve executable permissions on Unix
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                let src_perms = fs::metadata(&path)
                    .map_err(|e| format!("Failed to get metadata: {}", e))?
                    .permissions();
                fs::set_permissions(&dst_path, src_perms)
                    .map_err(|e| format!("Failed to set permissions: {}", e))?;
            }
        }
    }

    Ok(())
}

/// Tauri command to ensure Mole is installed
#[tauri::command]
pub fn ensure_mole_installed_command(app: AppHandle) -> Result<String, String> {
    let path = ensure_mole_installed(&app)?;
    Ok(path.to_string_lossy().to_string())
}

/// Tauri command to get the home directory
#[tauri::command]
pub fn get_home_dir() -> Result<String, String> {
    let home = dirs::home_dir()
        .ok_or_else(|| "Failed to get home directory".to_string())?;
    Ok(home.to_string_lossy().to_string())
}
