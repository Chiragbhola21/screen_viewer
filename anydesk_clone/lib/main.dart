import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'services/signaling_service.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SignalingService()),
      ],
      child: const AnyDeskCloneApp(),
    ),
  );
}

class AnyDeskCloneApp extends StatelessWidget {
  const AnyDeskCloneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AnyDesk Clone',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.red,
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF2D2D30),
          elevation: 0,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
