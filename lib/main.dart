import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class MyApp extends StatefulWidget {
  final bool isFirstRun;
  
  const MyApp({super.key, required this.isFirstRun});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late SyncBloc _syncBloc;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncBloc = SyncBloc();
    _syncBloc.add(LoadSettings());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncBloc.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // When app goes to background or is paused, let background sync take over
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _syncBloc.add(SwitchToBackgroundSync());
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _syncBloc,
      child: MaterialApp(
        title: 'simplySync',
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
        home: widget.isFirstRun ? const OnboardingScreen() : const HomeScreen(),
      ),
    );
  }
}
