import 'dart:io';

import 'package:args/args.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:stub_server/stub_server.dart';

/// `dart run stub_server [--port 9000]`
Future<void> main(List<String> args) async {
  final options = (ArgParser()..addOption('port', abbr: 'p', defaultsTo: '9000')).parse(args);
  final server = await io.serve(stubHandler(), InternetAddress.anyIPv4, int.parse(options['port'] as String));
  stdout
    ..writeln('stratastax stub on http://localhost:${server.port} (contract: platform-v1)')
    ..writeln('  OIDC issuer: http://localhost:${server.port}/realms/stratastax')
    ..writeln('  users: ${stubUsers.values.map((u) => '${u.id} (${u.description})').join(', ')}');
}
