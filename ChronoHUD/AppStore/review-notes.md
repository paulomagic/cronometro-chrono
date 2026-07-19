# App Review notes

CHRONO HUD is a native macOS menu bar utility with a floating timer panel. It does not require an account, network connection, subscription, purchase, or demo credentials.

## Suggested review flow

1. Launch the app and complete the short onboarding.
2. The floating HUD appears automatically; the menu bar timer icon provides the remaining controls.
3. Test Stopwatch, Countdown, and Pomodoro modes from the HUD.
4. Expand the event log to inspect timer events or export them as TXT.
5. Open History from the menu bar to inspect completed sessions and CSV/JSON export.
6. Open Settings to test compact mode, theme, accent color, transparency, completion behavior, and durations.
7. Default global shortcuts are Command-Shift-C to show/hide the HUD and Command-Shift-T to toggle click-through mode.

The app uses local notifications only for Countdown and Pomodoro completion. Notification permission is requested when a timed session first needs it.

The App Sandbox is enabled. User-selected file read/write access is used only for exports through the standard macOS save panel. All timer data and preferences are stored locally. The app collects no data and performs no tracking.

`ITSAppUsesNonExemptEncryption` is set to `false`; the app does not implement or include non-exempt encryption.
