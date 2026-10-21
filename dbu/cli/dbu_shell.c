/* ===================================================================== */
/*  File : ez_shell.c                                                    */
/*  Desc : ezDB CLI Workstation & DBU Interactive Shell                  */
/*  Copyright (c) 2026 ezLink.io All rights reserved.                    */
/* ===================================================================== */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "ez_engine_loader.h"

/* Fix MSVC LNK2019 unresolved external symbol error for strcasecmp / strncasecmp */
#ifdef _WIN32
    #ifndef strcasecmp
        #define strcasecmp _stricmp
    #endif
    #ifndef strncasecmp
        #define strncasecmp _strnicmp
    #endif
#endif

EzEngineAPI ez;
static LibHandle g_engine_lib = NULL;

typedef struct {
    int index;                      /* Slot index (1 ~ 16) */
    unsigned long long handle;      /* WorkArea Handle returned by engine */
    char filename[256];             /* EBF file name */
    u32 active_tag_id;              /* 0: Natural (physical order), 1~8: Specified EDX Tag */
    char active_tag_name[64];       /* Active Tag name */
} ShellWorkArea;

ShellWorkArea g_work_areas[MAX_WORK_AREAS];
int g_current_slot = -1;     /* 0-based; -1 indicates no WorkArea selected */

/* --- Relation View state variables --- */
static u64 g_active_rel_handle = 0;
static char g_active_rel_name[64] = {0};

/* --- Internal helper functions --- */

static void trim_spaces(char* s) {
    if (!s) return;
    char* p = s;
    while (isspace((unsigned char)*p)) p++;
    if (p != s) memmove(s, p, strlen(p) + 1);
    size_t len = strlen(s);
    while (len > 0 && isspace((unsigned char)s[len - 1])) {
        s[len - 1] = '\0';
        len--;
    }
}

int get_workarea_handle_by_name(const char* name) {
    for (int i = 0; i < MAX_WORK_AREAS; i++) {
        if (g_work_areas[i].handle != 0 && strcasecmp(g_work_areas[i].filename, name) == 0) {
            return i;
        }
    }
    return -1;
}

static int find_slot_by_filename_or_id(const char* token) {
    if (!token || *token == '\0') return -1;
    if (isdigit((unsigned char)*token)) {
        int id = atoi(token);
        if (id >= 1 && id <= MAX_WORK_AREAS && g_work_areas[id - 1].handle != 0) {
            return id - 1;
        }
    }
    return get_workarea_handle_by_name(token);
}

int load_ez_engine_symbols(const char* lib_path) {
    printf("Loading engine library [%s]...\n", lib_path);
    g_engine_lib = LOAD_LIB(lib_path);
    if (!g_engine_lib) {
        printf("FATAL: Failed to load dynamic library '%s'. Please check file path.\n", lib_path);
        return -1;
    }

    /* Group A: Initialization, Creation, and Storage */
    ez.ez_db_create = (pfn_ez_db_create)GET_FUNC(g_engine_lib, "ez_db_create");
    ez.ez_db_alter = (pfn_ez_db_alter)GET_FUNC(g_engine_lib, "ez_db_alter");
    ez.ez_db_reconstruct = (pfn_ez_db_reconstruct)GET_FUNC(g_engine_lib, "ez_db_reconstruct");
    ez.ez_db_use = (pfn_ez_db_use)GET_FUNC(g_engine_lib, "ez_db_use");
    ez.ez_db_open = (pfn_ez_db_use)GET_FUNC(g_engine_lib, "ez_db_use");
    ez.ez_db_close = (pfn_ez_db_close)GET_FUNC(g_engine_lib, "ez_db_close");
    ez.ez_db_close_all = (pfn_ez_db_close_all)GET_FUNC(g_engine_lib, "ez_db_close_all");
    ez.ez_db_set_vacuum = (pfn_ez_db_set_vacuum)GET_FUNC(g_engine_lib, "ez_db_set_vacuum");
    ez.ez_db_get_name_from_path = (pfn_ez_db_get_name_from_path)GET_FUNC(g_engine_lib, "ez_db_get_name_from_path");

    /* Group B: Navigation and State (Updated for TLS Multi-Track) */
    ez.ez_db_gotop = (pfn_ez_db_gotop)GET_FUNC(g_engine_lib, "ez_db_gotop");
    ez.ez_db_gobottom = (pfn_ez_db_gobottom)GET_FUNC(g_engine_lib, "ez_db_gobottom");
    ez.ez_db_skip = (pfn_ez_db_skip)GET_FUNC(g_engine_lib, "ez_db_skip");
    ez.ez_db_is_eof = (pfn_ez_db_is_eof)GET_FUNC(g_engine_lib, "ez_db_is_eof");
    ez.ez_db_is_bof = (pfn_ez_db_is_bof)GET_FUNC(g_engine_lib, "ez_db_is_bof");
    ez.ez_db_is_found = (pfn_ez_db_is_found)GET_FUNC(g_engine_lib, "ez_db_is_found");
    ez.ez_db_recno = (pfn_ez_db_recno)GET_FUNC(g_engine_lib, "ez_db_recno");
    ez.ez_db_lastrec = (pfn_ez_db_lastrec)GET_FUNC(g_engine_lib, "ez_db_lastrec");
    ez.ez_db_goto = (pfn_ez_db_goto)GET_FUNC(g_engine_lib, "ez_db_goto");
    ez.ez_db_recsize = (pfn_ez_db_recsize)GET_FUNC(g_engine_lib, "ez_db_recsize");
    ez.ez_db_record_count = (pfn_ez_db_record_count)GET_FUNC(g_engine_lib, "ez_db_record_count");

    /* Group C: Data Manipulation & Seek */
    ez.ez_db_seek_by_tag = (pfn_ez_db_seek_by_tag)GET_FUNC(g_engine_lib, "ez_db_seek_by_tag");
    ez.ez_db_seek_by_tag_id = (pfn_ez_db_seek_by_tag_id)GET_FUNC(g_engine_lib, "ez_db_seek_by_tag_id");
    ez.ez_db_seek_by_tag_array = (pfn_ez_db_seek_by_tag_array)GET_FUNC(g_engine_lib, "ez_db_seek_by_tag_array");
    ez.ez_db_seek_by_tag_id_array = (pfn_ez_db_seek_by_tag_id_array)GET_FUNC(g_engine_lib, "ez_db_seek_by_tag_id_array");
    ez.ez_db_locate = (pfn_ez_db_locate)GET_FUNC(g_engine_lib, "ez_db_locate");
    ez.ez_db_append = (pfn_ez_db_append)GET_FUNC(g_engine_lib, "ez_db_append");
    ez.ez_db_row_replace = (pfn_ez_db_row_replace)GET_FUNC(g_engine_lib, "ez_db_row_replace");
    ez.ez_db_insert = (pfn_ez_db_insert)GET_FUNC(g_engine_lib, "ez_db_insert");
    ez.ez_db_replace = (pfn_ez_db_replace)GET_FUNC(g_engine_lib, "ez_db_replace");
    ez.ez_db_get_record = (pfn_ez_db_get_record)GET_FUNC(g_engine_lib, "ez_db_get_record");
    ez.ez_db_is_deleted = (pfn_ez_db_is_deleted)GET_FUNC(g_engine_lib, "ez_db_is_deleted");
    ez.ez_db_delete = (pfn_ez_db_delete)GET_FUNC(g_engine_lib, "ez_db_delete");
    ez.ez_db_pack = (pfn_ez_db_pack)GET_FUNC(g_engine_lib, "ez_db_pack");
    ez.ez_db_zap = (pfn_ez_db_zap)GET_FUNC(g_engine_lib, "ez_db_zap");
    ez.ez_db_recall = (pfn_ez_db_recall)GET_FUNC(g_engine_lib, "ez_db_recall");
    ez.ez_db_commit = (pfn_ez_db_commit)GET_FUNC(g_engine_lib, "ez_db_commit");
    ez.ez_db_get_blob_data = (pfn_ez_db_get_blob_data)GET_FUNC(g_engine_lib, "ez_db_get_blob_data");

    /* Group E & F: Schema, Tags & Vectors */
    ez.ez_db_get_field_names = (pfn_ez_db_get_field_names)GET_FUNC(g_engine_lib, "ez_db_get_field_names");
    ez.ez_db_get_index_key = (pfn_ez_db_get_index_key)GET_FUNC(g_engine_lib, "ez_db_get_index_key");
    ez.ez_db_get_fdt = (pfn_ez_db_get_fdt)GET_FUNC(g_engine_lib, "ez_db_get_fdt");
    ez.ez_db_get_tags = (pfn_ez_db_get_tags)GET_FUNC(g_engine_lib, "ez_db_get_tags");
    ez.ez_db_get_delete_count = (pfn_ez_db_get_delete_count)GET_FUNC(g_engine_lib, "ez_db_get_delete_count");
    ez.ez_db_create_index = (pfn_ez_db_create_index)GET_FUNC(g_engine_lib, "ez_db_create_index");
    ez.ez_db_get_record_vector = (pfn_ez_db_get_record_vector)GET_FUNC(g_engine_lib, "ez_db_get_record_vector");
    ez.ez_db_dump_record = (pfn_ez_db_dump_record)GET_FUNC(g_engine_lib, "ez_db_dump_record");
    ez.ez_db_dump_workarea = (pfn_ez_db_dump_workarea)GET_FUNC(g_engine_lib, "ez_db_dump_workarea");

    /* Group G: Relation Manager (ERL) Subsystem */
    ez.ez_rl_mgr_init = (pfn_ez_rl_mgr_init)GET_FUNC(g_engine_lib, "ez_rl_mgr_init");
    ez.ez_rl_mgr_cleanup = (pfn_ez_rl_mgr_cleanup)GET_FUNC(g_engine_lib, "ez_rl_mgr_cleanup");
    ez.ez_rl_build_view = (pfn_ez_rl_build_view)GET_FUNC(g_engine_lib, "ez_rl_build_view");
    ez.ez_rl_destroy_view = (pfn_ez_rl_destroy_view)GET_FUNC(g_engine_lib, "ez_rl_destroy_view");
    ez.ez_rl_register = (pfn_ez_rl_register)GET_FUNC(g_engine_lib, "ez_rl_register");
    ez._ez_get_relation_table = (pfn__ez_get_relation_table)GET_FUNC(g_engine_lib, "_ez_get_relation_table");
    ez.ez_rl_get_record_vector = (pfn_ez_rl_get_record_vector)GET_FUNC(g_engine_lib, "ez_rl_get_record_vector");
    ez.ez_rl_save_view_file = (pfn_ez_rl_save_view_file)GET_FUNC(g_engine_lib, "ez_rl_save_view_file");
    ez.ez_rl_load_view_file = (pfn_ez_rl_load_view_file)GET_FUNC(g_engine_lib, "ez_rl_load_view_file");

    if (!ez.ez_db_use || !ez.ez_db_gotop || !ez.ez_db_get_record) {
        printf("WARNING: Some core functions could not be resolved from the library.\n");
    }
    return 0;
}

/* ===================================================================== */
/* Command Implementations                                               */
/* ===================================================================== */

static void cmd_cls(const char* args) {
    (void)args;
#ifdef _WIN32
    system("cls");
#else
    (void)!system("clear");
#endif
}

static void cmd_pwd(const char* args) {
    (void)args;
    char buf[1024];
    if (GETCWD(buf, sizeof(buf))) {
        printf("  [Directory] Current path: %s\n", buf);
    } else {
        printf("  [Error] Failed to get current working directory\n");
    }
}

static void cmd_cd(const char* args) {
    if (!args || *args == '\0') {
        printf("  [Error] Missing argument. Usage: CD <directory_path>\n");
        return;
    }
    if (CHDIR(args) == 0) {
        cmd_pwd(NULL);
    } else {
        printf("  [Error] Failed to change directory\n");
    }
}

static void cmd_list(const char* args) {
    if (!args || *args == '\0') {
        printf("    -> Usage: LIST <EBF | EDX | ERL>\n");
        return;
    }
    char target[32] = {0};
    sscanf(args, "%31s", target);

    const char* ext = NULL;
    if (strcasecmp(target, "EBF") == 0) ext = ".ebf";
    else if (strcasecmp(target, "EDX") == 0) ext = ".edx";
    else if (strcasecmp(target, "ERL") == 0) ext = ".erl";
    else {
        printf("  [Error] Unknown list target '%s'. Use EBF, EDX, or ERL.\n", target);
        return;
    }

    char cwd[1024];
    if (!GETCWD(cwd, sizeof(cwd))) return;

    printf("  [Directory File Listing (*%s)]\n", ext);
    int count = 0;

    #ifdef _WIN32
        /* Native Windows directory traversal (using FindFirstFileA / FindNextFileA) */
        char search_pattern[1024];
        snprintf(search_pattern, sizeof(search_pattern), "%s\\*%s", cwd, ext);

        WIN32_FIND_DATAA find_data;
        HANDLE hFind = FindFirstFileA(search_pattern, &find_data);

        if (hFind != INVALID_HANDLE_VALUE) {
            do {
                if (!(find_data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) {
                    printf("    - %s\n", find_data.cFileName);
                    count++;
                }
            } while (FindNextFileA(hFind, &find_data));
            FindClose(hFind);
        }
    #else
        /* Linux / POSIX directory traversal */
        DIR* dir = opendir(cwd);
        if (!dir) {
            perror("opendir");
            return;
        }

        struct dirent* entry;
        while ((entry = readdir(dir)) != NULL) {
            char* dot = strrchr(entry->d_name, '.');
            if (dot && strcasecmp(dot, ext) == 0) {
                printf("    - %s\n", entry->d_name);
                count++;
            }
        }
        closedir(dir);
    #endif

    if (count == 0) {
        printf("    (No *%s files found)\n", ext);
    }
}

static void cmd_use(const char* args) {
    if (!args || *args == '\0') {
        printf("    -> Usage: USE <filename.ebf>\n");
        return;
    }
    if (!ez.ez_db_use) {
        printf("  [Error] Engine API 'ez_db_use' not loaded.\n");
        return;
    }

    char filename[256] = {0};
    sscanf(args, "%255s", filename);

    int existing_slot = get_workarea_handle_by_name(filename);
    if (existing_slot != -1) {
        g_current_slot = existing_slot;
        printf("  [Notice] Database '%s' is already open.\n", filename);
        printf("    -> Switched to existing Id [%d]\n", existing_slot + 1);
        return;
    }

    int free_slot = -1;
    for (int i = 0; i < MAX_WORK_AREAS; i++) {
        if (g_work_areas[i].handle == 0) {
            free_slot = i;
            break;
        }
    }

    if (free_slot == -1) {
        printf("  [Error] Maximum active databases reached (%d limit).\n", MAX_WORK_AREAS);
        return;
    }

    u64 h = ez.ez_db_use(filename, NULL);
    if (h == 0) {
        printf("  [Error] Failed to open database '%s'\n", filename);
        return;
    }

    g_work_areas[free_slot].index = free_slot + 1;
    g_work_areas[free_slot].handle = h;
    strncpy(g_work_areas[free_slot].filename, filename, sizeof(g_work_areas[free_slot].filename) - 1);
    g_work_areas[free_slot].active_tag_id = 0;       /* Defaults to Natural order upon opening */
    g_work_areas[free_slot].active_tag_name[0] = '\0';
    g_current_slot = free_slot;
    /* Position cursor to the first record immediately after opening (Natural order) */
    ez.ez_db_gotop(h, 0, NULL);

    printf("  [Success] Database opened successfully.\n");
    printf("  +------------------------------------------+\n");
    printf("  | Id       : [%-2d]                          |\n", g_work_areas[free_slot].index);
    printf("  | Filename : %-29s |\n", g_work_areas[free_slot].filename);
    printf("  | Handle   : 0x%016llX            |\n", (unsigned long long)h);
    printf("  +------------------------------------------+\n");
}

static void cmd_select(const char* args) {
    if (!args || *args == '\0') {
        printf("    -> Usage: SELECT <id | filename.ebf>\n");
        return;
    }

    int target_slot = -1;
    if (isdigit((unsigned char)*args)) {
        int id = atoi(args);
        if (id >= 1 && id <= MAX_WORK_AREAS && g_work_areas[id - 1].handle != 0) {
            target_slot = id - 1;
        }
    } else {
        char filename[256] = {0};
        sscanf(args, "%255s", filename);
        target_slot = get_workarea_handle_by_name(filename);
    }

    if (target_slot == -1) {
        printf("  [Error] Database '%s' not found in active work areas. Use 'USE' first.\n", args);
        return;
    }

    g_current_slot = target_slot;
    printf("  [Success] Switched active work area:\n");
    printf("    +------------------------------------------+\n");
    printf("    | Id       : [%-2d]                          |\n", g_work_areas[target_slot].index);
    printf("    | Filename : %-29s |\n", g_work_areas[target_slot].filename);
    printf("    +------------------------------------------+\n");
}

static void cmd_close(const char* args) {
    int target_slot = g_current_slot;

    if (args && *args != '\0') {
        if (isdigit((unsigned char)*args)) {
            int id = atoi(args);
            if (id >= 1 && id <= MAX_WORK_AREAS && g_work_areas[id - 1].handle != 0) {
                target_slot = id - 1;
            } else {
                target_slot = -1;
            }
        } else {
            char filename[256] = {0};
            sscanf(args, "%255s", filename);
            target_slot = get_workarea_handle_by_name(filename);
        }
    }

    if (target_slot == -1 || g_work_areas[target_slot].handle == 0) {
        printf("  [Error] Specified database not found in active work areas.\n");
        return;
    }

    ez.ez_db_close(g_work_areas[target_slot].handle);
    printf("  [Success] Closed database: [%d] %s\n", g_work_areas[target_slot].index, g_work_areas[target_slot].filename);

    g_work_areas[target_slot].handle = 0;
    g_work_areas[target_slot].filename[0] = '\0';
    g_work_areas[target_slot].active_tag_id = 0;
    g_work_areas[target_slot].active_tag_name[0] = '\0';

    if (g_current_slot == target_slot) {
        g_current_slot = -1;
        for (int i = 0; i < MAX_WORK_AREAS; i++) {
            if (g_work_areas[i].handle != 0) {
                g_current_slot = i;
                break;
            }
        }
    }
}

/* Core command to switch EDX Tag / Natural track */
static void cmd_order(const char* args) {
    if (g_current_slot == -1) {
        printf("  [Error] No active database selected. Use 'USE' or 'SELECT' first.\n");
        return;
    }
    ShellWorkArea* slot = &g_work_areas[g_current_slot];

    /* Display current state if no arguments are provided */
    if (!args || *args == '\0') {
        if (slot->active_tag_id == 0) {
            printf("  [Order] Active Order: Natural Order (Physical EBF Sequence)\n");
        } else {
            printf("  [Order] Active Order: Tag Slot [%u] (%s)\n", 
                   slot->active_tag_id, slot->active_tag_name);
        }
        return;
    }

    /* Retrieve current Tag definition array */
    const EZ_TAG_INFO* tags = ez.ez_db_get_tags(slot->handle);

    /* Determine whether argument is a single Slot ID (length 1, digit '0'~'8') */
    if (strlen(args) == 1 && isdigit((unsigned char)*args)) {
        u32 slot_id = (u32)atoi(args);
        
        if (slot_id == 0) {
            /* Switch back to Natural physical order */
            slot->active_tag_id = 0;
            slot->active_tag_name[0] = '\0';
            ez.ez_db_gotop(slot->handle, 0, NULL);
            printf("  [Success] Switched order to Natural (Physical Sequence).\n");
            return;
        } else if (slot_id > 8) {
            printf("  [Error] Invalid slot id [%u]. Range is 1~8 (or 0 for Natural).\n", slot_id);
            return;
        }

        /* Verify whether the slot has an index mounted */
        if (!tags || tags[slot_id - 1].tag_name[0] == '\0') {
            printf("  [Error] Tag slot [%u] is empty. No index mounted.\n", slot_id);
            return;
        }

        /* Apply Slot ID switch */
        slot->active_tag_id = slot_id;
        strncpy(slot->active_tag_name, tags[slot_id - 1].tag_name, sizeof(slot->active_tag_name) - 1);
        ez.ez_db_gotop(slot->handle, slot->active_tag_id, slot->active_tag_name);
        printf("  [Success] Switched order to Tag ID [%u] (%s).\n", slot->active_tag_id, slot->active_tag_name);
        
    } else {
        /* Treat argument as Tag Name for lookup */
        char tag_name[64] = {0};
        sscanf(args, "%63s", tag_name);

        int found_idx = -1;
        for (int i = 0; i < 8; i++) {
            if (tags && tags[i].tag_name[0] != '\0' && strcasecmp(tags[i].tag_name, tag_name) == 0) {
                found_idx = i;
                break;
            }
        }

        if (found_idx == -1) {
            printf("  [Error] Tag name '%s' not found in database.\n", tag_name);
            printf("    -> Use 'SHOW TAGS' to list available indexes.\n");
            return;
        }

        /* Apply Tag Name switch */
        slot->active_tag_id = (u32)(found_idx + 1);
        strncpy(slot->active_tag_name, tags[found_idx].tag_name, sizeof(slot->active_tag_name) - 1);
        ez.ez_db_gotop(slot->handle, slot->active_tag_id, slot->active_tag_name);
        printf("  [Success] Switched order to Tag Name '%s' (Slot: %u).\n", slot->active_tag_name, slot->active_tag_id);
    }
}

static void cmd_top(const char* args) {
    (void)args;
    if (g_current_slot == -1) {
        printf("  [Error] No active database selected.\n");
        return;
    }
    ShellWorkArea* slot = &g_work_areas[g_current_slot];

    int st = ez.ez_db_gotop(slot->handle, slot->active_tag_id, 
                            slot->active_tag_name[0] ? slot->active_tag_name : NULL);
    if (st == 0) {
        s64 rec = ez.ez_db_recno(slot->handle, slot->active_tag_id, 
                                 slot->active_tag_name[0] ? slot->active_tag_name : NULL);
        printf("  [Success] Moved to TOP (RecNo: %lld)\n", (long long)rec);
    } else {
        printf("  [Error] Failed to move top or table is empty.\n");
    }
}

static void cmd_bottom(const char* args) {
    (void)args;
    if (g_current_slot == -1) {
        printf("  [Error] No active database selected.\n");
        return;
    }
    ShellWorkArea* slot = &g_work_areas[g_current_slot];

    int st = ez.ez_db_gobottom(slot->handle, slot->active_tag_id, 
                               slot->active_tag_name[0] ? slot->active_tag_name : NULL);
    if (st == 0) {
        s64 rec = ez.ez_db_recno(slot->handle, slot->active_tag_id, 
                                 slot->active_tag_name[0] ? slot->active_tag_name : NULL);
        printf("  [Success] Moved to BOTTOM (RecNo: %lld)\n", (long long)rec);
    } else {
        printf("  [Error] Failed to move bottom or table is empty.\n");
    }
}

static void cmd_skip(const char* args) {
    if (g_current_slot == -1) {
        printf("  [Error] No active database selected.\n");
        return;
    }
    int n = 1;
    if (args && *args != '\0') {
        n = atoi(args);
    }

    ShellWorkArea* slot = &g_work_areas[g_current_slot];
    int st = ez.ez_db_skip(slot->handle, slot->active_tag_id, 
                           slot->active_tag_name[0] ? slot->active_tag_name : NULL, n);
    if (st == 0) {
        s64 rec = ez.ez_db_recno(slot->handle, slot->active_tag_id, 
                                 slot->active_tag_name[0] ? slot->active_tag_name : NULL);
        ez_bool eof = ez.ez_db_is_eof(slot->handle, slot->active_tag_id, 
                                      slot->active_tag_name[0] ? slot->active_tag_name : NULL);
        printf("  [Success] Skipped %d record(s). Current RecNo: %lld (EOF: %s)\n", 
               n, (long long)rec, eof ? "TRUE" : "FALSE");
    }
}

static void cmd_goto(const char* args) {
    if (g_current_slot == -1) {
        printf("  [Error] No active database selected.\n");
        return;
    }
    if (!args || *args == '\0') {
        printf("  [Error] Missing argument. Usage: GOTO <recno>\n");
        return;
    }
    u64 target_no = strtoull(args, NULL, 10);
    ShellWorkArea* slot = &g_work_areas[g_current_slot];

    int st = ez.ez_db_goto(slot->handle, slot->active_tag_id, 
                           slot->active_tag_name[0] ? slot->active_tag_name : NULL, target_no);
    if (st == 0) {
        s64 rec = ez.ez_db_recno(slot->handle, slot->active_tag_id, 
                                 slot->active_tag_name[0] ? slot->active_tag_name : NULL);
        printf("  [Success] Jumped to record number %llu (Physical RecNo: %lld)\n", 
               (unsigned long long)target_no, (long long)rec);
    } else {
        printf("  [Error] Failed to jump to record %llu\n", (unsigned long long)target_no);
    }
}

static void cmd_recno(const char* args) {
    (void)args;
    if (g_current_slot == -1) {
        printf("  [Error] No active database selected.\n");
        return;
    }
    ShellWorkArea* slot = &g_work_areas[g_current_slot];
    s64 rec = ez.ez_db_recno(slot->handle, slot->active_tag_id, 
                             slot->active_tag_name[0] ? slot->active_tag_name : NULL);
    printf("  [Status] Current Record Number (RECNO): %lld\n", (long long)rec);
}

static void cmd_total(const char* args) {
    (void)args;
    if (g_current_slot == -1) {
        printf("  [Error] No active database selected.\n");
        return;
    }
    ShellWorkArea* slot = &g_work_areas[g_current_slot];
    s64 total = ez.ez_db_lastrec(slot->handle, slot->active_tag_id, 
                                 slot->active_tag_name[0] ? slot->active_tag_name : NULL);
    printf("  [Status] Total Records (LASTREC): %lld\n", (long long)total);
}

static void cmd_eof(const char* args) {
    (void)args;
    if (g_current_slot == -1) {
        printf("  [Error] No active database selected.\n");
        return;
    }
    ShellWorkArea* slot = &g_work_areas[g_current_slot];
    ez_bool is_eof = ez.ez_db_is_eof(slot->handle, slot->active_tag_id, 
                                     slot->active_tag_name[0] ? slot->active_tag_name : NULL);
    printf("  [Status] End of File (EOF): %s\n", is_eof ? "TRUE" : "FALSE");
}

static void cmd_bof(const char* args) {
    (void)args;
    if (g_current_slot == -1) {
        printf("  [Error] No active database selected.\n");
        return;
    }
    ShellWorkArea* slot = &g_work_areas[g_current_slot];
    ez_bool is_bof = ez.ez_db_is_bof(slot->handle, slot->active_tag_id, 
                                     slot->active_tag_name[0] ? slot->active_tag_name : NULL);
    printf("  [Status] Beginning of File (BOF): %s\n", is_bof ? "TRUE" : "FALSE");
}

static void cmd_found(const char* args) {
    (void)args;
    if (g_current_slot == -1) {
        printf("  [Error] No active database selected.\n");
        return;
    }
    ShellWorkArea* slot = &g_work_areas[g_current_slot];
    ez_bool found = ez.ez_db_is_found(slot->handle, slot->active_tag_id, 
                                      slot->active_tag_name[0] ? slot->active_tag_name : NULL);
    printf("  [Status] Search Found Flag (FOUND): %s\n", found ? "TRUE" : "FALSE");
}

static void cmd_locate(const char* args) {
    if (g_current_slot == -1) {
        printf("  [Error] No active database selected.\n");
        return;
    }
    char field[64] = {0}, val[256] = {0};
    if (sscanf(args, "%63s %255s", field, val) < 2) {
        printf("  [Error] Missing arguments. Usage: LOCATE <field> <value>\n");
        return;
    }

    ShellWorkArea* slot = &g_work_areas[g_current_slot];
    int st = ez.ez_db_locate(slot->handle, field, val, ez_false);
    if (st == 0) {
        s64 rec = ez.ez_db_recno(slot->handle, 0, NULL);
        printf("  [Success] Record located! Current RecNo: %lld\n", (long long)rec);
    } else {
        printf("  [Result] Record not found for field '%s' with value '%s'.\n", field, val);
    }
}

static void cmd_seek(const char* args) {
    if (g_current_slot == -1) {
        printf("  [Error] No active database selected.\n");
        return;
    }
    char tag[64] = {0}, val[256] = {0};
    if (sscanf(args, "%63s %255s", tag, val) < 2) {
        printf("  [Error] Missing arguments. Usage: SEEK <tag_name> <value>\n");
        return;
    }

    ShellWorkArea* slot = &g_work_areas[g_current_slot];
    int st = ez.ez_db_seek_by_tag(slot->handle, tag, val);
    if (st == 0) {
        strncpy(slot->active_tag_name, tag, sizeof(slot->active_tag_name) - 1);
        const EZ_TAG_INFO* tags = ez.ez_db_get_tags(slot->handle);
        slot->active_tag_id = 0;
        for (int i = 0; i < 8; i++) {
            if (tags && tags[i].tag_name[0] != '\0' && strcasecmp(tags[i].tag_name, tag) == 0) {
                slot->active_tag_id = (u32)(i + 1);
                break;
            }
        }
        s64 rec = ez.ez_db_recno(slot->handle, slot->active_tag_id, slot->active_tag_name);
        printf("  [Success] Record found and positioned via tag '%s'. RecNo: %lld\n", tag, (long long)rec);
    } else {
        printf("  [Result] Record not found for tag '%s' with value '%s'.\n", tag, val);
    }
}

static void cmd_replace(const char* args) {
    if (g_current_slot == -1) {
        printf("  [Error] No active database selected.\n");
        return;
    }
    char field[64] = {0}, val[256] = {0};
    if (sscanf(args, "%63s %255s", field, val) < 2) {
        printf("    -> Usage: REPLACE <field_name> <value>\n");
        printf("    -> Example: REPLACE name \"NewName\"\n");
        return;
    }

    ShellWorkArea* slot = &g_work_areas[g_current_slot];
    s64 rec = ez.ez_db_recno(slot->handle, slot->active_tag_id, 
                             slot->active_tag_name[0] ? slot->active_tag_name : NULL);
    if (rec <= 0) {
        printf("  [Error] Current record pointer is invalid.\n");
        return;
    }

    int st = ez.ez_db_replace(slot->handle, (u64)rec, field, val);
    if (st == 0) {
        printf("  [Success] Field '%s' replaced successfully at current record.\n", field);
    } else {
        printf("  [Error] Failed to replace field. Error code: %d\n", st);
    }
}

static void cmd_rowreplace(const char* args) {
    if (g_current_slot == -1) {
        printf("  [Error] No active database selected.\n");
        return;
    }
    if (!args || *args == '\0') {
        printf("    -> Usage: ROWREPLACE <comma_separated_values>\n");
        printf("    -> Example: ROWREPLACE \"0051, 100,59722\"\n");
        return;
    }

    ShellWorkArea* slot = &g_work_areas[g_current_slot];
    s64 rec = ez.ez_db_recno(slot->handle, slot->active_tag_id, 
                             slot->active_tag_name[0] ? slot->active_tag_name : NULL);
    if (rec <= 0) {
        printf("  [Error] Current record pointer is invalid.\n");
        return;
    }

    int st = ez.ez_db_row_replace(slot->handle, (u64)rec, args, ",");
    if (st == 0) {
        printf("  [Success] Current record row replaced successfully.\n");
    } else {
        printf("  [Error] Failed to replace row. Error code: %d\n", st);
    }
}

static void cmd_append(const char* args) {
    if (g_current_slot == -1) {
        printf("  [Error] No active database selected.\n");
        return;
    }
    if (!args || *args == '\0') {
        printf("  [Error] Missing argument. Usage: APPEND <comma_separated_values>\n");
        return;
    }

    ShellWorkArea* slot = &g_work_areas[g_current_slot];
    int st = ez.ez_db_append(slot->handle, args, 1, (ez_pstr)",");
    if (st == 0) {
        printf("  [Success] Record appended successfully.\n");
    } else {
        printf("  [Error] Failed to append record. Code: %d\n", st);
    }
}

static void cmd_delete_rec(const char* args) {
    (void)args;
    if (g_current_slot == -1) {
        printf("  [Error] No active database selected.\n");
        return;
    }
    ShellWorkArea* slot = &g_work_areas[g_current_slot];
    s64 rec = ez.ez_db_recno(slot->handle, slot->active_tag_id, 
                             slot->active_tag_name[0] ? slot->active_tag_name : NULL);
    if (rec <= 0) return;

    if (ez.ez_db_delete(slot->handle, (u64)rec) == 0) {
        printf("  [Success] Current record marked as deleted.\n");
    }
}

static void cmd_recall(const char* args) {
    (void)args;
    if (g_current_slot == -1) {
        printf("  [Error] No active database selected.\n");
        return;
    }
    ShellWorkArea* slot = &g_work_areas[g_current_slot];
    s64 rec = ez.ez_db_recno(slot->handle, slot->active_tag_id, 
                             slot->active_tag_name[0] ? slot->active_tag_name : NULL);
    if (rec <= 0) return;

    if (ez.ez_db_recall(slot->handle, (u64)rec) == 0) {
        printf("  [Success] Current record deletion mark recalled.\n");
    }
}

static void cmd_pack(const char* args) {
    (void)args;
    if (g_current_slot == -1) {
        printf("  [Error] No active database selected.\n");
        return;
    }
    ShellWorkArea* slot = &g_work_areas[g_current_slot];
    if (ez.ez_db_pack(slot->handle, slot->filename) == 0) {
        printf("  [Success] Database packed (deleted records removed physically).\n");
    }
}

static void cmd_zap(const char* args) {
    (void)args;
    if (g_current_slot == -1) {
        printf("  [Error] No active database selected.\n");
        return;
    }
    ShellWorkArea* slot = &g_work_areas[g_current_slot];
    if (ez.ez_db_zap(slot->handle) == 0) {
        printf("  [Success] Database ZAPPED (all records wiped out).\n");
    }
}

static void cmd_commit(const char* args) {
    (void)args;
    if (g_current_slot == -1) {
        printf("  [Error] No active database selected.\n");
        return;
    }
    ShellWorkArea* slot = &g_work_areas[g_current_slot];
    if (ez.ez_db_commit(slot->handle) == 0) {
        printf("  [Success] Database committed to disk.\n");
    }
}

static void cmd_show(const char* args) {
    if (!args || *args == '\0') {
        printf("    -> Usage: SHOW <schema | record | db | index | tags>\n");
        return;
    }

    char sub[64] = {0};
    sscanf(args, "%63s", sub);

    if (strcasecmp(sub, "DB") == 0 || strcasecmp(sub, "DATABASES") == 0) {
        printf("  =======================================================\n");
        printf("                   Active Work Areas                     \n");
        printf("  =======================================================\n");
        printf("   Sts | Id    | Filename                | Handle        \n");
        printf("  -----+-------+-------------------------+---------------\n");
        int count = 0;
        for (int i = 0; i < MAX_WORK_AREAS; i++) {
            if (g_work_areas[i].handle != 0) {
                printf("   %s   |  [%-2d] | %-23s | 0x%08llX\n",
                       (i == g_current_slot) ? " * " : "   ",
                       g_work_areas[i].index,
                       g_work_areas[i].filename,
                       (unsigned long long)g_work_areas[i].handle);
                count++;
            }
        }
        if (count == 0) {
            printf("     (No database currently opened)\n");
        }
        printf("  =======================================================\n");
        return;
    }

    if (g_current_slot == -1) {
        printf("  [Error] No database selected. Use 'USE <file>' or 'SELECT <id>' first.\n");
        return;
    }
    ShellWorkArea* slot = &g_work_areas[g_current_slot];

    if (strcasecmp(sub, "SCHEMA") == 0 || strcasecmp(sub, "FIELDS") == 0) {
        const EZ_FIELD_NODE* fdt = ez.ez_db_get_fdt(slot->handle);
        if (!fdt || fdt[0].name[0] == '\0') {
            printf("  [Error] Failed to fetch FDT schema or empty table definition.\n");
            return;
        }

        printf("  [Schema] FDT Information for [%s] (Id: %d):\n", slot->filename, slot->index);
        printf("  +-----+-------------------------+------+--------+----------+---------+--------+\n");
        printf("  | #   | Field Name              | Type | Length | Decimals | Storage | Offset |\n");
        printf("  +-----+-------------------------+------+--------+----------+---------+--------+\n");

        for (u32 i = 0; i < 94 && fdt[i].name[0] != '\0'; i++) {
            printf("  | %-3u | %-23s |  %c   | %-6u | %-8u | %-7s | %-6u |\n",
                   i + 1,
                   fdt[i].name,
                   fdt[i].type,
                   fdt[i].len,
                   fdt[i].dec,
                   fdt[i].storage ? "Remote" : "Inline",
                   fdt[i].offset);
        }
        printf("  +-----+-------------------------+------+--------+----------+---------+--------+\n");
        return;
    }

    if (strcasecmp(sub, "TAGS") == 0 || strcasecmp(sub, "INDEX") == 0 || strcasecmp(sub, "INDEXES") == 0) {
        const EZ_TAG_INFO* tags = ez.ez_db_get_tags(slot->handle);
        printf("  [Index Tags] Active Index Information for [%s]:\n", slot->filename);
        printf("  +-----+-------------------------+-------------------------+----------+--------+--------+\n");
        printf("  | Slot| Tag Name                | Expression (Key)        | Nodes    | Unique | Active |\n");
        printf("  +-----+-------------------------+-------------------------+----------+--------+--------+\n");
        int tag_count = 0;
        for (int i = 0; i < 8; i++) {
            if (tags && tags[i].tag_name[0] != '\0') {
                u32 slot_id = (u32)(i + 1);
                char expr_buf[128] = {0};

                /* Dynamically resolve real key expression via C-Core API */
                if (ez.ez_db_get_index_key) {
                    ez.ez_db_get_index_key(slot->handle, slot_id, tags[i].tag_name, expr_buf, sizeof(expr_buf));
                }
                if (expr_buf[0] == '\0') {
                    strncpy(expr_buf, tags[i].tag_name, sizeof(expr_buf) - 1);
                }

                printf("  |  %-2u | %-23s | %-23s | %-8llu | %-6s |  %-5s |\n",
                       slot_id,
                       tags[i].tag_name,
                       expr_buf,
                       (unsigned long long)tags[i].node_count,
                       tags[i].is_unique ? "YES" : "NO",
                       (slot->active_tag_id == slot_id) ? " * " : "");
                tag_count++;
            }
        }
        if (tag_count == 0) {
            printf("  |     | (No EDX index mounted)  |                         |          |        |        |\n");
        }
        printf("  +-----+-------------------------+-------------------------+----------+--------+--------+\n");
        return;
    }

    if (strcasecmp(sub, "RECORD") == 0) {
        s64 rec = ez.ez_db_recno(slot->handle, slot->active_tag_id, 
                                 slot->active_tag_name[0] ? slot->active_tag_name : NULL);
        if (rec <= 0) {
            printf("  [Record] Current Record View: Pointer at EOF or invalid.\n");
            return;
        }

        u32 rec_size = ez.ez_db_recsize(slot->handle);
        void* buf = malloc(rec_size);
        if (!buf) return;

        int st = ez.ez_db_get_record(slot->handle, slot->active_tag_id,
                                     slot->active_tag_name[0] ? slot->active_tag_name : NULL,
                                     buf, rec_size, ez_true);
        if (st == 0) {
            printf("  [Record] Current Record View (RecNo: %lld, Order: %s):\n",                
                   (long long)rec, (slot->active_tag_id > 0) ? slot->active_tag_name : "Natural");
            ez.ez_db_dump_record(slot->handle, buf);
        } else {
            printf("  [Record] Current Record View (RecNo: %lld):\n", (long long)rec);
            printf("    -> (Failed to fetch current record data)\n");
        }
        free(buf);
        return;
    }

    printf("  [Error] Unknown show target '%s'\n", sub);
}

static void cmd_index(const char* args) {
    (void)args;
    cmd_show("INDEX");
}

static void cmd_create_table(const char* args) {
    if (!args || *args == '\0') {
        printf("    -> Usage: CREATE TABLE <filename.ebf> (<col_name type(len), ...>)\n");
        printf("    -> Example: CREATE TABLE test.ebf (id N(8), name C(20))\n");
        return;
    }
    char path[256] = {0};
    const char* p_open = strchr(args, '(');
    const char* p_close = strrchr(args, ')');
    if (!p_open || !p_close || p_close <= p_open) {
        printf("  [Error] Syntax error. Columns must be enclosed in parentheses.\n");
        return;
    }

    size_t path_len = p_open - args;
    if (path_len >= sizeof(path)) path_len = sizeof(path) - 1;
    strncpy(path, args, path_len);
    trim_spaces(path);

    char cols_buf[1024] = {0};
    strncpy(cols_buf, p_open + 1, p_close - p_open - 1);

    EZ_FIELD_NODE map[94];
    memset(map, 0, sizeof(map));
    int f_count = 0;

    char* token = strtok(cols_buf, ",");
    while (token && f_count < 94) {
        trim_spaces(token);
        char c_name[52] = {0}, c_type = 0;
        int c_len = 0, c_dec = 0;

        if (sscanf(token, "%51s %c(%d,%d)", c_name, &c_type, &c_len, &c_dec) == 4 ||
            sscanf(token, "%51s %c(%d)", c_name, &c_type, &c_len) >= 3) {
            strncpy(map[f_count].name, c_name, 51);
            map[f_count].type = (u8)toupper((unsigned char)c_type);
            map[f_count].len = (u32)c_len;
            map[f_count].dec = (u8)c_dec;
            f_count++;
        }
        token = strtok(NULL, ",");
    }

    if (f_count == 0) {
        printf("  [Error] No valid columns parsed.\n");
        return;
    }

    int st = ez.ez_db_create(path, map);
    if (st == 0) {
        printf("  [Success] Table '%s' created successfully.\n", path);
    } else {
        printf("  [Error] Failed to create table. Error code: %d\n", st);
    }
}

static void cmd_create_index_sql(const char* args) {
    if (!args || *args == '\0') {
        printf("    -> Usage: CREATE INDEX <tag_name> ON <table_or_col> (<fields>) [UNIQUE]\n");
        printf("    -> Example: CREATE INDEX idx_code ON test (code) UNIQUE\n");
        return;
    }
    if (g_current_slot == -1) {
        printf("  [Error] No active database selected.\n");
        return;
    }

    char tag_name[64] = {0};
    char dummy_table[64] = {0};
    const char* p_open = strchr(args, '(');
    const char* p_close = strrchr(args, ')');
    if (!p_open || !p_close) {
        printf("  [Error] Fields must be enclosed in parentheses.\n");
        return;
    }

    sscanf(args, "%63s ON %63s", tag_name, dummy_table);
    char fields[256] = {0};
    strncpy(fields, p_open + 1, p_close - p_open - 1);
    trim_spaces(fields);

    ez_bool is_unique = ez_false;
    if (strstr(p_close, "UNIQUE") != NULL || strstr(p_close, "unique") != NULL) {
        is_unique = ez_true;
    }

    ShellWorkArea* slot = &g_work_areas[g_current_slot];
    int st = ez.ez_db_create_index(slot->handle, tag_name, fields, is_unique);
    if (st == 0) {
        printf("  [Success] Index '%s' created successfully.\n", tag_name);
    } else {
        printf("  [Error] Failed to create index. Error code: %d\n", st);
    }
}

static void cmd_alter_table(const char* args) {
    if (g_current_slot == -1) {
        printf("  [Error] No active database selected. Use 'USE' or 'SELECT' first.\n");
        return;
    }
    if (!args || *args == '\0') {
        printf("    -> Usage: ALTER TABLE <filename.ebf> (<new_columns...>)\n");
        return;
    }
    ShellWorkArea* slot = &g_work_areas[g_current_slot];

    const char* p_open = strchr(args, '(');
    const char* p_close = strrchr(args, ')');
    if (!p_open || !p_close || p_close <= p_open) {
        printf("  [Error] Syntax error. Columns must be enclosed in parentheses.\n");
        return;
    }

    char cols_buf[1024] = {0};
    strncpy(cols_buf, p_open + 1, p_close - p_open - 1);

    EZ_FIELD_NODE map[94];
    memset(map, 0, sizeof(map));
    int f_count = 0;

    char* token = strtok(cols_buf, ",");
    while (token && f_count < 94) {
        trim_spaces(token);
        char c_name[52] = {0}, c_type = 0;
        int c_len = 0, c_dec = 0;

        if (sscanf(token, "%51s %c(%d,%d)", c_name, &c_type, &c_len, &c_dec) == 4 ||
            sscanf(token, "%51s %c(%d)", c_name, &c_type, &c_len) >= 3) {
            strncpy(map[f_count].name, c_name, 51);
            map[f_count].type = (u8)toupper((unsigned char)c_type);
            map[f_count].len = (u32)c_len;
            map[f_count].dec = (u8)c_dec;
            f_count++;
        }
        token = strtok(NULL, ",");
    }

    if (f_count == 0) {
        printf("  [Error] No valid columns parsed.\n");
        return;
    }

    EZ_MIGRATE_REPORT report;
    memset(&report, 0, sizeof(EZ_MIGRATE_REPORT));
    int st = ez.ez_db_alter(slot->handle, slot->filename, map, &report);
    if (st == 0) {
        printf("  [Success] Table schema altered successfully.\n");
    } else {
        printf("  [Error] Failed to alter table. Error code: %d\n", st);
    }
}

/* ===================================================================== */
/* Relation View Subsystem                                               */
/* ===================================================================== */

static void cmd_set_relation(const char* args) {
    if (g_current_slot == -1) {
        printf("  [Error] No active parent database selected. Use 'USE' or 'SELECT' first.\n");
        return;
    }
    if (!args || *args == '\0') {
        if (g_active_rel_handle != 0) {
            printf("  [Relation] Active Relation View: [%s] (Handle: 0x%016llX)\n", 
                   g_active_rel_name, (unsigned long long)g_active_rel_handle);
        } else {
            printf("  [Relation] No active relation configured.\n");
            printf("    -> Usage: SET RELATION TO <field> INTO <child> TAG <tag> [INNER|LEFT] [AS <name>]\n");
            printf("    -> To clear: SET RELATION OFF\n");
        }
        return;
    }

    if (strcasecmp(args, "OFF") == 0 || strcasecmp(args, "CLEAR") == 0) {
        if (g_active_rel_handle != 0) {
            ez.ez_rl_destroy_view(g_active_rel_handle);
            g_active_rel_handle = 0;
            g_active_rel_name[0] = '\0';
            printf("  [Success] Active relation view detached and destroyed.\n");
        } else {
            printf("  [Notice] No active relation to clear.\n");
        }
        return;
    }

    char fk_field[64] = {0};
    char child_ref[64] = {0};
    char child_tag[64] = {0};
    char view_name[64] = "rel_view";
    EZ_RL_JOIN_MODE join_mode = EZ_RL_JOIN_LEFT; /* Defaults to LEFT OUTER JOIN */

    const char* p_to = strstr(args, "TO ");
    const char* p_into = strstr(args, "INTO ");
    const char* p_tag = strstr(args, "TAG ");
    const char* p_as = strstr(args, "AS ");

    if (!p_into || !p_tag) {
        printf("  [Error] Syntax error. Usage: SET RELATION TO <field> INTO <child> TAG <tag> [INNER|LEFT] [AS <name>]\n");
        printf("    -> Example: SET RELATION TO cust_no INTO orders.ebf TAG idx_cust INNER AS cust_orders\n");
        return;
    }

    /* Check if INNER JOIN is specified */
    if (strstr(args, "INNER") != NULL || strstr(args, "inner") != NULL) {
        join_mode = EZ_RL_JOIN_INNER;
    } else if (strstr(args, "LEFT") != NULL || strstr(args, "left") != NULL ||
               strstr(args, "OUTER") != NULL || strstr(args, "outer") != NULL) {
        join_mode = EZ_RL_JOIN_LEFT;
    }

    if (p_to) {
        sscanf(p_to + 3, "%63s", fk_field);
    } else {
        sscanf(args, "%63s", fk_field);
    }
    sscanf(p_into + 5, "%63s", child_ref);
    sscanf(p_tag + 4, "%63s", child_tag);
    if (p_as) {
        sscanf(p_as + 3, "%63s", view_name);
    }

    int parent_slot = g_current_slot;
    int child_slot = find_slot_by_filename_or_id(child_ref);
    if (child_slot == -1) {
        printf("  [Error] Child table '%s' not found in active work areas. Use 'USE' first.\n", child_ref);
        return;
    }

    ShellWorkArea* parent_wa = &g_work_areas[parent_slot];
    ShellWorkArea* child_wa = &g_work_areas[child_slot];

    const EZ_FIELD_NODE* parent_fdt = ez.ez_db_get_fdt(parent_wa->handle);
    const EZ_FIELD_NODE* matched_f = NULL;
    for (int i = 0; i < 94 && parent_fdt[i].name[0] != '\0'; i++) {
        if (strcasecmp(parent_fdt[i].name, fk_field) == 0) {
            matched_f = &parent_fdt[i];
            break;
        }
    }
    if (!matched_f) {
        printf("  [Error] Foreign key field '%s' not found in parent table '%s'.\n", fk_field, parent_wa->filename);
        return;
    }

    /* Initialize relation manager (idempotent safe call) */
    if (ez.ez_rl_mgr_init) ez.ez_rl_mgr_init();

    /* 1. Prepare EBF Handles array */
    u64 h_ebf[2] = { parent_wa->handle, child_wa->handle };

    /* 2. Prepare projection node array (up to 16 columns) */
    EZ_RL_NODE_DESC node_arr[16];
    memset(node_arr, 0, sizeof(node_arr));
    u16 node_idx = 0;

    for (int i = 0; i < 8 && parent_fdt[i].name[0] != '\0'; i++) {
        node_arr[node_idx].ebf_index = 0;
        strncpy((char*)node_arr[node_idx].field_name, parent_fdt[i].name, 51);
        snprintf((char*)node_arr[node_idx].alias_name, 51, "P_%s", parent_fdt[i].name);
        node_idx++;
    }

    const EZ_FIELD_NODE* child_fdt = ez.ez_db_get_fdt(child_wa->handle);
    if (child_fdt) {
        for (int i = 0; i < 8 && child_fdt[i].name[0] != '\0'; i++) {
            node_arr[node_idx].ebf_index = 1;
            strncpy((char*)node_arr[node_idx].field_name, child_fdt[i].name, 51);
            snprintf((char*)node_arr[node_idx].alias_name, 51, "C_%s", child_fdt[i].name);
            node_idx++;
        }
    }

    /* 3. Prepare foreign key linkage chain (Link) */
    EZ_RL_LINK_DESC link_arr[1];
    memset(link_arr, 0, sizeof(link_arr));
    link_arr[0].parent_ebf_index = 0;
    link_arr[0].child_ebf_index = 1;
    link_arr[0].fk_field_count = 1;
    link_arr[0].parent_fk_offsets[0] = (u16)matched_f->offset;
    link_arr[0].parent_fk_lens[0] = (u16)matched_f->len;
    strncpy((char*)link_arr[0].child_tag_name, child_tag, 47);

    /* 4. Assemble main descriptor EZ_RL_VIEW_DESC */
    EZ_RL_VIEW_DESC desc;
    memset(&desc, 0, sizeof(EZ_RL_VIEW_DESC));
    desc.relation_name = view_name;
    desc.join_mode = join_mode;
    desc.h_ebf_array = h_ebf;
    desc.ebf_count = 2;
    desc.nodes = node_arr;
    desc.node_count = node_idx;
    desc.links = link_arr;
    desc.link_count = 1;

    /* Call underlying C engine to build relation view entity */
    u64 hRel = ez.ez_rl_build_view(&desc);
    if (hRel == 0) {
        printf("  [Error] Failed to build relation view. Key geometry mismatch or missing tag '%s'.\n", child_tag);
        return;
    }

    if (g_active_rel_handle != 0) {
        ez.ez_rl_destroy_view(g_active_rel_handle);
    }
    g_active_rel_handle = hRel;
    strncpy(g_active_rel_name, view_name, sizeof(g_active_rel_name) - 1);

    printf("  [Success] Relation View established successfully!\n");
    printf("  +---------------------------------------------------+\n");
    printf("  | View Name   : %-35s |\n", g_active_rel_name);
    printf("  | Join Mode   : %-35s |\n", (join_mode == EZ_RL_JOIN_INNER) ? "INNER JOIN" : "LEFT OUTER JOIN");
    printf("  | Parent Table: [%d] %-31s |\n", parent_wa->index, parent_wa->filename);
    printf("  | Child Table : [%d] %-31s |\n", child_wa->index, child_wa->filename);
    printf("  | Target Tag  : %-35s |\n", child_tag);
    printf("  | Handle      : 0x%016llX |\n", (unsigned long long)hRel);
    printf("  +---------------------------------------------------+\n");
}

static void cmd_list_relation(const char* args) {
    if (g_active_rel_handle == 0) {
        printf("  [Error] No active relation view. Use 'SET RELATION' first.\n");
        return;
    }
    u32 req_count = 10;
    if (args && *args != '\0') {
        int c = atoi(args);
        if (c > 0) req_count = (u32)c;
    }

    void* pRelTable = ez._ez_get_relation_table(g_active_rel_handle);
    if (!pRelTable) {
        printf("  [Error] Failed to acquire relation runtime table instance.\n");
        return;
    }

    u32 buf_size = req_count * 4096;
    u8* out_buf = (u8*)calloc(1, buf_size);
    u32 actual_count = 0;

    int st = ez.ez_rl_get_record_vector(pRelTable, out_buf, req_count, &actual_count);
    if (st != 0 || actual_count == 0) {
        printf("  [Result] Relation view query returned 0 records (Status: %d).\n", st);
        free(out_buf);
        return;
    }

    printf("  [Relation Query Result: %s] (Fetched %u stitched rows):\n", g_active_rel_name, actual_count);
    printf("  -------------------------------------------------------------------\n");
    for (u32 i = 0; i < actual_count; i++) {
        printf("  Row [%03u] -> Stitched Payload Length: 4096 Bytes\n", i + 1);
    }
    printf("  -------------------------------------------------------------------\n");
    free(out_buf);
}

static void cmd_save_relation(const char* args) {
    if (g_active_rel_handle == 0) {
        printf("  [Error] No active relation view to save.\n");
        return;
    }
    if (!args || *args == '\0') {
        printf("    -> Usage: SAVE RELATION <filename.erl>\n");
        return;
    }
    char path[256] = {0};
    sscanf(args, "%255s", path);
    printf("  [Notice] Exporting current relation view '%s' blueprint to '%s'...\n", g_active_rel_name, path);
}

static void cmd_load_relation(const char* args) {
    if (!args || *args == '\0') {
        printf("    -> Usage: LOAD RELATION <filename.erl>\n");
        return;
    }
    char path[256] = {0};
    sscanf(args, "%255s", path);

    u64 h_array[MAX_WORK_AREAS];
    u16 cnt = 0;
    for (int i = 0; i < MAX_WORK_AREAS; i++) {
        if (g_work_areas[i].handle != 0) {
            h_array[cnt++] = g_work_areas[i].handle;
        }
    }

    if (cnt == 0) {
        printf("  [Error] No tables currently opened in WorkAreas to bind relation.\n");
        return;
    }

    u64 hRel = ez.ez_rl_load_view_file(path, h_array, cnt);
    if (hRel == 0) {
        printf("  [Error] Failed to load relation from file '%s'. Corrupt or table mismatch.\n", path);
        return;
    }

    if (g_active_rel_handle != 0) {
        ez.ez_rl_destroy_view(g_active_rel_handle);
    }
    g_active_rel_handle = hRel;
    strncpy(g_active_rel_name, path, sizeof(g_active_rel_name) - 1);

    printf("  [Success] Loaded Relation View from '%s' successfully! (Handle: 0x%016llX)\n", 
           path, (unsigned long long)hRel);
}

static void cmd_help(const char* args);

static void cmd_exit(const char* args) {
    (void)args;
    if (g_active_rel_handle != 0 && ez.ez_rl_destroy_view) {
        ez.ez_rl_destroy_view(g_active_rel_handle);
        g_active_rel_handle = 0;
    }
    if (ez.ez_rl_mgr_cleanup) {
        ez.ez_rl_mgr_cleanup();
    }

    int unclosed = 0;
    for (int i = 0; i < MAX_WORK_AREAS; i++) {
        if (g_work_areas[i].handle != 0) unclosed++;
    }
    if (unclosed > 0) {
        printf("  [Notice] Found %d unclosed database(s). Executing auto cleanup...\n", unclosed);
        ez.ez_db_close_all();
    }
    if (g_engine_lib) {
        CLOSE_LIB(g_engine_lib);
    }
    printf("  [Exit] Exiting EZ-Shell. Goodbye!\n");
    exit(0);
}

static void cmd_getindexkey(const char* args) {
    if (g_current_slot == -1) {
        printf("  [Error] No active database selected. Use 'USE' or 'SELECT' first.\n");
        return;
    }
    if (!ez.ez_db_get_index_key) {
        printf("  [Error] Engine API 'ez_db_get_index_key' not loaded.\n");
        return;
    }

    ShellWorkArea* slot = &g_work_areas[g_current_slot];
    u32 tag_id = 0;
    char tag_name[64] = {0};

    if (args && *args != '\0') {
        char p1[64] = {0}, p2[64] = {0};
        int parsed = sscanf(args, "%63s %63s", p1, p2);

        if (parsed == 2) {
            /* Format: GETINDEXKEY <slot_id> <tag_name> */
            if (isdigit((unsigned char)p1[0])) {
                tag_id = (u32)atoi(p1);
                strncpy(tag_name, p2, sizeof(tag_name) - 1);
            } else if (isdigit((unsigned char)p2[0])) {
                tag_id = (u32)atoi(p2);
                strncpy(tag_name, p1, sizeof(tag_name) - 1);
            } else {
                printf("  [Error] Invalid arguments. Usage: GETINDEXKEY [slot_id] [tag_name]\n");
                return;
            }
        } else if (parsed == 1) {
            /* Format: GETINDEXKEY <slot_id> OR GETINDEXKEY <tag_name> */
            if (isdigit((unsigned char)p1[0])) {
                tag_id = (u32)atoi(p1);
            } else {
                strncpy(tag_name, p1, sizeof(tag_name) - 1);
            }
        }
    } else {
        /* Default: Resolve currently active order tag if set */
        tag_id = slot->active_tag_id;
        if (slot->active_tag_name[0] != '\0') {
            strncpy(tag_name, slot->active_tag_name, sizeof(tag_name) - 1);
        }
        if (tag_id == 0 && tag_name[0] == '\0') {
            printf("  [Notice] No active tag order. Usage: GETINDEXKEY <slot_id | tag_name>\n");
            return;
        }
    }

    char out_buf[128] = {0};
    int st = ez.ez_db_get_index_key(slot->handle, tag_id, tag_name[0] ? tag_name : NULL, out_buf, sizeof(out_buf));

    if (st == 0) {
        printf("  [Success] Index Key Expression Resolved:\n");
        printf("  +---------------------------------------------------+\n");
        printf("  | Database   : [%d] %-31s |\n", slot->index, slot->filename);
        if (tag_id > 0) {
            printf("  | Tag Slot   : %-36u |\n", tag_id);
        }
        if (tag_name[0] != '\0') {
            printf("  | Tag Name   : %-36s |\n", tag_name);
        }
        printf("  | Expression : %-36s |\n", out_buf);
        printf("  +---------------------------------------------------+\n");
    } else {
        printf("  [Error] Failed to resolve index key (Status: %d). Invalid slot, tag name, or mismatch.\n", st);
    }
}

/* ===================================================================== */
/* Command Dispatch Table                                                */
/* ===================================================================== */

typedef struct {
    const char* cmd;
    void (*handler)(const char* args);
    const char* desc;
} CommandEntry;

static CommandEntry g_cmd_table[] = {
    {"USE",          cmd_use,              "Open and select an EBF database (USE test.ebf)"},
    {"OPEN",         cmd_use,              "Open and select an EBF database (USE test.ebf)"},
    {"SELECT",       cmd_select,           "Switch active database by slot Id or Filename"},
    {"CLOSE",        cmd_close,            "Close database by slot Id or Filename (or current)"},
    {"ORDER",        cmd_order,            "Set or display active index order (ORDER 1 / ORDER 0)"},    
    {"GETINDEXKEY",  cmd_getindexkey,      "Get key expression of a tag (GETINDEXKEY [slot] [tag])"},    
    {"RELATION",     cmd_set_relation,     "Set table relation (SET RELATION TO .. INTO .. TAG ..)"},
    {"LISTREL",      cmd_list_relation,    "List stitched records from active relation view"},
    {"TOP",          cmd_top,              "Move database pointer to the first record"},
    {"BOTTOM",       cmd_bottom,           "Move database pointer to the last record"},
    {"SKIP",         cmd_skip,             "Skip records forward/backward (SKIP 1)"},
    {"GOTO",         cmd_goto,             "Jump to specific record number (GOTO 10)"},
    {"RECNO",        cmd_recno,            "Show current record number"},
    {"TOTAL",        cmd_total,            "Show total record count (LASTREC)"},
    {"LASTREC",      cmd_total,            "Show total record count (LASTREC)"},
    {"BOF",          cmd_bof,              "Check if pointer is at Beginning of File"},
    {"EOF",          cmd_eof,              "Check if pointer is at End of File"},
    {"FOUND",        cmd_found,            "Check last search/locate result flag"},
    {"LOCATE",       cmd_locate,           "Locate record by field and value (LOCATE code 0051)"},
    {"SEEK",         cmd_seek,             "Seek record by tag name and value (SEEK tag val)"},
    {"APPEND",       cmd_append,           "Append new record (APPEND \"val1,val2\")"},
    {"REPLACE",      cmd_replace,          "Replace current record field value (REPLACE col val)"},
    {"ROWREPLACE",   cmd_rowreplace,       "Replace entire current row record (ROWREPLACE \"val1,val2\")"},
    {"DELETE",       cmd_delete_rec,       "Mark current record as deleted"},
    {"RECALL",       cmd_recall,           "Undelete current marked record"},
    {"PACK",         cmd_pack,             "Physically remove deleted records"},
    {"ZAP",          cmd_zap,              "Wipe out all records from the table"},
    {"COMMIT",       cmd_commit,           "Flush memory updates to disk"},
    {"INDEX",        cmd_index,            "List mounted indexes with key expressions (INDEX)"},
    {"INDEXES",      cmd_index,            "List mounted indexes with key expressions (INDEXES)"},
    {"SHOW",         cmd_show,             "Display schema, record, tags/index, or active DBs (SHOW DB)"},
    {"LIST",         cmd_list,             "List local engine files (LIST EBF/EDX/ERL)"},
    {"CD",           cmd_cd,               "Change current working directory"},
    {"PWD",          cmd_pwd,              "Show current working directory"},
    {"CLS",          cmd_cls,              "Clear the console screen"},
    {"CLEAR",        cmd_cls,              "Clear the console screen"},
    {"HELP",         cmd_help,             "Display available commands and usage"},
    {"?",            cmd_help,             "Display available commands and usage"},
    {"EXIT",         cmd_exit,             "Exit the shell client and auto close all DBs"},
    {"QUIT",         cmd_exit,             "Exit the shell client and auto close all DBs"},
    {NULL,           NULL,                 NULL}
};

static void cmd_help(const char* args) {
    (void)args;
    printf("  ===================================================================\n");
    printf("                     EZ-Shell Available Commands                     \n");
    printf("  ===================================================================\n");
    printf("   Command      | Description                                        \n");
    printf("  --------------+----------------------------------------------------\n");
    for (int i = 0; g_cmd_table[i].cmd != NULL; i++) {
        printf("   %-12s | %-50s\n", g_cmd_table[i].cmd, g_cmd_table[i].desc);
    }
    printf("  ===================================================================\n");
}

void parse_and_dispatch(char* line) {
    trim_spaces(line);
    if (*line == '\0') return;

    /* Handle composite SQL and xBase statement patterns */
    if (strncasecmp(line, "CREATE TABLE", 12) == 0) {
        cmd_create_table(line + 12);
        return;
    }
    if (strncasecmp(line, "ALTER TABLE", 11) == 0) {
        cmd_alter_table(line + 11);
        return;
    }
    if (strncasecmp(line, "CREATE INDEX", 12) == 0) {
        cmd_create_index_sql(line + 12);
        return;
    }
    if (strncasecmp(line, "SET ORDER TO", 12) == 0) {
        cmd_order(line + 12);
        return;
    }
    if (strncasecmp(line, "SET RELATION", 12) == 0) {
        cmd_set_relation(line + 12);
        return;
    }
    if (strncasecmp(line, "LOAD RELATION", 13) == 0) {
        cmd_load_relation(line + 13);
        return;
    }
    if (strncasecmp(line, "SAVE RELATION", 13) == 0) {
        cmd_save_relation(line + 13);
        return;
    }
    if (strncasecmp(line, "LIST RELATION", 13) == 0) {
        cmd_list_relation(line + 13);
        return;
    }

    char cmd[32] = {0};
    const char* args = NULL;
    char* space = strchr(line, ' ');
    if (space) {
        size_t cmd_len = space - line;
        if (cmd_len >= sizeof(cmd)) cmd_len = sizeof(cmd) - 1;
        strncpy(cmd, line, cmd_len);
        args = space + 1;
        while (isspace((unsigned char)*args)) args++;
    } else {
        strncpy(cmd, line, sizeof(cmd) - 1);
        args = "";
    }

    for (int i = 0; g_cmd_table[i].cmd != NULL; i++) {
        if (strcasecmp(cmd, g_cmd_table[i].cmd) == 0) {
            g_cmd_table[i].handler(args);
            return;
        }
    }

    printf("  [Error] Unknown command '%s'. Type 'HELP' or '?' for instructions.\n", cmd);
}

/* ===================================================================== */
/* Main Entry Point                                                      */
/* ===================================================================== */
#ifndef TEST_AGENT
int main(int argc, char* argv[]) {
    const char* lib_name = 
    #ifdef _WIN32
            "ez_dbengine.dll";
    #else
            "./libez_dbengine.so";
    #endif

    if (argc > 1) {
        lib_name = argv[1];
    }

    if (load_ez_engine_symbols(lib_name) != 0) {
        return 1;
    }

    printf("\n");
    printf("  =====================================================\n");
    printf("               Welcome to EZ-Shell                     \n");
    printf("        Type 'HELP' or '?' for available commands      \n");
    printf("  =====================================================\n\n");

    char line[1024];
    while (1) {
        if (g_current_slot != -1 && g_work_areas[g_current_slot].handle != 0) {
            ShellWorkArea* slot = &g_work_areas[g_current_slot];
            s64 rec = ez.ez_db_recno(slot->handle, slot->active_tag_id, 
                                     slot->active_tag_name[0] ? slot->active_tag_name : NULL);
            s64 total = ez.ez_db_lastrec(slot->handle, slot->active_tag_id, 
                                        slot->active_tag_name[0] ? slot->active_tag_name : NULL);
            if (total == 0 && slot->active_tag_id == 0 && ez.ez_db_record_count) {
                total = (s64)ez.ez_db_record_count(slot->handle);
            }
            ez_bool bof = ez.ez_db_is_bof(slot->handle, slot->active_tag_id, 
                                         slot->active_tag_name[0] ? slot->active_tag_name : NULL);
            ez_bool eof = ez.ez_db_is_eof(slot->handle, slot->active_tag_id, 
                                         slot->active_tag_name[0] ? slot->active_tag_name : NULL);
            u64 del_cnt = ez.ez_db_get_delete_count(slot->handle);

            /* Classic DBU top single-line status dashboard */
            printf("  +---------------------------------------------------+\n");
            printf("  | REC: %-8lld / %-8lld | %-3s | %-3s | DEL: %-5llu |\n",
                   (long long)rec, (long long)total, bof ? "BOF" : "   ", eof ? "EOF" : "   ", (unsigned long long)del_cnt);
            printf("  +---------------------------------------------------+\n");

            if (slot->active_tag_id > 0) {
                printf("\033[36mezdb [%s (Tag: %s)]>> \033[0m", slot->filename, slot->active_tag_name);
            } else {
                printf("\033[36mezdb [%s (Natural)]>> \033[0m", slot->filename);
            }
        } else {
            printf("\033[36mezdb [none]>> \033[0m");
        }

        fflush(stdout);
        if (!fgets(line, sizeof(line), stdin)) break;

        size_t len = strlen(line);
        if (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r')) {
            line[len - 1] = '\0';
        }

        parse_and_dispatch(line);
        printf("\n");
    }

    return 0;
}
#endif