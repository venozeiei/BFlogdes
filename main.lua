-- โหลดคอนฟิกจาก URL
loadstring(game:HttpGet("https://raw.githubusercontent.com/venozeiei/scripts/main/config.lua"))()

repeat task.wait() until game:IsLoaded()
repeat task.wait() until game.Players.LocalPlayer.Team ~= nil and game:IsLoaded()

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

local function GetFruitInU()
    local fruits = {}
    for _, v in pairs(CommF:InvokeServer("getInventory")) do
        if type(v) == "table" and table.find(_G.Config.WantedFruits, v.Name) then
            table.insert(fruits, string.split(v.Name, "-")[2])
        end
    end
    return #fruits > 0 and table.concat(fruits, ", ") or ""
end

-- (ส่วนอื่น ๆ ของโค้ดที่เหลือยังคงเหมือนเดิม)
