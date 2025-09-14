# AndroidManifest.xml Configuration Guide

## Overview
The AndroidManifest.xml file contains sensitive AdMob configuration and is excluded from version control for security reasons.

## Setup Instructions

### 1. Copy Template
Copy the template file to create your AndroidManifest.xml:
```bash
cp android/app/src/main/AndroidManifest.xml.template android/app/src/main/AndroidManifest.xml
```

### 2. Configure AdMob Settings

Replace the following placeholders in your AndroidManifest.xml:

#### AdMob App ID
Replace:
```xml
<meta-data
    android:name="com.google.android.gms.ads.APPLICATION_ID"
    android:value="ca-app-pub-XXXXXXXXXXXXXXXX~XXXXXXXXXX"/>
```

With your actual AdMob App ID from [AdMob Console](https://admob.google.com):
```xml
<meta-data
    android:name="com.google.android.gms.ads.APPLICATION_ID"
    android:value="ca-app-pub-1234567890123456~1234567890"/>
```

#### App-ads.txt URL
Replace:
```xml
<meta-data
    android:name="com.google.android.gms.ads.APP_ADS_TXT_URL"
    android:value="https://YOUR_USERNAME.github.io/YOUR_REPO/app-ads.txt"/>
```

With your actual GitHub Pages URL:
```xml
<meta-data
    android:name="com.google.android.gms.ads.APP_ADS_TXT_URL"
    android:value="https://userone912.github.io/simplysync-ads/app-ads.txt"/>
```

### 3. Development vs Production

#### For Development/Testing:
Use test Ad Unit IDs in your AdMob configuration:
- Android Test App ID: `ca-app-pub-3940256099942544~3347511713`

#### For Production:
- Replace with your actual AdMob App ID
- Ensure app-ads.txt is properly hosted
- Update app store listings with your website URL

### 4. Security Notes

- ✅ AndroidManifest.xml is in .gitignore
- ✅ Template file is available for new setups
- ✅ Sensitive AdMob IDs are not committed to version control

### 5. Team Setup

When setting up the project:
1. Get AdMob credentials from team lead
2. Copy and configure AndroidManifest.xml from template
3. Test with development Ad Unit IDs first
4. Switch to production IDs before release

## Important Files

- `AndroidManifest.xml` - Your configured file (not in Git)
- `AndroidManifest.xml.template` - Template for setup (in Git)
- `.gitignore` - Excludes AndroidManifest.xml from version control

## Troubleshooting

### Build Errors
If you get build errors about missing AndroidManifest.xml:
1. Ensure you copied from template
2. Check file permissions
3. Verify XML syntax is correct

### AdMob Not Working
1. Verify App ID is correct
2. Check app-ads.txt URL is accessible
3. Ensure proper permissions are set
4. Test with AdMob test IDs first