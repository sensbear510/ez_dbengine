//! ez_dbengine.rs - High-Level Safe Rust Binding for EDB 2.0 Engine
//! Encapsulated with Flutter-like OOP design and idiomatic Rust standards.
//! Complete 1:1 C-FFI Mapping aligned with ez_engine.h & ez_relation_mgr.h
#![allow(dead_code, unused_imports, non_camel_case_types)]

use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::fmt;
use std::path::Path;
use std::sync::OnceLock;

// =============================================================================
// 1. Raw C-FFI Binding Definitions
// =============================================================================
pub mod ffi {
    use super::*;

    // 52 + 1 + 4 + 1 + 1 + 4 + 1 = 64 Bytes，嚴格對齊 C 核心 EZ_FIELD_NODE
    #[repr(C, packed)]
    pub struct RawFieldNode {
        pub name: [u8; 52],
        pub type_: u8,
        pub len: u32,
        pub dec: u8,
        pub storage: u8,
        pub offset: u32,
        pub zbf_sequence: u8,
    }

    #[repr(C, packed)]
    pub struct RawMigrateReport {
        pub status: u32,
        pub error_code: u32,
        pub total_recs: u64,
        pub recovered_recs: u64,
        pub message: [u8; 128],
    }

    #[repr(C, packed)]
    pub struct RawTagInfo {
        pub tag_name: [u8; 64],
        pub key_len: u32,
        pub key_type: u32,
        pub root_ptr: u64,
        pub node_count: u64,
        pub is_descending: u32,
        pub h_slot: u32,
        pub field_offsets: [u32; 8],
        pub field_lens: [u32; 8],
        pub field_count: u8,
        pub is_unique: u8,
        pub _final_pad: [u8; 94],
    }

    #[repr(C, packed)]
    pub struct RawBlobPtr {
        pub blob_offset: u64,
        pub logical_length: u32,
        pub physical_length: u32,
        pub file_sequence: u32,
        pub flags: u32,
    }

    #[repr(C)]
    pub struct RawRlNodeDesc {
        pub ebf_index: u16,
        pub field_name: [u8; 52],
        pub alias_name: [u8; 52],
    }

    #[repr(C)]
    pub struct RawRlLinkDesc {
        pub parent_ebf_index: u16,
        pub child_ebf_index: u16,
        pub fk_field_count: u8,
        pub parent_fk_offsets: [u16; 8],
        pub parent_fk_lens: [u16; 8],
        pub child_tag_name: [u8; 48],
    }

    #[repr(C)]
    pub struct RawRlViewDesc {
        pub relation_name: *const c_char,
        pub join_mode: u32,
        pub h_ebf_array: *const u64,
        pub ebf_count: u16,
        pub nodes: *const RawRlNodeDesc,
        pub node_count: u16,
        pub links: *const RawRlLinkDesc,
        pub link_count: u16,
    }

    pub type ObserverCallback = Option<
        extern "C" fn(slot: u32, event: u32, offset: u64, len: u32, buffer: *const c_void),
    >;

    extern "C" {
        // Group A: 生命週期與結構維護
        pub fn ez_db_create(path: *const c_char, map: *const RawFieldNode) -> i32;
        pub fn ez_db_alter(h: u64, path: *const c_char, new_map: *const RawFieldNode, report: *mut RawMigrateReport) -> i32;
        pub fn ez_db_reconstruct(h: u64, path: *const c_char, report: *mut RawMigrateReport) -> i32;
        pub fn ez_db_use(path: *const c_char, report: *mut RawMigrateReport) -> u64;
        pub fn ez_db_open(path: *const c_char, report: *mut RawMigrateReport) -> u64;
        pub fn ez_db_close(h: u64) -> i32;
        pub fn ez_db_close_all() -> i32;
        pub fn ez_db_set_vacuum(h: u64, threshold: f32, min_deleted: u32);
        pub fn ez_db_get_name_from_path(path: *const c_char, out_name: *mut c_char, max_len: u32);

        // Group B: 雙軌導航與狀態
        pub fn ez_db_gotop(h: u64, tag_id: u32, tag_name: *const c_char) -> i32;
        pub fn ez_db_gobottom(h: u64, tag_id: u32, tag_name: *const c_char) -> i32;
        pub fn ez_db_skip(h: u64, tag_id: u32, tag_name: *const c_char, n: i32) -> i32;
        pub fn ez_db_goto(h: u64, tag_id: u32, tag_name: *const c_char, recno: u64) -> i32;
        pub fn ez_db_is_eof(h: u64, tag_id: u32, tag_name: *const c_char) -> bool;
        pub fn ez_db_is_bof(h: u64, tag_id: u32, tag_name: *const c_char) -> bool;
        pub fn ez_db_is_found(h: u64, tag_id: u32, tag_name: *const c_char) -> bool;
        pub fn ez_db_recno(h: u64, tag_id: u32, tag_name: *const c_char) -> i64;
        pub fn ez_db_lastrec(h: u64, tag_id: u32, tag_name: *const c_char) -> i64;
        pub fn ez_db_recsize(h: u64) -> u32;
        pub fn ez_db_record_count(h: u64) -> u64;

        // Group C: 資料存取與原子更新
        pub fn ez_db_get_record(h: u64, tag_id: u32, tag_name: *const c_char, buffer: *mut u8, buffer_size: u32, include_deleted: bool) -> i32;
        pub fn ez_db_get_record_vector(h: u64, tag_id: u32, tag_name: *const c_char, out_struct_array: *mut c_void, p_count: *mut u32, struct_size: u32, strip_str: bool, include_deleted: bool) -> i32;
        pub fn ez_db_seek_by_tag(h: u64, tag_name: *const c_char, ...) -> i32;
        pub fn ez_db_seek_by_tag_id(h: u64, tag_id: u32, ...) -> i32;
        pub fn ez_db_seek_by_tag_array(h: u64, tag_name: *const c_char, values: *const *const c_void) -> i32;
        pub fn ez_db_seek_by_tag_id_array(h: u64, tag_id: u32, values: *const *const c_void) -> i32;
        pub fn ez_db_locate(h: u64, fieldname: *const c_char, target_value: *const c_void, partial_match: bool) -> i32;

        pub fn ez_db_append(h: u64, data: *const c_char, rec_count: u32, delim: *const c_char) -> i32;
        pub fn ez_db_insert(h: u64, data: *const c_char, rec_count: u32, delim: *const c_char) -> i32;
        pub fn ez_db_row_replace(h: u64, row_id: u64, data: *const c_char, delim: *const c_char) -> i32;
        pub fn ez_db_replace(h: u64, row_id: u64, fieldname: *const c_char, val: *const c_void) -> i32;

        pub fn ez_db_is_deleted(h: u64, row_id: u64) -> bool;
        pub fn ez_db_delete(h: u64, row_id: u64) -> i32;
        pub fn ez_db_recall(h: u64, row_id: u64) -> i32;
        pub fn ez_db_pack(h: u64, temp_path: *const c_char) -> i32;
        pub fn ez_db_zap(h: u64) -> i32;
        pub fn ez_db_commit(h: u64) -> i32;
        pub fn ez_db_get_blob_data(h: u64, blob_ptr: *const RawBlobPtr, out_buf: *mut c_void, out_buf_size: u32) -> i32;

        // Group D: 索引維護
        pub fn ez_db_create_index(h: u64, tag_name: *const c_char, fields_str: *const c_char, is_unique: bool) -> i32;
        pub fn ez_db_mount_index(h: u64, edx_path: *const c_char, slot_id: u32) -> i32;
        pub fn ez_db_purge_duplicates(h: u64, tag_id: u32, keep_row_id: u64) -> i32;
        pub fn ez_db_extract_duplicates(h: u64, tag_id: u32) -> i32;

        // Group E: 反射與偵錯工具
        pub fn ez_db_get_field_names(h: u64, out_buf: *mut c_char, buf_size: u32, delim: *const c_char) -> i32;
        pub fn ez_db_get_index_key(h: u64, tag_id: u32, tag_name: *const c_char, out_buf: *mut c_char, out_buf_len: u32) -> i32;
        pub fn ez_db_get_fdt(h: u64) -> *const RawFieldNode;
        pub fn ez_db_get_tags(h: u64) -> *const RawTagInfo;
        pub fn ez_db_get_delete_count(h: u64) -> u64;
        pub fn ez_db_dump_record(h: u64, record_payload: *const c_void);
        pub fn ez_db_dump_workarea(h: u64);
        pub fn ez_set_state_observer(cb: ObserverCallback);

        // 錯誤診斷子系統導出 (ez_engine.h)
        pub fn ez_errstr(status: i32) -> *const c_char;
        pub fn ez_last_error() -> *const c_char;

        // 關聯檢視子系統 (ez_relation_mgr.h)
        pub fn ez_rl_mgr_init() -> i32;
        pub fn ez_rl_mgr_cleanup() -> i32;
        pub fn ez_rl_build_view(desc: *const RawRlViewDesc) -> u64;
        pub fn ez_rl_destroy_view(h_rel: u64) -> i32;
        pub fn ez_rl_register(rel: *mut c_void) -> u64;
        pub fn _ez_get_relation_table(h_rel: u64) -> *mut c_void;
        pub fn ez_rl_get_record_vector(rel: *mut c_void, out_buffer: *mut u8, request_count: u32, actual_count: *mut u32) -> i32;
        pub fn ez_rl_save_view_file(desc: *const RawRlViewDesc, erl_path: *const c_char) -> i32;
        pub fn ez_rl_load_view_file(erl_path: *const c_char, h_ebf_array: *const u64, ebf_count: u16) -> u64;

        // 量化子系統 (ez_quant.h)
        pub fn ez_quant_compress_f32_4bit(in_vec: *const f32, dim: u32, out_packed: *mut u8, out_min: *mut f32, out_max: *mut f32) -> i32;
        pub fn ez_quant_decompress_4bit_f32(in_packed: *const u8, min_val: f32, max_val: f32, dim: u32, out_vec: *mut f32) -> i32;
    }
}

// =============================================================================
// 2. Strongly-Typed Enums & Safe Data Structures
// =============================================================================

#[derive(Debug, PartialEq, Eq)]
pub enum EzDbError {
    DatabaseCreateFailed(i32, String),
    DatabaseOpenFailed(String),
    OperationFailed(i32, String),
    StringConversionError,
    InvalidHandle,
}

impl fmt::Display for EzDbError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            EzDbError::DatabaseCreateFailed(code, msg) => write!(f, "Failed to create database [Code: {}]: {}", code, msg),
            EzDbError::DatabaseOpenFailed(msg) => write!(f, "Failed to open database: {}", msg),
            EzDbError::OperationFailed(code, msg) => write!(f, "Operation failed [Code: {}]: {}", code, msg),
            EzDbError::StringConversionError => write!(f, "Failed to convert string into C-compatible format."),
            EzDbError::InvalidHandle => write!(f, "Database handle is invalid or 0."),
        }
    }
}

impl std::error::Error for EzDbError {}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FieldType {
    Character,
    Numeric,
    Date,
    Logical,
    Integer,
    Memo,
    Binary,
}

impl FieldType {
    pub fn to_code(self) -> u8 {
        match self {
            FieldType::Character => b'C',
            FieldType::Numeric => b'N',
            FieldType::Date => b'D',
            FieldType::Logical => b'L',
            FieldType::Integer => b'I',
            FieldType::Memo => b'M',
            FieldType::Binary => b'B',
        }
    }

    pub fn from_code(code: u8) -> Self {
        match code {
            b'N' => FieldType::Numeric,
            b'D' => FieldType::Date,
            b'L' => FieldType::Logical,
            b'I' => FieldType::Integer,
            b'M' => FieldType::Memo,
            b'B' => FieldType::Binary,
            _ => FieldType::Character,
        }
    }
}

#[derive(Debug, Clone)]
pub struct FieldDefinition {
    pub name: String,
    pub field_type: FieldType,
    pub length: u32,
    pub decimals: u8,
}

impl FieldDefinition {
    pub fn new(name: impl Into<String>, field_type: FieldType, length: u32, decimals: u8) -> Self {
        Self {
            name: name.into(),
            field_type,
            length,
            decimals,
        }
    }

    pub fn to_raw(&self, offset: u32) -> ffi::RawFieldNode {
        let mut name_buf = [0u8; 52];
        let bytes = self.name.as_bytes();
        let copy_len = bytes.len().min(51);
        name_buf[..copy_len].copy_from_slice(&bytes[..copy_len]);

        ffi::RawFieldNode {
            name: name_buf,
            type_: self.field_type.to_code(),
            len: self.length,
            dec: self.decimals,
            storage: 0,
            offset,
            zbf_sequence: 0,
        }
    }
}

#[derive(Debug, Clone)]
pub struct MigrateReport {
    pub status: u32,
    pub error_code: u32,
    pub total_records: u64,
    pub recovered_records: u64,
    pub message: String,
}

impl MigrateReport {
    pub fn from_raw(raw: &ffi::RawMigrateReport) -> Self {
        let msg_bytes = raw.message.split(|&b| b == 0).next().unwrap_or(&[]);
        Self {
            status: raw.status,
            error_code: raw.error_code,
            total_records: raw.total_recs,
            recovered_records: raw.recovered_recs,
            message: String::from_utf8_lossy(msg_bytes).into_owned(),
        }
    }
}

// =============================================================================
// 3. 高階無狀態單例驅動 (EzDbEngine Stateless Singleton)
// =============================================================================

#[derive(Clone, Copy)]
pub struct EzDbEngine;

static INSTANCE: OnceLock<EzDbEngine> = OnceLock::new();

impl EzDbEngine {
    /// 取得全域無狀態單例
    pub fn global() -> &'static EzDbEngine {
        INSTANCE.get_or_init(|| EzDbEngine)
    }

    // --- 錯誤診斷子系統 ---
    pub fn err_str(&self, status: i32) -> String {
        unsafe {
            let ptr = ffi::ez_errstr(status);
            if ptr.is_null() {
                "Unknown engine error".to_string()
            } else {
                CStr::from_ptr(ptr).to_string_lossy().into_owned()
            }
        }
    }

    pub fn last_error(&self) -> String {
        unsafe {
            let ptr = ffi::ez_last_error();
            if ptr.is_null() {
                String::new()
            } else {
                CStr::from_ptr(ptr).to_string_lossy().into_owned()
            }
        }
    }

    pub fn get_detailed_error(&self, status: i32) -> String {
        let dyn_msg = self.last_error();
        let desc = self.err_str(status);
        if !dyn_msg.is_empty() {
            format!("[{}] {} (Code: {})", desc, dyn_msg, status)
        } else {
            format!("[{}] (Code: {})", desc, status)
        }
    }

    // --- Group A: 生命週期與結構維護 ---
    pub fn create_table(&self, path: impl AsRef<Path>, fields: &[FieldDefinition]) -> Result<(), EzDbError> {
        let path_str = path.as_ref().to_str().ok_or(EzDbError::StringConversionError)?;
        let c_path = CString::new(path_str).map_err(|_| EzDbError::StringConversionError)?;

        let mut raw_fdt: Vec<ffi::RawFieldNode> = Vec::with_capacity(fields.len() + 1);
        let mut curr_offset: u32 = 0;

        for f in fields {
            raw_fdt.push(f.to_raw(curr_offset));
            curr_offset += f.length;
        }

        // 結尾 Node (type_ = 0)
        let mut end_node: ffi::RawFieldNode = unsafe { std::mem::zeroed() };
        end_node.offset = curr_offset;
        raw_fdt.push(end_node);

        let status = unsafe { ffi::ez_db_create(c_path.as_ptr(), raw_fdt.as_ptr()) };
        if status == 0 {
            Ok(())
        } else {
            Err(EzDbError::DatabaseCreateFailed(status, self.get_detailed_error(status)))
        }
    }

    pub fn use_table(&self, path: impl AsRef<Path>) -> Result<(u64, MigrateReport), EzDbError> {
        let path_str = path.as_ref().to_str().ok_or(EzDbError::StringConversionError)?;
        let c_path = CString::new(path_str).map_err(|_| EzDbError::StringConversionError)?;

        let mut report = unsafe { std::mem::zeroed::<ffi::RawMigrateReport>() };
        let handle = unsafe { ffi::ez_db_use(c_path.as_ptr(), &mut report) };

        let rep = MigrateReport::from_raw(&report);
        if handle == 0 {
            let dyn_msg = self.last_error();
            Err(EzDbError::DatabaseOpenFailed(format!("{} {}", rep.message, dyn_msg)))
        } else {
            Ok((handle, rep))
        }
    }

    pub fn open(&self, path: impl AsRef<Path>) -> Result<(u64, MigrateReport), EzDbError> {
        self.use_table(path)
    }

    pub fn close(&self, handle: u64) -> i32 {
        if handle == 0 { return -106; }
        unsafe { ffi::ez_db_close(handle) }
    }

    pub fn close_all(&self) -> i32 {
        unsafe { ffi::ez_db_close_all() }
    }

    pub fn set_vacuum(&self, handle: u64, threshold: f32, min_deleted: u32) {
        unsafe { ffi::ez_db_set_vacuum(handle, threshold, min_deleted) };
    }

    // --- Group B: 雙軌導航與狀態 ---
    pub fn go_top(&self, handle: u64, tag_id: u32, tag_name: Option<&str>) -> i32 {
        let c_tag = tag_name.and_then(|s| CString::new(s).ok());
        let p_tag = c_tag.as_ref().map_or(std::ptr::null(), |c| c.as_ptr());
        unsafe { ffi::ez_db_gotop(handle, tag_id, p_tag) }
    }

    pub fn go_bottom(&self, handle: u64, tag_id: u32, tag_name: Option<&str>) -> i32 {
        let c_tag = tag_name.and_then(|s| CString::new(s).ok());
        let p_tag = c_tag.as_ref().map_or(std::ptr::null(), |c| c.as_ptr());
        unsafe { ffi::ez_db_gobottom(handle, tag_id, p_tag) }
    }

    pub fn skip(&self, handle: u64, step: i32, tag_id: u32, tag_name: Option<&str>) -> i32 {
        let c_tag = tag_name.and_then(|s| CString::new(s).ok());
        let p_tag = c_tag.as_ref().map_or(std::ptr::null(), |c| c.as_ptr());
        unsafe { ffi::ez_db_skip(handle, tag_id, p_tag, step) }
    }

    pub fn go_to(&self, handle: u64, recno: u64, tag_id: u32, tag_name: Option<&str>) -> i32 {
        let c_tag = tag_name.and_then(|s| CString::new(s).ok());
        let p_tag = c_tag.as_ref().map_or(std::ptr::null(), |c| c.as_ptr());
        unsafe { ffi::ez_db_goto(handle, tag_id, p_tag, recno) }
    }

    pub fn is_eof(&self, handle: u64, tag_id: u32, tag_name: Option<&str>) -> bool {
        let c_tag = tag_name.and_then(|s| CString::new(s).ok());
        let p_tag = c_tag.as_ref().map_or(std::ptr::null(), |c| c.as_ptr());
        unsafe { ffi::ez_db_is_eof(handle, tag_id, p_tag) }
    }

    pub fn is_bof(&self, handle: u64, tag_id: u32, tag_name: Option<&str>) -> bool {
        let c_tag = tag_name.and_then(|s| CString::new(s).ok());
        let p_tag = c_tag.as_ref().map_or(std::ptr::null(), |c| c.as_ptr());
        unsafe { ffi::ez_db_is_bof(handle, tag_id, p_tag) }
    }

    pub fn is_found(&self, handle: u64, tag_id: u32, tag_name: Option<&str>) -> bool {
        let c_tag = tag_name.and_then(|s| CString::new(s).ok());
        let p_tag = c_tag.as_ref().map_or(std::ptr::null(), |c| c.as_ptr());
        unsafe { ffi::ez_db_is_found(handle, tag_id, p_tag) }
    }

    pub fn get_recno(&self, handle: u64, tag_id: u32, tag_name: Option<&str>) -> i64 {
        let c_tag = tag_name.and_then(|s| CString::new(s).ok());
        let p_tag = c_tag.as_ref().map_or(std::ptr::null(), |c| c.as_ptr());
        unsafe { ffi::ez_db_recno(handle, tag_id, p_tag) }
    }

    pub fn get_lastrec(&self, handle: u64, tag_id: u32, tag_name: Option<&str>) -> i64 {
        let c_tag = tag_name.and_then(|s| CString::new(s).ok());
        let p_tag = c_tag.as_ref().map_or(std::ptr::null(), |c| c.as_ptr());
        unsafe { ffi::ez_db_lastrec(handle, tag_id, p_tag) }
    }

    pub fn get_record_size(&self, handle: u64) -> u32 {
        unsafe { ffi::ez_db_recsize(handle) }
    }

    pub fn get_record_count(&self, handle: u64) -> u64 {
        unsafe { ffi::ez_db_record_count(handle) }
    }

    // --- Group C: 資料存取與原子更新 ---
    pub fn get_record(&self, handle: u64, tag_id: u32, tag_name: Option<&str>, include_deleted: bool) -> Option<Vec<u8>> {
        let rec_size = self.get_record_size(handle);
        if rec_size == 0 { return None; }

        let mut buf = vec![0u8; rec_size as usize];
        let c_tag = tag_name.and_then(|s| CString::new(s).ok());
        let p_tag = c_tag.as_ref().map_or(std::ptr::null(), |c| c.as_ptr());

        let res = unsafe {
            ffi::ez_db_get_record(handle, tag_id, p_tag, buf.as_mut_ptr(), rec_size, include_deleted)
        };
        if res == 0 { Some(buf) } else { None }
    }

    /// 高效能熱路徑專用：直接吃已含 \0 的位元組指標，0 次 Heap 分配
    #[inline(always)]
    pub unsafe fn append_raw(&self, handle: u64, data_ptr: *const c_char, rec_count: u32, delim_ptr: *const c_char) -> i32 {
        ffi::ez_db_append(handle, data_ptr, rec_count, delim_ptr)
    }

    /// 常規 Safe append：優化 delimiter 避免重複分配
    pub fn append(&self, handle: u64, data: &str, rec_count: u32, delimiter: &str) -> i32 {
        let c_data = match CString::new(data) { Ok(c) => c, Err(_) => return -106 };
        // 針對常見的逗號做靜態快取，避免重複分配
        if delimiter == "," {
            static COMMA_CSTR: &[u8] = b",\0";
            unsafe { ffi::ez_db_append(handle, c_data.as_ptr(), rec_count, COMMA_CSTR.as_ptr() as *const c_char) }
        } else {
            let c_delim = match CString::new(delimiter) { Ok(c) => c, Err(_) => return -106 };
            unsafe { ffi::ez_db_append(handle, c_data.as_ptr(), rec_count, c_delim.as_ptr()) }
        }
    }

    //pub fn append(&self, handle: u64, data: &str, rec_count: u32, delimiter: &str) -> i32 {
    //    let c_data = match CString::new(data) { Ok(c) => c, Err(_) => return -106 };
    //    let c_delim = match CString::new(delimiter) { Ok(c) => c, Err(_) => return -106 };
    //    unsafe { ffi::ez_db_append(handle, c_data.as_ptr(), rec_count, c_delim.as_ptr()) }
    //}

    pub fn insert(&self, handle: u64, data: &str, rec_count: u32, delimiter: &str) -> i32 {
        let c_data = match CString::new(data) { Ok(c) => c, Err(_) => return -106 };
        let c_delim = match CString::new(delimiter) { Ok(c) => c, Err(_) => return -106 };
        unsafe { ffi::ez_db_insert(handle, c_data.as_ptr(), rec_count, c_delim.as_ptr()) }
    }

    pub fn row_replace(&self, handle: u64, row_id: u64, data: &str, delimiter: &str) -> i32 {
        let c_data = match CString::new(data) { Ok(c) => c, Err(_) => return -106 };
        let c_delim = match CString::new(delimiter) { Ok(c) => c, Err(_) => return -106 };
        unsafe { ffi::ez_db_row_replace(handle, row_id, c_data.as_ptr(), c_delim.as_ptr()) }
    }

    pub fn seek_by_tag(&self, handle: u64, tag_name: &str, keys: &[&str]) -> bool {
        let c_tag = match CString::new(tag_name) { Ok(c) => c, Err(_) => return false };
        let c_keys: Vec<CString> = keys.iter().filter_map(|&k| CString::new(k).ok()).collect();
        // 陣列末端補上 null 作為 Sentinel 標記
        let mut ptrs: Vec<*const c_void> = c_keys.iter().map(|k| k.as_ptr() as *const c_void).collect();
        ptrs.push(std::ptr::null());
        unsafe { ffi::ez_db_seek_by_tag_array(handle, c_tag.as_ptr(), ptrs.as_ptr()) == 0 }
    }

    pub fn commit(&self, handle: u64) -> i32 {
        unsafe { ffi::ez_db_commit(handle) }
    }

    pub fn create_index(&self, handle: u64, tag_name: &str, fields_str: &str, is_unique: bool) -> i32 {
        let c_tag = match CString::new(tag_name) { Ok(c) => c, Err(_) => return -106 };
        let c_fields = match CString::new(fields_str) { Ok(c) => c, Err(_) => return -106 };
        unsafe { ffi::ez_db_create_index(handle, c_tag.as_ptr(), c_fields.as_ptr(), is_unique) }
    }

    // --- Group E: 反射與偵錯工具 ---

    /// Dynamically retrieves the index expression (e.g. "code" or "date+code") for the specified tag.
    /// Supports resolution via tag_id (1~8) and/or tag_name.
    pub fn get_index_key(&self, handle: u64, tag_id: u32, tag_name: Option<&str>) -> Option<String> {
        if handle == 0 {
            return None;
        }

        let mut buf = [0u8; 128];
        let c_tag = tag_name.and_then(|s| CString::new(s).ok());
        let p_tag = c_tag.as_ref().map_or(std::ptr::null(), |c| c.as_ptr());

        let status = unsafe {
            ffi::ez_db_get_index_key(
                handle,
                tag_id,
                p_tag,
                buf.as_mut_ptr() as *mut c_char,
                buf.len() as u32,
            )
        };

        if status == 0 {
            let nul_pos = buf.iter().position(|&b| b == 0).unwrap_or(buf.len());
            let s = String::from_utf8_lossy(&buf[..nul_pos]).trim().to_string();
            if !s.is_empty() {
                return Some(s);
            }
        }
        None
    }
    
    pub fn dump_workarea(&self, handle: u64) {
        unsafe { ffi::ez_db_dump_workarea(handle) };
    }
}