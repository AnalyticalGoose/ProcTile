# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),


## [0.1.2] - UNRELEASED

### Added
- Add UI rotation gizmo to view and reset camera position [GH-0681889](https://github.com/AnalyticalGoose/ProcTile/commit/0681889d27c2d53c528e9beaba9128eaee4275aa)
- Add lighting settings menu to change HDRI & Tonemapping [GH-e6ad379](https://github.com/AnalyticalGoose/ProcTile/commit/e6ad379516dea5baf81435ba935e59b076783a1d)

### Changed
- Improve Brick Wall Material to make mortar more realistic [GH-313a2f3](https://github.com/AnalyticalGoose/ProcTile/commit/313a2f39fbc86c69082b6ceab349872c5c0f9ade)
- Improve Grass Lawn Material to by adding seamless tiling [GH-2fa0c63](https://github.com/AnalyticalGoose/ProcTile/commit/2fa0c63593d12aa1d77310c417ab7ad6d7de0b13)
- Improve Hardwood Floor Material by adding tiling and UV offsets for the planks [GH-09837ca](https://github.com/AnalyticalGoose/ProcTile/commit/09837caf9b87d4e42f2935840a53c156025332e2)

### Fixed


## [0.1.1] - 2025-03-17
 
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
    - Pixel Wooden Floor [GH-e4fc37c](https://github.com/AnalyticalGoose/ProcTile/commit/e4fc37c0fa5c6e5c4b673ac64ed4fcef0efbd708)

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