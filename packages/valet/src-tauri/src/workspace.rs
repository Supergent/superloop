use std::fs;
use std::path::PathBuf;
use tauri::{AppHandle, Manager};

/// Get the workspace directory path
pub fn get_workspace_path() -> Result<PathBuf, String> {
    let home_dir = dirs::home_dir()
        .ok_or_else(|| "Failed to get home directory".to_string())?;

    Ok(home_dir.join("Library/Application Support/Valet/workspace"))
}

/// Get the path to bundled resources
fn get_bundled_resources_path(app: &AppHandle) -> Result<PathBuf, String> {
    app
        .path()
        .resource_dir()
        .map_err(|e| format!("Failed to get resource directory: {}", e))
}

/// Ensure the workspace directory exists and is set up correctly
pub fn ensure_workspace(app: &AppHandle) -> Result<PathBuf, String> {
    let workspace_path = get_workspace_path()?;

    // Create workspace directory if it doesn't exist
    fs::create_dir_all(&workspace_path)
        .map_err(|e| format!("Failed to create workspace directory: {}", e))?;

    // Create .claude directory structure
    let claude_dir = workspace_path.join(".claude");
    let skills_dir = claude_dir.join("skills");

    fs::create_dir_all(&skills_dir)
        .map_err(|e| format!("Failed to create .claude/skills directory: {}", e))?;

    // Copy mole.md skill file if it doesn't exist
    let skills_dest = skills_dir.join("mole.md");
    if !skills_dest.exists() {
        let bundled_resources = get_bundled_resources_path(app)?;
        let skills_source = bundled_resources.join(".claude/skills/mole.md");

        if skills_source.exists() {
            fs::copy(&skills_source, &skills_dest)
                .map_err(|e| format!("Failed to copy mole.md skill file: {}", e))?;

            log::info!("Copied mole.md skill file to workspace");
        } else {
            log::warn!("Bundled mole.md skill file not found at {:?}", skills_source);
        }
    }

    Ok(workspace_path)
}

/// Tauri command to get the workspace path
#[tauri::command]
pub fn workspace_path() -> Result<String, String> {
    let path = get_workspace_path()?;
    Ok(path.to_string_lossy().to_string())
}

/// Tauri command to ensure workspace is set up
#[tauri::command]
pub fn ensure_workspace_command(app: AppHandle) -> Result<String, String> {
    let path = ensure_workspace(&app)?;
    Ok(path.to_string_lossy().to_string())
}
