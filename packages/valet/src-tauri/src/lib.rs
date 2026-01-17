use tauri::Manager;

mod audit;
mod keychain;
mod mole;
mod monitoring;
mod permissions;
mod settings;
mod workspace;

/// Enable or disable auto-launch on system startup
#[tauri::command]
fn set_autostart(app: tauri::AppHandle, enable: bool) -> Result<(), String> {
  let autostart_manager = app.autolaunch();

  if enable {
    autostart_manager.enable().map_err(|e| e.to_string())?;
  } else {
    autostart_manager.disable().map_err(|e| e.to_string())?;
  }

  Ok(())
}

/// Check if auto-launch is currently enabled
#[tauri::command]
fn is_autostart_enabled(app: tauri::AppHandle) -> Result<bool, String> {
  let autostart_manager = app.autolaunch();
  autostart_manager.is_enabled().map_err(|e| e.to_string())
}

/// Update tray icon tooltip
#[tauri::command]
fn update_tray_tooltip(app: tauri::AppHandle, tooltip: String) -> Result<(), String> {
  if let Some(tray) = app.tray_by_id("main") {
    tray.set_tooltip(Some(&tooltip)).map_err(|e| e.to_string())?;
  }
  Ok(())
}

/// Update tray icon based on health status and AI working state
#[tauri::command]
fn update_tray_icon(app: tauri::AppHandle, status: String, is_ai_working: bool) -> Result<(), String> {
  if let Some(tray) = app.tray_by_id("main") {
    // If AI is working, show AI-active indicator using title overlay
    // This provides a visually distinct indicator without requiring animated assets
    if is_ai_working {
      tray.set_title(Some("🤖")).map_err(|e| e.to_string())?;
      return Ok(());
    }

    // Update tray icon based on health status using icon assets
    // Icon files should be placed in src-tauri/icons/ directory:
    // - icon-good.png (green) for healthy state
    // - icon-warning.png (yellow) for warning state
    // - icon-critical.png (red) for critical state

    let icon_name = match status.as_str() {
      "good" => "icon-good.png",
      "warning" => "icon-warning.png",
      "critical" => "icon-critical.png",
      _ => "icon.png", // fallback to default icon
    };

    // Try to load the health-specific icon from bundled resources
    let icon_path = app
      .path()
      .resource_dir()
      .map_err(|e| e.to_string())?
      .join(icon_name);

    // If the specific health icon doesn't exist, fall back to using the default icon
    // with a title indicator (temporary solution until icons are created)
    if icon_path.exists() {
      use tauri::image::Image;
      let icon = Image::from_path(&icon_path).map_err(|e| e.to_string())?;
      tray.set_icon(Some(icon)).map_err(|e| e.to_string())?;
      tray.set_title(None).map_err(|e| e.to_string())?; // Clear title when using icon
    } else {
      // Fallback: use title indicators until health-specific icons are created
      let title = match status.as_str() {
        "good" => "",
        "warning" => "⚠",
        "critical" => "!",
        _ => "",
      };
      tray.set_title(Some(title)).map_err(|e| e.to_string())?;
    }
  }
  Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
  tauri::Builder::default()
    .plugin(tauri_plugin_autostart::init(
      tauri_plugin_autostart::MacosLauncher::LaunchAgent,
      Some(vec!["--minimized"]), // Launch minimized (to menubar only)
    ))
    .plugin(tauri_plugin_shell::init())
    .plugin(tauri_plugin_global_shortcut::Builder::new().build())
    .invoke_handler(tauri::generate_handler![
      set_autostart,
      is_autostart_enabled,
      update_tray_tooltip,
      update_tray_icon,
      mole::ensure_mole_installed_command,
      mole::get_home_dir,
      mole::run_privileged_optimize,
      workspace::workspace_path,
      workspace::ensure_workspace_command,
      audit::log_audit_event,
      audit::get_audit_events,
      audit::clear_audit_log_command,
      monitoring::get_cached_status,
      monitoring::update_monitoring_config,
      monitoring::trigger_status_check,
      permissions::check_permissions_command,
      permissions::request_microphone_permission_command,
      permissions::open_system_preferences_command,
      settings::get_setting_command,
      settings::set_setting_command,
      settings::delete_setting_command,
      settings::get_all_settings_command,
      keychain::store_key_command,
      keychain::get_key_command,
      keychain::delete_key_command,
      keychain::has_key_command,
    ])
    .setup(|app| {
      if cfg!(debug_assertions) {
        app.handle().plugin(
          tauri_plugin_log::Builder::default()
            .level(log::LevelFilter::Info)
            .build(),
        )?;
      }

      // Ensure Mole is installed on startup
      if let Err(e) = mole::ensure_mole_installed(app.handle()) {
        log::error!("Failed to install Mole: {}", e);
      } else {
        log::info!("Mole installed successfully");
      }

      // Ensure workspace is set up on startup
      if let Err(e) = workspace::ensure_workspace(app.handle()) {
        log::error!("Failed to set up workspace: {}", e);
      } else {
        log::info!("Workspace set up successfully");
      }

      // Start background monitoring
      monitoring::start_monitoring(app.handle().clone());

      // Set up tray icon click handler
      if let Some(tray) = app.tray_by_id("main") {
        tray.on_tray_icon_event(|tray, event| {
          if let tauri::tray::TrayIconEvent::Click { button, .. } = event {
            if button == tauri::tray::MouseButton::Left {
              // Get the app handle
              let app = tray.app_handle();

              // Toggle window visibility (menubar-only lifecycle)
              if let Some(window) = app.get_webview_window("main") {
                if window.is_visible().unwrap_or(false) {
                  let _ = window.hide();
                } else {
                  // Position window below tray icon before showing
                  let _ = window.show();
                  let _ = window.set_focus();
                }
              }
            }
          }
        });
      }

      // Hide window on blur to maintain menubar-only behavior
      if let Some(window) = app.get_webview_window("main") {
        let window_clone = window.clone();
        window.on_window_event(move |event| {
          if let tauri::WindowEvent::Focused(false) = event {
            // Window lost focus, hide it
            let _ = window_clone.hide();
          }
        });
      }

      Ok(())
    })
    .run(tauri::generate_context!())
    .expect("error while running tauri application");
}
