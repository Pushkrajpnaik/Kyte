import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/member_provider.dart';
import '../screens/main_navigation_screen.dart';
import '../services/firestore_service.dart';
import '../utils/app_theme.dart';
import 'bootstrap.dart';

class KyteApp extends StatelessWidget {
  const KyteApp({super.key, required this.bootstrap});

  final AppBootstrap bootstrap;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<MemberProvider>(
      create: (_) =>
          MemberProvider(FirestoreService(demoMode: bootstrap.demoMode)),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Kyte',
        theme: AppTheme.dark(),
        home: MainNavigationScreen(bootstrap: bootstrap),
      ),
    );
  }
}
