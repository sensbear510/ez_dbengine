//! ez_db_adapter.rs - Shared Instance Data Mapper for Rust Web Services (Axum / Actix)

use std::collections::HashMap;
use std::sync::{OnceLock, RwLock};
use std::path::Path;
use crate::ez_dbengine::EzDbEngine;

pub struct EzDbAdapter {
    engine: &'static EzDbEngine,
    handles: RwLock<HashMap<String, u64>>,
}

static ADAPTER_INSTANCE: OnceLock<EzDbAdapter> = OnceLock::new();

impl EzDbAdapter {
    pub fn global() -> &'static EzDbAdapter {
        ADAPTER_INSTANCE.get_or_init(|| EzDbAdapter {
            engine: EzDbEngine::global(),
            handles: RwLock::new(HashMap::new()),
        })
    }

    pub fn get_handle(&self, table_name: &str) -> Result<u64, String> {
        let path = format!("data/{}.ebf", table_name);

        {
            let map = self.handles.read().map_err(|e| e.to_string())?;
            if let Some(&h) = map.get(&path) {
                return Ok(h);
            }
        }

        let mut map = self.handles.write().map_err(|e| e.to_string())?;
        if let Some(&h) = map.get(&path) {
            return Ok(h);
        }

        let (h, _) = self.engine.use_table(&path).map_err(|e| e.to_string())?;
        map.insert(path, h);
        Ok(h)
    }

    pub fn insert(&self, table_name: &str, csv_payload: &str) -> Result<u64, String> {
        let h = self.get_handle(table_name)?;
        let st = self.engine.append(h, csv_payload, 1, ",");
        if st != 0 {
            return Err(format!("Insert failed on table {}: {}", table_name, self.engine.get_detailed_error(st)));
        }
        let commit_st = self.engine.commit(h);
        if commit_st != 0 {
            return Err(format!("Commit failed on table {}: {}", table_name, self.engine.get_detailed_error(commit_st)));
        }
        Ok(self.engine.get_record_count(h))
    }
}