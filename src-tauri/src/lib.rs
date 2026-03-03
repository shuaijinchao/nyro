mod commands;

use tauri::Manager;
use nyro_core::{Gateway, config::GatewayConfig, logging};

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tracing_subscriber::fmt()
        .with_env_filter("nyro=debug,tower_http=debug")
        .init();

    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|_app, _args, _cwd| {}))
        .setup(|app| {
            let data_dir = app
                .path()
                .app_data_dir()
                .unwrap_or_else(|_| std::path::PathBuf::from(".nyro"));

            let config = GatewayConfig {
                data_dir,
                ..Default::default()
            };

            let rt = tokio::runtime::Handle::current();
            let (gateway, log_rx) = rt.block_on(Gateway::new(config))?;

            let gw_proxy = gateway.clone();
            let db_for_logs = gateway.db.clone();

            tauri::async_runtime::spawn(async move {
                if let Err(e) = gw_proxy.start_proxy().await {
                    tracing::error!("proxy server error: {e}");
                }
            });

            tauri::async_runtime::spawn(async move {
                logging::run_collector(log_rx, db_for_logs).await;
            });

            app.manage(gateway);
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::get_providers,
            commands::create_provider,
            commands::delete_provider,
            commands::list_routes,
            commands::create_route,
            commands::delete_route,
            commands::get_gateway_status,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
