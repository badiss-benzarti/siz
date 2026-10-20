import 'package:siz/core/sync/sync_remote.dart';

/// A server keeping local-format rows with its own clock.
class FakeServer implements SyncRemote {
  final rows = <String, Map<String, Map<String, Object?>>>{};
  final _changedAt = <String, Map<String, DateTime>>{};
  final _deleted = <String, List<(String, DateTime)>>{};
  var _clock = DateTime.utc(2026);

  bool offline = false;
  final rejectKeys = <String>{};

  /// Runs while a row is being sent, to simulate edits made meanwhile.
  Future<void> Function(String entity, String key)? duringPush;

  DateTime _tick() => _clock = _clock.add(const Duration(seconds: 1));

  /// Writes a row as another device would have.
  void serverWrite(String entity, String key, Map<String, Object?> row) {
    (rows[entity] ??= {})[key] = Map.of(row);
    (_changedAt[entity] ??= {})[key] = _tick();
  }

  @override
  Future<void> push(
    String entity,
    String shopId,
    String key,
    Map<String, Object?>? row,
  ) async {
    if (offline) throw const SyncOffline();
    await duringPush?.call(entity, key);
    if (rejectKeys.contains(key)) throw const SyncRejected('refused');
    if (row == null) {
      rows[entity]?.remove(key);
      (_deleted[entity] ??= []).add((key, _tick()));
    } else {
      serverWrite(entity, key, row);
    }
  }

  @override
  Future<RemoteChanges> pull(
    String entity,
    String shopId,
    DateTime? since,
  ) async {
    if (offline) throw const SyncOffline();
    bool fresh(DateTime t) => since == null || t.isAfter(since);
    final times = _changedAt[entity] ?? {};
    final keys = [
      for (final MapEntry(:key, :value) in times.entries)
        if (fresh(value) && rows[entity]!.containsKey(key)) key,
    ]..sort((a, b) => times[a]!.compareTo(times[b]!));
    final deleted = [
      for (final (key, at) in _deleted[entity] ?? const <(String, DateTime)>[])
        if (fresh(at)) key,
    ];
    return RemoteChanges(
      rows: [for (final k in keys) Map.of(rows[entity]![k]!)],
      deletedKeys: deleted,
      cursor: _clock,
    );
  }
}
