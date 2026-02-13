local ADDON_NAME = "AuctionCheck"
local PREFIX = "|cff33ff99AuctionCheck|r"

local frame = CreateFrame("Frame")
local auctionSoldPattern = nil
local auctionSoldPrefix = nil
local mailOnEnterHandler = nil
local mailOnLeaveHandler = nil

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

    local sold = AuctionCheckDB.sold
    if table.getn(sold) > 0 then
        local first = sold[1]
        if first and (first.t or first.msg or not first.count) then
            local rebuilt = {}
            local i
            for i = 1, table.getn(sold) do
                local entry = sold[i]
                local label = entry.item
                if not label or label == "" then
                    label = entry.msg or "(unknown sale)"
                end

                local j
                local found = nil
                for j = 1, table.getn(rebuilt) do
                    if rebuilt[j].item == label then
                        found = rebuilt[j]
                        break
                    end
                end

                if found then
                    found.count = found.count + (entry.count or 1)
                else
                    table.insert(rebuilt, { item = label, count = entry.count or 1 })
                end
            end
            AuctionCheckDB.sold = rebuilt
        end
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

    local label = item
    if not label or label == "" then
        label = msg or "(unknown sale)"
    end

    local sold = AuctionCheckDB.sold
    local i
    for i = 1, table.getn(sold) do
        local entry = sold[i]
        local existingLabel = entry.item
        if (not existingLabel or existingLabel == "") and entry.msg then
            existingLabel = entry.msg
            entry.item = existingLabel
        end

        if existingLabel == label then
            entry.count = (entry.count or 1) + 1
            return
        end
    end

    table.insert(sold, {
        item = label,
        count = 1,
    })
end

local function ClearSold(reason)
    EnsureDB()
    AuctionCheckDB.sold = {}
    if reason then
        Chat(reason)
    end
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
        local text = entry.item or entry.msg or "(unknown sale)"
        local qty = entry.count or 1
        Chat(qty .. "x " .. text)
    end
end

local function ShowMailTooltip(owner)
    EnsureDB()

    if not owner then
        owner = MiniMapMailFrame
    end

    if not owner then
        return
    end

    local anchor = "ANCHOR_BOTTOMLEFT"

    GameTooltip:SetOwner(owner, anchor)
    GameTooltip:ClearLines()
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
        local text = entry.item or entry.msg or "(unknown sale)"
        local qty = entry.count or 1
        GameTooltip:AddLine(qty .. "x " .. text, 0.9, 0.9, 0.9, 1)
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
        ShowStoredSales()
    elseif cmd == "clear" then
        ClearSold("Cleared stored auction sales.")
    elseif cmd == "debug" then
        local fmt = ERR_AUCTION_SOLD_S or "(nil)"
        local pat = auctionSoldPattern or "(nil)"
        Chat("ERR_AUCTION_SOLD_S: " .. fmt)
        Chat("Pattern: " .. pat)
    elseif cmd == "debugmail" then
        TryHookMailFrame()
        DebugMailTooltipState()
    else
        Chat("Usage: /auctioncheck [clear|debug|debugmail]")
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
