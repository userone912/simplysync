# App-ads.txt Setup Instructions for Simply Sync

## What is app-ads.txt?
App-ads.txt is a file that helps prevent unauthorized ad inventory sales by publicly declaring which ad networks can sell ads for your app.

## Step 1: Get Your AdMob Publisher ID

1. Go to [AdMob Console](https://admob.google.com)
2. Sign in with your Google account
3. Look for your Publisher ID (format: `pub-XXXXXXXXXXXXXXXX`)
4. Copy this ID for the next steps

## Step 2: Create app-ads.txt File

Create a file named `app-ads.txt` with the following content:

```
google.com, pub-YOUR_PUBLISHER_ID, DIRECT, f08c47fec0942fa0
```

**Replace `pub-YOUR_PUBLISHER_ID` with your actual Publisher ID from Step 1.**

Example:
```
google.com, pub-1234567890123456, DIRECT, f08c47fec0942fa0
```

## Step 3: Choose Hosting Option

### Option A: Own Website (Recommended)
If you have a website:
1. Upload `app-ads.txt` to your website root directory
2. Ensure it's accessible at: `https://yourdomain.com/app-ads.txt`
3. Test the URL to make sure it loads correctly

### Option B: GitHub Pages (Free)
If you don't have a website:

1. **Create GitHub Repository**:
   - Go to [GitHub](https://github.com)
   - Create a new public repository (e.g., `simplysync-ads`)

2. **Upload app-ads.txt**:
   - Upload your `app-ads.txt` file to the repository root
   - Commit the changes

3. **Enable GitHub Pages**:
   - Go to repository Settings
   - Scroll to "Pages" section
   - Select "Deploy from a branch"
   - Choose "main" branch and "/ (root)" folder
   - Click Save

4. **Access Your File**:
   - Your file will be available at: `https://USERNAME.github.io/REPO-NAME/app-ads.txt`
   - Example: `https://userone912.github.io/simplysync-ads/app-ads.txt`

### Option C: Netlify (Free)
1. Go to [Netlify](https://netlify.com)
2. Create a free account
3. Create a folder on your computer with the `app-ads.txt` file
4. Drag and drop the folder to Netlify
5. Get a free URL like: `https://yourapp.netlify.app/app-ads.txt`

## Step 4: Update App Store Listings

### Google Play Store:
1. Go to Google Play Console
2. Select your app
3. Go to "Store presence" > "Store listing"
4. Add your website URL in the "Website" field
5. Save changes

### Apple App Store:
1. Go to App Store Connect
2. Select your app
3. Go to "App Information"
4. Add your website URL in the "Marketing URL" field
5. Save changes

## Step 5: Update AndroidManifest.xml (Optional but Recommended)

Add your website URL to your AndroidManifest.xml:

```xml
<application
    android:label="Simply Sync"
    android:name="${applicationName}"
    android:icon="@mipmap/ic_launcher">
    
    <!-- Add this metadata for app-ads.txt verification -->
    <meta-data
        android:name="com.google.android.gms.ads.APP_ADS_TXT_URL"
        android:value="https://yourdomain.com/app-ads.txt" />
        
    <!-- Existing content... -->
</application>
```

## Step 6: Verify Setup

1. **Test URL**: Open your app-ads.txt URL in a browser to ensure it loads
2. **Wait for Crawling**: Google typically crawls within 24-48 hours
3. **Check AdMob**: Look for app-ads.txt status in your AdMob account

## Troubleshooting

### Common Issues:
- **File not accessible**: Ensure HTTPS and correct path
- **Wrong format**: Check for typos in Publisher ID
- **Not crawled yet**: Wait 24-48 hours after publishing

### Validation:
- Use [Google's app-ads.txt validator](https://adstxt.guru) to check your file
- Ensure the file is plain text (not HTML)
- Check that there are no extra spaces or characters

## Sample app-ads.txt Content

```
# Simply Sync App-ads.txt
# This file authorizes Google AdMob to sell ad inventory for this app
google.com, pub-YOUR_PUBLISHER_ID, DIRECT, f08c47fec0942fa0

# If you use other ad networks, add them here:
# facebook.com, YOUR_FACEBOOK_ID, DIRECT
# unity.com, YOUR_UNITY_ID, DIRECT
```

## Production Checklist

- [ ] Publisher ID obtained from AdMob
- [ ] app-ads.txt file created with correct format
- [ ] File hosted and accessible via HTTPS
- [ ] Website URL added to app store listings
- [ ] AndroidManifest.xml updated (optional)
- [ ] File validated and working
- [ ] AdMob account shows app-ads.txt status as verified

## Need Help?

If you encounter issues:
1. Check [Google AdMob Help Center](https://support.google.com/admob)
2. Validate your file format
3. Ensure proper HTTPS hosting
4. Wait for Google's crawling process (24-48 hours)