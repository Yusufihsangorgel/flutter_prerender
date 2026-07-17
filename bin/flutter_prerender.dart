import 'dart:io';

import 'package:flutter_prerender/flutter_prerender.dart';

/// Entry point for the `flutter_prerender` command.
Future<void> main(List<String> args) async {
  exitCode = await runCli(args);
}
