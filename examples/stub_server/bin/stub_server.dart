import 'dart:io';

import 'package:args/args.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:stub_server/stub_server.dart';

/// `dart run stub_server [--port 9000]`
Future<void> main(List<String> args) async {
  final options = (ArgParser()..addOption('port', abbr: 'p', defaultsTo: '9000')).parse(args);
  final server = await io.serve(
    stubHandler(store: StubStore(demo: true)),
    InternetAddress.anyIPv4,
    int.parse(options['port'] as String),
  );
  stdout
    ..writeln('stratastax stub on http://localhost:${server.port} (contracts: platform-v1, i18n-v1 bundles)')
    ..writeln('  OIDC issuer: http://localhost:${server.port}/realms/stratastax')
    ..writeln('  users: ${stubUsers.values.map((u) => '${u.id} (${u.description})').join(', ')}')
    ..writeln(
      '  service accounts: ${stubServiceAccounts.entries.map((e) => '${e.key} (secret ${e.value.$1})').join(', ')}',
    );
}
