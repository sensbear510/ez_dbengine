#pragma once

#include <stdint.h>
#include <stdbool.h>
// --- 1. Cross-platform dynamic library loading (DLL / SO) macros and type definitions ---
#ifdef _WIN32
    #include <windows.h>
    typedef HMODULE LibHandle;
    #define LOAD_LIB(path) LoadLibraryA(path)
    #define GET_FUNC(lib, name) (void*)GetProcAddress(lib, name)
    #define CLOSE_LIB(lib) FreeLibrary(lib)
#else
    #include <dlfcn.h>
    #include <dirent.h>
    typedef void* LibHandle;
    #define LOAD_LIB(path) dlopen(path, RTLD_LAZY)
    #define GET_FUNC(lib, name) dlsym(lib, name)
    #define CLOSE_LIB(lib) dlclose(lib)
#endif

#ifdef _WIN32
    #include <direct.h>
    #define CHDIR(path) _chdir(path)
    #define GETCWD(buf, size) _getcwd(buf, size)
#else
    #include <unistd.h>
    #define CHDIR(path) chdir(path)
    #define GETCWD(buf, size) getcwd(buf, size)
#endif

#ifndef _WIN32
    #include <strings.h>
#endif

#include <string.h>

#ifndef _WIN32
    #ifndef _stricmp
        #define _stricmp(s1, s2) strcasecmp(s1, s2)
    #endif
#endif

#include "ez_def.h"
#include "ez_relation_mgr.h"

/* --- 1. Function Pointer Typedefs for Engine APIs --- */

typedef int (*pfn_ez_db_create)(ez_pcstr path, const EZ_FIELD_NODE* map);
typedef int (*pfn_ez_db_alter)(const u64 h, ez_pcstr path, EZ_FIELD_NODE* new_map, EZ_MIGRATE_REPORT* report);
typedef int (*pfn_ez_db_reconstruct)(const u64 h, ez_pcstr path, EZ_MIGRATE_REPORT* report);
typedef u64 (*pfn_ez_db_use)(ez_pcstr path, EZ_MIGRATE_REPORT* report);
typedef u64 (*pfn_ez_db_open)(ez_pcstr path, EZ_MIGRATE_REPORT* report);

typedef int (*pfn_ez_db_close)(const u64 h);
typedef int (*pfn_ez_db_close_all)(void);
typedef void (*pfn_ez_db_set_vacuum)(const u64 h, f32 threshold, u32 min_deleted);
typedef void (*pfn_ez_db_get_name_from_path)(ez_pcstr path, ez_pchar out_name, u32 max_len);

/* Group B: Navigation and State */
typedef int (*pfn_ez_db_gotop)(const u64 h, u32 tag_id, ez_pcstr tag_name);
typedef int (*pfn_ez_db_gobottom)(const u64 h, u32 tag_id, ez_pcstr tag_name);
typedef int (*pfn_ez_db_skip)(const u64 h, u32 tag_id, ez_pcstr tag_name, s32 n);
typedef ez_bool (*pfn_ez_db_is_eof)(const u64 h, u32 tag_id, ez_pcstr tag_name);
typedef ez_bool (*pfn_ez_db_is_bof)(const u64 h, u32 tag_id, ez_pcstr tag_name);
typedef ez_bool (*pfn_ez_db_is_found)(const u64 h, u32 tag_id, ez_pcstr tag_name);
typedef s64 (*pfn_ez_db_recno)(const u64 h, u32 tag_id, ez_pcstr tag_name);
typedef s64 (*pfn_ez_db_lastrec)(const u64 h, u32 tag_id, ez_pcstr tag_name);
typedef int (*pfn_ez_db_goto)(const u64 h, u32 tag_id, ez_pcstr tag_name, u64 recno);
typedef u32 (*pfn_ez_db_recsize)(const u64 h);
typedef u64 (*pfn_ez_db_record_count)(const u64 h);

/* Group C: Data Manipulation & Seek */
typedef int (*pfn_ez_db_seek_by_tag)(const u64 h, ez_pcstr tag_name, ...);
typedef int (*pfn_ez_db_seek_by_tag_id)(const u64 h, u32 tag_id, ...);
typedef int (*pfn_ez_db_seek_by_tag_array)(const u64 h, ez_pcstr tag_name, ez_pcvoid* values);
typedef int (*pfn_ez_db_seek_by_tag_id_array)(const u64 h, u32 tag_id, ez_pcvoid* values);
typedef int (*pfn_ez_db_locate)(const u64 h, ez_pcstr fieldname, ez_pcvoid target_value, ez_bool partial_match);

typedef int (*pfn_ez_db_append)(const u64 h, ez_pcvoid data, u32 rec_count, ez_pstr delim);
typedef int (*pfn_ez_db_row_replace)(const u64 h, u64 row_id, ez_pcvoid data, ez_pcstr delim);
typedef int (*pfn_ez_db_insert)(const u64 h, ez_pcvoid data, u32 rec_count, ez_pstr delim);
typedef int (*pfn_ez_db_replace)(const u64 h, u64 row_id, ez_pcstr fieldname, ez_pcvoid val);

typedef int (*pfn_ez_db_get_record)(const u64 h, u32 tag_id, ez_pcstr tag_name, ez_pvoid buffer, u32 buffer_size, ez_bool include_deleted);
typedef ez_bool (*pfn_ez_db_is_deleted)(const u64 h, u64 row_id);
typedef int (*pfn_ez_db_delete)(const u64 h, u64 row_id);
typedef int (*pfn_ez_db_pack)(const u64 h, ez_pcstr path);
typedef int (*pfn_ez_db_zap)(u64 handle);
typedef int (*pfn_ez_db_recall)(const u64 h, u64 row_id);
typedef int (*pfn_ez_db_commit)(const u64 h);
typedef int (*pfn_ez_db_get_blob_data)(const u64 h, const EZ_BLOB_PTR* blob_ptr, ez_pvoid out_buf, u32 out_buf_size);

/* Group E & F: Utility, Indexing & Vector */
typedef int (*pfn_ez_db_get_field_names)(const u64 h, ez_pchar out_buf, u32 buf_size, ez_pcstr delim);
typedef int (*pfn_ez_db_get_index_key)(unsigned long long h, unsigned int tag_id, const char* tag_name, char* out_buf, unsigned int out_buf_len);
typedef const EZ_FIELD_NODE* (*pfn_ez_db_get_fdt)(const u64 h);
typedef const EZ_TAG_INFO* (*pfn_ez_db_get_tags)(const u64 h);
typedef u64 (*pfn_ez_db_get_delete_count)(const u64 h);

typedef int (*pfn__platform_write_raw)(ez_pvoid hFile, u64 offset, ez_pcvoid buf, u32 len);
typedef int (*pfn_ez_db_mount_index)(const u64 h, ez_pcstr edx_path, u32 slot_id);
typedef int (*pfn_ez_db_get_record_vector)(const u64 h, u32 tag_id, ez_pcstr tag_name, ez_pvoid out_struct_array, u32* p_count, u32 struct_size, ez_bool strip_str, ez_bool include_deleted);

typedef int (*pfn_ez_db_create_index)(const u64 h, ez_pcstr tag_name, ez_pcstr fields_str, ez_bool is_unique);
typedef void (*pfn__internal_build_node)(EZ_TAG_INFO* tag, void* p_rec, ez_pchar p_node);

/* Group G: Observer & Maintenance */
typedef void (*EZ_STATE_OBSERVER)(u32 slot, u32 event, u64 offset, u32 len, ez_pcvoid buffer);
typedef void (*pfn_ez_set_state_observer)(EZ_STATE_OBSERVER cb);
typedef void (*pfn_ez_db_dump_workarea)(const u64 h);
typedef int (*pfn_ez_db_purge_duplicates)(const u64 h, u32 tag_id, u64 keep_row_id);
typedef int (*pfn_ez_db_extract_duplicates)(const u64 h, u32 tag_id);
typedef void (*pfn_ez_db_dump_record)(const u64 h, ez_pcvoid record_payload);

/* Relation Manager (ERL) Subsystem Function Pointers */
typedef int (*pfn_ez_rl_mgr_init)(void);
typedef int (*pfn_ez_rl_mgr_cleanup)(void);
typedef u64 (*pfn_ez_rl_build_view)(const EZ_RL_VIEW_DESC* desc);
typedef int (*pfn_ez_rl_destroy_view)(const u64 h_rel);
typedef u64 (*pfn_ez_rl_register)(void* rel);
typedef void* (*pfn__ez_get_relation_table)(const u64 h_rel);
typedef int (*pfn_ez_rl_get_record_vector)(void* rel, u8* out_buffer, u32 request_count, u32* actual_count);
typedef int (*pfn_ez_rl_save_view_file)(const EZ_RL_VIEW_DESC* desc, const ez_char* erl_path);
typedef u64 (*pfn_ez_rl_load_view_file)(const ez_char* erl_path, const u64* h_ebf_array, u16 ebf_count);


/* --- 2. Global Function Pointers Bundle --- */
typedef struct {
    pfn_ez_db_create              ez_db_create;
    pfn_ez_db_alter               ez_db_alter;
    pfn_ez_db_reconstruct         ez_db_reconstruct;
    pfn_ez_db_use                 ez_db_use;
    pfn_ez_db_open                ez_db_open;
    pfn_ez_db_close               ez_db_close;
    pfn_ez_db_close_all           ez_db_close_all;
    pfn_ez_db_set_vacuum          ez_db_set_vacuum;
    pfn_ez_db_get_name_from_path  ez_db_get_name_from_path;
    
    pfn_ez_db_gotop               ez_db_gotop;
    pfn_ez_db_gobottom            ez_db_gobottom;
    pfn_ez_db_skip                ez_db_skip;
    pfn_ez_db_is_eof              ez_db_is_eof;
    pfn_ez_db_is_bof              ez_db_is_bof;
    pfn_ez_db_is_found            ez_db_is_found;
    pfn_ez_db_recno               ez_db_recno;
    pfn_ez_db_lastrec             ez_db_lastrec;
    pfn_ez_db_goto                ez_db_goto;
    pfn_ez_db_recsize             ez_db_recsize;
    pfn_ez_db_record_count        ez_db_record_count;

    pfn_ez_db_seek_by_tag         ez_db_seek_by_tag;
    pfn_ez_db_seek_by_tag_id      ez_db_seek_by_tag_id;
    pfn_ez_db_seek_by_tag_array   ez_db_seek_by_tag_array;
    pfn_ez_db_seek_by_tag_id_array ez_db_seek_by_tag_id_array;
    pfn_ez_db_locate              ez_db_locate;
    pfn_ez_db_append              ez_db_append;
    pfn_ez_db_row_replace         ez_db_row_replace;
    pfn_ez_db_insert              ez_db_insert;
    pfn_ez_db_replace             ez_db_replace;
    pfn_ez_db_get_record          ez_db_get_record;
    pfn_ez_db_is_deleted          ez_db_is_deleted;
    pfn_ez_db_delete              ez_db_delete;
    pfn_ez_db_pack                ez_db_pack;
    pfn_ez_db_zap                 ez_db_zap;
    pfn_ez_db_recall              ez_db_recall;
    pfn_ez_db_commit              ez_db_commit;
    pfn_ez_db_get_blob_data       ez_db_get_blob_data;

    pfn_ez_db_get_field_names     ez_db_get_field_names;
    pfn_ez_db_get_index_key       ez_db_get_index_key;
    pfn_ez_db_get_fdt             ez_db_get_fdt;
    pfn_ez_db_get_tags            ez_db_get_tags;
    pfn_ez_db_get_delete_count    ez_db_get_delete_count;
    pfn__platform_write_raw       _platform_write_raw;
    pfn_ez_db_mount_index         ez_db_mount_index;
    pfn_ez_db_get_record_vector   ez_db_get_record_vector;
    pfn_ez_db_create_index        ez_db_create_index;
    pfn__internal_build_node      _internal_build_node;

    pfn_ez_set_state_observer     ez_set_state_observer;
    pfn_ez_db_dump_workarea       ez_db_dump_workarea;
    pfn_ez_db_purge_duplicates    ez_db_purge_duplicates;
    pfn_ez_db_extract_duplicates  ez_db_extract_duplicates;
    pfn_ez_db_dump_record         ez_db_dump_record;

    /* Relation Manager (ERL) Subsystem Pointers */
    pfn_ez_rl_mgr_init            ez_rl_mgr_init;
    pfn_ez_rl_mgr_cleanup         ez_rl_mgr_cleanup;
    pfn_ez_rl_build_view          ez_rl_build_view;
    pfn_ez_rl_destroy_view        ez_rl_destroy_view;
    pfn_ez_rl_register            ez_rl_register;
    pfn__ez_get_relation_table    _ez_get_relation_table;
    pfn_ez_rl_get_record_vector   ez_rl_get_record_vector;
    pfn_ez_rl_save_view_file      ez_rl_save_view_file;
    pfn_ez_rl_load_view_file      ez_rl_load_view_file;
} EzEngineAPI;

/* External declaration of global instance for external access */
extern EzEngineAPI ez;

#define MAX_WORK_AREAS 16

typedef struct {
    int index;                      // Slot index (1 ~ 16)
    unsigned long long handle;      // DB Handle returned by engine
    char filename[256];             // EBF file name
} WorkAreaSlot;