# Token Racing

Token Racing is a minimal macOS menu bar app for competing with friends on AI coding assistant token usage across Cursor, Claude Code, and Codex/OpenAI Codex.

The MVP is intentionally small:

- Native macOS status bar app written in Swift/AppKit/SwiftUI.
- Local-first usage collection through adapter classes.
- Visible Demo Mode for mocked leaderboard data.
- Tiny dependency-free Node sync server for handles, friend requests, invite codes, and aggregate leaderboard counts.
- No teams, payments, public profiles, badges, chat, notifications, or complex analytics.

## Run The App

Requirements:

- macOS 13+
- Xcode command line tools
- Swift 5.8+

From the repo root:

```sh
./scripts/run-app.sh
```

The app builds to `.build/app/Token Racing.app`, runs as an accessory process, and appears in the macOS menu bar. Click the `🏁` menu bar item to open the popover.

If your local Xcode/SwiftPM setup is healthy, `swift run TokenRacing` also works. The script exists because some Command Line Tools installations can compile with `swiftc` but fail inside SwiftPM when resolving the macOS platform path.

To build the `.app` bundle without launching it:

```sh
./scripts/build-app.sh
```

## Landing Page

The simple one-page site lives in `site/index.html`.

Create the downloadable Mac app zip used by the landing page:

```sh
./scripts/package-download.sh
```

Then open `site/index.html` in a browser. The download button points to `site/downloads/Token-Racing.zip`.

## Run The Sync Backend

The backend is optional for local/demo use, but required for handles, friend requests, invite codes, and multi-user leaderboard sync.

```sh
cd backend
npm start
```

It listens on `http://127.0.0.1:8787` by default. The app uses that URL unless changed in Settings.

The backend stores data in `backend/token-racing-db.json`. Override with:

```sh
TOKEN_RACING_DB=/path/to/token-racing-db.json npm start
```

Run the backend smoke test:

```sh
cd backend
npm test
```

## Privacy Model

Raw usage data and secrets must never leave the user's machine.

Local only:

- API keys, stored only in macOS Keychain.
- Raw logs and usage files.
- Prompts and completions.
- Source code and file names.
- Model names.
- Any local assistant configuration.

Synced to backend:

- User handle.
- Invite code.
- Friend graph and friend request status.
- Aggregate token counts by app and timeframe.

The Swift app uses `KeychainStore` for API keys. The Cursor adapter can use a Cursor Admin API key, but the key never syncs to the backend.

## Data Model

Core app models live in `Sources/TokenRacing/Models.swift`:

- `UserProfile`: local user id, handle, invite code.
- `Friend`: handle, status, direction.
- `TokenUsageEvent`: local event with app, timestamp, token count, source description.
- `TokenAggregate`: app/timeframe aggregate used for sync.
- `LeaderboardRow`: ranked display row with total tokens and app breakdown.

Local state is stored in:

```text
~/Library/Application Support/Token Racing/state.json
```

## Usage Source Detection

All adapters implement the same interface in `Sources/TokenRacing/UsageAdapter.swift`:

```swift
func detectAvailability() async -> AdapterAvailability
func fetchUsageSince(date: Date) async throws -> [TokenUsageEvent]
func explainDataSource() -> String
```

### Cursor

Detected paths:

- `~/Library/Application Support/Cursor/User/globalStorage`
- `~/Library/Application Support/Cursor/logs`
- `~/.cursor`

Cursor connects through the Cursor Admin API when the user provides an Enterprise/Admin API key during onboarding, from the main popover, or in Settings. The key is stored only in macOS Keychain. Once connected, Token Racing turns off Demo Mode, polls `/teams/filtered-usage-events`, paginates through the returned usage events, and sums the exact `tokenUsage` fields locally. Personal Cursor accounts do not currently expose a normal token-usage API, so the app does not fabricate Cursor usage when no API key is connected.

### Claude Code

Detected paths:

- `~/.claude/projects`
- `~/.claude`

The adapter auto-scans local JSON/JSONL files for explicit token fields such as `input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`, `prompt_tokens`, `completion_tokens`, `reasoning_tokens`, `cached_tokens`, or `total_tokens`. No file picker or upload is required.

### Codex / OpenAI Codex

Detected paths:

- `~/.codex`
- `~/.config/openai`
- `~/Library/Application Support/OpenAI`

The adapter auto-scans `~/.codex/sessions` when present. No file picker or upload is required.

## Demo Mode

Demo Mode is enabled by default so the menu bar UI is usable immediately. Demo data is visibly labeled and is not presented as real usage.

Turn Demo Mode off in Settings to show only locally extracted token counts.

## Validate Local Extraction

The repo includes a safe fixture that contains only timestamps and token fields:

```sh
./scripts/check-usage-parser.sh
```

Expected output:

```text
events=3
total=3175
```

## Friend And Share Flow

- Pick a handle during onboarding.
- The app syncs to the hosted backend at `https://token.racing/api`.
- Share the invite code shown in the popover.
- Add a friend by handle or invite code.
- Incoming requests can be accepted or declined.
- The leaderboard only includes the current user and accepted friends.
- Today is the default timeframe, with Week and Month available in the segmented control.

## Backend API

The backend intentionally accepts only low-sensitivity aggregate data:

- `POST /users`
- `GET /friends/:userId`
- `POST /friends/request`
- `POST /friends/respond`
- `POST /usage`
- `GET /leaderboard/:userId?timeframe=Today`

It rejects no raw logs because there is no endpoint for raw logs.

### Hosted Backend Setup

The production backend is a Vercel API route backed by Supabase Postgres.

1. Create a Supabase project.
2. Run `supabase/schema.sql` in the Supabase SQL editor.
3. Add these Vercel environment variables for production:

```sh
SUPABASE_URL=https://YOUR_PROJECT.supabase.co
SUPABASE_SERVICE_ROLE_KEY=YOUR_SERVICE_ROLE_KEY
```

4. Redeploy Vercel.

The service-role key is used only inside the Vercel API route. It is never shipped in the Mac app or browser JavaScript.

## Current Limitations

- The app is packaged as an ad-hoc signed beta `.app` bundle. It is not notarized or distributed with a Developer ID installer yet, so downloaded builds may still need quarantine removal on macOS.
- Cursor exact token extraction requires a Cursor Enterprise/Admin API key. Personal Cursor accounts do not currently expose an exact token API.
- Claude Code local token logs may be approximate depending on the Claude Code version and what final usage fields are persisted.
- The usage parser only counts explicit token fields in local JSON/JSONL/log files.
- The hosted backend has no user login yet; friend access is still scoped by unguessable local UUIDs/invite codes.
- Demo friends are local-only sample rows.
