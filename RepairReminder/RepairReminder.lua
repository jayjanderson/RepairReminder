local addonName = ...
local f = CreateFrame("Frame")

local DEFAULTS = {
  enabled = true,
  threshold = 50,       -- remind when overall durability is at or below this %
  resetAt = 95,         -- reset reminder when overall durability is at or above this %
  quietReset = true,    -- don't print a "reset" message
  showWorstItem = true, -- include lowest item durability in reminder
  renudgeMinutes = 0,   -- 0 = off; otherwise re-remind after this many minutes (on vendor open)
}

-- Session state (resets on relog / /reload)
local remindedThisSession = false
local lastReminderAt = 0 -- seconds since login (GetTime())

local SLOT_NAMES = {
  [1] = "Head",
  [2] = "Neck",
  [3] = "Shoulder",
  [4] = "Shirt",
  [5] = "Chest",
  [6] = "Waist",
  [7] = "Legs",
  [8] = "Feet",
  [9] = "Wrist",
  [10] = "Hands",
  [11] = "Finger 1",
  [12] = "Finger 2",
  [13] = "Trinket 1",
  [14] = "Trinket 2",
  [15] = "Back",
  [16] = "Main Hand",
  [17] = "Off Hand",
  [18] = "Ranged",
}

local function Print(msg)
  print("|cff00ff00[RepairReminder]|r " .. msg)
end

local function GetDurabilityStats()
  local totalCur, totalMax = 0, 0
  local worstPct, worstSlot = 101, nil

  for slot = 1, 18 do
    local cur, max = GetInventoryItemDurability(slot)
    if cur and max and max > 0 then
      totalCur = totalCur + cur
      totalMax = totalMax + max

      local pct = (cur / max) * 100
      if pct < worstPct then
        worstPct = pct
        worstSlot = slot
      end
    end
  end

  local overall = (totalMax > 0) and ((totalCur / totalMax) * 100) or 100
  if worstSlot == nil then
    worstPct = nil
  end

  return overall, worstSlot, worstPct
end

local function FormatMoney(copper)
  if not copper or copper <= 0 then return "0g" end
  local gold = math.floor(copper / 10000)
  local silver = math.floor((copper % 10000) / 100)
  local c = copper % 100

  if gold > 0 then
    return string.format("%dg %ds %dc", gold, silver, c)
  elseif silver > 0 then
    return string.format("%ds %dc", silver, c)
  else
    return string.format("%dc", c)
  end
end

local function ShouldRenudge()
  local mins = tonumber(RepairReminderDB.renudgeMinutes) or 0
  if mins <= 0 then return false end
  if lastReminderAt <= 0 then return true end
  return (GetTime() - lastReminderAt) >= (mins * 60)
end

local function MaybeRemindOnMerchant()
  if not RepairReminderDB.enabled then return end

  -- UX guardrail: no reminder while in combat
  if UnitAffectingCombat("player") then return end

  if not CanMerchantRepair() then return end

  local cost, canRepairNow = GetRepairAllCost()
  if not cost or cost <= 0 then return end -- nothing to repair

  local overall, worstSlot, worstPct = GetDurabilityStats()

  -- Remind at or below threshold
  if overall > RepairReminderDB.threshold then return end

  -- One reminder per session, unless renudge is enabled and time has passed
  if remindedThisSession and not ShouldRenudge() then return end

  local costText = FormatMoney(cost)

  local detail = ""
  if RepairReminderDB.showWorstItem and worstSlot and worstPct then
    local slotName = SLOT_NAMES[worstSlot] or ("Slot " .. tostring(worstSlot))
    detail = string.format(" | Worst: %s %.0f%%", slotName, worstPct)
  end

  if canRepairNow then
    Print(string.format(
      "Durability: %.0f%% (at or below %d%%). Repair cost: %s%s",
      overall, RepairReminderDB.threshold, costText, detail
    ))
  else
    Print(string.format(
      "Durability: %.0f%% (at or below %d%%). Repair cost: %s (not enough gold)%s",
      overall, RepairReminderDB.threshold, costText, detail
    ))
  end

  remindedThisSession = true
  lastReminderAt = GetTime()
end

local function CheckForRepairReset()
  if not remindedThisSession then return end

  local overall = select(1, GetDurabilityStats())
  if overall >= RepairReminderDB.resetAt then
    remindedThisSession = false
    lastReminderAt = 0
    if not RepairReminderDB.quietReset then
      Print(string.format("Repaired (≥%d%%). Reminder reset.", RepairReminderDB.resetAt))
    end
  end
end

local function HandleSlash(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

  if msg == "" or msg == "status" then
    local overall, worstSlot, worstPct = GetDurabilityStats()
    local worst = (worstSlot and worstPct)
      and string.format("%s %.0f%%", SLOT_NAMES[worstSlot] or ("Slot " .. worstSlot), worstPct)
      or "n/a"

    Print(string.format(
      "Enabled: %s | Threshold: %d%% | ResetAt: %d%% | QuietReset: %s | WorstItem: %s | Renudge: %s | Current: %.0f%% | Worst: %s",
      tostring(RepairReminderDB.enabled),
      RepairReminderDB.threshold,
      RepairReminderDB.resetAt,
      tostring(RepairReminderDB.quietReset),
      tostring(RepairReminderDB.showWorstItem),
      (RepairReminderDB.renudgeMinutes > 0) and (RepairReminderDB.renudgeMinutes .. "m") or "off",
      overall,
      worst
    ))
    Print("Commands: /rr on|off | /rr <number> | /rr reset | /rr quiet on|off | /rr worst on|off | /rr renudge <mins>")
    return
  end

  if msg == "on" then
    RepairReminderDB.enabled = true
    Print("Enabled.")
    return
  elseif msg == "off" then
    RepairReminderDB.enabled = false
    Print("Disabled.")
    return
  elseif msg == "reset" then
    remindedThisSession = false
    lastReminderAt = 0
    Print("Session reminder reset (manual).")
    return
  end

  local a, b = msg:match("^(%S+)%s+(%S+)$")
  if a == "quiet" then
    RepairReminderDB.quietReset = (b == "on")
    Print("quietReset set to " .. tostring(RepairReminderDB.quietReset) .. ".")
    return
  elseif a == "worst" then
    RepairReminderDB.showWorstItem = (b == "on")
    Print("showWorstItem set to " .. tostring(RepairReminderDB.showWorstItem) .. ".")
    return
  elseif a == "renudge" then
    local n = tonumber(b) or 0
    n = math.max(0, math.floor(n))
    RepairReminderDB.renudgeMinutes = n
    Print("renudgeMinutes set to " .. ((n > 0) and (n .. " minutes") or "off") .. ".")
    return
  end

  local n = tonumber(msg:gsub("%%", ""))
  if n then
    n = math.max(1, math.min(100, math.floor(n)))
    RepairReminderDB.threshold = n
    Print("Threshold set to " .. n .. "%.")
    return
  end

  Print("Unknown command. Try /rr status")
end

f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("MERCHANT_SHOW")
f:RegisterEvent("UPDATE_INVENTORY_DURABILITY")

f:SetScript("OnEvent", function(self, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name ~= addonName then return end

    RepairReminderDB = RepairReminderDB or {}
    for k, v in pairs(DEFAULTS) do
      if RepairReminderDB[k] == nil then
        RepairReminderDB[k] = v
      end
    end

    SLASH_REPAIRREMINDER1 = "/rr"
    SlashCmdList["REPAIRREMINDER"] = HandleSlash
    return
  end

  if event == "PLAYER_LOGIN" then
    remindedThisSession = false
    lastReminderAt = 0
    Print("Loaded. Type /rr status for options.")
    return
  end

  if event == "MERCHANT_SHOW" then
    MaybeRemindOnMerchant()
    return
  end

  if event == "UPDATE_INVENTORY_DURABILITY" then
    CheckForRepairReset()
    return
  end
end)
