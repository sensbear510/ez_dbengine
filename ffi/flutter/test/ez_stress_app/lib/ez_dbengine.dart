// ignore_for_all: unused_field
// ignore_for_file: unused_field, non_constant_identifier_names, unintended_html_in_doc_comment

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

// =====================================================================
// 🚀 [1. High-Level Schema Builder & Reflector (Pure Dart)]
// =====================================================================

class EzTag {
  final String name;
  final String expression;
  final bool isUnique;
  final int fieldCount;

  const EzTag({
    required this.name,
    required this.expression,
    required this.isUnique,
    this.fieldCount = 1,
  });
}

class EzField {
  final String name;
  final String type;
  final int len;
  final int dec;
  final int offset;
  final int storage;
  final int zbfSequence;

  const EzField(
    this.name,
    this.type,
    this.len, [
    this.dec = 0,
    this.offset = 0,
    this.storage = 0,
    this.zbfSequence = 0,
  ]);

  /// Factory constructor converting Native EzFieldMap struct directly into EzField
  factory EzField.fromNative(EzFieldMap map) {
    final List<int> nameBytes = <int>[];
    for (int j = 0; j < 52; j++) {
      if (map.name[j] == 0) break;
      nameBytes.add(map.name[j]);
    }
    final String fieldName = utf8.decode(nameBytes).trim();

    return EzField(
      fieldName,
      String.fromCharCode(map.type),
      map.len,
      map.dec,
      map.offset,
      map.storage,
      map.zbfSequence,
    );
  }
}

/// Extension to convert Dart List<EzField> directly into Native EzFieldMap Pointer
extension EzFieldListNative on List<EzField> {
  /// Allocates contiguous native memory for EzFieldMap array with null terminator.
  /// Matches C-engine 64-byte EZ_FIELD_NODE alignment.
  Pointer<EzFieldMap> toNativeMap(Arena arena) {
    final mapArray = arena<EzFieldMap>(length + 1);
    int currentOffset = 0;

    for (var i = 0; i < length; i++) {
      final f = this[i];
      final nameBytes = utf8.encode(f.name);

      for (var j = 0; j < 52; j++) {
        mapArray[i].name[j] = (j < nameBytes.length && j < 51) ? nameBytes[j] : 0;
      }

      mapArray[i].type = f.type.codeUnitAt(0);
      mapArray[i].len = f.len;
      mapArray[i].dec = f.dec;
      mapArray[i].storage = 0; // 0: Inline
      mapArray[i].offset = currentOffset;
      mapArray[i].zbfSequence = 0;

      currentOffset += f.len;
    }

    // End marker: type = 0 and name[0] = 0
    mapArray[length].name[0] = 0;
    mapArray[length].type = 0;

    return mapArray;
  }
}

// =====================================================================
// 🔗 RELATION SUBSYSTEM DART HIGH-LEVEL MODELS
// =====================================================================

class RlNode {
  final int ebfIndex;
  final String fieldName;
  final String aliasName;

  const RlNode({
    required this.ebfIndex,
    required this.fieldName,
    required this.aliasName,
  });
}

class RlLink {
  final int parentEbfIndex;
  final int childEbfIndex;
  final List<int> parentFkOffsets;
  final List<int> parentFkLens;
  final String childTagName;

  const RlLink({
    required this.parentEbfIndex,
    required this.childEbfIndex,
    required this.parentFkOffsets,
    required this.parentFkLens,
    required this.childTagName,
  });
}

class RlViewDesc {
  final String relationName;
  final int joinMode; // 0: EZ_RL_JOIN_LEFT, 1: EZ_RL_JOIN_INNER
  final List<int> ebfHandles;
  final List<RlNode> nodes;
  final List<RlLink> links;

  const RlViewDesc({
    required this.relationName,
    this.joinMode = 0,
    required this.ebfHandles,
    required this.nodes,
    required this.links,
  });
}

// =====================================================================
// 🚀 [2. Physical Struct Alignment: Aligned with ez_def.h / ez_relation_mgr.h]
// =====================================================================

/// Matches C `EZ_TAG_INFO` struct with 1-byte packed alignment (256 Bytes)
@Packed(1)
sealed class EzTagMap extends Struct {
  @Array(64)
  external Array<Uint8> tagName; // 64 Bytes (ez_char tag_name[64])

  @Uint32()
  external int keyLen; // 4 Bytes (u32 key_len)

  @Uint32()
  external int keyType; // 4 Bytes (u32 key_type)

  @Uint64()
  external int rootPtr; // 8 Bytes (u64 root_ptr)

  @Uint64()
  external int nodeCount; // 8 Bytes (u64 node_count)

  @Uint32()
  external int isDescending; // 4 Bytes (u32 is_descending)

  @Uint32()
  external int hSlot; // 4 Bytes (u32 h_slot)

  @Array(8)
  external Array<Uint32> fieldOffsets; // 32 Bytes (u32 field_offsets[8])

  @Array(8)
  external Array<Uint32> fieldLens; // 32 Bytes (u32 field_lens[8])

  @Uint8()
  external int fieldCount; // 1 Byte (u8 field_count)

  @Uint8()
  external int isUnique; // 1 Byte (u8 is_unique)

  @Array(94)
  external Array<Uint8> finalPad; // 94 Bytes (u8 _final_pad[94])
}

/// Exactly 64 Bytes to match C `EZ_FIELD_NODE`
@Packed(1)
sealed class EzFieldMap extends Struct {
  @Array(52)
  external Array<Uint8> name; // 52 Bytes
  @Uint8()
  external int type; // 1 Byte
  @Uint32()
  external int len; // 4 Bytes (u32 in C)
  @Uint8()
  external int dec; // 1 Byte
  @Uint8()
  external int storage; // 1 Byte
  @Uint32()
  external int offset; // 4 Bytes (u32 in C)
  @Uint8()
  external int zbfSequence; // 1 Byte (Total = 64 Bytes)
}

@Packed(1)
sealed class EzMigrateReport extends Struct {
  @Uint32()
  external int status;
  @Uint32()
  external int errorCode;
  @Uint64()
  external int totalRecs;
  @Uint64()
  external int recoveredRecs;
  @Array(128)
  external Array<Uint8> message;
}

/// Matches C `EZ_BLOB_PTR` (24 Bytes)
@Packed(1)
sealed class EzBlobPtr extends Struct {
  @Uint64()
  external int blobOffset;
  @Uint32()
  external int logicalLength;
  @Uint32()
  external int physicalLength;
  @Uint32()
  external int fileSequence;
  @Uint32()
  external int flags;
}

/// Matches C `EZ_RL_NODE_DESC` (106 bytes)
@Packed(2)
sealed class EzRlNodeDesc extends Struct {
  @Uint16()
  external int ebfIndex;
  @Array(52)
  external Array<Uint8> fieldName;
  @Array(52)
  external Array<Uint8> aliasName;
}

/// Matches C `EZ_RL_LINK_DESC`
@Packed(2)
sealed class EzRlLinkDesc extends Struct {
  @Uint16()
  external int parentEbfIndex;
  @Uint16()
  external int childEbfIndex;
  @Uint8()
  external int fkFieldCount;
  @Uint8()
  external int _padding; // Alignment padding
  @Array(8)
  external Array<Uint16> parentFkOffsets;
  @Array(8)
  external Array<Uint16> parentFkLens;
  @Array(48)
  external Array<Uint8> childTagName;
}

/// Matches C `EZ_RL_VIEW_DESC`
sealed class EzRlViewDesc extends Struct {
  external Pointer<Utf8> relationName;
  @Int32()
  external int joinMode;
  external Pointer<Uint64> hEbfArray;
  @Uint16()
  external int ebfCount;
  external Pointer<EzRlNodeDesc> nodes;
  @Uint16()
  external int nodeCount;
  external Pointer<EzRlLinkDesc> links;
  @Uint16()
  external int linkCount;
}

// =========================================================================
// ⚡ FFI Native Typedefs
// =========================================================================

typedef NativeEzDbGetTags = Pointer<EzTagMap> Function(Uint64 h);
typedef EzDbGetTags = Pointer<EzTagMap> Function(int h);

typedef NativeEzDbGetRecordVector = Int32 Function(
  Uint64 h,
  Uint32 tagId,
  Pointer<Utf8> tagName,
  Pointer<Void> outStructArray,
  Pointer<Uint32> pCount,
  Uint32 structSize,
  Uint8 stripStr,
  Uint8 binclude_deleted,
);

typedef EzDbGetRecordVector = int Function(
  int h,
  int tagId,
  Pointer<Utf8> tagName,
  Pointer<Void> outStructArray,
  Pointer<Uint32> pCount,
  int structSize,
  int stripStr,
  int include_deleted,
);

typedef NativeEzDbGetFdt = Pointer<EzFieldMap> Function(Uint64 h);
typedef EzDbGetFdt = Pointer<EzFieldMap> Function(int h);

// Relation Subsystem Native Signatures
typedef NativeEzRlMgrInit = Int32 Function();
typedef EzRlMgrInit = int Function();

typedef NativeEzRlMgrCleanup = Int32 Function();
typedef EzRlMgrCleanup = int Function();

typedef NativeEzRlBuildView = Uint64 Function(Pointer<EzRlViewDesc> desc);
typedef EzRlBuildView = int Function(Pointer<EzRlViewDesc> desc);

typedef NativeEzRlDestroyView = Int32 Function(Uint64 hRel);
typedef EzRlDestroyView = int Function(int hRel);

typedef NativeEzGetRelationTable = Pointer<Void> Function(Uint64 hRel);
typedef EzGetRelationTable = Pointer<Void> Function(int hRel);

typedef NativeEzRlGetRecordVector = Int32 Function(
  Pointer<Void> relTable,
  Pointer<Uint8> outBuffer,
  Uint32 requestCount,
  Pointer<Uint32> actualCount,
);
typedef EzRlGetRecordVector = int Function(
  Pointer<Void> relTable,
  Pointer<Uint8> outBuffer,
  int requestCount,
  Pointer<Uint32> actualCount,
);

// Native FFI Signatures for .ERL view persistence
typedef NativeEzRlSaveViewFile = Int32 Function(Pointer<EzRlViewDesc> desc, Pointer<Utf8> erlPath);
typedef EzRlSaveViewFile = int Function(Pointer<EzRlViewDesc> desc, Pointer<Utf8> erlPath);

typedef NativeEzRlLoadViewFile = Uint64 Function(Pointer<Utf8> erlPath, Pointer<Uint64> hEbfArray, Uint16 ebfCount);
typedef EzRlLoadViewFile = int Function(Pointer<Utf8> erlPath, Pointer<Uint64> hEbfArray, int ebfCount);

// Native State Observer Callback Signature
typedef EzStateObserverNative = Void Function(Uint32 slot, Uint32 event, Uint64 offset, Uint32 len, Pointer<Void> buffer);
typedef EzStateObserverDart = void Function(int slot, int event, int offset, int len, Pointer<Void> buffer);

// Native Diagnostics Error Subsystem Signatures
typedef NativeEzErrStr = Pointer<Utf8> Function(Int32 status);
typedef EzErrStr = Pointer<Utf8> Function(int status);

typedef NativeEzLastError = Pointer<Utf8> Function();
typedef EzLastError = Pointer<Utf8> Function();

// Native Quantization Signatures
typedef NativeEzQuantCompress = Int32 Function(
    Pointer<Float> inVec, Uint32 dim, Pointer<Uint8> outPacked, Pointer<Float> outMin, Pointer<Float> outMax);
typedef EzQuantCompress = int Function(
    Pointer<Float> inVec, int dim, Pointer<Uint8> outPacked, Pointer<Float> outMin, Pointer<Float> outMax);

typedef NativeEzQuantDecompress = Int32 Function(
    Pointer<Uint8> inPacked, Float minVal, Float maxVal, Uint32 dim, Pointer<Float> outVec);
typedef EzQuantDecompress = int Function(Pointer<Uint8> inPacked, double minVal, double maxVal, int dim, Pointer<Float> outVec);

// =====================================================================
// 🚀 [3. High-Level Pure Dart Record Reader (Zero C / FFI Exposure)]
// =====================================================================

// 📁 lib/services/ez_dbengine.dart

class EzRecordReader {
  final Uint8List _data;

  EzRecordReader(this._data);

  Uint8List get bytes => _data;

  /// Pure physical slice for text/numeric fields (padded with 0x20 spaces)
  String stringAt(int offset, int length) {
    if (offset + length > _data.length) return '';
    final sub = _data.sublist(offset, offset + length);

    String result = utf8.decode(sub, allowMalformed: true);

    // 1. Strip C null-terminators (\0)
    final int nullIdx = result.indexOf('\x00');
    if (nullIdx != -1) {
      result = result.substring(0, nullIdx);
    }

    // 2. Trim 0x20 ASCII space padding
    return result.trim();
  }

  /// Pure physical slice for 'B' Binary/BLOB fields (padded with 0x00)
  Uint8List bytesAt(int offset, int length) {
    if (offset + length > _data.length) return Uint8List(0);
    return _data.sublist(offset, offset + length);
  }

  int intAt(int offset, int length) {
    return int.tryParse(stringAt(offset, length)) ?? 0;
  }

  int longAt(int offset, int length) {
    return int.tryParse(stringAt(offset, length)) ?? 0;
  }

  /// Reads 8-byte binary IEEE 754 float64 double extracted by C vector core
  double doubleAt(int offset, [int length = 8]) {
    if (offset + 8 > _data.length) return 0.0;
    final ByteData bd = ByteData.sublistView(_data, offset, offset + 8);
    final double val = bd.getFloat64(0, Endian.little);
    return (val.isNaN || val.isInfinite) ? 0.0 : val;
  }

  int binaryAt(int offset, int length) {
    int result = 0;
    final cap = (length > 8) ? 8 : length;
    for (int i = 0; i < cap; i++) {
      result = (result << 8) | _data[offset + i];
    }
    return result;
  }
}

// =====================================================================
// 🚀 [4. Primary Engine Wrapper Class (Aligned with ez_engine.h & ez_relation_mgr.h)]
// =====================================================================

class EzDB {
  late DynamicLibrary _lib;

  // --- Group A: Lifecycle and Schema Maintenance ---
  late int Function(Pointer<Utf8>, Pointer<EzFieldMap>) _ezDbCreate;
  late int Function(int, Pointer<Utf8>, Pointer<EzFieldMap>, Pointer<EzMigrateReport>) _ezDbAlter;
  late int Function(int, Pointer<Utf8>, Pointer<EzMigrateReport>) _ezDbReconstruct;
  late int Function(Pointer<Utf8>, Pointer<EzMigrateReport>) _ezDbUse;
  late int Function(Pointer<Utf8>, Pointer<EzMigrateReport>) _ezDbOpen;
  late int Function(int) _ezDbClose;
  late int Function() _ezDbCloseAll;
  late void Function(int, double, int) _ezDbSetVacuum;
  late void Function(Pointer<Utf8>, Pointer<Uint8>, int) _ezDbGetNameFromPath;

  // --- Group B: Dual-Track Navigation and State ---
  late int Function(int, int, Pointer<Utf8>) _ezDbGoTop;
  late int Function(int, int, Pointer<Utf8>) _ezDbGoBottom;
  late int Function(int, int, Pointer<Utf8>, int) _ezDbSkip;
  late int Function(int, int, Pointer<Utf8>, int) _ezDbGoTo;
  late bool Function(int, int, Pointer<Utf8>) _ezDbIsEof;
  late bool Function(int, int, Pointer<Utf8>) _ezDbIsBof;
  late bool Function(int, int, Pointer<Utf8>) _ezDbIsFound;
  late int Function(int, int, Pointer<Utf8>) _ezDbRecNo;
  late int Function(int, int, Pointer<Utf8>) _ezDbLastRec;
  late int Function(int) _ezDbRecSize;
  late int Function(int) _ezDbRecordCount;

  // --- Group C: Data Retrieval & Modification ---
  late int Function(int, int, Pointer<Utf8>, Pointer<Void>, int, bool) _ezDbGetRecord;
  late EzDbGetRecordVector _ezDbGetRecordVector;

  // 搜尋對照組：TagName 與 TagId 雙軌搜尋 (陣列與單鍵版本)
  late int Function(int, Pointer<Utf8>, Pointer<Pointer<Void>>) _ezDbSeekByTagArray;
  late int Function(int, int, Pointer<Pointer<Void>>) _ezDbSeekByTagIdArray;

  late int Function(int, Pointer<Utf8>, Pointer<Void>, int) _ezDbLocate;
  late int Function(int, Pointer<Void>, int, Pointer<Utf8>) _ezDbAppend;
  late int Function(int, Pointer<Void>, int, Pointer<Utf8>) _ezDbInsert;
  late int Function(int, int, Pointer<Void>, Pointer<Utf8>) _ezDbRowReplace;
  late int Function(int, int, Pointer<Utf8>, Pointer<Void>) _ezDbReplace;

  late bool Function(int, int) _ezDbIsDeleted;
  late int Function(int, int) _ezDbDelete;
  late int Function(int, int) _ezDbRecall;
  late int Function(int, Pointer<Utf8>) _ezDbPack;
  late int Function(int) _ezDbZap;
  late int Function(int) _ezDbCommit;
  late int Function(int, Pointer<EzBlobPtr>, Pointer<Void>, int) _ezDbGetBlobData;

  // --- Group D: Index Management & Tag Maintenance ---
  late int Function(int, Pointer<Utf8>, Pointer<Utf8>, bool) _ezDbCreateIndex;
  late int Function(int, Pointer<Utf8>, int) _ezDbMountIndex;
  late int Function(int, int, int) _ezDbPurgeDuplicates;
  late int Function(int, int) _ezDbExtractDuplicates;

  // --- Group E: Reflection & Utilities ---
  late int Function(int, Pointer<Utf8>, int, Pointer<Utf8>) _ezDbGetFieldNames;
  late EzDbGetFdt _ezDbGetFdt;
  late EzDbGetTags _ezDbGetTags;
  late int Function(int) _ezDbGetDeleteCount;
  late void Function(int, Pointer<Void>) _ezDbDumpRecord;
  late void Function(int) _ezDbDumpWorkarea;

  // --- Group F: Event Observation & Telemetry ---
  late void Function(Pointer<NativeFunction<EzStateObserverNative>>) _ezSetStateObserver;

  // --- Group G: Relation Subsystem ---
  late EzRlMgrInit _ezRlMgrInit;
  late EzRlMgrCleanup _ezRlMgrCleanup;
  late EzRlBuildView _ezRlBuildView;
  late EzRlDestroyView _ezRlDestroyView;
  late EzGetRelationTable _ezGetRelationTable;
  late EzRlGetRecordVector _ezRlGetRecordVector;
  late EzRlSaveViewFile _ezRlSaveViewFile;
  late EzRlLoadViewFile _ezRlLoadViewFile;

  // --- Group H: Diagnostics and Error Subsystem ---
  late EzErrStr _ezErrStr;
  late EzLastError _ezLastError;

  // --- Group I: Quantization Subsystem ---
  late EzQuantCompress _ezQuantCompress;
  late EzQuantDecompress _ezQuantDecompress;

  EzDB() {
    _lib = Platform.isWindows
        ? DynamicLibrary.open('ez_dbengine.dll')
        : (Platform.isAndroid || Platform.isLinux ? DynamicLibrary.open('libez_dbengine.so') : DynamicLibrary.process());

    _initFunctions();
  }

  void _initFunctions() {
    // Group A: Lifecycle and Schema Maintenance
    _ezDbCreate =
        _lib.lookupFunction<Int32 Function(Pointer<Utf8>, Pointer<EzFieldMap>), int Function(Pointer<Utf8>, Pointer<EzFieldMap>)>(
            'ez_db_create');
    _ezDbAlter = _lib.lookupFunction<Int32 Function(Uint64, Pointer<Utf8>, Pointer<EzFieldMap>, Pointer<EzMigrateReport>),
        int Function(int, Pointer<Utf8>, Pointer<EzFieldMap>, Pointer<EzMigrateReport>)>('ez_db_alter');
    _ezDbReconstruct = _lib.lookupFunction<Int32 Function(Uint64, Pointer<Utf8>, Pointer<EzMigrateReport>),
        int Function(int, Pointer<Utf8>, Pointer<EzMigrateReport>)>('ez_db_reconstruct');
    _ezDbUse = _lib.lookupFunction<Uint64 Function(Pointer<Utf8>, Pointer<EzMigrateReport>),
        int Function(Pointer<Utf8>, Pointer<EzMigrateReport>)>('ez_db_use');
    _ezDbOpen = _lib.lookupFunction<Uint64 Function(Pointer<Utf8>, Pointer<EzMigrateReport>),
        int Function(Pointer<Utf8>, Pointer<EzMigrateReport>)>('ez_db_open');
    _ezDbClose = _lib.lookupFunction<Int32 Function(Uint64), int Function(int)>('ez_db_close');
    _ezDbCloseAll = _lib.lookupFunction<Int32 Function(), int Function()>('ez_db_close_all');
    _ezDbSetVacuum = _lib.lookupFunction<Void Function(Uint64, Float, Uint32), void Function(int, double, int)>('ez_db_set_vacuum');
    _ezDbGetNameFromPath = _lib.lookupFunction<Void Function(Pointer<Utf8>, Pointer<Uint8>, Uint32),
        void Function(Pointer<Utf8>, Pointer<Uint8>, int)>('ez_db_get_name_from_path');

    // Group B: Dual-Track Navigation and State
    _ezDbGoTop =
        _lib.lookupFunction<Int32 Function(Uint64, Uint32, Pointer<Utf8>), int Function(int, int, Pointer<Utf8>)>('ez_db_gotop');
    _ezDbGoBottom =
        _lib.lookupFunction<Int32 Function(Uint64, Uint32, Pointer<Utf8>), int Function(int, int, Pointer<Utf8>)>('ez_db_gobottom');
    _ezDbSkip =
        _lib.lookupFunction<Int32 Function(Uint64, Uint32, Pointer<Utf8>, Int32), int Function(int, int, Pointer<Utf8>, int)>(
            'ez_db_skip');
    _ezDbGoTo =
        _lib.lookupFunction<Int32 Function(Uint64, Uint32, Pointer<Utf8>, Uint64), int Function(int, int, Pointer<Utf8>, int)>(
            'ez_db_goto');
    _ezDbIsEof =
        _lib.lookupFunction<Bool Function(Uint64, Uint32, Pointer<Utf8>), bool Function(int, int, Pointer<Utf8>)>('ez_db_is_eof');
    _ezDbIsBof =
        _lib.lookupFunction<Bool Function(Uint64, Uint32, Pointer<Utf8>), bool Function(int, int, Pointer<Utf8>)>('ez_db_is_bof');
    _ezDbIsFound =
        _lib.lookupFunction<Bool Function(Uint64, Uint32, Pointer<Utf8>), bool Function(int, int, Pointer<Utf8>)>('ez_db_is_found');
    _ezDbRecNo =
        _lib.lookupFunction<Int64 Function(Uint64, Uint32, Pointer<Utf8>), int Function(int, int, Pointer<Utf8>)>('ez_db_recno');
    _ezDbLastRec =
        _lib.lookupFunction<Int64 Function(Uint64, Uint32, Pointer<Utf8>), int Function(int, int, Pointer<Utf8>)>('ez_db_lastrec');
    _ezDbRecSize = _lib.lookupFunction<Uint32 Function(Uint64), int Function(int)>('ez_db_recsize');
    _ezDbRecordCount = _lib.lookupFunction<Uint64 Function(Uint64), int Function(int)>('ez_db_record_count');

    // Group C: Data Retrieval & Modification
    _ezDbGetRecord = _lib.lookupFunction<Int32 Function(Uint64, Uint32, Pointer<Utf8>, Pointer<Void>, Uint32, Bool),
        int Function(int, int, Pointer<Utf8>, Pointer<Void>, int, bool)>('ez_db_get_record');
    _ezDbGetRecordVector = _lib.lookupFunction<NativeEzDbGetRecordVector, EzDbGetRecordVector>('ez_db_get_record_vector');

    // Tag 搜尋 API 綁定 (ez_engine.h)
    _ezDbSeekByTagArray = _lib.lookupFunction<Int32 Function(Uint64, Pointer<Utf8>, Pointer<Pointer<Void>>),
        int Function(int, Pointer<Utf8>, Pointer<Pointer<Void>>)>('ez_db_seek_by_tag_array');
    _ezDbSeekByTagIdArray =
        _lib.lookupFunction<Int32 Function(Uint64, Uint32, Pointer<Pointer<Void>>), int Function(int, int, Pointer<Pointer<Void>>)>(
            'ez_db_seek_by_tag_id_array');

    _ezDbLocate = _lib.lookupFunction<Int32 Function(Uint64, Pointer<Utf8>, Pointer<Void>, Uint8),
        int Function(int, Pointer<Utf8>, Pointer<Void>, int)>('ez_db_locate');
    _ezDbAppend = _lib.lookupFunction<Int32 Function(Uint64, Pointer<Void>, Uint32, Pointer<Utf8>),
        int Function(int, Pointer<Void>, int, Pointer<Utf8>)>('ez_db_append');
    _ezDbInsert = _lib.lookupFunction<Int32 Function(Uint64, Pointer<Void>, Uint32, Pointer<Utf8>),
        int Function(int, Pointer<Void>, int, Pointer<Utf8>)>('ez_db_insert');
    _ezDbRowReplace = _lib.lookupFunction<Int32 Function(Uint64, Uint64, Pointer<Void>, Pointer<Utf8>),
        int Function(int, int, Pointer<Void>, Pointer<Utf8>)>('ez_db_row_replace');
    _ezDbReplace = _lib.lookupFunction<Int32 Function(Uint64, Uint64, Pointer<Utf8>, Pointer<Void>),
        int Function(int, int, Pointer<Utf8>, Pointer<Void>)>('ez_db_replace');

    _ezDbIsDeleted = _lib.lookupFunction<Bool Function(Uint64, Uint64), bool Function(int, int)>('ez_db_is_deleted');
    _ezDbDelete = _lib.lookupFunction<Int32 Function(Uint64, Uint64), int Function(int, int)>('ez_db_delete');
    _ezDbRecall = _lib.lookupFunction<Int32 Function(Uint64, Uint64), int Function(int, int)>('ez_db_recall');
    _ezDbPack = _lib.lookupFunction<Int32 Function(Uint64, Pointer<Utf8>), int Function(int, Pointer<Utf8>)>('ez_db_pack');
    _ezDbZap = _lib.lookupFunction<Int32 Function(Uint64), int Function(int)>('ez_db_zap');
    _ezDbCommit = _lib.lookupFunction<Int32 Function(Uint64), int Function(int)>('ez_db_commit');
    _ezDbGetBlobData = _lib.lookupFunction<Int32 Function(Uint64, Pointer<EzBlobPtr>, Pointer<Void>, Uint32),
        int Function(int, Pointer<EzBlobPtr>, Pointer<Void>, int)>('ez_db_get_blob_data');

    // Group D: Index Management & Tag Maintenance
    _ezDbCreateIndex = _lib.lookupFunction<Int32 Function(Uint64, Pointer<Utf8>, Pointer<Utf8>, Bool),
        int Function(int, Pointer<Utf8>, Pointer<Utf8>, bool)>('ez_db_create_index');
    _ezDbMountIndex = _lib
        .lookupFunction<Int32 Function(Uint64, Pointer<Utf8>, Uint32), int Function(int, Pointer<Utf8>, int)>('ez_db_mount_index');
    _ezDbPurgeDuplicates =
        _lib.lookupFunction<Int32 Function(Uint64, Uint32, Uint64), int Function(int, int, int)>('ez_db_purge_duplicates');
    _ezDbExtractDuplicates =
        _lib.lookupFunction<Int32 Function(Uint64, Uint32), int Function(int, int)>('ez_db_extract_duplicates');

    // Group E: Reflection & Utilities
    _ezDbGetFieldNames = _lib.lookupFunction<Int32 Function(Uint64, Pointer<Utf8>, Uint32, Pointer<Utf8>),
        int Function(int, Pointer<Utf8>, int, Pointer<Utf8>)>('ez_db_get_field_names');
    _ezDbGetFdt = _lib.lookupFunction<NativeEzDbGetFdt, EzDbGetFdt>('ez_db_get_fdt');
    _ezDbGetTags = _lib.lookupFunction<NativeEzDbGetTags, EzDbGetTags>('ez_db_get_tags');
    _ezDbGetDeleteCount = _lib.lookupFunction<Uint64 Function(Uint64), int Function(int)>('ez_db_get_delete_count');
    _ezDbDumpRecord =
        _lib.lookupFunction<Void Function(Uint64, Pointer<Void>), void Function(int, Pointer<Void>)>('ez_db_dump_record');
    _ezDbDumpWorkarea = _lib.lookupFunction<Void Function(Uint64), void Function(int)>('ez_db_dump_workarea');

    // Group F: Event Observation & Telemetry
    _ezSetStateObserver = _lib.lookupFunction<Void Function(Pointer<NativeFunction<EzStateObserverNative>>),
        void Function(Pointer<NativeFunction<EzStateObserverNative>>)>('ez_set_state_observer');

    // Group G: Relation Subsystem
    _ezRlMgrInit = _lib.lookupFunction<NativeEzRlMgrInit, EzRlMgrInit>('ez_rl_mgr_init');
    _ezRlMgrCleanup = _lib.lookupFunction<NativeEzRlMgrCleanup, EzRlMgrCleanup>('ez_rl_mgr_cleanup');
    _ezRlBuildView = _lib.lookupFunction<NativeEzRlBuildView, EzRlBuildView>('ez_rl_build_view');
    _ezRlDestroyView = _lib.lookupFunction<NativeEzRlDestroyView, EzRlDestroyView>('ez_rl_destroy_view');
    _ezGetRelationTable = _lib.lookupFunction<NativeEzGetRelationTable, EzGetRelationTable>('_ez_get_relation_table');
    _ezRlGetRecordVector = _lib.lookupFunction<NativeEzRlGetRecordVector, EzRlGetRecordVector>('ez_rl_get_record_vector');
    _ezRlSaveViewFile = _lib.lookupFunction<NativeEzRlSaveViewFile, EzRlSaveViewFile>('ez_rl_save_view_file');
    _ezRlLoadViewFile = _lib.lookupFunction<NativeEzRlLoadViewFile, EzRlLoadViewFile>('ez_rl_load_view_file');

    // Group H: Diagnostics and Error Subsystem
    _ezErrStr = _lib.lookupFunction<NativeEzErrStr, EzErrStr>('ez_errstr');
    _ezLastError = _lib.lookupFunction<NativeEzLastError, EzLastError>('ez_last_error');

    // Group I: Quantization Subsystem
    _ezQuantCompress = _lib.lookupFunction<NativeEzQuantCompress, EzQuantCompress>('ez_quant_compress_f32_4bit');
    _ezQuantDecompress = _lib.lookupFunction<NativeEzQuantDecompress, EzQuantDecompress>('ez_quant_decompress_4bit_f32');
  }

  // =====================================================================
  // 🚀 [5. High-Level Public APIs]
  // =====================================================================

  // --- Group A: Lifecycle and Schema Maintenance ---
  int create(String path, List<EzField> fields) {
    return using((arena) {
      final pathPtr = path.toNativeUtf8(allocator: arena);
      final mapPtr = fields.toNativeMap(arena);
      return _ezDbCreate(pathPtr, mapPtr);
    });
  }

  int alter(int handle, String path, Pointer<EzFieldMap> newMap, Pointer<EzMigrateReport> report) {
    return using((arena) {
      final pathPtr = path.toNativeUtf8(allocator: arena);
      return _ezDbAlter(handle, pathPtr, newMap, report);
    });
  }

  int reconstruct(int handle, String path, Pointer<EzMigrateReport> report) {
    return using((arena) {
      final pathPtr = path.toNativeUtf8(allocator: arena);
      return _ezDbReconstruct(handle, pathPtr, report);
    });
  }

  int use(String path, Pointer<EzMigrateReport> report) {
    return using((arena) {
      final pathPtr = path.toNativeUtf8(allocator: arena);
      return _ezDbUse(pathPtr, report);
    });
  }

  int open(String path, Pointer<EzMigrateReport> report) {
    return using((arena) {
      final pathPtr = path.toNativeUtf8(allocator: arena);
      return _ezDbOpen(pathPtr, report);
    });
  }

  int close(int handle) => _ezDbClose(handle);
  int closeAll() => _ezDbCloseAll();
  void setVacuum(int handle, double threshold, int minDeleted) => _ezDbSetVacuum(handle, threshold, minDeleted);

  String getNameFromPath(String path, {int maxLen = 64}) {
    return using((arena) {
      final pathPtr = path.toNativeUtf8(allocator: arena);
      final outBuf = arena<Uint8>(maxLen);
      _ezDbGetNameFromPath(pathPtr, outBuf, maxLen);
      final bytes = outBuf.asTypedList(maxLen);
      int len = bytes.indexOf(0);
      if (len < 0) len = maxLen;
      return utf8.decode(bytes.sublist(0, len), allowMalformed: true);
    });
  }

  // --- Group B: Dual-Track Navigation and State ---
  int goTop(int handle, {int tagId = 0, String tagName = ''}) {
    return using((arena) {
      final tagPtr = tagName.isEmpty ? nullptr : tagName.toNativeUtf8(allocator: arena);
      return _ezDbGoTop(handle, tagId, tagPtr);
    });
  }

  int goBottom(int handle, {int tagId = 0, String tagName = ''}) {
    return using((arena) {
      final tagPtr = tagName.isEmpty ? nullptr : tagName.toNativeUtf8(allocator: arena);
      return _ezDbGoBottom(handle, tagId, tagPtr);
    });
  }

  int skip(int handle, int count, {int tagId = 0, String tagName = ''}) {
    return using((arena) {
      final tagPtr = tagName.isEmpty ? nullptr : tagName.toNativeUtf8(allocator: arena);
      return _ezDbSkip(handle, tagId, tagPtr, count);
    });
  }

  int goTo(int handle, int recNo, {int tagId = 0, String tagName = ''}) {
    return using((arena) {
      final tagPtr = tagName.isEmpty ? nullptr : tagName.toNativeUtf8(allocator: arena);
      return _ezDbGoTo(handle, tagId, tagPtr, recNo);
    });
  }

  bool isEof(int handle, {int tagId = 0, String tagName = ''}) {
    return using((arena) {
      final tagPtr = tagName.isEmpty ? nullptr : tagName.toNativeUtf8(allocator: arena);
      return _ezDbIsEof(handle, tagId, tagPtr);
    });
  }

  bool isBof(int handle, {int tagId = 0, String tagName = ''}) {
    return using((arena) {
      final tagPtr = tagName.isEmpty ? nullptr : tagName.toNativeUtf8(allocator: arena);
      return _ezDbIsBof(handle, tagId, tagPtr);
    });
  }

  bool isFound(int handle, {int tagId = 0, String tagName = ''}) {
    return using((arena) {
      final tagPtr = tagName.isEmpty ? nullptr : tagName.toNativeUtf8(allocator: arena);
      return _ezDbIsFound(handle, tagId, tagPtr);
    });
  }

  int getRecNo(int handle, {int tagId = 0, String tagName = ''}) {
    return using((arena) {
      final tagPtr = tagName.isEmpty ? nullptr : tagName.toNativeUtf8(allocator: arena);
      return _ezDbRecNo(handle, tagId, tagPtr);
    });
  }

  int getLastRec(int handle, {int tagId = 0, String tagName = ''}) {
    return using((arena) {
      final tagPtr = tagName.isEmpty ? nullptr : tagName.toNativeUtf8(allocator: arena);
      return _ezDbLastRec(handle, tagId, tagPtr);
    });
  }

  int getRecSize(int handle) => _ezDbRecSize(handle);
  int getRecordSize(int handle) => _ezDbRecSize(handle);
  int getRecordCount(int handle) => _ezDbRecordCount(handle);

  // --- Group C: Data Retrieval & Modification ---
  int getRecord(
    int handle,
    Pointer<Void> buffer,
    int bufferSize, {
    bool includeDeleted = false,
    int tagId = 0,
    String tagName = '',
  }) {
    return using((arena) {
      final tagPtr = tagName.isEmpty ? nullptr : tagName.toNativeUtf8(allocator: arena);
      return _ezDbGetRecord(handle, tagId, tagPtr, buffer, bufferSize, includeDeleted);
    });
  }

  EzRecordReader? readRecord(
    int handle, {
    bool includeDeleted = false,
    int tagId = 0,
    String tagName = '',
  }) {
    final recSize = getRecordSize(handle);
    if (recSize == 0) return null;

    return using((arena) {
      final nativeBuf = arena<Uint8>(recSize);
      final tagPtr = tagName.isEmpty ? nullptr : tagName.toNativeUtf8(allocator: arena);
      final status = _ezDbGetRecord(handle, tagId, tagPtr, nativeBuf.cast<Void>(), recSize, includeDeleted);
      if (status != 0) return null;

      final bytes = Uint8List.fromList(nativeBuf.asTypedList(recSize));
      return EzRecordReader(bytes);
    });
  }

  List<EzRecordReader> readRecordVector(
    int handle, {
    required int count,
    int tagId = 0,
    String tagName = '',
    bool stripStr = true,
    bool includeDeleted = true,
  }) {
    final recSize = getRecordSize(handle);
    if (recSize == 0 || count <= 0) return <EzRecordReader>[];

    return using((arena) {
      final totalSize = count * recSize;
      final nativeBuf = arena<Uint8>(totalSize);
      final pCount = arena<Uint32>()..value = count;
      final tagPtr = tagName.isEmpty ? nullptr : tagName.toNativeUtf8(allocator: arena);

      final status = _ezDbGetRecordVector(
        handle,
        tagId,
        tagPtr,
        nativeBuf.cast<Void>(),
        pCount,
        recSize,
        stripStr ? 1 : 0,
        includeDeleted ? 1 : 0,
      );

      if (status != 0) return <EzRecordReader>[];

      final actualCount = pCount.value;
      final rawBytes = Uint8List.fromList(nativeBuf.asTypedList(actualCount * recSize));
      final listReaders = <EzRecordReader>[];

      for (int i = 0; i < actualCount; i++) {
        final offset = i * recSize;
        final recordBytes = rawBytes.sublist(offset, offset + recSize);
        listReaders.add(EzRecordReader(recordBytes));
      }

      return listReaders;
    });
  }

  // 💡 正確對稱的雙軌 Seek APIs：
  // 1. Tag Name 系列 (ez_db_seek_by_tag / ez_db_seek_by_tag_array)
  int seekByTagName(int handle, String tagName, String key) {
    return using((arena) {
      final tagPtr = tagName.toNativeUtf8(allocator: arena);
      final ptrArray = arena<Pointer<Void>>(2);
      ptrArray[0] = key.toNativeUtf8(allocator: arena).cast<Void>();
      ptrArray[1] = nullptr; // 結尾 Sentinel NULL
      return _ezDbSeekByTagArray(handle, tagPtr, ptrArray);
    });
  }

  int seekByTagNameArray(int handle, String tagName, List<String> keys) {
    return using((arena) {
      final tagPtr = tagName.toNativeUtf8(allocator: arena);
      final ptrArray = arena<Pointer<Void>>(keys.length + 1);
      for (var i = 0; i < keys.length; i++) {
        ptrArray[i] = keys[i].toNativeUtf8(allocator: arena).cast<Void>();
      }
      ptrArray[keys.length] = nullptr; // 結尾 Sentinel NULL
      return _ezDbSeekByTagArray(handle, tagPtr, ptrArray);
    });
  }

  // 2. Tag ID 系列 (ez_db_seek_by_tag_id / ez_db_seek_by_tag_id_array)
  int seekByTagId(int handle, int tagId, String key) {
    return using((arena) {
      final ptrArray = arena<Pointer<Void>>(2);
      ptrArray[0] = key.toNativeUtf8(allocator: arena).cast<Void>();
      ptrArray[1] = nullptr; // 結尾 Sentinel NULL
      return _ezDbSeekByTagIdArray(handle, tagId, ptrArray);
    });
  }

  int seekByTagIdArray(int handle, int tagId, List<String> keys) {
    return using((arena) {
      final ptrArray = arena<Pointer<Void>>(keys.length + 1);
      for (var i = 0; i < keys.length; i++) {
        ptrArray[i] = keys[i].toNativeUtf8(allocator: arena).cast<Void>();
      }
      ptrArray[keys.length] = nullptr; // 結尾 Sentinel NULL
      return _ezDbSeekByTagIdArray(handle, tagId, ptrArray);
    });
  }

  // 兼容舊版命名：保留 seekByTag 與 seekByName 作為別名轉發
  bool seekByTag(int handle, String tagName, String key) => seekByTagName(handle, tagName, key) == 0;
  bool seekByName(int handle, String tagName, List<String> keys) => seekByTagNameArray(handle, tagName, keys) == 0;
  bool seekById(int handle, int tagId, List<String> keys) => seekByTagIdArray(handle, tagId, keys) == 0;

  int locate(int handle, String fieldName, String targetValue, {bool partialMatch = false}) {
    return using((arena) {
      final namePtr = fieldName.toNativeUtf8(allocator: arena);
      final valPtr = targetValue.toNativeUtf8(allocator: arena);
      final int iPartial = partialMatch ? 1 : 0;
      return _ezDbLocate(handle, namePtr, valPtr.cast<Void>(), iPartial);
    });
  }

  int append(int handle, String data, {int recCount = 1, String delimiter = ','}) {
    return using((arena) {
      final dataPtr = data.toNativeUtf8(allocator: arena);
      final delPtr = delimiter.toNativeUtf8(allocator: arena);
      return _ezDbAppend(handle, dataPtr.cast<Void>(), recCount, delPtr);
    });
  }

  int insert(int handle, String data, {int recCount = 1, String delimiter = ','}) {
    return using((arena) {
      final dataPtr = data.toNativeUtf8(allocator: arena);
      final delPtr = delimiter.toNativeUtf8(allocator: arena);
      return _ezDbInsert(handle, dataPtr.cast<Void>(), recCount, delPtr);
    });
  }

  int rowReplace(int handle, int rowId, String data, {String delimiter = ','}) {
    return using((arena) {
      final dataPtr = data.toNativeUtf8(allocator: arena);
      final delPtr = delimiter.toNativeUtf8(allocator: arena);
      return _ezDbRowReplace(handle, rowId, dataPtr.cast<Void>(), delPtr);
    });
  }

  int replace(int handle, int rowId, String fieldName, String value) {
    return using((arena) {
      final namePtr = fieldName.toNativeUtf8(allocator: arena);
      final valPtr = value.toNativeUtf8(allocator: arena);
      return _ezDbReplace(handle, rowId, namePtr, valPtr.cast<Void>());
    });
  }

  bool isDeleted(int handle, int rowId) => _ezDbIsDeleted(handle, rowId);
  int deleteRecord(int handle, int rowId) => _ezDbDelete(handle, rowId);
  int recallRecord(int handle, int rowId) => _ezDbRecall(handle, rowId);

  int pack(int handle, [String path = '']) {
    return using((arena) {
      final pathPtr = path.isEmpty ? nullptr : path.toNativeUtf8(allocator: arena);
      return _ezDbPack(handle, pathPtr);
    });
  }

  int zap(int handle) => _ezDbZap(handle);
  int commit(int handle) => _ezDbCommit(handle);

  int getBlobData(int handle, Pointer<EzBlobPtr> blobPtr, Pointer<Void> outBuf, int outBufSize) {
    return _ezDbGetBlobData(handle, blobPtr, outBuf, outBufSize);
  }

  // --- Group D: Index Management & Tag Maintenance ---
  int createIndex(int handle, String tagName, String fieldsStr, {bool isUnique = false}) {
    return using((arena) {
      final tagPtr = tagName.toNativeUtf8(allocator: arena);
      final fieldsPtr = fieldsStr.toNativeUtf8(allocator: arena);
      return _ezDbCreateIndex(handle, tagPtr, fieldsPtr, isUnique);
    });
  }

  int mountIndex(int handle, String edxPath, int slotId) {
    return using((arena) {
      final pathPtr = edxPath.toNativeUtf8(allocator: arena);
      return _ezDbMountIndex(handle, pathPtr, slotId);
    });
  }

  int purgeDuplicates(int handle, int tagId, int keepRowId) {
    return _ezDbPurgeDuplicates(handle, tagId, keepRowId);
  }

  int extractDuplicates(int handle, int tagId) {
    return _ezDbExtractDuplicates(handle, tagId);
  }

  // --- Group E: Reflection & Utilities ---
  List<String> getFieldNames(int handle, [String delimiter = ',']) {
    if (handle == 0) return <String>[];

    return using((arena) {
      const int bufferSize = 2048;
      final outBuf = arena<Uint8>(bufferSize).cast<Utf8>();
      final delPtr = delimiter.toNativeUtf8(allocator: arena);

      final status = _ezDbGetFieldNames(handle, outBuf, bufferSize, delPtr);
      if (status == 0) {
        final rawNames = outBuf.toDartString();
        if (rawNames.isEmpty) return <String>[];
        return rawNames.split(delimiter);
      }
      return <String>[];
    });
  }

  List<EzField> getFdt(int handle) {
    if (handle == 0) return <EzField>[];

    final Pointer<EzFieldMap> ptrFdt = _ezDbGetFdt(handle);
    if (ptrFdt == nullptr) return <EzField>[];

    final List<EzField> lstFields = <EzField>[];
    for (int i = 0; i < 94; i++) {
      final EzFieldMap mapNode = ptrFdt[i];
      if (mapNode.type == 0) break; // 嚴格比對 C 核心結束標記
      lstFields.add(EzField.fromNative(mapNode));
    }

    return lstFields;
  }

  List<EzTag> getTags(int handle) {
    if (handle == 0) return <EzTag>[];

    final Pointer<EzTagMap> ptrTags = _ezDbGetTags(handle);
    if (ptrTags == nullptr) return <EzTag>[];

    final List<EzField> lstFields = getFdt(handle);
    final List<EzTag> lstTags = <EzTag>[];

    for (int i = 0; i < 8; i++) {
      final EzTagMap tagNode = ptrTags[i];

      final List<int> nameBytes = <int>[];
      for (int j = 0; j < 64; j++) {
        if (tagNode.tagName[j] == 0) break;
        nameBytes.add(tagNode.tagName[j]);
      }

      final String strTagName = utf8.decode(nameBytes, allowMalformed: true).trim();
      if (strTagName.isEmpty) continue;

      final List<String> exprFields = <String>[];
      for (int f = 0; f < tagNode.fieldCount && f < 8; f++) {
        final int u32Offset = tagNode.fieldOffsets[f];

        for (final field in lstFields) {
          if (field.offset == u32Offset) {
            exprFields.add(field.name);
            break;
          }
        }
      }

      lstTags.add(EzTag(
        name: strTagName,
        expression: exprFields.join('+'),
        isUnique: tagNode.isUnique == 1,
        fieldCount: tagNode.fieldCount,
      ));
    }

    return lstTags;
  }

  int getDeleteCount(int handle) => _ezDbGetDeleteCount(handle);
  void dumpRecord(int handle, Pointer<Void> recordPayload) => _ezDbDumpRecord(handle, recordPayload);
  void dumpWorkarea(int handle) => _ezDbDumpWorkarea(handle);

  // --- Group F: Event Observation & Telemetry ---
  void setStateObserver(Pointer<NativeFunction<EzStateObserverNative>> cb) {
    _ezSetStateObserver(cb);
  }

  // --- Group G: Relation Subsystem ---
  int rlMgrInit() => _ezRlMgrInit();
  int rlMgrCleanup() => _ezRlMgrCleanup();

  int rlBuildView(RlViewDesc desc) {
    return using((arena) {
      final viewDescPtr = _convertRlViewDescToNative(desc, arena);
      return _ezRlBuildView(viewDescPtr);
    });
  }

  int rlDestroyView(int hRel) => _ezRlDestroyView(hRel);

  List<EzRecordReader> rlGetRecordVector(int hRel, int recordSize, {int count = 200}) {
    if (hRel == 0 || recordSize <= 0 || count <= 0) return <EzRecordReader>[];

    final relTablePtr = _ezGetRelationTable(hRel);
    if (relTablePtr == nullptr) return <EzRecordReader>[];

    return using((arena) {
      final totalBufSize = count * recordSize;
      final outBuffer = arena<Uint8>(totalBufSize);
      final pActualCount = arena<Uint32>();

      final status = _ezRlGetRecordVector(relTablePtr, outBuffer, count, pActualCount);
      if (status != 0) return <EzRecordReader>[];

      final actualCount = pActualCount.value;
      final rawBytes = Uint8List.fromList(outBuffer.asTypedList(actualCount * recordSize));
      final listReaders = <EzRecordReader>[];

      for (int i = 0; i < actualCount; i++) {
        final offset = i * recordSize;
        final recordBytes = rawBytes.sublist(offset, offset + recordSize);
        listReaders.add(EzRecordReader(recordBytes));
      }

      return listReaders;
    });
  }

  Pointer<EzRlViewDesc> _convertRlViewDescToNative(RlViewDesc desc, Arena arena) {
    final viewDescPtr = arena<EzRlViewDesc>();

    viewDescPtr.ref.relationName = desc.relationName.toNativeUtf8(allocator: arena);
    viewDescPtr.ref.joinMode = desc.joinMode;

    final ebfArrayPtr = arena<Uint64>(desc.ebfHandles.length);
    for (int i = 0; i < desc.ebfHandles.length; i++) {
      ebfArrayPtr[i] = desc.ebfHandles[i];
    }
    viewDescPtr.ref.hEbfArray = ebfArrayPtr;
    viewDescPtr.ref.ebfCount = desc.ebfHandles.length;

    final nodesPtr = arena<EzRlNodeDesc>(desc.nodes.length);
    for (int i = 0; i < desc.nodes.length; i++) {
      final node = desc.nodes[i];
      nodesPtr[i].ebfIndex = node.ebfIndex;

      final nameBytes = utf8.encode(node.fieldName);
      for (int j = 0; j < 52; j++) {
        nodesPtr[i].fieldName[j] = (j < nameBytes.length && j < 51) ? nameBytes[j] : 0;
      }

      final aliasBytes = utf8.encode(node.aliasName);
      for (int j = 0; j < 52; j++) {
        nodesPtr[i].aliasName[j] = (j < aliasBytes.length && j < 51) ? aliasBytes[j] : 0;
      }
    }
    viewDescPtr.ref.nodes = nodesPtr;
    viewDescPtr.ref.nodeCount = desc.nodes.length;

    final linksPtr = arena<EzRlLinkDesc>(desc.links.length);
    for (int i = 0; i < desc.links.length; i++) {
      final link = desc.links[i];
      linksPtr[i].parentEbfIndex = link.parentEbfIndex;
      linksPtr[i].childEbfIndex = link.childEbfIndex;
      linksPtr[i].fkFieldCount = link.parentFkOffsets.length;

      for (int f = 0; f < link.parentFkOffsets.length && f < 8; f++) {
        linksPtr[i].parentFkOffsets[f] = link.parentFkOffsets[f];
        linksPtr[i].parentFkLens[f] = link.parentFkLens[f];
      }

      final tagBytes = utf8.encode(link.childTagName);
      for (int j = 0; j < 48; j++) {
        linksPtr[i].childTagName[j] = (j < tagBytes.length && j < 47) ? tagBytes[j] : 0;
      }
    }
    viewDescPtr.ref.links = linksPtr;
    viewDescPtr.ref.linkCount = desc.links.length;

    return viewDescPtr;
  }

  int rlSaveViewFile(RlViewDesc desc, String path) {
    return using((arena) {
      final pathPtr = path.toNativeUtf8(allocator: arena);
      final viewDescPtr = _convertRlViewDescToNative(desc, arena);
      return _ezRlSaveViewFile(viewDescPtr, pathPtr);
    });
  }

  int rlLoadViewFile(String path, List<int> ebfHandles) {
    return using((arena) {
      final pathPtr = path.toNativeUtf8(allocator: arena);
      final ebfArrayPtr = arena<Uint64>(ebfHandles.length);
      for (int i = 0; i < ebfHandles.length; i++) {
        ebfArrayPtr[i] = ebfHandles[i];
      }
      return _ezRlLoadViewFile(pathPtr, ebfArrayPtr, ebfHandles.length);
    });
  }

  void clearTags(int handle) {
    if (handle == 0) return;

    final Pointer<EzTagMap> ptrTags = _ezDbGetTags(handle);
    if (ptrTags == nullptr) return;

    for (int i = 0; i < 8; i++) {
      ptrTags[i].tagName[0] = 0;
    }
  }

  // --- Group H: Diagnostics and Error Subsystem ---
  String errStr(int status) {
    final Pointer<Utf8> ptr = _ezErrStr(status);
    if (ptr == nullptr) return "Unknown engine error";
    return ptr.toDartString();
  }

  String lastError() {
    final Pointer<Utf8> ptr = _ezLastError();
    if (ptr == nullptr) return "";
    return ptr.toDartString();
  }

  String getDetailedError(int status) {
    final String dyn = lastError();
    final String desc = errStr(status);
    if (dyn.isNotEmpty) {
      return "[$desc] $dyn (Code: $status)";
    }
    return "[$desc] (Code: $status)";
  }

  // --- Group I: Quantization Subsystem ---
  int quantCompressF32(Pointer<Float> inVec, int dim, Pointer<Uint8> outPacked, Pointer<Float> outMin, Pointer<Float> outMax) {
    return _ezQuantCompress(inVec, dim, outPacked, outMin, outMax);
  }

  int quantDecompressF32(Pointer<Uint8> inPacked, double minVal, double maxVal, int dim, Pointer<Float> outVec) {
    return _ezQuantDecompress(inPacked, minVal, maxVal, dim, outVec);
  }
}
