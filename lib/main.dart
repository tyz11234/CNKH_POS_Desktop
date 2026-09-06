import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'db/app_database.dart';
import 'desktop_shell.dart';
import 'models/app_user.dart';
import 'screens/login_screen.dart';
import 'services/e_receipt.dart';
import 'services/lan_pairing_host.dart';
import 'services/pos_repository.dart';
import 'services/qr_storage.dart';
import 'theme/cnkh_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppDatabase.ensureFfi();
  // Desktop: allow all orientations / wide window. Mobile keep portrait.
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }
  purgeEReceiptCache();
  runApp(const CnkhPosDesktopApp());
}

class CnkhPosDesktopApp extends StatelessWidget {
  const CnkhPosDesktopApp({super.key, this.repository});
  final PosRepository? repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '黄金发宝号 POS Desktop',
      debugShowCheckedModeBanner: false,
      theme: buildCnkhTheme(),
      home: _Root(repository: repository),
    );
  }
}

class _Root extends StatefulWidget {
  const _Root({this.repository});
  final PosRepository? repository;
  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  AppUser? _user;
  final _qr = QrStorage();
  late final _repo = widget.repository ?? PosRepository();

  @override
  void initState() {
    super.initState();
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux)) {
      unawaited(
        LanPairingHost.shared(_repo).start().catchError((_) {
          // The pairing page will surface a useful error if the user opens it.
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    if (user == null) {
      return LoginScreen(repo:_repo,onLoggedIn: (u) => setState(() => _user = u));
    }
    return DesktopShell(
      user: user,
      qrStorage: _qr,
      repo: _repo,
      onLogout: () { _repo.auth.logout();setState(()=>_user=null); },
    );
  }
}
