/* =================================================================================
 * 📁 FILE: ez_dbengine.js
 * ---------------------------------------------------------------------------------
 * Full Node.js High-Concurrency Stateless Driver for ez_dbengine (Koffi FFI)
 * ================================================================================= */

const fs = require('fs');
const path = require('path');
const koffi = require('koffi');

function resolveLibrary() {
    const isWin = process.platform === 'win32';
    const isMac = process.platform === 'darwin';
    let libName = 'libez_dbengine.so';
    if (isWin) libName = 'ez_dbengine.dll';
    else if (isMac) libName = 'libez_dbengine.dylib';

    const candidatePaths = [
        path.join(__dirname, isWin ? 'run_win' : 'run_linux', libName),
        path.join(__dirname, libName),
        path.join(process.cwd(), libName),
        path.join(__dirname, '..', '..', isWin ? 'build_win/bin/Release' : 'build_linux/lib', libName),
        path.join(__dirname, '..', '..', isWin ? 'build_win/bin' : 'build_linux/lib', libName)
    ];

    for (const p of candidatePaths) {
        if (fs.existsSync(p)) {
            return koffi.load(p);
        }
    }
    return koffi.load(libName);
}

const lib = resolveLibrary();

// =========================================================================
// 1. C-Core Structure Alignment (ez_def.h / ez_relation_mgr.h 1-Byte Alignment)
// =========================================================================

// 52 + 1 + 4 + 1 + 1 + 4 + 1 = 64 Bytes, exactly aligned with C-Core definitions
const EZ_FIELD_NODE = koffi.pack('EZ_FIELD_NODE', {
    name: koffi.array('uint8_t', 52),
    type: 'uint8_t',
    len: 'uint32_t',
    dec: 'uint8_t',
    storage: 'uint8_t',
    offset: 'uint32_t',
    zbf_sequence: 'uint8_t'
});

const EZ_TAG_INFO = koffi.pack('EZ_TAG_INFO', {
    tag_name: koffi.array('char', 64),
    key_len: 'uint32_t',
    key_type: 'uint32_t',
    root_ptr: 'uint64_t',
    node_count: 'uint64_t',
    is_descending: 'uint32_t',
    h_slot: 'uint32_t',
    field_offsets: koffi.array('uint32_t', 8),
    field_lens: koffi.array('uint32_t', 8),
    field_count: 'uint8_t',
    is_unique: 'uint8_t',
    _final_pad: koffi.array('uint8_t', 94)
});

const EZ_MIGRATE_REPORT = koffi.pack('EZ_MIGRATE_REPORT', {
    status: 'uint32_t',
    error_code: 'uint32_t',
    total_recs: 'uint64_t',
    recovered_recs: 'uint64_t',
    message: koffi.array('char', 128)
});

const EZ_BLOB_PTR = koffi.pack('EZ_BLOB_PTR', {
    blob_offset: 'uint64_t',
    logical_length: 'uint32_t',
    physical_length: 'uint32_t',
    file_sequence: 'uint32_t',
    flags: 'uint32_t'
});

const EZ_RL_NODE_DESC = koffi.struct('EZ_RL_NODE_DESC', {
    ebf_index: 'uint16_t',
    field_name: koffi.array('char', 52),
    alias_name: koffi.array('char', 52)
});

const EZ_RL_LINK_DESC = koffi.struct('EZ_RL_LINK_DESC', {
    parent_ebf_index: 'uint16_t',
    child_ebf_index: 'uint16_t',
    fk_field_count: 'uint8_t',
    parent_fk_offsets: koffi.array('uint16_t', 8),
    parent_fk_lens: koffi.array('uint16_t', 8),
    child_tag_name: koffi.array('char', 48)
});

const EZ_RL_VIEW_DESC = koffi.struct('EZ_RL_VIEW_DESC', {
    relation_name: 'string',
    join_mode: 'uint32_t',
    h_ebf_array: koffi.pointer('uint64_t'),
    ebf_count: 'uint16_t',
    nodes: koffi.pointer(EZ_RL_NODE_DESC),
    node_count: 'uint16_t',
    links: koffi.pointer(EZ_RL_LINK_DESC),
    link_count: 'uint16_t'
});

// =========================================================================
// 2. Native C Symbol Bindings
// =========================================================================

const native = {
    // Group A: Lifecycle & Schema Maintenance
    dbcreate: lib.func('int ez_db_create(const char *path, const EZ_FIELD_NODE *map)'),
    dbalter: lib.func('int ez_db_alter(uint64_t h, const char *path, const EZ_FIELD_NODE *new_map, _Out_ EZ_MIGRATE_REPORT *report)'),
    dbReconstruct: lib.func('int ez_db_reconstruct(uint64_t h, const char *path, _Out_ EZ_MIGRATE_REPORT *report)'),
    dbuse: lib.func('uint64_t ez_db_use(const char *path, _Out_ EZ_MIGRATE_REPORT *report)'),
    dbopen: lib.func('uint64_t ez_db_open(const char *path, _Out_ EZ_MIGRATE_REPORT *report)'),
    dbclose: lib.func('int ez_db_close(uint64_t h)'),
    dbcloseAll: lib.func('int ez_db_close_all()'),
    dbSetVacuum: lib.func('void ez_db_set_vacuum(uint64_t h, float threshold, uint32_t min_deleted)'),
    dbGetNameFromPath: lib.func('void ez_db_get_name_from_path(const char *path, _Out_ char *out_name, uint32_t max_len)'),

    // Group B: Dual-Track Navigation & Status
    dbgotop: lib.func('int ez_db_gotop(uint64_t h, uint32_t tag_id, const char *tag_name)'),
    dbgobottom: lib.func('int ez_db_gobottom(uint64_t h, uint32_t tag_id, const char *tag_name)'),
    dbskip: lib.func('int ez_db_skip(uint64_t h, uint32_t tag_id, const char *tag_name, int32_t n)'),
    dbgoto: lib.func('int ez_db_goto(uint64_t h, uint32_t tag_id, const char *tag_name, uint64_t recno)'),
    dbEof: lib.func('bool ez_db_is_eof(uint64_t h, uint32_t tag_id, const char *tag_name)'),
    dbBof: lib.func('bool ez_db_is_bof(uint64_t h, uint32_t tag_id, const char *tag_name)'),
    dbFound: lib.func('bool ez_db_is_found(uint64_t h, uint32_t tag_id, const char *tag_name)'),
    dbRecno: lib.func('int64_t ez_db_recno(uint64_t h, uint32_t tag_id, const char *tag_name)'),
    dbLastrec: lib.func('int64_t ez_db_lastrec(uint64_t h, uint32_t tag_id, const char *tag_name)'),
    dbRecsize: lib.func('uint32_t ez_db_recsize(uint64_t h)'),
    dbRecordCount: lib.func('uint64_t ez_db_record_count(uint64_t h)'),

    // Group C: Data Access & Atomic Mutations (data uses const char * to guarantee null-terminated UTF-8)
    getRecord: lib.func('int ez_db_get_record(uint64_t h, uint32_t tag_id, const char *tag_name, _Out_ uint8_t *buffer, uint32_t buffer_size, bool include_deleted)'),
    getRecordVector: lib.func('int ez_db_get_record_vector(uint64_t h, uint32_t tag_id, const char *tag_name, _Out_ void *out_struct_array, _Inout_ uint32_t *p_count, uint32_t struct_size, bool strip_str, bool include_deleted)'),
    dbseekByTag: lib.func('int ez_db_seek_by_tag(uint64_t h, const char *tag_name, ...)'),
    dbseekByTagId: lib.func('int ez_db_seek_by_tag_id(uint64_t h, uint32_t tag_id, ...)'),
    dbseekByTagArray: lib.func('int ez_db_seek_by_tag_array(uint64_t h, const char *tag_name, const void **values)'),
    dbseekByTagIdArray: lib.func('int ez_db_seek_by_tag_id_array(uint64_t h, uint32_t tag_id, const void **values)'),
    dblocate: lib.func('int ez_db_locate(uint64_t h, const char *fieldname, const void *target_value, bool partial_match)'),
    dbappend: lib.func('int ez_db_append(uint64_t h, const char *data, uint32_t rec_count, const char *delim)'),
    dbinsert: lib.func('int ez_db_insert(uint64_t h, const char *data, uint32_t rec_count, const char *delim)'),
    dbrowreplace: lib.func('int ez_db_row_replace(uint64_t h, uint64_t row_id, const char *data, const char *delim)'),
    dbreplace: lib.func('int ez_db_replace(uint64_t h, uint64_t row_id, const char *fieldname, const void *val)'),
    dbdeleted: lib.func('bool ez_db_is_deleted(uint64_t h, uint64_t row_id)'),
    dbdelete: lib.func('int ez_db_delete(uint64_t h, uint64_t row_id)'),
    dbrecall: lib.func('int ez_db_recall(uint64_t h, uint64_t row_id)'),
    dbpack: lib.func('int ez_db_pack(uint64_t h, const char *path)'),
    dbzap: lib.func('int ez_db_zap(uint64_t h)'),
    dbcommit: lib.func('int ez_db_commit(uint64_t h)'),
    dbGetBlobData: lib.func('int ez_db_get_blob_data(uint64_t h, const EZ_BLOB_PTR *blob_ptr, _Out_ void *out_buf, uint32_t out_buf_size)'),

    // Group D: Index Maintenance
    dbcreateIndex: lib.func('int ez_db_create_index(uint64_t h, const char *tag_name, const char *fields_str, bool is_unique)'),
    dbMountIndex: lib.func('int ez_db_mount_index(uint64_t h, const char *edx_path, uint32_t slot_id)'),
    dbPurgeDuplicates: lib.func('int ez_db_purge_duplicates(uint64_t h, uint32_t tag_id, uint64_t keep_row_id)'),
    dbExtractDuplicates: lib.func('int ez_db_extract_duplicates(uint64_t h, uint32_t tag_id)'),

    // Group E: Reflection & Diagnostics
    dbGetFieldNames: lib.func('int ez_db_get_field_names(uint64_t h, _Out_ char *out_buf, uint32_t buf_size, const char *delim)'),
    dbGetIndexKey: lib.func('int ez_db_get_index_key(uint64_t h, uint32_t tag_id, const char *tag_name, _Out_ char *out_buf, uint32_t out_buf_len)'),
    dbGetFdt: lib.func('EZ_FIELD_NODE *ez_db_get_fdt(uint64_t h)'),
    dbGetTags: lib.func('EZ_TAG_INFO *ez_db_get_tags(uint64_t h)'),
    dbGetDeleteCount: lib.func('uint64_t ez_db_get_delete_count(uint64_t h)'),
    dbDumpRecord: lib.func('void ez_db_dump_record(uint64_t h, const void *record_payload)'),
    dbDumpWorkarea: lib.func('void ez_db_dump_workarea(uint64_t h)'),

    // Error Diagnostics Subsystem (ez_engine.h)
    errstr: lib.func('const char * ez_errstr(int status)'),
    lastError: lib.func('const char * ez_last_error(void)'),

    // Relation View Subsystem (ez_relation_mgr.h)
    rlMgrInit: lib.func('int ez_rl_mgr_init(void)'),
    rlMgrCleanup: lib.func('int ez_rl_mgr_cleanup(void)'),
    rlBuildView: lib.func('uint64_t ez_rl_build_view(const EZ_RL_VIEW_DESC *desc)'),
    rlDestroyView: lib.func('int ez_rl_destroy_view(uint64_t h_rel)'),
    rlGetRelationTable: lib.func('void * _ez_get_relation_table(uint64_t h_rel)'),
    rlGetRecordVector: lib.func('int ez_rl_get_record_vector(void *rel, _Out_ uint8_t *out_buffer, uint32_t request_count, _Inout_ uint32_t *actual_count)'),
    rlSaveViewFile: lib.func('int ez_rl_save_view_file(const EZ_RL_VIEW_DESC *desc, const char *erl_path)'),
    rlLoadViewFile: lib.func('uint64_t ez_rl_load_view_file(const char *erl_path, const uint64_t *h_ebf_array, uint16_t ebf_count)'),

    // Quantization Subsystem (ez_quant.h)
    quantCompressF32: lib.func('int ez_quant_compress_f32_4bit(const float *in_vec, uint32_t dim, _Out_ uint8_t *out_packed, _Inout_ float *out_min, _Inout_ float *out_max)'),
    quantDecompressF32: lib.func('int ez_quant_decompress_4bit_f32(const uint8_t *in_packed, float min_val, float max_val, uint32_t dim, _Out_ float *out_vec)')
};

// =========================================================================
// 3. High-Level Stateless Singleton Driver (EzDbEngine Stateless Singleton)
// =========================================================================

class EzDbEngine {
    static #instance = null;

    constructor() {
        if (EzDbEngine.#instance) return EzDbEngine.#instance;
        EzDbEngine.#instance = this;
    }

    static getInstance() {
        if (!EzDbEngine.#instance) {
            EzDbEngine.#instance = new EzDbEngine();
        }
        return EzDbEngine.#instance;
    }

    // --- Error Diagnostics Subsystem ---
    errStr(status) {
        const ptr = native.errstr(status);
        return ptr || 'Unknown engine error';
    }

    lastError() {
        const ptr = native.lastError();
        return ptr || '';
    }

    getDetailedError(status) {
        const dyn = this.lastError();
        const desc = this.errStr(status);
        if (dyn && dyn.length > 0) {
            return `[${desc}] ${dyn} (Code: ${status})`;
        }
        return `[${desc}] (Code: ${status})`;
    }

    // --- Group A: Lifecycle & Schema Maintenance ---
    createDatabase(filePath, schema) {
        let currentOffset = 0;
        const rawFields = [];

        for (const f of schema) {
            const raw = f._toRawStruct(currentOffset);
            rawFields.push(raw);
            currentOffset += f.length; // Accumulate field offsets
        }

        // Sentinel Terminator Node (type = 0)
        rawFields.push({
            name: Array(52).fill(0),
            type: 0,
            len: 0,
            dec: 0,
            storage: 0,
            offset: currentOffset,
            zbf_sequence: 0
        });

        const status = native.dbcreate(filePath, rawFields);
        return status;
    }

    use(filePath) {
        const report = {};
        const handle = native.dbuse(filePath, report);
        if (!handle || handle === 0n) {
            const msg = report.message ? Buffer.from(report.message).toString('utf8').replace(/\0/g, '') : '';
            const dynErr = this.lastError();
            throw new Error(`ez_db_use failed: ${filePath} | ${msg} ${dynErr}`);
        }
        return handle;
    }

    open(filePath) {
        return this.use(filePath);
    }

    close(handle) {
        if (!handle) return -106;
        return native.dbclose(handle);
    }

    closeAll() {
        return native.dbcloseAll();
    }

    setVacuum(handle, threshold, minDeleted) {
        native.dbSetVacuum(handle, threshold, minDeleted);
    }

    getNameFromPath(filePath, maxLen = 64) {
        const buf = Buffer.alloc(maxLen);
        native.dbGetNameFromPath(filePath, buf, maxLen);
        return buf.toString('utf8').replace(/\0/g, '');
    }

    // --- Group B: Dual-Track Navigation & Status ---
    goTop(handle, tagId = 0, tagName = null) {
        return native.dbgotop(handle, tagId, tagName);
    }

    goBottom(handle, tagId = 0, tagName = null) {
        return native.dbgobottom(handle, tagId, tagName);
    }

    skip(handle, step = 1, tagId = 0, tagName = null) {
        return native.dbskip(handle, tagId, tagName, step);
    }

    goTo(handle, recordNumber, tagId = 0, tagName = null) {
        return native.dbgoto(handle, tagId, tagName, BigInt(recordNumber));
    }

    isEof(handle, tagId = 0, tagName = null) {
        return native.dbEof(handle, tagId, tagName);
    }

    isBof(handle, tagId = 0, tagName = null) {
        return native.dbBof(handle, tagId, tagName);
    }

    isFound(handle, tagId = 0, tagName = null) {
        return native.dbFound(handle, tagId, tagName);
    }

    getRecNo(handle, tagId = 0, tagName = null) {
        return Number(native.dbRecno(handle, tagId, tagName));
    }

    getLastRec(handle, tagId = 0, tagName = null) {
        return Number(native.dbLastrec(handle, tagId, tagName));
    }

    getRecordSize(handle) {
        return native.dbRecsize(handle);
    }

    getRecordCount(handle) {
        return Number(native.dbRecordCount(handle));
    }

    // --- Group C: Data Access & Atomic Mutations ---
    getRecord(handle, includeDeleted = false, tagId = 0, tagName = null) {
        const recSize = this.getRecordSize(handle);
        if (recSize <= 0) return null;
        const buffer = Buffer.alloc(recSize);
        const status = native.getRecord(handle, tagId, tagName, buffer, recSize, includeDeleted);
        return status === 0 ? buffer : null;
    }

    seekByTag(handle, tagName, key) {
        return native.dbseekByTagArray(handle, tagName, [key, null]) === 0;
    }

    seekByTagId(handle, tagId, key) {
        return native.dbseekByTagIdArray(handle, tagId, [key, null]) === 0;
    }

    seekByTagArray(handle, tagName, keys) {
        return native.dbseekByTagArray(handle, tagName, [...keys, null]);
    }

    seekByTagIdArray(handle, tagId, keys) {
        return native.dbseekByTagIdArray(handle, tagId, [...keys, null]);
    }

    locate(handle, fieldName, targetValue, partialMatch = false) {
        return native.dblocate(handle, fieldName, targetValue, partialMatch);
    }

    append(handle, line, count = 1, delimiter = ',') {
        return native.dbappend(handle, line, count, delimiter);
    }

    insert(handle, line, count = 1, delimiter = ',') {
        return native.dbinsert(handle, line, count, delimiter);
    }

    rowReplace(handle, rowId, line, delimiter = ',') {
        return native.dbrowreplace(handle, BigInt(rowId), line, delimiter);
    }

    replace(handle, rowId, fieldName, value) {
        return native.dbreplace(handle, BigInt(rowId), fieldName, value);
    }

    isDeleted(handle, rowId) {
        return native.dbdeleted(handle, BigInt(rowId));
    }

    delete(handle, rowId) {
        return native.dbdelete(handle, BigInt(rowId));
    }

    recall(handle, rowId) {
        return native.dbrecall(handle, BigInt(rowId));
    }

    pack(handle, filePath = '') {
        return native.dbpack(handle, filePath);
    }

    zap(handle) {
        return native.dbzap(handle);
    }

    commit(handle) {
        return native.dbcommit(handle);
    }

    // --- Group D: Index Maintenance ---
    createIndex(handle, tagName, fieldsStr, isUnique = true) {
        return native.dbcreateIndex(handle, tagName, fieldsStr, isUnique);
    }

    mountIndex(handle, edxPath, slotId) {
        return native.dbMountIndex(handle, edxPath, slotId);
    }

    purgeDuplicates(handle, tagId, keepRowId = 0) {
        return native.dbPurgeDuplicates(handle, tagId, BigInt(keepRowId));
    }

    extractDuplicates(handle, tagId) {
        return native.dbExtractDuplicates(handle, tagId);
    }

    // --- Group E: Reflection & Diagnostics ---
    getFieldNames(handle, delim = ',', bufSize = 1024) {
        const buf = Buffer.alloc(bufSize);
        if (native.dbGetFieldNames(handle, buf, bufSize, delim) !== 0) return '';
        return buf.toString('utf8').replace(/\0/g, '');
    }

    /**
     * Resolves the active index key/expression (e.g. "code" or "date+code") for a specified tag.
     * Supports resolution via tagId (1~8) and/or tagName.
     *
     * @param {bigint|number} handle WorkArea fingerprint handle
     * @param {number} tagId Tag slot ID (1~8); 0 indicates omitted
     * @param {string|null} tagName Tag name string; null or empty indicates omitted
     * @param {number} bufSize Buffer capacity for key string (default 128 bytes)
     * @returns {string} Resolved expression string, or empty string on failure
     */
    getIndexKey(handle, tagId = 0, tagName = null, bufSize = 128) {
        if (!handle || bufSize <= 0) return '';

        const buf = Buffer.alloc(bufSize);
        const normalizedTagName = (tagName && tagName.length > 0) ? tagName : null;

        const status = native.dbGetIndexKey(handle, tagId, normalizedTagName, buf, bufSize);
        if (status === 0) { // EZ_SUCCESS
            return buf.toString('utf8').replace(/\0.*$/g, '').trim();
        }
        return '';
    }

    getTags(handle) {
        const pTags = native.dbGetTags(handle);
        if (!pTags) return [];

        const tags = [];
        for (let i = 0; i < 8; i++) {
            const tag = koffi.decode(pTags, EZ_TAG_INFO, i);
            if (!tag.tag_name || tag.tag_name[0] === 0) break;

            const nameBuf = Buffer.from(tag.tag_name);
            const strTagName = nameBuf.toString('utf8').replace(/\0.*$/g, '').trim();
            if (strTagName.length === 0) continue;

            const slotNum = i + 1;
            // Delegate directly to C-Core ez_db_get_index_key for dynamic resolution
            let resolvedExpr = this.getIndexKey(handle, slotNum, strTagName);
            if (!resolvedExpr || resolvedExpr.length === 0) {
                resolvedExpr = strTagName;
            }

            tags.push({
                slot: slotNum,
                name: strTagName,
                expression: resolvedExpr,
                isUnique: tag.is_unique === 1,
                nodeCount: Number(tag.node_count)
            });
        }
        return tags;
    }
    
    getFdt(handle) {
        const pFdt = native.dbGetFdt(handle);
        if (!pFdt) return [];

        const list = [];
        let i = 0;
        while (true) {
            const node = koffi.decode(pFdt, EZ_FIELD_NODE, i);
            if (node.type === 0) break;
            const nameStr = Buffer.from(node.name).toString('utf8').replace(/\0.*$/g, '');
            list.push({
                name: nameStr,
                type: String.fromCharCode(node.type),
                length: node.len,
                dec: node.dec
            });
            i++;
        }
        return list;
    }

    debugDumpWorkarea(handle) {
        native.dbDumpWorkarea(handle);
    }

    dumpRecord(handle, recordBuffer) {
        native.dbDumpRecord(handle, recordBuffer);
    }

    // --- Relation View Subsystem ---
    relationMgrInit() {
        return native.rlMgrInit();
    }

    relationMgrCleanup() {
        return native.rlMgrCleanup();
    }

    relationBuildView(desc) {
        return native.rlBuildView(desc);
    }

    relationDestroyView(hRel) {
        return native.rlDestroyView(hRel);
    }

    relationGetTable(hRel) {
        return native.rlGetRelationTable(hRel);
    }

    relationSaveViewFile(desc, erlPath) {
        return native.rlSaveViewFile(desc, erlPath);
    }

    relationLoadViewFile(erlPath, ebfHandles) {
        return native.rlLoadViewFile(erlPath, ebfHandles, ebfHandles.length);
    }

    // --- Quantization Subsystem ---
    quantCompressF32(inVec, dim) {
        const outPacked = Buffer.alloc(dim / 2);
        const minRef = [0];
        const maxRef = [0];
        const status = native.quantCompressF32(inVec, dim, outPacked, minRef, maxRef);
        return { success: status === 0, status, packed: outPacked, min: minRef[0], max: maxRef[0] };
    }

    quantDecompressF32(inPacked, minVal, maxVal, dim) {
        const outVec = new Float32Array(dim);
        const status = native.quantDecompressF32(inPacked, minVal, maxVal, dim, outVec);
        return { success: status === 0, status, vec: outVec };
    }
}

const FieldType = Object.freeze({
    Character: 'C',
    Numeric: 'N',
    Date: 'D',
    Logical: 'L',
    Integer: 'I',
    Memo: 'M',
    Binary: 'B'
});

class FieldDefinition {
    constructor(name, type, length, decimals = 0) {
        this.name = name;
        this.type = type;
        this.length = length;
        this.decimals = decimals;
    }

    _toRawStruct(calculatedOffset = 0) {
        const nameBuffer = Buffer.alloc(52, 0);
        nameBuffer.write(this.name, 0, 'utf8');

        return {
            name: Array.from(nameBuffer),
            type: this.type.charCodeAt(0),
            len: this.length,
            dec: this.decimals,
            storage: 0,
            offset: calculatedOffset,
            zbf_sequence: 0
        };
    }
}

module.exports = {
    EzDbEngine,
    FieldDefinition,
    FieldType
};