# Troubleshooting Guide

## Assets.xcassets Not Visible in Xcode

If Assets.xcassets is not visible in Xcode after running `xcodegen generate`:

### Quick Fix (One-Time Manual Add)
1. Open Sunday.xcodeproj in Xcode
2. In the project navigator, find the Resources folder (it should contain Info.plist)
3. Right-click on Resources → "Add Files to Sunday..."
4. Navigate to and select `Resources/Assets.xcassets`
5. **Important**: Uncheck "Copy items if needed" 
6. Ensure "Sunday" target is checked
7. Click "Add"

### Why This Happens
XcodeGen has a known issue with asset catalogs not always appearing in the project navigator, even though they're properly included in the build. The assets are there and will be compiled, but the folder reference might not show.

### Verification
To verify the assets are actually included:
1. Select the Sunday target
2. Go to Build Phases → Copy Bundle Resources
3. Assets.xcassets should be listed there

Once manually added, the Assets.xcassets will persist through future `xcodegen generate` commands.

## UV Index and Notifications

### UV Shows Non-Zero After Sunset
Fixed! The app now checks actual sunset times and shows UV 0 when the sun has set.

### Sunset/Sunrise Notifications Not Delivered
The app now:
- Only schedules notifications for future times
- Uses time interval triggers for better reliability
- Logs success/failure of notification scheduling

To test notifications:
1. Make sure you've granted notification permissions
2. Check Xcode console for scheduling logs
3. Notifications won't fire if the time has already passed

### Track Button Disabled
When UV is 0 (after sunset or before sunrise), the track button shows "No UV available" and is disabled.