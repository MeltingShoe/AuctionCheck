local ADDON_NAME = "AuctionCheck"
local PREFIX = "|cff33ff99AuctionCheck|r"

local frame = CreateFrame("Frame")
local auctionSoldPattern = nil
local auctionSoldPrefix = nil
local mailHooked = false

local function Chat(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. " " .. msg)
    end
end

local function EnsureDB()
    if not AuctionCheckDB then
        AuctionCheckDB = { sold = {} }
    end
    if not AuctionCheckDB.sold then
        AuctionCheckDB.sold = {}
    end
end

local function EscapePattern(s)
    if not s then
        return ""
    end
    return string.gsub(s, "([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
end

local function BuildAuctionSoldPattern()
    auctionSoldPattern = nil
    auctionSoldPrefix = nil

    if type(ERR_AUCTION_SOLD_S) == "string" and ERR_AUCTION_SOLD_S ~= "" then
        local escaped = EscapePattern(ERR_AUCTION_SOLD_S)
        local withCapture = string.gsub(escaped, "%%%%s", "(.+)")
        auctionSoldPattern = "^" .. withCapture .. "$"
        auctionSoldPrefix = string.gsub(ERR_AUCTION_SOLD_S, "%%s.*$", "")
    end
end

local function IsAuctionSoldMessage(msg)
    if type(msg) ~= "string" or msg == "" then
        return false, nil
    end

    if auctionSoldPattern and auctionSoldPrefix and auctionSoldPrefix ~= "" then
        if string.find(msg, auctionSoldPrefix, 1, 1) then
            local item = string.match(msg, auctionSoldPattern)
            if item then
                return true, item
            end
        end
    elseif auctionSoldPattern then
        local item = string.match(msg, auctionSoldPattern)
        if item then
            return true, item
        end
    end

    local lowerMsg = string.lower(msg)
    if string.find(lowerMsg, "your auction of", 1, 1) and string.find(lowerMsg, "sold", 1, 1) then
        local item = string.match(msg, "[Yy]our auction of%s+(.+)%s+[Hh]as sold")
        if not item then
            item = string.match(msg, "[Yy]our auction of%s+(.+)%s+[Ss]old")
        end
        return true, item
    end

    return false, nil
end

local function AddSoldMessage(msg, item)
    EnsureDB()
    table.insert(AuctionCheckDB.sold, {
        t = time(),
        item = item,
        msg = msg,
    })
end

local function ClearSold(reason)
    EnsureDB()
    AuctionCheckDB.sold = {}
    if reason then
        Chat(reason)
    end
end

local function FormatClock(ts)
    local value = ts or time()
    return date("%H:%M", value)
end

local function FormatDateTime(ts)
    local value = ts or time()
    return date("%Y-%m-%d %H:%M:%S", value)
end

local function ShowStoredSales()
    EnsureDB()
    local sold = AuctionCheckDB.sold
    local count = table.getn(sold)

    Chat("Stored auction sales: " .. count .. " (oldest -> newest)")
    if count == 0 then
        Chat("No stored auction sales.")
        return
    end

    local i
    for i = 1, count do
        local entry = sold[i]
        local whenText = FormatDateTime(entry.t)
        if entry.item and entry.item ~= "" then
            Chat(whenText .. " - " .. entry.item)
        else
            Chat(whenText .. " - " .. (entry.msg or "(no message)"))
        end
    end
end

local function ShowMailTooltip(self)
    EnsureDB()

    local anchor = "ANCHOR_LEFT"
    if self then
        anchor = "ANCHOR_BOTTOMLEFT"
    end

    GameTooltip:SetOwner(self, anchor)
    GameTooltip:AddLine("AuctionCheck")

    local sold = AuctionCheckDB.sold
    local count = table.getn(sold)

    if count == 0 then
        GameTooltip:AddLine("No stored auction sales.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
        return
    end

    GameTooltip:AddLine("Stored sales: " .. count, 1, 1, 1)

    local maxLines = 10
    local startIndex = count - maxLines + 1
    if startIndex < 1 then
        startIndex = 1
    end

    local i
    for i = startIndex, count do
        local entry = sold[i]
        local text = entry.item and entry.item ~= "" and entry.item or (entry.msg or "(no message)")
        GameTooltip:AddLine(FormatClock(entry.t) .. " - " .. text, 0.9, 0.9, 0.9, 1)
    end

    if count > maxLines then
        GameTooltip:AddLine("(Showing last 10)", 0.7, 0.7, 0.7)
    end

    GameTooltip:Show()
end

local function HideMailTooltip()
    GameTooltip:Hide()
end

local function TryHookMailFrame()
    if mailHooked then
        return
    end

    local mailFrame = MiniMapMailFrame
    if not mailFrame then
        return
    end

    local oldEnter = mailFrame:GetScript("OnEnter")
    local oldLeave = mailFrame:GetScript("OnLeave")

    mailFrame:SetScript("OnEnter", function(self)
        if oldEnter then
            oldEnter(self)
        end
        ShowMailTooltip(self)
    end)

    mailFrame:SetScript("OnLeave", function(self)
        HideMailTooltip()
        if oldLeave then
            oldLeave(self)
        end
    end)

    mailHooked = true
end

SlashCmdList["AUCTIONCHECK"] = function(msg)
    EnsureDB()

    local cmd = string.lower((msg or ""))
    cmd = string.gsub(cmd, "^%s+", "")
    cmd = string.gsub(cmd, "%s+$", "")

    if cmd == "" then
        ShowStoredSales()
    elseif cmd == "clear" then
        ClearSold("Cleared stored auction sales.")
    elseif cmd == "debug" then
        local fmt = ERR_AUCTION_SOLD_S or "(nil)"
        local pat = auctionSoldPattern or "(nil)"
        Chat("ERR_AUCTION_SOLD_S: " .. fmt)
        Chat("Pattern: " .. pat)
    else
        Chat("Usage: /auctioncheck [clear|debug]")
    end
end
SLASH_AUCTIONCHECK1 = "/auctioncheck"

frame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            EnsureDB()
            BuildAuctionSoldPattern()
            TryHookMailFrame()
        end
    elseif event == "CHAT_MSG_SYSTEM" then
        local msg = arg1
        local isSold, item = IsAuctionSoldMessage(msg)
        if isSold then
            AddSoldMessage(msg, item)
        end
    elseif event == "MAIL_SHOW" then
        ClearSold("Mailbox opened - cleared stored auction sales.")
    elseif event == "UPDATE_PENDING_MAIL" then
        TryHookMailFrame()
    end
end)

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("CHAT_MSG_SYSTEM")
frame:RegisterEvent("MAIL_SHOW")
frame:RegisterEvent("UPDATE_PENDING_MAIL")
