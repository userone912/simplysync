import 'package:flutter/material.dart';
import 'package:translator/translator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui' as ui;

class TranslationService {
  static final GoogleTranslator _translator = GoogleTranslator();
  static const String _localeKey = 'app_locale';
  static const String _userOverrideKey = 'user_locale_override';
  static Locale _currentLocale = const Locale('en', 'US');
  static bool _isUserOverride = false;
  static final Map<String, String> _cache = {};

  // Supported languages with their codes
  static const List<Map<String, dynamic>> supportedLanguages = [
    {'locale': Locale('en', 'US'), 'name': 'English (US)', 'code': 'en'},
    {'locale': Locale('id', 'ID'), 'name': 'Bahasa Indonesia', 'code': 'id'},
    {'locale': Locale('es', 'ES'), 'name': 'Español (Spain)', 'code': 'es'},
    {'locale': Locale('fr', 'FR'), 'name': 'Français (France)', 'code': 'fr'},
    {'locale': Locale('de', 'DE'), 'name': 'Deutsch (Germany)', 'code': 'de'},
    {'locale': Locale('it', 'IT'), 'name': 'Italiano (Italian)', 'code': 'it'},
    {'locale': Locale('ja', 'JP'), 'name': '日本語 (Japanese)', 'code': 'ja'},
    {'locale': Locale('ko', 'KR'), 'name': '한국어 (Korean)', 'code': 'ko'},
    {'locale': Locale('hi', 'IN'), 'name': 'हिन्दी (Hindi)', 'code': 'hi'},
    {'locale': Locale('ar', 'SA'), 'name': 'العربية (Arabic)', 'code': 'ar'},
    {'locale': Locale('ru', 'RU'), 'name': 'Русский (Russian)', 'code': 'ru'},
    {'locale': Locale('pt', 'BR'), 'name': 'Português (Portuguese)', 'code': 'pt'},
  ];

  static Locale get currentLocale => _currentLocale;
  static bool get isUserOverride => _isUserOverride;

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Check if user has manually selected a language
    final userOverride = prefs.getBool(_userOverrideKey) ?? false;
    final savedLocale = prefs.getString(_localeKey);
    
    if (userOverride && savedLocale != null) {
      // Priority 1: User's manual selection (highest priority)
      final parts = savedLocale.split('_');
      if (parts.length == 2) {
        _currentLocale = Locale(parts[0], parts[1]);
        _isUserOverride = true;
      }
    } else {
      // Priority 2: Device system language (if supported)
      final deviceLocale = ui.PlatformDispatcher.instance.locale;
      final isSupported = _isLocaleSupported(deviceLocale);
      
      if (isSupported) {
        _currentLocale = _getSupportedLocaleForLanguage(deviceLocale.languageCode);
        _isUserOverride = false;
      } else {
        // Priority 3: English fallback
        _currentLocale = const Locale('en', 'US');
        _isUserOverride = false;
      }
      
      // Save the detected/fallback locale
      await _saveLocale(_currentLocale, _isUserOverride);
    }
  }

  static bool _isLocaleSupported(Locale locale) {
    return supportedLanguages.any((lang) => 
      (lang['locale'] as Locale).languageCode == locale.languageCode);
  }

  static Locale _getSupportedLocaleForLanguage(String languageCode) {
    final found = supportedLanguages.firstWhere(
      (lang) => (lang['locale'] as Locale).languageCode == languageCode,
      orElse: () => supportedLanguages[0], // Default to English
    );
    return found['locale'] as Locale;
  }

  static Future<void> changeLocale(Locale locale) async {
    _currentLocale = locale;
    _isUserOverride = true; // Mark as user override
    await _saveLocale(locale, true);
    
    // Clear cache when language changes to force retranslation
    _cache.clear();
  }

  static Future<void> resetToDeviceLanguage() async {
    final deviceLocale = ui.PlatformDispatcher.instance.locale;
    final isSupported = _isLocaleSupported(deviceLocale);
    
    if (isSupported) {
      _currentLocale = _getSupportedLocaleForLanguage(deviceLocale.languageCode);
    } else {
      _currentLocale = const Locale('en', 'US'); // English fallback
    }
    
    _isUserOverride = false;
    await _saveLocale(_currentLocale, false);
    _cache.clear();
  }

  static Future<void> _saveLocale(Locale locale, bool isUserOverride) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeKey, '${locale.languageCode}_${locale.countryCode}');
    await prefs.setBool(_userOverrideKey, isUserOverride);
  }

  static Future<String> translate(String text) async {
    // Return original text if English
    if (_currentLocale.languageCode == 'en') {
      return text;
    }

    // Check cache first
    final cacheKey = '${_currentLocale.languageCode}_$text';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    try {
      // Get language code for this locale
      final langData = supportedLanguages.firstWhere(
        (lang) => (lang['locale'] as Locale).languageCode == _currentLocale.languageCode,
        orElse: () => supportedLanguages[0],
      );
      
      final translation = await _translator.translate(
        text,
        from: 'en',
        to: langData['code'],
      );

      final translatedText = translation.text;
      _cache[cacheKey] = translatedText;
      return translatedText;
    } catch (e) {
      // Return original text if translation fails (English fallback)
      return text;
    }
  }

  static String getLanguageName(Locale locale) {
    final langData = supportedLanguages.firstWhere(
      (lang) => (lang['locale'] as Locale).languageCode == locale.languageCode,
      orElse: () => supportedLanguages[0],
    );
    return langData['name'];
  }

  static String getDeviceLanguageName() {
    final deviceLocale = ui.PlatformDispatcher.instance.locale;
    return getLanguageName(deviceLocale);
  }

  static IconData getLanguageIcon() {
    return Icons.language;
  }
}