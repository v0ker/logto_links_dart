import 'package:app_links/app_links.dart';
import 'package:example/auth.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
// ignore: implementation_imports
import 'package:logto_links_dart/src/modules/id_token.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final _log = Logger();
  final AppLinks _appLinks = AppLinks();

  bool _isLoading = false;
  bool _isLoggedIn = false;
  OpenIdClaims? _idTokenClaims;

  @override
  void initState() {
    super.initState();
    _init();
    _appLinks.uriLinkStream.listen((uri) {
      _log.d('received uri: ${uri.toString()}');
      if (uri.toString().startsWith(envConfig.signInRedirectUri)) {
        _log.d('sign in redirect uri received');
        _handleSignInCallback(uri);
      } else if (envConfig.signOutRedirectUri != null &&
          uri.toString().startsWith(envConfig.signOutRedirectUri!)) {
        _log.d('sign out redirect uri received');
        _handleSignOutCallback(uri);
      }
    });
  }

  Future<void> _init() async {
    _isLoggedIn = await logtoClient.isAuthenticated;
    _idTokenClaims = await logtoClient.idTokenClaims;
    setState(() {});
  }

  Future<void> _handleSignIn() async {
    _log.d('handling sign in');
    _isLoading = true;
    setState(() {});
    await logtoClient.signIn(envConfig.signInRedirectUri);
  }

  Future<void> _handleSignOut() async {
    _log.d('handling sign out');
    _isLoading = true;
    setState(() {});
    await logtoClient.signOut(redirectUri: envConfig.signOutRedirectUri);
    if (envConfig.signOutRedirectUri != null) {
      _log.d('sign out without redirect uri');
      _isLoading = false;
      _isLoggedIn = await logtoClient.isAuthenticated;
      _idTokenClaims = await logtoClient.idTokenClaims;
      setState(() {});
    }
  }

  Future<void> _handleSignInCallback(Uri uri) async {
    _log.d('handling sign in callback');
    bool isAuthenticated = await logtoClient.isAuthenticated;
    if (isAuthenticated) {
      // do nothing
      _log.d('user is authenticated');
      return;
    }
    await logtoClient.handleSignInCallback(
      uri.toString(),
      envConfig.signInRedirectUri,
    );
    _log.d('sign in handled');
    _isLoading = false;
    _isLoggedIn = await logtoClient.isAuthenticated;
    _idTokenClaims = await logtoClient.idTokenClaims;
    setState(() {});
  }

  Future<void> _handleSignOutCallback(Uri uri) async {
    _log.d('handling sign out callback');
    _isLoading = false;
    _isLoggedIn = await logtoClient.isAuthenticated;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    Widget action =
        _isLoading
            ? _loading()
            : _isLoggedIn
            ? _loggedIn()
            : _loggedOut();
    return Column(
      children: [
        Text('isLoading: $_isLoading'),
        Text('isLoggedIn: $_isLoggedIn'),
        Text('user: ${_idTokenClaims?.subject}'),
        action,
      ],
    );
  }

  Widget _loading() {
    return const Center(child: CircularProgressIndicator());
  }

  Widget _loggedIn() {
    return Center(
      child: TextButton(
        onPressed: _handleSignOut,
        child: const Text('Sign out'),
      ),
    );
  }

  Widget _loggedOut() {
    return Center(
      child: TextButton(onPressed: _handleSignIn, child: const Text('Sign in')),
    );
  }
}
