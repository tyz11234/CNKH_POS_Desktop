import 'dart:convert';
import 'package:http/http.dart' as http;

/// MyInvois API client placeholder.
/// Authentication and document endpoints are isolated here so POS UI and
/// sales workflow remain unchanged.
class MyInvoisClient {
  final String baseUrl;
  String? _accessToken;

  MyInvoisClient({required this.baseUrl});

  void setAccessToken(String token) {
    _accessToken = token;
  }

  Future<Map<String, dynamic>> submitDocument(
    Map<String, dynamic> document,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1.0/documentsubmissions'),
      headers: {
        'Content-Type': 'application/json',
        if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
      },
      body: jsonEncode(document),
    );

    return {
      'statusCode': response.statusCode,
      'body': response.body,
    };
  }
}
