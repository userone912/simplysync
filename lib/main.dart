import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'services/background_sync_service.dart';
import 'services/notification_service.dart';
import 'services/settings_service.dart';
import 'services/translation_service.dart';
import 'services/ads_service.dart';
import 'bloc/server_config_bloc.dart';
import 'bloc/synced_folders_bloc.dart';
import 'bloc/sync_operation_bloc.dart';
import 'bloc/app_settings_bloc.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize core services
  await NotificationService.initialize();
  await BackgroundSyncService.initialize();
  await TranslationService.initialize();
  
  // Initialize AdMob
  await AdsService().initialize();
  
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
  late ServerConfigBloc _serverConfigBloc;
  late SyncedFoldersBloc _syncedFoldersBloc;
  late SyncOperationBloc _syncOperationBloc;
  late AppSettingsBloc _appSettingsBloc;
  Locale _currentLocale = TranslationService.currentLocale;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Initialize BLoCs with lazy loading
    _serverConfigBloc = ServerConfigBloc();
    _syncedFoldersBloc = SyncedFoldersBloc();
    _syncOperationBloc = SyncOperationBloc();
    _appSettingsBloc = AppSettingsBloc();
    
    // Don't load data immediately - let screens load when needed
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _serverConfigBloc.close();
    _syncedFoldersBloc.close();
    _syncOperationBloc.close();
    _appSettingsBloc.close();
    super.dispose();
  }

  void _changeLocale(Locale locale) async {
    await TranslationService.changeLocale(locale);
    setState(() {
      _currentLocale = locale;
    });
  }

  Future<String> _translate(String text) async {
    return await TranslationService.translate(text);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // When app goes to background or is paused, let background sync take over
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _syncOperationBloc.add(SwitchToBackgroundSync());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _serverConfigBloc),
        BlocProvider.value(value: _syncedFoldersBloc),
        BlocProvider.value(value: _syncOperationBloc),
        BlocProvider.value(value: _appSettingsBloc),
      ],
      child: MaterialApp(
        title: 'simplySync',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: Colors.white,
          cardTheme: CardTheme(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            color: Colors.white,
          ),
          textTheme: Theme.of(context).textTheme.apply(
            bodyColor: Colors.black87,
            displayColor: Colors.black,
          ),
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: Colors.black,
          cardTheme: CardTheme(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            color: Colors.grey[900],
          ),
          textTheme: Theme.of(context).textTheme.apply(
            bodyColor: Colors.white,
            displayColor: Colors.white,
          ),
        ),
        home: widget.isFirstRun 
          ? OnboardingScreen(
              translate: _translate,
              changeLocale: _changeLocale,
              currentLocale: _currentLocale,
            )
          : HomeScreen(
              translate: _translate,
              changeLocale: _changeLocale,
              currentLocale: _currentLocale,
            ),
      ),
    );
  }
}
