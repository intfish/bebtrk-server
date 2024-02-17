import 'dart:async';
import 'dart:io';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:crdt_sync/crdt_sync_server.dart';
import 'package:postgres_crdt/postgres_crdt.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:version/version.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'db_util.dart';
import 'extensions.dart';

const maxIdleDuration = Duration(minutes: 5);
final minimumVersion = Version(1, 0, 0);
final applicationTag = 'bebtrk';

class Server {
  late final SqlCrdt _crdt;
  late final String _apiKey;

  final _connectedClients = <CrdtSync, DateTime>{};

  Future<void> serve({
    required int port,
    required String database,
    required String dbHost,
    required int dbPort,
    required String apiKey,
    String? dbUsername,
    String? dbPassword,
  }) async {
    _apiKey = apiKey;
    try {
      _crdt = await PostgresCrdt.open(
        database,
        host: dbHost,
        port: dbPort,
        username: dbUsername,
        password: dbPassword,
        sslMode: SslMode.disable,
      );
    } catch (e) {
      print('Failed to open Postgres database.');
      rethrow;
    }
    await DbUtil.createTables(_crdt);

    final router = Router()
      ..head('/alive', _alive)
      ..get('/ws', _wsHandler)
    ;

    final handler = Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(_validate)
        .addHandler(router.call);

    final server = await io.serve(handler, '0.0.0.0', port);
    print('[+] Serving at ${server.address.host}:${server.port}');
  }

  Response _alive(Request request) => Response(HttpStatus.noContent);

  Handler _validate(Handler innerHandler) => (request) {
    if (request.url.toString() == 'alive') {
      return innerHandler(request);
    }

    // Authenticate
    String? key;
    if (request.headers.containsKey('x-api-key')) {
      key = request.headers['x-api-key'];
    }
    if (request.queryParameters.containsKey('token')) {
      key = request.queryParameters['token'];
    }
    if (key == null) {
      print('[!] no api key provided');
      return Response(HttpStatus.unauthorized);
    }
    if (_apiKey != key) {
      print('[!] invalid api key');
      return Response(HttpStatus.unauthorized);
    }

    return innerHandler(request);
  };

  Future<Response> _wsHandler(Request request) async {
    final handler = webSocketHandler(
      (WebSocketChannel webSocket) {
        late CrdtSync syncClient;
        syncClient = CrdtSync.server(
          _crdt,
          webSocket,
          changesetBuilder: (
                  {exceptNodeId,
                  modifiedAfter,
                  modifiedOn,
                  onlyNodeId,
                  onlyTables}) =>
              _crdt.getChangeset(
                  onlyTables: onlyTables,
                  onlyNodeId: onlyNodeId,
                  exceptNodeId: exceptNodeId,
                  modifiedOn: modifiedOn,
                  modifiedAfter: modifiedAfter),
          validateRecord: _validateRecord,
          onConnect: (nodeId, __) {
            _refreshClient(syncClient);
            print('$nodeId: connect [${_connectedClients.length}]');
          },
          onDisconnect: (nodeId, code, reason) {
            _connectedClients.remove(syncClient);
            print('$nodeId: disconnect [${_connectedClients.length}] $code ${reason ?? ''}');
          },
          onChangesetReceived: (nodeId, recordCounts) {
            _refreshClient(syncClient);
            print('⬇️ $nodeId: ${recordCounts.entries.map((e) => '${e.key}: ${e.value}').join(', ')}');
          },
          onChangesetSent: (nodeId, recordCounts) => print(
              '⬆️ $nodeId: ${recordCounts.entries.map((e) => '${e.key}: ${e.value}').join(', ')}'),
          // verbose: true,
        );
      },
    );
    return await handler(request);
  }

  void _refreshClient(CrdtSync syncClient) {
    final now = DateTime.now();
    // Reset client's idle time
    _connectedClients[syncClient] = now;
    // Close stale connections
    _connectedClients.forEach((client, lastAccess) {
      final idleTime = now.difference(lastAccess);
      if (idleTime > maxIdleDuration) {
        print('[*] Closing idle client: (${syncClient.peerId!})');
        client.close();
      }
    });
  }

  bool _validateRecord(String table, Map<String, dynamic> record) =>
      ['events', 'profiles'].contains(table);
}

class CrdtStream {
  final _controller = StreamController<String>.broadcast();

  Stream<String> get stream => _controller.stream;

  void add(String event) => _controller.add(event);

  void close() => _controller.close();
}
