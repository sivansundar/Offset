# Offset

Offset is a native macOS menu bar app for quickly converting times across time zones.

It supports two fast workflows:

- Convert a typed input like `9AM PT`, `3:30 PM EST`, or `tomorrow 9AM JST`
- Select text anywhere on macOS and use the Services action to convert it in place
- Select text anywhere on macOS and use the `Schedule meeting` service to create an Apple Calendar or Google Calendar draft

Offset is open source and welcomes contributions. The project is licensed under GPL-3.0.

## Preview


https://github.com/user-attachments/assets/e07b263c-731e-4700-93da-973c83c11685



## Features

- Menu bar app with live local time
- Quick natural-language time conversion
- Optional Apple Intelligence-assisted parsing for fuzzier typed phrases on supported Macs
- World clock dashboard with configurable cities
- macOS Services integration for selected text
- Lightweight tooltip presentation near the current selection
- Meeting scheduling from selected text with Apple Calendar and Google Calendar draft handoff
- Unit tests covering parsing, menu bar timing logic, and service presentation behavior

## Requirements

- macOS 13.0 or later
- Xcode 17+

The app includes visual enhancements that take advantage of newer macOS APIs when available, while still building with a macOS 13 deployment target.

## Project Structure

- `Offset/`: App source, SwiftUI views, menu bar controller, service handling, and conversion logic
- `OffsetTests/`: Unit tests for parsing, UI view model behavior, service results, and menu bar timing
- `script/build_and_run.sh`: Local build and run helper
- `Info.plist`: App configuration and Services registration

## Getting Started

Clone the repository and open the project in Xcode:

```bash
git clone https://github.com/sivansundar/Offset.git
cd Offset
open Offset.xcodeproj
```

You can also build and run from the terminal:

```bash
./script/build_and_run.sh
```

Available script modes:

- `./script/build_and_run.sh`
- `./script/build_and_run.sh --debug`
- `./script/build_and_run.sh --logs`
- `./script/build_and_run.sh --telemetry`
- `./script/build_and_run.sh --verify`

## Running Tests

Run the full unit test suite with:

```bash
xcodebuild \
  -project Offset.xcodeproj \
  -scheme Offset \
  -derivedDataPath build \
  test \
  CODE_SIGNING_ALLOWED=NO
```

## How It Works

### Quick Conversion

The converter parses common timezone abbreviations and supports:

- 12-hour times like `9AM PT`
- 24-hour times like `14:00 CET`
- Day references like `today`, `tomorrow`, `Monday`, and `next Friday`

When enabled in settings, Offset can also ask Apple's on-device model to normalize harder-to-parse typed phrases on Macs where Apple Intelligence is available.

### World Clocks

Offset stores a customizable list of world clock cities in `UserDefaults` and renders them inside the menu bar popover.

### macOS Services

Offset registers two Services actions for selected text in apps that support macOS Services:

- `What's the time here?`
- `Schedule meeting`

## Contributing

Contributions are welcome. For changes larger than a small fix, please open an issue first so we can align on scope and direction.

When contributing:

- keep changes focused
- include or update tests where relevant
- document user-facing changes
- avoid committing local environment files or build artifacts

See [CONTRIBUTING.md](CONTRIBUTING.md) for the contribution workflow.

## Release Notes

This repository contains the open source code for Offset. App Store release management, signing, and distribution will be handled separately.

## Audit Notes

Current status as of April 15, 2026:

- The app builds successfully with `xcodebuild`
- The codebase includes automated unit coverage for core conversion and menu bar behavior
- One test isolation issue was fixed so the suite can run reliably from a clean contributor checkout

Known follow-up areas before an App Store release:

- add a privacy and permissions explanation for the Services and accessibility-assisted selection flow
- add release automation, notarization, and store metadata documentation
- define trademark and branding policy for official distribution

## License

Licensed under the GPL-3.0 license. See [LICENSE](LICENSE).
