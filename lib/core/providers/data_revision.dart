import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Increases when another account on this device may have changed salon
/// data (e.g. a client joined the queue, then the owner signed in).
/// Screens showing salon data watch it so they reload.
final dataRevisionProvider = NotifierProvider<DataRevision, int>(
  DataRevision.new,
);

class DataRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}
