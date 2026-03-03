use nyro_core::db::models::*;
use nyro_core::Gateway;
use tauri::State;

#[tauri::command]
pub async fn get_providers(gw: State<'_, Gateway>) -> Result<Vec<Provider>, String> {
    gw.admin()
        .list_providers()
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn create_provider(
    gw: State<'_, Gateway>,
    input: CreateProvider,
) -> Result<Provider, String> {
    gw.admin()
        .create_provider(input)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn delete_provider(gw: State<'_, Gateway>, id: String) -> Result<(), String> {
    gw.admin()
        .delete_provider(&id)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn list_routes(gw: State<'_, Gateway>) -> Result<Vec<Route>, String> {
    gw.admin()
        .list_routes()
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn create_route(
    gw: State<'_, Gateway>,
    input: CreateRoute,
) -> Result<Route, String> {
    gw.admin()
        .create_route(input)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn delete_route(gw: State<'_, Gateway>, id: String) -> Result<(), String> {
    gw.admin()
        .delete_route(&id)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn get_gateway_status(gw: State<'_, Gateway>) -> Result<serde_json::Value, String> {
    Ok(serde_json::json!({
        "status": "running",
        "proxy_port": gw.config.proxy_port,
    }))
}
