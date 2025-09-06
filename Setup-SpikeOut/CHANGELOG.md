# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.4] - 2025-6-9

### Added

- Added a mirror download mechanism that will try to download the last Supermodel builds from the [model3emu-code-sinden fork](https://github.com/DirtBagXon/model3emu-code-sinden) for when the Supermodel homepage is down or inaccassible. This fork is usually up to date with the latest Supermodel commit and has regular builds available for all platforms.

### Changed

- Updated anti-aliasing setting prompt to recommend against enabling it, as enabling it will tank the performance on even higher-end machines.

## [1.0.3] - 2025-6-3

### Added

- Added a prompt for whether to run Supermodel at the true Model 3 framerate (~57.524Hz) or 60fps (i.e. 104,3% the original game speed, or what the default option in previous versions was)
- Added a prompt for whether to run Supermodel in Turbo Mode (120% game speed)
- Added the option to select a control setup for fightsticks/arcade sticks/fight pads

### Changed

- Disabled vertical sync in default Supermodel settings to make turbo mode work
- Added extra line breaks between printing certain prompts to improve readability when running the script
- Changed control layout example images from JPG to WebP to save a little bit of space
- Updated README.md to add headings between sections and add the fightstick layout image

## [1.0.2] - 2024-15-11

### Fixed

- Fixed crash during non-Steam shortcut creation when running the script via
Windows PowerShell as an administrator.
- Fixed crash if the file path from the Steam process couldn't be read when
restarting Steam. Now it just prints a warning instead.

## [1.0.1] - 2024-28-10

### Added

- Opening message script now shows current version number and author contact information.

### Changed

- Changed scope of VDF type bytes from global to script
- Applied formatting and PSScriptAnalyzer suggestions to script

### Fixed

- Fixed issue where if a path for executables or working directories in a shortcut
contained whitespace characters (f.e. C:/Games/Sega Emulator/Supermodel.exe), the
shortcut paths wouldn't get parsed correctly.

## [1.0.0] - 2024-21-10

### Added

- Initial version
