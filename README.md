# Sunday

A minimal iOS app that tracks UV exposure and calculates vitamin D intake based on your location and sun exposure.

## Features

- Real-time UV index tracking based on location (using free Open-Meteo API)
- Vitamin D calculation considering:
  - UV levels
  - Altitude adjustment (UV increases ~10% per 1000m elevation)
  - Clothing coverage (including no clothing option)
  - Skin type (Fitzpatrick scale 1-6)
  - Sun exposure duration
- HealthKit integration to save vitamin D data
- Beautiful, minimal interface that changes color based on time of day
- Sunrise and sunset times display
- Automatic notifications:
  - Sunrise reminder to start tracking
  - Sunset reminder to check progress
  - Safe exposure time alert based on skin type
- Single screen design for simplicity

## Setup

1. Open `Sunday.xcodeproj` in Xcode
2. Select your development team in project settings
3. Build and run on your device (HealthKit requires a physical device)
4. No API key needed - uses free Open-Meteo weather API

## Permissions Required

- Location: To determine UV levels at your position
- Health: To save vitamin D intake data
- Notifications: For sunrise/sunset reminders

## Usage

1. Allow location and health permissions when prompted
2. Toggle "In the Sun" when you're exposed to sunlight
3. Select your clothing level
4. The app will calculate and track your vitamin D intake
5. Data is automatically saved to Apple Health

## Notes

- UV data updates every 5 minutes
- Vitamin D calculations are based on scientific research but should not replace medical advice
- The app uses a simplified model for vitamin D synthesis
- HealthKit requires a physical device and proper code signing
- Clothing options include "No clothing" for maximum exposure tracking
- Background gradients adapt to real daylight patterns throughout the day