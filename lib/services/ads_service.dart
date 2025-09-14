import 'dart:io';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/foundation.dart';

class AdsService {
  static final AdsService _instance = AdsService._internal();
  factory AdsService() => _instance;
  AdsService._internal();

  bool _isInitialized = false;
  BannerAd? _homeBannerAd;
  BannerAd? _settingsBannerAd;
  
  // Dynamic Ad Unit IDs - automatically switches between test and production
  static String get _bannerAdUnitId {
    if (kDebugMode) {
      // 🧪 DEBUG MODE: Use Google's test ad unit IDs (safe for development)
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/6300978111' // Google test banner (Android)
          : 'ca-app-pub-3940256099942544/2934735716'; // Google test banner (iOS)
    } else {
      // 🚀 RELEASE MODE: Use your actual ad unit IDs (for production)
      return Platform.isAndroid
          ? 'ca-app-pub-5670463753817092/4375137236' // Your actual Android banner ad unit ID
          : 'YOUR_IOS_BANNER_AD_UNIT_ID'; // Replace with your actual iOS banner ad unit ID
    }
  }

  /// Initialize Mobile Ads SDK
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      await MobileAds.instance.initialize();
      _isInitialized = true;
      
      if (kDebugMode) {
        print('🧪 AdMob initialized in DEBUG mode - using TEST ads');
        print('📱 Platform: ${Platform.isAndroid ? "Android" : "iOS"}');
        print('🎯 Ad Unit ID: $_bannerAdUnitId');
      } else {
        print('🚀 AdMob initialized in RELEASE mode - using PRODUCTION ads');
        print('📱 Platform: ${Platform.isAndroid ? "Android" : "iOS"}');
        print('💰 Ad Unit ID: $_bannerAdUnitId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to initialize AdMob: $e');
      }
    }
  }

  /// Create and load a banner ad for the home screen
  Future<BannerAd?> createHomeBannerAd() async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      _homeBannerAd = BannerAd(
        adUnitId: _bannerAdUnitId,
        size: AdSize.banner, // 320x50
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (kDebugMode) {
              print('Home banner ad loaded successfully');
            }
          },
          onAdFailedToLoad: (ad, error) {
            if (kDebugMode) {
              print('Home banner ad failed to load: $error');
            }
            ad.dispose();
          },
          onAdOpened: (ad) {
            if (kDebugMode) {
              print('Home banner ad opened');
            }
          },
          onAdClosed: (ad) {
            if (kDebugMode) {
              print('Home banner ad closed');
            }
          },
        ),
      );

      await _homeBannerAd!.load();
      return _homeBannerAd;
    } catch (e) {
      if (kDebugMode) {
        print('Error creating home banner ad: $e');
      }
      return null;
    }
  }

  /// Create and load a banner ad for the settings screen
  Future<BannerAd?> createSettingsBannerAd() async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      _settingsBannerAd = BannerAd(
        adUnitId: _bannerAdUnitId,
        size: AdSize.banner, // 320x50
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (kDebugMode) {
              print('Settings banner ad loaded successfully');
            }
          },
          onAdFailedToLoad: (ad, error) {
            if (kDebugMode) {
              print('Settings banner ad failed to load: $error');
            }
            ad.dispose();
          },
          onAdOpened: (ad) {
            if (kDebugMode) {
              print('Settings banner ad opened');
            }
          },
          onAdClosed: (ad) {
            if (kDebugMode) {
              print('Settings banner ad closed');
            }
          },
        ),
      );

      await _settingsBannerAd!.load();
      return _settingsBannerAd;
    } catch (e) {
      if (kDebugMode) {
        print('Error creating settings banner ad: $e');
      }
      return null;
    }
  }

  /// Create a banner ad widget that can be used in any screen
  Future<BannerAd?> createBannerAd({
    AdSize size = AdSize.banner,
    String? customAdUnitId,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      final bannerAd = BannerAd(
        adUnitId: customAdUnitId ?? _bannerAdUnitId,
        size: size,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (kDebugMode) {
              print('Banner ad loaded successfully');
            }
          },
          onAdFailedToLoad: (ad, error) {
            if (kDebugMode) {
              print('Banner ad failed to load: $error');
            }
            ad.dispose();
          },
          onAdOpened: (ad) {
            if (kDebugMode) {
              print('Banner ad opened');
            }
          },
          onAdClosed: (ad) {
            if (kDebugMode) {
              print('Banner ad closed');
            }
          },
        ),
      );

      await bannerAd.load();
      return bannerAd;
    } catch (e) {
      if (kDebugMode) {
        print('Error creating banner ad: $e');
      }
      return null;
    }
  }

  /// Dispose of all ads
  void dispose() {
    _homeBannerAd?.dispose();
    _settingsBannerAd?.dispose();
    _homeBannerAd = null;
    _settingsBannerAd = null;
  }

  /// Get the current home banner ad
  BannerAd? get homeBannerAd => _homeBannerAd;

  /// Get the current settings banner ad
  BannerAd? get settingsBannerAd => _settingsBannerAd;

  /// Check if ads are initialized
  bool get isInitialized => _isInitialized;
}