using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Collections.Generic;

namespace EzDbEngine
{
    // =========================================================================
    // Struct Alignment (Preserving exact original layout definitions)
    // =========================================================================

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    public struct EZ_FIELD_NODE
    {
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 52)]
        public byte[] name;
        public byte type;
        public uint len;
        public byte dec;
        public byte storage;
        public uint offset;
        public byte zbf_sequence;

        public static EZ_FIELD_NODE Create(string fieldName, char fieldType, uint length, byte decimalPlaces = 0)
        {
            var node = new EZ_FIELD_NODE
            {
                name = new byte[52],
                type = (byte)fieldType,
                len = length,
                dec = decimalPlaces,
                storage = 0,
                offset = 0,
                zbf_sequence = 0                
            };
            byte[] nameBytes = Encoding.UTF8.GetBytes(fieldName);
            Array.Copy(nameBytes, node.name, Math.Min(nameBytes.Length, 51));
            return node;
        }

        public string GetName()
        {
            if (name == null) return string.Empty;
            int nullIdx = Array.IndexOf(name, (byte)0);
            int len = nullIdx >= 0 ? nullIdx : name.Length;
            return Encoding.UTF8.GetString(name, 0, len);
        }
    }

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    public struct EZ_TAG_INFO
    {
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 64)]
        public byte[] tag_name;
        public uint key_len;
        public uint key_type;
        public ulong root_ptr;
        public ulong node_count;
        public uint is_descending;
        public uint h_slot;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 8)]
        public uint[] field_offsets;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 8)]
        public uint[] field_lens;
        public byte field_count;
        public byte is_unique;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 94)]
        public byte[] _final_pad;
    }

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    public struct EZ_MIGRATE_REPORT
    {
        public uint status;
        public uint error_code;
        public ulong total_recs;
        public ulong recovered_recs;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 128)]
        public byte[] message;

        public string GetMessage()
        {
            if (message == null) return string.Empty;
            int nullIdx = Array.IndexOf(message, (byte)0);
            int len = nullIdx >= 0 ? nullIdx : message.Length;
            return Encoding.UTF8.GetString(message, 0, len);
        }
    }

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    public struct EZ_BLOB_PTR
    {
        public ulong blob_offset;
        public uint logical_length;
        public uint physical_length;
        public uint file_sequence;
        public uint flags;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct EZ_RL_NODE_DESC
    {
        public ushort ebf_index;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 52)]
        public byte[] field_name;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 52)]
        public byte[] alias_name;

        public static EZ_RL_NODE_DESC Create(ushort ebfIdx, string fName, string aName = "")
        {
            var desc = new EZ_RL_NODE_DESC
            {
                ebf_index = ebfIdx,
                field_name = new byte[52],
                alias_name = new byte[52]
            };
            byte[] fn = Encoding.UTF8.GetBytes(fName);
            byte[] an = Encoding.UTF8.GetBytes(string.IsNullOrEmpty(aName) ? fName : aName);
            Array.Copy(fn, desc.field_name, Math.Min(fn.Length, 51));
            Array.Copy(an, desc.alias_name, Math.Min(an.Length, 51));
            return desc;
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct EZ_RL_LINK_DESC
    {
        public ushort parent_ebf_index;
        public ushort child_ebf_index;
        public byte fk_field_count;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 8)]
        public ushort[] parent_fk_offsets;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 8)]
        public ushort[] parent_fk_lens;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 48)]
        public byte[] child_tag_name;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct EZ_RL_VIEW_DESC
    {
        [MarshalAs(UnmanagedType.LPStr)]
        public string relation_name;
        public uint join_mode;
        public IntPtr h_ebf_array; // const u64*
        public ushort ebf_count;
        public IntPtr nodes;       // const EZ_RL_NODE_DESC*
        public ushort node_count;
        public IntPtr links;       // const EZ_RL_LINK_DESC*
        public ushort link_count;
    }

    public delegate void EZ_STATE_OBSERVER(uint slot, uint ev, ulong offset, uint len, IntPtr buffer);

    // =========================================================================
    // Native P/Invoke Primitive Exports
    // =========================================================================

    public static class NativeEngine
    {
        public const string LIB_NAME = "ez_dbengine";

        static NativeEngine()
        {
            NativeLibrary.SetDllImportResolver(typeof(NativeEngine).Assembly, (libraryName, assembly, searchPath) =>
            {
                if (libraryName == LIB_NAME)
                {
                    string extension = RuntimeInformation.IsOSPlatform(OSPlatform.Windows) ? ".dll" : ".so";
                    string fileName = $"ez_dbengine{extension}";
                    if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows) && !fileName.StartsWith("lib"))
                    {
                        fileName = $"lib{fileName}";
                    }

                    string baseDir = AppContext.BaseDirectory;
                    string directPath = Path.Combine(baseDir, fileName);
                    if (File.Exists(directPath)) return NativeLibrary.Load(directPath);

                    string cwdPath = Path.Combine(Directory.GetCurrentDirectory(), fileName);
                    if (File.Exists(cwdPath)) return NativeLibrary.Load(cwdPath);

                    string runDir = RuntimeInformation.IsOSPlatform(OSPlatform.Windows) ? "run_win" : "run_linux";
                    string relativeRun = Path.Combine(baseDir, runDir, fileName);
                    if (File.Exists(relativeRun)) return NativeLibrary.Load(relativeRun);
                }
                return IntPtr.Zero;
            });
        }

        // Group A: Lifecycle & Schema Maintenance
        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern int ez_db_create(string path, [In] EZ_FIELD_NODE[] map);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern int ez_db_alter(ulong h, string path, [In, Out] EZ_FIELD_NODE[] new_map, ref EZ_MIGRATE_REPORT report);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern int ez_db_reconstruct(ulong h, string path, ref EZ_MIGRATE_REPORT report);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern ulong ez_db_use(string path, ref EZ_MIGRATE_REPORT report);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern ulong ez_db_open(string path, ref EZ_MIGRATE_REPORT report);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl)]
        public static extern int ez_db_close(ulong h);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl)]
        public static extern int ez_db_close_all();

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl)]
        public static extern void ez_db_set_vacuum(ulong h, float threshold, uint min_deleted);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern void ez_db_get_name_from_path(string path, [Out] byte[] out_name, uint max_len);

        // Group B: Dual-Track Navigation & Status
        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern int ez_db_gotop(ulong h, uint tag_id, string? tag_name);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern int ez_db_gobottom(ulong h, uint tag_id, string? tag_name);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern int ez_db_skip(ulong h, uint tag_id, string? tag_name, int n);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern int ez_db_goto(ulong h, uint tag_id, string? tag_name, ulong recno);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        [return: MarshalAs(UnmanagedType.I1)]
        public static extern bool ez_db_is_eof(ulong h, uint tag_id, string? tag_name);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        [return: MarshalAs(UnmanagedType.I1)]
        public static extern bool ez_db_is_bof(ulong h, uint tag_id, string? tag_name);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        [return: MarshalAs(UnmanagedType.I1)]
        public static extern bool ez_db_is_found(ulong h, uint tag_id, string? tag_name);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern long ez_db_recno(ulong h, uint tag_id, string? tag_name);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern long ez_db_lastrec(ulong h, uint tag_id, string? tag_name);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl)]
        public static extern uint ez_db_recsize(ulong h);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl)]
        public static extern ulong ez_db_record_count(ulong h);

        // Group C: Data Access & Atomic Updates (Passing UTF-8 payloads)
        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern int ez_db_get_record(ulong h, uint tag_id, string? tag_name, [Out] byte[] buffer, uint buffer_size, [MarshalAs(UnmanagedType.I1)] bool include_deleted);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern int ez_db_get_record_vector(ulong h, uint tag_id, string? tag_name, IntPtr out_struct_array, ref uint p_count, uint struct_size, [MarshalAs(UnmanagedType.I1)] bool strip_str, [MarshalAs(UnmanagedType.I1)] bool include_deleted);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern int ez_db_seek_by_tag(ulong h, string tag_name, string key);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern int ez_db_seek_by_tag_id(ulong h, uint tag_id, string key);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern int ez_db_locate(ulong h, string fieldname, IntPtr target_value, [MarshalAs(UnmanagedType.I1)] bool partial_match);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl)]
        public static extern int ez_db_append(ulong h, [MarshalAs(UnmanagedType.LPUTF8Str)] string data, uint rec_count, [MarshalAs(UnmanagedType.LPUTF8Str)] string delim);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl)]
        public static extern int ez_db_insert(ulong h, [MarshalAs(UnmanagedType.LPUTF8Str)] string data, uint rec_count, [MarshalAs(UnmanagedType.LPUTF8Str)] string delim);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl)]
        public static extern int ez_db_row_replace(ulong h, ulong row_id, [MarshalAs(UnmanagedType.LPUTF8Str)] string data, [MarshalAs(UnmanagedType.LPUTF8Str)] string delim);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern int ez_db_replace(ulong h, ulong row_id, string fieldname, IntPtr val);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl)]
        [return: MarshalAs(UnmanagedType.I1)]
        public static extern bool ez_db_is_deleted(ulong h, ulong row_id);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl)]
        public static extern int ez_db_delete(ulong h, ulong row_id);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl)]
        public static extern int ez_db_recall(ulong h, ulong row_id);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern int ez_db_pack(ulong h, string? path);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl)]
        public static extern int ez_db_zap(ulong h);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl)]
        public static extern int ez_db_commit(ulong h);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl)]
        public static extern int ez_db_get_blob_data(ulong h, ref EZ_BLOB_PTR blob_ptr, [Out] byte[] out_buf, uint out_buf_size);

        // Group D: Index Maintenance
        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern int ez_db_create_index(ulong h, string tag_name, string fields_str, [MarshalAs(UnmanagedType.I1)] bool is_unique);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern int ez_db_mount_index(ulong h, string edx_path, uint slot_id);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl)]
        public static extern int ez_db_purge_duplicates(ulong h, uint tag_id, ulong keep_row_id);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl)]
        public static extern int ez_db_extract_duplicates(ulong h, uint tag_id);

        // Group E: Reflection & Diagnostics
        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern int ez_db_get_field_names(ulong h, [Out] byte[] out_buf, uint buf_size, string delim);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr ez_db_get_fdt(ulong h);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr ez_db_get_tags(ulong h);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl)]
        public static extern ulong ez_db_get_delete_count(ulong h);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl)]
        public static extern void ez_db_dump_record(ulong h, IntPtr record_payload);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl)]
        public static extern void ez_db_dump_workarea(ulong h);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl)]
        public static extern void ez_set_state_observer(EZ_STATE_OBSERVER cb);

        // Error Diagnostic Subsystem Exports
        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr ez_errstr(int status);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr ez_last_error();

        // Relation View Subsystem
        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl)]
        public static extern int ez_rl_mgr_init();

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl)]
        public static extern int ez_rl_mgr_cleanup();

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl)]
        public static extern ulong ez_rl_build_view(ref EZ_RL_VIEW_DESC desc);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl)]
        public static extern int ez_rl_destroy_view(ulong h_rel);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr _ez_get_relation_table(ulong h_rel);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl)]
        public static extern int ez_rl_get_record_vector(IntPtr rel, [Out] byte[] out_buffer, uint request_count, ref uint actual_count);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern int ez_rl_save_view_file(ref EZ_RL_VIEW_DESC desc, string erl_path);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern ulong ez_rl_load_view_file(string erl_path, [In] ulong[] h_ebf_array, ushort ebf_count);

        // Quantization Subsystem
        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl)]
        public static extern int ez_quant_compress_f32_4bit([In] float[] in_vec, uint dim, [Out] byte[] out_packed, ref float out_min, ref float out_max);

        [DllImport(LIB_NAME, CallingConvention = CallingConvention.Cdecl)]
        public static extern int ez_quant_decompress_4bit_f32([In] byte[] in_packed, float min_val, float max_val, uint dim, [Out] float[] out_vec);
    }

    // =========================================================================
    // High-Level Stateless Driver Singleton
    // =========================================================================

    public sealed class EzDBEngine
    {
        private static readonly Lazy<EzDBEngine> _lazy = new Lazy<EzDBEngine>(() => new EzDBEngine());
        public static EzDBEngine Instance => _lazy.Value;

        private EzDBEngine() { }

        // --- Group A: Lifecycle & Schema Maintenance ---
        public int CreateTable(string path, EZ_FIELD_NODE[] fields) => 
            NativeEngine.ez_db_create(path, fields);

        public int Alter(ulong handle, string path, EZ_FIELD_NODE[] newMap, ref EZ_MIGRATE_REPORT report) => 
            NativeEngine.ez_db_alter(handle, path, newMap, ref report);

        public int Reconstruct(ulong handle, string path, ref EZ_MIGRATE_REPORT report) => 
            NativeEngine.ez_db_reconstruct(handle, path, ref report);

        public ulong Use(string path)
        {
            var rep = new EZ_MIGRATE_REPORT();
            ulong h = NativeEngine.ez_db_use(path, ref rep);
            if (h == 0) throw new InvalidOperationException($"Failed to use dataset: {path} | Msg: {rep.GetMessage()}");
            return h;
        }

        public ulong Open(string path) => Use(path);
        public int Close(ulong handle) => NativeEngine.ez_db_close(handle);
        public int CloseAll() => NativeEngine.ez_db_close_all();

        public void SetVacuum(ulong handle, float threshold, uint minDeleted) => 
            NativeEngine.ez_db_set_vacuum(handle, threshold, minDeleted);

        public string GetNameFromPath(string path, uint maxLen = 64)
        {
            byte[] buf = new byte[maxLen];
            NativeEngine.ez_db_get_name_from_path(path, buf, maxLen);
            int idx = Array.IndexOf(buf, (byte)0);
            int len = idx >= 0 ? idx : buf.Length;
            return Encoding.UTF8.GetString(buf, 0, len);
        }

        // --- Group B: Dual-Track Navigation & Status ---
        public int GoTop(ulong handle, uint tagId = 0, string? tagName = null) => 
            NativeEngine.ez_db_gotop(handle, tagId, string.IsNullOrEmpty(tagName) ? null : tagName);

        public int GoBottom(ulong handle, uint tagId = 0, string? tagName = null) => 
            NativeEngine.ez_db_gobottom(handle, tagId, string.IsNullOrEmpty(tagName) ? null : tagName);

        public int Skip(ulong handle, int step = 1, uint tagId = 0, string? tagName = null) => 
            NativeEngine.ez_db_skip(handle, tagId, string.IsNullOrEmpty(tagName) ? null : tagName, step);

        public int GoTo(ulong handle, ulong recno, uint tagId = 0, string? tagName = null) => 
            NativeEngine.ez_db_goto(handle, tagId, string.IsNullOrEmpty(tagName) ? null : tagName, recno);

        public bool IsEof(ulong handle, uint tagId = 0, string? tagName = null) => 
            NativeEngine.ez_db_is_eof(handle, tagId, string.IsNullOrEmpty(tagName) ? null : tagName);

        public bool IsBof(ulong handle, uint tagId = 0, string? tagName = null) => 
            NativeEngine.ez_db_is_bof(handle, tagId, string.IsNullOrEmpty(tagName) ? null : tagName);

        public bool IsFound(ulong handle, uint tagId = 0, string? tagName = null) => 
            NativeEngine.ez_db_is_found(handle, tagId, string.IsNullOrEmpty(tagName) ? null : tagName);

        public long GetRecno(ulong handle, uint tagId = 0, string? tagName = null) => 
            NativeEngine.ez_db_recno(handle, tagId, string.IsNullOrEmpty(tagName) ? null : tagName);

        public long GetLastRec(ulong handle, uint tagId = 0, string? tagName = null) => 
            NativeEngine.ez_db_lastrec(handle, tagId, string.IsNullOrEmpty(tagName) ? null : tagName);

        public uint GetRecordSize(ulong handle) => NativeEngine.ez_db_recsize(handle);
        public ulong GetRecordCount(ulong handle) => NativeEngine.ez_db_record_count(handle);

        // --- Group C: Data Access & Atomic Updates ---
        public int GetRecord(ulong handle, byte[] buffer, uint tagId = 0, string? tagName = null, bool includeDeleted = false)
        {
            if (buffer == null || buffer.Length == 0) return -104; // EZ_ERR_PARAM
            return NativeEngine.ez_db_get_record(handle, tagId, string.IsNullOrEmpty(tagName) ? null : tagName, buffer, (uint)buffer.Length, includeDeleted);
        }

        public byte[]? GetRecord(ulong handle, uint tagId = 0, string? tagName = null, bool includeDeleted = false)
        {
            uint size = GetRecordSize(handle);
            if (size == 0) return null;
            byte[] buf = new byte[size];
            int res = NativeEngine.ez_db_get_record(handle, tagId, string.IsNullOrEmpty(tagName) ? null : tagName, buf, size, includeDeleted);
            return res == 0 ? buf : null;
        }

        public int SeekByTag(ulong handle, string tagName, string key) => 
            NativeEngine.ez_db_seek_by_tag(handle, tagName, key);

        public int SeekByTagId(ulong handle, uint tagId, string key) => 
            NativeEngine.ez_db_seek_by_tag_id(handle, tagId, key);

        public int Locate(ulong handle, string fieldName, IntPtr targetValue, bool partialMatch = false) => 
            NativeEngine.ez_db_locate(handle, fieldName, targetValue, partialMatch);

        public int Append(ulong handle, string csvPayload, uint recCount = 1, string delim = ",") => 
            NativeEngine.ez_db_append(handle, csvPayload, recCount, delim);

        public int Insert(ulong handle, string csvPayload, uint recCount = 1, string delim = ",") => 
            NativeEngine.ez_db_insert(handle, csvPayload, recCount, delim);

        public int RowReplace(ulong handle, ulong rowId, string csvPayload, string delim = ",") => 
            NativeEngine.ez_db_row_replace(handle, rowId, csvPayload, delim);

        public int Replace(ulong handle, ulong rowId, string fieldName, IntPtr val) => 
            NativeEngine.ez_db_replace(handle, rowId, fieldName, val);

        public bool IsDeleted(ulong handle, ulong rowId) => 
            NativeEngine.ez_db_is_deleted(handle, rowId);

        public int Delete(ulong handle, ulong rowId) => 
            NativeEngine.ez_db_delete(handle, rowId);

        public int Recall(ulong handle, ulong rowId) => 
            NativeEngine.ez_db_recall(handle, rowId);

        public int Pack(ulong handle, string? tempPath = null) => 
            NativeEngine.ez_db_pack(handle, string.IsNullOrEmpty(tempPath) ? null : tempPath);

        public int Zap(ulong handle) => 
            NativeEngine.ez_db_zap(handle);

        public int Commit(ulong handle) => 
            NativeEngine.ez_db_commit(handle);

        public int GetBlobData(ulong handle, ref EZ_BLOB_PTR blobPtr, byte[] outBuf)
        {
            if (outBuf == null || outBuf.Length == 0) return -104; // EZ_ERR_PARAM
            return NativeEngine.ez_db_get_blob_data(handle, ref blobPtr, outBuf, (uint)outBuf.Length);
        }

        // --- Group D: Index Maintenance ---
        public int CreateIndex(ulong handle, string tagName, string fieldExpr, bool isUnique = false) => 
            NativeEngine.ez_db_create_index(handle, tagName, fieldExpr, isUnique);

        public int MountIndex(ulong handle, string edxPath, uint slotId) => 
            NativeEngine.ez_db_mount_index(handle, edxPath, slotId);

        public int PurgeDuplicates(ulong handle, uint tagId, ulong keepRowId = 0) => 
            NativeEngine.ez_db_purge_duplicates(handle, tagId, keepRowId);

        public int ExtractDuplicates(ulong handle, uint tagId) => 
            NativeEngine.ez_db_extract_duplicates(handle, tagId);

        // --- Group E: Reflection & Diagnostics ---
        public string GetFieldNames(ulong handle, string delim = ",", uint bufSize = 1024)
        {
            byte[] buf = new byte[bufSize];
            if (NativeEngine.ez_db_get_field_names(handle, buf, bufSize, delim) != 0) return string.Empty;
            int idx = Array.IndexOf(buf, (byte)0);
            int len = idx >= 0 ? idx : buf.Length;
            return Encoding.UTF8.GetString(buf, 0, len);
        }

        public List<EZ_FIELD_NODE> GetFdt(ulong handle)
        {
            var list = new List<EZ_FIELD_NODE>();
            IntPtr pFdt = NativeEngine.ez_db_get_fdt(handle);
            if (pFdt == IntPtr.Zero) return list;

            int structSize = Marshal.SizeOf<EZ_FIELD_NODE>();
            int i = 0;
            while (true)
            {
                IntPtr nodePtr = IntPtr.Add(pFdt, i * structSize);
                var node = Marshal.PtrToStructure<EZ_FIELD_NODE>(nodePtr);
                if (node.type == 0) break; // Strict parity check against original definition
                list.Add(node);
                i++;
            }
            return list;
        }

        public List<EZ_TAG_INFO> GetTags(ulong handle)
        {
            var list = new List<EZ_TAG_INFO>();
            IntPtr pTags = NativeEngine.ez_db_get_tags(handle);
            if (pTags == IntPtr.Zero) return list;

            int structSize = Marshal.SizeOf<EZ_TAG_INFO>();
            for (int i = 0; i < 8; i++)
            {
                IntPtr tagPtr = IntPtr.Add(pTags, i * structSize);
                var tag = Marshal.PtrToStructure<EZ_TAG_INFO>(tagPtr);
                if (tag.tag_name[0] == 0) break;
                list.Add(tag);
            }
            return list;
        }

        public ulong GetDeleteCount(ulong handle) => NativeEngine.ez_db_get_delete_count(handle);
        public void DumpRecord(ulong handle, IntPtr recordPayload) => NativeEngine.ez_db_dump_record(handle, recordPayload);
        public void DumpWorkarea(ulong handle) => NativeEngine.ez_db_dump_workarea(handle);
        public void SetStateObserver(EZ_STATE_OBSERVER cb) => NativeEngine.ez_set_state_observer(cb);

        // --- Error Diagnostic Subsystem ---
        public string ErrStr(int status)
        {
            IntPtr ptr = NativeEngine.ez_errstr(status);
            return ptr == IntPtr.Zero ? "Unknown engine error" : Marshal.PtrToStringUTF8(ptr) ?? "Unknown engine error";
        }

        public string LastError()
        {
            IntPtr ptr = NativeEngine.ez_last_error();
            return ptr == IntPtr.Zero ? string.Empty : Marshal.PtrToStringUTF8(ptr) ?? string.Empty;
        }

        public string GetDetailedError(int status)
        {
            string dynErr = LastError();
            string staticErr = ErrStr(status);
            if (!string.IsNullOrEmpty(dynErr))
            {
                return $"[{staticErr}] {dynErr} (Code: {status})";
            }
            return $"[{staticErr}] (Code: {status})";
        }

        // --- Relation View Subsystem ---
        public int RelationMgrInit() => NativeEngine.ez_rl_mgr_init();
        public int RelationMgrCleanup() => NativeEngine.ez_rl_mgr_cleanup();

        public ulong RelationBuildView(ref EZ_RL_VIEW_DESC desc) => 
            NativeEngine.ez_rl_build_view(ref desc);

        public int RelationDestroyView(ulong hRel) => 
            NativeEngine.ez_rl_destroy_view(hRel);

        public IntPtr RelationGetTable(ulong hRel) => 
            NativeEngine._ez_get_relation_table(hRel);

        public byte[]? RelationGetRecordVector(IntPtr relTable, uint requestCount, out uint actualCount)
        {
            actualCount = 0;
            if (relTable == IntPtr.Zero) return null;
            byte[] buf = new byte[requestCount * 1024];
            int res = NativeEngine.ez_rl_get_record_vector(relTable, buf, requestCount, ref actualCount);
            return res == 0 ? buf : null;
        }

        public int RelationSaveViewFile(ref EZ_RL_VIEW_DESC desc, string erlPath) => 
            NativeEngine.ez_rl_save_view_file(ref desc, erlPath);

        public ulong RelationLoadViewFile(string erlPath, ulong[] ebfHandles) => 
            NativeEngine.ez_rl_load_view_file(erlPath, ebfHandles, (ushort)ebfHandles.Length);

        // --- Quantization Subsystem ---
        public int QuantCompressF32(float[] inVec, uint dim, byte[] outPacked, ref float outMin, ref float outMax) => 
            NativeEngine.ez_quant_compress_f32_4bit(inVec, dim, outPacked, ref outMin, ref outMax);

        public int QuantDecompressF32(byte[] inPacked, float minVal, float maxVal, uint dim, float[] outVec) => 
            NativeEngine.ez_quant_decompress_4bit_f32(inPacked, minVal, maxVal, dim, outVec);
    }
}