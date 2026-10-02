/// Picks the log backend at compile time.
///
/// The default is the web implementation because it compiles everywhere. Any
/// platform that provides `dart:io` (Android, iOS, desktop) gets real files.
library;

export 'log_storage_web.dart' if (dart.library.io) 'log_storage_io.dart';
