# Privacy Policy for Sun Day

*Last updated: January 2025*

## Overview

Sun Day is designed with your privacy in mind. We believe in transparency and want you to understand exactly how your data is used.

## Data Collection and Usage

### Location Data
- **What we collect**: Your current location (latitude, longitude, altitude)
- **Why**: To fetch UV index data for your specific location
- **How it's used**: Coordinates are sent to Open-Meteo weather API to retrieve UV data
- **Storage**: Not stored; only used in real-time

### Health Data
- **What we collect**: 
  - Fitzpatrick skin type (if available in Apple Health)
  - Date of birth (to calculate age factor)
  - Vitamin D history (past 7-14 days for adaptation factor)
- **Why**: To personalize vitamin D calculations
- **How it's used**: Read from and written to Apple HealthKit
- **Storage**: Stored securely in Apple Health on your device

### User Preferences
- **What we collect**: Your selected skin type, clothing level, age (if not from Health)
- **Why**: To remember your preferences between app sessions
- **Storage**: Stored locally on your device using UserDefaults

## Third-Party Services

### Open-Meteo API
- **What we share**: Location coordinates only
- **Purpose**: Retrieve UV index and weather data
- **Their privacy**: No authentication required, no personal data collected
- **More info**: https://open-meteo.com/en/terms

### Farmsense API
- **What we share**: Current timestamp only
- **Purpose**: Display moon phase
- **Their privacy**: No authentication required, no personal data collected
- **More info**: https://www.farmsense.net/

## Data Storage

- **All data stays on your device**
- **No cloud storage or accounts**
- **No analytics or tracking**
- **No advertising identifiers**

## Permissions

### Location (Required)
Used solely to fetch UV data for your current position

### Health (Optional)
- Read: Skin type, date of birth, vitamin D history
- Write: Vitamin D intake from sun exposure

### Notifications (Optional)
Local notifications only for:
- Sunrise/sunset times
- Sun exposure warnings

## Data Sharing

**We do not:**
- Collect personal information
- Track your usage
- Share data with advertisers
- Store data on external servers
- Use analytics services

## Children's Privacy

Sun Day does not knowingly collect data from children under 13. The app is designed for general use with health calculations suitable for all ages.

## Changes to This Policy

Any updates to this privacy policy will be reflected in the app's next update with an updated "Last updated" date.

## Open Source

Sun Day is open source. You can review the entire codebase at:
https://github.com/jackjackbits/sunday

## Contact

For privacy questions or concerns:
- Create an issue on GitHub
- The app is provided as-is with no warranty

## Your Rights

You can:
- Deny location access (app will use estimated data)
- Deny health access (manually enter data)
- Delete the app to remove all local data
- Review all code since it's open source

---

This privacy policy is released into the public domain alongside the app code.