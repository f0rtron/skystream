import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'doh_service.dart';

final dioClientProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  // Instead of an interceptor (which mangles the URL/Host headers for HTTPS/SNI),
  // we intercept at the socket level. This intercepts socket creation right
  // before the TLS handshake, preserving the original URI host for SNI verification.
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient();
      client.maxConnectionsPerHost = 10;
      client
          .connectionFactory = (Uri uri, String? proxyHost, int? proxyPort) async {
        final host = uri.host;

        // Helper to upgrade the socket to TLS if the scheme is https
        Future<ConnectionTask<Socket>> connectWithTlsUpgrade(
          Future<ConnectionTask<Socket>> taskFuture,
        ) {
          if (uri.scheme == 'https') {
            return taskFuture.then((task) {
              return ConnectionTask.fromSocket(
                task.socket.then((socket) {
                  return SecureSocket.secure(socket, host: uri.host);
                }),
                task.cancel,
              );
            });
          }
          return taskFuture;
        }

        // Optionally skip if DoH is disabled
        if (!DohService.instance.enabled) {
          return connectWithTlsUpgrade(Socket.startConnect(host, uri.port));
        }

        final ip = await DohService.instance.resolve(host);
        if (ip != null) {
          if (kDebugMode) {
            debugPrint(
              '[IOHttpClientAdapter] Connecting $host via DoH resolved IP: $ip',
            );
          }
          // Connect to the resolved IP but preserve the original uri properties for SNI
          return connectWithTlsUpgrade(Socket.startConnect(ip, uri.port));
        }

        // Fallback to normal DNS
        return connectWithTlsUpgrade(Socket.startConnect(host, uri.port));
      };
      return client;
    },
  );

  return dio;
});
