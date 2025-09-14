import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/ads_service.dart';

class BannerAdWidget extends StatefulWidget {
  final AdSize adSize;
  final String? customAdUnitId;
  final EdgeInsetsGeometry? margin;
  final bool showOnError;

  const BannerAdWidget({
    super.key,
    this.adSize = AdSize.banner,
    this.customAdUnitId,
    this.margin,
    this.showOnError = false,
  });

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadBannerAd();
  }

  Future<void> _loadBannerAd() async {
    try {
      _bannerAd = await AdsService().createBannerAd(
        size: widget.adSize,
        customAdUnitId: widget.customAdUnitId,
      );
      
      if (_bannerAd != null && mounted) {
        setState(() {
          _isLoaded = true;
          _hasError = false;
        });
      } else if (mounted) {
        setState(() {
          _hasError = true;
          _isLoaded = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoaded = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Don't show anything if ad failed to load and showOnError is false
    if (_hasError && !widget.showOnError) {
      return const SizedBox.shrink();
    }

    // Show loading indicator while ad is loading
    if (!_isLoaded && !_hasError) {
      return Container(
        margin: widget.margin,
        height: widget.adSize.height.toDouble(),
        width: widget.adSize.width.toDouble(),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    // Show error state if needed
    if (_hasError && widget.showOnError) {
      return Container(
        margin: widget.margin,
        height: widget.adSize.height.toDouble(),
        width: widget.adSize.width.toDouble(),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: const Center(
          child: Text(
            'Ad not available',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    // Show the loaded ad
    if (_isLoaded && _bannerAd != null) {
      return Container(
        margin: widget.margin,
        width: widget.adSize.width.toDouble(),
        height: widget.adSize.height.toDouble(),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: AdWidget(ad: _bannerAd!),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

/// A convenience widget for bottom banner ads that stick to the bottom of the screen
class BottomBannerAdWidget extends StatelessWidget {
  final AdSize adSize;
  final String? customAdUnitId;

  const BottomBannerAdWidget({
    super.key,
    this.adSize = AdSize.banner,
    this.customAdUnitId,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          color: Colors.white,
          child: SafeArea(
            child: BannerAdWidget(
              adSize: adSize,
              customAdUnitId: customAdUnitId,
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
          ),
        ),
      ],
    );
  }
}