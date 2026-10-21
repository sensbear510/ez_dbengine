"""
ez_dbengine.py - EDB 2.0 Python High-Concurrency FFI Stateless Singleton Driver
"""

import ctypes
import os
import platform
from typing import List, Dict, Optional, Tuple, Any

# --- [1. 動態函式庫自動載入與跨平台路徑解析] ---
_current_dir = os.path.dirname(os.path.abspath(__file__))
_root_dir = os.path.abspath(os.path.join(_current_dir, "..", ".."))
_system = platform.system()

if _system == "Windows":
    _lib_name = "ez_dbengine.dll"
elif _system == "Darwin":
    _lib_name = "libez_dbengine.dylib"
else:
    _lib_name = "libez_dbengine.so"

_candidate_paths = [
    os.path.join(_current_dir, _lib_name),
    os.path.join(_current_dir, "run_win", _lib_name),
    os.path.join(_root_dir, "build_linux", "lib", _lib_name),
    os.path.join(_root_dir, "build_linux", _lib_name),
    os.path.join(_root_dir, "build_win", "bin", "Release", _lib_name),
    os.path.join(_root_dir, "build_win", "bin", _lib_name),
    os.path.join(_root_dir, "build_win", _lib_name),
]

_lib = None
for _p in _candidate_paths:
    if os.path.exists(_p):
        try:
            _lib = ctypes.CDLL(_p)
            break
        except Exception:
            pass

if _lib is None:
    try:
        _lib = ctypes.CDLL(_lib_name)
    except Exception as e:
        raise RuntimeError(f"無法載入核心動態庫 [{_lib_name}]，請確認已執行專案建置。錯誤: {e}")


# =========================================================================
# 2. 嚴格對齊 C 結構體 (ez_def.h / ez_relation_mgr.h 1-Byte Alignment)
# =========================================================================

# 52 + 1 + 4 + 1 + 1 + 4 + 1 = 64 Bytes，精確對齊 C 核心 EZ_FIELD_NODE
class EZ_FIELD_NODE(ctypes.Structure):
    _pack_ = 1
    _fields_ = [
        ("name", ctypes.c_char * 52),
        ("type", ctypes.c_uint8),
        ("len", ctypes.c_uint32),
        ("dec", ctypes.c_uint8),
        ("storage", ctypes.c_uint8),
        ("offset", ctypes.c_uint32),
        ("zbf_sequence", ctypes.c_uint8),
    ]

    @classmethod
    def create(cls, name: str, f_type: str, length: int, dec: int = 0, offset: int = 0):
        node = cls()
        name_bytes = name.encode("utf-8")[:51]
        node.name = name_bytes
        node.type = ord(f_type)
        node.len = length
        node.dec = dec
        node.storage = 0
        node.offset = offset
        node.zbf_sequence = 0
        return node

    def get_name(self) -> str:
        return self.name.decode("utf-8", errors="ignore").split('\x00', 1)[0]


class EZ_TAG_INFO(ctypes.Structure):
    _pack_ = 1
    _fields_ = [
        ("tag_name", ctypes.c_char * 64),
        ("key_len", ctypes.c_uint32),
        ("key_type", ctypes.c_uint32),
        ("root_ptr", ctypes.c_uint64),
        ("node_count", ctypes.c_uint64),
        ("is_descending", ctypes.c_uint32),
        ("h_slot", ctypes.c_uint32),
        ("field_offsets", ctypes.c_uint32 * 8),
        ("field_lens", ctypes.c_uint32 * 8),
        ("field_count", ctypes.c_uint8),
        ("is_unique", ctypes.c_uint8),
        ("_final_pad", ctypes.c_uint8 * 94),
    ]


class EZ_MIGRATE_REPORT(ctypes.Structure):
    _pack_ = 1
    _fields_ = [
        ("status", ctypes.c_uint32),
        ("error_code", ctypes.c_uint32),
        ("total_recs", ctypes.c_uint64),
        ("recovered_recs", ctypes.c_uint64),
        ("message", ctypes.c_char * 128),
    ]

    def get_message(self) -> str:
        return self.message.decode("utf-8", errors="ignore").split('\x00', 1)[0]


class EZ_BLOB_PTR(ctypes.Structure):
    _pack_ = 1
    _fields_ = [
        ("blob_offset", ctypes.c_uint64),
        ("logical_length", ctypes.c_uint32),
        ("physical_length", ctypes.c_uint32),
        ("file_sequence", ctypes.c_uint32),
        ("flags", ctypes.c_uint32),
    ]


class EZ_RL_NODE_DESC(ctypes.Structure):
    _fields_ = [
        ("ebf_index", ctypes.c_uint16),
        ("field_name", ctypes.c_char * 52),
        ("alias_name", ctypes.c_char * 52),
    ]


class EZ_RL_LINK_DESC(ctypes.Structure):
    _fields_ = [
        ("parent_ebf_index", ctypes.c_uint16),
        ("child_ebf_index", ctypes.c_uint16),
        ("fk_field_count", ctypes.c_uint8),
        ("parent_fk_offsets", ctypes.c_uint16 * 8),
        ("parent_fk_lens", ctypes.c_uint16 * 8),
        ("child_tag_name", ctypes.c_char * 48),
    ]


class EZ_RL_VIEW_DESC(ctypes.Structure):
    _fields_ = [
        ("relation_name", ctypes.c_char_p),
        ("join_mode", ctypes.c_uint32),
        ("h_ebf_array", ctypes.POINTER(ctypes.c_uint64)),
        ("ebf_count", ctypes.c_uint16),
        ("nodes", ctypes.POINTER(EZ_RL_NODE_DESC)),
        ("node_count", ctypes.c_uint16),
        ("links", ctypes.POINTER(EZ_RL_LINK_DESC)),
        ("link_count", ctypes.c_uint16),
    ]


# =========================================================================
# 3. 原生 C 符號繫結
# =========================================================================

# Group A: 生命週期與結構維護
_lib.ez_db_create.argtypes = [ctypes.c_char_p, ctypes.POINTER(EZ_FIELD_NODE)]
_lib.ez_db_create.restype = ctypes.c_int32

_lib.ez_db_alter.argtypes = [ctypes.c_uint64, ctypes.c_char_p, ctypes.POINTER(EZ_FIELD_NODE), ctypes.POINTER(EZ_MIGRATE_REPORT)]
_lib.ez_db_alter.restype = ctypes.c_int32

_lib.ez_db_reconstruct.argtypes = [ctypes.c_uint64, ctypes.c_char_p, ctypes.POINTER(EZ_MIGRATE_REPORT)]
_lib.ez_db_reconstruct.restype = ctypes.c_int32

_lib.ez_db_use.argtypes = [ctypes.c_char_p, ctypes.POINTER(EZ_MIGRATE_REPORT)]
_lib.ez_db_use.restype = ctypes.c_uint64

_lib.ez_db_open.argtypes = [ctypes.c_char_p, ctypes.POINTER(EZ_MIGRATE_REPORT)]
_lib.ez_db_open.restype = ctypes.c_uint64

_lib.ez_db_close.argtypes = [ctypes.c_uint64]
_lib.ez_db_close.restype = ctypes.c_int32

_lib.ez_db_close_all.argtypes = []
_lib.ez_db_close_all.restype = ctypes.c_int32

_lib.ez_db_set_vacuum.argtypes = [ctypes.c_uint64, ctypes.c_float, ctypes.c_uint32]
_lib.ez_db_set_vacuum.restype = None

_lib.ez_db_get_name_from_path.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint32]
_lib.ez_db_get_name_from_path.restype = None

# Group B: 雙軌導航與狀態
_lib.ez_db_gotop.argtypes = [ctypes.c_uint64, ctypes.c_uint32, ctypes.c_char_p]
_lib.ez_db_gotop.restype = ctypes.c_int32

_lib.ez_db_gobottom.argtypes = [ctypes.c_uint64, ctypes.c_uint32, ctypes.c_char_p]
_lib.ez_db_gobottom.restype = ctypes.c_int32

_lib.ez_db_skip.argtypes = [ctypes.c_uint64, ctypes.c_uint32, ctypes.c_char_p, ctypes.c_int32]
_lib.ez_db_skip.restype = ctypes.c_int32

_lib.ez_db_goto.argtypes = [ctypes.c_uint64, ctypes.c_uint32, ctypes.c_char_p, ctypes.c_uint64]
_lib.ez_db_goto.restype = ctypes.c_int32

_lib.ez_db_is_eof.argtypes = [ctypes.c_uint64, ctypes.c_uint32, ctypes.c_char_p]
_lib.ez_db_is_eof.restype = ctypes.c_bool

_lib.ez_db_is_bof.argtypes = [ctypes.c_uint64, ctypes.c_uint32, ctypes.c_char_p]
_lib.ez_db_is_bof.restype = ctypes.c_bool

_lib.ez_db_is_found.argtypes = [ctypes.c_uint64, ctypes.c_uint32, ctypes.c_char_p]
_lib.ez_db_is_found.restype = ctypes.c_bool

_lib.ez_db_recno.argtypes = [ctypes.c_uint64, ctypes.c_uint32, ctypes.c_char_p]
_lib.ez_db_recno.restype = ctypes.c_int64

_lib.ez_db_lastrec.argtypes = [ctypes.c_uint64, ctypes.c_uint32, ctypes.c_char_p]
_lib.ez_db_lastrec.restype = ctypes.c_int64

_lib.ez_db_recsize.argtypes = [ctypes.c_uint64]
_lib.ez_db_recsize.restype = ctypes.c_uint32

_lib.ez_db_record_count.argtypes = [ctypes.c_uint64]
_lib.ez_db_record_count.restype = ctypes.c_uint64

# Group C: 資料存取與原子更新
_lib.ez_db_get_record.argtypes = [ctypes.c_uint64, ctypes.c_uint32, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint32, ctypes.c_bool]
_lib.ez_db_get_record.restype = ctypes.c_int32

_lib.ez_db_seek_by_tag.argtypes = [ctypes.c_uint64, ctypes.c_char_p]
_lib.ez_db_seek_by_tag.restype = ctypes.c_int32

_lib.ez_db_seek_by_tag_array.argtypes = [ctypes.c_uint64, ctypes.c_char_p, ctypes.POINTER(ctypes.c_char_p)]
_lib.ez_db_seek_by_tag_array.restype = ctypes.c_int32

_lib.ez_db_seek_by_tag_id_array.argtypes = [ctypes.c_uint64, ctypes.c_uint32, ctypes.POINTER(ctypes.c_char_p)]
_lib.ez_db_seek_by_tag_id_array.restype = ctypes.c_int32

_lib.ez_db_locate.argtypes = [ctypes.c_uint64, ctypes.c_char_p, ctypes.c_void_p, ctypes.c_bool]
_lib.ez_db_locate.restype = ctypes.c_int32

_lib.ez_db_append.argtypes = [ctypes.c_uint64, ctypes.c_char_p, ctypes.c_uint32, ctypes.c_char_p]
_lib.ez_db_append.restype = ctypes.c_int32

_lib.ez_db_insert.argtypes = [ctypes.c_uint64, ctypes.c_char_p, ctypes.c_uint32, ctypes.c_char_p]
_lib.ez_db_insert.restype = ctypes.c_int32

_lib.ez_db_row_replace.argtypes = [ctypes.c_uint64, ctypes.c_uint64, ctypes.c_char_p, ctypes.c_char_p]
_lib.ez_db_row_replace.restype = ctypes.c_int32

_lib.ez_db_replace.argtypes = [ctypes.c_uint64, ctypes.c_uint64, ctypes.c_char_p, ctypes.c_void_p]
_lib.ez_db_replace.restype = ctypes.c_int32

_lib.ez_db_is_deleted.argtypes = [ctypes.c_uint64, ctypes.c_uint64]
_lib.ez_db_is_deleted.restype = ctypes.c_bool

_lib.ez_db_delete.argtypes = [ctypes.c_uint64, ctypes.c_uint64]
_lib.ez_db_delete.restype = ctypes.c_int32

_lib.ez_db_recall.argtypes = [ctypes.c_uint64, ctypes.c_uint64]
_lib.ez_db_recall.restype = ctypes.c_int32

_lib.ez_db_pack.argtypes = [ctypes.c_uint64, ctypes.c_char_p]
_lib.ez_db_pack.restype = ctypes.c_int32

_lib.ez_db_zap.argtypes = [ctypes.c_uint64]
_lib.ez_db_zap.restype = ctypes.c_int32

_lib.ez_db_commit.argtypes = [ctypes.c_uint64]
_lib.ez_db_commit.restype = ctypes.c_int32

_lib.ez_db_get_blob_data.argtypes = [ctypes.c_uint64, ctypes.POINTER(EZ_BLOB_PTR), ctypes.c_char_p, ctypes.c_uint32]
_lib.ez_db_get_blob_data.restype = ctypes.c_int32

# Group D: 索引維護
_lib.ez_db_create_index.argtypes = [ctypes.c_uint64, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_bool]
_lib.ez_db_create_index.restype = ctypes.c_int32

_lib.ez_db_mount_index.argtypes = [ctypes.c_uint64, ctypes.c_char_p, ctypes.c_uint32]
_lib.ez_db_mount_index.restype = ctypes.c_int32

_lib.ez_db_purge_duplicates.argtypes = [ctypes.c_uint64, ctypes.c_uint32, ctypes.c_uint64]
_lib.ez_db_purge_duplicates.restype = ctypes.c_int32

_lib.ez_db_extract_duplicates.argtypes = [ctypes.c_uint64, ctypes.c_uint32]
_lib.ez_db_extract_duplicates.restype = ctypes.c_int32

# Group E: 反射與偵錯工具
_lib.ez_db_get_field_names.argtypes = [ctypes.c_uint64, ctypes.c_char_p, ctypes.c_uint32, ctypes.c_char_p]
_lib.ez_db_get_field_names.restype = ctypes.c_int32

# Dynamically resolve index key expression
_lib.ez_db_get_index_key.argtypes = [ctypes.c_uint64, ctypes.c_uint32, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint32]
_lib.ez_db_get_index_key.restype = ctypes.c_int32

_lib.ez_db_get_fdt.argtypes = [ctypes.c_uint64]
_lib.ez_db_get_fdt.restype = ctypes.POINTER(EZ_FIELD_NODE)

_lib.ez_db_get_tags.argtypes = [ctypes.c_uint64]
_lib.ez_db_get_tags.restype = ctypes.POINTER(EZ_TAG_INFO)

_lib.ez_db_get_delete_count.argtypes = [ctypes.c_uint64]
_lib.ez_db_get_delete_count.restype = ctypes.c_uint64

_lib.ez_db_dump_record.argtypes = [ctypes.c_uint64, ctypes.c_void_p]
_lib.ez_db_dump_record.restype = None

_lib.ez_db_dump_workarea.argtypes = [ctypes.c_uint64]
_lib.ez_db_dump_workarea.restype = None

# 錯誤診斷子系統導出 (ez_engine.h)
_lib.ez_errstr.argtypes = [ctypes.c_int32]
_lib.ez_errstr.restype = ctypes.c_char_p

_lib.ez_last_error.argtypes = []
_lib.ez_last_error.restype = ctypes.c_char_p

# 關聯檢視子系統 (ez_relation_mgr.h)
_lib.ez_rl_mgr_init.argtypes = []
_lib.ez_rl_mgr_init.restype = ctypes.c_int32

_lib.ez_rl_mgr_cleanup.argtypes = []
_lib.ez_rl_mgr_cleanup.restype = ctypes.c_int32

_lib.ez_rl_build_view.argtypes = [ctypes.POINTER(EZ_RL_VIEW_DESC)]
_lib.ez_rl_build_view.restype = ctypes.c_uint64

_lib.ez_rl_destroy_view.argtypes = [ctypes.c_uint64]
_lib.ez_rl_destroy_view.restype = ctypes.c_int32

_lib.ez_rl_save_view_file.argtypes = [ctypes.POINTER(EZ_RL_VIEW_DESC), ctypes.c_char_p]
_lib.ez_rl_save_view_file.restype = ctypes.c_int32

# 量化子系統 (ez_quant.h)
_lib.ez_quant_compress_f32_4bit.argtypes = [
    ctypes.POINTER(ctypes.c_float), ctypes.c_uint32,
    ctypes.c_char_p, ctypes.POINTER(ctypes.c_float), ctypes.POINTER(ctypes.c_float)
]
_lib.ez_quant_compress_f32_4bit.restype = ctypes.c_int32

_lib.ez_quant_decompress_4bit_f32.argtypes = [
    ctypes.c_char_p, ctypes.c_float, ctypes.c_float,
    ctypes.c_uint32, ctypes.POINTER(ctypes.c_float)
]
_lib.ez_quant_decompress_4bit_f32.restype = ctypes.c_int32


# =========================================================================
# 4. 高階無狀態驅動單例 (EzDBEngine Stateless Singleton)
# =========================================================================

class EzDBEngine:
    _instance: Optional['EzDBEngine'] = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(EzDBEngine, cls).__new__(cls)
        return cls._instance

    @classmethod
    def get_instance(cls) -> 'EzDBEngine':
        return cls()

    # --- 錯誤診斷子系統 ---
    @staticmethod
    def err_str(status: int) -> str:
        ptr = _lib.ez_errstr(status)
        return ptr.decode("utf-8", errors="ignore") if ptr else "Unknown engine error"

    @staticmethod
    def last_error() -> str:
        ptr = _lib.ez_last_error()
        return ptr.decode("utf-8", errors="ignore") if ptr else ""

    @classmethod
    def get_detailed_error(cls, status: int) -> str:
        dyn = cls.last_error()
        desc = cls.err_str(status)
        if dyn:
            return f"[{desc}] {dyn} (Code: {status})"
        return f"[{desc}] (Code: {status})"

    # --- Group A: 生命週期與結構維護 ---
    def create_table(self, path: str, fields: List[EZ_FIELD_NODE]) -> int:
        arr_type = EZ_FIELD_NODE * (len(fields) + 1)
        arr = arr_type()
        curr_offset = 0

        for i, f in enumerate(fields):
            arr[i].name = f.name
            arr[i].type = f.type
            arr[i].len = f.len
            arr[i].dec = f.dec
            arr[i].storage = f.storage
            arr[i].offset = curr_offset
            arr[i].zbf_sequence = f.zbf_sequence
            curr_offset += f.len

        # 結尾標記 Node (type = 0)
        arr[len(fields)].type = 0
        arr[len(fields)].offset = curr_offset

        return _lib.ez_db_create(path.encode("utf-8"), arr)

    def use(self, path: str) -> int:
        rep = EZ_MIGRATE_REPORT()
        h = _lib.ez_db_use(path.encode("utf-8"), ctypes.byref(rep))
        if h == 0:
            dyn = self.last_error()
            raise RuntimeError(f"ez_db_use failed: {path} | Msg: {rep.get_message()} {dyn}")
        return h

    def open(self, path: str) -> int:
        return self.use(path)

    def close(self, handle: int) -> int:
        if not handle:
            return -106
        return _lib.ez_db_close(handle)

    def close_all(self) -> int:
        return _lib.ez_db_close_all()

    def set_vacuum(self, handle: int, threshold: float, min_deleted: int) -> None:
        _lib.ez_db_set_vacuum(handle, threshold, min_deleted)

    def get_name_from_path(self, path: str, max_len: int = 64) -> str:
        buf = ctypes.create_string_buffer(max_len)
        _lib.ez_db_get_name_from_path(path.encode("utf-8"), buf, max_len)
        return buf.value.decode("utf-8", errors="ignore")

    # --- Group B: 雙軌導航與狀態 ---
    def go_top(self, handle: int, tag_id: int = 0, tag_name: Optional[str] = None) -> int:
        tn = tag_name.encode("utf-8") if tag_name else None
        return _lib.ez_db_gotop(handle, tag_id, tn)

    def go_bottom(self, handle: int, tag_id: int = 0, tag_name: Optional[str] = None) -> int:
        tn = tag_name.encode("utf-8") if tag_name else None
        return _lib.ez_db_gobottom(handle, tag_id, tn)

    def skip(self, handle: int, step: int = 1, tag_id: int = 0, tag_name: Optional[str] = None) -> int:
        tn = tag_name.encode("utf-8") if tag_name else None
        return _lib.ez_db_skip(handle, tag_id, tn, step)

    def go_to(self, handle: int, recno: int, tag_id: int = 0, tag_name: Optional[str] = None) -> int:
        tn = tag_name.encode("utf-8") if tag_name else None
        return _lib.ez_db_goto(handle, tag_id, tn, recno)

    def is_eof(self, handle: int, tag_id: int = 0, tag_name: Optional[str] = None) -> bool:
        tn = tag_name.encode("utf-8") if tag_name else None
        return _lib.ez_db_is_eof(handle, tag_id, tn)

    def is_bof(self, handle: int, tag_id: int = 0, tag_name: Optional[str] = None) -> bool:
        tn = tag_name.encode("utf-8") if tag_name else None
        return _lib.ez_db_is_bof(handle, tag_id, tn)

    def is_found(self, handle: int, tag_id: int = 0, tag_name: Optional[str] = None) -> bool:
        tn = tag_name.encode("utf-8") if tag_name else None
        return _lib.ez_db_is_found(handle, tag_id, tn)

    def get_recno(self, handle: int, tag_id: int = 0, tag_name: Optional[str] = None) -> int:
        tn = tag_name.encode("utf-8") if tag_name else None
        return _lib.ez_db_recno(handle, tag_id, tn)

    def get_lastrec(self, handle: int, tag_id: int = 0, tag_name: Optional[str] = None) -> int:
        tn = tag_name.encode("utf-8") if tag_name else None
        return _lib.ez_db_lastrec(handle, tag_id, tn)

    def get_record_size(self, handle: int) -> int:
        return _lib.ez_db_recsize(handle)

    def get_record_count(self, handle: int) -> int:
        return _lib.ez_db_record_count(handle)

    # --- Group C: 資料存取與原子更新 ---
    def get_record(self, handle: int, tag_id: int = 0, tag_name: Optional[str] = None, include_deleted: bool = False) -> Optional[bytes]:
        rec_size = self.get_record_size(handle)
        if rec_size <= 0:
            return None
        buf = ctypes.create_string_buffer(rec_size)
        tn = tag_name.encode("utf-8") if tag_name else None
        res = _lib.ez_db_get_record(handle, tag_id, tn, buf, rec_size, include_deleted)
        return buf.raw if res == 0 else None

    def seek_by_tag(self, handle: int, tag_name: str, key_values: List[str]) -> bool:
        # 分配 len + 1，補上 NULL 作為結尾 Sentinel 標記
        c_keys = (ctypes.c_char_p * (len(key_values) + 1))()
        for i, k in enumerate(key_values):
            c_keys[i] = k.encode("utf-8")
        c_keys[len(key_values)] = None
        return _lib.ez_db_seek_by_tag_array(handle, tag_name.encode("utf-8"), c_keys) == 0

    def seek_by_tag_id(self, handle: int, tag_id: int, key_values: List[str]) -> bool:
        c_keys = (ctypes.c_char_p * (len(key_values) + 1))()
        for i, k in enumerate(key_values):
            c_keys[i] = k.encode("utf-8")
        c_keys[len(key_values)] = None
        return _lib.ez_db_seek_by_tag_id_array(handle, tag_id, c_keys) == 0

    def append(self, handle: int, data: str, rec_count: int = 1, delimiter: str = ",") -> int:
        return _lib.ez_db_append(handle, data.encode("utf-8"), rec_count, delimiter.encode("utf-8"))

    def insert(self, handle: int, data: str, rec_count: int = 1, delimiter: str = ",") -> int:
        return _lib.ez_db_insert(handle, data.encode("utf-8"), rec_count, delimiter.encode("utf-8"))

    def row_replace(self, handle: int, row_id: int, data: str, delimiter: str = ",") -> int:
        return _lib.ez_db_row_replace(handle, row_id, data.encode("utf-8"), delimiter.encode("utf-8"))

    def replace(self, handle: int, row_id: int, field_name: str, val: bytes) -> int:
        return _lib.ez_db_replace(handle, row_id, field_name.encode("utf-8"), ctypes.cast(val, ctypes.c_void_p))

    def is_deleted(self, handle: int, row_id: int) -> bool:
        return _lib.ez_db_is_deleted(handle, row_id)

    def delete(self, handle: int, row_id: int) -> int:
        return _lib.ez_db_delete(handle, row_id)

    def recall(self, handle: int, row_id: int) -> int:
        return _lib.ez_db_recall(handle, row_id)

    def pack(self, handle: int, temp_path: str = "") -> int:
        tp = temp_path.encode("utf-8") if temp_path else None
        return _lib.ez_db_pack(handle, tp)

    def zap(self, handle: int) -> int:
        return _lib.ez_db_zap(handle)

    def commit(self, handle: int) -> int:
        return _lib.ez_db_commit(handle)

    # --- Group D: 索引維護 ---
    def create_index(self, handle: int, tag_name: str, fields_expr: str, is_unique: bool = True) -> int:
        return _lib.ez_db_create_index(handle, tag_name.encode("utf-8"), fields_expr.encode("utf-8"), is_unique)

    def mount_index(self, handle: int, edx_path: str, slot_id: int) -> int:
        return _lib.ez_db_mount_index(handle, edx_path.encode("utf-8"), slot_id)

    def purge_duplicates(self, handle: int, tag_id: int, keep_row_id: int = 0) -> int:
        return _lib.ez_db_purge_duplicates(handle, tag_id, keep_row_id)

    def extract_duplicates(self, handle: int, tag_id: int) -> int:
        return _lib.ez_db_extract_duplicates(handle, tag_id)

    # --- Group E: 反射與偵錯工具 ---
    def get_field_names(self, handle: int, delimiter: str = ",", buf_size: int = 1024) -> str:
        buf = ctypes.create_string_buffer(buf_size)
        if _lib.ez_db_get_field_names(handle, buf, buf_size, delimiter.encode("utf-8")) != 0:
            return ""
        return buf.value.decode("utf-8", errors="ignore")
    
    def get_index_key(self, handle: int, tag_id: int = 0, tag_name: Optional[str] = None, buf_size: int = 128) -> str:
        """
        Dynamically resolves the active index expression (e.g., "code" or "date+code") for the specified tag.
        Supports resolution via tag_id (1~8) and/or tag_name.
        """
        if not handle or buf_size <= 0:
            return ""

        buf = ctypes.create_string_buffer(buf_size)
        tn = tag_name.encode("utf-8") if (tag_name and len(tag_name) > 0) else None

        status = _lib.ez_db_get_index_key(handle, tag_id, tn, buf, buf_size)
        if status == 0:  # EZ_SUCCESS
            return buf.value.decode("utf-8", errors="ignore").strip()
        return ""
    
    def get_tags(self, handle: int) -> List[Dict[str, Any]]:
        """
        Retrieves all mounted index tags, delegating expression resolution directly to C-Core.
        """
        pTags = _lib.ez_db_get_tags(handle)
        if not pTags:
            return []

        tags = []
        for i in range(8):
            tag_node = pTags[i]
            if not tag_node.tag_name or tag_node.tag_name[0] == b'\x00':
                break

            str_tag_name = tag_node.tag_name.decode("utf-8", errors="ignore").split('\x00', 1)[0].strip()
            if not str_tag_name:
                continue

            slot_num = i + 1
            # Delegate directly to C-Core ez_db_get_index_key for dynamic resolution
            resolved_expr = self.get_index_key(handle, slot_num, str_tag_name)
            if not resolved_expr:
                resolved_expr = str_tag_name

            tags.append({
                "slot": slot_num,
                "name": str_tag_name,
                "expression": resolved_expr,
                "is_unique": bool(tag_node.is_unique == 1),
                "node_count": int(tag_node.node_count)
            })
        return tags

    def get_fdt(self, handle: int) -> List[Dict[str, Any]]:
        pFdt = _lib.ez_db_get_fdt(handle)
        if not pFdt:
            return []
        fields = []
        i = 0
        while True:
            node = pFdt[i]
            if node.type == 0:
                break
            fields.append({
                "name": node.get_name(),
                "type": chr(node.type),
                "len": node.len,
                "dec": node.dec,
                "offset": node.offset
            })
            i += 1
        return fields

    def dump_workarea(self, handle: int) -> None:
        _lib.ez_db_dump_workarea(handle)

    # --- 關聯檢視子系統 (Relation View) ---
    def relation_mgr_init(self) -> int:
        return _lib.ez_rl_mgr_init()

    def relation_mgr_cleanup(self) -> int:
        return _lib.ez_rl_mgr_cleanup()

    def relation_build_view(self, desc: EZ_RL_VIEW_DESC) -> int:
        return _lib.ez_rl_build_view(ctypes.byref(desc))

    def relation_destroy_view(self, h_rel: int) -> int:
        return _lib.ez_rl_destroy_view(h_rel)

    def relation_save_view_file(self, desc: EZ_RL_VIEW_DESC, erl_path: str) -> int:
        return _lib.ez_rl_save_view_file(ctypes.byref(desc), erl_path.encode("utf-8"))

    # --- 量化子系統 (Quantization) ---
    def quant_compress_f32(self, vec: List[float], dim: int) -> Tuple[bool, bytes, float, float]:
        c_vec = (ctypes.c_float * dim)(*vec)
        packed_buf = ctypes.create_string_buffer(dim // 2)
        out_min = ctypes.c_float()
        out_max = ctypes.c_float()
        status = _lib.ez_quant_compress_f32_4bit(c_vec, dim, packed_buf, ctypes.byref(out_min), ctypes.byref(out_max))
        return (status == 0, packed_buf.raw, out_min.value, out_max.value)

    def quant_decompress_f32(self, packed_bytes: bytes, min_val: float, max_val: float, dim: int) -> Tuple[bool, List[float]]:
        out_vec = (ctypes.c_float * dim)()
        status = _lib.ez_quant_decompress_4bit_f32(packed_bytes, min_val, max_val, dim, out_vec)
        return (status == 0, list(out_vec))