# Foil Home UX Redesign Design

Date: 2026-06-30

## Summary

Migrate Foil toward a light, sidebar-based app experience inspired by the useful structure of Wispr Flow's Home screen, while preserving Foil's own product identity and color theme. The first pass should stay conservative: reorganize existing Home, History, and Settings concepts into a clearer app shell instead of introducing new writing-system features such as Dictionary, Transforms, or Scratchpad.

The menu bar popover remains, but it becomes a compact quick-control and status surface. The main app window becomes the primary place for reviewing transcripts, recovering from paste/setup issues, and changing preferences.

## Goals

- Make Foil feel more like a real app and less like a collection of popovers.
- Use a light, app-like visual system based on Foil's existing brand colors.
- Move primary navigation to a left sidebar.
- Make Home the default command center for recording readiness, recent transcript review, and recovery actions.
- Move History into the app shell as a first-class workspace.
- Replace Settings' top tab strip with left-sidebar destinations.
- Clean up the menu bar popover styling and reduce its role to fast actions and status.

## Non-Goals

- Do not copy Wispr Flow's beige palette or visual identity.
- Do not add Dictionary, Snippets, Style, Transforms, Scratchpad, or voice-profile features in this migration.
- Do not remove the menu bar app behavior.
- Do not rewrite settings or history internals unless needed to host them in the new shell.
- Do not treat analytics, streaks, or voice-profile summaries as required Home content.

## Information Architecture

The app shell uses a persistent left sidebar with grouped destinations:

```text
Foil

Workspace
- Home
- History

Preferences
- General
- Recording
- Transcription
- Cleanup
- Paste
- Storage
- Experimental
- What's New
```

Home and History are workspace sections. Existing Settings tabs become Preferences destinations. This avoids a single "Settings" sidebar item that opens another nested top-tab interface.

Future writing-system sections may be added later, but they should not appear until the feature exists and has a clear job.

## Visual Theme

The redesign should use Foil's theme, not Wispr Flow's theme.

Foil's existing cylinder mark provides the palette anchor:

- Primary brand: deep teal.
- Secondary brand: mid teal.
- Accent: warm yellow, used sparingly.
- Canvas: system light window background or near-white.
- Surfaces: system grouped backgrounds and white cards with subtle separators.
- Status colors: green for ready/success, orange for needs attention, red for failure, secondary gray for metadata.

Implementation should prefer semantic theme tokens over scattered raw colors. A small `FoilTheme` layer can expose names such as `brandPrimary`, `brandSecondary`, `brandAccent`, `sidebarSelection`, `panelBackground`, and status colors.

Selected sidebar state should use a pale teal tint. Primary actions should use deep or mid teal. Warm yellow should be reserved for brand accents or active recording emphasis, not broad page backgrounds.

## Home

Home is the default landing screen and command center. It should answer:

- Is Foil ready to record?
- What happened recently?
- Can I recover, copy, retry, or paste the latest text?
- Is setup or provider state blocking me?

Recommended layout:

```text
Header
- Home
- state line: Ready / Recording / Transcribing / Needs setup
- primary record/status action

Main column
- current session/status card
- recent transcripts feed
- per-item actions: Copy, Paste, Retry cleanup, Retry recording if failed, Delete/More

Right rail
- setup health: Accessibility, Microphone, Provider
- queue/paste state when relevant
- light usage summary from existing data
- quick links to Recording, Cleanup, and Paste preferences
```

The first version should be recovery-oriented rather than analytics-oriented. It is more important that users can inspect what happened, fix it, and paste it than that the screen shows streaks or vanity metrics.

## History

History should become a pane inside the app shell. The existing `HistoryPopoverView` behavior should be preserved:

- Search.
- Filter by all/successful/failed.
- Copy/export.
- Paste.
- Retry failed or retryable records.
- Delete individual, filtered, old, or all records.
- Detail/edit workflow where currently supported.

The shell may provide the page title and sidebar context, so `HistoryPopoverView` should remain configurable with `showsHeader` or be split into a reusable content pane.

## Preferences

The existing Settings tabs should become sidebar destinations:

- General.
- Recording.
- Transcription.
- Cleanup.
- Paste.
- Storage.
- Experimental.
- What's New.

The existing pane content should be reused wherever possible. The main structural change is navigation: the top tab strip goes away inside the app shell.

During transition, macOS `Settings {}` can remain if needed for `Cmd-,` compatibility. Normal Foil navigation should open the app shell to the selected preference destination. `Cmd-,` may either open the shell to General or continue opening the native Settings scene until the migration is complete.

## Menu Bar Popover

The menu bar popover remains a compact quick-control/status surface.

It should include:

- Record/stop/cancel controls.
- Current status.
- Last successful transcript preview when useful.
- Retry and paste actions.
- Setup warning when action is required.
- Open Foil primary action.
- Quit and diagnostics/help actions with lower visual priority.

It should not try to host full History, full Settings, or the complete app navigation. Styling should move toward the same light Foil theme while preserving compact menu-bar ergonomics.

## Implementation Shape

Introduce a new app-shell layer and migrate existing panes into it:

```text
FoilAppShellView
- owns selected navigation item
- renders left sidebar
- renders selected content pane
- provides shared header/footer styling

FoilSidebarView
- renders Workspace and Preferences groups
- uses semantic theme tokens and stable accessibility identifiers

FoilHomeView
- uses existing AppState, TranscriptionHistory, and QueuedPasteQueue data/callbacks
- presents readiness, recent records, and recovery actions

SettingsPaneHost
- hosts existing settings pane content for the selected preference destination
- removes the top tab strip in app-shell context

HistoryPane
- hosts history content inside the shell

MenuBarView refresh
- keeps quick controls
- adds Open Foil
- lightens panel/card styling
```

The existing menu bar buttons that open History or Settings should route to the app shell destination once the shell exists.

## Rollout

Use a staged migration:

1. Add theme tokens and sidebar shell.
2. Add Home pane using existing app state and history data.
3. Move History into the shell.
4. Fan out Settings panes into sidebar destinations.
5. Update menu bar popover styling and links.
6. Keep or remove legacy windows based on what remains useful after migration.

## Verification

The strongest realistic failure mode is that the redesign looks right but breaks access to existing History or Settings functionality. Verification must therefore prove that migrated panes preserve existing workflows.

Required evidence for implementation:

- App launches and the menu bar extra still appears.
- Open Foil opens the app shell to Home.
- History opens inside the shell and supports search, filter, copy, paste, retry, delete, export, and detail workflows.
- Each preference destination shows the same controls as today's Settings tab.
- Menu bar popover still supports record, stop, cancel, retry, paste, setup recovery, and quit.
- Focused UI tests are updated or added for shell navigation, Home, History, and preference destinations.
- Existing focused tests for History and Settings either pass unchanged or are intentionally updated.
- Screenshot evidence covers the app shell Home, History, one preference pane, and the menu bar popover.
- Text labels fit at the target window size and sidebar items do not truncate unexpectedly.
- `git diff --check` is clean.

Skipped visual checks must be recorded as residual risk rather than treated as passing.

## Implementation Decisions For First Pass

- Create a new `Window("Foil", id: "main")` for the app shell. Do not replace the existing History or Settings windows until the shell is verified.
- Route normal Foil actions such as Open Foil, History, and Settings buttons to the app shell destination once that destination exists.
- Route `Cmd-,` to the app shell General pane in the completed migration. During an intermediate implementation step, it may temporarily keep using the native Settings scene only if the shell destination is not wired yet.
- Split `SettingsView` only as much as needed to reuse each existing pane inside the shell. Avoid a broad rewrite of individual settings controls.
- Keep legacy History and Settings entry points during the first implementation if they reduce migration risk, but treat the app shell as the primary user path.
