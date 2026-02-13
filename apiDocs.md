# Turtle WoW / Vanilla 1.12 API Reference

This document consolidates the core API primitives that are available to WoW 1.12 add-ons (which Turtle WoW is built on) along with Turtle-specific nuances observed by the community. Use it as a quick reference while building `AuctionCheck`.

## AddOn Packaging Basics
- AddOns live in `Interface\\AddOns\\<AddonName>`. Turtle WoW follows the exact vanilla folder layout.
- Each AddOn must provide a `.toc` file declaring interface version `11200`, the title, saved variables, and file load order.
- Lua files execute top-to-bottom during login. XML files describe frames and widgets and can call back into Lua via scripts such as `OnLoad`, `OnShow`, `OnEvent`.
- Saved variables declared in the `.toc` file are persisted per account (`SavedVariables`) or per character (`SavedVariablesPerCharacter`).
- Turtle WoW exposes the same FrameXML base files as retail vanilla (e.g., `Interface\\FrameXML\\UIParent.xml`). Inspect them to understand default widget templates and inheritable frames.

## Event Lifecycle
- Register events with `frame:RegisterEvent("EVENT_NAME")` and handle them in `frame:SetScript("OnEvent", handler)`.
- **Key login events:** `ADDON_LOADED`, `VARIABLES_LOADED`, `PLAYER_LOGIN`, `PLAYER_ENTERING_WORLD`.
- **Auction-related:** `AUCTION_HOUSE_SHOW`, `AUCTION_HOUSE_CLOSED`, `AUCTION_ITEM_LIST_UPDATE`, `AUCTION_BIDDER_LIST_UPDATE`, `AUCTION_OWNED_LIST_UPDATE`, `AUCTION_MULTISELL_START`, `AUCTION_MULTISELL_UPDATE`, `AUCTION_MULTISELL_FAILURE`, `NEW_AUCTION_UPDATE`.
- **Economic events:** `BAG_UPDATE`, `BAG_UPDATE_DELAYED`, `PLAYER_MONEY`, `CHAT_MSG_SYSTEM` (for auction errors), `MAIL_INBOX_UPDATE`, `MAIL_SHOW`.
- **Turtle WoW extras:** Turtle occasionally fires the custom `TW_EVENT` payload for seasonal activities. Guard handlers with `if event == "TW_EVENT" then` to avoid Lua errors on realms that do not emit it.

## UI Objects & FrameXML Helpers
- `CreateFrame("Frame", name, parent)` constructs frames. Supported types: `Frame`, `Button`, `Slider`, `StatusBar`, `GameTooltip`, `EditBox`, etc.
- Use templates defined in FrameXML via `CreateFrame("Frame", name, parent, "OptionsButtonTemplate")` or XML `<Button inherits="OptionsButtonTemplate">`.
- Key widget methods: `SetPoint`, `SetWidth`, `SetHeight`, `Show`, `Hide`, `RegisterEvent`, `UnregisterEvent`, `SetScript`, `HookScript`, `SetText`, `SetStatusBarColor`, `SetValue`.
- Tooltips: `GameTooltip:SetOwner`, `GameTooltip:SetAuctionItem(listType, index)`, `GameTooltip:SetHyperlink(link)`.
- `UIDropDownMenu` utilities are located in `FrameXML/UIDropDownMenu.lua` (functions like `UIDropDownMenu_Initialize`, `_AddButton`, `_SetSelectedValue`).

## Slash Commands & Chat
- Use `SLASH_<NAME>1 = "/ac"` then `SlashCmdList["<NAME>"] = handler` to register commands.
- `SendChatMessage` sends chat. `DEFAULT_CHAT_FRAME:AddMessage` prints to the player's chat frame.
- `ChatFrame_AddMessageEventFilter` lets you filter `CHAT_MSG_SYSTEM` for auction results.

## Auction House API (1.12 Client)
The following functions drive auction scanning logic:
- `CanSendAuctionQuery()` – returns `true` when the client is ready for the next `QueryAuctionItems` call. Always throttle requests (0.3s minimum).
- `QueryAuctionItems(name, minLevel, maxLevel, invTypeIndex, classIndex, subclassIndex, page, isUsable, qualityIndex, getAll)` – fires `AUCTION_ITEM_LIST_UPDATE` once data arrives. Turtle WoW respects the `getAll` flag just like vanilla (disabled when throttled).
- `GetNumAuctionItems(listType)` – `listType` is `"list"`, `"bidder"`, or `"owner"`.
- `GetAuctionItemInfo(listType, index)` – returns name, texture, count, quality, canUse, level, levelColHeader, minBid, minIncrement, buyoutPrice, bidAmount, highBidder, owner, saleStatus, itemId.
- `GetAuctionItemLink(listType, index)` – standard item hyperlink string for tooltip parsing.
- `GetAuctionItemTimeLeft(listType, index)` – values 1 (30m), 2 (2h), 3 (8h), 4 (24h+).
- `PlaceAuctionBid(listType, index, amount)` – bids on an auction.
- `StartAuction(minBid, buyoutPrice, runTime, stackSize, numStacks)` – must have a pending item via `ClickAuctionSellItemButton()` and `PickupContainerItem`.
- `CancelAuction(index)` – only works on the owner list and after `GetOwnerAuctionItems`.
- `SortAuctionItems("list", "unitprice"|"timeleft"|"seller")` – reorders the cached list client-side.

## Bag, Item & Currency Helpers
- `GetItemInfo(itemLinkOrId)` – returns name, link, quality, level, minLevel, type, subType, stackCount, equipLoc, texture, vendorPrice.
- `GetContainerItemInfo(bag, slot)` and `GetContainerItemLink` – gather stack counts for posting.
- `PickupContainerItem`, `SplitContainerItem`, `PickupMerchantItem` – manipulate inventory.
- `GetMoney()` (copper), `GetCoinTextureString(amount)` for printing.

## Timing, Updates & Throttling
- Use `C_Timer` equivalents do **not** exist in 1.12. Instead create an `OnUpdate` script and accumulate elapsed time.
- Example timer frame: `local f = CreateFrame("Frame") f:SetScript("OnUpdate", function(_, elapsed) accumulator = accumulator + elapsed end)`.
- `GetTime()` gives the UI time in seconds since login.

## Saved Variables & Persistence
- Declare saved tables in the `.toc` (e.g., `## SavedVariables: AuctionCheckDB`).
- Saved variables load after `VARIABLES_LOADED`. Always nil-check: `AuctionCheckDB = AuctionCheckDB or {}`.
- Turtle WoW stores saved variables in `_classic_era_/WTF`. File format is Lua chunk executed on login.

## Turtle WoW-Specific Notes
- Turtle WoW runs the stock 1.12 scripting engine. Most API additions are content oriented (new quests, custom spells) rather than UI primitives, so vanilla documentation remains authoritative.
- Custom server events occasionally piggy-back on `CHAT_MSG_ADDON` channels with prefixes such as `"Turtle"` or `"TWEVENT"`. Inspect payloads with `DEFAULT_CHAT_FRAME:AddMessage(prefix..":"..msg)` while debugging.
- The server exposes custom slash commands (e.g., `/turtle speed`, `/reloadui`). Avoid name collisions by picking a unique command prefix like `/acheck`.
- New currencies/items still follow the same item link format (`|cffXXXXXX|Hitem:itemId:enchant:...|h[Name]|h|r`). Use `GetItemInfo` to normalize them.
- Turtle WoW's launcher occasionally patches FrameXML. If you need authoritative documentation, extract `Art.MPQ` and `Interface.MPQ` from the Turtle client and inspect the embedded Lua/XML directly.

## Recommended Reference Sources
Even though we cannot bundle the external pages here, the following sources remain the canonical documentation for the 1.12 environment:
1. **FrameXML** shipped with the Turtle WoW client (`Interface\\FrameXML`). Every default function/event is implemented there.
2. **Wowpedia (World of Warcraft API)** – contains vanilla-era API descriptions. Search for function names like `GetAuctionItemInfo`.
3. **Wowwiki Archive (API functions)** – includes exhaustive tables for 1.12 (note: access might require enabling JavaScript/Cookies due to Cloudflare when downloading programmatically).
4. **Turtle WoW Forums / Discord** – for server-exclusive behaviors (e.g., limited-time events, addon policies). No additional UI API differences have been announced as of early 2026.

## Troubleshooting Tips
- Enable Lua error display via `/console scriptErrors 1`.
- Use `/reloadui` after editing files to reload quickly.
- When interacting with protected functions (none for auction API), ensure you are not invoking them during combat.
- Use `DEFAULT_CHAT_FRAME:AddMessage` liberally while debugging server quirks.

## Change Log Note
- `2026-02-12`: Document created locally after attempting (and failing due to Cloudflare) to fetch Wowwiki HTML automatically. Consult the sources listed above for the most up-to-date reference text.

