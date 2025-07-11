# Debug Information

## UV API Response Logging

When you run the app, check the Xcode console for debug output like this:

```
=== UV API Response Debug ===
Location: 37.7749, -122.4194
Current hour: 20
Hourly UV data count: 24
UV for hour 20: 0.0
Daily max UV: 8.5
Sunrise: 2025-07-11T05:57
Sunset: 2025-07-11T20:21
=============================
Final currentUV after sunset check: 0.0
```

This will show:
- What UV value the API returns for the current hour
- The sunrise/sunset times
- The final UV value after sunset checking

## App Icon Not Showing

If the app icon doesn't show on your phone:

1. **Clean Build Folder**
   - In Xcode: Product → Clean Build Folder (⇧⌘K)
   - Delete the app from your device
   - Build and run again

2. **Verify Icon is in Build**
   - In Xcode, select your app target
   - Go to Build Phases → Copy Bundle Resources
   - Ensure "Assets.xcassets" is listed

3. **Check Build Settings**
   - Select your target
   - Build Settings → Search for "App Icon"
   - Ensure "Asset Catalog App Icon Set Name" is set to "AppIcon"

4. **If Still Not Working**
   - Open Assets.xcassets in Xcode
   - Check if AppIcon shows all the icons
   - If not visible, drag the Resources/Assets.xcassets folder into Xcode

## Current Status

- ✅ Safe time shows "--" when UV is 0
- ✅ Debug logging added to track API responses
- ✅ UV correctly shows 0 after sunset
- ✅ Track button disabled when UV is 0
- 🔧 App icon may need manual verification in Xcode