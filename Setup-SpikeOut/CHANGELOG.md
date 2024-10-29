# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
