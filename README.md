# logto_links_dart

A Flutter package that integrates Logto authentication with deep linking support for seamless sign-in and sign-out experiences in mobile applications.

This is not an **official** package, but a fork of the original [logto_dart_sdk](https://github.com/logto-io/dart).

## Features

- Handle authentication flows with Logto
- Manage sign-in and sign-out with redirect callbacks
- Deep linking support via app_links
- Track authentication state

## Installation

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  logto_links_dart: ^latest_version
```

## Getting Started

### Configuration

1. add your env config to `example/assets/.env`, refer to `example/assets/.env.example`

2. To use the package, you'll need to configure your Logto client with your application's redirect URIs.

```dart
// Configure environment
var envConfigStr = await rootBundle.loadString('assets/.env');
logtoConfig = LogtoEnvConfig.fromJson(jsonDecode(envConfigStr));

// Initialize Logto client
final logtoClient = LogtoClient(
  // Your Logto configuration
   config: logtoConfig,
);
```

### Basic Usage

The example demonstrates how to:

1. Initialize the authentication client
2. Handle deep links for sign-in and sign-out callbacks
3. Manage authentication state
4. Provide sign-in and sign-out UI

Here's a simplified usage example:

```dart
import 'package:app_links/app_links.dart';
import 'package:logto_links_dart/logto_links_dart.dart';

class MyAuthScreen extends StatefulWidget {
  @override
  State<MyAuthScreen> createState() => _MyAuthScreenState();
}

class _MyAuthScreenState extends State<MyAuthScreen> {
  final AppLinks _appLinks = AppLinks();
  bool _isLoggedIn = false;
  
  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
    _listenForDeepLinks();
  }
  
  Future<void> _checkAuthStatus() async {
    _isLoggedIn = await logtoClient.isAuthenticated;
    setState(() {});
  }
  
  void _listenForDeepLinks() {
    _appLinks.uriLinkStream.listen((uri) {
      if (uri.toString().startsWith(envConfig.signInRedirectUri)) {
        _handleSignInCallback(uri);
      } else if (uri.toString().startsWith(envConfig.signOutRedirectUri!)) {
        _handleSignOutCallback(uri);
      }
    });
  }
  
  Future<void> _signIn() async {
    await logtoClient.signIn(envConfig.signInRedirectUri);
  }
  
  Future<void> _signOut() async {
    await logtoClient.signOut(redirectUri: envConfig.signOutRedirectUri);
  }
  
  // Implementation of callback handlers...
}
```

## Deep Linking Setup

For the deep linking functionality to work, you need to configure your application to handle custom URL schemes:

refer to `app_links` plugin documentation.

### For Android

refer to `example/android/app/src/main/AndroidManifest.xml` for the manifest file.


## Example

See the `example` directory for a complete sample application.
