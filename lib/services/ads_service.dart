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
  
  // Test Ad Unit IDs (replace with your actual Ad Unit IDs for production)
  static String get _testBannerAdUnitId => kDebugMode
      ? (Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/6300978111' // Android test banner
          : 'ca-app-pub-3940256099942544/2934735716') // iOS test banner
      : (Platform.isAndroid
          ? 'YOUR_ANDROID_BANNER_AD_UNIT_ID' // Replace with your actual Android banner ad unit ID
          : 'YOUR_IOS_BANNER_AD_UNIT_ID');    // Replace with your actual iOS banner ad unit ID

  /// Initialize Mobile Ads SDK
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      await MobileAds.instance.initialize();
      _isInitialized = true;
      
      if (kDebugMode) {
        print('AdMob initialized successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to initialize AdMob: $e');
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
        adUnitId: _testBannerAdUnitId,
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
        adUnitId: _testBannerAdUnitId,
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
        adUnitId: customAdUnitId ?? _testBannerAdUnitId,
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