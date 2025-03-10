# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),

## [Unreleased]
 
### Added
- Add camera settings menu including optional camera orbit [GH-b588e8a](https://github.com/AnalyticalGoose/ProcTile/issues/9)
- Add serialising, saving and loading of material settings [GH-cd8734e](https://github.com/AnalyticalGoose/ProcTile/commit/cd8734e0c638facd1939f6820de727f01a93c165)
- Add support for material presets (variations of shader settings) [GH-82675c9](https://github.com/AnalyticalGoose/ProcTile/commit/82675c98a00af282d2ae5cc692433a1dac44005c)
- Add basic search functionality in the asset window [GH-d3753dc](https://github.com/AnalyticalGoose/ProcTile/commit/d3753dce171e2da80f9ea1da2234588f761316c7)
- Add a large texture preview when hovering over an asset in the selection window [GH-a4e5b69](https://github.com/AnalyticalGoose/ProcTile/commit/a4e5b69baedf8a8f25609d8c87ecb9821bb6bd29)
- Add quick-saving hotkey (CTRL+S) and snackbar confirmation message[GH-4f8a5a8](https://github.com/AnalyticalGoose/ProcTile/commit/4f8a5a80257ca6d4ceacaf4e1c2d33b8bcd485da)
- Add new materials: 
    - Castle Wall [GH-a6c6bd4](https://github.com/AnalyticalGoose/ProcTile/commit/a6c6bd4c5b74642acad7e0fa228899e553a926cc)
    - Grass Lawn [GH-ca64e20](https://github.com/AnalyticalGoose/ProcTile/commit/ca64e20654e82872868e5d6087de6f7a972f6aa1)
    - Pixel Uneven Wall [GH-503ec5d](https://github.com/AnalyticalGoose/ProcTile/commit/503ec5d7797b9ac0d2da7bf93ac0f8ab01b35d6a)
 
### Changed
- Migrate ProcTile to Godot 4.4 [GH-6cf65fa](https://github.com/AnalyticalGoose/ProcTile/commit/6cf65fac14d2ec063a3a27a007d29ca50083b416)
- Improve camera controller consistency prevent snapping on Y-axis [GH-550ca26](https://github.com/AnalyticalGoose/ProcTile/issues/8)
 
### Fixed
- Fix gradient buffers wrapping incorrectly [GH-b6e5b9d](https://github.com/AnalyticalGoose/ProcTile/issues/7)
- Fix gradient buffers sharing an instance [GH-a6c6bd4](https://github.com/AnalyticalGoose/ProcTile/commit/a6c6bd4c5b74642acad7e0fa228899e553a926cc)
- Fix numerous smaller bugs and crashes. [Commits](https://github.com/AnalyticalGoose/ProcTile/commits/main/)

 
## [0.1.0] - 2025-02-15
 
### Added
- Closed DEMO version released for testing