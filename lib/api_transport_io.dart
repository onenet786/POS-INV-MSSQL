import 'dart:convert';
import 'dart:io';

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
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await client.openUrl(method, uri).timeout(timeout);
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (token != null) request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    if (body != null) request.write(jsonEncode(body));
    final response = await request.close().timeout(timeout);
    final text = await response.transform(utf8.decoder).join().timeout(timeout);
    return ApiResponse(statusCode: response.statusCode, body: text);
  } finally {
    client.close(force: true);
  }
}
