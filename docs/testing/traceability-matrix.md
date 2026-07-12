# Traceability Matrix

The machine-readable source of truth is `coverage-manifest.json`; `MetaCoverageTests`
enforces it. This table mirrors it for humans. `status: pending` rows are backfilled by
the named plan; Plan 4 flips `MetaCoverageTests.requireAllCovered` so no row may stay pending.

| # | Feature | Tier | Tests | Checklist | Status |
|---|---------|------|-------|-----------|--------|
| 1 | ClipboardMonitor — capture | T2 | CaptureFlowTests, MonitorConstructionTests | — | covered |
| 2 | ClipboardMonitor — readPasteboard | T1 | ReadPasteboardSkipTests, ReadPasteboardImageTests, ReadPasteboardFileTests, ReadPasteboardTextTests | — | covered |
| 3 | ClipboardMonitor — dedup/cap | T1,T2 | ClipboardMonitorTests, CaptureFlowTests, ImageHelpersTests | — | covered |
| 4 | PasteService — suppression | T1 | PasteServiceTests, SelfPasteTrackerTests | — | covered |
| 5 | PasteService — copy/paste | T1,T2 | PasteServiceTests, PasteServiceSeamTests, PasteWritePathTests | M1,M2,M7 | covered |
| 6 | HotKeyParser | T1 | HotKeyParserTests | — | covered |
| 7 | HotKeyCenter | T2 | HotKeyCenterIntegrationTests | M3,M4 | covered |
| 8 | Settings | T1,T2 | SettingsDataTests, SettingsPersistenceTests | — | pending (backfill-settings-viewmodels) |
| 9 | ClipboardListViewModel | T1 | ClipboardListViewModelTests | — | pending (backfill-settings-viewmodels) |
| 10 | CapsuleViewModel | T1 | CapsuleViewModelTests | — | pending (backfill-settings-viewmodels) |
| 11 | MenuBarService | T2,T3 | MenuBarServiceTests | M9 | pending (backfill-settings-viewmodels) |
| 12 | FrequencyCleanupService | T1 | FrequencyCleanupServiceTests | — | pending (backfill-settings-viewmodels) |
| 13 | CapsuleWindowController | T3,T4 | — | M5,M6 | pending (backfill-settings-viewmodels) |
| 14 | ColorHex | T1 | ColorHexTests | — | covered |
| 15 | App wiring / AppDelegate | T3,T4 | — | M8 | pending (backfill-settings-viewmodels) |
| 16 | Models | T1 | Mini_CapsuleTests | — | pending (backfill-settings-viewmodels) |
| 17 | UI views x9 | T3,T4 | — | M5,M6,M9 | pending (backfill-settings-viewmodels) |
| 18 | Logging facade | T1 | LogEventTests, LogFacadeTests, OSLogSinkTests, FileSinkTests, LogArchiveTests | — | covered |
