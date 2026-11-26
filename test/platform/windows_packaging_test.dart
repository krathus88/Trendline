import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// `#define name "value"` from the installer script.
String _define(String iss, String name) =>
    RegExp('#define $name "([^"]*)"').firstMatch(iss)!.group(1)!;

/// A `VALUE "name", "value"` from the runner's version resource.
String _rcValue(String rc, String name) =>
    RegExp('VALUE "$name", "([^"]*)"').firstMatch(rc)!.group(1)!;

void main() {
  final iss = File('windows/installer/trendline.iss').readAsStringSync();
  final rc = File('windows/runner/Runner.rc').readAsStringSync();

  test('uninstalling deletes the folder the app keeps its data in', () {
    // path_provider names it after the exe's company and product names,
    // and Windows folder names ignore case.
    expect(
      _define(iss, 'DataCompany').toLowerCase(),
      _rcValue(rc, 'CompanyName').toLowerCase(),
    );
    expect(
      _define(iss, 'DataProduct').toLowerCase(),
      _rcValue(rc, 'ProductName').toLowerCase(),
    );
    expect(_define(iss, 'DataFile'), 'flutter_secure_storage.dat');
  });

  test('uninstalling deletes only the data file, never whole folders', () {
    final section = iss.substring(iss.indexOf('[UninstallDelete]'));
    expect(section, isNot(contains('filesandordirs')));
    expect(section, isNot(contains('*')));
    expect(
      section,
      contains(
        'Type: files; Name: '
        r'"{userappdata}\{#DataCompany}\{#DataProduct}\{#DataFile}"',
      ),
    );
  });

  test('the installer registers the same sign-in link as the app', () {
    final header = File('windows/runner/url_scheme.h').readAsStringSync();
    final scheme = RegExp(
      r'kUrlScheme\[\] = L"([^"]*)"',
    ).firstMatch(header)!.group(1);
    expect(_define(iss, 'UrlScheme'), scheme);
    expect(iss, contains('uninsdeletekey'));
  });

  test('installs per user, without admin rights', () {
    expect(iss, contains('PrivilegesRequired=lowest'));
  });

  test('the Windows icon holds every size from 16 to 256 px', () {
    final ico = File(
      'windows/runner/resources/app_icon.ico',
    ).readAsBytesSync().buffer.asByteData();
    expect(ico.getUint16(2, Endian.little), 1, reason: 'an icon file');
    final count = ico.getUint16(4, Endian.little);
    final sizes = [
      for (var i = 0; i < count; i++)
        switch (ico.getUint8(6 + 16 * i)) {
          0 => 256,
          final n => n,
        },
    ];
    expect(sizes, [16, 24, 32, 48, 64, 128, 256]);
  });

  test('Android has an adaptive icon on the app’s green', () {
    const res = 'android/app/src/main/res';
    expect(
      File('$res/mipmap-anydpi-v26/ic_launcher.xml').readAsStringSync(),
      allOf(contains('ic_launcher_foreground'), contains('<monochrome')),
    );
    expect(
      File('$res/values/ic_launcher_background.xml').readAsStringSync(),
      contains('#2E6F57'),
    );
    for (final dpi in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      expect(File('$res/mipmap-$dpi/ic_launcher.png').existsSync(), isTrue);
      expect(
        File('$res/mipmap-$dpi/ic_launcher_foreground.png').existsSync(),
        isTrue,
      );
    }
  });
}
