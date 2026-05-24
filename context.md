# Context Log

## 2026-05-23

- Started from an empty workspace containing only `PLAN.md`.
- Chose XcodeGen for reproducible project generation instead of hand-maintaining a `.pbxproj`.
- Created an iOS 26 / Swift 6 SwiftUI app target named `Calendar`.
- Removed local dummy data after it became clear it misrepresented implementation status.
- Used material-backed capsules as the Liquid Glass fallback path; direct `.glassEffect` usage can be added after visual validation on iOS 26 devices.
- Verified with `xcodebuild -project Calendar.xcodeproj -scheme Calendar -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -configuration Debug build CODE_SIGNING_ALLOWED=NO`.
- Added EventKit full-access request flow and real local calendar/event loading for the visible month window.
- Replaced the fixed month window with edge-triggered month expansion so the monthly view can keep paging indefinitely in both directions.
- Wired calendar drawer visibility toggles and local calendar color overrides, and persisted those preferences across reloads with a lightweight local store.
- Added local calendar appearance settings for start-of-week, week-number display, and default writable calendar selection, with the month grid and event editor now respecting those preferences.
