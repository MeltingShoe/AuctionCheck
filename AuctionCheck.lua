local ADDON_NAME = "AuctionCheck"
local PREFIX = "|cff33ff99AuctionCheck|r"

local frame = CreateFrame("Frame")
local systemPatterns = {}
local subjectMatchers = {}
local subjectFallbacks = {}
local mailOnEnterHandler = nil
local mailOnLeaveHandler = nil

local function Chat(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. " " .. msg)
    end
end

local function EnsureBucket(tbl, key)
    if not tbl[key] then
        tbl[key] = {}
    end
end

local function EnsureDB()
    if not AuctionCheckDB then
        AuctionCheckDB = {}
    end

    EnsureBucket(AuctionCheckDB, "sold")
    EnsureBucket(AuctionCheckDB, "won")
    EnsureBucket(AuctionCheckDB, "returned")
end

local function EscapePattern(s)
    if not s then
        return ""
    end
    return string.gsub(s, "([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
end

local function BuildFormatPattern(fmt)
    if type(fmt) ~= "string" or fmt == "" then
        return nil
    end

    local escaped = EscapePattern(fmt)
    local pattern = string.gsub(escaped, "%%%%s", "(.+)")
    pattern = string.gsub(pattern, "%%%%d", "(%%d+)")
    return "^" .. pattern .. "$"
end

local function AddMatcher(list, fmt)
    if type(fmt) ~= "string" or fmt == "" then
        return
    end

    local matcher = {
        format = fmt,
        pattern = BuildFormatPattern(fmt),
    }
    table.insert(list, matcher)
end

local function BuildPatterns()
    systemPatterns = {
        sold = {},
        won = {},
    }

    AddMatcher(systemPatterns.sold, ERR_AUCTION_SOLD_S)
    AddMatcher(systemPatterns.won, ERR_AUCTION_WON_S)

    subjectMatchers = {
        sold = {},
        won = {},
        returned = {},
    }

    AddMatcher(subjectMatchers.sold, AUCTION_SOLD_MAIL_SUBJECT)
    AddMatcher(subjectMatchers.won, AUCTION_WON_MAIL_SUBJECT)
    AddMatcher(subjectMatchers.returned, AUCTION_EXPIRED_MAIL_SUBJECT)
    AddMatcher(subjectMatchers.returned, AUCTION_REMOVED_MAIL_SUBJECT)

    subjectFallbacks = {
        sold = { "auction successful", "sold" },
        won = { "auction won", "won" },
        returned = { "auction expired", "expired", "cancelled", "canceled", "removed" },
    }
end

local function MatchFromMatchers(msg, matchers)
    if type(msg) ~= "string" or msg == "" then
        return nil
    end

    local i
    for i = 1, table.getn(matchers) do
        local matcher = matchers[i]
        if matcher and matcher.pattern then
            local captured = string.match(msg, matcher.pattern)
            if captured then
                return captured
            end
        end
    end

    return nil
end

local function IsAuctionSystemMessage(kind, msg)
    local matchers = systemPatterns[kind]
    if not matchers then
        return false, nil
    end

    local captured = MatchFromMatchers(msg, matchers)
    if captured then
        return true, captured
    end

    local lowerMsg = string.lower(msg or "")
    if kind == "sold" then
        if string.find(lowerMsg, "your auction of", 1, 1) and string.find(lowerMsg, "sold", 1, 1) then
            local item = string.match(msg, "[Yy]our auction of%s+(.+)%s+[Hh]as sold")
            if not item then
                item = string.match(msg, "[Yy]our auction of%s+(.+)%s+[Ss]old")
            end
            return true, item
        end
    elseif kind == "won" then
        if string.find(lowerMsg, "won", 1, 1) and string.find(lowerMsg, "auction", 1, 1) then
            local item = string.match(msg, "[Yy]ou have won an auction for%s+(.+)")
            return true, item
        end
    end

    return false, nil
end

local function FindEntryByLabel(bucket, label)
    local i
    for i = 1, table.getn(bucket) do
        local entry = bucket[i]
        if entry.item == label then
            return entry
        end
    end
    return nil
end

local function AddEntry(bucket, label, amount)
    if not label or label == "" then
        label = "(unknown)"
    end

    if not amount or amount < 1 then
        amount = 1
    end

    local entry = FindEntryByLabel(bucket, label)
    if entry then
        entry.count = (entry.count or 0) + amount
    else
        table.insert(bucket, {
            item = label,
            count = amount,
        })
    end
end

local function NormalizeSubjectToItem(kind, subject)
    local matchers = subjectMatchers[kind]
    if not matchers then
        return subject
    end

    local captured = MatchFromMatchers(subject, matchers)
    if captured and captured ~= "" then
        return captured
    end

    return subject
end

local function ClassifyAuctionSubject(subject)
    if type(subject) ~= "string" or subject == "" then
        return nil
    end

    local kinds = { "sold", "won", "returned" }
    local i
    for i = 1, table.getn(kinds) do
        local kind = kinds[i]
        if MatchFromMatchers(subject, subjectMatchers[kind]) then
            return kind
        end
    end

    local lowerSubject = string.lower(subject)
    for i = 1, table.getn(kinds) do
        local kind = kinds[i]
        local words = subjectFallbacks[kind]
        local j
        for j = 1, table.getn(words) do
            if string.find(lowerSubject, words[j], 1, 1) then
                return kind
            end
        end
    end

    return nil
end

local function ScanMailbox()
    EnsureDB()

    if not GetInboxNumItems or not GetInboxHeaderInfo then
        return
    end

    local numItems = GetInboxNumItems()
    if type(numItems) ~= "number" then
        return
    end

    local sold = {}
    local won = {}
    local returned = {}

    local i
    for i = 1, numItems do
        local _, _, _, subject = GetInboxHeaderInfo(i)
        local kind = ClassifyAuctionSubject(subject)

        if kind == "sold" then
            AddEntry(sold, NormalizeSubjectToItem("sold", subject), 1)
        elseif kind == "won" then
            AddEntry(won, NormalizeSubjectToItem("won", subject), 1)
        elseif kind == "returned" then
            AddEntry(returned, NormalizeSubjectToItem("returned", subject), 1)
        end
    end

    AuctionCheckDB.sold = sold
    AuctionCheckDB.won = won
    AuctionCheckDB.returned = returned
end

local function ClearAll(reason)
    EnsureDB()
    AuctionCheckDB.sold = {}
    AuctionCheckDB.won = {}
    AuctionCheckDB.returned = {}
    if reason then
        Chat(reason)
    end
end

local function ShowBucket(title, bucket)
    local count = table.getn(bucket)
    if count == 0 then
        Chat(title .. ": none")
        return
    end

    Chat(title .. ":")
    local i
    for i = 1, count do
        local entry = bucket[i]
        Chat("  " .. (entry.count or 1) .. "x " .. (entry.item or "(unknown)"))
    end
end

local function ShowStoredData()
    EnsureDB()
    ShowBucket("AH Sold", AuctionCheckDB.sold)
    ShowBucket("AH Won", AuctionCheckDB.won)
    ShowBucket("AH Returned", AuctionCheckDB.returned)
end

local function AddTooltipSection(title, bucket, r, g, b, maxLines)
    GameTooltip:AddLine(title, r, g, b)

    local count = table.getn(bucket)
    if count == 0 then
        GameTooltip:AddLine("None", 0.7, 0.7, 0.7)
        return 1
    end

    local shown = 0
    local i
    for i = 1, count do
        local entry = bucket[i]
        GameTooltip:AddLine((entry.count or 1) .. "x " .. (entry.item or "(unknown)"), 0.9, 0.9, 0.9)
        shown = shown + 1
        if shown >= maxLines then
            break
        end
    end

    if count > shown then
        GameTooltip:AddLine("...", 0.6, 0.6, 0.6)
    end

    return shown + 1
end

local function ShowMailTooltip(owner)
    EnsureDB()

    if not owner then
        owner = MiniMapMailFrame
    end

    if not owner then
        return
    end

    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMLEFT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine("AuctionCheck")

    AddTooltipSection("AH Sold", AuctionCheckDB.sold, 1, 0.85, 0.3, 3)
    AddTooltipSection("AH Won", AuctionCheckDB.won, 0.4, 1, 0.4, 3)
    AddTooltipSection("AH Returned", AuctionCheckDB.returned, 1, 0.4, 0.4, 3)

    GameTooltip:Show()
end

local function HideMailTooltip()
    GameTooltip:Hide()
end

local function TryHookMailFrame()
    local mailFrame = MiniMapMailFrame
    if not mailFrame then
        return
    end

    if mailFrame.AuctionCheckTooltipHooked then
        return
    end

    mailOnEnterHandler = function(self)
        local owner = self or this or MiniMapMailFrame
        ShowMailTooltip(owner)
    end

    mailOnLeaveHandler = function()
        HideMailTooltip()
    end

    mailFrame:SetScript("OnEnter", mailOnEnterHandler)
    mailFrame:SetScript("OnLeave", mailOnLeaveHandler)

    mailFrame.AuctionCheckTooltipHooked = 1
end

local function DebugMailTooltipState()
    local mailFrame = MiniMapMailFrame
    if not mailFrame then
        Chat("MiniMapMailFrame: nil")
        return
    end

    local enterScript = mailFrame:GetScript("OnEnter")
    local leaveScript = mailFrame:GetScript("OnLeave")

    Chat("MiniMapMailFrame exists; shown=" .. (mailFrame:IsShown() and "1" or "0") .. ", visible=" .. (mailFrame:IsVisible() and "1" or "0"))
    Chat("Hooked flag: " .. (mailFrame.AuctionCheckTooltipHooked and "1" or "0"))
    Chat("OnEnter is ours: " .. ((enterScript == mailOnEnterHandler) and "1" or "0"))
    Chat("OnLeave is ours: " .. ((leaveScript == mailOnLeaveHandler) and "1" or "0"))
end

SlashCmdList["AUCTIONCHECK"] = function(msg)
    EnsureDB()

    local cmd = string.lower((msg or ""))
    cmd = string.gsub(cmd, "^%s+", "")
    cmd = string.gsub(cmd, "%s+$", "")

    if cmd == "" then
        ShowStoredData()
    elseif cmd == "clear" then
        ClearAll("Cleared stored auction data.")
    elseif cmd == "debug" then
        local soldFmt = ERR_AUCTION_SOLD_S or "(nil)"
        local wonFmt = ERR_AUCTION_WON_S or "(nil)"
        Chat("ERR_AUCTION_SOLD_S: " .. soldFmt)
        Chat("ERR_AUCTION_WON_S: " .. wonFmt)
        Chat("AUCTION_WON_MAIL_SUBJECT: " .. (AUCTION_WON_MAIL_SUBJECT or "(nil)"))
        Chat("AUCTION_EXPIRED_MAIL_SUBJECT: " .. (AUCTION_EXPIRED_MAIL_SUBJECT or "(nil)"))
    elseif cmd == "debugmail" then
        TryHookMailFrame()
        DebugMailTooltipState()
    elseif cmd == "scan" then
        ScanMailbox()
        Chat("Mailbox scan complete.")
    else
        Chat("Usage: /auctioncheck [clear|debug|debugmail|scan]")
    end
end
SLASH_AUCTIONCHECK1 = "/auctioncheck"

frame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            EnsureDB()
            BuildPatterns()
            TryHookMailFrame()
        end
    elseif event == "CHAT_MSG_SYSTEM" then
        local msg = arg1
        local isSold, soldItem = IsAuctionSystemMessage("sold", msg)
        if isSold then
            AddEntry(AuctionCheckDB.sold, soldItem or msg, 1)
            return
        end

        local isWon, wonItem = IsAuctionSystemMessage("won", msg)
        if isWon then
            AddEntry(AuctionCheckDB.won, wonItem or msg, 1)
        end
    elseif event == "MAIL_SHOW" then
        ScanMailbox()
    elseif event == "MAIL_INBOX_UPDATE" then
        ScanMailbox()
    elseif event == "UPDATE_PENDING_MAIL" then
        TryHookMailFrame()
    end
end)

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("CHAT_MSG_SYSTEM")
frame:RegisterEvent("MAIL_SHOW")
frame:RegisterEvent("MAIL_INBOX_UPDATE")
frame:RegisterEvent("UPDATE_PENDING_MAIL")
