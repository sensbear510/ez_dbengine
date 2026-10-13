/* =================================================================================
 * 📁 FILE: ez_dbengine.cpp
 * ---------------------------------------------------------------------------------
 * Full C++ Implementation of Stateless Singleton Driver
 * =================================================================================
 */

#include "ez_dbengine.hpp"
#include <cstring>

namespace ez {

// --- Group A: Lifecycle and Schema Maintenance ---

EZ_STATUS EzDBEngine::create_table(const std::string& path, const std::vector<EZ_FIELD_NODE>& fields) {
    if (fields.empty()) return EZ_ERR_PARAM;
    return ez_db_create(path.c_str(), fields.data());
}

EZ_STATUS EzDBEngine::alter(u64 handle, const std::string& path, std::vector<EZ_FIELD_NODE>& new_map, EZ_MIGRATE_REPORT* report) {
    if (handle == 0 || new_map.empty()) return EZ_ERR_PARAM;
    return ez_db_alter(handle, path.c_str(), new_map.data(), report);
}

EZ_STATUS EzDBEngine::reconstruct(u64 handle, const std::string& path, EZ_MIGRATE_REPORT* report) {
    if (handle == 0) return EZ_ERR_PARAM;
    return ez_db_reconstruct(handle, path.c_str(), report);
}

u64 EzDBEngine::use(const std::string& path, EZ_MIGRATE_REPORT* report) {
    EZ_MIGRATE_REPORT local_report{};
    EZ_MIGRATE_REPORT* p_report = report ? report : &local_report;
    u64 h = ez_db_use(path.c_str(), p_report);
    if (h == 0) {
        throw std::runtime_error("EzDBEngine::use failed: " + path + " | " + std::string(p_report->message));
    }
    return h;
}

u64 EzDBEngine::open(const std::string& path, EZ_MIGRATE_REPORT* report) {
    return use(path, report);
}

EZ_STATUS EzDBEngine::close(u64 handle) noexcept {
    if (handle == 0) return EZ_ERR_INVALID_HANDLE;
    return ez_db_close(handle);
}

s32 EzDBEngine::close_all() noexcept {
    return ez_db_close_all();
}

void EzDBEngine::set_vacuum(u64 handle, float threshold, uint32_t min_deleted) {
    if (handle != 0) {
        ez_db_set_vacuum(handle, threshold, min_deleted);
    }
}

std::string EzDBEngine::get_name_from_path(const std::string& path, uint32_t max_len) {
    std::vector<char> buf(max_len, '\0');
    ez_db_get_name_from_path(path.c_str(), buf.data(), max_len);
    return std::string(buf.data());
}

// --- Group B: Dual-Track Navigation and State ---

EZ_STATUS EzDBEngine::go_top(u64 handle, uint32_t tag_id, const std::string& tag_name) {
    if (handle == 0) return EZ_ERR_INVALID_HANDLE;
    return ez_db_gotop(handle, tag_id, tag_name.empty() ? nullptr : tag_name.c_str());
}

EZ_STATUS EzDBEngine::go_bottom(u64 handle, uint32_t tag_id, const std::string& tag_name) {
    if (handle == 0) return EZ_ERR_INVALID_HANDLE;
    return ez_db_gobottom(handle, tag_id, tag_name.empty() ? nullptr : tag_name.c_str());
}

EZ_STATUS EzDBEngine::skip(u64 handle, int32_t step, uint32_t tag_id, const std::string& tag_name) {
    if (handle == 0) return EZ_ERR_INVALID_HANDLE;
    return ez_db_skip(handle, tag_id, tag_name.empty() ? nullptr : tag_name.c_str(), step);
}

EZ_STATUS EzDBEngine::go_to(u64 handle, uint64_t recno, uint32_t tag_id, const std::string& tag_name) {
    if (handle == 0) return EZ_ERR_INVALID_HANDLE;
    return ez_db_goto(handle, tag_id, tag_name.empty() ? nullptr : tag_name.c_str(), recno);
}

bool EzDBEngine::is_eof(u64 handle, uint32_t tag_id, const std::string& tag_name) const {
    if (handle == 0) return true;
    return ez_db_is_eof(handle, tag_id, tag_name.empty() ? nullptr : tag_name.c_str());
}

bool EzDBEngine::is_bof(u64 handle, uint32_t tag_id, const std::string& tag_name) const {
    if (handle == 0) return true;
    return ez_db_is_bof(handle, tag_id, tag_name.empty() ? nullptr : tag_name.c_str());
}

bool EzDBEngine::is_found(u64 handle, uint32_t tag_id, const std::string& tag_name) const {
    if (handle == 0) return false;
    return ez_db_is_found(handle, tag_id, tag_name.empty() ? nullptr : tag_name.c_str());
}

uint64_t EzDBEngine::get_recno(u64 handle, uint32_t tag_id, const std::string& tag_name) const {
    if (handle == 0) return 0;
    int64_t r = ez_db_recno(handle, tag_id, tag_name.empty() ? nullptr : tag_name.c_str());
    return r > 0 ? static_cast<uint64_t>(r) : 0;
}

uint64_t EzDBEngine::get_lastrec(u64 handle, uint32_t tag_id, const std::string& tag_name) const {
    if (handle == 0) return 0;
    int64_t r = ez_db_lastrec(handle, tag_id, tag_name.empty() ? nullptr : tag_name.c_str());
    return r > 0 ? static_cast<uint64_t>(r) : 0;
}

uint32_t EzDBEngine::get_record_size(u64 handle) const {
    return handle != 0 ? ez_db_recsize(handle) : 0;
}

uint64_t EzDBEngine::get_record_count(u64 handle) const {
    return handle != 0 ? ez_db_record_count(handle) : 0;
}

// --- Group C: Data Access and Atomic Mutations ---

EZ_STATUS EzDBEngine::get_record(u64 handle, void* out_buffer, uint32_t buffer_size, bool include_deleted, uint32_t tag_id, const std::string& tag_name) {
    if (handle == 0) return EZ_ERR_INVALID_HANDLE;
    if (!out_buffer) return EZ_ERR_PARAM;
    return ez_db_get_record(handle, tag_id, tag_name.empty() ? nullptr : tag_name.c_str(), out_buffer, buffer_size, include_deleted);
}

EZ_STATUS EzDBEngine::get_record_vector(u64 handle, void* out_struct_array, uint32_t* p_count, uint32_t struct_size, bool strip_str, bool include_deleted, uint32_t tag_id, const std::string& tag_name) {
    if (handle == 0) return EZ_ERR_INVALID_HANDLE;
    if (!out_struct_array || !p_count) return EZ_ERR_PARAM;
    return ez_db_get_record_vector(handle, tag_id, tag_name.empty() ? nullptr : tag_name.c_str(), out_struct_array, p_count, struct_size, strip_str, include_deleted);
}

EZ_STATUS EzDBEngine::seek_by_tag(u64 handle, const std::string& tag_name, const std::string& key_value) {
    if (handle == 0) return EZ_ERR_INVALID_HANDLE;
    if (tag_name.empty()) return EZ_ERR_PARAM;
    return ez_db_seek_by_tag(handle, tag_name.c_str(), key_value.c_str());
}

EZ_STATUS EzDBEngine::seek_by_tag_id(u64 handle, uint32_t tag_id, const std::string& key_value) {
    if (handle == 0) return EZ_ERR_INVALID_HANDLE;
    if (tag_id == 0) return EZ_ERR_PARAM;
    return ez_db_seek_by_tag_id(handle, tag_id, key_value.c_str());
}

EZ_STATUS EzDBEngine::seek_by_tag_array(u64 handle, const std::string& tag_name, const void** values) {
    if (handle == 0) return EZ_ERR_INVALID_HANDLE;
    if (tag_name.empty() || !values) return EZ_ERR_PARAM;
    return ez_db_seek_by_tag_array(handle, tag_name.c_str(), const_cast<ez_pcvoid*>(values));
}

EZ_STATUS EzDBEngine::seek_by_tag_id_array(u64 handle, uint32_t tag_id, const void** values) {
    if (handle == 0) return EZ_ERR_INVALID_HANDLE;
    if (tag_id == 0 || !values) return EZ_ERR_PARAM;
    return ez_db_seek_by_tag_id_array(handle, tag_id, const_cast<ez_pcvoid*>(values));
}

EZ_STATUS EzDBEngine::locate(u64 handle, const std::string& field_name, const void* target_value, bool partial_match) {
    if (handle == 0) return EZ_ERR_INVALID_HANDLE;
    if (field_name.empty() || !target_value) return EZ_ERR_PARAM;
    return ez_db_locate(handle, field_name.c_str(), target_value, partial_match);
}

EZ_STATUS EzDBEngine::append(u64 handle, const void* data_payload, uint32_t rec_count, const char* delim) {
    if (handle == 0) return EZ_ERR_INVALID_HANDLE;
    if (!data_payload) return EZ_ERR_PARAM;
    return ez_db_append(handle, data_payload, rec_count, const_cast<ez_pstr>(reinterpret_cast<const ez_u8*>(delim)));
}

EZ_STATUS EzDBEngine::insert(u64 handle, const void* data_payload, uint32_t rec_count, const char* delim) {
    if (handle == 0) return EZ_ERR_INVALID_HANDLE;
    if (!data_payload) return EZ_ERR_PARAM;
    return ez_db_insert(handle, data_payload, rec_count, const_cast<ez_pstr>(reinterpret_cast<const ez_u8*>(delim)));
}

EZ_STATUS EzDBEngine::row_replace(u64 handle, uint64_t row_id, const void* data_payload, const char* delim) {
    if (handle == 0) return EZ_ERR_INVALID_HANDLE;
    if (!data_payload || row_id == 0) return EZ_ERR_PARAM;
    return ez_db_row_replace(handle, row_id, data_payload, delim);
}

EZ_STATUS EzDBEngine::replace(u64 handle, uint64_t row_id, const std::string& field_name, const void* value_ptr) {
    if (handle == 0) return EZ_ERR_INVALID_HANDLE;
    if (field_name.empty() || row_id == 0 || !value_ptr) return EZ_ERR_PARAM;
    return ez_db_replace(handle, row_id, field_name.c_str(), value_ptr);
}

bool EzDBEngine::is_deleted(u64 handle, uint64_t row_id) const {
    if (handle == 0 || row_id == 0) return false;
    return ez_db_is_deleted(handle, row_id);
}

EZ_STATUS EzDBEngine::delete_record(u64 handle, uint64_t row_id) {
    if (handle == 0 || row_id == 0) return EZ_ERR_INVALID_HANDLE;
    return ez_db_delete(handle, row_id);
}

EZ_STATUS EzDBEngine::recall_record(u64 handle, uint64_t row_id) {
    if (handle == 0 || row_id == 0) return EZ_ERR_INVALID_HANDLE;
    return ez_db_recall(handle, row_id);
}

EZ_STATUS EzDBEngine::pack(u64 handle, const std::string& temp_path) {
    if (handle == 0) return EZ_ERR_INVALID_HANDLE;
    return ez_db_pack(handle, temp_path.empty() ? nullptr : temp_path.c_str());
}

EZ_STATUS EzDBEngine::zap(u64 handle) {
    if (handle == 0) return EZ_ERR_INVALID_HANDLE;
    return ez_db_zap(handle);
}

EZ_STATUS EzDBEngine::commit(u64 handle) {
    if (handle == 0) return EZ_ERR_INVALID_HANDLE;
    return ez_db_commit(handle);
}

EZ_STATUS EzDBEngine::get_blob_data(u64 handle, const EZ_BLOB_PTR* blob_ptr, void* out_buf, uint32_t out_buf_size) {
    if (handle == 0) return EZ_ERR_INVALID_HANDLE;
    if (!blob_ptr || !out_buf) return EZ_ERR_PARAM;
    return ez_db_get_blob_data(handle, blob_ptr, out_buf, out_buf_size);
}

// --- Group D: Index Maintenance ---

EZ_STATUS EzDBEngine::create_index(u64 handle, const std::string& tag_name, const std::string& fields_expr, bool is_unique) {
    if (handle == 0) return EZ_ERR_INVALID_HANDLE;
    if (tag_name.empty() || fields_expr.empty()) return EZ_ERR_PARAM;
    return ez_db_create_index(handle, tag_name.c_str(), fields_expr.c_str(), is_unique);
}

s32 EzDBEngine::mount_index(u64 handle, const std::string& edx_path, uint32_t slot_id) {
    if (handle == 0 || edx_path.empty()) return -1;
    return ez_db_mount_index(handle, edx_path.c_str(), slot_id);
}

EZ_STATUS EzDBEngine::purge_duplicates(u64 handle, uint32_t tag_id, uint64_t keep_row_id) {
    if (handle == 0) return EZ_ERR_INVALID_HANDLE;
    if (tag_id == 0) return EZ_ERR_PARAM;
    return ez_db_purge_duplicates(handle, tag_id, keep_row_id);
}

EZ_STATUS EzDBEngine::extract_duplicates(u64 handle, uint32_t tag_id) {
    if (handle == 0) return EZ_ERR_INVALID_HANDLE;
    if (tag_id == 0) return EZ_ERR_PARAM;
    return ez_db_extract_duplicates(handle, tag_id);
}

// --- Group E: Reflection and Diagnostics ---

std::string EzDBEngine::get_field_names(u64 handle, const std::string& delim, uint32_t buf_size) {
    if (handle == 0) return "";
    std::vector<char> buf(buf_size, '\0');
    if (ez_db_get_field_names(handle, buf.data(), buf_size, delim.c_str()) == EZ_SUCCESS) {
        return std::string(buf.data());
    }
    return "";
}

std::vector<EZ_FIELD_NODE> EzDBEngine::get_fdt(u64 handle) const {
    std::vector<EZ_FIELD_NODE> fields;
    if (handle == 0) return fields;

    const EZ_FIELD_NODE* pFdt = ez_db_get_fdt(handle);
    if (!pFdt) return fields;

    for (size_t i = 0; i < EZ_MAX_FDT_NODES; ++i) {
        if (pFdt[i].name[0] == '\0') break;
        fields.push_back(pFdt[i]);
    }
    return fields;
}

std::vector<EZ_TAG_INFO> EzDBEngine::get_tags(u64 handle) const {
    std::vector<EZ_TAG_INFO> tags;
    if (handle == 0) return tags;

    const EZ_TAG_INFO* pTags = ez_db_get_tags(handle);
    if (!pTags) return tags;

    for (size_t i = 0; i < EZ_MAX_TAGS; ++i) {
        if (pTags[i].tag_name[0] == '\0') break;
        tags.push_back(pTags[i]);
    }
    return tags;
}

uint64_t EzDBEngine::get_delete_count(u64 handle) const {
    return handle != 0 ? ez_db_get_delete_count(handle) : 0;
}

void EzDBEngine::dump_record(u64 handle, const void* record_payload) {
    if (handle != 0 && record_payload) {
        ez_db_dump_record(handle, const_cast<void*>(record_payload));
    }
}

void EzDBEngine::dump_workarea(u64 handle) {
    if (handle != 0) {
        ez_db_dump_workarea(handle);
    }
}

EZ_STATUS EzDBEngine::platform_write_raw(void* hFile, uint64_t offset, const void* buf, uint32_t len) {
    return _platform_write_raw(hFile, offset, buf, len);
}

// --- Error Diagnostic Subsystem ---

std::string EzDBEngine::errstr(EZ_STATUS status) const noexcept {
    ez_pcstr str = ::ez_errstr(status);
    return str ? std::string(str) : "Unknown engine error";
}

std::string EzDBEngine::last_error() const noexcept {
    ez_pcstr str = ::ez_last_error();
    return str ? std::string(str) : "";
}

std::string EzDBEngine::get_detailed_error(EZ_STATUS status) const {
    std::string dynamic_err = last_error();
    std::string static_err = errstr(status);
    if (!dynamic_err.empty()) {
        return "[" + static_err + "] " + dynamic_err + " (Code: " + std::to_string(status) + ")";
    }
    return "[" + static_err + "] (Code: " + std::to_string(status) + ")";
}

// --- Group F: State Observer ---

void EzDBEngine::set_state_observer(EZ_STATE_OBSERVER cb) {
    ez_set_state_observer(cb);
}

// --- Relation View Subsystem (ez_relation_mgr.h) ---

bool EzDBEngine::relation_mgr_init() {
    return ez_rl_mgr_init() == EZ_SUCCESS;
}

bool EzDBEngine::relation_mgr_cleanup() {
    return ez_rl_mgr_cleanup() == EZ_SUCCESS;
}

u64 EzDBEngine::relation_build_view(const EZ_RL_VIEW_DESC& desc) {
    return ez_rl_build_view(&desc);
}

bool EzDBEngine::relation_destroy_view(u64 h_rel) {
    return ez_rl_destroy_view(h_rel) == EZ_SUCCESS;
}

u64 EzDBEngine::relation_register(void* rel) {
    return ez_rl_register(rel);
}

void* EzDBEngine::relation_get_table(u64 h_rel) {
    return _ez_get_relation_table(h_rel);
}

bool EzDBEngine::relation_get_record_vector(EZ_RELATION_TABLE* rel, uint8_t* out_buffer, uint32_t request_count, uint32_t* actual_count) {
    if (!rel || !out_buffer || !actual_count) return false;
    return ez_rl_get_record_vector(rel, out_buffer, request_count, actual_count) == EZ_SUCCESS;
}

bool EzDBEngine::relation_save_view_file(const EZ_RL_VIEW_DESC& desc, const std::string& erl_path) {
    return ez_rl_save_view_file(&desc, erl_path.c_str()) == EZ_SUCCESS;
}

u64 EzDBEngine::relation_load_view_file(const std::string& erl_path, const std::vector<u64>& ebf_handles) {
    if (ebf_handles.empty()) return 0;
    return ez_rl_load_view_file(erl_path.c_str(), ebf_handles.data(), static_cast<u16>(ebf_handles.size()));
}

// --- Quantization and Vector Rotation (ez_quant.h) ---

bool EzDBEngine::quant_compress_f32_4bit(const float* in_vec, uint32_t dim, uint8_t* out_packed, float* out_min, float* out_max) {
    return ez_quant_compress_f32_4bit(in_vec, dim, out_packed, out_min, out_max) == EZ_SUCCESS;
}

bool EzDBEngine::quant_decompress_4bit_f32(const uint8_t* in_packed, float min_val, float max_val, uint32_t dim, float* out_vec) {
    return ez_quant_decompress_4bit_f32(in_packed, min_val, max_val, dim, out_vec) == EZ_SUCCESS;
}

} // namespace ez