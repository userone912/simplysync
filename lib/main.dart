import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'services/background_sync_service.dart';
import 'services/notification_service.dart';
import 'services/settings_service.dart';
import 'bloc/sync_bloc.dart';
import 'bloc/sync_event.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize notification service first
  await NotificationService.initialize();
  
  // Request notification permissions
  await NotificationService.requestNotificationPermissions();
  
  // Initialize background sync service (includes notification setup)
  await BackgroundSyncService.initialize();
  
  // Check if this is the first run
  final isFirstRun = await SettingsService.isFirstRun();
  
  runApp(MyApp(isFirstRun: isFirstRun));
}

class MyApp extends StatelessWidget {
  final bool isFirstRun;
  
  const MyApp({super.key, required this.isFirstRun});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => SyncBloc()..add(LoadSettings()),
      child: MaterialApp(
        title: 'SimplySync',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: isFirstRun ? const OnboardingScreen() : const HomeScreen(),
      ),
    );
  }
}
