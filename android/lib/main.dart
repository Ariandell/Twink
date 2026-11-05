import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'classic_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const TwinkApp());
}

class TwinkApp extends StatelessWidget {
  const TwinkApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'WordyTwink',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.black,
      colorScheme: const ColorScheme.dark(
        primary: Colors.white,
        secondary: Colors.white,
      ),
    ),
    home: const ClassicShell(),
  );
}
