import 'dart:convert';

import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

class ApiResponse {
  const ApiResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

Future<ApiResponse> sendApiRequest({
  required String method,
  required Uri uri,
  required String? token,
  required Map<String, dynamic>? body,
}) async {
  const timeout = Duration(seconds: 12);
  final client = BrowserClient();
  try {
    final request = http.Request(method, uri)
      ..headers.addAll({
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      });
    if (body != null) request.body = jsonEncode(body);
    final response = await client.send(request).timeout(timeout);
    return ApiResponse(statusCode: response.statusCode, body: await response.stream.bytesToString().timeout(timeout));
  } finally {
    client.close();
  }
}
