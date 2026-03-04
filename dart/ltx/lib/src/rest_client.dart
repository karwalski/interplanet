// rest_client.dart — LTX REST API client using dart:io HttpClient

import 'dart:io';
import 'dart:convert';
import 'models.dart';
import 'constants.dart';

/// Store a session plan on the server.
/// Returns the parsed response map.
Future<Map<String, dynamic>> storeSession(
  LtxPlan cfg, {
  String apiBase = kDefaultApiBase,
}) async {
  final uri = Uri.parse('$apiBase?action=session');
  final client = HttpClient();
  try {
    final request = await client.postUrl(uri);
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    final body = cfg.toJson();
    request.write(body);
    final response = await request.close();
    final respBody = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('LTX API ${response.statusCode}: $respBody');
    }
    return jsonDecode(respBody) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

/// Retrieve a stored session plan by plan ID.
/// Returns the parsed response map.
Future<Map<String, dynamic>> getSession(
  String planId, {
  String apiBase = kDefaultApiBase,
}) async {
  final uri = Uri.parse(
      '$apiBase?action=session&plan_id=${Uri.encodeComponent(planId)}');
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    final respBody = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('LTX API ${response.statusCode}: $respBody');
    }
    return jsonDecode(respBody) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

/// Download ICS content for a stored plan from the server.
/// Returns the ICS text.
Future<String> downloadIcs(
  String planId,
  Map<String, dynamic> opts, {
  String apiBase = kDefaultApiBase,
}) async {
  final uri = Uri.parse(
      '$apiBase?action=ics&plan_id=${Uri.encodeComponent(planId)}');
  final client = HttpClient();
  try {
    final request = await client.postUrl(uri);
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.write(jsonEncode({
      'start': opts['start'],
      'duration_min': opts['duration_min'],
    }));
    final response = await request.close();
    final respBody = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('LTX API ${response.statusCode}: $respBody');
    }
    return respBody;
  } finally {
    client.close();
  }
}

/// Submit session feedback.
/// Returns the parsed response map.
Future<Map<String, dynamic>> submitFeedback(
  Map<String, dynamic> payload, {
  String apiBase = kDefaultApiBase,
}) async {
  final uri = Uri.parse('$apiBase?action=feedback');
  final client = HttpClient();
  try {
    final request = await client.postUrl(uri);
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.write(jsonEncode(payload));
    final response = await request.close();
    final respBody = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('LTX API ${response.statusCode}: $respBody');
    }
    return jsonDecode(respBody) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}
