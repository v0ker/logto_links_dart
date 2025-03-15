import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:jose/jose.dart';
import 'package:url_launcher/url_launcher.dart';

import '/src/exceptions/logto_auth_exceptions.dart';
import '/src/interfaces/logto_interfaces.dart';
import '/src/modules/id_token.dart';
import '/src/modules/logto_storage_strategy.dart';
import '/src/modules/pkce.dart';
import '/src/modules/token_storage.dart';
import '/src/utilities/constants.dart';
import '/src/utilities/utils.dart' as utils;
import 'logto_core.dart' as logto_core;

export '/src/exceptions/logto_auth_exceptions.dart';
export '/src/interfaces/logto_interfaces.dart';
export '/src/utilities/constants.dart';

enum BrowserLaunchMode { platformDefault, external }

class LogtoLinksClient {
  final LogtoConfig config;

  late PKCE _pkce;
  late String _state;

  static late TokenStorage _tokenStorage;

  // Custom [http.Client].
  // Note that you will have to call `close()` yourself when passing a [http.Client] instance.
  late final http.Client? _httpClient;

  bool _loading = false;

  int _lastSignInTime = 0;

  bool get loading => _loading;

  OidcProviderConfig? _oidcConfig;

  late final BrowserLaunchMode _launchMode;

  LogtoLinksClient({
    required this.config,
    LogtoStorageStrategy? storageProvider,
    http.Client? httpClient,
    BrowserLaunchMode? launchMode,
  }) {
    _httpClient = httpClient ?? http.Client();
    _tokenStorage = TokenStorage(storageProvider);
    _launchMode = launchMode ?? BrowserLaunchMode.platformDefault;
  }

  // Use idToken to check if the user is authenticated.
  Future<bool> get isAuthenticated async {
    return await _tokenStorage.idToken != null;
  }

  Future<String?> get idToken async {
    final token = await _tokenStorage.idToken;
    return token?.serialization;
  }

  Future<OpenIdClaims?> get idTokenClaims async {
    final token = await _tokenStorage.idToken;
    return token?.claims;
  }

  Future<OidcProviderConfig> _getOidcConfig(http.Client httpClient) async {
    if (_oidcConfig != null) {
      return _oidcConfig!;
    }

    final discoveryUri = utils.appendUriPath(
      config.endpoint,
      logto_core.discoveryPath,
    );
    _oidcConfig = await logto_core.fetchOidcConfig(httpClient, discoveryUri);

    return _oidcConfig!;
  }

  // Get the access token by resource indicator or organizationId.
  Future<AccessToken?> getAccessToken({
    String? resource,
    String? organizationId,
  }) async {
    final accessToken = await _tokenStorage.getAccessToken(
      resource: resource,
      organizationId: organizationId,
    );

    if (accessToken != null) {
      return accessToken;
    }

    final token = await _getAccessTokenByRefreshToken(
      resource: resource,
      organizationId: organizationId,
    );

    return token;
  }

  // Get the access token for the organization by organizationId.
  Future<AccessToken?> getOrganizationToken(String organizationId) async {
    if (config.scopes == null ||
        !config.scopes!.contains(
          logto_core.LogtoUserScope.organizations.value,
        )) {
      throw LogtoAuthException(
        LogtoAuthExceptions.missingScopeError,
        'organizations scope is not specified',
      );
    }

    return await getAccessToken(organizationId: organizationId);
  }

  // Fetch the access token by refresh token.
  // No need to specify the scopes for the resource, all the related scopes in the refresh token's grant list will be returned.
  Future<AccessToken?> _getAccessTokenByRefreshToken({
    String? resource,
    String? organizationId,
  }) async {
    final refreshToken = await _tokenStorage.refreshToken;

    if (refreshToken == null) {
      throw LogtoAuthException(
        LogtoAuthExceptions.authenticationError,
        'not_authenticated',
      );
    }

    final httpClient = _httpClient ?? http.Client();

    try {
      final oidcConfig = await _getOidcConfig(httpClient);

      final response = await logto_core.fetchTokenByRefreshToken(
        httpClient: httpClient,
        tokenEndPoint: oidcConfig.tokenEndpoint,
        clientId: config.appId,
        refreshToken: refreshToken,
        resource: resource,
        organizationId: organizationId,
      );

      final scopes = response.scope.split(' ');

      await _tokenStorage.setAccessToken(
        response.accessToken,
        expiresIn: response.expiresIn,
        resource: resource,
        organizationId: organizationId,
        scopes: scopes,
      );

      // renew refresh token
      if (response.refreshToken != null) {
        await _tokenStorage.setRefreshToken(response.refreshToken);
      }

      // verify and store id_token if not null
      if (response.idToken != null) {
        final idToken = IdToken.unverified(response.idToken!);
        await _verifyIdToken(idToken, oidcConfig);
        await _tokenStorage.setIdToken(idToken);
      }

      return await _tokenStorage.getAccessToken(
        resource: resource,
        organizationId: organizationId,
      );
    } finally {
      if (_httpClient == null) httpClient.close();
    }
  }

  Future<void> _verifyIdToken(
    IdToken idToken,
    OidcProviderConfig oidcConfig,
  ) async {
    final keyStore =
        JsonWebKeyStore()..addKeySetUrl(Uri.parse(oidcConfig.jwksUri));

    if (!await idToken.verify(keyStore)) {
      throw LogtoAuthException(
        LogtoAuthExceptions.idTokenValidationError,
        'invalid jws signature',
      );
    }

    final violations = idToken.claims.validate(
      issuer: Uri.parse(oidcConfig.issuer),
      clientId: config.appId,
    );

    if (violations.isNotEmpty) {
      throw LogtoAuthException(
        LogtoAuthExceptions.idTokenValidationError,
        '$violations',
      );
    }
  }

  // Clear the access token by resource indicator or organizationId.
  Future<void> clearAccessToken({String? resource, String? organizationId}) {
    return _tokenStorage.deleteAccessToken(
      resource: resource,
      organizationId: organizationId,
    );
  }

  // Sign in using the PKCE flow.
  Future<void> signIn(
    String redirectUri, {
    String? loginHint,
    String? directSignIn,
    FirstScreen? firstScreen,
    List<IdentifierType>? identifiers,
    Map<String, String>? extraParams,
    int maxAge = 10 * 6000,
  }) async {
    var now = DateTime.now().millisecondsSinceEpoch;
    if (_loading && now - _lastSignInTime < maxAge) {
      throw LogtoAuthException(
        LogtoAuthExceptions.isLoadingError,
        'Already signing in...',
      );
    }

    final httpClient = _httpClient ?? http.Client();

    try {
      _loading = true;
      _lastSignInTime = now;
      _pkce = PKCE.generate();
      _state = utils.generateRandomString();
      _tokenStorage.setIdToken(null);
      final oidcConfig = await _getOidcConfig(httpClient);

      final signInUri = logto_core.generateSignInUri(
        authorizationEndpoint: oidcConfig.authorizationEndpoint,
        clientId: config.appId,
        redirectUri: redirectUri,
        codeChallenge: _pkce.codeChallenge,
        state: _state,
        resources: config.resources,
        scopes: config.scopes,
        loginHint: loginHint,
        firstScreen: firstScreen,
        directSignIn: directSignIn,
        identifiers: identifiers,
        extraParams: extraParams,
      );

      // final redirectUriScheme = Uri.parse(redirectUri).scheme;

      final url = Uri.parse(signInUri.toString());

      final LaunchMode launchMode =
          _launchMode == BrowserLaunchMode.platformDefault
              ? LaunchMode.platformDefault
              : LaunchMode.externalApplication;

      if (!await launchUrl(url, mode: launchMode)) {
        throw Exception('Could not launch ${url.toString()}');
      }
    } finally {
      _loading = false;
      if (_httpClient == null) httpClient.close();
    }
  }

  // Handle the sign-in callback and complete the token exchange process.
  Future handleSignInCallback(String callbackUri, String redirectUri) async {
    if (await isAuthenticated) {
      throw LogtoAuthException(
        LogtoAuthExceptions.authenticationError,
        'Already signed in...',
      );
    }

    final code = logto_core.verifyAndParseCodeFromCallbackUri(
      callbackUri,
      redirectUri,
      _state,
    );

    final oidcConfig = await _getOidcConfig(_httpClient!);

    final tokenResponse = await logto_core.fetchTokenByAuthorizationCode(
      httpClient: _httpClient,
      tokenEndPoint: oidcConfig.tokenEndpoint,
      code: code,
      codeVerifier: _pkce.codeVerifier,
      clientId: config.appId,
      redirectUri: redirectUri,
    );

    final idToken = IdToken.unverified(tokenResponse.idToken);

    await _verifyIdToken(idToken, oidcConfig);

    await _tokenStorage.save(
      idToken: idToken,
      accessToken: tokenResponse.accessToken,
      refreshToken: tokenResponse.refreshToken,
      expiresIn: tokenResponse.expiresIn,
      scopes: tokenResponse.scope.split(' '),
    );
  }

  // Sign out the user.
  Future<void> signOut({String? redirectUri}) async {
    // Throw error is authentication status not found
    final idToken = await _tokenStorage.idToken;

    final httpClient = _httpClient ?? http.Client();

    if (idToken == null) {
      throw LogtoAuthException(
        LogtoAuthExceptions.authenticationError,
        'not authenticated',
      );
    }

    try {
      final oidcConfig = await _getOidcConfig(httpClient);

      // Revoke refresh token if exist
      final refreshToken = await _tokenStorage.refreshToken;

      if (refreshToken != null) {
        try {
          await logto_core.revoke(
            httpClient: httpClient,
            revocationEndpoint: oidcConfig.revocationEndpoint,
            clientId: config.appId,
            token: refreshToken,
          );
        } catch (e) {
          // Do Nothing silently revoke the token
        }
      }

      await _tokenStorage.clear();

      // Redirect to the end session endpoint it the platform is not iOS
      // iOS uses the preferEphemeral flag on the sign-in flow, it will not preserve the session.
      // For Android and Web, we need to redirect to the end session endpoint to clear the session manually.
      if (kIsWeb || !Platform.isIOS) {
        final signOutUri = logto_core.generateSignOutUri(
          endSessionEndpoint: oidcConfig.endSessionEndpoint,
          clientId: config.appId,
          postLogoutRedirectUri:
              redirectUri != null ? Uri.parse(redirectUri) : null,
        );

        // Execute the sign-out flow asynchronously, this should not block the main app to render the UI.
        final LaunchMode launchMode =
            _launchMode == BrowserLaunchMode.platformDefault
                ? LaunchMode.platformDefault
                : LaunchMode.externalApplication;

        await launchUrl(Uri.parse(signOutUri.toString()), mode: launchMode);
      }
    } finally {
      if (_httpClient == null) {
        httpClient.close();
      }
    }
  }

  // Fetch user info from the user info endpoint.
  Future<LogtoUserInfoResponse> getUserInfo() async {
    final httpClient = _httpClient ?? http.Client();

    try {
      final oidcConfig = await _getOidcConfig(httpClient);

      final accessToken = await getAccessToken();

      if (accessToken == null) {
        throw LogtoAuthException(
          LogtoAuthExceptions.authenticationError,
          'not authenticated',
        );
      }

      final userInfoResponse = await logto_core.fetchUserInfo(
        httpClient: httpClient,
        userInfoEndpoint: oidcConfig.userInfoEndpoint,
        accessToken: accessToken.token,
      );

      return userInfoResponse;
    } finally {
      if (_httpClient == null) httpClient.close();
    }
  }
}
