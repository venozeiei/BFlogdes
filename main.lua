repeat task.wait() until game:IsLoaded()
repeat task.wait() until game.Players.LocalPlayer.Team ~= nil and game:IsLoaded()

_G.Delay = 1
local Req = (syn and syn.request) or request or (http and http.request) or http_request
local User = game.Players.LocalPlayer.Name
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CommF = ReplicatedStorage.Remotes.CommF_
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local function foo(n)
    if n >= 1e6 then return string.format("%.0fM", n / 1e6)
    elseif n >= 1e3 then return string.format("%.0fK", n / 1e3)
    else return tostring(n) end
end

local function formatNumber(number)
    local i, k, j = tostring(number):match("(%-?%d?)(%d*)(%.?.*)")
    return i .. k:reverse():gsub("(%d%d%d)", "%1,"):reverse() .. j
end

local function format_number_(n)
    return tonumber(n:gsub(",", ""))
end

local function GetFruitInU()
    local fruits = {}
    for _, v in pairs(CommF:InvokeServer("getInventory")) do
        if type(v) == "table" and (v.Name == "Yeti-Yeti" or v.Name == "Leopard-Leopard" or v.Name == "Gas-Gas" or v.Name == "Kitsune-Kitsune") then
            table.insert(fruits, string.split(v.Name, "-")[2])
        end
    end
    return #fruits > 0 and table.concat(fruits, ", ") or ""
end

local function GetFriendsList()
    local success, friends = pcall(function()
        local friendsList = {}
        local friendPages = Players:GetFriendsAsync(LocalPlayer.UserId)
        while true do
            for _, friend in ipairs(friendPages:GetCurrentPage()) do
                table.insert(friendsList, {Username = friend.Username, UserId = friend.UserId, IsOnline = friend.IsOnline})
            end
            if friendPages.IsFinished then break end
            friendPages:AdvanceToNextPageAsync()
        end
        return friendsList
    end)
    return success and #friends > 0 and friends or {}
end

local function FormatFriendsListForDescription(friends)
    return #friends > 0 and tostring(#friends) .. " friends" or "No friends found"
end

spawn(function()
    local fightingStyles = {
        {"Superhuman", "BuySuperhuman"}, {"DeathStep", "BuyDeathStep"}, {"SharkmanKarate", "BuySharkmanKarate"},
        {"ElectricClaw", "BuyElectricClaw"}, {"DragonTalon", "BuyDragonTalon"}, {"Godhuman", "BuyGodhuman"},
        {"SanguineArt", "BuySanguineArt"}
    }
    local weaponChecks = {
        {"Cursed Dual Katana", "Cdk", 375}, {"Shark Anchor", "SA", 350}, {"Hallow Scythe", "HS", 350},
        {"Soul Guitar", "SG", 300, "Gun"}, {"Fox Lamp", "FOX"}
    }
    
    while task.wait(_G.Delay) do
        local inventory = CommF:InvokeServer("getInventory") or {}
        local Level = LocalPlayer.Data.Level.Value
        local LevelShow = Level == 2600 and "Max" or Level
        
        -- Fighting Styles
        local HeeCount = 0
        local styleStatus = {}
        for _, style in ipairs(fightingStyles) do
            styleStatus[style[1]] = CommF:InvokeServer(style[2], true) == 1
            if styleStatus[style[1]] then HeeCount = HeeCount + 1 end
        end
        
        -- Weapons and Mastery
        local weaponDisplays = {}
        for _, check in ipairs(weaponChecks) do
            for _, v in pairs(inventory) do
                if v.Type == (check[4] or "Sword") and string.find(v.Name, check[1]) then
                    local mastery = v.Mastery >= (check[3] or 0) and "" or "(" .. v.Mastery .. ")"
                    weaponDisplays[check[2]] = " | " .. check[2] .. mastery
                    break
                end
            end
        end
        
        -- Accessories and Materials
        local ShowVHMF = ""
        local hasValk = false
        local hasMirror = false
        for _, v in pairs(inventory) do
            if v.Type == "Wear" and string.find(v.Name, "Valkyrie Helm") then hasValk = true
            elseif v.Type == "Material" and string.find(v.Name, "Mirror Fractal") then hasMirror = true end
        end
        if hasValk and hasMirror then ShowVHMF = " | VK+MR"
        elseif hasValk then ShowVHMF = " | VK"
        elseif hasMirror then ShowVHMF = " | MR" end
        
        local ShowPullStatus = CommF:InvokeServer("CheckTempleDoor") and " | Lv" or ""
        
        -- Race
        local raceMap = {Human = "Hu", Mink = "Mink", Skypiea = "Sky", Fishman = "Fish", Cyborg = "Cyb", Ghoul = "Gh"}
        local NameRace = " | " .. (raceMap[LocalPlayer.Data.Race.Value] or "")
        local GetTier = (CommF:InvokeServer("UpgradeRace", "Check") or {})[2] or 0
        local raceAbilities = {{"Awakening", "V4"}, {"Last Resort", "V3"}, {"Agility", "V3"}, {"Heavenly Blood", "V3"},
                              {"Water Body", "V3"}, {"Energy Core", "V3"}, {"Heightened Senses", "V3"}}
        local ShowRace = NameRace .. "V1"
        for _, ability in ipairs(raceAbilities) do
            if LocalPlayer.Backpack:FindFirstChild(ability[1]) or LocalPlayer.Character:FindFirstChild(ability[1]) then
                ShowRace = ability[2] == "V4" and NameRace .. " V4 T." .. GetTier or NameRace .. ability[2]
                break
            elseif LocalPlayer.Data.Race:FindFirstChild("Evolved") then ShowRace = NameRace .. "V2" end
        end
        
        -- Fruit Mastery and Stats
        local FruitMastery = 0
        for _, v in pairs(LocalPlayer.Character:GetChildren()) do
            if v:IsA("Tool") and v.ToolTip == "Blox Fruit" then FruitMastery = v.Level.Value break end
        end
        if FruitMastery == 0 then
            for _, v in pairs(LocalPlayer.Backpack:GetChildren()) do
                if v:IsA("Tool") and v.ToolTip == "Blox Fruit" then FruitMastery = v.Level.Value break end
            end
        end
        
        local MyFruit = LocalPlayer.Data.DevilFruit.Value
        local CurrentFN = MyFruit == "" and "None" or (MyFruit == "T-Rex-T-Rex" and "T-Rex" or string.match(MyFruit, "%-(.*)"))
        local awakened = CommF:InvokeServer("getAwakenedAbilities") or {}
        local S = 0
        for _, v in pairs(awakened) do if v.Awakened then S = S + 1 end end
        local AwakedStat = ""
        if CurrentFN == "Dough" and S == 6 then AwakedStat = "F."
        elseif CurrentFN == "Quake" and S == 4 then AwakedStat = "F."
        elseif S == 5 then AwakedStat = "F." end
        
        -- Money and Materials
        local Money = foo(format_number_(formatNumber(LocalPlayer.Data.Beli.Value)))
        local Fragment = foo(format_number_(formatNumber(LocalPlayer.Data.Fragments.Value)))
        local materialCounts = {["Dark Fragment"] = 0, ["Vampire Fang"] = 0, ["Demonic Wisp"] = 0, ["Alucard Fragment"] = 0}
        local CheckHeart = ""
        for _, v in pairs(inventory) do
            if v.Type == "Material" then
                if materialCounts[v.Name] then materialCounts[v.Name] = v.Count
                elseif v.Name == "Leviathan Heart" then CheckHeart = " | H" end
            end
        end
        
        -- Build Alias and Description
        local HeeAl = {LevelShow, " | ", HeeCount, weaponDisplays["Cdk"] or "", weaponDisplays["SA"] or "",
                      weaponDisplays["FOX"] or "", ShowVHMF, ShowPullStatus}
        Req({Method = "POST", Url = "http://localhost:7963/SetAlias?Account=" .. User, Body = table.concat(HeeAl)})
        
        local friendsList = GetFriendsList()
        local HeeDes = {AwakedStat, CurrentFN, "(", FruitMastery, ")", " | M : ", Money, " | F :", Fragment, CheckHeart,
                       " | Fruits : ", GetFruitInU(), " | ", ShowRace, " | CDK :", materialCounts["Alucard Fragment"],
                       " | Friends: ", FormatFriendsListForDescription(friendsList)}
        Req({Method = "POST", Url = "http://localhost:7963/SetDescription?Account=" .. User, Body = table.concat(HeeDes)})
    end
end)

spawn(function()
    local buttons = {
        {"CDK", "Cursed Dual Katana"}, {"Anchor", "Shark Anchor"}, {"SGA", "BuySanguineArt"},
        {"GOD", "BuyGodhuman"}, {"Skarate", "BuySharkmanKarate"}, {"W3", "TravelZou"},
        {"Race", "BlackbeardReward", "Reroll", "2"}, {"Cyborg", "CyborgTrainer", "Buy"},
        {"Ghoul", "Ectoplasm", "Change", 4}, {"Friends", "Show Friends"}
    }
    while task.wait() do
        local success = pcall(function()
            for _, btn in ipairs(buttons) do
                Nexus:CreateButton(btn[1], btn[#btn > 2 and 1 or 2], {100, 35})
            end
        end)
        if success then break end
    end
end)

local buttonActions = {
    CDK = function() CommF:InvokeServer("LoadItem", "Cursed Dual Katana") end,
    Anchor = function() CommF:InvokeServer("LoadItem", "Shark Anchor") end,
    SGA = function() CommF:InvokeServer("BuySanguineArt") end,
    GOD = function() CommF:InvokeServer("BuyGodhuman") end,
    Skarate = function() CommF:InvokeServer("BuySharkmanKarate") end,
    W3 = function() CommF:InvokeServer("TravelZou") end,
    Race = function() CommF:InvokeServer("BlackbeardReward", "Reroll", "2") end,
    Cyborg = function() CommF:InvokeServer("CyborgTrainer", "Buy") end,
    Ghoul = function() CommF:InvokeServer("Ectoplasm", "Change", 4) end,
    Friends = function()
        local friends = GetFriendsList()
        local message = #friends == 0 and "No friends found." or "Friends (" .. #friends .. "):\n" .. table.concat(
            table.create(#friends, function(i, friend) return i .. ". " .. friend.Username .. " " .. (friend.IsOnline and "(Online)" or "(Offline)") .. "\n" end),
            "", 1, #friends)
        game.StarterGui:SetCore("ChatMakeSystemMessage", {Text = message, Color = Color3.fromRGB(255, 255, 255), Font = Enum.Font.SourceSansBold, FontSize = Enum.FontSize.Size24})
    end
}

for btn, action in pairs(buttonActions) do
    Nexus:OnButtonClick(btn, action)
end
