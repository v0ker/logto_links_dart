import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:logto_links_dart/logto_links_client.dart';

class LogtoEnvConfig {
  final String appId;
  final String endpoint;
  final String signInRedirectUri;
  final String? signOutRedirectUri;
  final String resource;
  final List<String> scopes;

  const LogtoEnvConfig({
    required this.appId,
    required this.endpoint,
    required this.signInRedirectUri,
    this.signOutRedirectUri,
    required this.resource,
    required this.scopes,
  });

  factory LogtoEnvConfig.fromJson(Map<String, dynamic> json) {
    return LogtoEnvConfig(
      appId: json['app_id'],
      endpoint: json['endpoint'],
      signInRedirectUri: json['sign_in_redirect_uri'],
      signOutRedirectUri: json['sign_out_redirect_uri'],
      resource: json['resource'],
      scopes:
          (json['scopes'] as List<dynamic>).map((e) => e as String).toList(),
    );
  }
}

late final LogtoEnvConfig envConfig;
late final LogtoLinksClient logtoClient;

Future<void> initLogtoClient() async {
  var envConfigStr = await rootBundle.loadString('assets/.env');
  envConfig = LogtoEnvConfig.fromJson(jsonDecode(envConfigStr));
  var logtoConfig = LogtoConfig(
    appId: envConfig.appId,
    endpoint: envConfig.endpoint,
    resources: [envConfig.resource],
    scopes: envConfig.scopes,
  );
  logtoClient = LogtoLinksClient(
    config: logtoConfig,
    httpClient: http.Client(), // Optional http client
    launchMode: BrowserLaunchMode.external,
  );
}
