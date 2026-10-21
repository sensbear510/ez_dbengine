/*
 * Copyrights (c) 2026 ezLink.io All rights reserved.
 * This source code may not be redistributed without the copyright owner's
 * written consent.
 *
 * @ Author : CHI-HSIUNG YANG
 * @ File   : custom_trace.dart
 */

/// Stack trace parser for extracting caller functions, line numbers, and file names
class CustomTrace {
  final StackTrace _trace;

  late String fileName;
  late String functionName;
  late String callerFunctionName;
  late int lineNumber;
  late int columnNumber;

  CustomTrace(this._trace) {
    _parseTrace();
  }

  String _getFunctionNameFromFrame(String frame) {
    var currentTrace = frame;
    var indexOfWhiteSpace = currentTrace.indexOf(' ');
    var subStr = currentTrace.substring(indexOfWhiteSpace);
    var indexOfFunction = subStr.indexOf(RegExp(r'[A-Za-z0-9]'));
    subStr = subStr.substring(indexOfFunction);
    indexOfWhiteSpace = subStr.indexOf(' ');
    return subStr.substring(0, indexOfWhiteSpace);
  }

  void _parseTrace() {
    var frames = _trace.toString().split("\n");
    if (frames.isNotEmpty && frames[0].isNotEmpty) {
      functionName = _getFunctionNameFromFrame(frames[0]);
    } else {
      functionName = "unknown";
    }

    if (frames.length > 1 && frames[1].isNotEmpty) {
      callerFunctionName = _getFunctionNameFromFrame(frames[1]);
    } else {
      callerFunctionName = functionName;
    }

    var traceString = frames[0];
    var indexOfFileName = traceString.indexOf(RegExp(r'[A-Za-z0-9_]+\.dart'));

    if (indexOfFileName != -1) {
      var fileInfo = traceString.substring(indexOfFileName);
      var listOfInfos = fileInfo.split(":");
      fileName = listOfInfos[0];
      lineNumber = listOfInfos.length > 1 ? int.tryParse(listOfInfos[1]) ?? 0 : 0;
      var columnStr = listOfInfos.length > 2 ? listOfInfos[2].replaceFirst(")", "") : "0";
      columnNumber = int.tryParse(columnStr) ?? 0;
    } else {
      fileName = "unknown.dart";
      lineNumber = 0;
      columnNumber = 0;
    }
  }
}