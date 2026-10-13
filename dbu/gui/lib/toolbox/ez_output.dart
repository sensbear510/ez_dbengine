/*
 * Copyrights (c) 2026 ezLink.io All rights reserved.
 * This source code may not be redistributed without the copyright owner's
 * written consent.
 *
 * @ Author : CHI-HSIUNG YANG
 * @ File   : ez_output.dart
 */

import 'package:flutter/foundation.dart';
import 'custom_trace.dart';

// Execution mode check
const bool _debug = !kReleaseMode;

/// Global output console printer with caller function trace
void ezOutput(Object out, {bool force = false}) {
  CustomTrace trace = CustomTrace(StackTrace.current);
  var outString = "(${trace.callerFunctionName}) - $out";
  if (_debug || force) {
    debugPrint(outString);
  }
}
