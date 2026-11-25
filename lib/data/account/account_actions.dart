import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trendline/data/account/data_export.dart';
import 'package:trendline/data/providers.dart';

/// Exporting the user's data and deleting their account.
final accountActionsProvider = Provider<AccountActions>(AccountActions.new);

class AccountActions {
  const new(this._ref);

  final Ref _ref;

  /// Builds [file] from a fresh export and asks where to save it. Returns
  /// false if the user cancelled the save.
  Future<bool> export(ExportFile file, {DateTime? now}) async {
    final data = await _ref.read(accountRepositoryProvider).exportData();
    return await _ref
        .read(fileSaverProvider)
        .save(
          fileName: file.fileName(now ?? DateTime.now()),
          mimeType: file.mimeType,
          contents: file.build(data),
        );
  }

  /// Deletes the account and everything in it, then signs out, which also
  /// clears what's cached on the device.
  Future<void> deleteAccount() async {
    await _ref.read(accountRepositoryProvider).deleteAccount();
    try {
      await _ref.read(authRepositoryProvider).signOut();
    } on Object {
      // The session is already removed from the device before the server
      // is told; the server no longer knows the account anyway.
    }
  }
}
