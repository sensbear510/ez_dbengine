/* ===================================================================================  */
/*  File : ez_engine.h                                                                  */
/*  Desc : The ez_dbengine API  header                                                  */
/* -----------------------------------------------------------------------------------  */
/*  EZ_ENGINE API HEADERE                                                               */
/* -----------------------------------------------------------------------------------  */

#pragma once

#include <stdint.h>
#include <stdbool.h>
#include <ctype.h>
#include "ez_def.h"   /* Contains physical status codes and EZ_STATUS definitions */

/* --- [1] DLL Export and Cross-Platform Definitions --- */
#ifdef _WIN32
    #ifdef EZ_ENGINE_EXPORTS
        #define EZ_API __declspec(dllexport)
    #else
        #define EZ_API __declspec(dllimport)
    #endif

    /**
     * External WorkArea Access
     * Exposes the global WorkArea array to external modules when not in the core C file.
     */
    #ifndef EZ_ENGINE_CORE_C
        extern EZ_WORKAREA *g_workareas;        
    #endif
#else
    #define EZ_API 
#endif

/* --- [2] Global I/O Mode & Defense Macros --- */
EZ_API extern s32 g_io_final_mode;

/**
 * EZ_IO_CHECK_READY
 * Physical defense macro: Blocks any API call if the engine is not healthy.
 */
#define EZ_IO_CHECK_READY() { \
    if (g_io_final_mode < 0) { \
        return (g_io_final_mode == -2) ? EZ_ERR_IO_FATAL : EZ_ERR_IO_INIT; \
    } \
}

/* ===================================================================== */
/* Group A: Lifecycle and Schema Maintenance                             */
/* ===================================================================== */

/* Unified Creation: Synchronously builds EBF (4K Header) and default schema layout */
EZ_API EZ_STATUS ez_db_create(ez_pcstr path, const EZ_FIELD_NODE* map);

/* Schema Evolution: Alters table structure and migrates data to a new map definition */
EZ_API EZ_STATUS ez_db_alter(const u64 h, ez_pcstr path, EZ_FIELD_NODE* new_map, EZ_MIGRATE_REPORT* report);

/* Recovery: Reconstructs database headers and indexes from existing data files */
EZ_API EZ_STATUS ez_db_reconstruct(const u64 h, ez_pcstr path, EZ_MIGRATE_REPORT* report);

/* Open / Use Mechanism: Opens a file and loads FDT into WorkArea for self-describing metadata */
EZ_API u64       ez_db_use(ez_pcstr path, EZ_MIGRATE_REPORT* report);
EZ_API u64       ez_db_open(ez_pcstr path, EZ_MIGRATE_REPORT* report);

/* Cleanup and Context Management */
EZ_API EZ_STATUS ez_db_close(const u64 h);
EZ_API s32       ez_db_close_all(ez_void);

/* Set Auto-Vacuum threshold value */
EZ_API void      ez_db_set_vacuum(const u64 h, f32 threshold, u32 min_deleted);

/* Safe filename isolated extractor */
EZ_API void      ez_db_get_name_from_path(ez_pcstr path, ez_pchar out_name, u32 max_len);

/* ===================================================================== */
/* Group B: Dual-Track Navigation and State (Lock-Free TLS Engine)       */
/* 💡 tag_id (1~8) takes precedence; if 0, matches tag_name; if both     */
/*    0 and NULL/"", operates in Natural physical record sequence.       */
/* ===================================================================== */

EZ_API EZ_STATUS ez_db_gotop(const u64 h, u32 tag_id, ez_pcstr tag_name);
EZ_API EZ_STATUS ez_db_gobottom(const u64 h, u32 tag_id, ez_pcstr tag_name);
EZ_API EZ_STATUS ez_db_skip(const u64 h, u32 tag_id, ez_pcstr tag_name, s32 n);
EZ_API EZ_STATUS ez_db_goto(const u64 h, u32 tag_id, ez_pcstr tag_name, u64 recno);

EZ_API ez_bool   ez_db_is_eof(const u64 h, u32 tag_id, ez_pcstr tag_name);        
EZ_API ez_bool   ez_db_is_bof(const u64 h, u32 tag_id, ez_pcstr tag_name);
EZ_API ez_bool   ez_db_is_found(const u64 h, u32 tag_id, ez_pcstr tag_name);      

/* Returns the mapped physical RowID of the current TLS track cursor */
EZ_API s64       ez_db_recno(const u64 h, u32 tag_id, ez_pcstr tag_name);      
EZ_API s64       ez_db_lastrec(const u64 h, u32 tag_id, ez_pcstr tag_name);
EZ_API u32       ez_db_recsize(const u64 h);
EZ_API u64       ez_db_record_count(const u64 h);

/* ===================================================================== */
/* Group C: Data Retrieval & Modification (Atomic & Lock-Free)           */
/* ===================================================================== */

/* Low-level Record Access: extracts data according to tag sequence and advances track cursor */
EZ_API EZ_STATUS ez_db_get_record(
    const u64 h, 
    u32 tag_id, 
    ez_pcstr tag_name, 
    ez_pvoid buffer, 
    u32 buffer_size, 
    ez_bool include_deleted
);

/* Vectorized / Paginated Batch Retrieval */
EZ_API EZ_STATUS ez_db_get_record_vector(
    const u64 h, 
    u32 tag_id, 
    ez_pcstr tag_name, 
    ez_pvoid out_struct_array, 
    u32* p_count, 
    u32 struct_size, 
    ez_bool strip_str, 
    ez_bool include_deleted
);

EZ_API EZ_STATUS _ez_internal_seek_core(
    EZ_WORKAREA* wa, 
    u64 h,
    EZ_TAG_INFO* tag, 
    ez_pvoid hIdx, 
    const ez_char* search_key
);

EZ_API EZ_STATUS ez_db_seek_by_tag(const u64 h, ez_pcstr tag_name, ...);
EZ_API EZ_STATUS ez_db_seek_by_tag_id(const u64 h, u32 tag_id, ...);

/* Pointer-array Search APIs for FFI / High-level bindings */
EZ_API EZ_STATUS ez_db_seek_by_tag_array(const u64 h, ez_pcstr tag_name, ez_pcvoid* values);
EZ_API EZ_STATUS ez_db_seek_by_tag_id_array(const u64 h, u32 tag_id, ez_pcvoid* values);

/* Physical Sequence Scanner: Operates purely on Natural Order without index */
EZ_API EZ_STATUS ez_db_locate(const u64 h, ez_pcstr fieldname, ez_pcvoid target_value, ez_bool partial_match);

/* Modern Record Handling: Atomic data append / insert */
EZ_API EZ_STATUS ez_db_append(const u64 h, ez_pcvoid data, u32 rec_count, ez_pstr delim);
EZ_API EZ_STATUS ez_db_insert(const u64 h, ez_pcvoid data, u32 rec_count, ez_pstr delim);

/* In-place Record & Field Updates: Decoupled via explicit row_id */
EZ_API EZ_STATUS ez_db_row_replace(const u64 h, u64 row_id, ez_pcvoid data, ez_pcstr delim);
EZ_API EZ_STATUS ez_db_replace(const u64 h, u64 row_id, ez_pcstr fieldname, ez_pcvoid val);

/* Logical Deletions and Lifecycle Controls */
EZ_API ez_bool   ez_db_is_deleted(const u64 h, u64 row_id);
EZ_API EZ_STATUS ez_db_delete(const u64 h, u64 row_id);
EZ_API EZ_STATUS ez_db_recall(const u64 h, u64 row_id);
EZ_API EZ_STATUS ez_db_pack(const u64 h, ez_pcstr path);
EZ_API EZ_STATUS ez_db_zap(u64 h);
EZ_API EZ_STATUS ez_db_commit(const u64 h);           

/* BLOB Side-Channel Extraction */
EZ_API EZ_STATUS ez_db_get_blob_data(const u64 h, const EZ_BLOB_PTR* blob_ptr, ez_pvoid out_buf, u32 out_buf_size);

/* ===================================================================== */
/* Group D: Index Management & Tag Maintenance                           */
/* ===================================================================== */

EZ_API EZ_STATUS ez_db_create_index(const u64 h, ez_pcstr tag_name, ez_pcstr fields_str, ez_bool is_unique);
EZ_API s32       ez_db_mount_index(const u64 h, ez_pcstr edx_path, u32 slot_id);
EZ_API EZ_STATUS ez_db_purge_duplicates(const u64 h, u32 tag_id, u64 keep_row_id);
EZ_API EZ_STATUS ez_db_extract_duplicates(const u64 h, u32 tag_id);
EZ_API void      _internal_build_node(EZ_TAG_INFO* tag, EZ_RECORD* p_rec, ez_pchar p_node);
EZ_API EZ_STATUS ez_db_build_search_key(const u64 h, u32 tag_id, ez_pcstr tag_name, ez_pchar out_key_buf, ...);
//EZ_API EZ_STATUS ez_db_get_batch_alloc(const u64 h, u32 tag_id, ez_pcstr tag_name, EZ_RESULT_SET* out_set, ez_pcvoid key);
//EZ_API ez_void   ez_db_free_result(EZ_RESULT_SET* set);

/* ===================================================================== */
/* Group E: Reflection & Utilities                                       */
/* ===================================================================== */

EZ_API EZ_STATUS            ez_db_get_field_names(const u64 h, ez_pchar out_buf, u32 buf_size, ez_pcstr delim);
EZ_API const EZ_FIELD_NODE* ez_db_get_fdt(const u64 h);
EZ_API const EZ_TAG_INFO*   ez_db_get_tags(const u64 h);
EZ_API u64                  ez_db_get_delete_count(const u64 h);
EZ_API void                 ez_db_dump_record(const u64 h, ez_pcvoid record_payload);
EZ_API void                 ez_db_dump_workarea(const u64 h);

/* Low-level Raw Write Access */
EZ_API EZ_STATUS _platform_write_raw(ez_pvoid hFile, u64 offset, ez_pcvoid buf, u32 len);

/* ===================================================================== */
/* Group F: Event Observation & Telemetry                                */
/* ===================================================================== */

typedef enum {
    EZ_EV_READ_COMPLETE  = 1,
    EZ_EV_WRITE_COMPLETE = 2
} EZ_EVENT_TYPE;

typedef void (*EZ_STATE_OBSERVER)(u32 slot, u32 event, u64 offset, u32 len, ez_pcvoid buffer);

EZ_API void ez_set_state_observer(EZ_STATE_OBSERVER cb);

/* ===================================================================== */
/* Group G: Field Deserialization Helpers (MSVC/GCC/Clang Compatible)    */
/* ===================================================================== */

#define EXTRACT_STR(out_buf, offset, len) do { \
    memset((out_buf), 0, (len) + 1); \
    memcpy((out_buf), raw_ebf + (offset), (len)); \
} while(0)

static inline int ez_extract_int_impl(const char *raw_ebf, size_t offset, size_t len) {
    char tmp[64] = {0};
    size_t copy_len = (len < 63) ? len : 63;
    memcpy(tmp, raw_ebf + offset, copy_len);
    return atoi(tmp);
}

static inline double ez_extract_num_impl(const char *raw_ebf, size_t offset, size_t len) {
    char tmp[64] = {0};
    size_t copy_len = (len < 63) ? len : 63;
    memcpy(tmp, raw_ebf + offset, copy_len);
    return atof(tmp);
}

static inline long long ez_extract_long_impl(const char *raw_ebf, size_t offset, size_t len) {
    char tmp[64] = {0};
    size_t copy_len = (len < 63) ? len : 63;
    memcpy(tmp, raw_ebf + offset, copy_len);
    return atoll(tmp);
}

#define EXTRACT_INT(offset, len)  ez_extract_int_impl((const char *)(raw_ebf), (offset), (len))
#define EXTRACT_NUM(offset, len)  ez_extract_num_impl((const char *)(raw_ebf), (offset), (len))
#define EXTRACT_LONG(offset, len) ez_extract_long_impl((const char *)(raw_ebf), (offset), (len))

static inline uint64_t _ez_extract_bin_helper(const char *buf, size_t len) {
    uint64_t val = 0;
    for (size_t i = 0; i < len && i < 8; i++) {
        val = (val << 8) | ((uint8_t)buf[i]);
    }
    return val;
}

#define EXTRACT_BIN(offset, len) \
    _ez_extract_bin_helper((const char *)(raw_ebf) + (offset), (len))

#define EXTRACT_B(out_buf, offset, len) do { \
    memcpy((out_buf), (const char *)(raw_ebf) + (offset), (len)); \
} while(0)

/* ====================================================================
 * Error Diagnostics & Introspection API
 * ==================================================================== */

/**
 * ez_errstr
 * Converts any EZ_STATUS or EZ_RUNTIME_STATUS code into a static, 
 * human-readable UTF-8 error description.
 * Safe for direct FFI consumption (Flutter/Rust/C#/Node.js).
 */
EZ_API ez_pcstr ez_errstr(EZ_STATUS status);

/**
 * get last operation status message
 */
EZ_API ez_pcstr ez_last_error(void);