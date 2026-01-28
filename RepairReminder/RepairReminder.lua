-- RepairReminder.lua
-- Reminds you to repair when visiting a vendor.
-- Features:
--   /rr <minutes>     -> set reminder interval
--   /rr on|off        -> enable/disable reminders + button
--   /rr reset         -> reset to defaults
--   /rrdur <percent>  -> set durability threshold (warn only if AVERAGE durability is below X%)
-- Button:
--   Bottom-right "Repair All" button (shows only at repair-capable merchants)
--   Tooltip includes cost (with coin icon) + durability indicator (red/yellow/green)
--   Click: repair with personal funds
--   Alt-Click: attempt guild repairs (if allowed)

RepairReminderDB = RepairReminderDB or {}

-- Defaults
local DEFAULT_INTERVAL_MINUTES = 90
local DEFAULT_DURABILITY_THRESHOLD_PERCENT = 50
local DEFAULT_ENABLED = true

-- Runtime
local lastReminderAt = 0
local repairButton

DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00RepairReminder loaded.|r")

------------------------------------------------------------
-- Helpers
------------------------------------------------------------
local function Trim(s)
  return (s or ""):match("^%s*(.-)%s*$")
end

local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage(msg)
end

local function ApplyDefaults()
  if RepairReminderDB.enabled == nil then
    RepairReminderDB.enabled = DEFAULT_ENABLED
  end
  if RepairReminderDB.intervalMinutes == nil then
    RepairReminderDB.intervalMinutes = DEFAULT_INTERVAL_MINUTES
  end
  if RepairReminderDB.durabilityThresholdPercent == nil then
    RepairReminderDB.durabilityThresholdPercent = DEFAULT_DURABILITY_THRESHOLD_PERCENT
  end
end

local function ResetDefaults()
  RepairReminderDB = {
    enabled = DEFAULT_ENABLED,
    intervalMinutes = DEFAULT_INTERVAL_MINUTES,
    durabilityThresholdPercent = DEFAULT_DURABILITY_THRESHOLD_PERCENT,
  }
  lastReminderAt = 0
end

local function GetIntervalSeconds()
  return (RepairReminderDB.intervalMinutes or DEFAULT_INTERVAL_MINUTES) * 60
end

local function GetThreshold()
  return RepairReminderDB.durabilityThresholdPercent or DEFAULT_DURABILITY_THRESHOLD_PERCENT
end

------------------------------------------------------------
-- Durability
------------------------------------------------------------
-- Returns:
--   avgPct (number)  average durability % across equipped items with durability
--   lowestPct (number) lowest durability % across equipped items with durability
--   nil, nil if no durability-bearing items are found
local function GetEquippedDurabilityStats()
  local slots = { 1, 3, 5, 6, 7, 8, 9, 10, 15, 16, 17 }

  local sumPct = 0
  local count = 0
  local lowest = nil

  for _, slotId in ipairs(slots) do
    local cur, max = GetInventoryItemDurability(slotId)
    if cur and max and max > 0 then
      local pct = (cur / max) * 100
      sumPct = sumPct + pct
      count = count + 1
      if (not lowest) or pct < lowest then
        lowest = pct
      end
    end
  end

  if count == 0 then
    return nil, nil
  end

  return (sumPct / count), lowest
end

------------------------------------------------------------
-- Merchant helpers
------------------------------------------------------------
local function CanRepairHere()
  return type(CanMerchantRepair) == "function" and CanMerchantRepair()
end

local function GetRepairCost()
  if type(GetRepairAllCost) == "function" then
    local cost, canRepair = GetRepairAllCost()
    return cost or 0, canRepair
  end
  return 0, false
end

local function MoneyString(copper)
  return GetCoinTextureString and GetCoinTextureString(copper) or (tostring(copper) .. "c")
end

------------------------------------------------------------
-- UI: Bottom-right Repair button (styled: icon + tooltip)
------------------------------------------------------------
local function CreateRepairButton()
  if repairButton or not MerchantFrame then return end

  repairButton = CreateFrame(
    "Button",
    "RepairReminderRepairButton",
    MerchantFrame,
    "UIPanelButtonTemplate"
  )

  repairButton:SetSize(170, 24)

  -- Bottom-right anchor (stable)
  repairButton:ClearAllPoints()
  repairButton:SetPoint("BOTTOMRIGHT", MerchantFrame, "BOTTOMRIGHT", -28, 28)

  -- Left icon (repair icon)
  local icon = repairButton:CreateTexture(nil, "ARTWORK")
  icon:SetSize(16, 16)
  icon:SetPoint("LEFT", repairButton, "LEFT", 8, 0)
  icon:SetTexture("Interface\\MerchantFrame\\UI-Merchant-Repair")
  repairButton.icon = icon

  -- Re-center text with room for icon
  local fontString = repairButton:GetFontString()
  if fontString then
    fontString:ClearAllPoints()
    fontString:SetPoint("CENTER", repairButton, "CENTER", 8, 0)
  end

  local coinIcon = "|TInterface\\MoneyFrame\\UI-GoldIcon:14:14:0:0|t"

  local function GetDurabilityIndicator(avg, threshold)
    if not avg then
      return "Average durability: Unknown", 0.8, 0.8, 0.8
    end

    if avg < threshold then
      return string.format("Average durability: %.0f%% (Below %d%%)", avg, threshold), 1.0, 0.2, 0.2
    elseif avg < (threshold + 10) then
      return string.format("Average durability: %.0f%% (Near %d%%)", avg, threshold), 1.0, 0.82, 0.2
    else
      return string.format("Average durability: %.0f%% (OK)", avg), 0.2, 1.0, 0.2
    end
  end

  -- Tooltip
  repairButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")

    local canRepair = CanRepairHere()
    local cost, canRepairCost = GetRepairCost()
    local avg, lowest = GetEquippedDurabilityStats()
    local threshold = GetThreshold()

    GameTooltip:AddLine("Repair All Now", 1, 1, 1)

    if canRepair then
      GameTooltip:AddLine("Merchant can repair.", 0.2, 1, 0.2)
    else
      GameTooltip:AddLine("Merchant cannot repair.", 1, 0.2, 0.2)
    end

    -- Cost line (coin icon when cost exists)
    if canRepair and canRepairCost and cost and cost > 0 then
      GameTooltip:AddDoubleLine(coinIcon .. " Cost", MoneyString(cost), 1, 1, 1, 1, 1, 1)
    else
      GameTooltip:AddDoubleLine("Cost", "—", 1, 1, 1, 0.8, 0.8, 0.8)
    end

    -- Durability indicator (based on AVERAGE)
    local durText, r, g, b = GetDurabilityIndicator(avg, threshold)
    GameTooltip:AddLine(" ", 1, 1, 1)
    GameTooltip:AddLine(durText, r, g, b)

    -- Detail lines (use "lowest" wording)
    if avg then
      GameTooltip:AddDoubleLine("Average durability", string.format("%.0f%%", avg), 1, 1, 1, 1, 1, 1)
    end
    if lowest then
      GameTooltip:AddDoubleLine("Lowest durability", string.format("%.0f%%", lowest), 1, 1, 1, 1, 1, 1)
    end
    GameTooltip:AddDoubleLine("Reminder threshold", string.format("%d%%", threshold), 1, 1, 1, 1, 1, 1)

    GameTooltip:AddLine(" ", 1, 1, 1)
    GameTooltip:AddLine("Click: Repair all items", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Alt-Click: Try guild repairs (if enabled)", 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)

  repairButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  -- Click behavior (Alt-click attempts guild repair)
  repairButton:SetScript("OnClick", function()
    if not CanRepairHere() then return end

    local cost, canRepair = GetRepairCost()
    if not canRepair or not cost or cost <= 0 then
      Print("|cffffff00RepairReminder: Nothing to repair.|r")
      return
    end

    local useGuild = IsAltKeyDown() and CanGuildBankRepair and CanGuildBankRepair()
    RepairAllItems(useGuild and true or false)

    if useGuild then
      Print(("|cff00ff00RepairReminder: Repaired all items using guild funds (%s).|r"):format(MoneyString(cost)))
    else
      Print(("|cff00ff00RepairReminder: Repaired all items for %s.|r"):format(MoneyString(cost)))
    end
  end)

  repairButton:Hide()
end

local function UpdateRepairButton()
  CreateRepairButton()
  if not repairButton then return end

  if CanRepairHere() then
    local cost, canRepair = GetRepairCost()

    if canRepair and cost and cost > 0 then
      repairButton:SetText(("Repair All (%s)"):format(MoneyString(cost)))
      repairButton.icon:SetVertexColor(1, 1, 1)
      repairButton:Enable()
    else
      repairButton:SetText("Repair All")
      repairButton.icon:SetVertexColor(0.6, 0.6, 0.6)
      repairButton:Disable()
    end

    repairButton:Show()
  else
    repairButton:Hide()
  end
end

------------------------------------------------------------
-- Slash commands
------------------------------------------------------------
SLASH_REPAIRREMINDER1 = "/rr"
SLASH_REPAIRREMINDER2 = "/repairreminder"

SlashCmdList["REPAIRREMINDER"] = function(msg)
  msg = Trim(msg)
  ApplyDefaults()

  local lower = msg:lower()

  if lower == "" then
    Print(("|cff00ff00RepairReminder|r: %s | interval %d min | threshold %d%%")
      :format(
        RepairReminderDB.enabled and "ON" or "OFF",
        RepairReminderDB.intervalMinutes,
        GetThreshold()
      ))
    Print("Commands: /rr <minutes> | on | off | reset | /rrdur <percent>")
    return
  end

  if lower == "on" then
    RepairReminderDB.enabled = true
    Print("|cff00ff00RepairReminder enabled.|r")
    return
  end

  if lower == "off" then
    RepairReminderDB.enabled = false
    Print("|cffff0000RepairReminder disabled.|r")
    return
  end

  if lower == "reset" then
    ResetDefaults()
    Print(("|cff00ff00RepairReminder reset to defaults.|r Interval %d min, threshold %d%%, enabled %s.")
      :format(RepairReminderDB.intervalMinutes, RepairReminderDB.durabilityThresholdPercent, tostring(RepairReminderDB.enabled)))
    return
  end

  local minutes = tonumber(msg, 10)
  if not minutes or minutes < 1 then
    Print("|cffffff00Usage: /rr <minutes> (example: /rr 90) | on | off | reset|r")
    return
  end

  RepairReminderDB.intervalMinutes = minutes
  Print(("|cff00ff00RepairReminder interval set to %d minutes.|r"):format(minutes))
end

SLASH_REPAIRREMINDERDUR1 = "/rrdur"
SLASH_REPAIRREMINDERDUR2 = "/repairreminderdur"

SlashCmdList["REPAIRREMINDERDUR"] = function(msg)
  msg = Trim(msg)
  ApplyDefaults()

  if msg == "" then
    Print(("RepairReminder: durability threshold is %d%% (warn only if AVERAGE durability is below this).")
      :format(GetThreshold()))
    Print("Usage: /rrdur <percent>   Example: /rrdur 40")
    return
  end

  local pct = tonumber(msg, 10)
  if not pct or pct < 1 or pct > 100 then
    Print("|cffffff00Usage: /rrdur <1-100> (example: /rrdur 40)|r")
    return
  end

  RepairReminderDB.durabilityThresholdPercent = pct
  Print(("|cff00ff00RepairReminder durability threshold set to %d%%.|r"):format(pct))
end

------------------------------------------------------------
-- Events
------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("MERCHANT_SHOW")
frame:RegisterEvent("MERCHANT_CLOSED")

frame:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    ApplyDefaults()
    CreateRepairButton()
    return
  end

  if event == "MERCHANT_SHOW" then
    UpdateRepairButton()

    if not RepairReminderDB.enabled then return end
    if not CanRepairHere() then return end

    -- Rate-limit reminders
    local now = time()
    if now - lastReminderAt < GetIntervalSeconds() then return end

    -- Reminder trigger based on AVERAGE durability
    local avg = select(1, GetEquippedDurabilityStats())
    local threshold = GetThreshold()

    -- If we can't detect durability, remind anyway (rare)
    if (not avg) or (avg < threshold) then
      if avg then
        Print(("|cffff0000RepairReminder: Repair suggested! Average durability %.0f%% (threshold %d%%).|r"):format(avg, threshold))
      else
        Print("|cffff0000RepairReminder: Repair suggested! (Durability unknown)|r")
      end
      lastReminderAt = now
    end
    return
  end

  if event == "MERCHANT_CLOSED" and repairButton then
    repairButton:Hide()
  end
end)

