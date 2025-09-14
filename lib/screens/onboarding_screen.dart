import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/app_settings_bloc.dart';
import '../services/settings_service.dart';
import '../services/translation_service.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  final Future<String> Function(String) translate;
  final void Function(Locale) changeLocale;
  final Locale currentLocale;

  const OnboardingScreen({
    super.key,
    required this.translate,
    required this.changeLocale,
    required this.currentLocale,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.background,
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.background,
          elevation: 0,
          actions: [
            PopupMenuButton<Locale>(
              onSelected: widget.changeLocale,
              itemBuilder: (context) => TranslationService.supportedLanguages
                  .map((lang) => PopupMenuItem<Locale>(
                        value: lang['locale'],
                        child: Row(
                          children: [
                            Icon(
                              widget.currentLocale == lang['locale']
                                  ? Icons.check
                                  : Icons.language,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(lang['name']),
                          ],
                        ),
                      ))
                  .toList(),
              icon: const Icon(Icons.language),
              tooltip: widget.currentLocale.languageCode == 'en' ? 'Change Language' : 'Change Language',
            ),
          ],
        ),
        body: Center(
          child: SingleChildScrollView(
            child: BlocListener<AppSettingsBloc, AppSettingsState>(
              listener: (context, state) {
                if (state is AppSettingsLoaded && state.permissionsGranted) {
                  _completeOnboarding();
                }
              },
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.85,
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() {
                      _currentPage = index;
                    });
                  },
                  children: [
                    _buildWelcomePage(),
                    _buildPermissionsPage(),
                    _buildSetupCompletePage(),
                  ],
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: _buildBottomNavigation(),
      ),
    );
  }

  Widget _buildWelcomePage() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.sync,
                size: 100,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              FutureBuilder<String>(
                future: widget.translate('Welcome to simplySync'),
                builder: (context, snapshot) => Text(
                  snapshot.data ?? 'Welcome to simplySync',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),
              FutureBuilder<String>(
                future: widget.translate('Automatically sync your files to a remote server via SSH or FTP. Keep your important documents backed up and accessible.'),
                builder: (context, snapshot) => Text(
                  snapshot.data ?? 'Automatically sync your files to a remote server via SSH or FTP. Keep your important documents backed up and accessible.',
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              Card(
                color: Theme.of(context).colorScheme.surfaceVariant,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.schedule),
                        title: FutureBuilder<String>(
                          future: widget.translate('Scheduled Sync'),
                          builder: (context, snapshot) => Text(snapshot.data ?? 'Scheduled Sync'),
                        ),
                        subtitle: FutureBuilder<String>(
                          future: widget.translate('Automatic background synchronization'),
                          builder: (context, snapshot) => Text(snapshot.data ?? 'Automatic background synchronization'),
                        ),
                      ),
                      ListTile(
                        leading: Icon(Icons.delete_outline),
                        title: FutureBuilder<String>(
                          future: widget.translate('Auto Delete'),
                          builder: (context, snapshot) => Text(snapshot.data ?? 'Auto Delete'),
                        ),
                        subtitle: FutureBuilder<String>(
                          future: widget.translate('Optionally delete files after sync'),
                          builder: (context, snapshot) => Text(snapshot.data ?? 'Optionally delete files after sync'),
                        ),
                      ),
                      ListTile(
                        leading: Icon(Icons.security),
                        title: FutureBuilder<String>(
                          future: widget.translate('Secure Transfer'),
                          builder: (context, snapshot) => Text(snapshot.data ?? 'Secure Transfer'),
                        ),
                        subtitle: FutureBuilder<String>(
                          future: widget.translate('SSH and FTP support'),
                          builder: (context, snapshot) => Text(snapshot.data ?? 'SSH and FTP support'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionsPage() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.security,
                size: 100,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              FutureBuilder<String>(
                future: widget.translate('Permissions Required'),
                builder: (context, snapshot) => Text(
                  snapshot.data ?? 'Permissions Required',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),
              FutureBuilder<String>(
                future: widget.translate('simplySync needs access to your device storage to scan and sync files. We also need notification permission to keep you informed about sync status.'),
                builder: (context, snapshot) => Text(
                  snapshot.data ?? 'simplySync needs access to your device storage to scan and sync files. We also need notification permission to keep you informed about sync status.',
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              Card(
                color: Theme.of(context).colorScheme.surfaceVariant,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.folder),
                        title: FutureBuilder<String>(
                          future: widget.translate('Storage Access'),
                          builder: (context, snapshot) => Text(snapshot.data ?? 'Storage Access'),
                        ),
                        subtitle: FutureBuilder<String>(
                          future: widget.translate('Read and sync files from selected folders'),
                          builder: (context, snapshot) => Text(snapshot.data ?? 'Read and sync files from selected folders'),
                        ),
                      ),
                      ListTile(
                        leading: Icon(Icons.notifications),
                        title: FutureBuilder<String>(
                          future: widget.translate('Notifications'),
                          builder: (context, snapshot) => Text(snapshot.data ?? 'Notifications'),
                        ),
                        subtitle: FutureBuilder<String>(
                          future: widget.translate('Sync progress and status updates'),
                          builder: (context, snapshot) => Text(snapshot.data ?? 'Sync progress and status updates'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              BlocBuilder<AppSettingsBloc, AppSettingsState>(
                builder: (context, state) {
                  return FilledButton.icon(
                    onPressed: () {
                      context.read<AppSettingsBloc>().add(RequestPermissions());
                    },
                    icon: const Icon(Icons.check),
                    label: FutureBuilder<String>(
                      future: widget.translate('Grant Permissions'),
                      builder: (context, snapshot) => Text(snapshot.data ?? 'Grant Permissions'),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSetupCompletePage() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle,
                size: 100,
                color: Colors.green,
              ),
              const SizedBox(height: 24),
              FutureBuilder<String>(
                future: widget.translate('Setup Complete!'),
                builder: (context, snapshot) => Text(
                  snapshot.data ?? 'Setup Complete!',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),
              FutureBuilder<String>(
                future: widget.translate('You\'re all set! You can now configure your server settings and start syncing files.'),
                builder: (context, snapshot) => Text(
                  snapshot.data ?? 'You\'re all set! You can now configure your server settings and start syncing files.',
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _completeOnboarding,
                icon: const Icon(Icons.arrow_forward),
                label: FutureBuilder<String>(
                  future: widget.translate('Get Started'),
                  builder: (context, snapshot) => Text(snapshot.data ?? 'Get Started'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_currentPage > 0)
            FutureBuilder<String>(
              future: widget.translate('Back'),
              builder: (context, snapshot) {
                return TextButton(
                  onPressed: () {
                    _pageController.previousPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                  child: Text(snapshot.data ?? 'Back'),
                );
              },
            )
          else
            const SizedBox(),
          Row(
            children: List.generate(3, (index) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _currentPage == index
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline,
                ),
              );
            }),
          ),
          if (_currentPage < 2)
            FutureBuilder<String>(
              future: widget.translate('Next'),
              builder: (context, snapshot) {
                return TextButton(
                  onPressed: () {
                    _pageController.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                  child: Text(snapshot.data ?? 'Next'),
                );
              },
            )
          else
            const SizedBox(),
        ],
      ),
    );
  }

  void _completeOnboarding() async {
    await SettingsService.setFirstRunCompleted();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => HomeScreen(
            translate: widget.translate,
            changeLocale: widget.changeLocale,
            currentLocale: widget.currentLocale,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
}
