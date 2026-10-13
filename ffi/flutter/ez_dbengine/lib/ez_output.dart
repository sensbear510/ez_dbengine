import 'custom_trace.dart';

const bool _debug = true;

/// Global output console printer with caller function trace
void ezOutput(Object out, {bool force = false}) {
  CustomTrace trace = CustomTrace(StackTrace.current);
  var outString = "${trace.callerFunctionName} - $out";
  if (_debug || force) {
    print(outString);
  }
}
