/*
 * Copyrights (c) 2026 ezLink.io All rights reserved.
 * @ Author : CHI-HSIUNG YANG
 * @ File   : ebf_tab_context.dart
 */

import '../services/ez_dbengine.dart';

/// Field geometry descriptor for C vector output struct
class VectorFieldInfo {
  final EzField field;
  final int vectorOffset;
  final int vectorLen;

  VectorFieldInfo({
    required this.field,
    required this.vectorOffset,
    required this.vectorLen,
  });
}

/// Model class encapsulating context state for an opened EBF file tab
class EbfTabContext {
  final String strId;
  final String strFileName;
  final String strFilePath;
  final int iHandle;
  int iActiveSlotIndex;
  List<String> listEdxKeys;

  /// Tab-scoped active bottom tool state ('relation', 'schema', or null)
  String? strActiveBottomTool;

  EbfTabContext({
    required this.strId,
    required this.strFileName,
    required this.strFilePath,
    required this.iHandle,
    this.iActiveSlotIndex = 0,
    this.listEdxKeys = const <String>[],
    this.strActiveBottomTool,
  });
}
