# Save System and Front End

## Goal

Replace the single-path save action with a complete product shell: title screen, continue, new-game setup, profiles, multiple manual and autosave slots, load management, settings, safe version migrations, recovery, and campaign/free-play metadata.

## Existing foundation

`SaveSystem` currently saves one `SaveGame` resource containing clock, player economy, restaurants, job market, and citizen wealth. The HUD exposes a direct save button. This is sufficient for prototyping but cannot represent multiple companies, scenarios, cities, custom recipes, layouts, inventory, campaigns, incidents, or profile progression safely.

## Save architecture

Separate three kinds of data:

- `UserSettings`: audio, graphics, accessibility, controls, language, and gameplay presentation.
- `PlayerProfile`: company cosmetics/defaults, campaign progress, unlocks, medals/highscores, tutorial status, and profile statistics.
- `SessionSave`: exact state of one campaign scenario or free-play world.

Each session save has a small metadata header and one or more versioned state sections. Metadata includes save ID, display name, timestamp, playtime, mode, campaign/scenario, city, difficulty, game date, company summary, screenshot/thumbnail path, application version, schema version, content fingerprint, and checksum.

Use stable IDs and plain serializable data for domain state. Runtime Nodes are reconstructed from the city and state. Each manager implements `capture_state()` and `restore_state()` or a centralized serializer adapter; managers do not write files independently.

## Reliability requirements

- Atomic write: serialize to a temporary file, validate checksum/readback, rotate backup, then rename into place.
- At least one previous backup per slot and a visible recovery flow after corruption.
- Autosave rotation with configurable interval and key lifecycle points such as scenario start/result or city transition.
- Save requests are queued/coalesced so simultaneous autosave/manual save cannot overlap.
- Capture occurs at a safe simulation boundary; the clock pauses briefly or state is snapshot consistently.
- Loading resets all session-scoped managers before reconstruction and validates cross-references afterward.
- Errors never delete the last known-good save.

## Versioning and migrations

Use a root schema version plus section versions for company, economy, restaurants, recipes, staff, inventory, marketing, city, AI, government, and scenario state. Migrations are ordered pure transformations on serialized data and retain the original file until success.

Required migration path from the current save:

1. Create player company state from global economy/company name.
2. Attach owned restaurants and staff to the player company.
3. Convert fixed dishes into starter recipe references.
4. Initialize new feature sections with compatibility defaults.
5. Record current city/scenario as a legacy sandbox session.

Missing content IDs should produce placeholders, safe refunds/defaults, and a warning report where possible—not a crash.

## Front-end flow

### Title screen

Continue latest valid session, New Game, Load Game, Settings, Credits, and Quit. Continue shows city, company, game date, and timestamp.

### New game

Select profile, campaign/free play/challenge, company name/logo/color/avatar, city/scenario, difficulty, seed, rivals, and optional systems. Present scenario objectives and major rules before confirmation.

### Load game

List manual and autosaves with filters, metadata, compatibility state, thumbnail, rename, duplicate, delete confirmation, reveal backup/recover, and error details. Never hide an incompatible save without explanation.

### Pause/options

Resume, Save, Load, Settings, Restart Scenario, Return to Menu, and Quit. Destructive transitions warn about unsaved progress. The existing HUD shortcut can remain as Quick Save with clear feedback.

## Settings

- Audio buses and mute behavior.
- Resolution/window/display, quality, shadows, traffic/crowd density presets, and frame cap.
- Camera speed/edge scroll/zoom and input rebinding.
- Text scale, color-independent indicators, reduced motion, subtitles/tooltips, and pause-on-modal behavior.
- Autosave interval/count, tutorial prompts, and confirmation preferences.

Apply settings immediately where safe and retain a timed revert for display-mode changes.

## Integrations

- Campaign manager owns profile progression commits and scenario metadata.
- City packages provide compatibility IDs/fingerprints.
- Every feature plan supplies versioned state and migration defaults.
- Reports may rebuild caches from authoritative events/state if report data is missing.
- AI decisions and random generators store deterministic state or seeds.
- Screenshot thumbnail capture is optional and asynchronous after state safety is secured.

## Delivery phases

### Phase 1 — Versioned multi-slot saves

Create metadata, slot catalog, atomic writes, backups, manual/autosave rotation, current-save migration, and a developer integrity validator.

### Phase 2 — Load/pause UI

Build load/save management, quick save feedback, corruption recovery, restart/return warnings, and settings persistence.

### Phase 3 — Title and new-game flow

Add title screen, profile selection, company setup, free-play/scenario configuration, and Continue.

### Phase 4 — Campaign polish and accessibility

Add campaign progress presentation, thumbnails, full options/accessibility, content compatibility messaging, and platform/cloud hooks if desired.

## Acceptance criteria

- Multiple manual saves and rotating autosaves coexist without overwriting one another.
- Interrupted or failed writes preserve the previous valid save and offer recovery.
- Current legacy saves migrate into a playable sandbox session or fail with a precise non-destructive message.
- Loading twice in one app session leaves no duplicated signals, citizens, companies, orders, or stale city references.
- Save/load during active orders, deliveries, construction, marketing, training, and incidents resumes each exactly once.
- Profile rewards commit once and remain separate from rollback-able session state.
- Front-end flows are fully keyboard navigable and destructive actions require confirmation.

## Testing strategy

- Round-trip equality tests for every state section.
- Golden migration fixtures for every released schema version.
- Fault injection during serialize, write, checksum, rename, and restore.
- Corrupt/truncated/missing-content save recovery tests.
- Repeated new/load/menu cycles to detect stale autoload state and signal duplication.
- Large-save performance and size budgets using maximum planned companies, staff, recipes, layouts, inventory, and history.

## Risks and controls

- **Migration burden:** section versions, golden fixtures, and compatibility defaults begin before new feature state proliferates.
- **Partial snapshots:** centralized safe-boundary capture and no independent manager writes.
- **Frontend blocking gameplay work:** deliver reliable slots/load first, then visual polish.
- **Content removal:** stable IDs, fingerprints, placeholders, and explicit compatibility reports.

