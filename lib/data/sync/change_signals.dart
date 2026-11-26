import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// "This table changed" signals from the database, so data edited on
/// another device (or by another household member) shows up without a
/// refresh.
///
/// A signal carries only a table name, on a private channel only its user
/// (or their household) can join; the app then refetches through its usual
/// policies. See the change_signals migration.
abstract interface class ChangeSignals {
  /// The names of tables as their rows change for [userId] and, when set,
  /// for the household [householdId]. Listening joins the channels;
  /// cancelling leaves them.
  Stream<String> watch(String userId, String? householdId);
}

class SupabaseChangeSignals implements ChangeSignals {
  const new(this._db);

  final SupabaseClient _db;

  @override
  Stream<String> watch(String userId, String? householdId) {
    final channels = <RealtimeChannel>[];
    late final StreamController<String> controller;
    controller = StreamController<String>(
      onListen: () {
        for (final topic in [
          'user:$userId',
          if (householdId != null) 'household:$householdId',
        ]) {
          const private = RealtimeChannelConfig(private: true);
          channels.add(
            _db
                .channel(topic, opts: private)
                .onBroadcast(
                  event: 'changed',
                  callback: (message) {
                    if (changedTable(message) case final table?) {
                      controller.add(table);
                    }
                  },
                )
                .subscribe(),
          );
        }
      },
      onCancel: () async {
        for (final c in channels) {
          await _db.removeChannel(c);
        }
        channels.clear();
      },
    );
    return controller.stream;
  }
}

/// The table a broadcast message names, or null if it doesn't name one.
/// The message is untrusted input: anything unexpected is ignored.
String? changedTable(Map<String, dynamic> message) {
  final inner = message['payload'];
  final body = inner is Map ? inner : message;
  final table = body['table'];
  return table is String && table.length <= 64 ? table : null;
}
