/* =================================================================================
 * 📁 FILE: ez_dbengine.hpp
 * ---------------------------------------------------------------------------------
 * Full C++17/C++20 High-Concurrency Stateless Singleton Driver for ez_dbengine.dll
 * =================================================================================
 */

#pragma once

#include <string>
#include <vector>
#include <memory>
#include <cstdint>
#include <stdexcept>

extern "C" {
    #include "../../source/ez_def.h"
    #include "../../source/ez_engine.h"
    #include "../../source/ez_relation_mgr.h"
    #include "../../source/ez_quant.h"
}

namespace ez {

class EzDBEngine {
private:
    EzDBEngine() = default;
    ~EzDBEngine() = default;

public:
    EzDBEngine(const EzDBEngine&) = delete;
    EzDBEngine& operator=(const EzDBEngine&) = delete;
    EzDBEngine(EzDBEngine&&) = delete;
    EzDBEngine& operator=(EzDBEngine&&) = delete;

    // 全域執行緒安全單例 (Meyers' Singleton)
    static EzDBEngine& get_instance() {
        static EzDBEngine instance;
        return instance;
    }

    // =========================================================================
    // Group A: 生命週期與結構維護 (Lifecycle & Schema Maintenance)
    // =========================================================================
    EZ_STATUS create_table(const std::string& path, const std::vector<EZ_FIELD_NODE>& fields);
    EZ_STATUS alter(u64 handle, const std::string& path, std::vector<EZ_FIELD_NODE>& new_map, EZ_MIGRATE_REPORT* report);
    EZ_STATUS reconstruct(u64 handle, const std::string& path, EZ_MIGRATE_REPORT* report);
    u64 use(const std::string& path, EZ_MIGRATE_REPORT* report = nullptr);
    u64 open(const std::string& path, EZ_MIGRATE_REPORT* report = nullptr);
    EZ_STATUS close(u64 handle) noexcept;
    s32 close_all() noexcept;
    void set_vacuum(u64 handle, float threshold, uint32_t min_deleted);
    std::string get_name_from_path(const std::string& path, uint32_t max_len = 64);

    // =========================================================================
    // Group B: 雙軌導航與狀態 (Dual-Track Navigation & Status)
    // =========================================================================
    EZ_STATUS go_top(u64 handle, uint32_t tag_id = 0, const std::string& tag_name = "");
    EZ_STATUS go_bottom(u64 handle, uint32_t tag_id = 0, const std::string& tag_name = "");
    EZ_STATUS skip(u64 handle, int32_t step = 1, uint32_t tag_id = 0, const std::string& tag_name = "");
    EZ_STATUS go_to(u64 handle, uint64_t recno, uint32_t tag_id = 0, const std::string& tag_name = "");

    bool is_eof(u64 handle, uint32_t tag_id = 0, const std::string& tag_name = "") const;
    bool is_bof(u64 handle, uint32_t tag_id = 0, const std::string& tag_name = "") const;
    bool is_found(u64 handle, uint32_t tag_id = 0, const std::string& tag_name = "") const;

    uint64_t get_recno(u64 handle, uint32_t tag_id = 0, const std::string& tag_name = "") const;
    uint64_t get_lastrec(u64 handle, uint32_t tag_id = 0, const std::string& tag_name = "") const;
    uint32_t get_record_size(u64 handle) const;
    uint64_t get_record_count(u64 handle) const;

    // =========================================================================
    // Group C: 資料存取與原子更新 (Data Retrieval & In-place Atomic Updates)
    // =========================================================================
    EZ_STATUS get_record(u64 handle, void* out_buffer, uint32_t buffer_size, bool include_deleted = false, uint32_t tag_id = 0, const std::string& tag_name = "");
    EZ_STATUS get_record_vector(u64 handle, void* out_struct_array, uint32_t* p_count, uint32_t struct_size, bool strip_str = false, bool include_deleted = false, uint32_t tag_id = 0, const std::string& tag_name = "");
    
    EZ_STATUS seek_by_tag(u64 handle, const std::string& tag_name, const std::string& key_value);
    EZ_STATUS seek_by_tag_id(u64 handle, uint32_t tag_id, const std::string& key_value);
    EZ_STATUS seek_by_tag_array(u64 handle, const std::string& tag_name, const void** values);
    EZ_STATUS seek_by_tag_id_array(u64 handle, uint32_t tag_id, const void** values);
    EZ_STATUS locate(u64 handle, const std::string& field_name, const void* target_value, bool partial_match = false);

    EZ_STATUS append(u64 handle, const void* data_payload, uint32_t rec_count = 1, const char* delim = ",");
    EZ_STATUS insert(u64 handle, const void* data_payload, uint32_t rec_count = 1, const char* delim = ",");
    EZ_STATUS row_replace(u64 handle, uint64_t row_id, const void* data_payload, const char* delim = ",");
    EZ_STATUS replace(u64 handle, uint64_t row_id, const std::string& field_name, const void* value_ptr);

    bool is_deleted(u64 handle, uint64_t row_id) const;
    EZ_STATUS delete_record(u64 handle, uint64_t row_id);
    EZ_STATUS recall_record(u64 handle, uint64_t row_id);
    EZ_STATUS pack(u64 handle, const std::string& temp_path = "");
    EZ_STATUS zap(u64 handle);
    EZ_STATUS commit(u64 handle);
    EZ_STATUS get_blob_data(u64 handle, const EZ_BLOB_PTR* blob_ptr, void* out_buf, uint32_t out_buf_size);

    // =========================================================================
    // Group D: 索引與重複資料處理 (Index & Tag Maintenance)
    // =========================================================================
    EZ_STATUS create_index(u64 handle, const std::string& tag_name, const std::string& fields_expr, bool is_unique = false);
    s32 mount_index(u64 handle, const std::string& edx_path, uint32_t slot_id);
    EZ_STATUS purge_duplicates(u64 handle, uint32_t tag_id, uint64_t keep_row_id = 0);
    EZ_STATUS extract_duplicates(u64 handle, uint32_t tag_id);
        
    // =========================================================================
    // Group E: 反射與偵錯工具 (Reflection & Diagnostics)
    // =========================================================================
    std::string get_field_names(u64 handle, const std::string& delim = ",", uint32_t buf_size = 1024);
    std::vector<EZ_FIELD_NODE> get_fdt(u64 handle) const;
    std::vector<EZ_TAG_INFO> get_tags(u64 handle) const;
    /**
     * Resolves the active index key/expression (e.g. "code" or "date+code") for a specified tag.
     * Supports resolution via tag_id (1~8) and/or tag_name.
     *
     * @param handle   WorkArea fingerprint handle
     * @param tag_id   Tag slot ID (1~8); 0 indicates omitted
     * @param tag_name Tag name string; empty indicates omitted
     * @param buf_size Buffer capacity for key string (default 128 bytes)
     * @return Resolved expression string, or empty string on failure
     */
    std::string get_index_key(u64 handle, uint32_t tag_id = 0, const std::string& tag_name = "", uint32_t buf_size = 128);
    uint64_t get_delete_count(u64 handle) const;
    void dump_record(u64 handle, const void* record_payload);
    void dump_workarea(u64 handle);
    EZ_STATUS platform_write_raw(void* hFile, uint64_t offset, const void* buf, uint32_t len);

    // 錯誤字串與診斷子系統
    std::string errstr(EZ_STATUS status) const noexcept;
    std::string last_error() const noexcept;
    std::string get_detailed_error(EZ_STATUS status) const;

    // =========================================================================
    // Group F: 狀態觀測器 (Event Observation & Telemetry)
    // =========================================================================
    void set_state_observer(EZ_STATE_OBSERVER cb);

    // =========================================================================
    // 關聯檢視子系統 (Relation View Subsystem - ez_relation_mgr.h)
    // =========================================================================
    bool relation_mgr_init();
    bool relation_mgr_cleanup();
    u64 relation_build_view(const EZ_RL_VIEW_DESC& desc);
    bool relation_destroy_view(u64 h_rel);
    u64 relation_register(void* rel);
    void* relation_get_table(u64 h_rel);
    bool relation_get_record_vector(EZ_RELATION_TABLE* rel, uint8_t* out_buffer, uint32_t request_count, uint32_t* actual_count);
    bool relation_save_view_file(const EZ_RL_VIEW_DESC& desc, const std::string& erl_path);
    u64 relation_load_view_file(const std::string& erl_path, const std::vector<u64>& ebf_handles);

    // =========================================================================
    // 量化與向量旋轉 (Quantization & Vector Algebra - ez_quant.h)
    // =========================================================================    
    bool quant_compress_f32_4bit(const float* in_vec, uint32_t dim, uint8_t* out_packed, float* out_min, float* out_max);
    bool quant_decompress_4bit_f32(const uint8_t* in_packed, float min_val, float max_val, uint32_t dim, float* out_vec);
};

} // namespace ez