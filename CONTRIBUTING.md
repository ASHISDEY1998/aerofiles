# Contributing to AeroFiles

Thank you for your interest in contributing to AeroFiles!

## Getting Started

1. **Fork and Clone**
   ```bash
   git clone https://github.com/ASHISDEY1998/aerofiles.git
   cd aerofiles
   ```

2. **Install Flutter Dependencies**
   ```bash
   flutter pub get
   ```

3. **Run Static Analysis and Tests**
   ```bash
   flutter analyze --no-fatal-infos
   flutter test
   ```

4. **Build APK**
   ```bash
   flutter build apk --split-per-abi
   ```

## Development Guidelines

- Ensure all code passes `flutter analyze` with 0 errors.
- Never commit private signing keys or sensitive configuration files (`key.properties`, `*.jks`, `*.keystore`).
- Maintain the clean, privacy-first architecture: network storage and media operations must respect local privacy and avoid unsolicited network transmissions.
- Follow the existing Cupertino / OLED dark theme design system (`AppleColors`, `AppleTheme`).
