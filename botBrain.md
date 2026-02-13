# AuctionCheck Bot Brain

## What This Addon Does
AuctionCheck is a lightweight Turtle WoW (1.12) helper that watches your auction house activity and mirrors the most recent sold, won, and returned auctions directly on the standard minimap mail icon tooltip. It also exposes slash commands to manually inspect, rescan, or clear the stored records per character.

## Core Data Flow
1. **Pattern prep on load** – When `ADDON_LOADED` fires for `AuctionCheck`, the addon builds language-aware matchers from Blizzard globals such as `ERR_AUCTION_SOLD_S`, `ERR_AUCTION_WON_S`, `AUCTION_SOLD_MAIL_SUBJECT`, etc. It falls back to keyword heuristics ("sold", "auction successful", etc.) if those strings are missing.
2. **System chat ingestion** – Every `CHAT_MSG_SYSTEM` message is checked with the prebuilt matchers. If the line indicates a sale or a won auction, `AddEntry` increments the appropriate bucket (`AuctionCheckDB.sold` or `.won`).
3. **Mailbox scanning** – When the mailbox UI opens (`MAIL_SHOW`, `MAIL_INBOX_UPDATE`), `ScanMailbox` enumerates every inbox header, classifies the subject as sold/won/returned, normalizes the item label, and rebuilds all three buckets from scratch. This keeps the tooltip in sync with what the mailbox currently shows.
4. **Tooltip rendering** – `TryHookMailFrame` overrides `MiniMapMailFrame`'s `OnEnter`/`OnLeave` scripts once per session. Hovering the mail icon now calls `ShowMailTooltip`, which prints the addon title followed by up to three lines per bucket (sold, won, returned), including stack counts.
5. **Saved variables** – Data persists per character through `AuctionCheckDB` (`SavedVariablesPerCharacter` in the `.toc`). Each bucket is a simple array of `{ item = <label>, count = <number> }` objects.

## Commands & Debug Utilities
- `/auctioncheck` – prints the three buckets in chat, respecting stack counts.
- `/auctioncheck scan` – triggers `ScanMailbox()` immediately.
- `/auctioncheck clear` – wipes all stored entries.
- `/auctioncheck debug` – echoes the localization strings currently returned by Blizzard (useful when diagnosing localization mismatches).
- `/auctioncheck debugmail` – forces the minimap hook and reports whether the tooltip handlers are attached.

## Heuristics & Edge Handling
- **Matcher safety** – All format strings are escaped before converting `%s`/`%d` tokens into Lua capture groups, preventing Lua pattern metacharacters from breaking detection.
- **Fallback keywords** – If localized strings change or return `nil`, lowercase keyword scans still classify subjects (e.g., "auction expired").
- **Throttle-aware** – The addon never sends auction queries; it relies solely on chat and mailbox APIs, making it safe for Turtle WoW's policies.
- **Count accumulation** – Multiple hits for the same item label increment a running counter so the tooltip shows "3x [Item]" rather than repeating entries.

## User-Facing Output
- **Chat** – All chat notifications are prefixed with `|cff33ff99AuctionCheck|r` for visibility.
- **Tooltip** – Uses gold/green/red color coding for sold/won/returned plus ellipses (`...`) if more rows exist than the allowed three lines.

## Lifecycle Summary
1. Register frame events (`ADDON_LOADED`, `CHAT_MSG_SYSTEM`, `MAIL_SHOW`, `MAIL_INBOX_UPDATE`, `UPDATE_PENDING_MAIL`).
2. On load: ensure saved variable structure, build patterns, and hook the minimap mail frame if it exists.
3. On system chat: update sold/won buckets immediately.
4. On mailbox visibility or updates: rescan headers and rebuild all buckets.
5. On minimap hover: display the aggregated data through the tooltip; hide when the mouse leaves.

This single-file addon therefore acts as a passive bot brain: it listens, categorizes, and summarizes your auction lifecycle without sending any automated auction commands, keeping Turtle WoW-friendly behavior while giving you instant mailbox intelligence.

