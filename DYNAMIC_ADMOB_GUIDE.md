# Dynamic AdMob Configuration Guide

## 🎯 How Dynamic Ad Unit Switching Works

Your Simply Sync app now automatically switches between test and production ads based on the build mode:

### 🧪 **Debug Mode** (Development/Testing)
```bash
flutter run --debug
flutter run  # defaults to debug
```

**What happens:**
- ✅ Uses Google's **test ad unit IDs**
- ✅ Shows **test ads** (no revenue, safe for testing)
- ✅ Console logs: "🧪 AdMob initialized in DEBUG mode - using TEST ads"
- ✅ **Safe for unlimited testing** without policy violations

**Test Ad Unit IDs:**
- **Android**: `ca-app-pub-3940256099942544/6300978111`
- **iOS**: `ca-app-pub-3940256099942544/2934735716`

### 🚀 **Release Mode** (Production)
```bash
flutter build apk --release
flutter build appbundle --release
flutter build ios --release
```

**What happens:**
- ✅ Uses your **actual ad unit IDs**
- ✅ Shows **real ads** (generates revenue)
- ✅ Console logs: "🚀 AdMob initialized in RELEASE mode - using PRODUCTION ads"
- ✅ **Ready for app store deployment**

**Production Ad Unit IDs:**
- **Android**: `ca-app-pub-5670463753817092/4375137236`
- **iOS**: `YOUR_IOS_BANNER_AD_UNIT_ID` (update when you get iOS ID)

## 🔧 Technical Implementation

### Code Structure
```dart
static String get _bannerAdUnitId {
  if (kDebugMode) {
    // 🧪 DEBUG: Use test ads
    return Platform.isAndroid
        ? 'ca-app-pub-3940256099942544/6300978111' 
        : 'ca-app-pub-3940256099942544/2934735716';
  } else {
    // 🚀 RELEASE: Use production ads
    return Platform.isAndroid
        ? 'ca-app-pub-5670463753817092/4375137236'
        : 'YOUR_IOS_BANNER_AD_UNIT_ID';
  }
}
```

### Automatic Detection
- **`kDebugMode`**: Flutter's built-in constant that detects debug vs release builds
- **`Platform.isAndroid`**: Automatically detects Android vs iOS platform
- **No manual configuration needed** - everything switches automatically!

## 📱 Testing Guide

### 1. Debug Testing
```bash
flutter run --debug
```
- Look for console message: "🧪 AdMob initialized in DEBUG mode"
- Ads will show "Test Ad" labels
- Safe to click and interact with test ads

### 2. Release Testing  
```bash
flutter build apk --release
# Install the APK manually and test
```
- Look for console message: "🚀 AdMob initialized in RELEASE mode"
- Real ads will appear
- **⚠️ Don't click your own ads** (violates AdMob policy)

### 3. Console Logging
The app will print helpful debug information:
```
🧪 AdMob initialized in DEBUG mode - using TEST ads
📱 Platform: Android
🎯 Ad Unit ID: ca-app-pub-3940256099942544/6300978111
```

## 🚨 Important Notes

### ✅ **Safe Practices:**
- **Debug builds**: Click test ads freely
- **Release builds**: Don't click your own ads
- **Testing**: Use debug mode for development
- **Deployment**: Use release mode for app stores

### 🔄 **Build Commands:**
| Command | Mode | Ads Used | Safe to Click |
|---------|------|----------|---------------|
| `flutter run` | Debug | Test Ads | ✅ Yes |
| `flutter run --debug` | Debug | Test Ads | ✅ Yes |
| `flutter run --release` | Release | Real Ads | ❌ No |
| `flutter build apk` | Release | Real Ads | ❌ No |

## 🎯 Benefits of This Setup

1. **🛡️ Policy Safe**: Never accidentally use production ads during development
2. **🔄 Automatic**: No manual switching needed
3. **🧪 Test Friendly**: Unlimited testing with Google's test ads
4. **💰 Revenue Ready**: Real ads automatically appear in production
5. **🌍 Cross-Platform**: Works on both Android and iOS
6. **📊 Clear Logging**: Easy to see which mode you're in

## 📝 Quick Reference

### Check Current Mode
Look for these console messages when your app starts:
- **Debug**: "🧪 AdMob initialized in DEBUG mode - using TEST ads"
- **Release**: "🚀 AdMob initialized in RELEASE mode - using PRODUCTION ads"

### Update iOS Ad Unit ID
When you get your iOS ad unit ID, update this line in `ads_service.dart`:
```dart
: 'YOUR_IOS_BANNER_AD_UNIT_ID'; // Replace with actual iOS ID
```

Your dynamic AdMob setup is now complete and production-ready! 🎉