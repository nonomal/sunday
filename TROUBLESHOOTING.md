# Troubleshooting Assets.xcassets in Xcode

If Assets.xcassets is not visible in Xcode after running `xcodegen generate`, try these solutions:

## Solution 1: Clean and Regenerate
```bash
rm -rf Sunday.xcodeproj
xcodegen generate
```

## Solution 2: Manual Add (if needed)
1. Open Sunday.xcodeproj in Xcode
2. Right-click on the Resources folder in the project navigator
3. Select "Add Files to Sunday..."
4. Navigate to Resources/Assets.xcassets
5. Make sure "Copy items if needed" is unchecked
6. Make sure "Sunday" target is checked
7. Click "Add"

## Solution 3: Check Build Phases
1. Select the Sunday target
2. Go to Build Phases tab
3. Expand "Copy Bundle Resources"
4. Ensure Assets.xcassets is listed there
5. If not, click + and add it manually

## Why This Happens
XcodeGen sometimes has issues with asset catalogs depending on the version and how the project is structured. The configuration in project.yml should work, but occasionally manual intervention is needed.

## Permanent Fix
Once you manually add Assets.xcassets in Xcode, it should persist even when regenerating with XcodeGen, as long as the path remains the same in project.yml.