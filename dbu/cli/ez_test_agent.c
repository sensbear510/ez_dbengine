#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ez_def.h"
#include "ez_engine_loader.h"

#ifdef _WIN32
    #ifndef strcasecmp
        #define strcasecmp _stricmp
    #endif
#endif

// 引用 dbu_shell.c 裡的符號與分派函式
extern void parse_and_dispatch(char* line);
extern int load_ez_engine_symbols(const char* lib_path);
extern LibHandle g_engine_lib;
extern int get_workarea_handle_by_name(const char* filename);

// 定義與 dbu_shell.c 對齊的結構
typedef struct {
    int index;
    unsigned long long handle;
    char filename[256];
    u32 active_tag_id;
    char active_tag_name[64];
} ShellWorkArea;

extern ShellWorkArea g_work_areas[];

void run_test_step(const char* test_desc, const char* cmd_line) {
    printf("\n=======================================================\n");
    printf(" [TEST AGENT] -> %s\n", test_desc);
    printf(" Command Line : %s\n", cmd_line);
    printf("=======================================================\n");
    
    char buffer[1024];
    strncpy(buffer, cmd_line, sizeof(buffer) - 1);
    buffer[sizeof(buffer) - 1] = '\0';

    parse_and_dispatch(buffer);
}

/**
 * test_and_dump_erl_relation
 * Tests building an ERL Relation View, verifies LEFT & INNER join semantics,
 * and validates .ERL persistence (save/load).
 */
void test_and_dump_erl_relation(void) {
    printf("\n=======================================================\n");
    printf(" [ERL AGENT EXEC] Phase: Build Relation View & Dump Data\n");
    printf("=======================================================\n");

    if (!ez.ez_rl_build_view || !ez.ez_rl_get_record_vector) {
        printf("  [Error] ERL Subsystem function pointers not loaded!\n");
        return;
    }

    if (ez.ez_rl_mgr_init) {
        ez.ez_rl_mgr_init();
    }

    int slot_master = get_workarea_handle_by_name("master.ebf");
    int slot_child  = get_workarea_handle_by_name("child.ebf");

    if (slot_master == -1 || slot_child == -1) {
        printf("  [Error] Failed to resolve DB slots for master.ebf or child.ebf\n");
        return;
    }

    u64 h_master = g_work_areas[slot_master].handle;
    u64 h_child  = g_work_areas[slot_child].handle;

    if (h_master == 0 || h_child == 0) {
        printf("  [Error] Failed to resolve DB handles (Master: 0x%llX, Child: 0x%llX)\n",
               (unsigned long long)h_master, (unsigned long long)h_child);
        return;
    }

    u64 ebfs[] = { h_master, h_child };

    EZ_RL_NODE_DESC nodes[4];
    memset(nodes, 0, sizeof(nodes));

    nodes[0].ebf_index = 0;
    strncpy((char*)nodes[0].field_name, "dept_id", 51);
    strncpy((char*)nodes[0].alias_name, "dept_id", 51);

    nodes[1].ebf_index = 0;
    strncpy((char*)nodes[1].field_name, "dept_name", 51);
    strncpy((char*)nodes[1].alias_name, "dept_name", 51);

    nodes[2].ebf_index = 1;
    strncpy((char*)nodes[2].field_name, "emp_id", 51);
    strncpy((char*)nodes[2].alias_name, "emp_id", 51);

    nodes[3].ebf_index = 1;
    strncpy((char*)nodes[3].field_name, "emp_name", 51);
    strncpy((char*)nodes[3].alias_name, "emp_name", 51);

    EZ_RL_LINK_DESC links[1];
    memset(&links[0], 0, sizeof(EZ_RL_LINK_DESC));
    links[0].parent_ebf_index     = 0;
    links[0].child_ebf_index      = 1;
    links[0].fk_field_count       = 1;
    links[0].parent_fk_offsets[0] = 0;
    links[0].parent_fk_lens[0]    = 4;
    strncpy((char*)links[0].child_tag_name, "idx_dept", sizeof(links[0].child_tag_name) - 1);

    EZ_RL_VIEW_DESC desc;
    memset(&desc, 0, sizeof(EZ_RL_VIEW_DESC));
    desc.relation_name = "v_dept_emp";
    desc.join_mode     = EZ_RL_JOIN_LEFT;
    desc.h_ebf_array   = ebfs;
    desc.ebf_count     = 2;
    desc.nodes         = nodes;
    desc.node_count    = sizeof(nodes) / sizeof(nodes[0]);
    desc.links         = links;
    desc.link_count    = sizeof(links) / sizeof(links[0]);

    /* TEST 1: LEFT JOIN Verification */
    printf("\n  >>> [1/3] Testing LEFT JOIN (Preserve Unmatched Master) <<<\n");
    u64 h_left_view = ez.ez_rl_build_view(&desc);
    if (h_left_view != 0) {
        u8 buffer[4096] = {0};
        u32 actual_count = 0;
        void* p_rel = ez._ez_get_relation_table ? ez._ez_get_relation_table(h_left_view) : (void*)h_left_view;
        
        ez.ez_rl_get_record_vector(p_rel, buffer, 10, &actual_count);
        printf("  [LEFT JOIN] Extracted Records: %u\n", actual_count);

        u32 stride = 4 + 20 + 4 + 15;
        for (u32 i = 0; i < actual_count; i++) {
            u8* p = buffer + (i * stride);
            char d_id[5] = {0}, d_name[21] = {0}, e_id[5] = {0}, e_name[16] = {0};
            memcpy(d_id, p, 4); memcpy(d_name, p + 4, 20); memcpy(e_id, p + 24, 4); memcpy(e_name, p + 28, 15);
            printf("    | #%-2u | %-4s | %-12s | %-4s | %-10s |\n", i + 1, d_id, d_name, e_id, e_name);
        }
        ez.ez_rl_destroy_view(h_left_view);
    }

    /* TEST 2: INNER JOIN Verification */
    printf("\n  >>> [2/3] Testing INNER JOIN (Filter Out Unmatched Records) <<<\n");
    desc.join_mode = EZ_RL_JOIN_INNER;
    u64 h_inner_view = ez.ez_rl_build_view(&desc);
    if (h_inner_view != 0) {
        u8 buffer[4096] = {0};
        u32 actual_count = 0;
        void* p_rel = ez._ez_get_relation_table ? ez._ez_get_relation_table(h_inner_view) : (void*)h_inner_view;
        
        ez.ez_rl_get_record_vector(p_rel, buffer, 10, &actual_count);
        printf("  [INNER JOIN] Extracted Records: %u\n", actual_count);

        u32 stride = 4 + 20 + 4 + 15;
        for (u32 i = 0; i < actual_count; i++) {
            u8* p = buffer + (i * stride);
            char d_id[5] = {0}, d_name[21] = {0}, e_id[5] = {0}, e_name[16] = {0};
            memcpy(d_id, p, 4); memcpy(d_name, p + 4, 20); memcpy(e_id, p + 24, 4); memcpy(e_name, p + 28, 15);
            printf("    | #%-2u | %-4s | %-12s | %-4s | %-10s |\n", i + 1, d_id, d_name, e_id, e_name);
        }
        ez.ez_rl_destroy_view(h_inner_view);
    }

    /* TEST 3: ERL File Save & Load Persistence */
    printf("\n  >>> [3/3] Testing ERL File Persistence (Save & Load) <<<\n");
    desc.join_mode = EZ_RL_JOIN_LEFT;
    const char* erl_file = "v_dept_emp.erl";

    if (ez.ez_rl_save_view_file) {
        EZ_STATUS st_save = ez.ez_rl_save_view_file(&desc, erl_file);
        printf("  [Save ERL] ez_rl_save_view_file -> Status: %s\n", 
               (st_save == EZ_SUCCESS) ? "SUCCESS" : "FAILED");
    }

    if (ez.ez_rl_load_view_file) {
        u64 h_loaded = ez.ez_rl_load_view_file(erl_file, ebfs, 2);
        if (h_loaded != 0) {
            printf("  [Load ERL] ez_rl_load_view_file -> Handle: 0x%016llX\n", (unsigned long long)h_loaded);
            
            u8 buffer[4096] = {0};
            u32 actual_count = 0;
            void* p_rel = ez._ez_get_relation_table ? ez._ez_get_relation_table(h_loaded) : (void*)h_loaded;
            
            ez.ez_rl_get_record_vector(p_rel, buffer, 10, &actual_count);
            printf("  [Loaded View] Fetched %u records from restored ERL view.\n", actual_count);
            ez.ez_rl_destroy_view(h_loaded);
        } else {
            printf("  [Load ERL] Failed to load .erl view file!\n");
        }
    }
}

int main(void) {
    printf("\n  +---------------------------------------------------+\n");
    printf("  | EZ-Shell Comprehensive CLI Command Test Agent     |\n");
    printf("  +---------------------------------------------------+\n\n");

    #ifdef _WIN32
        const char* lib_name = "ez_dbengine.dll";
    #elif __APPLE__
        const char* lib_name = "libez_dbengine.dylib";
    #else
        const char* lib_name = "./libez_dbengine.so";
    #endif

    printf("Loading engine library [%s] for Test Agent...\n", lib_name);
    if (load_ez_engine_symbols(lib_name) != 0) {
        printf("FATAL: Failed to load dynamic library '%s'. Please check file path.\n", lib_name);
        return 1;
    }

    /* ================================================================= */
    /* PHASE 1: 資料表建立與結構操作測試                                   */
    /* ================================================================= */
    run_test_step("1-1. 建立 Master 主表", "CREATE TABLE master.ebf (dept_id C(4), dept_name C(20))");
    run_test_step("1-2. 建立 Child 子表", "CREATE TABLE child.ebf (emp_id C(4), dept_id C(4), emp_name C(15))");
    run_test_step("1-3. 建立獨立測試表", "CREATE TABLE staff.ebf (id N(4), name C(20), salary N(8,2))");

    /* ================================================================= */
    /* PHASE 2: 資料庫開啟 (USE / OPEN) 與 工作區切換 (SELECT) 測試       */
    /* ================================================================= */
    run_test_step("2-1. 開啟 Master 主表", "USE master.ebf");
    run_test_step("2-2. 開啟 Child 子表", "USE child.ebf");
    run_test_step("2-3. 使用 OPEN 指令別名開啟 staff.ebf", "OPEN staff.ebf");
    run_test_step("2-4. 檢視當前所有開啟的 WorkAreas", "SHOW DB");
    run_test_step("2-5. 切換回 staff 資料庫", "SELECT staff.ebf");
    run_test_step("2-6. 檢視 staff 表的欄位結構 (FDT)", "SHOW SCHEMA");

    /* ================================================================= */
    /* PHASE 3: 資料寫入 (APPEND / ROWREPLACE) 與 讀取/檢視 (SHOW) 測試    */
    /* ================================================================= */
    run_test_step("3-1. 新增第 1 筆員工 (APPEND)", "APPEND \"1001,Alice,55000.00\"");
    run_test_step("3-2. 新增第 2 筆員工 (APPEND)", "APPEND \"1002,Bob,62000.00\"");
    run_test_step("3-3. 新增第 3 筆員工 (APPEND)", "APPEND \"1003,Charlie,71000.00\"");
    run_test_step("3-4. 新增第 4 筆員工 (APPEND)", "APPEND \"1004,David,48000.00\"");
    run_test_step("3-5. 提交寫入至磁碟 (COMMIT)", "COMMIT");
    run_test_step("3-6. 查詢總筆數 (TOTAL/LASTREC)", "TOTAL");
    run_test_step("3-7. 顯示目前游標所在記錄資料", "SHOW RECORD");

    /* ================================================================= */
    /* PHASE 4: 游標導航測試 (TOP, BOTTOM, SKIP, GOTO, RECNO, BOF, EOF)   */
    /* ================================================================= */
    run_test_step("4-1. 移動到第一筆 (TOP)", "TOP");
    run_test_step("4-2. 檢查目前筆數 (RECNO)", "RECNO");
    run_test_step("4-3. 檢查 BOF 旗標", "BOF");
    run_test_step("4-4. 向下移動 2 筆 (SKIP 2)", "SKIP 2");
    run_test_step("4-5. 檢查目前筆數 (RECNO)", "RECNO");
    run_test_step("4-6. 移動到最後一筆 (BOTTOM)", "BOTTOM");
    run_test_step("4-7. 檢查目前筆數 (RECNO)", "RECNO");
    run_test_step("4-8. 嘗試在末筆向下 (SKIP 1) 觸發 EOF", "SKIP 1");
    run_test_step("4-9. 檢查 EOF 旗標", "EOF");
    run_test_step("4-10. 直接跳至第 2 筆 (GOTO 2)", "GOTO 2");
    run_test_step("4-11. 顯示第 2 筆內容", "SHOW RECORD");

    /* ================================================================= */
    /* PHASE 5: 單欄修改 (REPLACE) 與 全行替換 (ROWREPLACE) 測試          */
    /* ================================================================= */
    run_test_step("5-1. 修改欄位 salary (REPLACE)", "REPLACE salary 65000.00");
    run_test_step("5-2. 檢視修改後的記錄", "SHOW RECORD");
    run_test_step("5-3. 全行置換 (ROWREPLACE)", "ROWREPLACE \"1002,Robert,66000.00\"");
    run_test_step("5-4. 檢視全行置換後的記錄", "SHOW RECORD");

    /* ================================================================= */
    /* PHASE 6: 軟刪除 (DELETE)、復原 (RECALL) 與 實體壓緊 (PACK) 測試     */
    /* ================================================================= */
    run_test_step("6-1. 刪除目前記錄 (DELETE)", "DELETE");
    run_test_step("6-2. 復原目前刪除記錄 (RECALL)", "RECALL");
    run_test_step("6-3. 再次刪除目前記錄 (DELETE)", "DELETE");
    run_test_step("6-4. 實體移除刪除筆數 (PACK)", "PACK");
    run_test_step("6-5. 檢查 PACK 後的總筆數 (TOTAL)", "TOTAL");

    /* ================================================================= */
    /* PHASE 7: 建立索引與多軌道 ORDER (ID / Name / Natural) 測試        */
    /* ================================================================= */
    run_test_step("7-1. 建立 name 欄位升冪索引", "CREATE INDEX idx_name ON staff (name)");
    run_test_step("7-2. 檢視資料表所有 EDX 索引 (SHOW TAGS)", "SHOW TAGS");
    run_test_step("7-3. 查詢目前 ORDER 狀態", "ORDER");
    run_test_step("7-4. 透過 Slot ID 切換至索引 1 (ORDER 1)", "ORDER 1");
    run_test_step("7-5. 索引順序移至首筆 (TOP)", "TOP");
    run_test_step("7-6. 顯示當前索引下的首筆記錄 (應按字母排序)", "SHOW RECORD");
    run_test_step("7-7. 切換回實體順序 (ORDER 0)", "ORDER 0");
    run_test_step("7-8. 實體順序移至首筆 (TOP)", "TOP");
    run_test_step("7-9. 顯示實體順序下的首筆記錄", "SHOW RECORD");
    run_test_step("7-10. 透過 Tag Name 切換索引 (ORDER idx_name)", "ORDER idx_name");
    run_test_step("7-11. 驗證 Tag Name 切換後的狀態", "ORDER");

    /* ================================================================= */
    /* PHASE 8: 查詢定位測試 (LOCATE 與 SEEK)                            */
    /* ================================================================= */
    run_test_step("8-1. 使用 SEEK 快速查詢 Bob (Robert)", "SEEK idx_name Robert");
    run_test_step("8-2. 檢查 FOUND 旗標", "FOUND");
    run_test_step("8-3. 顯示 SEEK 命中後的記錄", "SHOW RECORD");
    run_test_step("8-4. 切回實體順序 (ORDER 0)", "ORDER 0");
    run_test_step("8-5. 移到首筆準備 LOCATE", "TOP");
    run_test_step("8-6. 使用 LOCATE 循序搜尋 name=Alice", "LOCATE name Alice");
    run_test_step("8-7. 檢查 LOCATE 是否命中 (FOUND)", "FOUND");
    run_test_step("8-8. 顯示 LOCATE 命中後的記錄", "SHOW RECORD");

    /* ================================================================= */
    /* PHASE 9: 清理 staff 表 (CLOSE / ZAP)                              */
    /* ================================================================= */
    run_test_step("9-1. 抹除 staff 表中所有資料 (ZAP)", "ZAP");
    run_test_step("9-2. 檢查 ZAP 後筆數 (TOTAL)", "TOTAL");
    run_test_step("9-3. 關閉 staff 表 (CLOSE)", "CLOSE staff.ebf");

    /* ================================================================= */
    /* PHASE 10: 原有 Master-Child 關聯視圖 (ERL) 完整測試流程           */
    /* ================================================================= */
    run_test_step("10-1. 替 Child 建立 dept_id 索引", "SELECT child.ebf");
    run_test_step("10-2. 建立 Child 關聯索引", "CREATE INDEX idx_dept ON child (dept_id)");

    run_test_step("10-3. 切回 Master 並寫入部門資料", "SELECT master.ebf");
    run_test_step("10-4. 寫入部門 A", "APPEND \"D01,研發部\"");
    run_test_step("10-5. 寫入部門 B", "APPEND \"D02,業務部\"");
    run_test_step("10-6. 寫入未匹配部門 C (檢驗 JOIN)", "APPEND \"D03,財務部\"");

    run_test_step("10-7. 切換至 Child 並寫入員工資料", "SELECT child.ebf");
    run_test_step("10-8. 寫入員工 1 (屬於 D01)", "APPEND \"E001,D01,張三\"");
    run_test_step("10-9. 寫入員工 2 (屬於 D01)", "APPEND \"E002,D01,李四\"");
    run_test_step("10-10. 寫入員工 3 (屬於 D02)", "APPEND \"E003,D02,王五\"");

    run_test_step("10-11. 切回 Master 準備進行關聯定位", "SELECT master.ebf");
    run_test_step("10-12. 建立 Master 索引", "CREATE INDEX idx_did ON master (dept_id) UNIQUE");
    run_test_step("10-13. 搜尋 Master 的 D01 部門", "SEEK idx_did D01");
    run_test_step("10-14. 確認 Master 定位成功 (RECNO)", "RECNO");

    // 真正執行 ERL View 建立與驗證
    test_and_dump_erl_relation();

    /* ================================================================= */
    /* PHASE 11: 系統清理與安全退出                                       */
    /* ================================================================= */
    run_test_step("11-1. 關閉剩餘所有資料庫", "CLOSE");
    run_test_step("11-2. 退出測試代理 (EXIT)", "EXIT");

    return 0;
}