# Browser Audio Discovery

## Scope

Batch 3 asks for an off-by-default experimental browser media control while recording, starting with Chrome/Chromium feasibility. This discovery looked for supported macOS mechanisms that do not require private APIs, audio drivers, browser extensions, external services, or capture of URL, page title, transcript text, audio, clipboard contents, or browser content.

## Local Evidence

- `/Applications/Google Chrome.app` is installed on this Mac.
- `sdef /Applications/Google\ Chrome.app` shows Chrome exposes `window` and `tab` objects and an `execute` command that runs JavaScript in a tab.
- The command compiles when the JavaScript is assigned to an AppleScript variable and then passed with `execute browserTab javascript pauseScript`.
- Chrome returns error 12 unless `View > Developer > Allow JavaScript from Apple Events` is enabled.
- Chrome's local scripting dictionary exposes tab `title` and `URL` properties, but Batch 3 should not use them.
- Chrome's local scripting dictionary does not expose a native tab-muted property or command.
- `osascript -e 'tell application "System Events" to exists process "Google Chrome"'` returned `true`.
- `osascript -e 'tell application "Google Chrome" to count windows'` returned `1`, confirming Automation scripting works in the current environment.
- Safari is installed and also exposes JavaScript execution in its local scripting dictionary, but the goal starts with Chrome/Chromium feasibility and should not expand browser scope yet.

## Options Considered

### Pause HTML Media With Browser JavaScript

Mechanism:

- Detect a supported running browser by bundle identifier.
- Use AppleScript to iterate browser windows/tabs.
- Execute fixed JavaScript that only inspects and controls `audio` and `video` elements in each tab, for example finding media elements where `!paused && !ended` and calling `pause()`.
- Return only small counts or status categories, not page text, URL, title, or media metadata.

Pros:

- Uses Chrome's supported AppleScript `execute javascript` command.
- Does not require a browser extension, audio driver, private API, or Accessibility UI scripting.
- Can avoid resuming media, which prevents starting media that was already paused before Foil acted.
- Failure can be isolated and non-blocking: unsupported browser, browser not running, no windows/tabs, AppleScript error, tab script error.

Cons:

- Only affects HTMLMediaElement playback visible to page JavaScript; WebAudio-only pages may keep playing.
- Cross-origin iframes are not directly controlled from top-page JavaScript.
- Paused media stays paused after recording unless a future design explicitly adds resume semantics.
- Script execution may fail on browser-internal pages or restricted tabs.
- Chrome requires the user to allow JavaScript from Apple Events before tab JavaScript execution can pause media.

### Mute HTML Media With Browser JavaScript

Mechanism:

- Execute fixed JavaScript that sets `muted = true` on `audio` and `video` elements.

Pros:

- Potentially less disruptive than pausing for some playback.
- Uses the same supported Chrome JavaScript execution surface.

Cons:

- Reversibility is worse unless Foil records prior muted state inside each page, which adds page-state complexity.
- Restoring mute state risks unmuting media the user manually muted during recording.
- Like pause, it does not reliably cover WebAudio-only playback or cross-origin iframe media.

### Native Browser/Tab Mute

Mechanism:

- Use a native tab mute command or app-level mute control if available.

Finding:

- Chrome's local AppleScript dictionary does not expose a tab mute property or command.
- macOS does not provide a simple public per-application output mute API suitable for this app without an audio driver or private APIs.

Conclusion:

- Not recommended for this batch.

### Accessibility UI Scripting

Mechanism:

- Drive Chrome UI/menu items or keyboard shortcuts through Accessibility.

Pros:

- Might reach commands not available in Chrome's AppleScript dictionary.

Cons:

- Requires invasive UI automation/Accessibility behavior.
- Fragile across Chrome versions, localization, focus state, menu layout, and active tab context.
- More likely to surprise the user or interfere with active work.

Conclusion:

- Do not use for the initial experimental implementation.

## Recommendation

Implement an off-by-default experimental setting named `Pause browser media while recording`, scoped clearly to Chrome/Chromium. The first implementation should use Chrome AppleScript plus fixed JavaScript to pause currently playing HTML `audio`/`video` elements on recording start. It should not resume media on stop; this is the safest way to satisfy the requirement that Foil must not unexpectedly start media that was already paused before Foil acted.

The controller should be isolated behind a small protocol so unit tests can cover state transitions without launching or controlling Chrome. Recording must continue even when browser control fails.

## Required Permissions

- macOS Automation permission may be required for Foil to control Chrome with Apple Events.
- Chrome/Chromium must allow JavaScript from Apple Events for the recommended pause path to affect tabs.
- No Accessibility permission should be required for the recommended AppleScript/JavaScript path.
- No browser extension, audio driver, private API, or external service is required.

## Failure Modes To Handle

- Setting off: no browser work is attempted.
- Chrome/Chromium not installed or not running.
- Browser has no windows or no tabs.
- Apple Events/Automation permission denied.
- A tab rejects script execution, such as browser-internal pages.
- Page has no controllable HTML media.
- Page media uses WebAudio or cross-origin iframe media that top-page JavaScript cannot pause.
- Browser script execution times out or returns unexpected data.

## Diagnostic Policy

Diagnostic events may record only local status categories and counts, such as:

- `browserMediaControl: skipped disabled`
- `browserMediaControl: skipped browserNotRunning`
- `browserMediaControl: attempted browser=chrome tabs=3 paused=1 failures=1`
- `browserMediaControl: failed category=automationDenied`

Diagnostics must not include URL, page title, page text, media metadata, transcript text, raw audio, clipboard contents, API keys, or browser content.
