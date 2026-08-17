--[[
	Hamsterdiwa — Steal An Egg Auto Farm
	PlaceId 107778070777162

	ลูป: เช็ครีเซ็ต -> คัดไข่ดีสุด -> วาปไปเก็บ -> กลับฐาน -> วางไข่ -> ฟัก -> อัปฐาน -> Equip Best -> ขายตัวล้น

	ทุกอย่างในไฟล์นี้วัดจากเกมจริงแล้ว:
	  เคลื่อนที่  : วาปทีละ <=60 studs แล้วพัก  (ลากต่อเนื่องเกิน 1.5x WalkSpeed = โดนลากกลับฐาน)
	                60/0.15 = 400 ผ่าน · 60/0.08 = 750 ผ่าน · 60/0.04 = 1500 พัง · ก้าว 120 พัง
	  เข้าโซน     : ต้องเดินข้ามเส้น GameplayZ (x ~552.8) ทีละก้าวเล็ก ไม่งั้น "Enter the gameplay area first"
	  เก็บไข่     : Eggs: RequestAreaEggCarry { Uid }   — เซิร์ฟเช็คระยะถึงไข่จริง เลี่ยงไม่ได้
	  ตีมูลค่าไข่ : AssetGenerationUtil.GetRateWithoutRebirth (สายพันธุ์ + ขนาด + mutation)
	  วางไข่      : Eggs: RequestPlaceEgg { Uid, LocalCFrame } — ต้องยืนกลางแปลงตัวเอง
	  ฟัก         : RequestHatchEgg -> RequestCompleteHatchEgg
	  ลงคอก       : Backpack: EquipBest
	  ขาย         : ActiveAssets: RequestSell (uuid string)
	  อัปฐาน      : Plots: RequestBaseUpgrade (FireServer เปล่า)
	  Noclip      : ตัวที่ขังเราในวงไข่คือ Guard.Collider — ปิด CanCollide ฝั่งเราก็ทะลุออก
]]

--==================================================================
-- SERVICES
--==================================================================
local Players           = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local TweenService       = game:GetService("TweenService")
local HttpService        = game:GetService("HttpService")

-- [ถอดออกแล้ว] เคยมี  local บริการจำลองอินพุต = บริการจำลองอินพุตของ CoreScript
--
-- บริการจำลองอินพุต เป็นบริการต้องห้าม สคริปต์ของเกมเรียกไม่ได้เลย มีแต่ CoreScript ของ Roblox
-- แค่ "เรียก" ก็ประกาศตัวว่าเป็นสคริปต์โกงแล้ว ไม่ต้องเรียกใช้ฟังก์ชันข้างในด้วยซ้ำ
--
-- วัดสดแบบแยกตัวแปร 2026-08-16:
--   เรียก บริการจำลองอินพุตของ CoreScript แล้วนั่งเฉยๆ ไม่ทำอะไรอีกเลย
--   -> โดนเตะที่ ~10 วินาที  "removed for cheating (Error Code: 267)"
-- ตัวควบคุมที่รันคู่กันแล้วรอด: ตั้ง global ชื่อเดียวกับสคริปต์ + สร้าง GUI (48 วิ)
--   · require โมดูลของเกม 3 ตัว (20 วิ+) · ยิงรีโมท 41 ครั้งรวด · ไถเก็บไข่ 6 รอบ
-- ทั้งหมดไม่โดนอะไรเลย เหลือตัวนี้ตัวเดียวที่โดน
--
-- เราใช้มันแค่กัน AFK ซึ่งฟาร์มที่ขยับตลอดเวลาไม่ต้องใช้อยู่แล้ว
-- ห้ามเอากลับมาไม่ว่ากรณีใด

local LocalPlayer = Players.LocalPlayer

--==================================================================
-- ปิดตัวเก่าก่อน
--
-- รันไฟล์ทับโดยไม่ปิดตัวเก่า = ลูปเก่ายังวิ่งอยู่ (มันไม่ผูกกับ UI เลยไม่ตายตาม)
-- สองลูปจะแย่งกันเขียน CFrame คนละเป้าหมาย เซิร์ฟเห็นเป็นการวาปมั่วแล้วลากกลับฐานรัวๆ
-- เคยเจอมาแล้วตอนรันทับ 8 รอบ ทุกลูปเลยต้องเช็ค generation ก่อนทำงาน
--==================================================================
local genv = (type(getgenv) == "function") and getgenv() or _G

if genv.EGG_FARM_HUB then
	pcall(function() genv.EGG_FARM_HUB.Destroy() end)
end

-- ตัวนับต้องอยู่ตารางเดียวกับ Hub
--
-- executor หลายตัว getgenv() กับ _G เป็นคนละตารางกัน (เช็คมาแล้วในเครื่องจริง)
-- ถ้า Hub อยู่ genv แต่ตัวนับอยู่ _G พอรันทับ ตัวเก่าจะมองไม่เห็นว่ามีตัวใหม่มา
-- แล้วรันต่อไปเงียบๆ = สองลูปแย่งเขียน CFrame = โดนเซิร์ฟลากกลับรัวๆ
-- เขียนลงทั้งสองตารางเผื่อสคริปต์เวอร์ชันเก่ายังค้างอยู่ แต่ยึด genv เป็นหลัก
genv.EGG_FARM_GEN = (tonumber(genv.EGG_FARM_GEN) or tonumber(_G.EGG_FARM_GEN) or 0) + 1
local GEN = genv.EGG_FARM_GEN
_G.EGG_FARM_GEN = GEN

do -- เก็บกวาด UI ที่ค้างจากรอบก่อน
	local function sweep(root)
		if not root then return end
		pcall(function()
			for _, c in ipairs(root:GetChildren()) do
				if c:IsA("ScreenGui") and tostring(c.Name):find("EggFarm") then
					pcall(function() c:Destroy() end)
				end
			end
		end)
	end
	pcall(function() sweep(LocalPlayer:FindFirstChild("PlayerGui")) end)
	pcall(function() sweep(game:GetService("CoreGui")) end)
	if gethui then pcall(function() sweep(gethui()) end) end
end

local Hub = {}
Hub.Name = "Hamsterdiwa — Steal An Egg"
Hub.Brand = "Hamsterdiwa"
Hub.Alive = true
Hub.Gen = GEN
Hub.Phase = "พัก"
Hub.Build = "clean-700"

-- จุดยืนกลาง SAFE ZONE ที่ใช้จริง วัดจากในเกม
-- แก้ตรงนี้ที่เดียวถ้าอยากย้ายจุดยืนของทุกเครื่อง
Hub.HOME = { X = 513.43, Y = 68.58, Z = -364.74 }
genv.EGG_FARM_HUB = Hub

-- ยังเป็นรุ่นล่าสุดอยู่ไหม
--
-- ตัวนี้สำคัญกว่าที่เห็น ทุกลูปเบื้องหลังใช้มันเป็นตัวตัดสินว่าจะหยุดตัวเองไหม
-- ถ้ามันตอบผิด ลูปของรอบก่อนๆ จะไม่ยอมตาย แล้วทับถมกันทุกครั้งที่รันสคริปต์ใหม่
-- รันสิบรอบ = สิบลูปยิงเซิร์ฟพร้อมกัน เกมค้างสนิท (เจอจริงบนเครื่องทดสอบ)
--
-- ของเดิมดูแค่ genv ซึ่งบาง executor คืนตารางใหม่ทุกครั้งที่รัน
-- ตัวนับรุ่นเลยเริ่มที่ 1 ใหม่ทุกรอบ ทุกลูปจึงคิดว่าตัวเองใหม่ล่าสุดตลอด
-- ดู _G ด้วยเพราะตารางนั้นใช้ร่วมกันแน่นอน ใครเห็นรุ่นใหม่กว่าก็หยุดตัวเอง
local function alive()
	if not Hub.Alive then return false end
	local a, b = genv.EGG_FARM_GEN, _G.EGG_FARM_GEN
	if a ~= nil and a ~= GEN then return false end
	if b ~= nil and b ~= GEN then return false end
	return true
end

--==================================================================
-- CONFIG
--==================================================================
local Config = {
	-- "ALL" = คัดไข่ $/s สูงสุดจากทุกด่าน ไม่สนระดับด่าน
	-- ด่านสุดท้ายไม่ได้แปลว่าไข่ดีสุดเสมอ เคยวัดได้ Snow $858K/s ขณะที่ Cosmic $25K/s
	Area        = "ALL",

	Step        = 55,    -- ระยะต่อการวาป 1 ครั้ง (เพดานที่วัดได้ = 60)
	Gap         = 0.10,  -- พักระหว่างวาป (ต่ำกว่า 0.06 เริ่มพัง)
	LoopDelay   = 2,

	-- เพดานความเร็วในการเคลื่อนที่ (studs ต่อวินาที)  ดูรายละเอียดที่ Hub.glide
	--
	-- เกมอัปเดต 2026-08-16 ย้ายการตัดสินไปฝั่งเซิร์ฟเวอร์ วาปทีเดียวถึงใช้ไม่ได้อีกแล้ว
	-- วัดสด: 121 / 135 / 154 / 180 st/s เก็บไข่ติดหมด · 260 st/s ตาย
	-- ตายครั้งเดียวเซิร์ฟเลิกเชื่อตำแหน่งเราทั้งเซสชันจนกว่าจะออกแล้วเข้าใหม่
	-- 130 คือค่าที่เผื่อไว้เยอะ ห้ามดันขึ้นไปไล่เพดานถ้าไม่ได้นั่งดูจอ
	-- ตรึงตำแหน่งทับทุกเฟรมตอนกล่องขาวขึ้น
	--
	-- ปิดไว้ เพราะการสู้กับตัวที่กำลังดึงเราออกคือเงื่อนไขที่ระบบใหม่ใช้ตัดสินว่า
	-- "แก้ไขไม่สำเร็จ" แล้วยกระดับเป็นเตะออก (ดูคำอธิบายเต็มที่ Hub.pinAt)
	-- เปิดได้ถ้าจะทดลอง แต่อย่าเปิดบนเครื่องลูกค้า
	PinHold     = false,

	-- วาปทีเดียวถึงแบบของเดิม ไม่คุมความเร็ว
	--
	-- เปิดไว้ให้ลองเองได้ แต่วัดมาแล้วไม่ผ่านตั้งแต่ 2026-08-16:
	--   วาป 436 studs บนเซสชันสะอาด ไม่ครอบทับอะไร ไม่มี บริการจำลองอินพุต ไม่มีตัวตรึง
	--   -> 0.36 วิ โดนดีดกลับที่เดิม (d=436 ตั้งแต่ตัวอย่างแรก)
	--   -> carry ตอบ "Enter the gameplay area first" 8 ครั้งจาก 8
	--   -> ไม่ตาย ไม่โดนเตะ แค่ไปไม่ถึง
	--
	-- คนละเรื่องกับการโดนเตะ  การโดนเตะแก้แล้วด้วยการถอด บริการจำลองอินพุต
	-- ส่วนตัวนี้คือเซิร์ฟเวอร์เก็บตำแหน่งของตัวเองไว้ต่างหาก แล้วเลื่อนตามเราได้
	-- ไม่เกิน 8.49 studs ต่อ 1 tick (0.05 วิ) ปะฝั่งไคลเอนต์ไม่มีผลกับมันเลย
	WarpInstant = false,

	-- ปลดเพดานความเร็วด้วยกลไกของเกมเอง (ดูรายละเอียดเต็มที่ Hub.armImpulse)
	--
	-- เขียน state.ImpulseContext ของระบบกันโกงเอง ซึ่งเป็นโหมดยกเว้นที่เกมใช้
	-- ตอนผู้เล่นโดนระเบิด/กระแทก  ไม่ได้ hook อะไรเลย แค่เขียนตารางที่ไม่ freeze
	--
	-- ปิดตัวนี้ = ถอยไปใช้เพดานปกติ (WalkSpeed x 1.1 + 8) ซึ่งยังทำงานได้
	-- แค่ช้ากว่า ~4 เท่า  executor ที่ไม่มี getgc จะถอยไปทางนั้นเองอัตโนมัติ
	ImpulseBypass = true,

	-- ความเร็วตอนเปิดโหมดยกเว้น (studs/วินาที)
	--
	-- วัดสด v364 ระยะ 433 studs แล้วยิงเก็บไข่จริง:
	--   250 -> 1.72 วิ ผ่าน · 400 -> 1.06 วิ ผ่าน · 700 -> 0.62 วิ ผ่าน
	--   1200 -> วิ่งเลยเป้าไปไม่ถึง (ไม่ใช่เซิร์ฟปฏิเสธ)
	-- 600 คือจุดที่เร็วกว่าของเดิม (550) แต่ยังไม่แกว่ง
	-- ดันเกณฑ์สั่งแก้ไข (SpeedCorrectionThreshold 1.35) ให้เป็นอนันต์
	--
	-- นี่คือกลไกเดียวกับที่โค้ดรุ่นก่อนเกมอัปเดตใช้ แล้ววาปเฟรมเดียวได้โดยไม่โดนดึงกลับ
	-- ต้องมี debug.setupvalue ตัวรันที่ไม่มีจะข้ามไปเอง สคริปต์ยังทำงานได้ปกติ
	LiftThreshold = true,

	-- ถึงที่หมายแล้วปล่อยโหมดยกเว้นหมดอายุ เพื่อให้เกมตั้งจุดตั้งต้นใหม่ให้ (ดู Hub.expireImpulse)
	-- นี่คือกลไกของเกมเอง ไม่ใช่การหลอก  ปิดได้ถ้าอยากเทียบผล
	ExpireOnArrive = true,

	-- รับรองตำแหน่งตัวเองเป็นจุดตั้งต้นทุกเฟรมตอนเดินทาง (ดู Hub.adoptBaseline)
	--
	-- ปิดไว้เป็นค่าเริ่มต้น ยังพิสูจน์ไม่ได้ว่าช่วย
	-- วัด A/B สลับกันทันที: เปิด = ดึงกลับ 51 ครั้ง · ปิด = 54 ครั้ง (แทบไม่ต่าง)
	-- และตอนเปิดเจออาการค้าง เปิดเองได้ถ้าอยากลองต่อ
	AdoptBaseline = false,

	-- เฝ้าลูกวิ่งเบื้องหลัง ติดเมื่อไหร่ปลดให้เองทุก 1 วินาที (ดู Hub.unstickTreadmill)
	TreadmillWatch = true,

	-- กดกระโดดให้เองเมื่อค้างไปต่อไม่ได้เกิน 4 วินาที (ดู Hub.unstickStalled)
	-- ทำแทนการกด space bar เอง โดยไม่ต้องรู้ว่าติดสถานะอะไร
	StallWatch = true,

	-- ยืนจุดกลางอย่างเดียว ไม่วาปเข้าแปลงเลย
	--
	-- ต้องประกาศตรงนี้ ไม่งั้น loader ตั้งมาก็ไม่มีผล
	-- mergeConfig ปฏิเสธคีย์ที่ยังไม่มีในตารางนี้ (เช็ค "if cur ~= nil then")
	StayCentre  = false,

	-- เพดานสูงสุด (studs/วินาที)
	--
	-- 320 ไม่ใช่การยอมแพ้ มันเร็วกว่าจริงๆ วัดมาแล้วบนเครื่องเดียวกันติดกัน:
	--
	--                    700 st/s      320 st/s
	--   โดนดึงกลับ        42 ครั้ง   ->   0 ครั้ง
	--   ตาย               7 ครั้ง   ->   0 ครั้ง
	--   เก็บไข่ได้        11 ฟอง    ->  15 ฟอง
	--   วินาทีต่อฟอง      4.55      ->  3.33
	--
	-- ที่ 700 เราโดนลากย้อนกลับเกือบทุกขา แล้วต้องวิ่งซ้ำ เวลาที่เสียมากกว่าเวลาที่ประหยัดได้
	--
	-- เพดานที่เซิร์ฟยอมรับคำนวณจากค่าในเกมเอง:
	--   TreadmillUtil.luau:18  MAX_WALK_SPEED = 300
	--   Impact.luau:101        เพดาน = WalkSpeed * SpeedMultiplier(1.1) + SpeedFlatAllowance(8)
	--   300 * 1.1 + 8 = 338 studs/วินาที คือเร็วสุดที่ผู้เล่นจริงเป็นไปได้
	-- ตั้ง 320 ให้ต่ำกว่านิดหน่อยเผื่อความคลาดเคลื่อน
	--
	-- และยังเร็วกว่าสัตว์เฝ้าทุกโซน (เร็วสุดคือ Cosmic 200)
	MoveSpeed   = 320,

	-- เผื่อเพดานความเร็วไว้กี่ส่วน  1.0 = ชนเพดานเป๊ะ (อย่าทำ)
	-- ใช้เฉพาะตอนเปิดโหมดยกเว้นไม่ได้
	--
	-- เพดานจริง = WalkSpeed * 1.1 + 8  อ่านสูตรมาจากโค้ดเกม (ดู Hub.legalSpeed)
	-- WalkSpeed 147 -> เพดาน 169.8 -> ที่ 0.9 ได้ 152.8 studs/วินาที
	-- ซึ่งยังเร็วกว่าเดินเองในเกม (147) เลยยังหนีการ์ดทัน
	SpeedSafety = 0.9,

	-- หยุดห่างเป้าเท่าไหร่ถึงถือว่าถึงแล้ว
	-- เซิร์ฟยอมให้เก็บไข่ในระยะ 30 studs เพราะงั้น 6 เหลือเฟือ
	WalkReach   = 6,

	-- "step"  = วาปเป็นก้อนแล้วพัก  ภาพกระตุกแต่ทนความเร็วสูงได้ (ใช้คู่กล้องนิ่มแล้วดูลื่น)
	-- "tween" = ลากต่อเนื่องทุกเฟรม ภาพลื่นจริง แต่ต้องลดความเร็วลงมาก ไม่งั้นโดนดึงกลับ
	--
	-- วัดมาแล้ว: ลากต่อเนื่อง 550 st/s โดนดึงทุกครั้ง · ราว 70 st/s ถึงจะรอด
	--            ส่วนวาปเป็นก้อน 550 st/s ผ่านสบาย (เฟรมส่วนใหญ่ขยับ 0)
	-- อัปเดต: หาสาเหตุเจอแล้ว ตัวที่ฆ่าเราคือโค้ดเกมฝั่งเราเอง ไม่ใช่เซิร์ฟเวอร์
	-- ปิดส่วนลงมือของมันได้ (ดู patchAntiCheat) แล้ววาปได้เลยไม่ต้องไล่ก้าว
	-- วัดแล้ว ไปกลับ Abyss Ocean (ห่าง ~1,750 studs) รอบละ ~620ms เลือดไม่ลด
	-- ตั้ง "auto" ถ้าไม่แน่ใจว่าเครื่องนั้นปะระบบกันโกงได้ไหม จะเลือกให้เอง
	MoveMode    = "warp",

	-- จุดยืนกลางเซฟโซนของโหมดวาป  ว่าง = ใช้ค่ากลางที่คำนวณไว้ (x512.8 z-364)
	-- ปะระบบตรวจจับไม่ได้ = ห้ามวาป ให้ถอยไปเดินแทน
	--
	-- วัดบนเครื่องที่ปะไม่ได้: วาปโดยไม่ปะ ตาย 4 ครั้งใน 12 วินาที แทบทุกรอบ
	-- ตายแล้วไข่หลุดมือด้วย ไม่คุ้มกับความเร็วที่ได้มา
	-- เลิกใช้แล้ว เก็บไว้เพื่อความเข้ากันได้กับคอนฟิกเก่า
	WarpRequirePatch = false,

	-- ไปยืนทับไข่ที่แพงสุดรอตั้งแต่ยังรีเซ็ตไม่จบ จะได้เก็บก่อนคนอื่น
	-- โดนตีเมื่อไหร่ถอยกลับเซฟโซนเอง  ตั้ง false ถ้าไม่อยากเสี่ยง
	PreWarpOnReset = true,

	-- ทำงานบ้าน (ฟักไข่ อัปฐาน วางสัตว์ ขายตัวอ่อน) ทุกกี่รอบ
	-- 1 = ทุกรอบเหมือนเดิม  5 = ทำทุกรอบที่ 5 ระหว่างนั้นเอาเวลาไปเก็บไข่
	-- เก็บไข่ติดๆ กันกี่ฟองก่อนกลับไปวางลงรัง
	-- 1 = เก็บทีละฟองแบบเดิม  5 = เก็บ 5 ฟองแล้วค่อยวางทีเดียว
	-- ระดับ cosmic ขึ้นไปมีไม่เกิน 5 ฟองต่อรอบรีเซ็ต ตั้ง 5 กำลังดี
	ChainGrab = 5,

	-- ขายสัตว์ที่สู้ตัวในคอกไม่ได้ กี่ตัวต่อรอบ (0 = ขายเฉพาะตอนทำงานบ้าน)
	-- หลังสนามรีเซ็ต เก็บทุกใบโดยไม่เทียบราคากับคอก นานกี่วินาที
	--
	-- ปิดไว้ (0) เพราะเจ้าของงานเลือกใช้เกณฑ์เทียบกับคอกตลอดเวลา
	-- ไข่ที่สู้ตัวในคอกไม่ได้ เก็บมาก็ใส่คอกไม่ได้ ได้แค่เอาไปขาย
	-- เปิดเป็น 90 ถ้าเปลี่ยนใจอยากกวาดทุกใบช่วงไข่ใหม่มา
	-- ไข่ต่ำกว่านี้ไม่ออกไปเก็บ แม้คอกจะยังว่าง ($/s)
	-- 0 = ไม่ใช้เกณฑ์นี้ (ค่าเริ่มต้น เร็วสุด)
	-- ตั้งเป็นตัวเลขถ้าอยากกันไข่ขยะ เช่น 10000 = ไม่เก็บไข่ต่ำกว่า $10K/s
	-- ปะระบบตรวจจับซ้ำทุกกี่วินาที (กันการปะหลุดกลางทาง)
	-- ปะระบบตรวจจับซ้ำทุกกี่วินาที
	-- การสแกนกิน 148 มิลลิวินาที ทำถี่เกินไปคือถ่วงรอบเปล่าๆ
	RepatchEvery = 30,

	-- หน่วงหลังวาปก่อนยิงคำสั่ง (วินาที)  ต่ำกว่า 0.15 เสี่ยงเก็บไม่ติด
	-- กดตัวติดพื้นก่อนวาปไหม  false = วาปไปพิกัดดิบเลย
	-- ช่วงรีเซ็ตจะข้ามการกดพื้นให้เองอยู่แล้ว เพราะมีกล่องครอบสนาม
	WarpSnapGround = true,

	-- หน่วงหลังถึงที่หมายก่อนยิงคำสั่ง
	--
	-- ยิ่งวิ่งเร็ว ยิ่งต้องรอนาน ไม่ใช่สั้นลง
	-- เซิร์ฟเลื่อนตำแหน่งของตัวเองตามเราด้วยอัตราจำกัด วิ่ง 600 มันตามช้ากว่าวิ่ง 153
	-- เคยลดเหลือ 0.05 ตอนวิ่ง 153 ซึ่งใช้ได้ แต่พอเร่งเป็น 600 แล้วพัง
	-- อาการ: เก็บไข่ไม่ติด และกลับเซฟโซนแล้วไม่ยอมฝากไข่
	WarpSettle = 0.18,
	-- หน่วงตอนแวะฝากไข่เข้ากระเป๋า
	-- หน่วงตอนแวะฝากไข่  เป็นแค่ค่าเริ่มต้น ตัวจริงรอจนไข่ออกจากมือจริง
	DepositWait = 0.12,

	MinEggRate = 0,

	-- หลังสนามรีเซ็ต หน่วงกี่วินาทีก่อนยิงเก็บใบแรก
	-- ไข่โผล่ในรายการก่อนที่เซิร์ฟจะพร้อมให้เก็บจริง ยิงเร็วไปโดนปฏิเสธ
	-- หน่วงหลังรีเซ็ตก่อนยิงเก็บใบแรก
	-- ปิดไว้ (0) เพราะหลักฐานที่ผมใช้ตัดสินใจใส่มันมาจากเครื่องมือวัดที่พังเอง
	-- ถ้าเจอว่าช่วงรีเซ็ตพลาดจริงค่อยตั้ง 1.5
	ResetSettleDelay = 0,

	-- หลังสนามรีเซ็ต ให้ความสำคัญกับการเก็บไข่กี่วินาที
	-- ช่วงนี้จะไม่แวะทำงานบ้าน และไม่เทียบราคากับคอก เก็บก่อนไว้ก่อน
	-- ของดีอยู่ได้ไม่กี่วินาทีก่อนโดนคนอื่นเก็บ
	-- ยืนทับไข่ยิงคำสั่งรัวๆ รอเซิร์ฟปลดล็อกได้นานสุดกี่วินาที
	-- วัดจริง: เซิร์ฟเปิดให้เก็บที่ ~6 วินาทีหลังไข่รีเซ็ต ตั้ง 10 เผื่อไว้
	-- กี่วินาทีสุดท้ายก่อนไข่รีเซ็ตที่ห้ามเริ่มงานบ้าน  ให้ยืนรอเก็บไข่อย่างเดียว
	-- 0 = ปิด  ยิ่งมากยิ่งไม่พลาดจังหวะ แต่เสียเวลาฟัก/ขายไปบ้าง
	-- ช่วงไข่เพิ่งรีเซ็ต เก็บติดกันได้กี่ใบก่อนแวะไปวางลงรัง
	-- ปกติใช้ ChainGrab (5) แต่ช่วงรีเซ็ตของดีมีให้แย่งแค่ไม่กี่วินาที
	-- ต้องกวาดให้หมดก่อน ค่อยไปวางตอนสนามเงียบแล้ว
	ChainGrabFresh = 12,

	PreResetQuiet = 20,

	-- เหลือกี่วินาทีก่อนรีเซ็ต ให้กลับมายืนนิ่งที่จุดกลางแล้วรอกล่องขาวหาย
	--
	-- ระหว่างกล่องขาวขึ้น เซิร์ฟไม่ให้เก็บไข่ ยิงไปกี่ครั้งก็ไม่ติด
	-- ออกไปตอนนั้นมีแต่เสีย: เก็บไม่ได้ · โดนการ์ดตี · แล้วคิวไข่โดนไล่ข้ามทิ้ง
	-- ยืนรอเฉยๆ แล้วออกตอนกล่องเปิด ได้ของครบกว่าและไม่ตาย
	-- 0 = ปิด (กลับไปใช้ท่าเดิมคือวาปไปยืนทับไข่รอ ซึ่งวัดแล้วเก็บไม่ติด)
	PreResetHold = 10,

	-- ยืนรอไข่รีเซ็ตได้นานสุดกี่วินาที  ครบแล้วยังไม่มาก็ออกไปลองเก็บเลย
	-- กันกรณีตัวตรวจ fieldIsFresh พลาด จะได้ไม่ยืนแช่ตลอดกาล
	ResetWaitMax = 90,

	-- วางไข่ไม่ลงติดกัน 3 รอบแล้วพักกี่วินาทีก่อนลองใหม่
	-- กันอาการวาปเข้าแปลงแล้วออกวนไม่จบเมื่อรังเต็ม
	-- วาปแล้วตาย 2 ครั้ง พักไปเดินกี่วินาทีก่อนกลับมาวาปใหม่
	-- ไม่ปิดวาปถาวร เพราะการตายมักมาจากจังหวะชั่วคราวไม่ใช่ตัวเครื่อง
	-- รอคำตอบจากเซิร์ฟนานสุดกี่วินาทีก่อนถือว่าไม่ตอบแล้วไปต่อ
	-- กันอาการวาปแล้วค้างเพราะ InvokeServer ไม่มีเวลาหมดอายุในตัว
	-- ปะกันโกงไม่ติด รออีกกี่วินาทีค่อยลองใหม่
	-- การสแกนหน่วยความจำแพง ยิ่งเครื่องช้ายิ่งแพง ห้ามลองรัวๆ
	-- กลับมายืนกลางก่อนวาปไปไข่ใบถัดไปเสมอ
	-- ห้ามวาปจากริมสนามไปริมสนาม เป็นทางที่ตายบ่อยที่สุด
	ViaHome = true,

	-- ให้โหมด tween/step วาปตรงๆ เหมือน warp
	-- ปลอดภัยแล้วเพราะปิดทั้งตัวที่สั่งฆ่าและตัวที่ลากตำแหน่งกลับ
	-- false = กลับไปเลื่อนตัวทีละนิดแบบเดิม
	TweenAsWarp = true,

	-- ห้ามตัวละครตายจากฝั่งเครื่องเรา และดึงเลือดกลับทุกเฟรม
	--
	-- ปิดเป็นค่าเริ่มต้นตั้งแต่เกมอัปเดต 2026-08-16
	--
	-- ระบบใหม่ทำงานแบบนี้: เจอความผิดปกติ -> สั่งแก้ไข (ฆ่า/ลากกลับ)
	-- ถ้าแก้ไขไม่สำเร็จ -> ยิง RemoteEvent "ClientCharacter: IntegrityViolation"
	-- -> เซิร์ฟเตะออก "Client integrity violation (Error Code: 267)"
	--
	-- การปิดสถานะตายแล้วดึงเลือดกลับ = ทำให้การแก้ไขของมันไม่สำเร็จพอดี
	-- เท่ากับเรากดปุ่มเรียกให้ตัวเองโดนเตะ  ปล่อยให้ตายตามปกติปลอดภัยกว่ามาก
	-- (ตายแล้วเกิดใหม่เสียเวลาไม่กี่วินาที โดนเตะเสียทั้งรอบ)
	--
	-- เปิดได้ถ้ารู้ว่ากำลังทำอะไรอยู่ แต่อย่าเปิดบนเครื่องที่ปล่อยรันทิ้งไว้
	BlockDeath = false,

	PatchRetryGap = 3,

	CallTimeout = 4,

	WarpRestAfterDeaths = 180,

	PlaceRetryRest = 60,

	-- ยืนทับไข่ยิงคำสั่งรัวๆ รอเซิร์ฟปลดล็อกได้นานสุดกี่วินาที
	--
	-- วัดจริงจากจังหวะไข่สลับชุด: เข้าถึงไข่ที่ 1.18 วิ แต่เซิร์ฟเพิ่งยอม
	-- ให้เก็บที่ 11.29 วิ = ยืนรอไป 9.86 วินาที เฉียดเพดาน 10 แค่ 0.14 วิ
	-- ถ้าหมดเวลาก่อนจะเสียทั้งรอบ ตั้ง 18 เผื่อเซิร์ฟช้ากว่านี้
	-- กล่องอยู่ราว 15 วินาที ตั้งเกินนั้นนิดหน่อยกำลังดี
	ResetHoldFor = 18,

	-- ยืนจ้องไข่ใบเดียวได้นานสุดกี่วินาทีก่อนหมุนไปใบถัดไป
	-- เซิร์ฟล็อกเป็นรายใบ ใบนี้ไม่ให้ก็ไปลองใบอื่นดีกว่ายืนรอ
	-- วัดจริง: ยืนรอใบเดียว 18 วินาทีแล้วไม่ได้อะไร เสียทั้งหน้าต่าง
	HoldPerEgg = 2.5,

	GrabAfterResetFor = 20,

	-- ฟักไข่ที่พร้อมแล้วกี่ฟองต่อรอบ  0 = ฟักให้หมดทุกฟองที่พร้อม
	-- ไข่ที่ค้างกินช่องรัง เพดาน 30 ใบ ยิ่งค้างยิ่งวางไข่ใหม่ไม่ได้
	-- ฟองละ ~0.5 วิ ถ้าพร้อมพร้อมกันหลายฟองรอบนั้นจะกินเวลาหลายวินาที
	HatchPerCycle = 0,

	-- ไข่ในรังเช็คจากในเครื่องไม่ได้ว่าครบเวลาหรือยัง ต้องยิงถามเซิร์ฟ
	-- เลยแวะไปลองฟักทุกกี่วินาทีตอนที่ว่างจากการเก็บไข่
	HatchRetryEvery = 30,

	SellPerCycle = 4,

	TendEvery = 5,

	WarpHomeX   = nil,
	WarpHomeZ   = nil,


	Running     = false,

	-- เริ่มฟาร์มเองทันทีที่โหลดเสร็จ
	--
	-- แยกออกจาก Running เพราะ Running โดนบังคับเป็น false ทุกครั้งที่โหลดคอนฟิก
	-- (กันไม่ให้ค่าที่เผลอเซฟไว้สั่งบอทออกวิ่งเองโดยไม่ตั้งใจ)
	-- ส่วน AutoStart ต้องตั้งเองเท่านั้น = เจตนาชัด
	AutoStart   = false,

	-- false = ไม่สร้างหน้าต่าง UI เลย  ใช้ตอนสั่งงานผ่านคอนฟิกล้วนๆ
	-- ประหยัดเฟรม เหมาะกับเปิดหลายจอทิ้งไว้
	ShowUI      = true,

	-- ข้อความสถานะลอยกลางจอ  ไม่ใช่หน้าต่าง UI
	--
	-- มีแค่ TextLabel ใบเดียว พื้นหลังโปร่ง ไม่มีกรอบ ไม่มีปุ่ม กินเฟรมแทบไม่ต่างจากศูนย์
	-- ทำงานแยกจาก ShowUI สิ้นเชิง ปิด UI แต่ยังอยากรู้ว่าบอททำอะไรอยู่ก็เปิดตัวนี้ตัวเดียว
	StatusText     = true,
	StatusTextSize = 18,
	StatusTextY    = 0.5,   -- 0 = บนสุด · 0.5 = กลางจอ · 1 = ล่างสุด

	AutoHatch   = true,  -- ฟักไข่ที่พร้อม + ปล่อยสัตว์ลงคอก
	AutoUpgrade = true,  -- อัปเกรดฐานเมื่อเงินถึง (เงินในเกม)
	AutoSell    = true,  -- ขายสัตว์ตัวที่ล้นคอก
	-- ปิด CanCollide ของตัวละครเพื่อทะลุ Collider ของการ์ด
	--
	-- ปิดเป็นค่าเริ่มต้นแล้ว เพราะ CanCollide เป็น property ที่ replicate ขึ้นเซิร์ฟเวอร์
	-- ตัวละครเป็นของเรา เราเขียนค่า เซิร์ฟเห็นทันที
	-- HumanoidRootPart.CanCollide = false คือลายเซ็นโกงที่ anti-cheat ทุกตัวเช็คเป็นอันดับแรก
	-- และอธิบายอาการ "โดนเตะอยู่ดีๆ" ได้พอดี เพราะโดนตอนเซิร์ฟบังเอิญสแกนมาเจอ
	-- ไม่ผูกกับจังหวะไหนเป็นพิเศษ (เทสตอนแรกแค่ 12 วินาทีเลยไม่เจอ)
	--
	-- และเราไม่ต้องใช้มันแล้วจริงๆ  noclip มีไว้ทะลุตอน "เดินชน"
	-- แต่เราขยับด้วยการเขียน CFrame ซึ่งทะลุทุกอย่างอยู่แล้วโดยไม่สนการชนเลย
	Noclip      = false,

	-- ยิงเรย์หาพื้นจริงแล้วเกาะไว้ทุกก้าว
	-- เลนไม่ได้ราบเท่ากันทุกจุด ถ้าไปโผล่จุดที่พื้นต่ำกว่าแล้วลอยค้าง เซิร์ฟจะฆ่าทิ้ง
	GroundSnap  = true,
	SmoothCam   = true,  -- กล้องไล่ตามแบบนุ่ม แก้ภาพกระตุกตอนวาป (ไม่แตะตัวละคร)
	CamSmooth   = 8,     -- สูง = ตามไว · ต่ำ = นุ่มขึ้นแต่ตามช้า
	PerfMode    = true,
	FpsBoost    = true,  -- ตัดเงา พื้นผิว อนุภาค ลดคุณภาพภาพ
	BlankScreen = false, -- ปิดการวาดภาพ 3 มิติ จอว่างแต่เฟรมพุ่งสุด
	SkipWeak    = true,  -- ไข่ที่กากกว่าตัวอ่อนสุดในคอก ไม่ต้องไปเก็บ
	AntiAFK     = true,

	KeepExtra   = 0,     -- เก็บสำรองเกินช่องคอกกี่ตัวก่อนเริ่มขาย
	-- เก็บตัวที่ทำเงินตั้งแต่เท่านี้ขึ้นไปเสมอ  (0 = ไม่สนราคา ขายตามอันดับล้วนๆ)
	--
	-- เขียนเป็นข้อความมีตัวย่อได้  "10M" · "20b" · "9.9t" · "1.5k" · "1,500,000"
	-- k=พัน m=ล้าน b=พันล้าน t=ล้านล้าน q=พันล้านล้าน  (ดู money() ข้างบน)
	-- ลูกค้าหลายคนตั้งค่าผิดเพราะต้องนับศูนย์เอง เลยรับแบบนี้ด้วย
	KeepAbove   = 0,

	-- ห้ามเก็บไข่ที่แย่กว่าตัวอ่อนสุดที่มี แม้คอกจะยังมีช่องว่าง
	-- true  = ไม่มีของดีก็ยืนเฉยๆ รอเวฟถัดไป
	-- false = แบบเดิม ช่องว่างทำเงิน $0 เก็บอะไรมาก็ดีกว่า
	SkipWorseThanPen = true,

	-- ตอนคอกยังมีช่องว่าง ไข่ต้องแรงอย่างน้อยกี่ % ของสัตว์ที่ดีที่สุดที่มี
	-- ช่องว่างทำเงิน $0 เก็บอะไรมาก็ได้เพิ่ม แต่ไม่ควรไล่เก็บของไร้ค่า
	-- 1 = ตัดเฉพาะขยะจริงๆ   10 = เลือกมากขึ้น   0 = เก็บทุกใบ
	EmptySlotPct = 1,
	TripReserve = 40,    -- เหลือเวลาก่อนรีเซ็ตน้อยกว่านี้ (วิ) = ไม่ออกไปไหน
	SafeZonePause = 1.5, -- ขากลับ แวะตรึงที่หน้า SAFE ZONE กี่วิก่อนเข้าแปลง (กันสะดุด)
	WarmupSteps  = 8,    -- ขาออก หลังข้ามเส้นแล้ว วิ่งช้าลงกี่ก้าวก่อนเร่ง
	WarmupGapMul = 2.5,  -- ช่วงออกตัว ช้าลงกี่เท่า (2.5 = เหลือราว 220 studs/s)

	-- ไต่ความเร็วให้ถึงพิกัด X นี้เป็นอย่างน้อย ก่อนจะอัดเต็มสปีด
	--
	-- WarmupSteps อย่างเดียวไม่พอ  55 x 8 = 440 studs จบที่ x=1020
	-- ซึ่งแค่พ้น Desert (944-952) ยังไม่ถึง Jungle แล้วอัดเต็มเลย = โดนลากกลับ
	--
	-- พิกัดด่านที่วัดจากเซิร์ฟ: เส้นแดง 552 · Forest 591 · Lake 738
	--   Desert 944 · Jungle 1183 · Snow 1487 · Volcano 1873
	--   Abyss 2276 · Prehistoric 2808 · Cosmic 3386
	-- 1020 = สุดสาย Desert  ซึ่งเป็นจุดที่ไอดีที่วิ่งได้ไม่ตายใช้อยู่จริง
	--
	-- อย่าตั้งเลย Jungle เด็ดขาด  เคยลอง 1200 (พ้น Jungle) แล้วแย่ลง
	-- วัดเทียบสองไอดี: ตัวที่รอดเริ่มพุ่งที่ ~x1020 · ตัวที่ตายเริ่มพุ่งที่ x1232
	-- ไต่นานเกินไปแปลว่าวิ่งช้าอยู่ในเขตอันตรายนานขึ้น ไม่ได้ปลอดภัยขึ้น
	--
	-- ตั้ง 0 = ปิด ใช้ WarmupSteps อย่างเดียว (Step x WarmupSteps = 440 studs)
	WarmupUntilX = 1020,


	-- ชะงักกี่วินาทีตรงรอยต่อ ก่อนเปลี่ยนจากความเร็วไต่เป็นเต็มสปีด
	--
	-- ช่วงไต่วิ่งราว 220 studs/s แล้วขาถัดไปกระโดดเป็น 550 ทันทีในเฟรมเดียว
	-- เซิร์ฟเห็นความเร็วเปลี่ยนพรวดตรงรอยต่อแล้วลากกลับ
	-- หยุดนิ่งให้ฝั่งเซิร์ฟบันทึกตำแหน่งเราให้ตรงกันก่อน แล้วค่อยเร่ง
	WarmupHold = 1.0,

	AutoSaveConfig = true,

	-- กล่องดำ: เขียนสถานะลงไฟล์ HamsterTrace.txt ทุก 2 วินาที
	--
	-- เก็บย้อนหลัง 150 บรรทัด (ราว 5 นาที) เขียนทับทั้งไฟล์ทุกครั้ง ไฟล์จึงไม่โตขึ้นเรื่อยๆ
	-- มีไว้ให้ลูกค้าที่โดนเตะส่งไฟล์มาดูว่าวินาทีสุดท้ายทำอะไรอยู่
	--
	-- จำเป็นเพราะอาการโดนเตะเกิดเฉพาะบางเครื่อง และเครื่องที่ใช้พัฒนาไม่เคยเป็น
	-- เดาจากภาพหน้าจอทีละใบแล้วผิดมาหลายรอบ เพราะไม่รู้ว่าตอนนั้นทำอะไรอยู่
	-- ตั้ง false ถ้าไม่อยากให้เขียนไฟล์เลย
	Trace = true,
}
Hub.Config = Config

local AREAS = {
	"ALL",
	"Lake", "Desert", "Jungle", "Snow",
	"Volcano", "Abyss Ocean", "Prehistoric", "Cosmic",
}

local GAMEPLAY_LINE_X = 552.8
local LANE_Z, LANE_Y  = -364, 70.6

-- จุดยืนกลาง SAFE ZONE ที่ใช้จริง วัดจากในเกม
-- แก้ตรงนี้ที่เดียวถ้าอยากย้ายจุดยืนของทุกเครื่อง
-- ย้ายไปไว้บน Hub ด้านล่าง (Luau จำกัด local ระดับบนสุดที่ 200 ตัว)

-- จุดยืนรอ: ในเขต SAFE ZONE ถัดจากเส้นแดงเข้ามา
--
-- ต้อง "เลยเส้นแดงเข้ามาให้ลึกพอ" ก่อนจะร่อนลง
-- ของเดิมตั้งไว้ -12 คือเลยเส้นมาแค่ 12 studs ซึ่งชิดเกินไป
-- สัตว์ที่ไล่ตามหลังมาเอื้อมถึงตอนเราชะลอตัวลงจอด แล้วฆ่าเราคาเส้น ไข่หลุดมือ
-- ขยับเข้ามา 40 studs พ้นระยะ แต่ยังใกล้พอที่จะออกตัวรอบหน้าได้ทันที
local IDLE_X = GAMEPLAY_LINE_X - 40

--==================================================================
-- เซฟ / โหลด / รีเซ็ตค่า
--==================================================================
local CONFIG_FILE = "StealAnEgg_Config.json"

local function deepCopy(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = deepCopy(v) end
	return out
end

local DEFAULTS = deepCopy(Config)

-- รับเฉพาะคีย์ที่รู้จักและชนิดตรงกัน ไฟล์เก่าจากเวอร์ชันก่อนเลยไม่ทำให้พัง
-- อ่านค่าเงินแบบที่คนเขียนจริง  "10M" · "20b" · "9.9t" · "1.5k"
--
-- ลูกค้าหลายคนบอกว่าตั้งค่าไม่ถูกเพราะต้องนับศูนย์เอง
-- 9.9 ล้านล้าน = 9900000000000 ซึ่งพิมพ์ผิดง่ายมาก
-- รับทั้งตัวเลขล้วนแบบเดิม และแบบมีตัวย่อ ไม่สนตัวพิมพ์เล็กใหญ่
--
--   k = พัน            1e3
--   m = ล้าน           1e6
--   b = พันล้าน        1e9
--   t = ล้านล้าน       1e12
--   q = พันล้านล้าน    1e15
local MONEY_SUFFIX = {
	k = 1e3, m = 1e6, b = 1e9, t = 1e12, q = 1e15,
}

local function money(v)
	if type(v) == "number" then return v end
	if type(v) ~= "string" then return nil end

	-- ตัดช่องว่างและลูกน้ำออกก่อน  "1,500,000" ก็ต้องอ่านได้
	local s = v:gsub("[%s,]", ""):lower()
	if s == "" then return nil end

	local num, suf = s:match("^([%d%.]+)([a-z]*)$")
	local n = tonumber(num)
	if not n then return nil end
	if suf == "" then return n end

	local mul = MONEY_SUFFIX[suf:sub(1, 1)]
	if not mul then return nil end
	return n * mul
end

-- คีย์ที่เป็นจำนวนเงิน  เขียนเป็นข้อความแบบ "10M" ได้
local MONEY_KEYS = { KeepAbove = true, MinEggRate = true }

local function mergeConfig(dst, src)
	for k, v in pairs(src) do
		local cur = dst[k]

		-- คีย์เงิน: แปลงข้อความเป็นตัวเลขก่อนเช็คชนิด
		--
		-- ต้องทำตรงนี้ ไม่ใช่ทีหลัง เพราะบรรทัด type(cur) == type(v) ข้างล่าง
		-- จะปฏิเสธค่าที่เป็นข้อความทิ้งไปเงียบๆ (ค่าเริ่มต้นเป็นตัวเลข)
		-- ลูกค้าตั้ง KeepAbove = "9.9t" แล้วไม่มีอะไรเกิดขึ้น หาสาเหตุไม่ได้
		if MONEY_KEYS[k] and type(v) == "string" then
			local n = money(v)
			if n then
				v = n
			else
				warn(("[Hamsterdiwa] อ่านค่า %s = %q ไม่ออก ข้ามไป  (ที่ถูก: 10M · 20b · 9.9t)")
					:format(tostring(k), tostring(v)))
				v = nil
			end
		end

		if v ~= nil and cur ~= nil then
			if type(cur) == "table" and type(v) == "table" then
				mergeConfig(cur, v)
			elseif type(cur) == type(v) then
				dst[k] = v
			end
		end
	end
end

local function saveConfig()
	if type(writefile) ~= "function" then return false end
	local snapshot = deepCopy(Config)
	snapshot.Running = false   -- ไม่เซฟสถานะ "กำลังวิ่ง" ครั้งหน้าจะได้ไม่ออกวิ่งเอง
	return (pcall(function()
		writefile(CONFIG_FILE, HttpService:JSONEncode(snapshot))
	end))
end

local function loadConfig()
	if type(readfile) ~= "function" or type(isfile) ~= "function" then return false end
	local exists = false
	pcall(function() exists = isfile(CONFIG_FILE) end)
	if not exists then return false end

	local ok, data = pcall(function() return HttpService:JSONDecode(readfile(CONFIG_FILE)) end)
	if not ok or type(data) ~= "table" then return false end
	data.Running = nil
	mergeConfig(Config, data)
	return true
end

local function resetConfig()
	mergeConfig(Config, deepCopy(DEFAULTS))
	Config.Running = false
	saveConfig()
end

local configDirty = false
local function markDirty() configDirty = true end

--==================================================================
-- ไฟล์คอนฟิกแยก (แก้เองได้ ไม่ต้องยุ่งกับสคริปต์)
--
-- StealAnEgg_Settings.lua  อยู่ในโฟลเดอร์ workspace ของ executor
-- เปิดแก้ด้วย notepad ได้เลย แก้เสร็จรันสคริปต์ใหม่ก็ใช้ค่าใหม่ทันที
--
-- ลำดับการโหลด: ค่าเริ่มต้น -> ไฟล์ JSON ที่ UI เซฟ -> ไฟล์คอนฟิกแยกนี้
-- ไฟล์แยกมาท้ายสุดจึงชนะเสมอ เพราะเป็นไฟล์ที่คุณตั้งใจแก้เอง
-- (ถ้าอยากให้ UI คุมแทน ก็ลบไฟล์นี้ทิ้ง เดี๋ยวมันสร้างใหม่ให้)
--==================================================================
local USER_CONFIG_FILE = "StealAnEgg_Settings.lua"

local CONFIG_TEMPLATE = [==[
-- ==============================================
--  Hamsterdiwa — Steal An Egg  ไฟล์ตั้งค่า
--  แก้ค่าในนี้ได้เลย แล้วรันสคริปต์ใหม่
--  ลบไฟล์นี้ทิ้ง = กลับไปใช้ค่าจาก UI
-- ==============================================
return {

	--------------------------------------------------
	-- ด่านที่จะไปเก็บ
	--------------------------------------------------
	-- "ALL" = คัดไข่ $/s สูงสุดจากทุกด่าน  (แนะนำ)
	-- หรือระบุเอง: Lake · Desert · Jungle · Snow · Volcano · Abyss Ocean · Prehistoric · Cosmic
	Area = "ALL",

	-- เริ่มฟาร์มเองทันทีที่โหลดเสร็จ (หน่วง 3 วิ ให้เกมพร้อมก่อน)
	-- false = ต้องไปกดสวิตช์ "เริ่มฟาร์ม" ใน UI เอง
	AutoStart = false,

	-- false = ไม่เปิดหน้าต่าง UI เลย  ใช้ตอนสั่งงานผ่านคอนฟิกล้วนๆ
	-- ประหยัดเฟรม เหมาะกับเปิดหลายจอทิ้งไว้
	ShowUI = true,

	--------------------------------------------------
	-- ความเร็ว / การเคลื่อนที่
	--------------------------------------------------
	-- "step"  = วาปเป็นก้อนแล้วพัก  เร็วได้ถึง 550 st/s  (ใช้คู่ SmoothCam แล้วภาพดูนิ่ง)
	-- "tween" = ลากต่อเนื่องทุกเฟรม ภาพลื่นจริง แต่ต้องช้าราว 100 st/s ไม่งั้นโดนดึงกลับ
	MoveMode = "step",

	Step = 55,      -- ระยะต่อการวาป 1 ครั้ง (เพดานที่วัดได้ = 60 เกินนี้พัง)
	Gap  = 0.10,    -- พักระหว่างวาป  ความเร็ว = Step / Gap
	                -- step:  0.10 = 550 · 0.15 = 366 · 0.25 = 220
	                -- tween: 0.55 = 100 · 0.80 = 70 (ปลอดภัยสุด)

	WarmupSteps  = 8,     -- หลังข้ามเส้นเข้าโซน ไต่ช้าๆ กี่ก้าวก่อนเร่ง (0 = ไม่ไต่)
	WarmupGapMul = 2.5,   -- ช่วงไต่ ช้าลงกี่เท่า

	SafeZonePause = 1.5,  -- ขากลับ ตรึงนิ่งที่หน้า SAFE ZONE กี่วิ ก่อนเข้าแปลง

	Noclip = false,       -- ห้ามเปิด: CanCollide replicate ขึ้นเซิร์ฟ = โดนเตะ

	--------------------------------------------------
	-- ภาพ
	--------------------------------------------------
	SmoothCam = true,     -- กล้องไล่ตามแบบนุ่ม แก้ภาพกระตุก (ไม่แตะตัวละคร ไม่มีความเสี่ยง)
	CamSmooth = 8,        -- สูง = ตามไว · ต่ำ = นุ่มขึ้นแต่ตามช้า (แนะนำ 6-10)

	PerfMode = true,      -- ใช้ตัวตั้งค่าของเกม: ซ่อนสัตว์คนอื่น · ปิดวิดีโอ · ปิดเพลง/เสียง

	--------------------------------------------------
	-- งานที่ฐาน
	--------------------------------------------------
	AutoHatch   = true,   -- ฟักไข่ที่พร้อม + ปล่อยสัตว์ลงคอก
	AutoUpgrade = true,   -- อัปเกรดฐานเมื่อเงินถึง (เงินในเกม ไม่ใช่ Robux)
	AutoSell    = true,   -- ขายสัตว์ตัวที่ล้นคอก

	KeepExtra = 0,        -- เก็บสำรองเกินช่องคอกกี่ตัวก่อนเริ่มขาย
	KeepAbove = 0,        -- เก็บตัวที่ $/s ตั้งแต่เท่านี้ขึ้นไปเสมอ (0 = ไม่สนราคา)
	                      -- เช่น 500000 = ตัวไหนถึงครึ่งล้านเก็บไว้หมด

	--------------------------------------------------
	-- อื่นๆ
	--------------------------------------------------
	SkipWeak    = true,   -- ไข่ที่กากกว่าตัวอ่อนสุดในคอก ไม่ต้องไปเก็บ
	TripReserve = 40,     -- เหลือเวลาก่อนรีเซ็ตน้อยกว่านี้ (วิ) = ไม่ออกไปไหน
	LoopDelay   = 2,      -- พักระหว่างรอบ (วิ)
	AntiAFK     = true,

	AutoSaveConfig = true,
}
]==]

local function writeUserConfig()
	if type(writefile) ~= "function" then return false end
	return (pcall(function() writefile(USER_CONFIG_FILE, CONFIG_TEMPLATE) end))
end

-- คืน true ถ้าโหลดไฟล์แยกมาใช้จริง
local function loadUserConfig()
	if type(readfile) ~= "function" or type(isfile) ~= "function" then return false end

	local exists = false
	pcall(function() exists = isfile(USER_CONFIG_FILE) end)
	if not exists then
		writeUserConfig()   -- ยังไม่มี สร้างไฟล์ตัวอย่างให้แก้
		return false
	end

	local ok, chunk = pcall(function() return loadstring(readfile(USER_CONFIG_FILE)) end)
	if not ok or type(chunk) ~= "function" then return false end

	local ok2, data = pcall(chunk)
	if not ok2 or type(data) ~= "table" then return false end

	mergeConfig(Config, data)
	Config.Running = false   -- กันไม่ให้ไฟล์สั่งให้ออกวิ่งเองตอนเปิด
	return true
end

--==================================================================
-- คอนฟิกแบบตั้งก่อนโหลด (_G.HamsterConfig)
--
-- รูปแบบมาตรฐานของฮับที่โหลดจาก URL  ตั้งค่าไว้ก่อนแล้วค่อยเรียกสคริปต์:
--
--   _G.HamsterConfig = { Area = "Cosmic", MoveMode = "step", Gap = 0.15 }
--   loadstring(game:HttpGet("<ลิงก์สคริปต์>"))()
--
-- ใส่เฉพาะคีย์ที่อยากเปลี่ยนก็พอ ที่ไม่ใส่จะใช้ค่าเดิม
-- อันนี้มาท้ายสุด จึงชนะทั้งไฟล์ JSON และไฟล์ Settings.lua
-- เพราะเป็นค่าที่เขียนติดมากับคำสั่งรันโดยตรง = เจตนาชัดที่สุด
--==================================================================
local function loadGlobalConfig()
	local t = genv.HamsterConfig or _G.HamsterConfig
	if type(t) ~= "table" then return false end

	mergeConfig(Config, t)
	Config.Running = false   -- กันไม่ให้สั่งออกวิ่งเองตอนเปิด
	return true
end

local configLoaded = loadConfig()
local userConfigLoaded = loadUserConfig()
local globalConfigLoaded = loadGlobalConfig()

--==================================================================
-- บังคับปิดของที่ทำให้โดนเตะ  ห้ามคอนฟิกใดๆ เปิดได้
--
-- ทำไมต้องบังคับแทนที่จะตั้งเป็นค่าเริ่มต้นเฉยๆ:
--
-- คอนฟิกมาสามชั้น ชั้นท้ายสุดชนะ
--   1) StealAnEgg_Config.json    ไฟล์ที่ UI เซฟไว้ในเครื่องลูกค้า
--   2) StealAnEgg_Settings.lua   ไฟล์ตัวอย่างที่สคริปต์สร้างเอง (ในนั้นเขียน Noclip = true)
--   3) _G.HamsterConfig          loader ที่ลูกค้าก๊อปไปวาง
--
-- ลูกค้าที่ก๊อป loader ไปนานแล้วจะไม่มีคีย์ใหม่อยู่ในนั้นเลย
-- ค่าอันตรายจึงตกไปใช้ของชั้น 1 หรือ 2 ซึ่งเป็น true
-- อาการที่เห็น: "บางคนโดนเตะ บางคนไม่โดน" ทั้งที่รันสคริปต์ตัวเดียวกัน
-- (ยืนยันจากลูกค้าจริง หลังอัปบิลด์เดียวกันให้ทุกคน)
--
-- ของสองอย่างนี้เซิร์ฟเวอร์มองเห็นได้เอง ไม่ต้องพึ่งไคลเอนต์รายงาน:
--   CanCollide = false            replicate ขึ้นเซิร์ฟตรงๆ  = ลายเซ็นโกงที่เช็คง่ายสุด
--   SetStateEnabled(Dead,false)   ขวางการแก้ไขของระบบ -> ระบบยิงรายงานขึ้นเซิร์ฟ
--
-- ปิดตายไว้เลย ใครจะตั้งอะไรมาก็ไม่มีผล  ยอมเสียความยืดหยุ่นแลกกับลูกค้าไม่หลุด
Config.Noclip = false
Config.BlockDeath = false

-- โหมดเคลื่อนที่ต้องเริ่มที่ warp เสมอ ห้ามให้ไฟล์บนดิสก์กำหนด
--
-- เจอจริง 2026-08-16: เครื่องลูกค้ามี StealAnEgg_Settings.lua ค้างอยู่ ในนั้นเขียน MoveMode = "step"
-- วันนั้นเขารันไฟล์ตรงๆ ไม่ได้ผ่าน loader (_G.HamsterConfig = nil) ค่าในไฟล์เลยชนะ
-- ผลคือ step ที่ MoveSpeed 700 บนไอดี WalkSpeed 21 (เพดานถูกกฎ 21*1.1+8 = 31 studs/วินาที)
-- กระโดดทีละ 55 studs = เกินเพดานทุกก้าว -> ตายรัวๆ เก็บไข่ไม่ติดเลยสักใบ
--
-- ระบบปลดเพดาน (Hub.glide + ImpulseContext) มีเฉพาะทาง warp เท่านั้น
-- โหมดอื่นไม่มีตัวคุมระยะต่อเฟรม จึงไม่ปลอดภัยไม่ว่าจะตั้งความเร็วเท่าไหร่
--
-- บังคับตรงนี้ = ชั้น 1/2 (ไฟล์บนดิสก์) กำหนดไม่ได้
-- ปุ่มเลือกโหมดใน UI ยังใช้ได้ปกติ เพราะ UI สร้างทีหลังบรรทัดนี้
Config.MoveMode = "warp"

--==================================================================
-- REMOTES / MODULES
--==================================================================
-- ห้ามรอไม่มีกำหนด  ตั้งเวลาไว้เสมอ
--
-- WaitForChild แบบไม่ใส่เวลา = ถ้าเกมเปลี่ยนชื่อโฟลเดอร์เมื่อไหร่ สคริปต์ค้างตรงนี้ตลอดกาล
-- ไม่ error ไม่ log ไม่มีอะไรเกิดขึ้น ผู้ใช้เห็นแค่ "รันแล้วไม่ขึ้นอะไรเลย"
-- ใส่เวลาไว้ 20 วินาที หมดเวลาแล้วค่อยบอกให้รู้ว่าเกิดอะไรขึ้น
local Net = ReplicatedStorage:WaitForChild("Network", 20)
if not Net then
	warn("[Hamsterdiwa] หา ReplicatedStorage.Network ไม่เจอใน 20 วินาที - เกมอาจเปลี่ยนโครงสร้าง")
	return
end

local function remote(name)
	return Net:FindFirstChild(name, true)
end

local snapF      = remote("Eggs: RequestAreaEggSnapshot")
local carryF     = remote("Eggs: RequestAreaEggCarry")
local placeF     = remote("Eggs: RequestPlaceEgg")
local eggSnapF   = remote("Eggs: RequestRuntimeSnapshot")
local hatchF     = remote("Eggs: RequestHatchEgg")
local hatchEndF  = remote("Eggs: RequestCompleteHatchEgg")
local plotsF     = remote("Plots: RequestState")
local petEquipF  = remote("ActiveAssets: RequestEquip")
local capF       = remote("ActiveAssets: RequestEquipLimit")
local sellF      = remote("ActiveAssets: RequestSell")
local equipBestF = remote("Backpack: EquipBest")
local upgradeE   = remote("Plots: RequestBaseUpgrade")
local settingF   = remote("Settings: Request Update")

-- require ของเกมต้องห่อ pcall เสมอ
--
-- สามบรรทัดนี้เดิมเรียกตรงๆ ถ้าเกมย้าย/เปลี่ยนชื่อโมดูลเมื่อไหร่ (ซึ่งวันนี้เกิดไปแล้วรอบนึง
-- ตอนย้ายระบบกันโกงทั้งชุด) สคริปต์จะ error ตรงนี้แล้วตายทั้งไฟล์
-- ผู้ใช้เห็นแค่ "รันแล้วไม่ขึ้นอะไรเลย" หาสาเหตุไม่ได้
--
-- ห่อไว้แล้วบอกให้รู้ว่าตัวไหนหาย ดีกว่าตายเงียบ
local function need(path, name)
	local ok, mod = pcall(require, path)
	if ok and type(mod) == "table" then return mod end
	warn(("[Hamsterdiwa] โหลดโมดูล %s ของเกมไม่ได้ - เกมอาจเปลี่ยนโครงสร้าง"):format(name))
	return nil
end

local Bases = need(ReplicatedStorage.Directory.Bases, "Bases")
local Save  = need(ReplicatedStorage.Library.Client.Save, "Save")
local AGU   = need(ReplicatedStorage.Library.Util.AssetGenerationUtil, "AssetGenerationUtil")

if not (Bases and Save and AGU) then
	warn("[Hamsterdiwa] ขาดโมดูลของเกม หยุดทำงานเพื่อไม่ให้พังต่อ")
	return
end

--==================================================================
-- STATS / LOG
--==================================================================
local Stats = { cycles = 0, stolen = 0, failed = 0, hatched = 0, sold = 0, upgrades = 0 }
Hub.Stats = Stats   -- เปิดให้อ่านจากข้างนอกได้ ไว้ตรวจผลว่าเก็บติดจริงกี่ใบ

local LogLines = {}

local function comma(n)
	local s = tostring(math.floor(tonumber(n) or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function log(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
	local line = ("[%s] %s"):format(os.date("%H:%M:%S"), table.concat(parts, " "))
	table.insert(LogLines, line)
	if #LogLines > 60 then table.remove(LogLines, 1) end
end

local function recentLog(n)
	n = n or 6
	local out = {}
	for i = math.max(1, #LogLines - n + 1), #LogLines do out[#out + 1] = LogLines[i] end
	return table.concat(out, "\n")
end

--==================================================================
-- ตั้งค่าประหยัดเครื่อง (ใช้ของเกมเอง)
--
-- ยิงผ่าน RemoteFunction "Settings: Request Update" (คีย์, true/false)
-- คีย์ที่มีจริง: SFX · DisableVideos · HideOtherPets · Music · AFK · Trading
-- ทดสอบแล้วได้ผลจริง (Music: true -> false)
--
-- ดีกว่าไปไล่ปิดเงา/พื้นผิวทั้งแมพเอง เพราะวิธีนั้นต้องวน 31,669 instances ตอนโหลด
-- แล้วสะดุดตอนเข้าเกม ส่วนของเกมเองมันจัดการภายในให้ ไม่มีช่วงกระตุก
--==================================================================
local PERF_SETTINGS = {
	HideOtherPets = true,   -- ซ่อนสัตว์คนอื่น = ตัวกินเฟรมอันดับหนึ่ง (13,406 instances)
	DisableVideos = true,   -- ปิดจอวิดีโอในแปลง
	Music         = false,
	SFX           = false,
}

-- เร่งเฟรมด้วยการตัดของที่ไม่ต้องใช้
--
-- สคริปต์ฟาร์มไม่ต้องมองอะไรเลย ภาพสวยๆ คือค่าใช้จ่ายล้วนๆ
-- ตัดสามชั้น: เงา/แสง · พื้นผิวและอนุภาค · การเรนเดอร์ภาพ 3 มิติทั้งหมด
-- ชั้นสุดท้ายให้ผลมากที่สุดแต่จอจะว่างเปล่า เปิดเฉพาะตอนไม่ได้ดูจอ
Hub.fpsBoost = function()
	local n = 0
	pcall(function()
		local L = game:GetService("Lighting")
		L.GlobalShadows = false
		L.FogEnd = 9e9
		L.Brightness = 0
		for _, v in ipairs(L:GetChildren()) do
			if v:IsA("BloomEffect") or v:IsA("BlurEffect") or v:IsA("SunRaysEffect")
			   or v:IsA("ColorCorrectionEffect") or v:IsA("DepthOfFieldEffect") then
				v.Enabled = false
				n = n + 1
			end
		end
	end)
	pcall(function()
		settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
	end)
	pcall(function()
		local T = workspace:FindFirstChildOfClass("Terrain")
		if T then
			T.WaterWaveSize = 0
			T.WaterWaveSpeed = 0
			T.WaterReflectance = 0
			T.WaterTransparency = 0
		end
	end)
	-- ตัดพื้นผิว อนุภาค และเอฟเฟกต์ในฉาก
	--
	-- ไล่ครั้งเดียวตอนเปิด ของใหม่ที่โผล่ทีหลังไม่ตาม เพราะการฟังทุกชิ้น
	-- ที่เพิ่มเข้ามาแพงกว่าประโยชน์ที่ได้ (ฉากนี้มีของเป็นหมื่นชิ้น)
	pcall(function()
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("Decal") or d:IsA("Texture") then
				d.Transparency = 1
				n = n + 1
			elseif d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Smoke")
			    or d:IsA("Fire") or d:IsA("Sparkles") or d:IsA("Beam") then
				d.Enabled = false
				n = n + 1
			elseif d:IsA("BasePart") then
				d.Material = Enum.Material.SmoothPlastic
				d.Reflectance = 0
			end
		end
	end)
	Hub.FpsBoosted = n
	return n
end

-- ปิดการเรนเดอร์ภาพ 3 มิติ  จอจะว่างแต่เฟรมพุ่ง
--
-- executor ส่วนใหญ่มีคำสั่งนี้ ถ้าไม่มีจะถอยไปใช้ผ้าคลุมทึบแทน
-- ซึ่งช่วยน้อยกว่าเพราะเกมยังวาดภาพอยู่ แค่เรามองไม่เห็น
Hub.setBlankScreen = function(on)
	local done = false
	pcall(function()
		local RS = game:GetService("RunService")
		if type(RS.Set3dRenderingEnabled) == "function" then
			RS:Set3dRenderingEnabled(not on)
			done = true
		end
	end)
	if not done then
		pcall(function()
			local parent = (gethui and gethui()) or game:GetService("CoreGui")
			local g = parent:FindFirstChild("HMD_Blank")
			if on then
				if not g then
					g = Instance.new("ScreenGui")
					g.Name = "HMD_Blank"
					g.IgnoreGuiInset = true
					g.DisplayOrder = 9999
					g.ResetOnSpawn = false
					g.Parent = parent
					local f = Instance.new("Frame", g)
					f.Size = UDim2.fromScale(1, 1)
					f.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					f.BorderSizePixel = 0
				end
			elseif g then
				g:Destroy()
			end
		end)
	end
	Hub.BlankOn = on and true or false
	return Hub.BlankOn
end

local function applyPerfSettings()
	if not settingF then return 0 end

	local data = Save.Get(LocalPlayer, false)
	local now = (data and type(data.Settings) == "table") and data.Settings or {}

	local changed = 0
	for key, want in pairs(PERF_SETTINGS) do
		if now[key] ~= want then
			local ok = pcall(function() settingF:InvokeServer(key, want) end)
			if ok then changed += 1 end
			task.wait(0.15)
		end
	end
	if changed > 0 then log(("ตั้งค่าประหยัดเครื่อง %d อย่าง"):format(changed)) end
	return changed
end

--==================================================================
-- ตัวละคร / การเคลื่อนที่
--==================================================================
local function char()
	local c = LocalPlayer.Character
	if not c then return nil end
	local hrp = c:FindFirstChild("HumanoidRootPart")
	local hum = c:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then return nil end
	return c, hrp, hum
end

-- Noclip
-- ในตัวละครมีแค่ HumanoidRootPart ที่ CanCollide = true
-- รังไข่ทั้งรังไม่ชนเลย ตัวที่ขังเราไว้ในวงไข่คือ Guard.Collider (8 x 10 x 7)
-- เปิดเฉพาะตอนเคลื่อนที่ ตอนยืนเฉยๆ ต้องคืนค่าไม่งั้นตกทะลุพื้น
local noclipConn

local function setNoclip(on)
	if on and Config.Noclip then
		if noclipConn then return end
		-- จำรายชื่อชิ้นส่วนไว้ ไม่ไล่ลูกหลานใหม่ทุกเฟรม
		--
		-- ของเดิมเรียก GetDescendants() ทุกเฟรมที่ noclip เปิด
		-- ตัวละครมีหลายสิบถึงร้อยชิ้น (แขนขา หัว เสื้อผ้า accessory)
		-- คูณ 60 เฟรมต่อวินาที = งานมหาศาลโดยไม่จำเป็น
		-- ตัวละครไม่ได้งอกชิ้นส่วนใหม่ทุกเฟรม เก็บไว้ครั้งเดียวพอ
		--
		-- ของใหม่โผล่มาทีหลังก็จับได้ เพราะฟัง DescendantAdded ไว้
		local parts, watch = {}, nil
		local function rebuild()
			parts = {}
			local c = LocalPlayer.Character
			if not c then return end
			for _, d in ipairs(c:GetDescendants()) do
				if d:IsA("BasePart") then parts[#parts + 1] = d end
			end
			if watch then watch:Disconnect() end
			watch = c.DescendantAdded:Connect(function(d)
				if d:IsA("BasePart") then parts[#parts + 1] = d end
			end)
		end
		rebuild()
		Hub.noclipRebuild = rebuild

		noclipConn = RunService.Stepped:Connect(function()
			for i = #parts, 1, -1 do
				local d = parts[i]
				if not d or not d.Parent then
					table.remove(parts, i)
				elseif d.CanCollide then
					d.CanCollide = false
				end
			end
		end)
	else
		if noclipConn then
			noclipConn:Disconnect()
			noclipConn = nil
		end
		-- คืนการชนให้เสมอ ไม่ใช่คืนเฉพาะตอนที่ตัวเองเป็นคนปิด
		--
		-- รันสคริปต์รุ่นเก่าค้างไว้แล้วรันรุ่นใหม่ทับ ค่าที่รุ่นเก่าปิดไว้ยังค้างอยู่
		-- CanCollide = false replicate ขึ้นเซิร์ฟ = ลายเซ็นโกงค้างคาไปเรื่อยๆ
		-- ทั้งที่รุ่นใหม่ไม่ได้สั่งปิดแล้ว  ต้องคืนให้ด้วยมือ
		local c = LocalPlayer.Character
		if c then
			pcall(function()
				local hrp = c:FindFirstChild("HumanoidRootPart")
				if hrp and not hrp.CanCollide then
					hrp.CanCollide = true
					Hub.CollideRestored = (Hub.CollideRestored or 0) + 1
				end
			end)
		end
	end
end

--==================================================================
-- กล้องนิ่ม (แก้อาการภาพกระตุกตอนวาป)
--
-- ตัวละครต้องวาปเป็นก้อนเสมอ ห้ามแก้ ไม่งั้นโดนแอนตี้ชีตลากกลับ
-- แต่ "ภาพที่เห็น" ไม่จำเป็นต้องกระตุกตาม
--
-- วิธี: สร้าง part ล่องหนขึ้นมาตัวหนึ่ง ให้มันไล่ตามตัวละครแบบ lerp
-- แล้วบอกกล้องให้เกาะ part ตัวนั้นแทน (CameraSubject)
-- กล้องดีฟอลต์ของเกมยังทำงานปกติทุกอย่าง หมุน/ซูมได้เหมือนเดิม แค่ตำแหน่งนุ่มขึ้น
--
-- เซิร์ฟเวอร์ไม่เห็นอะไรเปลี่ยนเลย เพราะไม่ได้แตะตำแหน่งตัวละครสักนิด
local camPart, camConn

local function stopSmoothCam()
	if camConn then camConn:Disconnect() camConn = nil end
	local cam = workspace.CurrentCamera
	local c = LocalPlayer.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if cam and hum then pcall(function() cam.CameraSubject = hum end) end
	if camPart then pcall(function() camPart:Destroy() end) camPart = nil end
end

local function startSmoothCam()
	if camConn then return end
	local c, hrp = char()
	if not hrp then return end

	camPart = Instance.new("Part")
	camPart.Name = "EggFarmCamAnchor"
	camPart.Anchored = true
	camPart.CanCollide = false
	camPart.CanQuery = false
	camPart.CanTouch = false
	camPart.Transparency = 1
	camPart.Size = Vector3.new(1, 1, 1)
	camPart.CFrame = CFrame.new(hrp.Position)
	camPart.Parent = workspace

	camConn = RunService.RenderStepped:Connect(function(dt)
		if not Config.SmoothCam then return end
		local cam = workspace.CurrentCamera
		local _, h = char()
		if not cam or not h then return end
		if not camPart or not camPart.Parent then return end

		-- ยิ่งค่าสูงยิ่งตามไว (นิ่งน้อยลง) ยิ่งต่ำยิ่งนุ่ม (ตามช้าลง)
		local a = math.clamp(dt * (tonumber(Config.CamSmooth) or 8), 0, 1)
		camPart.CFrame = camPart.CFrame:Lerp(CFrame.new(h.Position), a)

		-- เกมรีเซ็ต CameraSubject ตอนเกิดใหม่ ต้องยึดคืนทุกเฟรม
		if cam.CameraSubject ~= camPart then cam.CameraSubject = camPart end
	end)
end

-- ความเร็วเป้าหมาย (studs/s) มาจาก ก้าว / พัก เหมือนเดิม
-- เปลี่ยนวิธีเคลื่อนที่แล้วความเร็วไม่เปลี่ยน ยังปรับที่สองค่าเดิม
local function targetSpeed()
	return Config.Step / math.max(Config.Gap, 0.01)
end

--==================================================================
-- มิเตอร์ของระบบตรวจจับในเกม
--
-- ค่าทั้งหมดถอดมาจากโมดูล Config ของชุด CharacterIntegrity ในตัวเกมเอง
-- (Movement · VerticalTrajectory · GroundContact · Correction · State · Rollback)
--
-- หัวใจ: เกมไม่ได้ดูความเร็วเฉลี่ย มันสะสม "คะแนนความผิด" แล้วหักลบเมื่อเราทำตัวดี
--     เกินเพดาน  -> +1.50 ต่อวินาที
--     ไม่เกิน    -> -0.75 ต่อวินาที
--     ถึง 1.35   -> สั่ง Correction ซึ่งจบด้วย Humanoid.Health = 0
--
-- ผลลัพธ์สำคัญ: เกินได้ไม่เกิน 1 ใน 3 ของเวลา แล้วคะแนนจะไม่มีวันถึงเพดาน
-- นี่คือเหตุผลที่โหมด step วิ่ง 550 st/s ได้ตลอดกาล
--   วาป 55 studs ใน 1 tick แล้วนิ่ง 2 ticks = อัตรา 1:2 = 0.75/1.5 พอดี
-- ส่วนโหมดบินลากต่อเนื่องทุก tick เลยบวกรัวเดียวแล้วตายใน ~0.9 วินาที
--==================================================================
local AC = {
	SpeedMultiplier    = 1.22,   -- เพดาน = WalkSpeed x 1.22 + 8
	SpeedFlatAllowance = 8,
}

-- ความเร็วแนวราบที่เกมยอมให้ ณ ตอนนี้ (ขึ้นกับ WalkSpeed ที่อัปมา)
local function legalSpeed()
	local _, _, hum = char()
	local ws = (hum and hum.WalkSpeed) or 16
	return ws * AC.SpeedMultiplier + AC.SpeedFlatAllowance
end


--==================================================================
-- ยึดติดพื้น
--
-- เซิร์ฟฆ่าทันทีถ้าเจอว่า "ลอยอยู่ในโซนเกมเพลย์"
-- ทดสอบยืนยันแล้ว: ลอยนิ่งๆ ที่ +15 ตายที่วินาทีที่ 4.2 · ลอยตอนวิ่งตายทันที HP 100 -> 0
-- ไม่เกี่ยวกับความสูง (+4 ก็ตาย) ไม่เกี่ยวกับความเร็ว
--
-- เลนกลางแมพไม่ได้ราบเท่ากันทุกจุด ถ้าสั่งไปที่ Y คงที่แล้วจุดนั้นพื้นต่ำกว่า
-- ตัวละครจะลอยค้างแล้วโดนฆ่า  เลยต้องยิงเรย์หาพื้นจริงแล้วเกาะไว้ตลอด
--
-- หมายเหตุ: สร้าง "พื้นเสก" ฝั่งเราไม่ช่วย เพราะเซิร์ฟมองไม่เห็น part ที่ client สร้าง
-- มันตัดสินจากโลกฝั่งมันเอง ทางเดียวคือยืนบนพื้นจริงของแมพ
--==================================================================
local GROUND_OFFSET = 3.1   -- HipHeight 2.1 + ครึ่งความสูง root 1

-- หาพื้นที่อยู่ "ใต้จุดที่กำหนด"
--
-- สำคัญมาก: ต้องยิงเรย์จากใกล้ๆ ตัวลงมา ห้ามยิงจากฟ้าลงมา
-- ยิงจาก Y=300 ลงมาจะเจอ "สิ่งแรกที่ต่ำกว่า 300" ซึ่งอาจเป็นหลังคาหรือตัวอาคาร
-- แล้วมันจะยกตัวละครขึ้นไปยืนบนหลังคาแทน (เคยทำให้ลอยไปถึง Y=218 แล้วตายรัวๆ)
local function groundYAt(x, z, fromY, fallback)
	local c = LocalPlayer.Character
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	-- ต้องกรองพื้นเสกออกเอง เพราะตอนนี้มันตั้ง CanQuery = true แล้ว
	-- (ให้ตัวตรวจของเกมมองเห็น) ไม่งั้นเรย์จะเจอพื้นเสกแล้วนึกว่าเป็นพื้นจริง
	params.FilterDescendantsInstances = { c }

	local origin = Vector3.new(x, (fromY or LANE_Y) + 6, z)
	local hit = workspace:Raycast(origin, Vector3.new(0, -250, 0), params)
	if hit then return hit.Position.Y + GROUND_OFFSET end
	return fallback
end

-- ดันตำแหน่งเป้าหมายให้ติดพื้นจริง
local function snapToGround(pos)
	if not Config.GroundSnap then return pos end
	local y = groundYAt(pos.X, pos.Z, pos.Y, pos.Y)
	return Vector3.new(pos.X, y, pos.Z)
end

--------------------------------------------------------------------
-- เคลื่อนที่ด้วย tween
--
-- ขยับต่อเนื่องทุกเฟรม ภาพลื่นกว่าการวาปเป็นก้อนมาก
-- แลกมาด้วยความเสี่ยงโดนดึงกลับสูงกว่า เพราะแอนตี้ชีตวัดระยะต่อเฟรม
-- ถ้าโดนดึงบ่อย ให้เพิ่มค่าพัก (ช้าลง) หรือเพิ่มช่วงออกตัวในแท็บความเร็ว
--------------------------------------------------------------------
local function moveTween(target)
	local _, hrp = char()
	if not hrp then return false end

	target = snapToGround(target)

	local start = hrp.Position
	local dist = (target - start).Magnitude
	if dist < 1 then return true end

	local dur = dist / targetSpeed()
	local tw = TweenService:Create(hrp,
		TweenInfo.new(dur, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut),
		{ CFrame = CFrame.new(target) })
	tw:Play()

	local deadline = os.clock() + dur + 2
	while os.clock() < deadline do
		if not Config.Running or not alive() then tw:Cancel() return false end

		local _, h, hum = char()
		if not h then tw:Cancel() return false end
		if not Hub.stillUp(hum) then tw:Cancel() return false end   -- ตายจริง เลิกวิ่ง

		-- แรงตกค้างจะสู้กับ tween แล้วทำให้สั่น ต้องล้างทุกจังหวะ
		h.AssemblyLinearVelocity = Vector3.zero
		h.AssemblyAngularVelocity = Vector3.zero

		-- หลุดลอยระหว่างทาง = โดนฆ่าใน ~4 วิ ดึงลงติดพื้นทันที
		if Config.GroundSnap then
			local gy = groundYAt(h.Position.X, h.Position.Z, h.Position.Y, nil)
			if gy and math.abs(h.Position.Y - gy) > 5 then
				h.CFrame = CFrame.new(h.Position.X, gy, h.Position.Z)
			end
		end

		-- โดนเซิร์ฟลากกลับ = ระยะถึงเป้าไกลขึ้นแทนที่จะใกล้ลง
		-- ต้องเลิกทันที ถ้าฝืนวิ่งต่อจะกลายเป็นสู้กับแอนตี้ชีตแล้วโดนลากรัวๆ
		if (h.Position - target).Magnitude > (start - target).Magnitude + 120 then
			tw:Cancel()
			log("โดนลากกลับ - พักแล้วเริ่มใหม่ (ลองเพิ่มค่าพัก หรือเพิ่มช่วงออกตัว)")
			task.wait(2)
			return false
		end

		if tw.PlaybackState == Enum.PlaybackState.Completed then break end
		task.wait()
	end
	tw:Cancel()

	local _, done = char()
	return done ~= nil and (done.Position - target).Magnitude < 25
end

--------------------------------------------------------------------
-- เคลื่อนที่เป็นก้อน (step)
--
-- วาปทีละ <=60 studs แล้วพัก  ภาพกระตุกแต่เซิร์ฟยอมรับความเร็วสูงกว่ามาก
-- เพราะเฟรมส่วนใหญ่ขยับ 0 มีแค่เฟรมเดียวที่กระโดด ซึ่งยังต่ำกว่าเพดานการวาปครั้งเดียว
-- ใช้คู่กับ "กล้องนิ่ม" แล้วภาพที่เห็นจะนิ่งทั้งที่ตัวจริงกระโดด
--------------------------------------------------------------------
local function moveStep(target)
	local guard = 0
	while true do
		if not Config.Running or not alive() then return false end
		local _, hrp, hum = char()
		if not hrp then return false end
		if not Hub.stillUp(hum) then return false end   -- ตายจริง เลิกวิ่ง

		local delta = target - hrp.Position
		if delta.Magnitude <= Config.Step then
			hrp.CFrame = CFrame.new(snapToGround(target))
			hrp.AssemblyLinearVelocity = Vector3.zero
			break
		end

		-- ทุกก้าวต้องเกาะพื้นจริง ไม่งั้นจุดที่พื้นต่ำกว่าจะกลายเป็นลอย แล้วโดนฆ่า
		--
		-- ก้าวและจังหวะพักต้องอยู่ใต้เพดานความเร็วเดียวกับ Hub.glide
		-- ของเดิม Step 55 / Gap 0.10 = 550 st/s ซึ่งเคยผ่านสบายก่อนเกมอัปเดต
		-- ตอนนี้ตายตั้งแต่ก้าวที่ 2-4 เพราะเซิร์ฟเป็นคนตัดสินแล้ว
		-- ทั้งก้าวและจังหวะต้องอยู่ใต้เพดาน "ระยะต่อ 1 tick" ของระบบ (ดู Hub.legalSpeed)
		-- 1 tick = 0.05 วิ  ระยะที่ยอมให้ต่อ tick = ความเร็วเพดาน x 0.05 = ราว 7-8 studs
		-- ของเดิม Step 55 / Gap 0.10 = กระโดด 55 studs ในเฟรมเดียว เกินไป 7 เท่า
		local spd = Hub.legalSpeed(hum)
		if os.clock() < (Hub.SlowUntil or 0) then spd = spd * 0.6 end
		local hop = math.min(Config.Step, spd * 0.05)
		hrp.CFrame = CFrame.new(snapToGround(hrp.Position + delta.Unit * hop))
		hrp.AssemblyLinearVelocity = Vector3.zero
		task.wait(math.min(Config.Gap, hop / spd))

		local _, after = char()
		if after and (after.Position - target).Magnitude > delta.Magnitude + 120 then
			log("โดนลากกลับ - พักแล้วเริ่มใหม่ (ลองเพิ่มค่าพัก)")
			task.wait(2)
			return false
		end

		guard += 1
		if guard > 500 then return false end
	end
	task.wait(Config.Gap)

	local _, hrp2 = char()
	return hrp2 ~= nil and (hrp2.Position - target).Magnitude < 25
end


--==================================================================
-- ปลดตัวแก้ไขฝั่งไคลเอนต์
--
-- สิ่งที่ฆ่าเราตลอดมาไม่ใช่เซิร์ฟเวอร์ แต่เป็นโค้ดเกมในเครื่องเราเอง
-- โมดูล Correction ของเกมสั่ง Humanoid.Health = 0 ใส่ตัวเอง
-- แล้วค่อยยิงไปบอกเซิร์ฟว่า "แก้ไขแล้ว" ทีหลัง
--
-- วัดจริงกับไข่ที่ห่าง 602 studs:
--   เปิดอยู่  วาปแล้วตายใน 24 มิลลิวินาที และโดนลากกลับที่เดิม
--   ปิดแล้ว   เลือดเต็มตลอด ตำแหน่งอยู่นิ่ง เก็บไข่ได้ ไปกลับรอบละ ~620ms
--
-- หาโดยดู "ลายเซ็นของฟิลด์" ไม่ใช่ชื่อโมดูล เพราะโมดูลถูกรวมอยู่ในสคริปต์ก้อนใหญ่
-- ไม่มีตัวตนในต้นไม้ให้ค้นด้วยชื่อ
--
-- ไม่ปิด Enabled ทั้งตัว ปิดเฉพาะส่วนลงมือ
-- เพราะระบบเดียวกันดูแลเรื่องอื่นของตัวละครด้วย ปิดหมดอาจพังจุดที่มองไม่เห็น
--==================================================================
local acPatched = false

-- ตรวจว่าตัวรันมีอะไรบ้าง  เอาไว้บอกผู้ใช้เฉยๆ ไม่ได้เอาไปตัดสินใจอะไร
--
-- เหลือเฉพาะตัวที่สคริปต์ใช้จริง  ตัวที่เลิกใช้แล้วไม่ต้องแม้แต่จะเอ่ยถึง
--
-- แค่การ "เอ่ยชื่อ" ฟังก์ชันอย่าง ฟังก์ชันครอบทับ/ปลดล็อกตาราง ในโค้ด
-- ก็เป็นลายเซ็นให้ตัวตรวจจับแบบสแกนข้อความจับได้แล้ว
-- ในเมื่อไม่ได้ใช้ ก็ไม่มีเหตุผลให้เก็บชื่อไว้ในไฟล์เลยสักตัว
do
	local function has(v) return type(v) == "function" end
	Hub.Caps = {
		getgc       = has(getgc),
		getupvalues = type(debug) == "table" and has(debug.getupvalues),
		gethui      = has(gethui),
		writefile   = has(writefile),
		executor    = (has(identifyexecutor) and select(1, pcall(identifyexecutor)) and identifyexecutor()) or "ไม่ทราบ",
	}
	-- เร่งความเร็วได้ไหม  ต้องอ่านหน่วยความจำได้เท่านั้น ไม่ต้องแก้อะไรของเกม
	Hub.Caps.canBoost = Hub.Caps.getgc and Hub.Caps.getupvalues
end

-- ปิดสถานะตายของตัวละคร  ปิดเป็นค่าเริ่มต้นแล้ว (ดู Config.BlockDeath)
Hub.blockLocalDeath = function()
	-- ปิดเป็นค่าเริ่มต้นแล้ว ดูเหตุผลยาวๆ ที่ Config.BlockDeath
	-- สรุปสั้นๆ: ขวางการแก้ไขของระบบ = ระบบยิงรายงานขึ้นเซิร์ฟ = โดนเตะ
	if Config.BlockDeath ~= true then
		Hub.DeathBlocked = false
		-- คืนสถานะให้ด้วย ไม่ใช่แค่ไม่ปิดเพิ่ม
		--
		-- รันสคริปต์รุ่นเก่าค้างไว้แล้วมารันรุ่นใหม่ทับ ค่าที่รุ่นเก่าปิดไว้ยังค้างอยู่
		-- ตัวละครจะตายไม่ลงต่อไปเรื่อยๆ ทั้งที่รุ่นใหม่ไม่ได้สั่งปิดแล้ว
		local c0 = LocalPlayer.Character
		local h0 = c0 and c0:FindFirstChildOfClass("Humanoid")
		if h0 then
			pcall(function()
				if not h0:GetStateEnabled(Enum.HumanoidStateType.Dead) then
					h0:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
					Hub.DeathRestored = (Hub.DeathRestored or 0) + 1
				end
			end)
		end
		return false
	end
	local c = LocalPlayer.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if not hum then return false end
	local ok = pcall(function()
		hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	end)
	if ok then Hub.DeathBlocked = true end
	return ok
end

-- [ลบทิ้งหมดแล้ว] เคยมีชุด "ปะระบบกันโกง" อยู่ตรงนี้ราว 120 บรรทัด
--
-- ที่เคยทำ: หาตารางเกณฑ์ใน getgc แล้ว ปลดล็อกตารางแล้วปิด CorrectionsEnabled
--           แก้ upvalue ค่า 1.35 เป็นอนันต์
--           ครอบทับ AdoptCorrectionBaseline / AdoptTeleportBaseline /
--           AdoptPostImpulseBaseline / requestControlledRecovery ให้เป็น noop
--
-- ตายหมดแล้วหลังเกมอัปเดต 2026-08-16 และแย่กว่าไม่ทำ:
--   · เกมเรียก Adopt*Baseline เองตอนตัวละครเกิดใหม่ พอ noop ทิ้ง = ตายวนไม่จบ
--   · ระบบแก้ไขไม่สำเร็จ -> ยิง "ClientCharacter: IntegrityViolation" -> โดนเตะ
--   · ต่อให้ปะผ่านก็ไม่ช่วย เพราะคนตัดสินตำแหน่งคือเซิร์ฟเวอร์ ไม่ใช่ไคลเอนต์
--
-- ลบออกทั้งหมดแทนที่จะเก็บไว้แล้วให้คืน false เฉยๆ เพราะ:
--   1) แค่มีชื่อ ฟังก์ชันครอบทับ/ปลดล็อกตารางของเกม อยู่ในไฟล์
--      ก็เป็นลายเซ็นให้ตัวตรวจแบบสแกนข้อความจับได้
--   2) โค้ดตายที่ยังเรียกฟังก์ชันของตัวรัน = ตัวรันที่ไม่มีฟังก์ชันนั้นอาจพังตอนโหลด
--   3) เก็บไว้ก็มีแต่คนอ่านแล้วเข้าใจผิดว่ายังใช้อยู่
--
-- ตอนนี้ความปลอดภัยมาจากการคุมความเร็ว (Hub.glide) อย่างเดียว
-- เหลือไว้เป็นฟังก์ชันเปล่าเพราะโค้ดส่วนอื่นยังเรียกอยู่หลายที่
local function patchAntiCheat()
	pcall(Hub.blockLocalDeath)
	-- ดันเกณฑ์สั่งแก้ไขเป็นอนันต์ (ดู Hub.liftThreshold)
	-- ทำครั้งเดียวพอ ตัวมันเช็ค Hub.ThresholdLifted ให้แล้ว ไม่กวาดซ้ำ
	pcall(Hub.liftThreshold)
	acPatched = true
	return true
end

-- ปะใหม่ทุกครั้งที่เกิดใหม่
--
-- โมดูลของเกมสร้างสถานะชุดใหม่ตอนตัวละครโหลด ค่าที่เราตั้งไว้รอบก่อนหายไป
-- ถ้าไม่ปะซ้ำ รอบถัดไปจะวาปแล้วตายทันทีเหมือนเดิม
-- ผูกกับรุ่นด้วย ไม่งั้นสคริปต์รุ่นเก่าที่ค้างอยู่จะแย่งกันปะ
LocalPlayer.CharacterAdded:Connect(function()
	if genv.EGG_FARM_GEN ~= GEN then return end
	acPatched = false
	if Hub.noclipRebuild then pcall(Hub.noclipRebuild) end   -- ตัวละครใหม่ ชิ้นส่วนชุดใหม่
	-- ตัวละครใหม่ = โมดูลสร้างค่าชุดใหม่ ต้องดันเกณฑ์ใหม่
	Hub.ThresholdLifted = false
	Hub.patchTries = 0
	pcall(Hub.blockLocalDeath)   -- Humanoid ตัวใหม่ ต้องปิดสถานะตายใหม่ทันที
	-- ปะทันทีรอบหนึ่งก่อน ไม่งั้นช่วง 1 วินาทีแรกหลังเกิดใหม่ยังไม่มีการปะ
	-- ลูปอาจวาปในช่วงนั้นพอดีแล้วตายซ้ำทันที
	pcall(patchAntiCheat)
	task.wait(1)
	pcall(patchAntiCheat)   -- ปะซ้ำหลังโมดูลโหลดครบ
end)

-- วาปได้ไหมตอนนี้
--
-- ห้ามวาปถ้ายังปลดไม่สำเร็จ ไม่งั้นตายทันทีตั้งแต่ก้าวแรก
-- executor บางตัวไม่มี ฟังก์ชันอ่าน/ปลดล็อกหน่วยความจำ จะปะไม่ได้ โหมด auto จะถอยไป tween ให้
-- ปะซ้ำเป็นระยะ ไม่ใช่ปะครั้งเดียวแล้วเชื่อธงไปตลอด
--
-- ของเดิม: ปะสำเร็จ -> ตั้ง acPatched = true -> ไม่เช็คอีกเลย
-- ถ้าเกมสร้างโมดูลชุดใหม่ระหว่างทาง (เกิดได้ตอนสลับกลางวัน-กลางคืน)
-- การปะจะหลุดแต่ธงยังบอกว่าปะแล้ว = วาปทั้งที่ไม่มีการปะ = โดนลากกลับ
-- อาการที่เห็นคือ "วาปไปข้างหน้านิดเดียวแล้วเด้งกลับ ไม่ถึงไข่"
--
-- การปะใช้เวลาไม่ถึงมิลลิวินาทีถ้าปะไว้แล้ว (แค่เขียนทับค่าเดิม) จึงทำถี่ได้
local lastPatchAt = 0

local function warpReady()
	if not acPatched then
		-- จำกัดความถี่แม้ตอนยังปะไม่ติด
		--
		-- patchAntiCheat สแกน getgc(true) สองรอบ ซึ่งไล่ทุกอ็อบเจกต์ในหน่วยความจำ
		-- เครื่องแรงใช้ 148ms เครื่องช้าหรือมือถือใช้เป็นวินาที
		-- หลังตัวละครตาย ธงถูกล้างเป็นเท็จ ทุกการวาปจึงสั่งสแกนใหม่
		-- ลูปวนเร็วๆ ตอนตาย = สแกนรัวๆ = เกมค้างสนิท
		-- (อาการที่ผู้ใช้เจอ: ค้างตอนจะวาป และค้างตอนตาย)
		--
		-- ปะไม่ติดก็รออีก 3 วินาทีค่อยลองใหม่ ไม่ได้ช้าลงในทางปฏิบัติ
		-- เพราะถ้าสแกนรอบแรกไม่เจอ สแกนซ้ำทันทีก็ไม่เจอเหมือนกัน
		-- ถอยห่างขึ้นเรื่อยๆ แล้วเลิกลอง
		--
		-- การปะสแกน getgc(true) สองถึงสามรอบ รอบละ 33,000 ฟังก์ชัน
		-- เครื่องที่ปะไม่ติดจะวนสแกนทุก 3 วินาทีตลอดไป แม้ตอนยืนเฉยๆ
		-- (ผู้ใช้เจอ: รันสคริปต์เฉยๆ ไม่ได้วาป ก็ค้างแล้ว)
		--
		-- ลองไม่ได้สิบครั้งแปลว่าเครื่องนี้ปะไม่ได้จริง เลิกลองไปเลย
		-- ยังทำงานได้เพราะมีตาข่ายกันตายอีกสองชั้น (ปิดสถานะตาย + ดึงเลือดกลับ)
		-- ล้างตัวนับตอนตัวละครเกิดใหม่ เพราะโมดูลสร้างชุดใหม่จริง
		local tries = Hub.patchTries or 0
		if tries >= 10 then return false end

		local base = math.max(1, tonumber(Config.PatchRetryGap) or 3)
		local gap = math.min(60, base * (2 ^ math.min(tries, 5)))
		if os.clock() - lastPatchAt < gap then return false end

		lastPatchAt = os.clock()
		Hub.patchTries = tries + 1
		patchAntiCheat()
		if acPatched then Hub.patchTries = 0 end
		return acPatched
	end

	local every = math.max(1, tonumber(Config.RepatchEvery) or 30)
	if os.clock() - lastPatchAt >= every then
		lastPatchAt = os.clock()
		patchAntiCheat()
	end
	return acPatched
end

-- เปิดสถานะออกมาให้ตรวจได้จากข้างนอก เวลาไล่ปัญหาจะได้ไม่ต้องเดา
Hub.Debug = Hub.Debug or {}
function Hub.Debug.warpState()
	return {
		acPatched = acPatched,
		warpReadyNow = warpReady(),
		moveMode = tostring(Config.MoveMode),
		requirePatch = Config.WarpRequirePatch,
	}
end

--==================================================================
-- วาป
--
-- เฟรมเดียวถึงเลย ไม่มีการไล่ก้าว
-- ใช้ได้ต่อเมื่อปลดตัวแก้ไขสำเร็จแล้วเท่านั้น
--==================================================================
local fieldIsFresh   -- ตัวจริงอยู่ใต้ isResetting ประกาศไว้ก่อนเพราะ moveWarp ต้องใช้

-- ตรึงตำแหน่งไว้เบื้องหลังระหว่างที่คำสั่งกำลังเดินทางไปเซิร์ฟ
--
-- carry เป็น InvokeServer ซึ่งบล็อกอยู่ ~230ms กว่าจะได้คำตอบ
-- ช่วงรีเซ็ตเราจะโดนดีดกลับเซฟโซนภายใน 0.15 วิ
-- แปลว่าตอนคำสั่งไปถึงเซิร์ฟ เซิร์ฟเห็นเรายืนอยู่เซฟโซนแล้ว = ปฏิเสธ
-- ต้องมีคนคอยเขียนตำแหน่งทับไว้ตลอดจนกว่าคำตอบจะกลับมา
-- เก็บสถานะไว้บน Hub ไม่ประกาศ local ใหม่
--
-- Luau จำกัดตัวแปร local ระดับบนสุดไว้ที่ 200 ตัว ไฟล์นี้ใช้ไป 198 แล้ว
-- เพิ่มอีกสามตัวเมื่อไหร่คอมไพล์ไม่ผ่านทั้งไฟล์ทันที และไม่มีข้อความบอกชัดๆ
-- อาการคือรันแล้วเงียบ สคริปต์เก่ายังวิ่งอยู่ เข้าใจผิดว่าโค้ดใหม่ไม่ได้ผล
-- (เสียเวลาไล่หลายรอบมาแล้ว ถ้าจะเพิ่มของใหม่ให้แขวนไว้บน Hub แบบนี้)
-- ตรึงตำแหน่งไว้ตอนกล่องขาวขึ้น  นี่คือตัวที่ทำให้ "ทะลุกล่องไปเก็บไข่ได้"
--
-- ช่วงกล่องขึ้น เกมเขียนพิกัดเรากลับเซฟโซนทุกเฟรม
-- (วัดไว้: กล่องขึ้น = เด้งกลับ x513 ทุกเฟรม · กล่องไม่ขึ้น = ตรึงอยู่สบาย 2.6 วิ)
-- ต้องเขียนทับเป็นคนสุดท้ายของเฟรมถึงจะอยู่ได้
--
-- เคยปิดตัวนี้ไปเพราะเข้าใจผิดว่ามันทำให้โดนเตะ
-- ตัวจริงคือ บริการจำลองอินพุตของ CoreScript ซึ่งถอดออกไปแล้ว
-- (เทสแยกยืนยัน: เรียก บริการจำลองอินพุต เฉยๆ โดนเตะใน 10 วิ · ตรึงอย่างเดียวไม่โดน)
--
-- และรอบนี้ตรึงพร้อมกับเปิด ImpulseContext ไปด้วยทุกเฟรม
-- ต่างจากของเดิมที่ตรึงเปล่าๆ แล้วไปสู้กับระบบตรงๆ
-- คราวนี้ระบบไม่ได้มองว่าเราผิดตั้งแต่แรก เลยไม่มีการ "แก้ไขที่ล้มเหลว" ให้มันรายงาน
Hub.PinPos, Hub.PinUntil = nil, 0
Hub.pinAt = function(pos, dur)
	if Config.PinHold == false then
		Hub.PinSkipped = (Hub.PinSkipped or 0) + 1
		return
	end
	Hub.PinPos = pos
	Hub.PinUntil = os.clock() + dur
end

-- เขียนพิกัดให้เป็นคนสุดท้ายของเฟรม
--
-- ตรึงที่ Heartbeat อย่างเดียวไม่พอตอนกล่องขึ้น เกมเขียนทับทีหลังเรา
-- (วัดจริง: วาปไปถึง x2818 แล้วเฟรมถัดมาอยู่ x513 ทุกครั้งตอนกล่องขึ้น
--  แต่ตอนกล่องไม่ขึ้น ตรึงอยู่ได้สบาย 2.6 วินาทีไม่ขยับ)
--
-- BindToRenderStep ที่ priority Last ทำงานหลังโค้ดของเกมในเฟรมเดียวกัน
-- เขียนทั้งสองจังหวะ โอกาสที่ค่าของเราเป็นค่าสุดท้ายจึงสูงสุด
pcall(function()
	game:GetService("RunService"):BindToRenderStep(
		"HMD_Pin", Enum.RenderPriority.Last.Value + 1, function()
			if not Hub.PinPos or os.clock() >= (Hub.PinUntil or 0) then return end
			local c = LocalPlayer.Character
			local h = c and c:FindFirstChild("HumanoidRootPart")
			if h then
				-- เปิดโหมดยกเว้นไปด้วยทุกเฟรม ระบบจะได้ไม่มองว่าเราผิดตั้งแต่แรก
				-- ต่างจากของเดิมที่ตรึงเปล่าๆ แล้วสู้กับตัวแก้ไขตรงๆ
				if Hub.armImpulse then pcall(Hub.armImpulse, h) end
				h.CFrame = CFrame.new(Hub.PinPos)
				h.AssemblyLinearVelocity = Vector3.zero
			end
		end)
end)

task.spawn(function()
	while true do
		task.wait()
		if not alive() then
			pcall(function() game:GetService("RunService"):UnbindFromRenderStep("HMD_Pin") end)
			break
		end
		if Hub.PinPos and os.clock() < Hub.PinUntil then
			local ok = pcall(function()
				local c = LocalPlayer.Character
				local h = c and c:FindFirstChild("HumanoidRootPart")
				if h then
					h.CFrame = CFrame.new(Hub.PinPos)
					h.AssemblyLinearVelocity = Vector3.zero
				end
			end)
			if not ok then Hub.PinPos = nil end
		end
	end
end)

--==================================================================
-- ตัวเฝ้าลูกวิ่ง
--
-- ลูกวิ่งในแปลงเป็นพื้นเลื่อน ยืนโดนแล้วโดนพาไถลเรื่อยๆ ออกเองไม่ได้
-- คนเล่นจริงต้องกด space bar ถึงจะหลุด (ผู้ใช้เจอซ้ำหลายรอบ)
--
-- โครงสร้างจริงในเกม: workspace.Plots.<เลขแปลง>.TreadmillBottom (7 อัน)
-- ขนาดราว 8.5 x 13.4 studs ที่ y=68  ตัวที่ใกล้จุดกลางที่สุดห่างแค่ 14.9 studs
--
-- บทเรียนจากการทดสอบ: ห้ามกระโดดมั่ว
-- เคยสั่งกระโดดรัว 5 ครั้งโดยไม่ตรึงตำแหน่ง ตัวร่วงตกแมพตาย
-- (วัดจริง y ลดจาก 65 -> 52 -> -12 -> -130 -> -300)
-- ต้องกระโดดพร้อมเขียนตำแหน่งตรึงทันที และเฉพาะตอนยืนบนมันจริงเท่านั้น
--==================================================================
local treadCache, treadAt = nil, 0
local function treadmills()
	if treadCache and os.clock() - treadAt < 30 then return treadCache end
	local list = {}
	local plots = workspace:FindFirstChild("Plots")
	if plots then
		for _, plot in ipairs(plots:GetChildren()) do
			local t = plot:FindFirstChild("TreadmillBottom")
			if t and t:IsA("BasePart") then list[#list + 1] = t end
		end
	end
	treadCache, treadAt = list, os.clock()
	return list
end

-- เช็คในระบบพิกัดของตัวลูกวิ่งเอง เพราะมันเป็นสี่เหลี่ยมผืนผ้า ไม่ใช่วงกลม
-- และต้องดูความสูงด้วย ไม่งั้นลอยอยู่เหนือมัน 50 studs ก็จะนับว่าติด
Hub.onTreadmill = function(pos)
	for _, t in ipairs(treadmills()) do
		local half = t.Size * 0.5
		local lp = t.CFrame:PointToObjectSpace(pos)
		if math.abs(lp.X) <= half.X + 2 and math.abs(lp.Z) <= half.Z + 2
			and lp.Y > -3 and lp.Y < 8 then
			return true, t
		end
	end
	return false, nil
end

-- ปลดออกจากลูกวิ่ง: กระโดดตัดสถานะ แล้วตรึงไว้นอกขอบทันที
Hub.unstickTreadmill = function()
	local c = LocalPlayer.Character
	local hrp = c and c:FindFirstChild("HumanoidRootPart")
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if not (hrp and hum) or hum.Health <= 0 then return false end

	local on, part = Hub.onTreadmill(hrp.Position)
	if not on then return false end

	-- หาจุดนอกขอบด้านที่ใกล้ที่สุด แล้วยึดตรงนั้น
	local safe = hrp.Position
	if part then
		local half = part.Size * 0.5
		local lp = part.CFrame:PointToObjectSpace(hrp.Position)
		local outZ = (half.Z + 6) * (lp.Z >= 0 and 1 or -1)
		safe = part.CFrame:PointToWorldSpace(Vector3.new(lp.X, lp.Y, outZ))
	end

	pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
	for _ = 1, 10 do
		if not (hrp.Parent and hum.Health > 0) then break end
		pcall(function()
			hrp.CFrame = CFrame.new(safe)
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
		end)
		task.wait(0.06)
	end
	Hub.Unstuck = (Hub.Unstuck or 0) + 1
	log("ปลดจากลูกวิ่งแล้ว")
	return true
end

--==================================================================
-- ปลดสถานะลูกวิ่งค้าง
--
-- อาการ: วิ่งผ่านลูกวิ่งแล้วเกมยังนับว่าเรา "อยู่บนลูกวิ่ง" ตลอดไป
-- ถึงจะวาปออกไปไกลเป็นพันๆ studs ก็ยังได้แต้มความเร็ว +2 ทุกวินาที
-- ผู้ใช้เห็นเป็นไอคอนรองเท้าลอยรอบตัวไม่หยุด และเก็บไข่ไม่ติด
--
-- ตัวชี้วัดที่ใช้ตรวจ: Humanoid.WalkSpeed ไต่ขึ้นเรื่อยๆ
-- (วัดจริง 21.3 -> 52.7 -> 54.4 -> 58.6 -> 61.9 -> 62.4 ตลอดทั้งรอบ)
-- ตรวจจากตำแหน่งไม่ได้ เพราะสคริปต์เราพาตัวออกมาไกลแล้วแต่สถานะยังค้าง
--
-- วิธีปลด: กระโดดให้ "ลอยพ้นพื้นจริง"
-- วัดเทียบแล้ว:
--   กระโดดแล้วตรึง CFrame ทันที -> ไม่เข้า Freefall -> แต้มยังขึ้น +108/6วิ  ไม่หลุด
--   กระโดดแล้วปล่อยลอยเอง       -> Freefall x8 -> แต้มเหลือ +6/6วิ          หลุด
-- ต้องหยุดเขียน CFrame ระหว่างนั้น ไม่งั้นตัวไม่มีวันพ้นพื้น
local lastWS, wsRose, lastFixAt = nil, 0, 0

Hub.treadmillStuck = function()
	local c = LocalPlayer.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then lastWS = nil return false end
	local ws = hum.WalkSpeed
	if lastWS and ws > lastWS + 0.002 then
		wsRose = wsRose + 1
	elseif lastWS and ws <= lastWS then
		wsRose = 0
	end
	lastWS = ws
	return wsRose >= 4   -- ขึ้นติดกัน 4 ครั้ง (ราว 4 วินาที) = ค้างแน่
end

Hub.clearTreadmillState = function()
	if os.clock() - lastFixAt < 12 then return false end   -- อย่าทำถี่เกิน
	local c = LocalPlayer.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	local hrp = c and c:FindFirstChild("HumanoidRootPart")
	if not (hum and hrp) or hum.Health <= 0 then return false end

	-- ห้ามกระโดดตรงขอบ  ยิงเรย์ลงหาพื้นก่อน ไม่เจอพื้นก็ไม่ทำ
	-- (เคยกระโดดตรงขอบแปลงแล้วร่วงตกแมพตาย y 65 -> -300)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { c }
	local hit = workspace:Raycast(hrp.Position, Vector3.new(0, -40, 0), params)
	if not hit then return false end

	lastFixAt = os.clock()
	wsRose = 0
	Hub.JumpHold = os.clock() + 2.2   -- บอก glide ให้หยุดเขียน CFrame ชั่วคราว
	Hub.Phase = "ปลดสถานะลูกวิ่ง"

	pcall(function()
		hum.Jump = true
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
	end)
	-- รอให้ลอยพ้นพื้นจริงแล้วลงพื้น ห้ามเขียน CFrame ระหว่างนี้เด็ดขาด
	local t0 = os.clock()
	while os.clock() - t0 < 2 do
		local st = hum:GetState()
		if st == Enum.HumanoidStateType.Landed and os.clock() - t0 > 0.5 then break end
		task.wait(0.05)
	end
	Hub.JumpHold = 0
	Hub.TreadFixed = (Hub.TreadFixed or 0) + 1
	log("ปลดสถานะลูกวิ่งแล้ว")
	return true
end

-- กดกระโดดให้เองตอนค้าง  ไม่ต้องรู้ว่าสถานะชื่ออะไร
--
-- ผู้ใช้อธิบายอาการไว้ชัด: ติดสถานะแล้วขายังขยับอยู่ วาปไปเก็บไข่ไม่ติด
-- ต้องกด space bar เองถึงจะหลุด
--
-- ตรวจหาตัวสถานะแล้วไม่เจอ: RagdollEndTime เป็นของเก่าหมดอายุ · MoveDirection = 0
-- PlatformStand/Sit = false · ไม่มี attribute บนตัวละครหรือ Humanoid เลย
-- เลยไม่ตรวจว่า "ติดอะไร" แต่ตรวจว่า "ไปต่อไม่ได้" ซึ่งวัดได้แน่นอนกว่า
--
-- เงื่อนไข: สคริปต์บอกว่ากำลังเดินทางอยู่ แต่ตำแหน่งแทบไม่ขยับเกิน 4 วินาที
-- แล้วกระโดดหนึ่งครั้ง (ไม่รัว) พร้อมตรึงตำแหน่งกันร่วงตกขอบ
local stuckSince, lastStuckPos, lastJumpAt = nil, nil, 0
Hub.unstickStalled = function()
	local c = LocalPlayer.Character
	local hrp = c and c:FindFirstChild("HumanoidRootPart")
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if not (hrp and hum) or hum.Health <= 0 then
		stuckSince, lastStuckPos = nil, nil
		return false
	end

	-- นับเฉพาะตอนที่ "ควรจะกำลังเดินทาง"
	local ph = tostring(Hub.Phase or "")
	local travelling = ph:find("วาป") ~= nil or ph:find("กลับ") ~= nil
	local p = hrp.Position
	if not travelling then
		stuckSince, lastStuckPos = nil, p
		return false
	end

	if lastStuckPos and (p - lastStuckPos).Magnitude < 3 then
		stuckSince = stuckSince or os.clock()
	else
		stuckSince = nil
	end
	lastStuckPos = p

	if not stuckSince or (os.clock() - stuckSince) < 4 then return false end
	if os.clock() - lastJumpAt < 3 then return false end   -- อย่ากระโดดรัว

	lastJumpAt = os.clock()
	stuckSince = nil
	pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
	-- ตรึงไว้ที่เดิมทันที ห้ามปล่อยลอย (เคยทดสอบแล้วกระโดดตรงขอบทำให้ร่วงตกแมพ)
	local hold = p
	for _ = 1, 6 do
		if not (hrp.Parent and hum.Health > 0) then break end
		pcall(function()
			hrp.CFrame = CFrame.new(hold)
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
		end)
		task.wait(0.05)
	end
	Hub.JumpUnstuck = (Hub.JumpUnstuck or 0) + 1
	log("ค้างเกิน 4 วินาที - กดกระโดดตัดสถานะ")
	return true
end

-- เฝ้าเบื้องหลัง  ปลดให้เองไม่ต้องรอใครสั่ง
task.spawn(function()
	while true do
		task.wait(1)
		if genv.EGG_FARM_GEN ~= GEN then break end   -- รุ่นใหม่มาแล้ว เลิกเฝ้า
		if Config.Running then
			-- ลูกวิ่งค้าง: ตรวจจาก WalkSpeed ที่ไต่ขึ้นไม่หยุด แล้วกระโดดปลด
			if Config.TreadmillWatch ~= false then
				if Hub.treadmillStuck() then pcall(Hub.clearTreadmillState) end
				pcall(Hub.unstickTreadmill)
			end
			if Config.StallWatch ~= false then pcall(Hub.unstickStalled) end
		end
	end
end)

-- ยังไปต่อได้ไหม  ใช้ร่วมทุกโหมดการเคลื่อนที่
--
-- เดิม warp มีตรรกะนี้อยู่ตัวเดียว ส่วน step/tween/fly เจอเลือด 0 แล้วเลิกทันที
-- ทั้งที่เราปิดสถานะตายไว้ = เลือด 0 ไม่ได้แปลว่าตาย ตัวละครยังขยับได้ปกติ
-- ผลคือโหมดเดินค้างกลางทางทุกครั้งที่โดนกดเลือด ต่างจาก warp ที่ไปต่อได้
-- ดึงเลือดกลับให้แล้วบอกว่าไปต่อได้ ให้ทุกโหมดทำงานเหมือนกันหมด
-- ยืนยันว่าอยู่ติดไข่จริงก่อนยิงคำสั่ง
--
-- ช่วงกล่องขึ้น เกมดีดเรากลับเซฟโซนได้แม้ตรึงตำแหน่งไว้แล้ว
-- ของเดิมยิงคำสั่งเก็บทันทีโดยไม่ดูว่าตอนนั้นอยู่ที่ไหน
-- ยิงจากบ้านระยะ 2,800 studs = เสียคำสั่งฟรี แถมเสียเวลารอคำตอบ 230ms
-- (วัดจริง: +1.44 อยู่ x3388 แต่ +1.71 กลับมา x513 แล้วยิงจากตรงนั้น)
--
-- เช็คก่อนยิง ไม่อยู่ก็วาปกลับไปแล้วเช็คซ้ำ ลองได้ 3 รอบ
-- ถ้ายังกลับไปไม่ได้ค่อยยอมแพ้ ดีกว่ายิงทิ้งแล้วรอคำตอบเปล่าๆ
Hub.atEggOrRewarp = function(pos, warpFn)
	for i = 1, 3 do
		local c = LocalPlayer.Character
		local h = c and c:FindFirstChild("HumanoidRootPart")
		if not h then return false end
		if (h.Position - pos).Magnitude <= 30 then return true end
		Hub.PushedBack = (Hub.PushedBack or 0) + 1
		if not warpFn() then return false end
		task.wait(0.05)
	end
	local c2 = LocalPlayer.Character
	local h2 = c2 and c2:FindFirstChild("HumanoidRootPart")
	return h2 and (h2.Position - pos).Magnitude <= 30 or false
end

Hub.stillUp = function(hum)
	if not hum then return false end
	if hum.Health > 0 then return true end
	if Hub.DeathBlocked and hum.MaxHealth > 0 then
		pcall(function() hum.Health = hum.MaxHealth end)
		return true
	end
	return false
end

--==================================================================
-- ไถไปทีละก้าว แทนการวาปทีเดียวถึง
--
-- เกมอัปเดต 2026-08-16 ย้ายการตัดสินไปอยู่ฝั่งเซิร์ฟเวอร์
-- เซิร์ฟเก็บตำแหน่งของตัวเองไว้ต่างหาก แล้วเลื่อนตามเราได้ไม่เกินความเร็วที่สมเหตุสมผล
-- วาปทีเดียว 600 studs = เซิร์ฟไม่ตามมา ต่อให้ฝั่งเราตรึงตำแหน่งไว้แนบไข่ก็ตาม
-- ผลคือ carry ตอบ "Enter the gameplay area first" ทุกครั้ง แล้วโดนลากกลับ + ฆ่า
--
-- วัดสดบนเครื่องสะอาด (WalkSpeed ในเกม = 147) ไปเก็บไข่จริงแล้ววัดคำตอบของเซิร์ฟ:
--   ความเร็วจริง 121 st/s  ระยะ 453  ใช้ 3.7 วิ  ->  carry = true   เลือดเต็ม
--   ความเร็วจริง 135 st/s  ระยะ 601  ใช้ 4.5 วิ  ->  carry = true   เลือดเต็ม
--   ความเร็วจริง 154 st/s  ระยะ 425  ใช้ 2.7 วิ  ->  carry = true   เลือดเต็ม
--   ความเร็วจริง 180 st/s  ระยะ 519  ใช้ 2.9 วิ  ->  carry = true   เลือดเต็ม
--   สั่ง       260 st/s  ->  ตาย โดนลากกลับ เก็บไม่ได้
--
-- และสำคัญมาก: พอตายหรือโดนจับได้หนึ่งครั้ง เซิร์ฟจะเลิกเชื่อตำแหน่งเราทั้งเซสชัน
-- หลังจากนั้นต่อให้เดินช้าแค่ไหนก็ตอบ "Enter the gameplay area first" ตลอด
-- จนกว่าจะออกจากเซิร์ฟแล้วเข้าใหม่ (ทดสอบยืนนิ่ง 19 วินาที ไม่หาย)
-- เพราะงั้นค่าเริ่มต้นต้องเผื่อไว้เยอะ ห้ามไล่ตามเพดาน
--
-- SpeedSafety = เผื่อเพดานไว้กี่ส่วน  ความเร็วจริง = (WalkSpeed * 1.1 + 8) * SpeedSafety
--==================================================================
-- โหมดเดินจริง  ไม่แตะ CFrame แม้แต่ครั้งเดียว
--
-- ทำไมต้องมีโหมดนี้:
-- 2026-08-16 บัญชีทดสอบโดนเตะด้วยข้อความ
--   "You have been removed for cheating | CODE BAC-7512 (Error Code: 267)"
-- ขณะรันบิลด์ที่ไม่ hook อะไรเลย ไม่ปิดสถานะตาย ไม่ดึงเลือด
-- และคุมความเร็วไว้แค่ 130 studs/วินาที
-- แปลว่าสิ่งที่เซิร์ฟจับได้คือ "การเขียนพิกัดตัวละครเอง" ล้วนๆ ไม่ใช่ความเร็ว
-- ข้อความนี้ไม่มีอยู่ในสคริปต์ฝั่งไคลเอนต์เลย = เป็นการตัดสินจากเซิร์ฟเวอร์
--
-- ตัวเลขที่ทำให้ตัดสินใจง่าย:
--   เขียน CFrame คุมความเร็วไว้     130 studs/วินาที  -> โดนเตะ
--   เดินจริงด้วย WalkSpeed ในเกม    147 studs/วินาที  -> ไม่มีอะไรให้จับ
-- เดินจริง "เร็วกว่า" ที่เราพยายามคุมไว้ด้วยซ้ำ เพราะบัญชีอัปความเร็วไว้แล้ว
--
-- ราคาที่ต้องจ่าย: ทะลุกำแพงกับตัวการ์ดไม่ได้ ต้องเดินอ้อมเอง
-- และเข้าใกล้เป้าได้แค่ระดับ ~6 studs ซึ่งยังอยู่ในระยะที่เซิร์ฟยอมให้เก็บไข่ (30)
Hub.moveWalk = function(target)
	if typeof(target) ~= "Vector3" then return false end
	local _, hrp, hum = char()
	if not hrp or not hum or hum.Health <= 0 then return false end

	local reach   = math.max(4, tonumber(Config.WalkReach) or 6)
	local ws      = math.max(1, hum.WalkSpeed)
	local far     = (hrp.Position - target).Magnitude
	-- เผื่อเวลาไว้ 3 เท่าของระยะทางตรง เพราะต้องเดินอ้อมสิ่งกีดขวาง
	local deadline = os.clock() + math.min(60, far / ws * 3 + 4)

	local lastPos, stuckSince = hrp.Position, os.clock()
	local reissue = 0

	while os.clock() < deadline do
		if not Config.Running or not alive() then hum:Move(Vector3.zero) return false end
		local c2, hrp2, hum2 = char()
		if not hrp2 or not hum2 or hum2.Health <= 0 then return false end
		hrp, hum = hrp2, hum2

		local d = target - hrp.Position
		local flat = Vector3.new(d.X, 0, d.Z)
		if flat.Magnitude <= reach then
			hum:Move(Vector3.zero)
			hum:MoveTo(hrp.Position)
			Hub.WalkHit = (Hub.WalkHit or 0) + 1
			return true
		end

		-- MoveTo ของ Roblox หมดอายุเองใน 8 วินาที ต้องสั่งซ้ำเรื่อยๆ
		if os.clock() - reissue > 0.5 then
			reissue = os.clock()
			hum:MoveTo(target)
		end

		-- ติดอะไรอยู่ไหม  ขยับได้น้อยกว่า 2 studs ใน 1.2 วินาที = ติด
		if (hrp.Position - lastPos).Magnitude > 2 then
			lastPos, stuckSince = hrp.Position, os.clock()
		elseif os.clock() - stuckSince > 1.2 then
			Hub.WalkStuck = (Hub.WalkStuck or 0) + 1
			stuckSince = os.clock()
			-- กระโดดข้าม แล้วเฉียงออกด้านข้างสักหน่อยเพื่อหลบมุมที่ติด
			pcall(function() hum.Jump = true end)
			local side = Vector3.new(-flat.Unit.Z, 0, flat.Unit.X) * 18
			hum:MoveTo(hrp.Position + side + flat.Unit * 12)
			task.wait(0.5)
			reissue = 0
		end

		task.wait(0.1)
	end

	hum:Move(Vector3.zero)
	Hub.WalkMiss = (Hub.WalkMiss or 0) + 1
	local _, hrp3 = char()
	return hrp3 ~= nil and (hrp3.Position - target).Magnitude <= 25
end

-- เพดานความเร็วที่เกมอนุญาต  อ่านสูตรมาจากโค้ดของเกมตรงๆ
--
-- ReplicatedFirst.UGI.ContentCatalog.Impact  บรรทัด 67:
--   local function dynamicLegalHorizontalSpeed(prev, sample)
--       local ws = prev == nil and sample.WalkSpeed or math.max(prev.WalkSpeed, sample.WalkSpeed)
--       return ws * SpeedMultiplier + SpeedFlatAllowance
--   end
--
-- ค่าคงที่อ่านสดจากเครื่องจริง (debug.getupvalues ของ boundedPreImpactHorizontalVelocity):
--   SpeedMultiplier    = 1.1
--   SpeedFlatAllowance = 8
--   TickInterval       = 0.05     <- ระบบเก็บตัวอย่างตำแหน่ง 20 ครั้งต่อวินาที
--   ReliableGapMaximum = 0.2
--
-- WalkSpeed ในเกม 147.1  ->  เพดาน = 147.1 * 1.1 + 8 = 169.8 studs/วินาที
--
-- และนี่คือคำอธิบายว่าทำไมบิลด์ที่แล้วถึงโดนเตะทั้งที่ "คุมความเร็วไว้ 130" แล้ว:
-- ระบบวัดระยะต่อ 1 tick ไม่ได้วัดความเร็วเฉลี่ย
--   1 tick = 0.05 วินาที  ->  ระยะที่ยอมให้ = 169.8 * 0.05 = 8.5 studs
--   ของเดิมกระโดดทีละ 12 studs ในเฟรมเดียว = เกิน 8.5 ทุกก้าว
--   ถึงหารเฉลี่ยแล้วจะได้ 130 ก็ตาม ระบบเห็นเป็นการวาปย่อยๆ รัวๆ
-- สรุป: ต้องขยับ "ทุกเฟรม ทีละนิด" ไม่ใช่ "กระโดดทีละก้อนแล้วหยุด"
--==================================================================
-- ปลดเพดานความเร็วด้วยกลไกของเกมเอง  ไม่ hook อะไรทั้งสิ้น
--
-- ระบบกันโกงมี "โหมดยกเว้น" ของตัวเองไว้ใช้ตอนผู้เล่นโดนระเบิด/กระแทก/ragdoll
-- เพราะตอนนั้นตัวละครพุ่งเร็วกว่าปกติมาก จะเอาเพดานเดินมาวัดไม่ได้
--
-- Impact.luau:333  ตอนเริ่มโหมดนี้มันเขียนตารางนี้ลงในสถานะตัวละคร:
--     state.ImpulseContext = {
--         MaxHorizontalSpeed    = <ความเร็วที่ยอมให้>,
--         MaxHorizontalDistance = <ระยะที่ยอมให้>,
--         ExpiresAt             = <หมดอายุเมื่อไหร่>,
--         ...
--     }
--
-- Impact.luau:256  ตอนตรวจ มันใช้ค่าจากตารางนี้แทนเพดานปกติทันที:
--     AllowedHorizontalDistance = ImpulseContext.MaxHorizontalSpeed * elapsed + tolerance
--
-- Impact.luau:104  และเพดานความเร็วก็ถูกเขียนทับด้วย:
--     if ImpulseContext ~= nil then
--         allowed = math.max(allowed, ImpulseContext.MaxHorizontalSpeed)
--     end
--
-- ตารางสถานะตัวละครที่ allocateStateRecord สร้าง เป็นตารางธรรมดา ไม่ได้ table.freeze
-- (ตรวจสดแล้ว: isfrozen = false, 56 คีย์) เขียนใส่ตรงๆ ได้เลย
-- ไม่ต้องครอบทับอะไรของเกม ไม่ต้องแตะโค้ดเกมสักบรรทัด
-- ซึ่งสำคัญมาก เพราะการครอบทับฟังก์ชันคือสิ่งที่ทำให้โดนเตะมาทั้งวัน
--
-- วัดสด 2026-08-16 (v364) ระยะ 433 studs จากจุดกลางไปไข่ แล้วยิงเก็บจริง:
--     250 st/s  -> 1.72 วิ  hp=100  carry = true
--     400 st/s  -> 1.06 วิ  hp=100  carry = true
--     700 st/s  -> 0.62 วิ  hp=100  carry = true    (ของเดิมก่อนเกมอัปเดตทำได้ 550)
--    1200 st/s  -> วิ่งเลยเป้า ไปไม่ถึง ไม่ใช่เซิร์ฟปฏิเสธ
-- เทียบกับตอนไม่เปิด: 260 st/s ตายทันที · วาปทีเดียว ดีดกลับ 100%
--
-- ต้องต่ออายุทุกเฟรม เพราะ Impact.EndRagdoll/Monitor ล้างทิ้งเมื่อหมดอายุ
Hub.acState = function()
	-- ตารางสถานะเป็นของตัวละครตัวปัจจุบัน เกิดใหม่ = ตารางใหม่ ต้องหาใหม่
	local c = LocalPlayer.Character
	if Hub.ACStateFor == c and Hub.ACState then return Hub.ACState end
	if type(getgc) ~= "function" or type(debug) ~= "table"
	   or type(debug.getupvalues) ~= "function" then return nil end

	-- ตัวละครเปลี่ยน = เริ่มนับใหม่
	--
	-- ของเดิมล้างตัวนับเฉพาะตอนสแกนสำเร็จ  ถ้าพลาดสะสมครบ 6 ครั้งทั้งเซสชัน
	-- (เช่นสะดุดตอนเกิดใหม่ไม่กี่ครั้ง) ตัวปลดเพดานจะปิดถาวรจนกว่าจะรันสคริปต์ใหม่
	-- แล้ว Hub.glide ถอยไปใช้ 152.8 studs/วินาทีเงียบๆ ไม่มีล็อกบอกเลย
	-- ซึ่งช้ากว่าการ์ด Cosmic (200) และ Prehistoric (152) = ตายทุกเที่ยว
	if Hub.ACStateFor ~= c then Hub.ACStateTries = 0 end

	-- สแกนแพง ห้ามลองรัวๆ ถ้าตัวละครตัวนี้หาไม่เจอจริงๆ ก็พอ
	Hub.ACStateTries = (Hub.ACStateTries or 0) + 1
	if Hub.ACStateTries > 6 then
		Hub.ACStateFor = c   -- จำไว้ว่าลองครบแล้วสำหรับตัวละครตัวนี้
		return nil
	end

	local found
	pcall(function()
		for _, v in pairs(getgc(true)) do
			if type(v) == "function" then
				local oi, info = pcall(debug.getinfo, v)
				if oi and info and string.find(tostring(info.source or ""),
				   "UGI.ContentCatalog.Runtime", 1, true) then
					local ok, ups = pcall(debug.getupvalues, v)
					if ok and type(ups) == "table" then
						for _, u in pairs(ups) do
							if type(u) == "table" and rawget(u, "MovementMode") ~= nil
							   and rawget(u, "SampleHistory") ~= nil then
								found = u
							end
						end
					end
				end
			end
		end
	end)

	if found then
		Hub.ACState, Hub.ACStateFor = found, c
		Hub.ACStateTries = 0
	end
	return found
end

-- ดันเกณฑ์สั่งแก้ไขให้เป็นอนันต์  = ตัดการดึงกลับที่ต้นทาง
--
-- ทำไมถึงกลับมาใช้วิธีนี้:
--
-- โค้ดรุ่นก่อนเกมอัปเดต (New Text Document.txt:1426-1480) วาปแบบเฟรมเดียวล้วนๆ
--     hrp.CFrame = CFrame.new(landing)
-- แล้วไม่โดนดึงกลับเลย เพราะมันปิดระบบแก้ไขทิ้งก่อน ด้วยสองวิธี
--     cfg.CorrectionsEnabled = false                    (ต้องมี setreadonly)
--     ถ้า upvalue ตัวไหน == 1.35 -> ตั้งเป็น math.huge   (ต้องมี debug.setupvalue)
--
-- 1.35 ตัวนั้นคือ SpeedCorrectionThreshold ซึ่งวันนี้ผมวัดสดยืนยันแล้วว่าใช่
-- (Impact.luau:415  SpeedCorrectionThreshold <= Evidence.Speed -> สั่งแก้ไข)
--
-- ต่างจากของเก่าตรงที่ ของเก่ากวาดทั้งหน่วยความจำแล้วแก้ทุกตัวที่บังเอิญ == 1.35
-- ซึ่งอาจไปโดนค่าอื่นของเกมที่ไม่เกี่ยวกัน  รอบนี้ยิงตรงเป้า:
--   หาเฉพาะฟังก์ชันที่มี upvalue ครบ 14 ช่อง และช่อง 6 == 0.2 (ReliableGapMaximum)
--   ซึ่งยืนยันว่าเป็นตัวเดียวกับที่วัดค่าออกมาได้ 5=1.8 6=0.2 7=1.35 8=0.75
--   แล้วค่อยแก้ช่อง 7 ช่องเดียว
--
-- ต้องมี debug.setupvalue ตัวรันที่ไม่มีจะข้ามไปเอง ไม่พัง
-- ปิดได้ด้วย Config.LiftThreshold = false
Hub.liftThreshold = function()
	if Config.LiftThreshold == false then return false end
	if Hub.ThresholdLifted then return true end
	-- กันสแกนถี่ ต่อให้ธงโดนรีเซ็ตด้วยเหตุอื่น ห้ามไล่ getgc บ่อยกว่า 20 วินาทีต่อครั้ง
	-- getgc(true) สร้างตาราง 45,000 ช่องทุกครั้งที่เรียก แพงมาก
	if os.clock() - (Hub.LiftScanAt or -1e9) < 20 then return false end
	Hub.LiftScanAt = os.clock()
	if type(getgc) ~= "function" or type(debug) ~= "table" then return false end
	if type(debug.getupvalues) ~= "function" or type(debug.setupvalue) ~= "function" then
		Hub.LiftSkipped = "ตัวรันไม่มี debug.setupvalue"
		return false
	end

	local done = 0
	pcall(function()
		for _, v in pairs(getgc(true)) do
			if type(v) == "function" then
				local okU, ups = pcall(debug.getupvalues, v)
				if okU and type(ups) == "table" then
					-- ลายเซ็นของฟังก์ชันเฝ้าความเร็ว: 14 ช่อง · ช่อง 6 = 0.2 · ช่อง 7 = 1.35
					local n = 0
					for i in pairs(ups) do if i > n then n = i end end
					if n == 14 and ups[6] == 0.2 and ups[7] == 1.35 then
						if pcall(debug.setupvalue, v, 7, math.huge) then done = done + 1 end
					end
				end
			end
		end
	end)

	-- ต้องตั้งธงเสมอ ไม่ว่าจะเจอหรือไม่เจอ
	--
	-- ของเดิมตั้งเฉพาะตอน done > 0 ซึ่งเป็นบั๊กที่กิน RAM หนักมาก:
	-- พอดันสำเร็จครั้งแรก ค่ากลายเป็น math.huge แล้ว รอบต่อไปลายเซ็น
	-- (ups[7] == 1.35) ไม่ตรงอีก -> done = 0 -> ธงไม่ถูกตั้ง -> สแกนใหม่ทุกครั้ง
	-- และ patchAntiCheat ถูกเรียกจากลูป 0.25 วินาที
	-- = ไล่ตาราง getgc(true) ขนาด 45,000 ช่อง วินาทีละ 4 ครั้งตลอดเวลา
	-- ผู้ใช้เห็นเป็น RAM ไหลขึ้นเรื่อยๆ จนเครื่องค้าง
	--
	-- done = 0 แปลว่า "ไม่มีอะไรเหลือให้ดันแล้ว" ซึ่งก็คือเสร็จงานเหมือนกัน
	Hub.ThresholdLifted = true
	if done > 0 then Hub.LiftCount = (Hub.LiftCount or 0) + done end
	return done > 0
end

-- สั่งให้โหมดยกเว้นหมดอายุทันที = ขอ "นิรโทษกรรม" ตอนจบขา
--
-- อ่านจากโค้ดเกมตรงๆ  Impact.luau:430-435
--     if sample.Timestamp >= ImpulseContext.ExpiresAt then
--         AdoptPostImpulseBaseline(player, state, sample)
--         return
--     end
--
-- แล้ว AdoptPostImpulseBaseline (Runtime.luau:597-649) ทำสามอย่างที่เราต้องการพอดี:
--     ล้างประวัติตัวอย่างทั้งหมด (602-607)
--     ImpulseContext = nil (614)
--     Evidence = { Speed = 0, Teleport = 0, ... }
--     ตั้งจุดตั้งต้นใหม่ "ตรงที่เรายืนอยู่ตอนนี้"
--
-- ของเดิมต่ออายุทุกเฟรมไม่มีวันหมด เกมจึงไม่เคยตั้งจุดตั้งต้นใหม่ให้เลย
-- มันเลยเทียบเรากับตัวอย่างเก่าตลอดเวลา แล้วลากกลับไปจุดนั้น
-- (วัดสด: โดนลากย้อนทางที่มา 334-882 studs โดยไม่มีความผิดบันทึกเลยสักครั้ง)
--
-- ปล่อยให้หมดอายุตอนถึงที่หมาย = เกมยอมรับตำแหน่งใหม่ ไม่มีของเก่าให้ลากกลับ
Hub.expireImpulse = function()
	local st = Hub.ACState
	if type(st) ~= "table" then return false end
	local ic = rawget(st, "ImpulseContext")
	if type(ic) ~= "table" then return false end
	local ok = pcall(function()
		-- ตั้งเวลาหมดอายุไว้ในอดีต  รอบตรวจถัดไปจะเห็นว่าหมดแล้วแล้วเรียกนิรโทษกรรมเอง
		-- ไม่ลบ ImpulseContext ทิ้งเอง เพราะต้องให้ Impact.Monitor เป็นคนเรียกฟังก์ชันนั้น
		ic.ExpiresAt = -1
	end)
	if ok then Hub.Expired = (Hub.Expired or 0) + 1 end
	return ok
end

-- เปิดโหมดยกเว้นให้ตัวเอง  เรียกทุกเฟรมระหว่างเดินทาง
Hub.armImpulse = function(hrp)
	if Config.ImpulseBypass == false then return false end
	local st = Hub.acState()
	if not st then return false end
	local last = st.LastSample or st.LastObservedSample
	local now = (last and last.Timestamp) or 0
	local okw = pcall(function()
		st.ImpulseContext = {
			Kind = "Impulse",
			StartedAt = now,
			ExpiresAt = now + 5,
			OriginPosition = hrp.Position,
			MaxHorizontalSpeed = 5000,
			MaxVerticalSpeed = 2000,
			MaxHorizontalDistance = 1e6,
			MaxUpwardDistance = 1e6,
			PreMovementSafeSample = st.LastValidatedGroundedSample or last,
		}
	end)
	if okw then Hub.ImpulseArmed = (Hub.ImpulseArmed or 0) + 1 end
	return okw
end

-- รับรองตำแหน่งปัจจุบันเป็น "จุดตั้งต้นที่ไว้ใจได้"
--
-- ลอกมาจากฟังก์ชันของเกมเองตรงๆ: Runtime.luau:522 AdoptTeleportBaseline(player, state, sample)
-- เกมเรียกมันเวลาย้ายตำแหน่งเราแบบถูกกฎ (เกิดใหม่ · ย้ายโซน) เพื่อบอกระบบว่า
-- "ตำแหน่งใหม่นี้ชอบธรรม อย่าเทียบกับตำแหน่งเก่า"
--
-- ของเดิมมันเซ็ตชุดนี้:
--   LastGameplayTrustedSample / LastValidatedSample / LastSample / LastGoodSample = sample
--   ValidationLocked = false ; ValidationStartedAt = sample.Timestamp
--   ถ้า sample.IsSupported: LastValidatedGroundedSample · LastConfirmedGroundSample ·
--                           LastSupportedAt · SupportStartedAt · MovementMode = "Grounded"
--   ถ้าไม่: MovementMode = "Initializing" แล้วเริ่มจับเวลา UnsupportedStartedAt (= ตัวที่ฆ่าเราตอนลอย)
--
-- เราไม่ปลอม sample ขึ้นมาเอง เพราะ Timestamp อยู่คนละนาฬิกากับ os.clock()
-- ใช้ LastObservedSample ที่เกมเพิ่งสร้างเอง ซึ่งสะท้อนตำแหน่งล่าสุดของเราอยู่แล้ว
-- (เราเขียน CFrame ทุกเฟรม ตัวเก็บตัวอย่างของเกมจึงเห็นตำแหน่งใหม่ก่อนเราเรียกตรงนี้)
--
-- ตารางสถานะและ sample ตรวจแล้วว่าไม่ถูกล็อก (table.isfrozen = false) เขียนทับได้ตรงๆ
-- ไม่ต้องครอบทับฟังก์ชันของเกม ไม่ต้องใช้ฟังก์ชันพิเศษของตัวรัน
Hub.adoptBaseline = function()
	local st = Hub.ACState or (Hub.acState and Hub.acState())
	if type(st) ~= "table" then return false end
	local s = rawget(st, "LastObservedSample")
	if type(s) ~= "table" then return false end

	local ok = pcall(function()
		st.LastGameplayTrustedSample = s
		st.LastValidatedSample = s
		st.LastSample = s
		st.LastGoodSample = s
		st.ValidationLocked = false
		st.ValidationStartedAt = s.Timestamp
		st.IsSupportedNow = s.IsSupported
		st.HighestYSinceGround = s.Position.Y

		if s.IsSupported then
			st.LastValidatedGroundedSample = s
			st.LastConfirmedGroundSample = s
			st.LastSupportedAt = s.Timestamp
			st.SupportStartedAt = s.Timestamp
			st.MovementMode = "Grounded"
		end

		-- ล้างคะแนนความผิดทั้งสองตัว (Runtime.luau:32 มี Speed กับ Teleport)
		local ev = rawget(st, "Evidence")
		if type(ev) == "table" then
			if rawget(ev, "Speed") ~= nil then ev.Speed = 0 end
			if rawget(ev, "Teleport") ~= nil then ev.Teleport = 0 end
		end
	end)
	if ok then Hub.Adopted = (Hub.Adopted or 0) + 1 end
	return ok
end

Hub.legalSpeed = function(hum)
	local ws = (hum and hum.WalkSpeed) or 16
	if ws ~= ws or ws <= 0 then ws = 16 end
	local mul  = tonumber(Hub.ACSpeedMul) or 1.1
	local flat = tonumber(Hub.ACSpeedFlat) or 8
	local safe = math.clamp(tonumber(Config.SpeedSafety) or 0.9, 0.3, 1.0)
	return (ws * mul + flat) * safe
end

-- เลื่อนตัวไปเรื่อยๆ ทุกเฟรม  ระยะต่อเฟรม = ความเร็ว x เวลาจริงของเฟรมนั้น
--
-- ห้ามใช้ task.wait(คงที่) แล้วคูณระยะเอง เพราะเฟรมดรอปเมื่อไหร่
-- ระยะต่อเฟรมจะพุ่งเกินเพดานทันทีโดยไม่รู้ตัว  ใช้ dt จริงจาก Heartbeat เท่านั้น
Hub.glide = function(hrp, hum, dest)
	if typeof(dest) ~= "Vector3" then return false end
	local RunS = game:GetService("RunService")

	-- ทางเลือก: วาปทีเดียวถึงแบบของเดิม (ดูเหตุผลที่ Config.WarpInstant)
	-- วัดแล้วเซิร์ฟไม่รับ แต่เปิดไว้ให้ลองเองได้
	if Config.WarpInstant == true then
		hrp.CFrame = CFrame.new(dest)
		hrp.AssemblyLinearVelocity = Vector3.zero
		task.wait(math.max(0.05, tonumber(Config.WarpSettle) or 0.15))
		local _, h2 = char()
		return h2 ~= nil and (h2.Position - dest).Magnitude <= 25
	end

	-- เปิดโหมดยกเว้นก่อน ถ้าเปิดได้จะวิ่งได้เร็วกว่าเพดานปกติหลายเท่า
	-- เปิดไม่ได้ (executor ไม่มี getgc/debug) ก็ถอยไปใช้เพดานปกติ ยังทำงานได้เหมือนเดิม
	local boosted = Hub.armImpulse(hrp)
	local speed
	if boosted then
		-- [เคยลองผูกกับ WalkSpeed แล้วข้อมูลบอกว่าไม่ใช่]
		--
		-- เคยคิดว่า "บางคนโดนเตะ บางคนไม่โดน" เกิดจาก WalkSpeed ต่างกัน
		-- เพราะ MoveSpeed เป็นเลขตายตัวเท่ากันหมด แต่ WalkSpeed แต่ละไอดีไม่เท่ากัน
		--
		-- เก็บข้อมูลจากเครื่องลูกค้าจริงแล้วพบว่าผิด:
		--   เครื่องที่ไม่โดนเตะ  ws=24  spd=700  = วิ่ง 29 เท่าของ WalkSpeed ตัวเอง
		-- ถ้าอัตราส่วนเป็นตัวจับ เครื่องนี้ต้องโดนหนักที่สุด แต่กลับไม่โดนเลย
		-- (เครื่องเดียวกันนั้น noclip = true ด้วย ซึ่งล้มทฤษฎี noclip ไปพร้อมกัน)
		--
		-- คืนกลับเป็นเลขตายตัวตามเดิม อย่าไปทำให้ไอดีที่ปกติดีอยู่แล้วช้าลงฟรีๆ
		speed = math.clamp(tonumber(Config.MoveSpeed) or 700, 60, 900)
	else
		speed = Hub.legalSpeed(hum)
		-- บอกให้รู้ตัวว่าตกไปใช้ทางช้าแล้ว ห้ามเงียบ
		--
		-- ทางช้า 152.8 studs/วินาที ช้ากว่าการ์ด Cosmic (200) กับ Prehistoric (152)
		-- = ตายทุกเที่ยวที่ไปสองโซนนั้น  ของเดิมตกมาทางนี้แบบไม่มีล็อกอะไรเลย
		-- ไล่ปัญหาไม่ได้เลยว่าทำไมจู่ๆ ก็ตายรัวๆ
		if not Hub.SlowWarned then
			Hub.SlowWarned = true
			Hub.BoostOff = true
		end
	end
	if boosted then Hub.BoostOff = false end

	-- เพิ่งตายไปเมื่อกี้ = ระบบยังจับตาอยู่ ชะลอลงชั่วคราว
	--
	-- แต่ห้ามชะลอต่ำกว่าความเร็วการ์ด ไม่งั้นกลายเป็นวงจรตายไม่จบ
	--
	-- ความเร็วการ์ดแต่ละโซน (Directory/Guards/_Index/*.luau)
	--   Cosmic 200 · Prehistoric 152 · Abyss Ocean 130 · Volcano 113
	--   Snow 98 · Jungle 82 · Desert 62 · Lake 35 · Forest 16
	--
	-- ของเดิมคูณ 0.6 ดื้อๆ  ตอนปลดเพดานไม่ได้จะเหลือ 152.8 x 0.6 = 91.7
	-- ซึ่งช้ากว่าการ์ดถึง 4 โซน = ตายซ้ำ = ต่ออายุหน้าต่างชะลออีก วนไม่จบ
	-- ชะลอได้ แต่ต้องไม่ต่ำกว่า 210 (เหนือการ์ดที่เร็วที่สุดในเกม)
	-- ถ้าเพดานที่มีอยู่ต่ำกว่านั้นเองก็ไม่ต้องชะลอเลย ชะลอไปก็ตายอยู่ดี
	if os.clock() < (Hub.SlowUntil or 0) then
		speed = math.max(speed * 0.6, math.min(speed, 210))
	end

	local far      = (hrp.Position - dest).Magnitude
	local deadline = os.clock() + math.min(40, far / speed * 4 + 4)
	local reach    = math.max(3, tonumber(Config.WalkReach) or 6)

	while os.clock() < deadline do
		local dt = RunS.Heartbeat:Wait()
		if not alive() then return false end
		local _, h, u = char()
		if not h or not u then return false end
		hrp, hum = h, u
		-- ระหว่างกระโดดปลดสถานะลูกวิ่ง ห้ามเขียน CFrame เด็ดขาด
		-- ถ้าเขียนทับ ตัวจะไม่มีวันลอยพ้นพื้น = ไม่เข้า Freefall = สถานะไม่หลุด
		-- (วัดเทียบแล้ว: ตรึงไว้ แต้มยังขึ้น +108/6วิ · ปล่อยลอย เหลือ +6/6วิ)
		if Hub.JumpHold and os.clock() < Hub.JumpHold then
			task.wait(0.05)
			continue
		end

		if boosted then Hub.armImpulse(hrp) end   -- ต่ออายุทุกเฟรม ไม่งั้นหมดอายุแล้วโดนจับ

		-- รับรองตำแหน่งใหม่ทุกเฟรมด้วย (ดู Hub.adoptBaseline)
		--
		-- armImpulse ยกเพดานความเร็วอย่างเดียว แต่ไม่ได้บอกว่าตำแหน่งใหม่ชอบธรรม
		-- ระบบจึงยังเทียบเรากับ LastGoodSample เก่าอยู่ แล้วลากกลับไปจุดนั้น
		-- (วัดสด: โดนลาก 86 ครั้ง/40 วินาที ทุกครั้งลากย้อนไปทางที่เรามา
		--  โดยที่ LastViolationReason = nil และ Evidence.Speed = 0 คือไม่มีความผิดเลย
		--  ซึ่งแปลว่าไม่ใช่ด่านความเร็วจับ แต่เป็นการซิงค์ตำแหน่งเทียบของเก่า)
		--
		-- เลื่อนจุดอ้างอิงตามเราไปทุกเฟรม ระบบจะไม่มีตำแหน่งเก่าให้ลากกลับ
		if Config.AdoptBaseline ~= false then pcall(Hub.adoptBaseline) end
		if not Hub.stillUp(hum) then
			Hub.SlowUntil = os.clock() + 20
			return false
		end

		local d = dest - hrp.Position
		local m = d.Magnitude
		if m <= reach then
			-- หยุดเดินให้เรียบร้อยตอนถึงที่หมาย
			--
			-- ต้องล้างความเร็วด้วย ไม่ใช่ล้างแค่ MoveDirection
			-- เฟรมที่แล้วเพิ่งตั้ง AssemblyLinearVelocity ไว้ถึง 200 studs/วินาที
			-- ถ้าปล่อยค้าง ตัวจะไถลเลยเป้าไปอีก ~25 studs หลังหยุดสั่ง
			--
			-- วัดสดตอนยืนรอที่จุดกลาง: MoveDirection = 0 แต่ vel วูบเป็น 135 แล้ว 177 สลับทิศ
			-- ตัวไปโผล่ห่างจุดกลาง 22-27 studs ระบบก็ลากกลับ แล้วไถลออกอีกฝั่ง วนไม่จบ
			-- = อาการ "ยืนสลับไปมา ไม่ยืนนิ่งที่จุดกลาง"
			--
			-- คนที่หยุดเดินจริงๆ ความเร็วต้องเป็นศูนย์ ล้างตรงนี้จึงสมเหตุสมผลกว่าเดิมด้วย
			pcall(function() hum:Move(Vector3.zero, false) end)
			pcall(function() hrp.AssemblyLinearVelocity = Vector3.zero end)
			pcall(function() hrp.AssemblyAngularVelocity = Vector3.zero end)

			-- ถึงที่หมายแล้ว ปล่อยโหมดยกเว้นหมดอายุเพื่อขอตั้งจุดตั้งต้นใหม่
			-- (ดูเหตุผลยาวๆ ที่ Hub.expireImpulse)
			if Config.ExpireOnArrive ~= false then pcall(Hub.expireImpulse) end
			return true
		end

		-- บอกเกมด้วยว่าเรากำลังเดินไปทางนั้น ไม่ใช่แค่ย้ายตำแหน่งเฉยๆ
		--
		-- นี่คือความขัดแย้งที่ค้างอยู่ตลอดเวลาโดยไม่มีใครสังเกต:
		--   ตำแหน่ง       เปลี่ยนทุกเฟรม        <- เซิร์ฟเห็น
		--   MoveDirection = 0,0,0 ตลอดกาล      <- เซิร์ฟเห็นเหมือนกัน
		--
		-- ผู้เล่นจริงที่เดินอยู่ MoveDirection ต้องไม่เป็นศูนย์
		-- ของเราขยับได้เป็นพันๆ studs โดยค่านี้เป็นศูนย์ = ขัดแย้งกันเองชัดๆ
		-- และเป็นการสะสมทีละ tick ตรงกับอาการ "รันได้สักพักแล้วค่อยโดนเตะ"
		-- (ต่างจากสาเหตุตอนโหลดที่เตะภายใน 10 วินาที)
		--
		-- Humanoid:Move() ตั้ง MoveDirection ให้ตรงกับทิศที่เราไปจริง
		-- ไม่ได้ทำให้ตัวละครขยับเอง (เราเขียน CFrame ทับทีหลังทุกเฟรมอยู่แล้ว)
		-- แค่ทำให้สิ่งที่เซิร์ฟเห็นสอดคล้องกัน
		local dir = d.Unit
		pcall(function() hum:Move(Vector3.new(dir.X, 0, dir.Z), false) end)

		-- ห้ามวิ่งเลยเป้า  ที่ 1200 st/s เคยพุ่งข้ามแล้วแกว่งไปมาจนไปไม่ถึง
		-- math.min กับระยะที่เหลือกันไว้อยู่แล้ว แต่หนีบ dt ด้วยกันเฟรมกระตุกยาว
		local capPerFrame = speed * math.min(dt, 0.05)
		local stepDist = math.min(capPerFrame, m)
		local nextPos = hrp.Position + dir * stepDist

		-- เกาะพื้นทุกเฟรม ห้ามลอย
		--
		-- เคยถอดออกเพราะวัดแล้ว "เก็บไข่ 0 ฟอง" แต่ภายหลังพบว่าตัววัดของผมเองพัง
		-- (มันเก็บ Hub ตัวเก่าไว้ พอโหลดสคริปต์ใหม่เลยนับไข่จากตัวที่หยุดนับไปแล้ว)
		-- ผลนั้นจึงใช้ไม่ได้ ใส่กลับตามหลักฐานจากโค้ดเกม
		--
		-- Runtime.luau:537-548 บอกชัดว่าสถานะที่ระบบยอมรับต้องติดพื้น:
		--   if not sample.IsSupported then
		--       state.MovementMode = "Initializing"      <- ไม่รับเป็นจุดตั้งต้น
		--       state.UnsupportedStartedAt = ...          <- เริ่มจับเวลาลอย
		--       return
		--   end
		--   state.MovementMode = "Grounded"               <- ติดพื้นเท่านั้น
		--
		-- และโน้ตที่วัดไว้เอง: ลอยนิ่งที่ +15 ตายวินาทีที่ 4.2 · ลอยตอนวิ่งตายทันที
		if Config.GroundSnap ~= false then
			local okg, snapped = pcall(snapToGround, nextPos)
			if okg and typeof(snapped) == "Vector3" then nextPos = snapped end
		end

		-- ตัวต้องนิ่ง ห้ามหมุนห้ามสั่นระหว่างเดินทาง
		--
		-- เขียนทั้งตำแหน่งและมุมพร้อมกัน ถ้าเขียนแต่ตำแหน่ง ตัวจะโดนฟิสิกส์หมุนเล่น
		-- ซึ่งทำให้ตัวอย่างที่เกมเก็บมีค่า AngularVelocity แกว่ง = ดูไม่เหมือนคนยืนวิ่งปกติ
		hrp.CFrame = CFrame.new(nextPos, nextPos + Vector3.new(dir.X, 0, dir.Z))
		hrp.AssemblyAngularVelocity = Vector3.zero

		-- ประกาศความเร็วให้ตรงกับที่เคลื่อนที่จริงเป๊ะๆ ห้ามหนีบ ห้ามล้างเป็นศูนย์
		--
		-- อ่านมาจากโค้ดเกมตรงๆ (ReplicatedFirst.UGI.ContentCatalog.Impact):
		--
		--   Impact.luau:101-105   เพดานพื้นฐาน = WalkSpeed * 1.1 + 8
		--                         ถ้ามี ImpulseContext -> เพดาน = max(นั้น, MaxHorizontalSpeed)
		--                         ของเราตั้ง 5000 ความเร็วที่เราประกาศจึงไม่โดนหนีบ
		--   Impact.luau:107-113   v20 = ความเร็วที่ "เรา" ประกาศ (AssemblyLinearVelocity)
		--   Impact.luau:311-313   เพดานของหน้าต่าง impulse = v20.Magnitude * 1.5 + 20
		--   Impact.luau:338       MaxHorizontalSpeed = ค่านั้น
		--
		-- แปลว่าเพดานคำนวณจากค่าที่เราประกาศเอง  ประกาศตามจริง = อยู่ใต้เพดานเสมอ
		--
		-- ของเดิมเขียน math.min(speed, 200) เพื่อ "ให้ดูปลอดภัย" ซึ่งกลับกันเลย:
		--   ประกาศ 200 -> เพดานเหลือ 200*1.5+20 = 320   แต่ตำแหน่งวิ่งจริง 700
		--   เกินเพดาน -> Impact.luau:414 Evidence.Speed += 1.8 ต่อวินาที
		--   ถึง SpeedCorrectionThreshold 1.35 ใน 1.35/1.8 = 0.75 วินาที -> "ImpulseSpeed"
		--   -> โดนดึงกลับตำแหน่งเก่า แล้วตาย
		--
		-- วัดสดยืนยัน: ตาย 4 ครั้งติด ค่าที่ประกาศ = 200 เป๊ะทุกครั้ง
		-- ขณะที่ความเร็วเชิงตำแหน่งจริงอยู่ที่ 419-903 (เกิน 320 ทั้งหมด)
		--
		-- ประกาศ stepDist/dt = ค่าที่ตรงกับการขยับจริงในเฟรมนั้นพอดี
		-- เพดานกลายเป็น 700*1.5+20 = 1070 ซึ่งสูงกว่าที่เราวิ่ง คะแนนจึงไม่ขึ้นเลย
		local realSpd = (dt > 0) and (stepDist / dt) or speed
		hrp.AssemblyLinearVelocity = dir * realSpd

		-- ตอนกล่องขาวขึ้น ต้องตรึง "ระหว่างทาง" ไม่ใช่ตรึงตอนถึงแล้ว
		--
		-- เกมเขียนพิกัดเรากลับเซฟโซนทุกเฟรม และมันเขียนทีหลังเราในเฟรมเดียวกัน
		-- การเขียนที่ Heartbeat (ตรงนี้) จึงโดนทับทุกครั้ง ไปได้ไกลสุดแค่ขอบ x~770
		-- (วัดสด: ช่วงกล่อง 2 วินาที ตัวเด้งอยู่ x617-768 ไม่เคยผ่านไปได้เลย got=0)
		--
		-- ของเดิมเรียก Hub.pinAt หลัง move() สำเร็จ ซึ่งไม่มีวันถึงตอนกล่องขึ้น
		-- = ตัวตรึงไม่เคยได้ทำงานเลยสักครั้งในจังหวะที่ต้องใช้มันที่สุด
		--
		-- ส่งตำแหน่งล่าสุดให้ตัวเขียนท้ายเฟรม (HMD_Pin ที่ RenderPriority.Last+1)
		-- ทับต่อทุกเฟรมระหว่างเดินทาง ค่าของเราจึงเป็นค่าสุดท้ายของเฟรมเสมอ
		if Hub.BoxUp and Config.PinHold ~= false then
			Hub.PinPos = nextPos
			Hub.PinUntil = os.clock() + 0.25
		end
	end

	-- ออกจากลูปแล้วอย่าปล่อยให้ตัวตรึงลากเราค้างอยู่กลางทาง
	if Hub.BoxUp and Hub.PinPos then Hub.PinUntil = math.min(Hub.PinUntil, os.clock() + 0.1) end

	Hub.GlideTimeout = (Hub.GlideTimeout or 0) + 1
	pcall(function() hum:Move(Vector3.zero, false) end)   -- หยุดเดินให้เรียบร้อย
	pcall(function() hrp.AssemblyLinearVelocity = Vector3.zero end)   -- และล้างแรงตกค้าง
	return (hrp.Position - dest).Magnitude <= 25
end

-- เรียกรีโมทแบบมีเวลาหมดอายุ
--
-- InvokeServer ของ Roblox ไม่มี timeout ถ้าเซิร์ฟไม่ตอบกลับจะรอตรงนั้นตลอดกาล
-- ลูปเก็บไข่ทั้งตัวหยุดนิ่ง อาการที่เห็นคือ "วาปแล้วค้าง" ไม่ไปไหนต่อเลย
-- เกิดได้เวลาเซิร์ฟตัดคำขอทิ้งเงียบๆ เช่นมองว่าเราอยู่นอกเขตหรือฝั่งเซิร์ฟพัง
--
-- ยิงในเธรดแยกแล้วนับเวลาข้างนอก ครบเวลาแล้วไม่ตอบก็เดินหน้าต่อ
-- เธรดที่ค้างจะค้างของมันไป แต่ไม่ลากลูปหลักไปด้วย
Hub.callTimed = function(fn, arg, secs)
	local done, ok, res = false, false, nil
	task.spawn(function()
		ok, res = pcall(fn, arg)
		done = true
	end)
	local limit = os.clock() + (tonumber(secs) or 4)
	while not done and os.clock() < limit do task.wait(0.03) end
	if not done then
		Hub.Timeouts = (Hub.Timeouts or 0) + 1
		return false, "เซิร์ฟไม่ตอบ"
	end
	if not ok then return false, tostring(res) end
	return res, nil
end

local function moveWarp(target)
	-- พยายามปะไว้ก่อน แต่ไม่บังคับว่าต้องสำเร็จ
	--
	-- วัดแล้ว: ปะสำเร็จ = ไม่ตายเลย  ปะไม่สำเร็จ = ตายราว 1 ใน 3 รอบ
	-- แต่ 2 ใน 3 ที่รอดยังเร็วกว่าเดินหลายเท่า เลยไม่ล็อกไม่ให้วาป
	-- ตั้ง WarpRequirePatch = true ถ้าอยากให้ถอยไปเดินเมื่อปะไม่ได้
	-- ปะไว้ก่อนเสมอ แล้ววาปไม่ว่าผลจะเป็นอย่างไร
	--
	-- ของเดิมเช็คธง acPatched แล้วถอยไปเดินถ้าธงไม่เป็นจริง
	-- ปัญหาคือธงนั้นอ่านได้เป็น nil ทั้งที่ประกาศเป็น false ไว้
	-- (ตรวจด้วยการแปลงเป็นข้อความในเกมเอง คีย์หายไปเลย ไม่ใช่ false)
	-- nil ทำให้ "not acPatched" จริงตลอด = เดินทุกครั้งไม่มีข้อยกเว้น
	-- อาการคือเดินไปชนกำแพงขอบเซฟโซนแล้วไปต่อไม่ได้
	--
	-- ตัดตัวถอยทิ้ง เพราะวัดแล้ววาปด้วยมือไปได้ 981 studs ไม่ตาย
	-- ถ้าเครื่องไหนปะไม่ได้จริงจะตายบ้าง ซึ่งยังดีกว่าเดินชนกำแพงแล้วไม่ได้อะไรเลย
	-- เช็คการปะเฉพาะตอนขาออก ขากลับไม่ต้อง
	-- หนึ่งรอบวาปสองครั้ง (ไปไข่ + กลับเซฟโซน) เรียกทั้งสองครั้งคือทำงานซ้ำเปล่า
	-- ข้ามการปะได้แค่ชั่วคราว ห้ามค้าง
	--
	-- ของเดิมเป็นธงบูลีน เปิดตอนวาปกลับไปฝากไข่แล้วปิดทีหลัง
	-- ถ้ามีอะไรพลาดระหว่างนั้น (ตายกลางทาง / move ขว้าง error)
	-- ธงจะค้างเปิดไว้ตลอดกาล ทุกการวาปหลังจากนั้นข้ามการปะทั้งหมด
	-- อาการ: ตายครั้งแรกแล้วตายรัวๆ ไม่หยุด ทั้งที่ปะได้ตั้งแต่ต้น
	--
	-- ใช้เวลาหมดอายุแทน หมดเวลาแล้วกลับมาปะเองไม่ต้องมีใครสั่งปิด
	-- ห้ามสแกนหน่วยความจำกลางการวาป
	--
	-- ของเดิมเรียก warpReady ตรงนี้ ซึ่งอาจสั่ง patchAntiCheat
	-- ที่ไล่ getgc(true) สองถึงสามรอบ รอบละ 33,000 ฟังก์ชัน
	-- เครื่องแรง 148ms ต่อรอบ เครื่องช้าเป็นวินาที
	-- ผลคือเกมค้างตอนกำลังจะวาปพอดี (ผู้ใช้รายงานตรงกันหลายเครื่อง)
	--
	-- ย้ายการปะไปทำในลูปเบื้องหลังแทน ตรงนี้แค่อ่านธงซึ่งไม่มีค่าใช้จ่าย
	-- ปะยังไม่ติดก็วาปไปก่อน เพราะมีตาข่ายกันตายอีกสองชั้นรออยู่แล้ว

	local _, hrp, hum = char()
	if not hrp or not hum then task.wait(0.5) return false end

	-- เลือด 0 ไม่ได้แปลว่าตาย ถ้าเราปิดสถานะตายไว้
	--
	-- ระบบกันโกงกดเลือดเป็น 0 รัวๆ แต่ตัวละครยังขยับได้ตามปกติ
	-- ของเดิมเห็นเลือด 0 แล้วเลิกทำงานทันที = ค้างทั้งที่ยังไปต่อได้
	-- ดึงเลือดกลับให้ก่อนแล้วไปต่อ ไม่ต้องรออะไร
	if not Hub.stillUp(hum) then task.wait(0.5) return false end

	-- ต้องเทียบกับจุดที่ไปจริง ไม่ใช่จุดที่สั่งไป
	--
	-- snapToGround() กดเป้าหมายลงติดพื้นก่อน ซึ่งอาจต่ำกว่าจุดเดิมหลายสิบ studs
	-- (ไข่วางบนรังที่ยกสูง พื้นจริงอยู่ข้างล่าง)
	-- ของเดิมวาปไปจุดที่กดแล้ว แต่ไปวัดระยะกับ target ดิบ
	-- พอต่างกันเกิน 25 ก็สรุปว่า "ไปไม่ถึง" แล้วเลิกทั้งรอบ ทั้งที่ยืนอยู่ตรงไข่แล้ว
	-- ช่วงรีเซ็ตมีกล่องใหญ่ครอบสนาม อย่ากดพื้น
	--
	-- ปกติเรายิงเรย์หาพื้นก่อนวาป เพื่อกันตัวลอยแล้วโดนฆ่า
	-- แต่ตอนรีเซ็ตมีกล่องขาวคลุมทั้งสนาม เรย์จะไปโดนกล่องแทนพื้นจริง
	-- ปลายทางเลยเพี้ยน = วาปไปผิดที่ = เก็บไม่ติด (วัดจากสถิติ ได้ 5 พลาด 5)
	-- ช่วงนั้นวาปไปพิกัดไข่ตรงๆ เลย ไม่ต้องกด
	local landing
	if fieldIsFresh() or Hub.BoxUp or Config.WarpSnapGround == false then
		landing = target
	else
		landing = snapToGround(target)
	end
	-- ตรวจปลายทางก่อนเขียน ห้ามวาปไปจุดที่ตกแน่ๆ
	--
	-- ของเดิมเขียน CFrame ไปเลยโดยไม่ดูว่าค่านั้นใช้ได้จริงไหม
	-- ถ้าข้อมูลไข่เพี้ยนหรือ snapToGround หาพื้นไม่เจอ จะได้พิกัดที่ตกนอกแมพ
	-- อาการที่ผู้ใช้เจอ: "วาปชนขอบตาย ตกขอบตาย"
	--
	-- เช็คสามอย่าง: เป็นตัวเลขจริงไหม / ต่ำกว่าพื้นสนามไหม / ไกลเกินจริงไหม
	-- ผิดข้อไหนก็ไม่วาป คืน false ให้รอบนั้นข้ามไป ดีกว่าวาปไปตาย
	local lx, ly, lz = landing.X, landing.Y, landing.Z
	if lx ~= lx or ly ~= ly or lz ~= lz then          -- NaN
		Hub.BadTarget = (Hub.BadTarget or 0) + 1
		return false
	end
	if ly < (LANE_Y - 60) or ly > (LANE_Y + 400) then  -- ต่ำกว่าพื้นสนามหรือลอยสูงผิดปกติ
		Hub.BadTarget = (Hub.BadTarget or 0) + 1
		Hub.LastBadTarget = ("y=%.0f (พื้นสนามอยู่ราว %.0f)"):format(ly, LANE_Y)
		return false
	end
	if math.abs(lx) > 20000 or math.abs(lz) > 20000 then
		Hub.BadTarget = (Hub.BadTarget or 0) + 1
		Hub.LastBadTarget = ("x=%.0f z=%.0f ไกลผิดปกติ"):format(lx, lz)
		return false
	end

	-- เดิมเขียน CFrame ทีเดียวถึงเลย  ตอนนี้ไถไปทีละก้าวใต้เพดานความเร็วของเซิร์ฟ
	-- ตรรกะรอบนอกทั้งหมด (แวะจุดกลางก่อน / ตรึงตอนกล่องขึ้น / เช็คว่าถึงจริง) เหมือนเดิมหมด
	Hub.glide(hrp, hum, landing)
	Hub.LastWarpAt = os.clock()   -- ไว้แยกว่าตายเพราะวาปหรือเพราะอย่างอื่น

	-- ช่วงสนามรีเซ็ต เกมดีดเราออกจากสนามกลับเซฟโซน
	--
	-- วัดจริง: วาปไปถึง x=2808 ตรงไข่ สูงถูกต้อง เลือดเต็ม
	-- แต่ 0.15 วินาทีต่อมาอยู่ที่ x=512 = เซฟโซน ห่างเป้า 2,296 studs พอดี
	-- (บันทึกไว้: d=2296 fresh=true y=72->71 hp=100)
	-- เขียน CFrame ครั้งเดียวจึงไม่พอ ต้องเขียนทับทุกเฟรมสู้กับตัวที่ดึงกลับ
	-- ต้องตรึงยาวคลุมไปถึงตอนยิงคำสั่งด้วย
	--
	-- รอบแรกที่ลองตรึงแค่ช่วงรอ 0.15 วิ แล้วปล่อยมือ ยังพลาดเหมือนเดิม
	-- (d=2882 fresh=true y=71->72) เพราะปล่อยแล้วโดนดีดกลับทันทีก่อนวัดผล
	-- ให้ตัวตรึงเบื้องหลังถือยาว 2 วินาที คลุมทั้งช่วงรอ ช่วงวัด และช่วงยิง carry
	-- ตรึงทั้งช่วงกล่องขึ้นและช่วงหลังไข่รีเซ็ต
	-- สองช่วงนี้คือช่วงที่เกมดีดเราออกจากสนาม นอกนั้นไม่ต้องตรึง
	if fieldIsFresh() or Hub.BoxUp then Hub.pinAt(landing, 2) end

	-- ต้องรอให้เซิร์ฟเวอร์รับรู้ตำแหน่งใหม่ก่อน ไม่งั้นคำสั่งถัดไปถูกปฏิเสธ
	--
	-- วัดจริง: วาปแล้วยิงเก็บไข่ทันที
	--   รอ 0.00 วิ -> false "Enter the gameplay area first"
	--   รอ 0.06 วิ -> false เหมือนกัน   <- ค่าเดิมที่ใช้ พลาดทุกครั้ง
	--   รอ 0.15 วิ -> true
	-- ใช้ 0.18 เผื่อ ping แกว่ง
	--
	-- ที่ต้องแก้เพราะข้อความที่ได้ทำให้เข้าใจผิดว่า "ยังไม่ได้เข้าเขต"
	-- โค้ดเลยพากลับไปเดินข้ามเส้นใหม่ทั้งที่แค่ยิงเร็วไป = เสียเที่ยวและมีเดินโผล่มา
	-- รอให้เซิร์ฟรับรู้ตำแหน่งใหม่
	-- วัดแล้ว 0.06 พลาดทุกครั้ง · 0.15 ผ่าน  ค่าเริ่มต้น 0.18 เผื่อ ping แกว่ง
	-- ลดได้ถ้าเน็ตดี แต่ต่ำเกินไปจะเก็บไม่ติดแล้วเสียเที่ยวแทน
	task.wait(math.max(0.05, tonumber(Config.WarpSettle) or 0.18))

	local _, hrp2, hum2 = char()
	if not hrp2 or not hum2 or hum2.Health <= 0 then return false end

	-- ถือว่าถึงถ้าอยู่ใกล้จุดที่ไปจริง หรือใกล้เป้าหมายเดิมอย่างใดอย่างหนึ่ง
	-- เผื่อกรณี snapToGround หาพื้นไม่เจอแล้วคืนค่าเดิมกลับมา
	local here = hrp2.Position
	local okArrive = (here - landing).Magnitude < 25 or (here - target).Magnitude < 25
	if not okArrive then
		-- บันทึกไว้ดูว่าไปตกอยู่ตรงไหน ห่างเท่าไหร่ ตอนสนามเพิ่งรีเซ็ตหรือเปล่า
		Hub.LastWarpMiss = ("d=%.0f fresh=%s y=%.0f->%.0f hp=%.0f"):format(
			(here - target).Magnitude, tostring(fieldIsFresh()),
			landing.Y, here.Y, hum2.Health)
		Hub.WarpMiss = (Hub.WarpMiss or 0) + 1
	else
		Hub.WarpHit = (Hub.WarpHit or 0) + 1
	end
	return okArrive
end

-- ห่อไว้เพื่อให้ noclip ปิดทุกทางออก รวมถึงตอน error
local function move(target)
	-- ตรวจปลายทางก่อนทุกโหมด ไม่ใช่แค่ warp
	--
	-- โหมดเดินก็พาไปตกนอกแมพได้ถ้าข้อมูลไข่เพี้ยน แค่ช้ากว่าเท่านั้น
	-- เช็คตรงนี้ที่เดียวครอบทุกโหมด ไม่ต้องไปใส่ซ้ำในแต่ละตัว
	if typeof(target) ~= "Vector3" then return false end
	local tx, ty, tz = target.X, target.Y, target.Z
	if tx ~= tx or ty ~= ty or tz ~= tz then
		Hub.BadTarget = (Hub.BadTarget or 0) + 1
		return false
	end
	if math.abs(tx) > 20000 or math.abs(tz) > 20000 or ty < -500 then
		Hub.BadTarget = (Hub.BadTarget or 0) + 1
		Hub.LastBadTarget = ("x%.0f y%.0f z%.0f"):format(tx, ty, tz)
		return false
	end

	-- โหมด auto: เลือกให้เองตามว่าเครื่องนี้ปะระบบกันโกงได้ไหม
	--
	-- วัดไว้แล้ว: ปะสำเร็จ = วาปไปกลับไม่ตายเลย
	--            ปะไม่สำเร็จ = ตายราว 1 ใน 3 รอบ ของที่ถืออยู่หายด้วย
	-- executor ฟรีหลายตัวไม่มี ฟังก์ชันครอบทับโค้ดเกม เลยปะไม่ได้
	-- ให้ถอยไปโหมด tween ซึ่งช้ากว่าแต่ไม่ตาย ดีกว่าวาปแล้วตายวนไปเรื่อยๆ
	local mode = tostring(Config.MoveMode or "warp")
	if mode == "auto" then
		-- อ่านธงอย่างเดียว ห้ามสั่งสแกน
		-- warpReady อาจไปเรียก patchAntiCheat ซึ่งไล่ getgc นับหมื่นฟังก์ชัน
		-- ถ้าเรียกตรงนี้จะค้างทุกครั้งที่จะเคลื่อนที่ ลูปเบื้องหลังปะให้อยู่แล้ว
		mode = (acPatched == true) and "warp" or "tween"
	end

	-- ตาข่ายกันตายวน ไม่ใช่การยอมแพ้ถาวร
	--
	-- ทุกเครื่องควรได้วาปเหมือนกันหมด เพราะ executor ที่เจอจริงมีของครบ
	-- (Delta ตรวจแล้ว: ฟังก์ชันอ่าน/แก้หน่วยความจำครบ ครบ)
	-- แต่ถ้าเครื่องไหนวาปแล้วตายจริงๆ ปล่อยให้ตายวนคือของในมือหายทุกรอบ
	--
	-- ของเดิมถอยไป tween ถาวรจนกว่าจะรันใหม่ ซึ่งแรงเกินไป
	-- อาการตายอาจมาจากจังหวะชั่วคราว (เกมแลค ปะหลุดชั่วขณะ)
	-- พักไปเดินสัก 3 นาทีแล้วกลับมาวาปใหม่ ถ้ายังตายอีกก็พักอีกรอบ
	-- เครื่องที่วาปได้ปกติจะไม่แตะโค้ดนี้เลย เพราะไม่เคยตาย
	if mode == "warp" and (Hub.WarpRestUntil or 0) > os.clock() then
		mode = "tween"
	end
	Hub.AutoMode = mode

	-- tween/step ให้วาปตรงๆ ด้วย
	--
	-- เดิมสองโหมดนี้เลื่อนตัวทีละนิดเพราะกลัวโดนระบบกันโกงจับ
	-- แต่ตอนนี้ปิดทั้งตัวที่สั่งฆ่าและตัวที่ลากตำแหน่งกลับไปแล้ว
	-- (วัดจริง: pushedBack = 0 จากเดิม 4 ครั้งต่อรอบ)
	-- วาปตรงๆ จึงปลอดภัยพอๆ กัน และเร็วกว่าหลายเท่า
	--
	-- ตั้ง TweenAsWarp = false ถ้าอยากได้พฤติกรรมเดิม
	if Config.TweenAsWarp ~= false and (mode == "tween" or mode == "step") then
		mode = "warp"
		Hub.AutoMode = mode
	end

	local fn = moveTween
	if mode == "step" then fn = moveStep
	elseif mode == "warp" then fn = moveWarp
	elseif mode == "walk" then fn = Hub.moveWalk end

	-- โหมดเดินจริงไม่ต้อง noclip
	-- มันเดินด้วยขาจริงๆ ปิดการชนเมื่อไหร่ก็ร่วงทะลุพื้นทันที
	if mode == "walk" then
		local ok, res = pcall(fn, target)
		if not ok then log("move error:", res) return false end
		return res
	end

	setNoclip(true)
	local ok, res = pcall(fn, target)
	setNoclip(false)
	if not ok then
		log("move error:", res)
		return false
	end
	return res
end

-- ดึงเลือดกลับทุกเฟรม
--
-- ระบบกันโกงกดเลือดเป็น 0 ถี่กว่าที่เราตรวจทุก 0.5 วินาทีมาก
-- ตัวละครเลยอยู่ในสภาพเลือด 0 เกือบตลอด และโค้ดเคลื่อนที่ทุกตัว
-- เช็ค Health <= 0 แล้วเลิกทำงาน = ค้างกลางสนามไปไหนไม่ได้
-- (วัดจริง: hp=0 ค้างที่ x1873 ทั้งที่ deadEnabled=false แล้ว)
--
-- ต้องไล่ให้ทันด้วยการเขียนทุกเฟรม ราคาถูกมากเพราะเป็นแค่การเทียบตัวเลข
if Hub.reviveConn then pcall(function() Hub.reviveConn:Disconnect() end) end
Hub.reviveConn = game:GetService("RunService").Heartbeat:Connect(function()
	if not alive() then
		pcall(function() Hub.reviveConn:Disconnect() end)
		return
	end
	if Config.BlockDeath == false then return end
	local c = LocalPlayer.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	if hum.Health <= 0 and hum.MaxHealth > 0 then
		pcall(function() hum.Health = hum.MaxHealth end)
		Hub.Revived = (Hub.Revived or 0) + 1
	end
end)

-- เฝ้าดูว่าวาปแล้วตายไหม แล้วถอยเองถ้าตายซ้ำ
--
-- ธงว่า "ปะสำเร็จ" เชื่อไม่ได้ทั้งหมด บาง executor ปะได้แค่ครึ่งเดียว
-- ตัวชี้ขาดที่โกหกไม่ได้คือ "วาปแล้วรอดไหม"
-- ตาย 2 ครั้งใน 3 นาทีถือว่าเครื่องนี้วาปไม่ไหว ถอยไป tween ถาวรจนกว่าจะรันใหม่
-- ยอมช้าดีกว่าตายวนแล้วของที่ถืออยู่หายทุกรอบ
task.spawn(function()
	local deaths, firstAt = 0, 0
	while true do
		task.wait(0.5)
		if not alive() then break end
		local c = LocalPlayer.Character
		local hum = c and c:FindFirstChildOfClass("Humanoid")

		-- ต้องเช็ค Config.BlockDeath ตรงนี้ด้วย ไม่ใช่เช็คแค่ที่ Hub.blockLocalDeath
		--
		-- ของเดิมลูปนี้ปิดสถานะ Dead ซ้ำทุก 0.5 วินาทีโดยไม่ดูคอนฟิกเลย
		-- ตั้ง BlockDeath = false ไปก็ไม่มีผล มันปิดให้ใหม่ตลอด
		-- ผลคือตัวละครตายไม่ลง เกิดใหม่ไม่ได้ ค้างครึ่งๆ กลางๆ
		-- แล้วเกมปฏิเสธทุกคำสั่งเพราะสถานะตัวละครเพี้ยน
		-- (ผู้ใช้เจอตรงๆ: กดเก็บไข่เองไม่ติด ทั้งที่ยืนอยู่ตรงไข่)
		if hum and Config.BlockDeath == true then
			pcall(function()
				if hum:GetStateEnabled(Enum.HumanoidStateType.Dead) then
					hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
					Hub.DeathReblocked = (Hub.DeathReblocked or 0) + 1
				end

				-- ปิดสถานะตายอย่างเดียวไม่พอ ต้องดึงเลือดกลับด้วย
				--
				-- ห้ามตายแล้วเลือดยังลงถึง 0 ได้ ตัวละครค้างสภาพครึ่งๆ
				-- ไม่ตาย ไม่เกิดใหม่ ขยับไม่ได้ และโค้ดทุกจุดเช็ค Health <= 0
				-- แล้วคืนค่าเท็จ ลูปเลยวนเปล่าไม่ทำอะไรเลย (เห็นเป็นผียืนนิ่ง)
				--
				-- ตัวละครเป็นของฝั่งเราเขียนเลือดกลับได้ ถ้าคนสั่งฆ่าอยู่ฝั่งเรา
				-- ถ้าเซิร์ฟเป็นคนสั่ง เขียนกลับไม่ติดก็ปล่อยให้ตายตามปกติ
				if hum.Health <= 0 and hum.MaxHealth > 0 then
					hum.Health = hum.MaxHealth
					Hub.Revived = (Hub.Revived or 0) + 1

					-- โดนกดเลือดรัวๆ = สู้ไม่ไหว ต้องถอย ไม่ใช่ฝืนสู้ต่อ
					--
					-- ปิดสถานะตายกันได้แค่ "ไม่ตาย" แต่กันการโดนกดเลือดไม่ได้
					-- ถ้าการปะล้มเหลว ระบบกันโกงจะกดเลือดซ้ำทุกเสี้ยววินาที
					-- ตัวละครทำอะไรไม่ได้ ค้างอยู่กับที่ (วัดจริง: ดึงกลับ 16 ครั้งใน 28 วิ)
					-- ฝืนวาปต่อไม่มีประโยชน์ พักไปเดินสักพักแล้วค่อยลองใหม่
					local w = os.clock()
					if (w - (Hub.ReviveWindow or 0)) > 15 then
						Hub.ReviveWindow, Hub.ReviveBurst = w, 0
					end
					Hub.ReviveBurst = (Hub.ReviveBurst or 0) + 1
					if Hub.ReviveBurst >= 5 and (Hub.WarpRestUntil or 0) <= w then
						local rest = math.max(30, tonumber(Config.WarpRestAfterDeaths) or 180)
						Hub.WarpRestUntil = w + rest
						Hub.ReviveBurst = 0
						pcall(patchAntiCheat)
						log(("โดนกดเลือดรัวๆ - ปะกันโกงไม่ติด พักวาป %d วินาที"):format(rest))
					end
					-- เขียนกลับไม่ติดสามครั้งติด แปลว่าห้ามไม่อยู่จริง
					-- เปิดสถานะตายคืนให้เกิดใหม่ตามปกติ ดีกว่าค้างเป็นผี
					if (Hub.Revived or 0) % 3 == 0 and hum.Health <= 0 then
						hum:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
						Hub.DeathBlocked = false
						log("ห้ามตายไม่อยู่ - ปล่อยให้เกิดใหม่ตามปกติ")
					end
				end
			end)
		end

		if hum and not hum:GetAttribute("__hmdWatched") then
			pcall(function() hum:SetAttribute("__hmdWatched", true) end)
			hum.Died:Connect(function()
				if Hub.AutoMode ~= "warp" and Config.MoveMode ~= "warp" then return end

				-- ตายเพราะวาปจริงไหม
				--
				-- ของเดิมนับทุกการตายเป็นความผิดของการวาป
				-- แต่ตายเพราะการ์ดไล่ตี หรือโดนผู้เล่นอื่นฆ่าตอนถือไข่ ก็มี
				-- นับรวมแล้วครบสองครั้งเมื่อไหร่ ระบบจะปิดวาปทิ้งทั้งที่วาปไม่มีปัญหา
				-- อาการที่เห็นคือจู่ๆ ก็เดินต้วมเตี้ยมข้ามสนามเหมือนค้าง
				-- (เจอจริง: ตาย 2 ครั้ง วาปพลาด 0 ครั้ง แล้วโดนสั่งพักวาป)
				--
				-- ตายเพราะวาปจะเกิดภายในเสี้ยววินาทีหลังเขียนตำแหน่ง
				-- ห่างเกิน 2 วินาทีถือว่าคนละเรื่อง ไม่นับ
				if os.clock() - (Hub.LastWarpAt or 0) > 2 then
					Hub.OtherDeaths = (Hub.OtherDeaths or 0) + 1
					return
				end
				local now = os.clock()
				if now - firstAt > 180 then deaths, firstAt = 0, now end
				deaths = deaths + 1
				Hub.WarpDeaths = deaths
				if deaths >= 2 then
					deaths = 0
					local rest = math.max(30, tonumber(Config.WarpRestAfterDeaths) or 180)
					Hub.WarpRestUntil = os.clock() + rest
					pcall(patchAntiCheat)   -- ปะใหม่ก่อน เผื่อแค่หลุดชั่วคราว
					log(("วาปแล้วตาย 2 ครั้ง - พักไปเดิน %d วินาทีแล้วกลับมาวาปใหม่"):format(rest))
				end
			end)
		end
	end
end)

-- เดินติดพื้นเสมอ ไม่ว่าตั้งโหมดอะไรไว้
--
-- ใช้กับช่วงเข้า/ออกแปลง และช่วงเข้าหาไข่
-- ระยะพวกนี้สั้นและมีรั้ว/สิ่งกีดขวาง การขึ้นบินแล้วร่อนลงเสียเวลากว่า
-- และที่สำคัญ ถ้าบินแล้วร่อนลงไม่ตรงจุด จะวางไข่ไม่ได้เพราะเซิร์ฟเช็คระยะแบบ 3 มิติ
-- (เคยเจอ: บินกลับมาแล้วค้างที่ SAFE ZONE ไข่ยังอยู่ในมือ ไม่ได้เข้าแปลงเลย)
local function moveGround(target)
	setNoclip(true)
	local ok, res = pcall(moveStep, target)
	setNoclip(false)
	if not ok then
		log("move error:", res)
		return false
	end
	return res
end

-- ตรึงตำแหน่งไว้ชั่วครู่
-- แท่นวิ่งในแปลงเป็นพื้นเลื่อน ยืนเฉยๆ แล้วโดนพาไปเรื่อยๆ
-- กระโดดอย่างเดียวไม่พอ เพราะตกลงมาก็โดนพาต่อ ต้องเขียนทับตำแหน่งค้างไว้
local function settle(target, seconds)
	-- ห้ามใช้ตัวนี้ "พาไป" ที่หมาย  มันมีไว้ "ตรึงอยู่กับที่" เท่านั้น
	--
	-- ข้างล่างเขียน hrp.CFrame ทับทุก 0.08 วิ ถ้าตัวละครยังอยู่ห่างจากเป้าหมาย
	-- บรรทัดแรกที่เขียนคือการวาปข้ามระยะทั้งหมดในเฟรมเดียว
	-- ซึ่งเป็นสิ่งที่แอนตี้ชีตจับแล้วสั่ง Correction -> Humanoid.Health = 0
	--
	-- วัดจริงในเกม: เจอความเร็วเฟรมเดียว 1,027 / 1,046 / 1,197 / 22,045 studs/s
	-- กระจุกอยู่แถว x507-558 คือตรงเส้นแดงพอดี แล้วตายตามมา
	-- ต้นทางคือ landAt() ที่เรียก settle() ทั้งที่ตัวยังอยู่ในแปลง ห่างเป็นร้อย studs
	local _, hrpStart = char()
	if hrpStart and (hrpStart.Position - target).Magnitude > 25 then
		-- โหมดวาปไม่ต้องเดินไปทีละก้อน ปัญหาความเร็วเฟรมเดียวข้างบนแก้ที่ต้นเหตุแล้ว
		-- (ปิดส่วนลงมือของตัวตรวจจับ ดู patchAntiCheat) ไปถึงในเฟรมเดียวได้เลย
		if Config.MoveMode == "warp" then
			moveWarp(target)
		else
			moveGround(target)   -- เดินไปให้ถึงก่อน แบบก้อนละไม่เกิน Step
		end
	end

	local t0 = os.clock()
	while os.clock() - t0 < (seconds or 1) do
		if not alive() then return end
		local _, hrp = char()
		if not hrp then return end

		-- ถ้ายังห่างอยู่ ก็อย่าเพิ่งกระชาก ปล่อยให้รอบหน้าจัดการ
		if (hrp.Position - target).Magnitude > 25 then return end

		hrp.CFrame = CFrame.new(target)
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
		task.wait(0.08)
	end
end

local function jump()
	local _, _, hum = char()
	if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
end

-- ถึงจุดหมายแล้วเช็คว่าโดนพื้นเลื่อนพาไปไหม ถ้าใช่ก็ดีดออก
local function landAt(target)
	-- โหมดวาป: ทับเป้าหมายไปเลย ไม่ต้องกระโดดหนีแท่นวิ่ง
	--
	-- ท่ากระโดด-ลอยขึ้น-เดินกลับ ข้างล่างมีไว้แก้ตอนโดนแท่นวิ่งกลางแปลงพาไถล
	-- ซึ่งวาปแก้ได้ตรงกว่า แค่เขียนตำแหน่งทับซ้ำสองสามเฟรมก็อยู่แล้ว
	--
	-- เคยใส่ท่ากระโดดหนีลูกวิ่ง + ตัวเลี่ยงลูกวิ่งตรงนี้ แล้ววัดได้แย่ลง (เก็บไข่ 0 ฟอง)
	-- ถอดออกกลับมาจุดที่วัดได้ 16 ฟอง/ตาย 0  ถ้าจะแก้เรื่องลูกวิ่งต้องใส่ทีละตัวแล้ววัด
	if Config.MoveMode == "warp" then
		for _ = 1, 3 do
			local _, h = char()
			if not h then return false end
			h.CFrame = CFrame.new(snapToGround(target))
			h.AssemblyLinearVelocity = Vector3.zero
			task.wait(0.05)
		end
		local _, hEnd = char()
		return hEnd ~= nil and (hEnd.Position - target).Magnitude < 12
	end

	settle(target, 1)

	local _, hrp = char()
	if not hrp then return false end
	if (hrp.Position - target).Magnitude < 12 then return true end

	log("ติดแท่นวิ่ง - กระโดดออก")
	jump()
	task.wait(0.25)
	setNoclip(true)
	for _ = 1, 6 do
		local _, h = char()
		if not h then break end
		h.CFrame = CFrame.new(h.Position + Vector3.new(0, 6, 0))
		h.AssemblyLinearVelocity = Vector3.zero
		task.wait(0.06)
	end

	-- ต้องเป็น moveGround ห้ามใช้ move()
	--
	-- ตัวนี้ทำงานอยู่ "ในแปลง" ตอนโดนแท่นวิ่งพาไถล
	-- ถ้าใช้ move() แล้วโดนพาไถลไกลเกิน Step*2 (110) โหมดบินจะยกตัวขึ้นทันที
	-- = ขึ้นบินตั้งแต่ยังอยู่ในแปลง ยังไม่ข้ามเส้นแดงด้วยซ้ำ
	-- (วัดจริง: จุดยกตัว x491 z-304 ซึ่งคือ SpawnPoint ของแปลงตัวเอง 3 ครั้งจาก 10)
	moveGround(target)
	setNoclip(false)
	settle(target, 1)

	local _, h2 = char()
	return h2 ~= nil and (h2.Position - target).Magnitude < 25
end

local function enterGameplayZone()
	local _, hrp = char()
	if not hrp then return false end
	if hrp.Position.X > GAMEPLAY_LINE_X + 10 then return true end

	-- ตั้งหลักก่อนข้ามเส้น  ต้องติดพื้นเท่านั้น ห้ามขึ้นบินฝั่งเซฟโซน
	moveGround(Vector3.new(GAMEPLAY_LINE_X - 18, LANE_Y, LANE_Z))

	-- ข้ามเส้นด้วยก้าวเล็กๆ ไม่งั้นกระโดดข้าม trigger ไปเลย
	-- แล้วเซิร์ฟจะตอบ "Enter the gameplay area first"
	for _ = 1, 12 do
		local _, h = char()
		if not h then return false end
		h.CFrame = CFrame.new(h.Position + Vector3.new(4, 0, 0))
		h.AssemblyLinearVelocity = Vector3.zero
		task.wait(0.06)
	end
	return true
end

-- ออกตัวช้าๆ หลังเพิ่งข้ามเส้นเข้าโซน
--
-- ตอนเพิ่งข้ามเส้น เซิร์ฟเพิ่งบันทึกตำแหน่งใหม่ให้เรา
-- ถ้าอัดเต็มความเร็วทันทีจากจุดนั้น มันจะเห็นเป็นการกระโดดไกลผิดปกติแล้วลากกลับ
-- ค่อยๆ ไต่ออกไปสองสามก้าวก่อน ให้ฝั่งเซิร์ฟตามทัน แล้วค่อยเร่ง
-- ชะงักตรงรอยต่อก่อนอัดเต็มสปีด
--
-- ตรึงตัวให้นิ่งสนิท (ความเร็วเป็นศูนย์) ไม่ใช่แค่ task.wait เฉยๆ
-- เพราะถ้าปล่อยให้ยังมีแรงเหลือค้างอยู่ พอเริ่มขาใหม่มันจะบวกกันแล้วพุ่งเกิน
local function warmupHold()
	local hold = math.max(0, tonumber(Config.WarmupHold) or 1)
	if hold <= 0 then return end

	local t0 = os.clock()
	while os.clock() - t0 < hold do
		if not Config.Running or not alive() then return end
		local _, h = char()
		if not h then return end
		h.AssemblyLinearVelocity = Vector3.zero
		h.AssemblyAngularVelocity = Vector3.zero
		task.wait(0.05)
	end
end

local function warmupRun()
	-- โหมดวาปไม่ต้องไต่ความเร็ว
	--
	-- การไต่มีไว้หลบตัวตรวจความเร็วของเกมอย่างเดียว ซึ่งตอนนี้ปิดส่วนลงมือไปแล้ว
	-- วัดแล้วช่วงนี้กินไป 2.5 วินาทีต่อรอบ (x648 -> x1022) โดยไม่ได้อะไรกลับมา
	-- ถ้าปะไม่สำเร็จ warpReady() จะเป็น false แล้วตกไปไต่ตามปกติ กันตายไว้
	if Config.MoveMode == "warp" then return end

	local mul = math.max(1, tonumber(Config.WarmupGapMul) or 2.5)
	local n = math.max(0, math.floor(tonumber(Config.WarmupSteps) or 8))
	if n == 0 then return end

	local _, hrp = char()
	if not hrp then return end

	-- ระยะไต่ความเร็ว: เอาค่าที่มากกว่าระหว่าง "จำนวนก้าว" กับ "ไต่ให้ถึงพิกัด X"
	--
	-- นับก้าวอย่างเดียวไม่พอ 55 x 8 = 440 studs จบที่ x=1020 แค่พ้น Desert
	-- แล้วอัดเต็มสปีดทันทีทั้งที่ยังไม่ถึง Jungle (1183) = จุดที่โดนลากกลับ
	local warmDist = Config.Step * n
	local untilX = tonumber(Config.WarmupUntilX) or 0
	if untilX > 0 then
		warmDist = math.max(warmDist, untilX - hrp.Position.X)
	end
	if warmDist <= 0 then return end   -- เลยจุดนั้นมาแล้ว ไม่ต้องไต่

	-- โหมดก้อน: ไต่ทีละก้าวโดยยืดเวลาพัก
	if Config.MoveMode == "step" then
		n = math.max(n, math.ceil(warmDist / math.max(1, Config.Step)))
		for _ = 1, n do
			if not Config.Running or not alive() then return end
			local _, h, hum = char()
			if not h or hum.Health <= 0 then return end
			h.CFrame = CFrame.new(h.Position + Vector3.new(Config.Step, 0, 0))
			h.AssemblyLinearVelocity = Vector3.zero
			task.wait(Config.Gap * mul)
		end
		warmupHold()   -- ชะงักตรงรอยต่อ ก่อนขาถัดไปจะอัดเต็มสปีด
		return
	end

	-- โหมดบิน: ห้ามไต่ออกด้วยเท้าบนพื้น
	--
	-- ของเดิมตกมาใช้สาขา tween ข้างล่าง = ไต่ Step x WarmupSteps (440 studs) "บนพื้น"
	-- ทั้งช่วงนั้นอยู่นอกเส้นแดงและวิ่งช้ากว่าปกติ สัตว์เฝ้าไข่เลยไล่ทัน
	-- (วัดจริง: ตายที่ x=809 y=70 ระหว่างไต่ ทั้งที่ยังไม่ถึงไข่ด้วยซ้ำ)
	--
	-- ยกตัวขึ้นก่อนแล้วค่อยไต่ความเร็วบนอากาศ ได้ผลกันเซิร์ฟลากกลับเหมือนเดิม
	-- แต่พ้นระยะสัตว์เฝ้า และไม่ปล่อยพื้นเสกทิ้งท้าย ขาต่อไปจะบินต่อได้เลย

	-- โหมด tween: ระยะเท่ากัน แต่ลากต่อเนื่องด้วยความเร็วที่ลดลง
	local dist = warmDist
	local target = hrp.Position + Vector3.new(dist, 0, 0)
	local dur = dist / (targetSpeed() / mul)

	local tw = TweenService:Create(hrp,
		TweenInfo.new(dur, Enum.EasingStyle.Linear),
		{ CFrame = CFrame.new(target) })
	tw:Play()

	local deadline = os.clock() + dur + 1
	while os.clock() < deadline do
		if not Config.Running or not alive() then break end
		local _, h, hum = char()
		if not h or hum.Health <= 0 then break end
		h.AssemblyLinearVelocity = Vector3.zero
		if tw.PlaybackState == Enum.PlaybackState.Completed then break end
		task.wait()
	end
	tw:Cancel()
	warmupHold()   -- ชะงักตรงรอยต่อเหมือนกัน ก่อนขาถัดไปจะอัดเต็มสปีด
end

--==================================================================
-- รอบรีเซ็ตกลางวัน/กลางคืน
--
-- เกมมีรอบรีเซ็ตไข่ ตอนกลางคืนโซนเกมเพลย์จะปิดแล้วดีดผู้เล่นกลับฐาน
-- ถ้าบอทยังวิ่งอยู่ตอนนั้น = โดนดีดกลางทาง ค้าง แล้วรอบถัดไปพัง
-- อ่านสถานะจาก UI ตัวเดียวกับที่ผู้เล่นเห็น
--==================================================================
-- จำที่อยู่ของ GUI ไว้ ไม่ค้นใหม่ทุกครั้ง
--
-- FindFirstChild(name, true) ไล่ทุกลูกหลานใน PlayerGui ซึ่งใหญ่มากในเกมนี้
-- ตัวเฝ้ารีเซ็ตเรียก 3 รอบทุก 0.1 วินาที = ไล่ต้นไม้ 30 รอบต่อวินาที
-- เป็นตัวกินเฟรมโดยตรง อาการที่ผู้ใช้เจอคือกระตุกตอนวาป
-- ของที่หาเจอแล้วไม่ย้ายที่ จำไว้ใช้ซ้ำได้ ค้นใหม่เฉพาะตอนของหายไปจริง
-- ตารางแคชอยู่บน Hub (Luau จำกัด local ระดับบนสุด 200 ตัว)

local function findGui(name)
	Hub.guiCache = Hub.guiCache or {}
	local hit = Hub.guiCache[name]
	if hit and hit.Parent then return hit end
	local pg = LocalPlayer:FindFirstChild("PlayerGui")
	local found = pg and pg:FindFirstChild(name, true) or nil
	Hub.guiCache[name] = found
	return found
end

-- ประกาศไว้ก่อน เพราะ isResetting() ต้องใช้ แต่ตัวจริงอยู่ข้างล่าง
local snapshot

-- ประกาศไว้ก่อน ตัวจริงอยู่ใต้ isResetting()
local secondsToReset
local clearSnapCacheFwd   -- ตัวจริงอยู่ใต้ snapshot() ประกาศไว้ก่อนเพราะ noteFieldReset ต้องใช้

-- จับว่าสนามเพิ่งรีเซ็ต
--
-- ตัวนับถอยหลังเด้งกลับขึ้น = รอบใหม่เริ่มแล้ว ไข่ชุดใหม่เต็มสนาม
-- ช่วงนี้เก็บก่อนไม่ต้องเทียบราคากับคอก เพราะไข่หายไปเองเมื่อถึงเช้า
-- เก็บมาแล้วขายทีหลังยังได้เงิน ปล่อยหายคือได้ศูนย์
local lastLeftSeen, freshUntil, resetSettleUntil = nil, 0, 0
local noteFieldResetNow

local function noteFieldReset()
	local left = secondsToReset()
	if left then
		if lastLeftSeen and left > lastLeftSeen + 60 then
			-- สนามเปลี่ยนชุดไข่ใหม่หมด แคชเก่าใช้ไม่ได้แล้ว
			-- ถ้าไม่ล้าง รอบแรกหลังรีเซ็ตจะไปยิง Uid ที่หายไปแล้ว
			if clearSnapCacheFwd then clearSnapCacheFwd() end

			-- หน่วงนิดหนึ่งก่อนยิงใบแรก
			-- ไข่โผล่ในรายการก่อนที่เซิร์ฟจะพร้อมให้เก็บจริง ยิงเร็วไปจะโดนปฏิเสธ
			resetSettleUntil = os.clock() + math.max(0, tonumber(Config.ResetSettleDelay) or 1.5)

			freshUntil = os.clock() + math.max(0, tonumber(Config.GrabAfterResetFor) or 0)
			-- จับเวลาไว้ดูว่า 6 วินาทีที่ช้าอยู่ เสียไปกับรอไข่โผล่ หรือรอเราตัดสินใจ
			Hub.ResetSeenAt = os.clock()
			Hub.GapEggSeen, Hub.GapFirstGrab = nil, nil
			log("สนามรีเซ็ตแล้ว - รอให้เซิร์ฟพร้อมก่อน")
		end
		lastLeftSeen = left
	end
end

-- ยกธง "เพิ่งรีเซ็ต" ทันที ไม่ต้องรอตัวนับเด้ง
function noteFieldResetNow()
	if clearSnapCacheFwd then clearSnapCacheFwd() end
	resetSettleUntil = os.clock() + math.max(0, tonumber(Config.ResetSettleDelay) or 0)
	freshUntil = os.clock() + math.max(0, tonumber(Config.GrabAfterResetFor) or 0)
	Hub.ResetSeenAt = os.clock()
	Hub.GapEggSeen, Hub.GapFirstGrab = nil, nil
end

function fieldIsFresh()
	return os.clock() < freshUntil
end

-- เพิ่งรีเซ็ต ยังไม่ถึงเวลาที่เซิร์ฟพร้อม
local function resetStillSettling()
	return os.clock() < resetSettleUntil
end

local function isResetting()
	-- เช็ค GUI ก่อนเพราะอ่านในเครื่อง ไม่เสียอะไร
	--
	-- ปกติ GUI บอกว่าไม่ได้รีเซ็ต = จบตรงนี้ ไม่ต้องยิงเซิร์ฟเลย
	-- ของเดิมผมเอาการยิงเซิร์ฟไว้ก่อน = เสีย 231ms ทุกครั้งที่ถาม
	-- (วัดได้ 3.6 ครั้งต่อการเก็บไข่หนึ่งใบ = 830ms ต่อใบ)
	local pg = LocalPlayer:FindFirstChild("PlayerGui")
	local starter = pg and pg:FindFirstChild("ResetStartTimer")
	local soon = findGui("EndingSoon")
	local guiSaysReset =
		(starter and starter:IsA("SurfaceGui") and starter.Enabled)
		or (soon and soon:IsA("GuiObject") and soon.Visible)

	if not guiSaysReset then return false end

	-- GUI ว่ารีเซ็ต แต่ธงนี้เปิดค้างไว้ไม่ยอมปิด ต้องยืนยันด้วยของจริง
	-- ถ้ามีไข่ให้เก็บอยู่ = เก็บได้ ไม่ต้องรอ
	for _, r in pairs(snapshot()) do
		local u = tostring(r.Uid)
		if r.State == "Slot" and #u >= 24 and u:sub(1, 5) ~= "First" then
			return false
		end
	end
	return true
end

function secondsToReset()
	local frame = findGui("TimeLeft")
	local lbl = frame and frame:FindFirstChild("TextLabel", true)
	if not lbl or not lbl.Visible then return nil end

	local txt = lbl.Text
	local m = tonumber(txt:match("(%d+)%s*m")) or 0
	local s = tonumber(txt:match("(%d+)%s*s")) or 0
	local total = m * 60 + s
	return total > 0 and total or nil
end

-- ตรวจรีเซ็ตเบื้องหลัง ไม่ใช่ตอนต้นรอบอย่างเดียว
--
-- noteFieldReset() เดิมถูกเรียกที่ต้นรอบเก็บไข่เท่านั้น
-- ถ้าตอนนั้นติดฟักไข่ 8 ฟองอยู่ (ใช้เวลา ~7 วินาที) จะไม่มีใครรู้เลยว่าไข่รีเซ็ตแล้ว
-- ธง fieldIsFresh จึงไม่ยกขึ้น ตัวหยุดงานบ้านที่อาศัยธงนี้ก็ไม่ทำงานตาม
-- วัดจริง: รอบที่ติดงานบ้าน เก็บใบแรกได้วินาทีที่ 13.1  รอบที่ว่าง วินาทีที่ 1.8
task.spawn(function()
	while true do
		-- 0.1 วินาทีถี่เกินความจำเป็น รีเซ็ตเกิดทุก 5 นาที
		-- 0.25 ยังจับได้ทันเหมือนเดิม แต่ลดภาระลงเกินครึ่ง
		task.wait(0.25)
		if not alive() then break end
		pcall(noteFieldReset)

		-- ปะระบบกันโกงที่นี่ ไม่ใช่กลางการวาป
		-- ลูปนี้เดินทุก 0.25 วินาทีอยู่แล้ว หน่วงตรงนี้ไม่มีใครเดือดร้อน
		-- ต่างจากการหน่วงกลางการวาปซึ่งทำให้ตัวละครค้างคาที่
		pcall(warpReady)

		-- กล่องขาวขึ้นอยู่ไหม  ต้องรู้ก่อนตรวจไข่สลับชุด
		--
		-- ของเดิมค้นแบบไม่ลงลูกหลาน (pg:FindFirstChild) แต่ ResetStartTimer
		-- ซ้อนอยู่ข้างใน จึงได้ nil ตลอด ธงนี้แทบไม่เคยเป็นจริงเลยตอนกล่องขึ้น
		-- และของเดิมคำนวณทีหลังการตรวจไข่ ทำให้ใช้ค่าเก่าของรอบก่อนเสมอ
		pcall(function()
			local starter = findGui("ResetStartTimer")
			local soon = findGui("EndingSoon")
			Hub.BoxUp =
				(starter and starter:IsA("SurfaceGui") and starter.Enabled)
				or (soon and soon:IsA("GuiObject") and soon.Visible) or false
		end)

		-- ดูที่ตัวไข่จริง ไม่เชื่อ GUI
		--
		-- GUI หลอกได้: ตัวนับ 5 นาทีเด้งกลับช้ากว่าจังหวะที่ไข่ถูกสลับชุดจริง
		-- และธง ResetStartTimer ก็เปิดค้างบ้างไม่ขึ้นบ้าง เชื่อไม่ได้
		-- ของจริงที่โกหกไม่ได้คือรายชื่อไข่ในสนาม
		-- ถ้ามี Uid ที่ไม่เคยเห็นโผล่มาพร้อมกันตั้งแต่ 5 ใบขึ้นไป = สลับชุดแล้ว
		--
		-- เช็คเฉพาะตอนใกล้ครบรอบ (เหลือไม่เกิน 40 วิ) หรือไม่รู้เวลา
		-- นอกช่วงนั้นไม่ต้องถาม จะได้ไม่เปลืองการยิงเซิร์ฟ 231ms ฟรีๆ
		pcall(function()
			-- ต้องตรวจตอนกล่องขึ้นด้วย ไม่ใช่ดูแต่ตัวนับถอยหลัง
			--
			-- วัดจริง: กล่องขึ้นที่ 140.4 -> ไข่สลับชุดที่ 141.2 -> กล่องหายที่ 154.4
			-- ตอนไข่สลับชุด ตัวนับถอยหลังเด้งกลับไปเป็น ~290 วินาทีแล้ว
			-- เงื่อนไขเดิม (left > 40 ให้ข้าม) จึงข้ามการตรวจในจังหวะที่สำคัญที่สุด
			-- แถมล้างรายชื่อไข่ทิ้งด้วย ทำให้รอบถัดไปเทียบอะไรไม่ได้เลย
			-- ผลคือต้องไปรอตัวนับเด้ง = เสียหน้าต่างทองคำ 13 วินาทีทั้งช่วง
			local left = secondsToReset()
			if left ~= nil and left > 40 and not Hub.BoxUp then
				Hub.SeenUids = nil
				return
			end
			local now = {}
			local fresh = 0
			for _, r in pairs(snapshot()) do
				local u = tostring(r.Uid)
				if r.State == "Slot" and #u >= 24 then
					now[u] = true
					if Hub.SeenUids and not Hub.SeenUids[u] then fresh = fresh + 1 end
				end
			end
			if Hub.SeenUids and fresh >= 5 and not fieldIsFresh() then
				noteFieldResetNow()
				log(("ไข่สลับชุดแล้ว - เจอของใหม่ %d ใบ"):format(fresh))
			end
			Hub.SeenUids = now
		end)

		-- กล่องขาวขึ้นอยู่ไหม
		--
		-- isResetting() เดิมจะตอบ false ทันทีที่ยังมีไข่เก่าเหลือให้เก็บ
		-- ซึ่งถูกสำหรับการตัดสินใจว่า "ออกไปเก็บได้ไหม"
		-- แต่ใช้บอกไม่ได้ว่ากล่องขึ้นหรือยัง ซึ่งเป็นคนละเรื่องกัน
		-- ช่วงกล่องขึ้นคือช่วงที่เกมดีดเราออกจากสนาม ต้องตรึงตำแหน่งสู้

	end
end)

-- ช่วงเงียบก่อนไข่รีเซ็ต
--
-- 20 วินาทีสุดท้ายห้ามเริ่มงานอะไรที่ค้างยาว
-- เพราะงานที่เริ่มไปแล้วจะลากข้ามจังหวะรีเซ็ตไป แล้วไปเก็บไข่ไม่ทัน
-- ยืนรอที่เดิมเฉยๆ ดีกว่า ฟักไข่ขายสัตว์ทำตอนไหนก็ได้
Hub.quietNow = function()
	local q = tonumber(Config.PreResetQuiet) or 20
	if q <= 0 then return false end
	local left = secondsToReset()
	return left ~= nil and left <= q
end

local function waitOutReset()
	if not isResetting() then return true end
	log("ช่วงรีเซ็ต - รออยู่ที่ฐาน")
	-- ตรวจถี่ๆ ไม่งั้นรู้ช้าได้ถึง 1 วินาทีหลังรีเซ็ตจบ
	-- isResetting() อ่านจาก GUI ในเครื่อง ไม่ได้ยิงเซิร์ฟ เรียกถี่ได้ไม่เปลือง
	local t0 = os.clock()
	while isResetting() and os.clock() - t0 < 180 do
		if not Config.Running or not alive() then return false end
		Hub.Phase = "รอรีเซ็ต"
		task.wait(0.15)
	end

	-- หมดเวลา 180 วิ แต่ยังรีเซ็ตอยู่ = ห้ามออกเด็ดขาด
	-- ถ้าปล่อยผ่านตรงนี้จะเดินเข้าโซนที่ปิดอยู่แล้วโดนดีดกลางทาง
	if isResetting() then
		log("รอรีเซ็ตเกิน 180 วิ แต่ยังรีเซ็ตอยู่ - ไม่ออกจากฐาน")
		return false
	end

	log("รีเซ็ตจบ - ออกได้")

	-- รอเผื่อ 2 วิมีไว้ตอนต้องเดินออกไป จะได้ไม่ไปถึงตอนโซนยังไม่เปิดเต็มที่
	-- โหมดวาปไปกลับ 0.4 วิ ถ้าไปเร็วไปแล้วไข่ยังไม่มา ก็แค่วนรอบใหม่ ไม่เสียหาย
	task.wait(Config.MoveMode == "warp" and 0.2 or 2)
	return true
end

--==================================================================
-- ไข่ในสนาม
--==================================================================
-- แคชผลไว้สั้นๆ
--
-- วัดจริงบนเครื่องผู้ใช้: ยิงเซิร์ฟครั้งละ 231ms (ไม่ใช่ 90ms อย่างที่วัดบนอีกเครื่อง)
-- หนึ่งรอบเก็บไข่เรียก snapshot อย่างน้อยสองครั้ง (findEgg + isResetting)
-- = เสียฟรี 231ms ทุกรอบ ทั้งที่เป็นข้อมูลชุดเดียวกัน
--
-- 0.4 วินาทีสั้นพอที่จะไม่พลาดไข่ที่คนอื่นเพิ่งเก็บไป
-- (ถ้าพลาดจริง carry จะตอบ false แล้ววนไปเลือกใบใหม่อยู่แล้ว)
local snapCache, snapAt = nil, -math.huge

function snapshot()
	local now = os.clock()
	-- ช่วงกล่องขึ้นต้องรู้เร็วที่สุดว่าไข่ชุดใหม่โผล่แล้ว
	-- แคช 0.4 วิ แปลว่ารู้ช้าได้ถึง 0.4 วิ ซึ่งกินไปเกือบ 1 ใน 3 ของเวลาที่ใช้เก็บใบแรก
	-- นอกช่วงนั้นคงไว้ 0.4 เหมือนเดิม ไม่งั้นเปลืองการยิงเซิร์ฟ 231ms ฟรีๆ
	-- 0.1 แรงไป: การถามหนึ่งครั้งใช้ 231ms ตั้ง 0.1 = ถามซ้อนกันตลอด
	-- แย่งเวลาจากการเก็บจนเก็บได้ไม่ครบ  0.25 คือถามติดกันพอดีไม่ทับ
	local ttl = Hub.BoxUp and 0.25 or 0.4
	if snapCache and now - snapAt < ttl then return snapCache end

	local ok, res = pcall(function() return snapF:InvokeServer({}) end)
	if not ok or type(res) ~= "table" then return snapCache or {} end
	snapCache, snapAt = res.Records or {}, now
	return snapCache
end

-- เก็บได้ใบไหนก็เอาใบนั้นออกจากแคช ไม่ต้องล้างทั้งก้อน
--
-- ล้างทั้งก้อนแปลว่ารอบถัดไปต้องยิงเซิร์ฟใหม่ทันที (231ms)
-- ทั้งที่ข้อมูลอีก 44 ใบยังใช้ได้อยู่
clearSnapCacheFwd = function()
	snapCache, snapAt = nil, -math.huge
end

local function dropFromSnap(uid)
	if not snapCache then return end
	for k, r in pairs(snapCache) do
		if tostring(r.Uid) == tostring(uid) then snapCache[k] = nil return end
	end
end

-- ตีมูลค่าไข่เป็น $/s ด้วยสูตรของเกมเอง (สายพันธุ์ + ขนาด + mutation)
-- ไม่ได้เดาจากชื่อด่าน ไข่ตัวเดียวกันคนละขนาดค่าต่างกันเยอะ
local function eggRate(rec)
	local ok, rate = pcall(AGU.GetRateWithoutRebirth, {
		Category = rec.AssetCategory,
		Scale = rec.AssetScale,
		Mutations = rec.Mutations or {},
		HasBeenFirstPlaced = true,
	})
	return (ok and type(rate) == "number") and rate or 0
end

-- ไข่ที่ว่างอยู่ เรียงจาก $/s มากไปน้อย  (area == "ALL" = ทุกด่าน)
local function rankedEggs(area)
	local list = {}
	for _, r in pairs(snapshot()) do
		if r.State == "Slot" and (area == "ALL" or r.AreaId == area) then
			list[#list + 1] = { rec = r, rate = eggRate(r) }
		end
	end
	table.sort(list, function(a, b) return a.rate > b.rate end)
	return list
end

local function findEgg(area)
	local best = rankedEggs(area)[1]
	return best and best.rec, best and best.rate
end

local function carriedByMe()
	for _, r in pairs(snapshot()) do
		if tostring(r.CarrierUserId) == tostring(LocalPlayer.UserId) then return r end
	end
end

--==================================================================
-- แปลงของเรา
--
-- สแกนสดทุกครั้ง ห้าม hardcode เลขช่อง เพราะพอรีจอย/เข้าเซิร์ฟใหม่ ช่องเปลี่ยนได้
-- (เคยเจอมาแล้ว ช่อง 3 -> ช่อง 1 -> ช่อง 5 แล้วไปยืนแปลงคนอื่น)
--==================================================================
-- แคชไว้ 15 วิ
--
-- ทุก InvokeServer หยุดรอเซิร์ฟราว 60ms  ถ้ายิงถี่ๆ ระหว่างกำลังเคลื่อนที่
-- ลูปเขียน CFrame จะสะดุดเป็นช่วงๆ แอนตี้ชีตเห็นเป็นการกระโดดแล้วลากกลับ
-- (เคยเจอตอนเพิ่มระบบขายสัตว์ ยิงถี่ขึ้นแล้วโดนดึงกลับทันที)
-- ช่องแปลงไม่เปลี่ยนระหว่างเล่น เปลี่ยนตอนรีจอยเท่านั้น แคชได้สบาย
local plotCache, plotCacheAt = nil, 0

local function myPlot()
	if plotCache and os.clock() - plotCacheAt < 15 and plotCache[1].Parent then
		return plotCache[1], plotCache[2]
	end

	local ok, res = pcall(function() return plotsF:InvokeServer({}) end)
	if not ok or type(res) ~= "table" or not res.OwnersBySlot then return nil end
	for slot, userId in pairs(res.OwnersBySlot) do
		if tostring(userId) == tostring(LocalPlayer.UserId) then
			local plots = workspace:FindFirstChild("Plots")
			local model = plots and plots:FindFirstChild(tostring(slot))
			if model then
				plotCache, plotCacheAt = { model, tostring(slot) }, os.clock()
				return model, tostring(slot)
			end
		end
	end
end

local function homePos()
	local model = myPlot()
	if not model then return nil end
	-- SpawnPoint = จุดยืนนอกรั้ว (CenterPoint อยู่ในรั้ว จะไปติดแท่นวิ่ง)
	local sp = model:FindFirstChild("SpawnPoint")
	if sp then return sp.Position + Vector3.new(0, 2, 0) end
	return model:GetPivot().Position + Vector3.new(0, 3, 0)
end

-- เส้นทางเข้า/ออกแปลง
--
-- ห้ามวิ่งตัดทแยงจากในรั้วไปเลนกลางแมพเด็ดขาด จะชนรั้วแล้วตาย
-- แปลงแต่ละช่องอยู่คนละ Z (ช่อง 1 อยู่ z=-364 แต่ช่อง 5 อยู่ z=-482)
local function exitRoute()
	local model = myPlot()
	if not model then return {} end
	local sp = model:FindFirstChild("SpawnPoint")
	local base = sp and (sp.Position + Vector3.new(0, 2, 0))
		or (model:GetPivot().Position + Vector3.new(0, 3, 0))
	return {
		base,                                   -- ออกมานอกรั้วก่อน
		Vector3.new(IDLE_X, base.Y, base.Z),    -- วิ่งตามแกน X ระดับ Z เดิม
		Vector3.new(IDLE_X, LANE_Y, LANE_Z),    -- จบที่หน้า SAFE ZONE
	}
end

local function runRoute(points)
	-- exitRoute() คืน {} ตอนหาแปลงไม่เจอ
	-- ถ้าไม่ดักตรงนี้ ipairs จะไม่วนสักรอบแล้วตกไป return true
	-- = รายงานว่า "ออกจากแปลงสำเร็จ" ทั้งที่ไม่ได้ขยับเลย แล้ววิ่งทะลุรั้วต่อ
	if #points == 0 then return false end

	-- โหมดวาปข้ามไปจุดสุดท้ายเลย
	--
	-- จุดกลางทางมีไว้กันชนรั้วตอนเดิน ซึ่งวาปไม่ชน
	-- ระยะทั้งเส้นแค่ ~119 studs แต่เดินทีละก้าวกินหลายวินาทีต่อรอบ
	if Config.MoveMode == "warp" then
		local last = points[#points]
		if not move(last) then return false end
		landAt(last)
		return true
	end

	for i, p in ipairs(points) do
		if not Config.Running then return false end
		-- เดินติดพื้นเสมอ ระยะพวกนี้สั้นและมีรั้ว การขึ้นบินแล้วร่อนลงไม่คุ้ม
		if not moveGround(p) then return false end
		if i == #points then landAt(p) end
	end
	return true
end

local function reversed(points)
	local out = {}
	for i = #points, 1, -1 do out[#out + 1] = points[i] end
	return out
end

-- จุดกลางแปลงเรา  ใช้เป็นเป้าหมายตอนบินข้ามรั้วเข้าไป
local function baseCenter()
	local model = myPlot()
	if not model then return nil end
	local cp = model:FindFirstChild("CenterPoint")
	return (cp and cp.Position or model:GetPivot().Position) + Vector3.new(0, 3, 0)
end

-- ตอนนี้ยืนอยู่ในแปลงตัวเองไหม (วัดเฉพาะแนวราบ ไม่สนความสูง)
local function insideBase()
	local center = baseCenter()
	local _, hrp = char()
	if not center or not hrp then return false end
	local a = Vector3.new(center.X, 0, center.Z)
	local b = Vector3.new(hrp.Position.X, 0, hrp.Position.Z)
	return (a - b).Magnitude < 45
end

-- เข้าแปลง
--
-- โหมดบิน: ข้ามรั้วเข้าไปตรงๆ เลย
--   วัดจริงแล้ว บินข้าม 125 studs จากหน้า SAFE ZONE เข้ากลางแปลง
--   ตาย 0 ครั้ง เลือดเต็ม ไม่โดนดึงกลับตลอด 6 วิ ที่ค้างดู
--   เร็วกว่าเดินอ้อม (เลน -> หน้า SAFE ZONE -> เลี้ยวเข้าแปลง) มาก
--   และตัดอาการค้างที่ SAFE ZONE ทั้งที่ยังถือไข่อยู่ทิ้งไปเลย
--
-- โหมดอื่น: แวะพักหน้า SAFE ZONE ให้นิ่งก่อน แล้วค่อยเดินตามทางเข้าไป
--   วิ่งรวดเดียวจากในสนามเข้าแปลงจะสะดุด เพราะเพิ่งข้ามเส้นเปลี่ยนโซนมา
local function enterBase()

	local idleSpot = Vector3.new(IDLE_X, LANE_Y, LANE_Z)

	-- ขากลับเป็นระยะไกลสุดของทั้งรอบ (จากรังไข่ถึงเซฟโซนได้ถึง ~2,900 studs)
	-- วัดแล้วเดินกลับกินเวลากว่า 11 วินาที ทั้งที่วาปทีเดียวถึง
	--
	-- ไม่แก้ moveGround ทั้งตัว เพราะ enterGameplayZone ต้องใช้ก้าวเล็กๆ ข้ามเส้นจริง
	-- ธง "เข้าเขตแล้ว" อยู่ฝั่งเซิร์ฟเวอร์ วาปข้ามแล้วเซิร์ฟตอบ Enter the gameplay area first
	if Config.MoveMode == "warp" then
		move(idleSpot)
	else
		moveGround(idleSpot)   -- อยู่ในเซฟโซนแล้ว ไม่ต้องบิน
	end
	-- ยืนพักมีไว้ให้เซิร์ฟบันทึกตำแหน่งใหม่ทันก่อนออกวิ่งต่อ
	-- โหมดวาปไม่ต้องรอ เพราะไม่ได้กลัวโดนมองว่าเร็วผิดปกติแล้ว
	if Config.MoveMode ~= "warp" then
		Hub.Phase = "พักที่ SAFE ZONE ก่อนเข้าแปลง"
		settle(idleSpot, math.max(0, tonumber(Config.SafeZonePause) or 1.5))
	end

	Hub.Phase = "เข้าแปลงไปวางไข่"
	return runRoute(reversed(exitRoute()))
end

-- ออกจากแปลงไปยืนหน้า SAFE ZONE
-- เดินตามทางเข้า-ออกย้อนกลับ ติดพื้นตลอดเส้นทาง
local function leaveBase()
	return runRoute(exitRoute())
end

-- ออกมายืนรอหน้า SAFE ZONE
-- ห้ามค้างอยู่กลางแปลง เพราะตรงนั้นมีแท่นวิ่งกับรั้ว แล้วรอบหน้าต้องวิ่งออกมาใหม่ทุกที
local function goIdle()
	-- โหมดยืนจุดกลาง: กลับไปที่จุดกลางเซฟโซนเสมอ ไม่ใช่หน้า SAFE ZONE
	--
	-- ผู้ใช้สั่งไว้ตรงๆ: ให้ยืนจุดเดียวนิ่งๆ ไม่ต้องไปไหนเลย
	-- และวัดมาแล้วว่าการเข้า-ออกแปลงคือหนึ่งในสองอาการที่เด้งไม่จบ
	-- (512,-365 <-> 522,-483 สลับกัน 119 studs ซ้ำๆ) โดยเฉพาะแปลงที่อยู่ติดมุม
	local spot = Vector3.new(IDLE_X, LANE_Y, LANE_Z)
	if Config.StayCentre == true then
		spot = Vector3.new(Hub.HOME.X, Hub.HOME.Y, Hub.HOME.Z)
	end

	local _, hrp = char()
	if hrp and (hrp.Position - spot).Magnitude < 10 then
		settle(spot, 0.3)   -- อยู่ตรงนั้นแล้ว แค่กันไม่ให้ไถล
		return true
	end
	Hub.Phase = (Config.StayCentre == true) and "กลับไปยืนจุดกลาง" or "กลับไปยืนหน้า SAFE ZONE"

	-- เดินตามทางออกเฉพาะตอนอยู่ในแปลงจริงๆ
	--
	-- exitRoute() เริ่มที่จุดเกิดของแปลงเสมอ ถ้าเรียกทั้งที่ยืนอยู่กลางสนาม
	-- มันจะลากกลับเข้าแปลงก่อนแล้วค่อยเดินออกมาใหม่ = "วนกลับไปเช็คที่แปลง"
	--
	-- โหมดยืนจุดกลางห้ามใช้ leaveBase เด็ดขาด มันเดินตามทางของแปลงซึ่งพาวนกลับเข้าไป
	-- ติดอยู่ในแปลงก็วิ่งตรงออกมาเลย
	if insideBase() and Config.StayCentre ~= true then
		leaveBase()
	else
		move(spot)
	end
	landAt(spot)
	return true
end

local function waitForRespawn()
	local _, _, hum = char()
	if hum and hum.Health > 0 then return true end
	log("ตาย - รอเกิดใหม่")
	local t0 = os.clock()
	while os.clock() - t0 < 20 do
		if not Config.Running or not alive() then return false end
		local _, _, h = char()
		if h and h.Health > 0 then task.wait(1) return true end
		task.wait(0.5)
	end
	return false
end

--==================================================================
-- ไข่ของเรา / วาง / ฟัก
--==================================================================
local function ownedEggs()
	local ok, res = pcall(function() return eggSnapF:InvokeServer({}) end)
	if not ok or type(res) ~= "table" then return {} end
	for _, entry in pairs(res) do
		if tostring(entry.OwnerUserId) == tostring(LocalPlayer.UserId) then
			return entry.Records or {}
		end
	end
	return {}
end

-- ตำแหน่งอ้างอิงที่เกมใช้จริง (ถอดมาจากไข่ที่วางสำเร็จ)
local PLACE_ORIGIN = Vector3.new(0.3726, -0.5001, 2.0857)
local PLACE_ROT    = CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 0, -1), Vector3.new(0, 1, 0))

local lastPlaceIndex = 1   -- จุดที่วางสำเร็จล่าสุด เริ่มไล่จากตรงนี้รอบหน้า

local PLACE_OFFSETS = (function()
	local list = {}
	for ring = 0, 5 do
		for dx = -ring, ring do
			for dz = -ring, ring do
				if math.max(math.abs(dx), math.abs(dz)) == ring then
					list[#list + 1] = Vector3.new(dx * 4, 0, dz * 4)
				end
			end
		end
	end
	return list
end)()

-- ฝากไข่ที่ถืออยู่เข้ากระเป๋า
--
-- ถือได้ทีละใบ ("Already carrying an egg") ต้องฝากก่อนถึงจะเก็บใบต่อไป
-- วัดจริงว่าช่องถือจะว่างเมื่อไหร่:
--   ยืนรอเฉยๆ ไม่ไปไหน   3,207 ms
--   แวะแปลงตัวเองทันที      601 ms   <- เร็วกว่า 5 เท่า
-- แค่ "เข้าเขตแปลง" ก็ฝากแล้ว ไม่ต้องวางลงรัง วางทีเดียวตอนสะสมครบก็ได้
local function depositCarried(spot)
	-- กลับเซฟโซนก็ฝากได้ ไม่ต้องเข้าแปลง
	-- วัดเทียบแล้ว: แวะแปลง 601ms · แวะเซฟโซน 601ms · ยืนรอเฉยๆ 3,207ms
	-- เลือกเซฟโซนเพราะเร็วเท่ากันแต่ปลอดภัยกว่า ไม่ต้องเข้าไปลึกถึงแปลง
	local target = spot
	if not target then
		local model = myPlot()
		if not model then return false end
		local center = model:FindFirstChild("CenterPoint")
		target = (center and center.Position or model:GetPivot().Position) + Vector3.new(0, 3, 0)
	end

	if Config.MoveMode == "warp" then
		if not moveWarp(target) then return false end
	else
		moveGround(target)
	end

	-- ต้องยืนยันว่าไข่ออกจากมือจริง ไม่ใช่รอเวลาคงที่แล้วเดาเอา
	--
	-- ของเดิมรอ DepositWait (0.05-0.12 วิ) แล้วคืน true ทันที
	-- ตอนวิ่ง 153 studs/วินาที เซิร์ฟตามทันพอดี ใช้ได้
	-- แต่พอเร่งเป็น 600 เซิร์ฟยิ่งตามช้าลง (ตำแหน่งฝั่งมันวิ่งตามด้วยอัตราจำกัด)
	-- ไข่ยังอยู่ในมือแต่โค้ดคิดว่าฝากแล้ว รอบถัดไปเลยเจอ "Already carrying an egg"
	-- อาการที่เห็น: กลับเซฟโซนแล้วไม่ยอมฝากไข่ · เก็บใบต่อไปไม่ติด
	--
	-- ยืนอยู่ตรงนั้นรอจนของหายจากมือจริงๆ ตรวจจากรายการไข่ในสนาม
	-- ปกติใช้ไม่ถึง 0.3 วิ  ถ้าเกิน 1.5 วิถือว่าฝากไม่ได้ ให้รอบนอกจัดการ
	local base = math.max(0.03, tonumber(Config.DepositWait) or 0.12)
	task.wait(base)
	local deadline = os.clock() + math.max(1.5, base * 8)
	while os.clock() < deadline do
		clearSnapCacheFwd()
		if not carriedByMe() then return true end
		-- ยืนนิ่งรอ อย่าขยับออกจากเขต ไม่งั้นเซิร์ฟยิ่งไม่รับ
		--
		-- เคยใส่ตัวกันระยะตรงนี้ (ดึงเฉพาะตอนใกล้กว่า 25) แล้ววัดได้แย่ลง เก็บไข่ 0 ฟอง
		-- ถอดกลับมาแบบเดิมที่วัดได้ 16 ฟอง/ตาย 0
		local _, h = char()
		if h then
			h.CFrame = CFrame.new(target)
			h.AssemblyLinearVelocity = Vector3.zero
		end
		task.wait(0.08)
	end
	Hub.DepositSlow = (Hub.DepositSlow or 0) + 1
	return not carriedByMe()
end

-- ตัวตัดวงจรตอนวางไข่ไม่ลง
--
-- ถ้ารังเต็มหรือหาที่ว่างไม่เจอ โค้ดจะวนกลับมาลองใหม่ทุกรอบไม่มีที่สิ้นสุด
-- อาการที่เห็นคือวาปเข้าแปลงแล้วออก วนอยู่แบบนั้นไม่ไปเก็บไข่เลย
-- พลาดติดกันหลายครั้งแปลว่าลองอีกก็ไม่ได้ พักไปทำอย่างอื่นก่อนดีกว่า
--
-- เครื่องที่วางไข่ลงได้ตามปกติจะไม่แตะโค้ดส่วนนี้เลยสักบรรทัด
-- เพราะตัวนับถูกล้างทุกครั้งที่วางสำเร็จ
Hub.placeBlocked = function()
	return (Hub.StuckUntil or 0) > os.clock()
end

Hub.notePlaceResult = function(placedAny)
	if placedAny then
		Hub.PlaceFails, Hub.StuckUntil = 0, 0
		return
	end
	Hub.PlaceFails = (Hub.PlaceFails or 0) + 1
	if Hub.PlaceFails >= 3 then
		local rest = math.max(15, tonumber(Config.PlaceRetryRest) or 60)
		Hub.StuckUntil = os.clock() + rest
		Hub.PlaceFails = 0
		log(("วางไข่ไม่ลงติดกัน 3 รอบ - พัก %d วินาทีแล้วไปเก็บไข่ต่อ"):format(rest))
	end
end

local function placePendingEggs()
	-- ต้องเข้าแปลงก่อนแล้วค่อยอ่านรายการไข่
	--
	-- ไข่ที่เพิ่งขโมยมายัง "ถืออยู่" ไม่ได้อยู่ในกระเป๋า
	-- มันจะเข้ากระเป๋าตอนเราเข้าเขตแปลงตัวเองเท่านั้น
	-- ของเดิมอ่านรายการก่อนเข้าแปลง เลยได้ศูนย์ใบทุกครั้งแล้วไม่วางอะไร
	-- รอบถัดไปถึงเจอว่ามีไข่ค้าง = เข้าแปลงสองรอบต่อไข่หนึ่งใบ
	local model = myPlot()
	if not model then log("หาแปลงเราไม่เจอ") return 0 end
	local center = model:FindFirstChild("CenterPoint")
	local standAt = (center and center.Position or model:GetPivot().Position) + Vector3.new(0, 3, 0)

	-- เข้าไปกลางแปลง
	--
	-- เดิมบังคับเดินติดพื้น เพราะโหมดบินจะยกตัวตั้งแต่ในเซฟโซนเมื่อช่องแปลงไกลเกิน 110 studs
	-- (เช่น slot 7 อยู่ z-483 ห่าง 119) แล้วลอยข้ามเส้นแดงออกไปโดนลากกลับ
	-- โหมดวาปไม่มีปัญหานั้น ไปถึงในเฟรมเดียวไม่ได้ลอยผ่านอะไร
	-- ต้องเข้าแปลงเสมอ ไม่มีทางเลี่ยง
	--
	-- เคยลองให้ StayCentre ข้ามการเข้าแปลงแล้ววางจากจุดกลางเลย  วัดจริงแล้วไม่ได้:
	--     place_ok      = 0        วางสำเร็จศูนย์ฟอง
	--     place_too_far = 1,932    เซิร์ฟตอบ "Get closer to your area" ทุกครั้ง
	--     eggs_stolen   = 266      ขโมยมาแล้ววางไม่ได้ คอกตัน รายได้หยุด
	-- แย่กว่าไม่ทำอะไรเลย เพราะยิงเซิร์ฟเปล่าเกือบสองพันครั้งด้วย
	--
	-- StayCentre จึงหมายถึง "ไม่ไปยืนเล่นในแปลง" ไม่ใช่ "ไม่เข้าแปลงเลย"
	-- เข้าเฉพาะตอนมีไข่ต้องวางจริงๆ วางเสร็จออกทันที (goIdle พากลับจุดกลาง)
	--
	-- เดิมบังคับเดินติดพื้น เพราะโหมดบินจะยกตัวตั้งแต่ในเซฟโซนเมื่อช่องแปลงไกลเกิน 110 studs
	-- (เช่น slot 7 อยู่ z-483 ห่าง 119) แล้วลอยข้ามเส้นแดงออกไปโดนลากกลับ
	-- โหมดวาปไม่มีปัญหานั้น ไปถึงในเฟรมเดียวไม่ได้ลอยผ่านอะไร
	Hub.Phase = "เข้าแปลงไปวางไข่"
	if Config.MoveMode == "warp" then
		move(standAt)
	else
		moveGround(standAt)
	end
	landAt(standAt)   -- กลางแปลงมีแท่นวิ่ง ต้องตรึงไว้ไม่ให้โดนพาไป
	task.wait(0.4)   -- ให้เซิร์ฟรับไข่ที่ถือมาเข้ากระเป๋าก่อน

	-- อ่านรายการหลังเข้าแปลงแล้ว ตอนนี้ไข่ที่เพิ่งถือมาจะอยู่ในนี้ด้วย
	--
	-- เรียงจากแพงไปถูกก่อนวาง  ช่องในรังมีจำกัด
	-- ถ้าวางตามลำดับที่เจอ ใบถูกอาจกินช่องไปก่อนแล้วใบแพงไม่เหลือที่
	--
	-- ต้องอ่านซ้ำเป็นรอบๆ ห้ามอ่านทีเดียวจบ
	--
	-- ของเดิมรอ 0.4 วินาทีแล้วอ่านรายการครั้งเดียว
	-- ไข่ที่เซิร์ฟรับเข้ากระเป๋าช้ากว่านั้นจะไม่อยู่ในรายการเลย = ไม่ถูกวาง
	-- ผู้ใช้เจอตรงๆ: "เข้าไปวางจริง แต่วางไม่ครบ"
	-- อ่านใหม่ทุกรอบจนกว่าจะไม่มีไข่เหลือ หรือวางเพิ่มไม่ได้แล้ว
	local placedTotal = 0
	for round = 1, 5 do
	local pending = {}
	for uid, rec in pairs(ownedEggs()) do
		if rec.Placement == nil then
			pending[#pending + 1] = { uid = uid, rate = eggRate(rec) }
		end
	end
	if #pending == 0 then break end
	table.sort(pending, function(a, b) return a.rate > b.rate end)

	-- อ่านช่องที่ถูกใช้ไปแล้วจากเซฟ แล้วข้ามไปเลย
	--
	-- ไข่ที่วางแล้วเก็บพิกัดไว้ใน Placement.LocalCFrame เป็นอาเรย์ 12 ตัว
	-- ตัวที่ 1 กับ 3 คือ X,Z  ช่องเรียงห่างกัน 4 studs พอดี
	-- ของเดิมไม่รู้ว่าช่องไหนเต็ม เลยยิงถามเซิร์ฟทีละจุดจนกว่าจะเจอที่ว่าง
	-- วัดจริง: ไข่ใบเดียวกินไป 1.4-3.2 วินาที (ยิงเซิร์ฟหลายสิบครั้ง ครั้งละ 93ms)
	local taken = {}
	for _, rec in pairs(ownedEggs()) do
		local pl = rec.Placement
		if type(pl) == "table" and type(pl.LocalCFrame) == "table" then
			local lc = pl.LocalCFrame
			local x, z = lc[1], lc[3]
			if type(x) == "number" and type(z) == "number" then
				taken[("%d:%d"):format(math.floor(x / 4 + 0.5), math.floor(z / 4 + 0.5))] = true
			end
		end
	end

	-- เริ่มไล่จากจุดที่วางสำเร็จล่าสุด
	--
	-- รังเติมทีละช่องเรียงกันไป จุดที่ว่างรอบหน้าจึงอยู่ติดกับจุดที่เพิ่งวางได้
	-- ของเดิมเริ่มจากจุดที่ 1 ทุกครั้ง = ไล่ชนไข่เก่าซ้ำๆ ก่อนถึงที่ว่าง
	-- วัดจริง: วางครั้งเดียวกินไป 3.17 วินาที (ยิงเซิร์ฟ ~35 ครั้ง ครั้งละ 93ms)
	local placed = 0
	for _, item in ipairs(pending) do
		local uid = item.uid
		local far = 0
		local order = {}
		for i = 1, #PLACE_OFFSETS do
			order[i] = PLACE_OFFSETS[((lastPlaceIndex + i - 2) % #PLACE_OFFSETS) + 1]
		end
		for oi, off in ipairs(order) do
			if not Config.Running or not alive() then
				placedTotal = placedTotal + placed
				Hub.PlaceOK = (Hub.PlaceOK or 0) + placedTotal
				return placedTotal
			end

			-- ข้ามช่องที่รู้อยู่แล้วว่ามีไข่อยู่ ไม่ต้องเสียเวลาถามเซิร์ฟ
			local px, pz = PLACE_ORIGIN.X + off.X, PLACE_ORIGIN.Z + off.Z
			local key = ("%d:%d"):format(math.floor(px / 4 + 0.5), math.floor(pz / 4 + 0.5))
			if taken[key] then continue end

			local cf = CFrame.new(PLACE_ORIGIN + off) * PLACE_ROT
			local ok, msg = placeF:InvokeServer({ Uid = uid, LocalCFrame = cf })
			if ok == true then
				placed += 1
				taken[key] = true   -- จำไว้ ใบถัดไปจะได้ไม่มาชนช่องนี้
				lastPlaceIndex = ((lastPlaceIndex + oi - 2) % #PLACE_OFFSETS) + 1
				break
			end
			if tostring(msg):find("too close") then taken[key] = true end

			-- แยกสาเหตุที่วางไม่ได้ให้ออก
			--
			-- "too close to another egg" = จุดนี้ไม่ว่าง ลองจุดถัดไปมีประโยชน์
			-- "Get closer to your area" = ยืนไกลจากแปลง ลองอีกร้อยจุดก็ตอบเหมือนเดิม
			-- เคยเสียเวลา 2.8 วิต่อรอบเพราะไล่ครบ 121 จุดทั้งที่ผิดที่ยืน
			-- เจอแบบหลังให้วาปเข้าไปใหม่ ถ้ายังไม่หายก็เลิก อย่าไล่ต่อ
			-- รังเต็มเพดานแล้ว ลองอีกกี่จุดกี่ใบก็ตอบเหมือนเดิม
			-- วัดจริง: เพดาน 30 ใบ พอเต็มแล้วมีไข่ค้าง 14 ใบ
			-- ของเดิมไล่ 121 จุด x 14 ใบ = ค้างเกิน 12 วินาทีทุกรอบ
			if tostring(msg):find("too many eggs") then
				log("รังเต็มเพดานแล้ว - รอไข่ฟักก่อน")
				placedTotal = placedTotal + placed
				if placedTotal > 0 then log(("วางไข่ลงแปลง %d ฟอง"):format(placedTotal)) end
				Hub.PlaceOK = (Hub.PlaceOK or 0) + placedTotal
				return placedTotal
			end

			if tostring(msg):find("Get closer") then
				far = far + 1
				Hub.PlaceTooFar = (Hub.PlaceTooFar or 0) + 1   -- เปิดตัวเลขให้วัดได้จากข้างนอก
				if far >= 3 then break end
				if Config.MoveMode == "warp" then move(standAt) else moveGround(standAt) end
				task.wait(0.15)
			end
			-- ไม่หน่วงเพิ่มระหว่างจุด การยิงเซิร์ฟเองใช้ ~93ms อยู่แล้ว
			-- ของเดิมบวก 0.05 ทุกจุด = เพิ่มเวลาไปอีกครึ่งเท่าโดยไม่ได้อะไร
		end
	end
	-- จบรอบนี้แล้ว  วางไม่ได้เพิ่มเลยก็เลิก ไม่ต้องวนต่อ
	placedTotal = placedTotal + placed
	if placed == 0 then break end
	task.wait(0.35)   -- ให้เซิร์ฟตามส่งไข่ที่เหลือเข้ากระเป๋าก่อนอ่านรอบหน้า
	end

	if placedTotal > 0 then log(("วางไข่ลงแปลง %d ฟอง"):format(placedTotal)) end
	Hub.PlaceOK = (Hub.PlaceOK or 0) + placedTotal
	return placedTotal
end

-- เปิดให้สั่งเคลียร์ไข่ค้างได้จากข้างนอก (แก้ตอนกระเป๋าเต็มโดยไม่ต้องรอลูป)
Hub.placeNow = function()
	local ok, n = pcall(placePendingEggs)
	return ok and n or 0
end

-- ฟักไข่ที่พร้อม
-- ไข่ที่ยังไม่ครบเวลาจะตอบ "Egg is not ready" เฉยๆ ไม่พัง ยิงรัวได้ไม่ต้องเช็คเวลาเอง
-- ประกาศล่วงหน้า ตัวจริงอยู่ข้างล่างพร้อมกับ myPets()
-- ต้องมีตรงนี้เพราะการฟักทำให้มีสัตว์ตัวใหม่ ต้องล้างแคชทันที
local clearPetsCache

-- limit = ฟักได้มากสุดกี่ฟองในครั้งนี้ (nil = ไม่จำกัด)
--
-- ไข่ที่ฟักได้แล้วแต่ยังไม่ฟัก = กินช่องรังไปเปล่าๆ (เพดาน 30 ใบ)
-- ยิ่งค้างยิ่งวางไข่ใหม่ไม่ได้ จึงต้องฟักทุกรอบ ไม่ใช่รอทำงานบ้านทุก 5 รอบ
-- แต่ฟักฟองละ 2 คำสั่ง (~0.5 วิ) ถ้าฟักรวดเดียวหมดจะบล็อกยาว เลยจำกัดต่อรอบ
-- force = true คือ "ต้องฟักให้ได้" ห้ามทิ้งงานกลางคันเพราะสนามมีไข่
local function hatchReadyEggs(limit, force)
	if not Config.AutoHatch then return 0 end

	local hatched = 0
	for uid, rec in pairs(ownedEggs()) do
		-- ไข่รีเซ็ตแล้วต้องทิ้งงานบ้านทันที
		-- วัดจริง: รอบที่ติดฟักไข่ 8 ฟองอยู่ กว่าจะเก็บใบแรกได้คือวินาทีที่ 13.1
		-- รอบที่ว่างอยู่ เก็บใบแรกได้ที่วินาทีที่ 1.8  ต่างกัน 11 วินาที = ของดีโดนชิงหมด
		-- งานบ้านทำตอนไหนก็ได้ ไข่ดีมีให้แย่งแค่ไม่กี่วินาที
		--
		-- แต่ห้ามใช้กฎนี้ตอนรังเต็ม
		--
		-- fieldIsFresh() เป็นจริงเกือบตลอดเวลาระหว่างฟาร์ม
		-- ผลคือลูปนี้ break ตั้งแต่ใบแรกแทบทุกครั้ง = ไข่ไม่เคยได้ฟักเลย
		-- รังเลยตันที่ 30/30 แล้ววางไข่ใหม่ไม่ได้อีก (ผู้ใช้เจอ "Egg inventory full!!")
		-- เป็นวงจรกัดตัวเองแบบเดียวกับที่เจอในตัววางไข่
		if not Config.Running or not alive() then break end
		if not force and (fieldIsFresh() or Hub.quietNow()) then break end
		if limit and hatched >= limit then break end
		if rec.Placement ~= nil then
			local ok = hatchF:InvokeServer(uid)
			if ok == true then
				task.wait(0.4)
				if hatchEndF:InvokeServer(uid) == true then hatched += 1 end
			end
			task.wait(0.05)
		end
	end
	-- ไปลองแล้วได้/ไม่ได้ ใช้ปรับความถี่ของการแวะรอบหน้า
	if hatched > 0 then
		Hub.hatchBackoff = 1
	else
		Hub.hatchBackoff = math.min(10, (Hub.hatchBackoff or 1) * 2)
	end

	if hatched > 0 then
		Stats.hatched += hatched
		-- ฟักแล้วได้สัตว์ตัวใหม่ ต้องล้างแคชทันที
		-- ไม่งั้น autoSellWeak() ที่ทำต่อจะไม่เห็นตัวใหม่ แล้วตัดสินใจจากรายการเก่า
		log(("ฟักไข่ %d ฟอง"):format(hatched))
	end
	if hatched > 0 and clearPetsCache then clearPetsCache() end
	return hatched
end

-- เปิดให้สั่งฟักเองจากข้างนอก  ใช้ตอนรังตันแล้วอยากเคลียร์ทันที
Hub.hatchNow = function()
	local ok, n = pcall(hatchReadyEggs, nil, true)
	return ok and n or 0
end

--==================================================================
-- สัตว์ในคอก
--==================================================================
-- ช่องคอกเปลี่ยนเฉพาะตอนอัปฐาน ไม่ต้องถามเซิร์ฟทุกครั้ง
--
-- InvokeServer ตัวนี้วัดได้ว่าหยุดรอ 62 มิลลิวินาทีต่อครั้ง
-- ตอนเพิ่มระบบขาย มีจุดเรียกเพิ่มขึ้นหลายที่ (แผงสัตว์ + sellCandidates + worthGoing)
-- ยิ่งเรียกถี่ยิ่งหยุดรอบ่อย ระหว่างนั้นการชนเปิดอยู่ ตัวละครโดนดันออกจากตำแหน่ง
-- เซิร์ฟเห็นเป็นการขยับที่ไม่ได้สั่ง แล้วลากกลับ
local capCache, capAt = 12, -math.huge

local function equipCap(force)
	if not force and (os.clock() - capAt) < 30 then return capCache end
	local ok, c = pcall(function() return capF:InvokeServer() end)
	if ok and type(c) == "number" and c > 0 then
		capCache, capAt = c, os.clock()
	end
	return capCache
end

-- สัตว์ทั้งหมดที่เรามี เรียง $/s มากไปน้อย
--
-- ต้องอ่านจาก Save.Inventory ไม่ใช่ ActiveAssets
-- ActiveAssets คืนมาแค่ตัวที่อยู่ในคอกจริง (13 ตัว) ส่วนในกระเป๋ามีอีก 37 ตัวที่มองไม่เห็น
-- นั่นคือเหตุผลที่ระบบขายไม่เคยทำงาน มันเทียบ 13 กับช่อง 13 แล้วสรุปว่าไม่มีตัวล้น
--
-- Save.EquippedAssets = map ช่อง -> uid  ใช้ระบุว่าตัวไหนอยู่ในคอก (ห้ามขาย)
-- ค่า $/s คำนวณเองด้วยสูตรของเกม ตรวจแล้วตรงกับ MoneyPerSecond ของเซิร์ฟทุกตัว
-- (Bronto server=1,208,810 / calc=1,208,810)
-- แคชสั้นๆ 3 วิ
-- worthGoing() เรียกตัวนี้ทุกรอบของลูปเก็บไข่ ซึ่งอยู่คั่นกลางระหว่างการเคลื่อนที่
-- ไล่อ่านกระเป๋า 50 ตัวพร้อมคำนวณ $/s ทุกครั้งคือการหยุดค้างระหว่างเดินทาง
local petsCache, petsAt = nil, -math.huge

local function myPets()
	if petsCache and (os.clock() - petsAt) < 3 then return petsCache end

	local data = Save.Get(LocalPlayer, false)
	if not data or type(data.Inventory) ~= "table" then return {} end

	local equipped = {}
	for _, uid in pairs(data.EquippedAssets or {}) do
		equipped[tostring(uid)] = true
	end

	local list = {}
	for uid, item in pairs(data.Inventory) do
		if type(item) == "table" then
			local ok, rate = pcall(AGU.GetRateWithoutRebirth, {
				Category = item.Category,
				Scale = item.Scale,
				Mutations = item.Mutations or {},
				HasBeenFirstPlaced = true,
			})
			list[#list + 1] = {
				uid = tostring(uid),
				cat = item.Category or "?",
				mps = (ok and type(rate) == "number") and rate or 0,
				equipped = equipped[tostring(uid)] == true,
			}
		end
	end
	table.sort(list, function(a, b) return a.mps > b.mps end)
	petsCache, petsAt = list, os.clock()
	return list
end

-- ขาย/ฟักแล้วของเปลี่ยน ต้องล้างแคชไม่งั้นอ่านค่าเก่า
function clearPetsCache()
	petsCache, petsAt = nil, -math.huge
end

-- ใช้ปุ่ม Equip Best ของเกมเป็นหลัก มันคัดตัว $/s สูงสุดให้เอง
-- ถ้าเรียกไม่ผ่านค่อยตกมาที่การไล่ equip ทีละตัว (ได้ตามลำดับดิบ ไม่คัดของดี)
local function placePets()
	if not Config.AutoHatch then return 0 end

	if equipBestF then
		local ok, res = pcall(function() return equipBestF:InvokeServer() end)
		if ok and res == true then
			-- ต้องล้างแคชทุกครั้งที่คอกเปลี่ยน
			--
			-- myPets() แคชไว้ 3 วินาที ถ้าไม่ล้าง autoSellWeak() ที่ทำต่อทันที
			-- จะอ่านรายการเก่าที่ยังไม่รู้ว่า Equip Best เพิ่งใส่ตัวไหนเข้าคอก
			-- ตัวที่เพิ่งใส่จะยังมี equipped = false = ถูกนับเป็นตัวล้น = โดนขายทิ้ง
			-- (เจอจากที่ผู้ใช้สังเกตว่ามันขายตัวที่แพงกว่าตัวในคอก)
			clearPetsCache()
			return 1
		end
	end

	local n = 0
	for _, p in ipairs(myPets()) do
		-- ไข่รีเซ็ตแล้วต้องทิ้งงานบ้านทันที
		-- วัดจริง: รอบที่ติดฟักไข่ 8 ฟองอยู่ กว่าจะเก็บใบแรกได้คือวินาทีที่ 13.1
		-- รอบที่ว่างอยู่ เก็บใบแรกได้ที่วินาทีที่ 1.8  ต่างกัน 11 วินาที = ของดีโดนชิงหมด
		-- งานบ้านทำตอนไหนก็ได้ ไข่ดีมีให้แย่งแค่ไม่กี่วินาที
		if not Config.Running or not alive() or fieldIsFresh() or Hub.quietNow() then break end
		if petEquipF:InvokeServer(p.uid) == true then n += 1 end
		task.wait(0.1)
	end
	if n > 0 then
		clearPetsCache()   -- คอกเปลี่ยนแล้ว ห้ามให้ตัวขายอ่านของเก่า
		log(("ปล่อยสัตว์ลงคอก %d ตัว"):format(n))
	end
	return n
end

-- ตัวที่เข้าข่ายขาย  ต้องทำ "หลัง" Equip Best เสมอ
--   1) ตัวที่อยู่ในคอกจริง ไม่แตะเด็ดขาด (เช็คจาก EquippedAssets ไม่ใช่เดาจากอันดับ)
--   2) เก็บอันดับต้นไว้ = ช่องคอก + KeepExtra
--   3) ถ้าตั้ง KeepAbove ไว้ ตัวที่ $/s ถึงเกณฑ์จะเก็บไว้ ถึงจะล้นอันดับก็ตาม
local function sellCandidates()
	local pets = myPets()
	local cap = equipCap()
	local keep = cap + math.max(0, math.floor(Config.KeepExtra))
	local floor = math.max(0, tonumber(Config.KeepAbove) or 0)

	local out = {}
	for i, p in ipairs(pets) do
		local overflow = i > keep
		local rich = floor > 0 and p.mps >= floor
		if not p.equipped and overflow and not rich then
			out[#out + 1] = p
		end
	end

	-- ส่งกลับโดยเรียง "กากสุดมาก่อน"
	--
	-- pets เรียงจากแพงไปถูก out จึงเรียงตามนั้นไปด้วย
	-- แต่ autoSellWeak มี limit ต่อรอบ (ขายทีละน้อยไม่ให้บล็อกยาว)
	-- ของเดิมจึงขายตัวที่ดีที่สุดในกลุ่มที่ขายได้ก่อน แล้วเหลือตัวกากไว้
	-- ซึ่งกลับหัวกับที่ควรเป็น  กลับลำดับให้ขายจากตัวรายได้ต่ำสุดขึ้นมา
	local rev = {}
	for i = #out, 1, -1 do rev[#rev + 1] = out[i] end
	return rev, #pets, keep
end

-- limit = ขายได้มากสุดกี่ตัวในครั้งนี้ (nil = ไม่จำกัด)
--
-- แยกให้ขายทีละน้อยทุกรอบได้ แทนที่จะไปกองรวมในงานบ้านซึ่งบล็อกยาว 10 วินาที
-- ตัวที่ขายช้าไปหนึ่งรอบไม่เสียหาย แต่พลาดจังหวะไข่รีเซ็ตคือเสียทั้งรอบ
local function autoSellWeak(force, limit)
	if not sellF then return 0 end
	if not force and not Config.AutoSell then return 0 end

	local list, total, keep = sellCandidates()
	if #list == 0 then return 0 end

	local sold = 0
	for _, p in ipairs(list) do
		if limit and sold >= limit then break end
		-- ขายแล้วเอาคืนไม่ได้ กดหยุดเมื่อไหร่ต้องหยุดทันที ห้ามขายต่อให้จบลูป
		if not force and (not Config.Running or not alive()) then break end
		if sellF:InvokeServer(p.uid) == true then
			sold += 1
		end
		task.wait(0.15)
	end
	if sold > 0 then
		Stats.sold += sold
		clearPetsCache()
		log(("ขาย %d ตัว (มีทั้งหมด %d · เก็บอันดับต้น %d)"):format(sold, total, keep))
	end
	return sold
end

-- คุ้มไหมที่จะออกไปเก็บ
-- คอกยังไม่เต็ม = เก็บอะไรมาก็ได้กำไร
-- คอกเต็มแล้ว = ไข่ต้องแรงกว่าตัวที่อ่อนสุดในคอก ไม่งั้นเก็บมาก็โดนขายทิ้งอยู่ดี
local function worthGoing(rate)
	if not Config.SkipWeak then return true, 0 end

	local cap = equipCap()
	local pets = myPets()

	-- เกณฑ์ขั้นต่ำ ใช้ได้แม้คอกยังไม่เต็ม
	--
	-- ของเดิม: คอกยังว่าง = ผ่านทุกใบ เพราะช่องว่างได้ $0 เก็บอะไรมาก็ดีกว่า
	-- ปัญหาคือบัญชีที่โตแล้วจะวิ่งไล่เก็บไข่ $8/s ทิ้งเวลาไปเปล่าๆ
	-- (เจอจริง: บัญชีเงิน $388M ฐาน Lv3 ยังออกไปเก็บ Chicken $8/s)
	--
	-- MinEggRate = 0 แปลว่าคิดให้เอง = 1% ของตัวที่ดีที่สุดที่มี
	-- บัญชีใหม่ที่ยังไม่มีสัตว์เลย เกณฑ์เป็น 0 = เก็บได้ทุกใบตามเดิม
	-- เกณฑ์ขั้นต่ำแบบตั้งเอง  0 = ไม่ใช้เลย (ค่าเริ่มต้น)
	--
	-- เคยลองคิดให้อัตโนมัติจากตัวที่ดีที่สุด (1% แล้วลดเป็น 0.1%)
	-- แต่บัญชีที่มีตัวแพงมากจะได้เกณฑ์สูงจนไม่เก็บอะไรเลย = ยืนเฉยทั้งวัน
	-- คืนกลับเป็นตรรกะเดิมที่เร็วกว่า ใครอยากกรองไข่ขยะค่อยตั้งตัวเลขเอง
	local floor = math.max(0, tonumber(Config.MinEggRate) or 0)
	if floor > 0 and rate < floor then return false, math.floor(floor) end

	-- คอกยังมีช่องว่าง
	--
	-- ของเดิม: ช่องว่างทำเงินได้ $0 เก็บอะไรมาก็ดีกว่า จึงผ่านทุกใบ
	-- ปัญหาที่เจอจริง: คอก 9 ช่อง มีสัตว์ 4 ตัว แต่สนามมีแค่ Dog $2/s Chicken $1/s
	-- มันวิ่งไล่เก็บของกากทั้งที่ในคอกมีดีกว่าอยู่แล้ว เสียเวลาทั้งรอบ
	--
	-- เทียบกับตัวอ่อนสุดที่มีเสมอ ไม่ว่าคอกจะว่างหรือไม่
	-- แลกกับการที่ช่องว่างจะว่างนานขึ้น แต่ไม่ต้องวิ่งไล่ของไร้ค่า
	-- ตั้ง SkipWorseThanPen = false ถ้าอยากได้แบบเดิม (บัญชีใหม่ล้วนๆ อาจเหมาะกว่า)
	if #pets < cap then
		if Config.SkipWorseThanPen == false then return true, math.floor(floor) end
		local best = pets[1]
		if not best then return true, math.floor(floor) end   -- ยังไม่มีสัตว์เลย เก็บได้ทุกใบ

		-- คอกยังว่าง: ช่องว่างทำเงินได้ $0 เก็บอะไรมาก็ได้เพิ่มทั้งนั้น
		--
		-- ห้ามเทียบกับตัวอ่อนสุดที่มี เพราะไข่ไม่ได้ไปแทนที่ใคร มันลงช่องว่าง
		-- (เจอจริง: คอก 12 ช่อง มีสัตว์ตัวเดียว $4.1M/s ไข่ในสนาม $1.1M/s
		--  ถูกตัดทิ้งทั้งที่เก็บมาแล้วได้เพิ่มฟรีๆ อีก 11 ช่อง)
		--
		-- แต่ก็ไม่ควรไล่เก็บของไร้ค่า (เคยเจอไล่เก็บ Dog $2/s)
		-- ใช้เกณฑ์ 1% ของตัวที่ดีที่สุดที่มี — ตัดขยะออกแต่ไม่ตัดของที่คุ้ม
		local pct = math.max(0, tonumber(Config.EmptySlotPct) or 1) / 100
		local minRate = best.mps * pct
		return rate >= minRate, math.floor(minRate)
	end

	local weakest = pets[cap]
	if not weakest then return true, math.floor(floor) end
	return rate > weakest.mps, weakest.mps
end

--==================================================================
-- อัปเกรดฐาน (ใช้เงินในเกม ไม่ใช่ Robux)
-- ราคาต่อเลเวล: 0/1k/1M/75M/500M/1B/50B/500B/1T/25T/100T/500T  สูงสุดเลเวล 11
-- เพดานสัตว์ไล่จาก 7 -> 18 ตัว
--==================================================================
local function baseInfo()
	local data = Save.Get(LocalPlayer, false)
	if not data then return nil end
	local lvl = data.BaseUpgradeLevel or 0
	local cfg = Bases.BASES[lvl]
	return lvl, cfg and cfg.MaxAssets or "?", data.Money or 0
end

local function autoUpgradeBase()
	if not Config.AutoUpgrade or not upgradeE then return 0 end

	local done = 0
	for _ = 1, 12 do
		if not Config.Running or not alive() then return done end
		local data = Save.Get(LocalPlayer, false)
		if not data then return done end

		local nextLvl = (data.BaseUpgradeLevel or 0) + 1
		local cfg = Bases.BASES[nextLvl]
		if not cfg then return done end                   -- เต็มเลเวลแล้ว
		if data.Money < cfg.Cost then return done end     -- เงินไม่พอ

		upgradeE:FireServer()
		task.wait(3)

		local after = Save.Get(LocalPlayer, false)
		if not after or after.BaseUpgradeLevel ~= nextLvl then return done end
		done += 1
		Stats.upgrades += 1
		log(("อัปฐานเป็นเลเวล %d (วางสัตว์ได้ %d)"):format(nextLvl, cfg.MaxAssets))
	end
	return done
end

local function tendBase()
	-- สนามรีเซ็ต = ทิ้งงานบ้านทันที ออกไปเก็บไข่ก่อน
	--
	-- งานบ้านเต็มชุดกิน ~10 วินาที ถ้าเริ่มไปแล้วรีเซ็ตมาพอดี
	-- กว่าจะเสร็จของดีโดนคนอื่นเก็บหมด (เจอจริง: เก็บใบแรกช้าไป 7 วินาที)
	-- งานบ้านรอได้ ไข่รอไม่ได้
	local function stopped()
		return not Config.Running or not alive() or fieldIsFresh() or Hub.quietNow()
	end

	-- งานส่วนใหญ่ยิงจากตรงไหนก็ได้ ไม่ต้องเข้าแปลง
	--
	-- วัดสดจากกลางสนาม (x876 z-397 ห่างแปลงเป็นร้อย studs):
	--   ActiveAssets: RequestSell    -> true    ยิงได้
	--   Backpack: EquipBest          -> true    ยิงได้
	--   Eggs: RequestHatchEgg        -> true    ยิงได้
	--   Plots: RequestBaseUpgrade    -> ยิงได้  (RemoteEvent ไม่มีคำตอบ)
	--   Eggs: RequestPlaceEgg        -> false / "Get closer to your area to place an egg!"
	--
	-- มีแค่ "วางไข่" ตัวเดียวที่ต้องอยู่ใกล้แปลงจริงๆ
	--
	-- ของเดิมเข้าแปลงทุกครั้งที่ทำงานบ้าน ทั้งที่ 4 ใน 5 อย่างไม่ต้องเข้าเลย
	-- และกลางแปลงมีแท่นวิ่ง วาปลงไปแล้วโดนพาไถล ออกไม่ได้ ต้องกดกระโดดเอง
	-- (ผู้ใช้เจอตรงๆ: วาปมาโดนแท่นวิ่งแล้วออกไม่ได้ ต้องกด space bar)
	--
	-- ทำจากที่ยืนอยู่ให้หมดก่อน แล้วค่อยเข้าแปลงเฉพาะตอนมีไข่ต้องวางจริงๆ
	hatchReadyEggs()
	if stopped() then return end
	autoUpgradeBase()
	if stopped() then return end
	placePets()     -- ทำหลังอัปฐาน จะได้ใช้ช่องที่เพิ่งเพิ่มมา
	if stopped() then return end
	autoSellWeak()
	if stopped() then return end

	-- เข้าแปลงเฉพาะตอนมีไข่รอวางจริงๆ  ไม่มีก็ไม่ต้องไป
	local waiting = 0
	for _, rec in pairs(ownedEggs()) do
		if rec.Placement == nil then waiting = waiting + 1 end
	end
	if waiting > 0 then
		placePendingEggs()
		-- ออกจากแปลงทันทีที่วางเสร็จ อย่าค้างบนแท่นวิ่ง
		if Hub.HOME then
			move(Vector3.new(Hub.HOME.X, Hub.HOME.Y, Hub.HOME.Z))
		end
	end
end

--==================================================================
-- รอบฟาร์ม 1 รอบ
--==================================================================

--==================================================================
-- วงจรวาป
--
-- ทั้งรอบมีแค่สี่จังหวะ: ยืนนิ่ง -> วาปไปไข่ -> เก็บ -> วาปกลับที่เดิม
-- ไม่มีเลนกลางทาง ไม่มีไต่ความเร็ว ไม่มียืนพัก เพราะสามอย่างนั้นมีไว้
-- หลบตัวตรวจจับซึ่งปิดไปแล้ว การขโมยไข่ใช้เวลาแค่เสี้ยววินาที
--
-- จุดยืนเก็บไว้ครั้งเดียวตอนเริ่ม แล้วกลับมาที่เดิมทุกรอบ
-- ไม่กลับเข้าแปลง เพราะแปลงอยู่ลึกกว่าและไม่ได้ปลอดภัยกว่าเซฟโซน
--==================================================================
local warpHome      -- จุดยืนในเซฟโซน คงที่ตลอดการรัน
local warpRound = 0 -- นับรอบไว้เว้นจังหวะทำงานบ้าน

-- เริ่มด้วยการ "ถือว่าเข้าเขตแล้ว"
--
-- ธงนี้อยู่ฝั่งเซิร์ฟเวอร์และติดค้างข้ามรอบ ไม่ได้หลุดทุกครั้งที่กลับเข้าเซฟโซน
-- วัดแล้ว: วาปจากเซฟโซนไปไข่ตรงๆ โดยไม่ข้ามเส้นเลย เซิร์ฟตอบ true ปกติ
-- เดินข้ามเส้นกินเวลา 0.7 วิ ต่อครั้ง จึงไม่ทำไว้ก่อนโดยไม่จำเป็น
-- ถ้าเซิร์ฟตอบ "Enter the gameplay area first" ค่อยไปเดินข้ามแล้วลองใหม่
local enteredZone = true

-- ธง "เข้าเขตแล้ว" อยู่ฝั่งเซิร์ฟเวอร์ ปลอมไม่ได้ ต้องเดินข้ามเส้นจริง
-- แต่ตั้งครั้งเดียวก็พอ ไม่ต้องข้ามใหม่ทุกรอบ (รอบละ 0.7 วิ)
-- เลยลองเก็บก่อน ถ้าเซิร์ฟบ่นว่ายังไม่เข้าเขตค่อยไปข้ามแล้วลองใหม่
local function ensureZone()
	if enteredZone then return true end
	if not enterGameplayZone() then return false end
	enteredZone = true
	return true
end

-- มีงานที่แปลงให้ทำจริงไหม
--
-- อ่านจากเซฟที่แคชไว้ในเครื่องล้วน ไม่ยิงเซิร์ฟ เรียกถี่ได้ไม่เปลือง
-- ถ้าไม่เช็คแล้วเรียก tendBase() ทุกรอบที่ว่าง จะกลายเป็นวาปเข้าแปลง
-- ไปยืนเฉยๆ ทั้งที่ไข่ยังไม่พร้อมฟัก ไม่มีไข่ในตัว และไม่มีตัวให้ขาย
--
-- การฟักเช็คล่วงหน้าไม่ได้ (ต้องยิงถามเซิร์ฟถึงจะรู้ว่าครบเวลาหรือยัง)
-- เลยใช้วิธีแวะไปลองทุก HatchRetryEvery วินาทีแทน
local lastHatchTry = 0

local function baseNeedsWork()
	local ok, data = pcall(Save.Get, LocalPlayer, false)
	if not ok or type(data) ~= "table" then return false end

	-- มีไข่ในกระเป๋ารอวางลงรัง
	for _, r in pairs(data.EggInventory or {}) do
		if type(r) == "table" and r.Placement == nil then return true end
	end

	-- มีสัตว์ที่เข้าข่ายขาย
	if Config.AutoSell then
		local list = sellCandidates()
		if #list > 0 then return true end
	end

	-- เงินพอสำหรับอัปฐานระดับถัดไป
	if Config.AutoUpgrade then
		local nextCfg = Bases.BASES[(data.BaseUpgradeLevel or 0) + 1]
		if nextCfg and (tonumber(data.Money) or 0) >= (nextCfg.Cost or math.huge) then
			return true
		end
	end

	-- ถึงรอบแวะไปลองฟัก
	--
	-- ของเดิมแวะทุก 30 วินาทีถ้ามีไข่วางอยู่ ไม่ว่าไข่จะพร้อมหรือไม่
	-- ไข่ที่เหลืออีก 20 นาทีก็ยังเดินไปลองอยู่ดี วนเข้าออกแปลงทั้งวัน
	-- (ผู้ใช้ถามตรงๆ ว่าทำไมชอบกลับไปเช็คที่แปลงตอนรอเก็บไข่)
	--
	-- ไปแล้วไม่ได้อะไรก็ถอยห่างขึ้นเป็นเท่าตัว 30 -> 60 -> 120 สูงสุด 300
	-- ฟักได้เมื่อไหร่กลับมาถี่เหมือนเดิมทันที
	if Config.AutoHatch then
		local base = math.max(5, tonumber(Config.HatchRetryEvery) or 30)
		local every = math.min(300, base * math.max(1, Hub.hatchBackoff or 1))
		if os.clock() - lastHatchTry >= every then
			for _, r in pairs(data.EggInventory or {}) do
				if type(r) == "table" and r.Placement ~= nil then
					lastHatchTry = os.clock()
					return true
				end
			end
		end
	end

	return false
end

local function warpCycle()
	if not waitForRespawn() then
		enteredZone = false
		return "ตายแล้วไม่เกิดใหม่"
	end

	local _, hrp = char()
	if not hrp then return "ไม่มีตัวละคร" end

	-- จุดยืนตรึงไว้กลางเซฟโซนเสมอ ไม่ใช่ "ที่ที่บังเอิญยืนตอนเริ่ม"
	--
	-- ตอนเริ่มรันตัวละครมักอยู่ในแปลงพอดี ถ้าจำจุดนั้นเป็นบ้าน
	-- ทุกรอบจะวาปจากไข่กลับเข้าแปลงตรงๆ ซึ่งตายเพราะแปลงอยู่ริมมุม
	-- กลางเซฟโซน (x512.8) อยู่กึ่งกลางระหว่างแถวแปลง (~x464) กับเส้นแดง (552.8)
	-- ตั้งค่า WarpHomeX / WarpHomeZ ทับได้ถ้าอยากยืนจุดอื่น
	-- ตั้งค่าจุดกลางใหม่ระหว่างรันได้ ไม่ต้องปิดเปิดสคริปต์
	--
	-- ของเดิมคำนวณครั้งเดียวตอนเริ่ม แก้ค่าในคอนฟิกทีหลังจึงไม่มีผล
	-- ต้องรันสคริปต์ใหม่ทุกครั้งที่อยากขยับจุดยืน ซึ่งไม่สะดวกเวลาหาจุดที่ดี
	if warpHome and (tonumber(Config.WarpHomeX) or tonumber(Config.WarpHomeZ)) then
		local wx = tonumber(Config.WarpHomeX) or warpHome.X
		local wz = tonumber(Config.WarpHomeZ) or warpHome.Z
		if math.abs(wx - warpHome.X) > 0.5 or math.abs(wz - warpHome.Z) > 0.5 then
			warpHome = Vector3.new(wx, LANE_Y, wz)
			log(("ย้ายจุดกลางเป็น x%d z%d"):format(math.floor(wx), math.floor(wz)))
		end
	end

	if not warpHome then
		-- จุดยืนกลาง SAFE ZONE ฝังตายตัว
		--
		-- พิกัดนี้วัดจากในเกมจริง เป็นจุดที่ยืนแล้วออกไปเก็บไข่ได้ทุกทิศ
		-- และอยู่ลึกพอจากเส้นแดงจนสัตว์ที่ไล่ตามมาเอื้อมไม่ถึง
		--
		-- ตั้งตายตัวตามที่เจ้าของสคริปต์กำหนด ไม่ต้องตั้งในคอนฟิก
		-- ข้อควรรู้: คนที่แปลงอยู่คนละแถวจะยืนไกลจากแปลงตัวเอง
		-- ถ้าวันไหนเจอปัญหานั้น ให้ตั้ง WarpHomeZ ในคอนฟิกทับได้
		warpHome = Vector3.new(
			tonumber(Config.WarpHomeX) or Hub.HOME.X,
			Hub.HOME.Y,
			tonumber(Config.WarpHomeZ) or Hub.HOME.Z)
		log(("จุดยืนกลาง SAFE ZONE: x%d z%d"):format(
			math.floor(warpHome.X), math.floor(warpHome.Z)))
	end

	-- ไม่เรียก tendBase() ตรงนี้
	--
	-- ข้างในมี placePendingEggs() ซึ่งเดินเข้าแปลง พอเรียกทั้งก่อนและหลังเก็บไข่
	-- กลายเป็นเข้าแปลงสองรอบต่อไข่หนึ่งใบ ทั้งที่ตอนเริ่มยังไม่มีไข่ให้วาง
	-- ย้ายไปทำครั้งเดียวหลังเก็บได้ ตอนที่ต้องเข้าแปลงอยู่แล้ว
	-- ไปยืนทับไข่รอตั้งแต่ยังรีเซ็ตไม่จบ
	--
	-- ข้อมูลไข่ชุดใหม่มาก่อนที่จะเก็บได้ (สถานะโชว์ราคาได้ตั้งแต่ยังนับถอยหลัง)
	-- ไปยืนทับใบที่แพงสุดรอไว้ แล้วยิงเก็บถี่ๆ จะได้ก่อนคนที่รอให้จบก่อนค่อยวิ่ง
	--
	-- ยืนกลางสนามตอนรีเซ็ตมีการ์ดเดินอยู่ ถ้าเลือดลดแม้แต่นิดเดียวให้ถอยทันที
	-- ไข่ใบเดียวไม่คุ้มกับการตายแล้วเสียของที่ถืออยู่
	-- เงื่อนไขเดิมไม่เคยเป็นจริงตอนกล่องขึ้น
	--
	-- isResetting() ตอบ false ทันทีที่ยังมีไข่เก่าเหลือให้เก็บในสนาม
	-- ซึ่งช่วงกล่องขึ้นมักมีไข่เหลืออยู่เสมอ ฟีเจอร์นี้จึงไม่เคยทำงานเลยสักครั้ง
	-- (ไล่ดูไทม์ไลน์ทั้งวันไม่เจอบรรทัด "ยืนทับไข่รอรีเซ็ตจบ" แม้แต่ครั้งเดียว)
	--
	-- ใช้ธงกล่องแทน ซึ่งเป็นสัญญาณตรงว่าอยู่ในช่วงรีเซ็ตจริง
	-- ใกล้รีเซ็ตแล้ว: กลับมายืนนิ่งที่จุดกลาง รอกล่องขาวหายก่อนค่อยออก
	--
	-- ผู้ใช้สั่งไว้ตรงๆ: เหลือราว 10 วินาทีก่อนกลางคืน ให้ยืนรอที่เซฟโซนนิ่งๆ
	-- รอไข่รีเซ็ตเสร็จและกล่องเปิด แล้วค่อยวาปไปเก็บ ถึงจะเก็บติด
	--
	-- ทำไมของเดิมพัง: ช่วงกล่องขึ้นมันวาปออกไปยืนทับไข่แล้วยิงเก็บรัวๆ
	-- แต่เซิร์ฟไม่ให้เก็บตอนกล่องยังอยู่ ยิงไปกี่ครั้งก็ไม่ติด
	-- แล้วลูปชุดเก็บก็เลื่อนไปใบถัดไป = ใบที่แพงสุดโดนข้ามทิ้งทั้งที่ยังอยู่ในสนาม
	-- (ผู้ใช้เจอตรงๆ: "มันไปหาแล้วเก็บไม่ติดรอบแรก มันเลยเมิน ไม่ไปเก็บอีกเลย")
	--
	-- ยืนรอเฉยๆ ปลอดภัยกว่าและได้ของครบกว่า ไม่มีการ์ดมาตีระหว่างรอด้วย
	local holdSecs = tonumber(Config.PreResetHold) or 10
	if holdSecs > 0 and Config.MoveMode == "warp" then
		local left = secondsToReset()
		if (left ~= nil and left <= holdSecs) or Hub.BoxUp or isResetting() then
			Hub.Phase = "ใกล้รีเซ็ต - ยืนรอที่จุดกลาง"
			move(warpHome)

			-- รอจน "ไข่สลับชุดจริง" ห้ามใช้ธงกล่องเป็นตัวตัดสิน
			--
			-- Hub.BoxUp อ่านจาก GUI (ResetStartTimer / EndingSoon) ซึ่งโค้ดเองจดไว้ว่า
			-- "เปิดค้างบ้างไม่ขึ้นบ้าง เชื่อไม่ได้" และตัวนับเวลาก็เด้งกลับช้ากว่าของจริง
			-- ถ้าเชื่อธงนั้น เราจะหลุดออกไปตอนที่เซิร์ฟยังไม่ให้เก็บ แล้วเก็บพลาดเหมือนเดิม
			--
			-- ตัวที่โกหกไม่ได้คือ fieldIsFresh() = เจอ Uid ที่ไม่เคยเห็นพร้อมกันตั้งแต่ 5 ใบ
			-- นั่นคือไข่ชุดใหม่มาถึงจริง ตอนนั้นเก็บได้แน่นอน
			-- สัญญาณที่มีให้เลือก และเลือกยังไง:
			--
			--   NIGHT-HIT-ZERO   ตัวนับ "in Xs" ถึงศูนย์      -> เร็วไป ไข่ยังไม่สลับ
			--   TIMELEFT-JUMP    ตัวนับ 5 นาทีเด้งกลับ        -> เร็วไปเหมือนกัน และเด้งช้ากว่าของจริงบ้าง
			--   BOX=true/false   กล่องขาว (อ่านจาก GUI)       -> เชื่อเดี่ยวๆ ไม่ได้ เปิดค้างบ้างไม่ขึ้นบ้าง
			--   EGGS-IN-FIELD    ไข่ชุดใหม่โผล่จริง (ถามเซิร์ฟ) -> ของจริง แต่ยังไม่พอ
			--
			-- ต้องครบสองอย่างถึงจะออก: ไข่สลับชุดจริง "และ" กล่องหายแล้ว
			-- ขาดข้อใดข้อหนึ่งก็ยังเก็บไม่ติด ยิงไปก็เสียเที่ยวและโดนการ์ดตี
			local t0 = os.clock()
			local hardStop = tonumber(Config.ResetWaitMax) or 90
			local sawFresh = false
			while os.clock() - t0 < hardStop do
				if not Config.Running or not alive() then return "หยุดกลางทาง" end

				if fieldIsFresh() then sawFresh = true end
				-- กล่องต้องหายด้วย ไม่ใช่แค่ไข่มา
				if sawFresh and not Hub.BoxUp and not isResetting() then break end

				-- ยืนนิ่งจริงๆ ตรึงไว้กันไถล ไม่ต้องยิงเซิร์ฟอะไรเลย
				settle(warpHome, 0.4)
			end

			local waited = os.clock() - t0
			if waited >= hardStop then
				log(("รอครบ %d วิแล้วยังไม่พร้อม (ไข่ใหม่=%s กล่อง=%s) - ออกไปลองเก็บเลย")
					:format(hardStop, tostring(sawFresh), tostring(Hub.BoxUp)))
			else
				log(("ไข่รีเซ็ตแล้วและกล่องหายแล้ว (รอไป %.1f วิ) - ออกไปเก็บ"):format(waited))
			end
			Hub.Phase = "รีเซ็ตจบ - ออกไปเก็บไข่"
			Hub.ResetSeenAt = os.clock()
			Hub.ResetWaits = (Hub.ResetWaits or 0) + 1
		end
	end

	if (Hub.BoxUp or isResetting()) and Config.MoveMode == "warp"
	   and Config.PreWarpOnReset == true and acPatched ~= false then
		local waitEgg = findEgg(Config.Area)
		if waitEgg then
			Hub.Phase = "ยืนทับไข่รอรีเซ็ตจบ"
			local _, _, hum0 = char()
			local hp0 = hum0 and hum0.Health or 100

			if move(waitEgg.BottomCFrame.Position + Vector3.new(0, 3, 0)) then
				local t0 = os.clock()
				while os.clock() - t0 < 120 do
					-- ไข่รีเซ็ตแล้วต้องทิ้งงานบ้านทันที
					-- วัดจริง: รอบที่ติดฟักไข่ 8 ฟองอยู่ กว่าจะเก็บใบแรกได้คือวินาทีที่ 13.1
					-- รอบที่ว่างอยู่ เก็บใบแรกได้ที่วินาทีที่ 1.8  ต่างกัน 11 วินาที = ของดีโดนชิงหมด
					-- งานบ้านทำตอนไหนก็ได้ ไข่ดีมีให้แย่งแค่ไม่กี่วินาที
					if not Config.Running or not alive() or fieldIsFresh() or Hub.quietNow() then break end

					local _, _, hum = char()
					if not hum or hum.Health < hp0 then
						log("โดนตีระหว่างยืนรอ - ถอยกลับเซฟโซน")
						break
					end

					local ok = carryF:InvokeServer({ Uid = waitEgg.Uid })
					if ok == true then
						Stats.stolen += 1
						log(("ได้ไข่ทันทีที่รีเซ็ตจบ: %s ($%s/s)"):format(
							tostring(waitEgg.AssetCategory), comma(eggRate(waitEgg))))
						Hub.Phase = "วาปกลับ SAFE ZONE"
						move(warpHome)
						Hub.Phase = "เข้าแปลงวางไข่"
						tendBase()
						move(warpHome)
						Hub.Phase = "ยืนรอที่ SAFE ZONE"
						return nil
					end

					-- รีเซ็ตจบแล้วแต่ยังเก็บไม่ได้ (คนอื่นชิงไปก่อน) ไปทางปกติ
					if not isResetting() then break end
					task.wait(0.12)
				end
			end
			move(warpHome)
		end
	end

	if not waitOutReset() then return "หยุดระหว่างรอรีเซ็ต" end

	-- มีไข่ค้างในกระเป๋าที่ยังวางไม่ลง = รังเต็ม อย่าเพิ่งออกไปเก็บใบใหม่
	--
	-- ถือได้ทีละใบ ถ้าใบเก่ายังค้างอยู่ ออกไปก็เก็บไม่ได้ เสียเที่ยวเปล่าและเสี่ยงเปล่า
	-- ลองวางก่อนหนึ่งที เผื่อมีช่องว่างจากไข่ที่เพิ่งฟักไป ถ้ายังไม่ลงก็รอรอบหน้า
	-- โหมดเก็บติดกันไม่ต้องเคลียร์ก่อน
	--
	-- มันตั้งใจสะสมไข่ไว้ในกระเป๋าอยู่แล้ว แล้ววางทีเดียวตอนจบรอบ
	-- ถ้ามาไล่วางก่อนออกไปเก็บ = วางสองรอบต่อหนึ่งชุด
	-- วัดจริง: ขั้นนี้กินไป 8.76 วินาทีต่อรอบโดยไม่ได้อะไรเพิ่ม
	local chainOn = (Config.MoveMode == "warp")
		and math.max(1, math.floor(tonumber(Config.ChainGrab) or 5)) > 1

	local stuck = 0
	if not chainOn then
		for _, rec in pairs(ownedEggs()) do
			if rec.Placement == nil then stuck = stuck + 1 end
		end
	end
	-- กำลังพักเพราะวางไม่ลงติดกันหลายรอบ ข้ามไปเก็บไข่เลย
	-- ไม่งั้นจะวนเข้าแปลงแล้วออกไม่จบ ไม่ได้ไปเก็บอะไรเลยสักใบ
	if stuck > 0 and Hub.placeBlocked() then stuck = 0 end

	if stuck > 0 then
		Hub.Phase = "มีไข่ค้าง - เอาไปวางก่อน"
		placePendingEggs()
		move(warpHome)

		local left = 0
		for _, rec in pairs(ownedEggs()) do
			if rec.Placement == nil then left = left + 1 end
		end
		Hub.notePlaceResult(left < stuck)   -- วางลงได้บ้างก็ถือว่าคืบหน้า ล้างตัวนับ
		if left > 0 then
			Hub.Phase = "วางไข่ที่ค้างไม่ลง"
			task.wait(1)
			return ("วางไข่ที่ค้างไม่ลง %d ฟอง (รังเต็มหรือหาที่ว่างไม่ได้)"):format(left)
		end
	end

	noteFieldReset()

	if resetStillSettling() then
		Hub.Phase = "รีเซ็ตเสร็จ - รอเซิร์ฟพร้อม"
		task.wait(0.2)
		return nil
	end

	local egg, rate = findEgg(Config.Area)
	if not egg then return "ไม่มีไข่ว่างที่ " .. Config.Area end
	rate = rate or 0

	local worth, floorRate = worthGoing(rate)
	-- เพิ่งรีเซ็ต: เดิมเก็บก่อนไม่ต้องเทียบ เพราะไข่หายไปเองเมื่อถึงเช้า
	-- แต่ถ้าเวฟใหม่มีแต่ของกากก็ไม่ควรวิ่งไปเก็บอยู่ดี ยืนรอเวฟถัดไปคุ้มกว่า
	if fieldIsFresh() and Config.SkipWorseThanPen == false then worth = true end
	if not worth then
		-- ไม่มีไข่คุ้มให้เก็บ = เวลาว่าง เอาไปทำงานบ้านให้จบเลย
		-- แต่ต้องมีงานจริงก่อนถึงจะเข้าแปลง ไม่งั้นวาปไปยืนเฉยๆ ทุกรอบ
		--
		-- ของเดิมยืนรอเฉยๆ แล้วงานบ้านไปผูกกับตัวนับรอบที่เพิ่มเฉพาะตอนเก็บไข่ได้
		-- พอไม่มีไข่คุ้ม ตัวนับไม่ขยับ = ไม่เคยฟักไข่ ไม่เคยขาย ไม่เคยอัปฐานเลย
		-- (เจอจริง: เงิน $1.4B ค่าอัปเกรด $500M แต่สถิติขึ้น "อัปฐาน 0")
		if baseNeedsWork() and not fieldIsFresh() and not Hub.quietNow() then
			Hub.Phase = "ไม่มีไข่คุ้ม - จัดการฐานแทน"
			tendBase()
			move(warpHome)
		end

		-- ต้องกลับไปยืนรอที่จุดกลางเสมอ ห้ามยืนค้างหน้าแปลง
		--
		-- ของเดิมแค่ตั้งเฟสเป็น "รอไข่ดีๆ" แล้ว wait เฉยๆ ไม่สั่งขยับเลย
		-- ถ้ารอบก่อนหน้าจบลงตอนอยู่หน้าแปลง (เช่นเพิ่งวางไข่เสร็จ หรือ baseNeedsWork
		-- เป็นเท็จเลยไม่ได้เรียก move(warpHome)) ตัวจะยืนค้างอยู่ตรงนั้นทั้งวัน
		-- (วัดจริง: ค้างที่ x492 z-244 หน้าแปลง ทั้งที่จุดกลางอยู่ x513 z-365)
		--
		-- ยืนหน้าแปลงมีสองปัญหา: พอไข่มามันต้องออกตัวจากริม ซึ่งเป็นทางที่ตายบ่อย
		-- และไกลกว่าจุดกลาง เสียเวลาทุกรอบ
		local _, hIdle = char()
		if hIdle and (hIdle.Position - warpHome).Magnitude > 20 then
			Hub.Phase = "กลับไปยืนรอที่จุดกลาง"
			move(warpHome)
		end

		Hub.Phase = "รอไข่ดีๆ"
		task.wait(1)
		return ("รอไข่ดีกว่านี้ - ดีสุด $%s/s สู้ตัวอ่อนสุดในคอก ($%s/s) ไม่ได้")
			:format(comma(rate), comma(floorRate))
	end

	-- ต้องยืนจุดกลางก่อนทุกครั้ง ไม่ใช่วาปจากที่ไหนก็ได้
	-- ถ้าเผลอวาปจากในแปลงออกไปไข่ตรงๆ จะตาย เพราะแปลงอยู่ริมมุม
	Hub.Phase = "กลับไปยืนกลาง SAFE ZONE"
	move(warpHome)

	-- เก็บติดๆ กันหลายฟองก่อนวาง
	--
	-- รอบเดิมเป็น ไข่ -> เซฟโซน -> แปลง -> วางลงรัง -> เซฟโซน  = ~3.5 วิ/ฟอง
	-- รอบใหม่เป็น  ไข่ -> แปลง(ฝาก) -> ไข่ถัดไป              = ~1 วิ/ฟอง
	-- แล้วค่อยวางลงรังทีเดียวตอนสะสมครบ ChainGrab ฟอง
	--
	-- ที่ทำได้เพราะ "เข้าเขตแปลง" ฝากไข่ให้เลย ไม่ต้องวางลงรังก่อนเก็บใบใหม่
	-- ช่วงไข่เพิ่งรีเซ็ต เก็บให้หมดก่อนค่อยไปวาง
	--
	-- วัดจริง: เก็บครบ 5 ใบที่วินาทีที่ 7.7 แล้วไปวางลงรัง
	-- กว่าจะกลับมาเก็บใบที่ 6 คือวินาทีที่ 15.9 หายไป 8.2 วินาที
	-- ช่วง 8 วินาทีนั้นคนอื่นกวาดของดีไปหมดแล้ว
	-- ไข่วางตอนไหนก็ได้ แต่ไข่ดีมีให้แย่งแค่ช่วงสั้นๆ เท่านั้น
	local chainGrab = math.max(1, math.floor(tonumber(Config.ChainGrab) or 5))
	if fieldIsFresh() then
		chainGrab = math.max(chainGrab, math.floor(tonumber(Config.ChainGrabFresh) or 12))
	end
	if Config.MoveMode == "warp" and chainGrab > 1 then
		-- เลือกเป้าทั้งชุดจากการถามเซิร์ฟครั้งเดียว
		--
		-- ของเดิมเรียก findEgg() ก่อนวาปทุกใบ = ยิงเซิร์ฟ 230ms คูณจำนวนใบ
		-- ข้อมูลชุดเดียวกันใช้ได้ทั้งชุดอยู่แล้ว ถามครั้งเดียวประหยัดไปเกือบวินาที
		-- ใบไหนโดนคนอื่นชิงไปก่อน carry จะตอบ false เอง แล้วข้ามไปใบถัดไป
		local queue = {}
		do
			local ranked = rankedEggs(Config.Area)
			for _, item in ipairs(ranked) do
				if #queue >= chainGrab * 2 then break end
				local okToTake = (fieldIsFresh() and Config.SkipWorseThanPen == false)
					or Config.SkipWeak == false
					or worthGoing(item.rate or 0)
				if okToTake then queue[#queue + 1] = item.rec end
			end
		end
		if #queue > 0 and Hub.ResetSeenAt and not Hub.GapEggSeen then
			Hub.GapEggSeen = os.clock() - Hub.ResetSeenAt
		end
		if #queue == 0 then
			-- ยืนรอต้องรอที่จุดกลางเท่านั้น (ดูเหตุผลที่เฟส "รอไข่ดีๆ" อีกจุด)
			local _, hq = char()
			if hq and (hq.Position - warpHome).Magnitude > 20 then
				Hub.Phase = "กลับไปยืนรอที่จุดกลาง"
				move(warpHome)
			end
			Hub.Phase = "รอไข่ดีๆ"
			task.wait(0.5)
			return "ไม่มีไข่คุ้มในสนาม"
		end

		local got, tried = 0, 0
		local qi = 0
		while got < chainGrab and tried < chainGrab * 2 do
			if not Config.Running or not alive() then break end
			tried = tried + 1

			qi = qi + 1
			local nextEgg = queue[qi]
			if not nextEgg then break end

			-- ต้องกลับมายืนกลางก่อนทุกครั้ง ห้ามวาปจากริมสนามไปไข่ตรงๆ
			--
			-- ปกติหลังเก็บได้จะแวะกลางอยู่แล้วตอนฝากไข่
			-- แต่ถ้ารอบก่อนเก็บไม่ติด ตัวจะค้างอยู่ที่ไข่ใบเดิมซึ่งอยู่ริมสนาม
			-- วาปจากริมไปริมคือทางที่ตายบ่อยสุด (ผู้ใช้ยืนยันตรงกัน)
			-- เกณฑ์ต้องต่ำกว่าระยะจากแปลงถึงจุดกลาง
			--
			-- วัดจริง: แปลงอยู่ x465 จุดกลาง x512 ห่างกันแค่ 47 studs
			-- ตั้งไว้ 60 เงื่อนไขจึงไม่เข้า มันวาปจากแปลงไปไข่ตรงๆ
			-- ซึ่งเป็นทางที่ตายบ่อย ตั้ง 20 ครอบคลุมทั้งจากแปลงและจากกลางสนาม
			-- ยืนอยู่จุดกลางพอดีจะไม่เข้าเงื่อนไข ไม่เสียเที่ยวเปล่า
			if Config.ViaHome ~= false then
				local _, hnow = char()
				if hnow and (hnow.Position - warpHome).Magnitude > 20 then
					Hub.Phase = "กลับกลางก่อนออกรอบใหม่"
					move(warpHome)
				end
			end

			Hub.Phase = ("วาปเก็บไข่ (%d/%d)"):format(got + 1, chainGrab)
			-- วาปพลาดใบเดียวไม่ควรตัดจบทั้งชุด
			--
			-- ของเดิม break ทันที = ได้ 3 ใบแล้วเลิก ทั้งที่ตั้งไว้ 12 ใบ
			-- ใบนี้ไปไม่ได้ก็ข้ามไปใบถัดไป ยังมีอีกสี่สิบใบรอในสนาม
			-- (ผู้ใช้รายงานตรงกัน: เก็บไม่ครบ 5 ใบสักที)
			if not move(nextEgg.BottomCFrame.Position + Vector3.new(0, 3, 0)) then
				Hub.SkipEgg = (Hub.SkipEgg or 0) + 1
				continue
			end

			local eggPos = nextEgg.BottomCFrame.Position + Vector3.new(0, 3, 0)
			if fieldIsFresh() or Hub.BoxUp then Hub.pinAt(eggPos, 2) end
			-- โดนดีดกลับระหว่างทางไหม ถ้าใช่วาปกลับไปก่อนค่อยยิง
			Hub.atEggOrRewarp(eggPos, function() return move(eggPos) end)
			local ok, msg = Hub.callTimed(function(a)
				return carryF:InvokeServer(a)
			end, { Uid = nextEgg.Uid }, tonumber(Config.CallTimeout) or 4)
			if ok ~= true then Hub.LastCarryMsg = tostring(msg) end

			-- เซิร์ฟล็อกไม่ให้เก็บอยู่ ~6 วินาทีแรกหลังไข่รีเซ็ต
			--
			-- วัดจริงจากไทม์ไลน์รอบรีเซ็ต (เซฟโซน x=512):
			--   +1.0 วาปถึง x3388 เก็บไม่ติด
			--   +2.6 วาปถึง x3388 ใบเดิม เก็บไม่ติด
			--   +4.2 วาปถึง x3388 ใบเดิม เก็บไม่ติด
			--   +5.9 วาปถึง x3388 ใบเดิม ติด! แล้วรัวต่อ 2/5 3/5 4/5 5/5 ภายใน 3 วิ
			-- แปลว่าไปถึงไข่ทุกครั้ง ไม่ได้ติดกำแพง เซิร์ฟแค่ยังไม่เปิดให้เก็บ
			--
			-- ของเดิมพอไม่ติดจะวาปกลับเซฟโซนแล้ววนมาใหม่ เสียรอบละ 1.6 วินาที
			-- ยืนทับไข่ยิงรัวรอปลดล็อกแทน จะได้เป็นคนแรกที่เก็บได้ตอนเปิด
			if ok ~= true and fieldIsFresh() and not tostring(msg):find("carrying") then
				-- ยืนจ้องใบเดียวนานๆ คือการเสียทั้งรอบ
				--
				-- วัดจริง: ยืนรอใบเดียว 18 วินาทีแล้วไม่ได้อะไรเลย
				-- ระหว่างนั้นกล่องหายไปแล้ว ไข่ใบอื่นเก็บได้ตั้งนานแล้ว
				-- เซิร์ฟล็อกเป็นราย "ใบ" ไม่ใช่ล็อกทั้งสนาม ใบนี้ไม่ให้ก็ไปใบอื่น
				--
				-- รอสั้นๆ ต่อใบแล้วหมุนไปใบถัดไป วนกลับมาใบเดิมได้ในรอบหน้า
				-- ResetHoldFor ยังใช้เป็นเพดานรวมของทั้งรอบอยู่
				Hub.Phase = "ยืนทับไข่รอเซิร์ฟปลดล็อก"
				local slice = math.max(0.5, tonumber(Config.HoldPerEgg) or 2.5)
				local total = math.max(2, tonumber(Config.ResetHoldFor) or 10)
				local deadline = os.clock() + math.min(slice, total)
				local n = 0
				while os.clock() < deadline do
					if not Config.Running or not alive() then break end
					task.wait(0.1)
					n = n + 1
					-- ยืนนานๆ ระบบอาจลากกลับ ตอกตำแหน่งซ้ำทุก ~1 วินาที
					if n % 10 == 0 then
						move(nextEgg.BottomCFrame.Position + Vector3.new(0, 3, 0))
						-- ใบนี้โดนคนอื่นชิงไปแล้วหรือยัง ถ้าหายจากสนามให้ไปใบถัดไป
						-- ไม่งั้นจะยืนยิง uid ที่ไม่มีอยู่จริงจนครบ 10 วินาที
						clearSnapCacheFwd()
						local still = false
						for _, e in pairs(snapshot()) do
							if e.Uid == nextEgg.Uid then still = true break end
						end
						if not still then break end
					end
					Hub.pinAt(eggPos, 2)   -- ต่ออายุการตรึงทุกครั้งที่ยิงซ้ำ
					Hub.atEggOrRewarp(eggPos, function() return move(eggPos) end)
					ok, msg = Hub.callTimed(function(a)
						return carryF:InvokeServer(a)
					end, { Uid = nextEgg.Uid }, tonumber(Config.CallTimeout) or 4)
					if ok ~= true then Hub.LastCarryMsg = tostring(msg) end
					if ok == true or tostring(msg):find("carrying") then break end
				end
			end

			if ok == true then
				if Hub.ResetSeenAt and not Hub.GapFirstGrab then
					Hub.GapFirstGrab = os.clock() - Hub.ResetSeenAt
				end
				got = got + 1
				Stats.stolen += 1
				dropFromSnap(nextEgg.Uid)   -- ใบนี้หายจากสนามแล้ว
				-- กลับเซฟโซนฝากทันที ช่องถือว่างเร็วกว่ายืนรอ 5 เท่า
				Hub.Phase = "วาปกลับ SAFE ZONE ฝากไข่"
				local okBack = depositCarried(warpHome)
				-- ฝากไข่ไม่สำเร็จก็ลองใบถัดไป อย่าตัดจบทั้งชุด
				if not okBack then
					Hub.DepositFail = (Hub.DepositFail or 0) + 1
					continue
				end
			elseif tostring(msg):find("carrying") then
				Hub.Phase = "วาปกลับ SAFE ZONE ฝากไข่"
				if not depositCarried(warpHome) then break end
			elseif tostring(msg):find("gameplay area") then
				task.wait(0.2)
				qi = qi - 1   -- ใบเดิมยังไม่ได้ ลองซ้ำ

			elseif Hub.BoxUp or isResetting() then
				-- เก็บไม่ติดเพราะยังรีเซ็ตไม่จบ = เลิกทั้งชุด กลับไปรอที่จุดกลาง
				--
				-- ห้ามลองซ้ำ ห้ามข้ามไปใบอื่น ทั้งสองทางผิดหมด:
				--   ลองซ้ำ  = ยืนแช่ข้างไข่ที่มีการ์ดเดินอยู่ แล้วโดนตี
				--             (ลูกค้ารายงาน "เก็บไข่ใบแรกชอบโดนตีตลอด")
				--   ข้ามไป  = ใบแพงสุดโดนทิ้ง กว่าจะวนกลับมาคนอื่นแย่งไปแล้ว
				--             (ลูกค้ารายงาน "กว่ามันจะวนมาเก็บใบแพงสุดอีก คนอื่นแย่ง")
				--
				-- ระหว่างกล่องขาวขึ้น เซิร์ฟไม่ให้เก็บ ยิงกี่ครั้งก็ไม่ติด อยู่ตรงนั้นมีแต่เสีย
				-- ถอยกลับมายืนนิ่ง แล้วรอบถัดไปตัวรอ (Config.PreResetHold)
				-- จะยืนรอจนไข่สลับชุดจริงค่อยออกไป ตอนนั้นเก็บติดแน่และได้ใบแพงสุดก่อนใคร
				Hub.Phase = "ยังรีเซ็ตไม่จบ - กลับไปรอที่จุดกลาง"
				move(warpHome)
				Hub.BoxAborts = (Hub.BoxAborts or 0) + 1
				break
			end
		end

		-- กลับจุดยืนแล้วค่อยจัดการฐานทีเดียว
		Hub.Phase = "วาปกลับกลาง SAFE ZONE"
		move(warpHome)

		if got > 0 then
			-- จัดคอกให้ดีที่สุดทุกรอบ
			--
			-- Backpack: EquipBest ยิงเซิร์ฟครั้งเดียวจบ ถูกกว่างานบ้านเต็มชุด (10 วินาที) มาก
			-- ของเดิมเรียกแค่ตอนทำงานบ้านทุก 5 รอบ สัตว์ตัวแพงเลยนั่งอยู่นอกคอกเป็นนาที
			-- วัดจริงตอนเจอ: อ่อนสุดในคอก $110,766 แต่นอกคอกมี $120,196 รออยู่
			-- มีไข่ดีรออยู่ไหม  ตัดสินก่อนว่าจะแวะทำอย่างอื่นหรือรีบไปเก็บต่อ
			local stillGood = false
			do
				local e, r = findEgg(Config.Area)
				if e then stillGood = (Config.SkipWeak == false) or worthGoing(r or 0) end
			end

			-- จัดคอกทุกรอบ ยิงเซิร์ฟครั้งเดียว ~0.1 วิ ถูกพอที่จะไม่ต้องเลื่อน
			if equipBestF then
				pcall(function() equipBestF:InvokeServer() end)
				clearPetsCache()
			end

			-- ขายเฉพาะตอนสนามไม่มีไข่ดีแล้ว
			--
			-- ขายตัวละ 0.15 วิ ถ้าขาย 4 ตัวทุกรอบคือถ่วงรอบละ ~1 วินาที
			-- สัตว์ขายช้าไปหน่อยไม่เสียหาย แต่ไข่หายไปเองเมื่อถึงเช้า
			-- ตั้งเป็นเลขถ้าอยากจำกัดจำนวนต่อรอบ (เช่น 4)
			-- 0 = ขายให้หมดไม่จำกัด
			local sn = math.max(0, math.floor(tonumber(Config.SellPerCycle) or 0))
			if not stillGood then
				pcall(autoSellWeak, false, sn > 0 and sn or nil)
			end

			-- คอกล้นมากแล้วต้องขายให้ได้ ไม่ว่าสนามจะมีไข่ดีอยู่หรือไม่
			--
			-- ลูกค้ารายงานตรงๆ ว่า "ปรับให้มันขายยังไง มันไม่ขายให้"
			-- สาเหตุ: ทางขายทั้งสองทางโดนล็อกด้วยเงื่อนไขที่แทบไม่เคยเป็นจริงระหว่างฟาร์ม
			--   ใน tendBase   autoSellWeak อยู่ท้ายสุด หลัง "if stopped() then return end" สามชั้น
			--                 (stopped = สนามมีไข่ใหม่) จึงแทบไม่เคยถึงบรรทัดนั้น
			--   ตรงนี้        ขายเฉพาะตอน not stillGood = สนามไม่มีไข่ดีเหลือแล้วเท่านั้น
			-- ระหว่างฟาร์มจริงสนามมีไข่ตลอด = ไม่ขายเลยสักตัว สัตว์ล้นจนไม่มีที่เก็บ
			--
			-- ตัวนี้เป็นตาข่ายกันพลาด ทำงานเฉพาะตอนล้นเกินช่องคอกไปมาก
			local overflow = 0
			pcall(function()
				local pets = myPets()
				local keep = equipCap() + math.max(0, math.floor(Config.KeepExtra or 0))
				overflow = math.max(0, #pets - keep)
			end)
			if overflow >= 10 then
				Hub.Phase = ("คอกล้น %d ตัว - ขายทิ้ง"):format(overflow)
				pcall(autoSellWeak, true, sn > 0 and sn or nil)   -- force = ไม่สนเงื่อนไขอื่น
			end

			warpRound = warpRound + 1
			local every = math.max(1, math.floor(tonumber(Config.TendEvery) or 5))

			-- ไข่ค้างในกระเป๋าเยอะ = รังเต็ม ต้องรีบฟักเปิดช่อง อย่ารอครบรอบ
			local waiting = 0
			for _, rec in pairs(ownedEggs()) do
				if rec.Placement == nil then waiting = waiting + 1 end
			end

			-- งานบ้านเต็มชุดกินเวลา 10.13 วินาที (ฟัก 23 ขาย 34 ยิงทีละตัว)
			-- ถ้าไปตกช่วงไข่ใหม่โผล่ก็พลาดทั้งรอบ  รอสนามว่างก่อนค่อยทำ
			local mustTend = (waiting >= chainGrab and not fieldIsFresh())          -- กระเป๋าจะล้น ต้องเคลียร์
				or (warpRound % every == 0 and not stillGood)  -- ครบรอบ และสนามว่างแล้ว

			if mustTend then
				Hub.Phase = "เข้าแปลงจัดการฐาน"
				tendBase()

				-- กระเป๋าไข่ใกล้เต็ม = ต้องวางให้ได้จริง ห้ามพึ่ง tendBase อย่างเดียว
				--
				-- tendBase มี "if stopped() then return end" คั่นหลายจุด
				-- (stopped = สนามมีไข่ใหม่โผล่ หรืออยู่ช่วงเงียบ)
				-- และ placePendingEggs อยู่ท้ายสุดของมัน
				-- ยิ่งสนามมีไข่ให้เก็บเยอะ ยิ่งโดนตัดจบก่อนถึงบรรทัดวาง
				-- ผลคือไข่กองสะสมจนขึ้น "Egg inventory full!!" แล้วเก็บอะไรไม่ได้อีกเลย
				--
				-- ตรงนี้เรียกซ้ำแบบไม่มีเงื่อนไข ฟักก่อนเพื่อเปิดช่องรัง แล้วค่อยวาง
				if waiting >= chainGrab then
					Hub.Phase = "กระเป๋าไข่เต็ม - ฟักและวางให้หมด"
					-- force = true  ห้ามทิ้งงานกลางคันเพราะสนามมีไข่
					-- ฟักคือทางเดียวที่จะเปิดช่องรัง ถ้าไม่ฟักก็วางอะไรไม่ได้เลย
					pcall(hatchReadyEggs, nil, true)
					pcall(placePendingEggs)
				end
			else
				-- ฟักก่อนวางเสมอ ฟักแล้วช่องรังว่าง ไข่ที่เพิ่งเก็บมาถึงจะลงได้
				Hub.Phase = "เข้าแปลงฟักไข่ + วางไข่"
				-- 0 = ไม่จำกัด ส่ง nil เข้าไปแทน
				-- ถ้าส่ง 0 ตรงๆ ตัวเช็ค hatched >= limit จะเป็นจริงทันที = ไม่ฟักเลย
				local hn = math.max(0, math.floor(tonumber(Config.HatchPerCycle) or 0))
				hatchReadyEggs(hn > 0 and hn or nil)
				placePendingEggs()
			end
			move(warpHome)
			Hub.Phase = "ยืนรอที่ SAFE ZONE"
			return nil
		end

		Stats.failed += 1
		return "เก็บไม่สำเร็จในรอบนี้"
	end

	Hub.Phase = "วาปไปเก็บไข่"
	log(("เป้าหมาย: %s [%s] $%s/s"):format(egg.AssetCategory, egg.AreaId, comma(rate)))

	local got, lastMsg
	for attempt = 1, 3 do
		if not Config.Running then return "หยุดกลางทาง" end
		if not move(egg.BottomCFrame.Position + Vector3.new(0, 3, 0)) then
			lastMsg = "วาปไปไม่ถึง"
			break
		end

		local ok, msg = carryF:InvokeServer({ Uid = egg.Uid })
		if ok == true then got = egg break end
		lastMsg = tostring(msg)

		-- ข้อความนี้มีสองสาเหตุ แยกให้ออกก่อนตัดสินใจ
		--   1. ยิงเร็วเกินไป เซิร์ฟยังไม่ทันรู้ตำแหน่งใหม่  -> รอแป๊บแล้วยิงซ้ำที่เดิม
		--   2. ยังไม่เคยเข้าเขตจริงๆ (เพิ่งเกิดใหม่)        -> ต้องไปเดินข้ามเส้น
		-- เหมาว่าเป็นข้อ 2 ตั้งแต่ครั้งแรกทำให้เสียเที่ยวเปล่าเกือบทุกรอบ
		if lastMsg:find("gameplay area") then
			if attempt == 1 then
				task.wait(0.2)   -- ให้โอกาสข้อ 1 ก่อน ยังยืนทับไข่อยู่
			else
				enteredZone = false
				move(warpHome)
				if not ensureZone() then return "เข้าโซนเกมเพลย์ไม่ได้" end
			end
		else
			-- ใบนี้โดนคนอื่นเก็บไปแล้ว เลือกใบใหม่
			local nextEgg, nextRate = findEgg(Config.Area)
			if not nextEgg then break end
			egg, rate = nextEgg, nextRate or 0
		end
	end

	-- กลับจุดยืนก่อนเสมอ ไม่ว่าเก็บได้หรือไม่ได้ ยืนค้างนอกเส้นคือโดนสัตว์รุม
	Hub.Phase = "วาปกลับ SAFE ZONE"
	move(warpHome)

	if not got then
		Stats.failed += 1
		return "เก็บไม่สำเร็จ: " .. tostring(lastMsg)
	end

	Stats.stolen += 1
	log(("เก็บได้: %s ($%s/s)"):format(got.AssetCategory or got.Uid, comma(eggRate(got))))

	-- ถือได้ทีละใบ ต้องเอาไปวางก่อนถึงจะเก็บใบต่อไปได้
	--
	-- รอบปกติทำแค่ "วางไข่" อย่างเดียว
	-- งานบ้านที่เหลือ (ฟัก อัปฐาน วางสัตว์ ขายตัวอ่อน) ยิงเซิร์ฟหลายครั้งต่อรอบ
	-- ทำทุกรอบคือกินเวลาเปล่า ไข่ไม่ได้ฟักเร็วขึ้นเพราะเราไปกดถี่ขึ้น
	-- ทำทุก TendEvery รอบก็พอ ระหว่างนั้นเอาเวลาไปเก็บไข่แทน
	warpRound = warpRound + 1
	local every = math.max(1, math.floor(tonumber(Config.TendEvery) or 5))

	if warpRound % every == 0 then
		Hub.Phase = "เข้าแปลงวางไข่ + จัดการฐาน"
		tendBase()
	else
		Hub.Phase = "เข้าแปลงวางไข่"
		placePendingEggs()
	end

	Hub.Phase = "วาปกลับกลาง SAFE ZONE"
	move(warpHome)

	Hub.Phase = "ยืนรอที่ SAFE ZONE"
	return nil
end

local function cycle()
	-- โหมดวาปใช้เส้นทางของตัวเอง สั้นกว่ามาก
	-- ถ้าปะตัวตรวจจับไม่สำเร็จ warpReady() เป็น false แล้วตกไปใช้เส้นทางเดิม
	if Config.MoveMode == "warp" then
		return warpCycle()
	end

	Stats.cycles += 1

	if not waitForRespawn() then return "ตายแล้วไม่เกิดใหม่" end

	local home = homePos()
	if not home then return "หาแปลงของเราไม่เจอ" end

	Hub.Phase = "จัดการฐาน"
	tendBase()

	-- อยู่ในช่วงรีเซ็ต = ห้ามออกจากฐานเด็ดขาด
	if not waitOutReset() then return "หยุดระหว่างรอรีเซ็ต" end

	-- คัดไข่ก่อนออกเดินทาง จะได้ไม่เสียเที่ยว
	local scout, scoutRate = findEgg(Config.Area)
	if not scout then return "ไม่มีไข่ว่างที่ " .. Config.Area end
	scoutRate = scoutRate or 0

	local worth, floorRate = worthGoing(scoutRate)
	if not worth then
		goIdle()
		Hub.Phase = "รอไข่ดีๆ"
		return ("รอไข่ดีกว่านี้ - ดีสุดในสนาม $%s/s ยังสู้ตัวอ่อนสุดในคอก ($%s/s) ไม่ได้")
			:format(comma(scoutRate), comma(floorRate))
	end

	-- เหลือเวลาไม่พอไปกลับ รอรอบหน้าดีกว่า โดนดีดกลางทางแน่
	local left = secondsToReset()
	if left and left < Config.TripReserve then
		goIdle()
		Hub.Phase = "รอรีเซ็ต"
		return ("อีก %ds จะรีเซ็ต - รอที่ฐานก่อน"):format(left)
	end

	Hub.Phase = "ออกเดินทาง"
	if not leaveBase() then return "ออกจากแปลงไม่สำเร็จ" end

	-- ต้องเดินข้ามเส้นจริงก่อนเสมอ ไม่งั้นเซิร์ฟตอบ "Enter the gameplay area first"
	if not enterGameplayZone() then return "เข้าโซนเกมเพลย์ไม่ได้" end

	-- เพิ่งข้ามเส้น อย่าเพิ่งอัดเต็ม ไต่ออกไปช้าๆ ก่อน
	Hub.Phase = "ออกตัวช้าๆ"
	warmupRun()

	log(("เป้าหมาย: %s [%s] $%s/s"):format(
		scout.AssetCategory, scout.AreaId, comma(scoutRate)))

	move(Vector3.new(scout.BottomCFrame.Position.X - 40, LANE_Y, LANE_Z))

	-- อุ่นแคชตำแหน่งแปลงไว้ก่อนลงมือเก็บ
	--
	-- ขาหนีต้องรู้ว่าจะบินกลับไปไหน ถ้าไปถามเซิร์ฟตอนนั้นจะหยุดรอ ~60ms
	-- ซึ่งเป็นช่วงที่ยืนนิ่งอยู่ข้างไข่พอดี ให้สัตว์ที่เฝ้าเข้ามาตีทัน
	pcall(baseCenter)

	Hub.Phase = "เก็บไข่"
	local got, lastMsg
	for _ = 1, 4 do
		if not Config.Running then return "หยุดกลางทาง" end
		local egg, rate = findEgg(Config.Area)
		if egg and not worthGoing(rate or 0) then
			lastMsg = "ฟองที่เหลือไม่คุ้ม เลิกรอบนี้"
			break
		end
		if not egg then
			lastMsg = "ไข่ถูกเก็บไปหมด"
			task.wait(1)
		else
			move(egg.BottomCFrame.Position + Vector3.new(0, 3, 0))
			local ok, msg = carryF:InvokeServer({ Uid = egg.Uid })
			if ok == true then got = egg break end
			lastMsg = tostring(msg)
			task.wait(0.5)
		end
	end

	if not got then
		Stats.failed += 1
		goIdle()
		return "เก็บไม่สำเร็จ: " .. tostring(lastMsg)
	end
	log(("เก็บได้: %s ($%s/s)"):format(got.AssetCategory or got.Uid, comma(eggRate(got))))

	Hub.Phase = "พากลับฐาน"
	move(Vector3.new(got.BottomCFrame.Position.X, LANE_Y, LANE_Z))   -- ออกจากรังไข่มาเข้าเลนก่อน

	-- ห้ามแวะพักที่ x = GAMEPLAY_LINE_X + 10 เด็ดขาด
	--
	-- จุดนั้นอยู่ "นอกเซฟโซน" (เส้นอยู่ที่ 552.8 จุดแวะเดิมอยู่ 562.8)
	-- พอหยุดตรงนั้นเพื่อเปลี่ยนขา สัตว์ที่เฝ้าไข่ซึ่งวิ่งไล่ตามหลังมาจะตามทัน
	-- แล้วฆ่าเราคาที่ ไข่หลุดมือทั้งที่เหลืออีกไม่กี่ studs ก็ถึงเซฟโซนแล้ว
	-- (วัดจริง: ตาย 6 ครั้งใน 90 วิ ทุกครั้งอยู่นอกเส้น)
	-- ขากลับจึงพุ่งเข้าฐานรวดเดียว ไม่แตะเบรกในเขตอันตราย
	enterBase()
	task.wait(2)

	if carriedByMe() then return "ยังถือไข่อยู่ ยังไม่เข้าฐาน" end

	local still
	for _, r in pairs(snapshot()) do
		if r.Uid == got.Uid then still = r.State end
	end
	if still == "Slot" then
		Stats.failed += 1
		return "โดนการ์ดแย่งคืน (สปีดไม่พอสำหรับด่านนี้)"
	end

	Stats.stolen += 1
	Hub.Phase = "จัดการฐาน"
	tendBase()
	goIdle()   -- จบงานในแปลงแล้วออกมายืนรอข้างนอก
	return nil, true
end

--==================================================================
-- UI
-- Yenixs library เป็นหลัก ถ้าโหลดไม่ได้ (เน็ต/ลิงก์ตาย) จะสลับไปใช้ UI สำรองในตัวอัตโนมัติ
--==================================================================
local UI_URL = "https://raw.githubusercontent.com/Yenixs/ToolScript/refs/heads/main/Utils.lua"

-- ไอคอนของปุ่มย่อหน้าต่าง
-- ฝังรูปมาในสคริปต์เลย (base64) แล้วเขียนลงไฟล์ + แปลงเป็น asset ด้วย getcustomasset
-- ไม่ต้องอัปโหลดขึ้น Roblox ให้ยุ่งยาก ถ้า executor ไม่รองรับจะกลับไปใช้ไอคอนดีฟอลต์
local DEFAULT_ICON = "rbxassetid://130669567657231"

local ICON_B64 = table.concat({
	"iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAMAAAD04JH5AAAAwFBMVEXaoGPfp5TvsJV4ZFZtWEri3Wjt07B4YE1/fzTWcoPPn2Xr",
	"tpCaiXfQoGbRomP2xaH34cmJblb71salmIv////z2Jr0xYipbGLxto5/Pz+8fT53X0y6o2pjSznTZ3z/f3//AAA2Jx+jhGLudhGH",
	"bFSidmw/Pz9ALya/vz/rw38AAADrvYP+7dHOnWTwlaXzxYr+89f0qa07KyPWpWr9/fD//wBENCssGxTouHz01612YVJ5YU4zIxzy",
	"un22lG2qqlU+dwIuAAAAQHRSTlMN+G4Q4wX+bAP/XZX+oe+g5+e2+wEKYwcgBASSCu3/AgH/pwNxqAT/BP8A/v79//3+d//8/wH/",
	"//7+99f/C+8DkpKYJwAACXBJREFUeNrtWwmTo7gONgmQbO50zr6me459bxfImiaBkIPk//+rlW0gHDJXZ+rVq2rVVE8SI+mzJEuy",
	"AWL8j4l8AfgC8AXg/wCAy6iB6Gp8JQDcILzghVzrgKjOVwjgyv8GBIh9WFWFUIevAIA2ByG93nC7ARr2ei/wtYr6enykaASExDTa",
	"bobwUyWn1uGTAtC4mE2C4FvvqTRq6/JJfp+/Gb20GE7+8CV0sHEvPhyAO38a5sXw2fSKbNCAD/3VfZLIKUHQhA/98cUYjjYbmSRi",
	"PEkANOEj6G+9xDxGib9c0uhJsrAb8SEASJsk40j5B0hREnMZ4gHVjI9geWx0k/NPTDdRW/JO4mTPaF6PrwQAMcg2NYuYIntuR8ZK",
	"W2jJ9KaRRSW+awUAVxJPJC0HJEVT6YlkrwWcFgv+9akKHykF4BpkI5ETS9oOg9a41Tcjov0WfCfbcr73cgCJUM7J4f6E/O6Dzizp",
	"1DS3LAhHEj7GuiG5ooABGMn0gyRQTin7lyfx83aL8o0EgJ/lAN5eomSGiGFaSoiBUKQm6OXCkMhCYKQ00B6ZIg8hFDrMKcQAbBED",
	"KLjZ5RgU1Ae9hgBqqkcgfApAA/U5CCGARi5QzCbqMxAqW8Ag7+EqUD6rPoWgTh4QNT1cBZ/Sf4MQVaRqiSiRBz6pPkaghKk4v01B",
	"asHTJvKB8nn9jJQ4DVQpRga5RqnwTvrNv80oE+c9gACI18HWvBdRX1qN0ZbMGPp31R8iAAO8u1UAuFcCTrinfoEAqUSSrvgnc4Jp",
	"3hkBUoik+4LA6FF6bwRDQ3MrAnAXwfje+qGctGDjWg3A1ejrpnl/BGsMAQJAc1vU/A1ElYVWZRV02xr9LQBMHXMCwRzwe/SDExZz",
	"rRSA9r6uqt/3RUdu+pWdUKEWXA2lEgBozw8Hi5N+qIoBiUOSO+KpZACfHnTLtgUA9v+BVjRBWVteyQC+eYi1WxEInfpNTEAaGMCn",
	"Vlq7gGAdmpiANDAAqp9B0BuYgGQMUCEHHXD13AilboBsdC0CsC4rAtTUrSKipV3UOt0VkXQzFBTyw5pn/pdbYGcf/JJdTLYmkXQE",
	"FHqA+tNXx/MGii3zwOzoed70Uiikv0h1xiQTAgVxRC/e+ew4zv58RI2wU7w9Gz+fVVrkw3RnmgTgagtZGfDBshfH+S+o35+9PYZg",
	"p5zP3ncx/lqQn8EHVxkAg6AhwLOurTicZrPjHhDk7a+cU+PS/JypiSQTAlSadT1uXn2326mgYbDL+h8ZR/Mz7RMZAA3phKKsaw/2",
	"Hihg8ne749nxJplUjI2j+TkTBKQ4Dd2yLhPveFz+bgZTnO0yBkDHkfxMzUAKwM3GoE/DaAsj4KYAVkI6AmTjufwsB+Aa62wMHuIQ",
	"Fxa+mdhxUgWhYBzyc1EqIkV58Jb1IwVhkLHJogCwcdummSisCADsn1MQLjMpAHTctqpYoNu9ZtIATfp4thfyWaIR7k4BKB5PxwHL",
	"RI/dVRpAm/9dmBL9lj0J5TvfRbhnEkHJOKtRN8FLg91g6KYBPHc67faLOIPGyr6tnp0knTMVqWycxsfJlA7bq07nuWOskgCOQCd1",
	"erlczPAo3EYzrSDvrNpWnXEIAzGz7eUyVU+n43HaETaIAHQ6nRP8rqowymBss32HfYzCTES7XXOcgtDpaQoK1KN6YgZPAeAg2mQY",
	"X6RO1ayRYw1ezsAl47YVShWT67VX+VXw2H2ExbHUQzNdplN1lm28jxDpnscKvrJD2hH5uG2BdQexexd80bWRashTsQgUy5pkm0/b",
	"GniwyvaeqvNCk6HMeJpTZ6UxCvAgWgEFxYh1foiVLWUwuEzwptAuGGfwopVI021puiEJwjXoS1pv24ZMK4aUP9LEZ50YxxrmMBO7",
	"WmlHlAAgzIvtQr59i7V/U9C9UpoVb4sTqbhtXNtRPQ69GAlA/TFRYgSI/jwrjU9qfhqSVDyPgoBGbn146Lda/Y/xA+pYgeDbHzoW",
	"LlnWOAjCO65YKm6351RsbUIZIOKDU+tjPLFxN2DmR1nZnsWk+tJYtduSVHxSO+FaZWFrj0MRIU1QN+Dmz7PaO53fVrz8eD6p8lR8",
	"DLPVDBZuRgiOwNKx6MuzwrKZhVkWao4sFYNpfomLXgHkn1kpH/ixQP6nhxzn6Xh6feWT+8F9jadiTkvKUvFselJzAFoPtlWBbKv/",
	"kQNwOl0U7t7FbdEh2/N29z+BuBVtWf2cmMoAcvr7fWBliRiakZfHkkMqthIhEdkPOTH5IGCJL5/57DHKiuxM0fuGvDOFWjDJGWCc",
	"0w+pfzCY5dcGxqojhwPoQSU3Ac2LASF2srrwXvg7VL+zCERbjoDp50cX6T1JPhWLJ1O4CUAeiEmG4cNNv70Li5/neK/OOew/k/jy",
	"rGxzoMc7Akkq5ovhL2YCn8b5jBHMIeF/Vvi9yc6GzYDzOt074rMzSF2SYWWdOVWCl2s36gXwVCy+sZIUzemB0SRdjWzY+3iD2RGa",
	"zwt9PYvPzj7Zh2VZuQfWccKRpeJTh+FYGbBgREG+9TvpGnA+O2fYgexVSjfR56OdL8YRK1uEcRUoTMWsOT91fly2tHCp6yro3HtT",
	"Vl424vPAKsoSB/9y+fUMeVhokKdihk89Yl1xthTD+hMnIPTAGjFrV5SaplDoRBXolKVi4aHOafo62xUaAVJQePzhWxCEdmFuBOM+",
	"p1RLU3EUo6s+3eolOfd2/HIoSc50S3u5mcrvmrW7j0/GYqybhV5Nbjhp2ZViR/xY46HWt+5qTIvk2ocqB+jiSgrz1+o+VfvWvo5p",
	"wcl49jhLl18pu2dZ8lzxW3slRYCdy0uvLNRf9IjsHPaKFHODbeMnkOiV7GCySAspfki6BQgO6UoHhVVyoIxeScdBwfzLnq4H7Hy/",
	"eogya/E9Oj93JYUWSHv7xOP9hDWJlN2hPHBi3VLJDa3ElZSZ3/3cCw6uy4zApHGqdkNVXEnZ9I31p9+wAAnLcf3b2cDBpl/6NH6l",
	"VzzqQ4CrW4FR/CB8jZdcrnMBgdaYPagP5vd7y0ZAMCtgYLuK8bKq+hqv+bBbXUGrT4tAiEOg8dKorL7We0ZrtrFftMagSE+cqMaq",
	"2cZn3GIPXLtB9Tdyar3o5PKrNa217N+0hs8U0/6yteYbv2BdR2bdN63mJIgf624tRefdWi6DdbjpJPOa70Q1eNXLdckCe29nEczn",
	"9aU1fdeMPdRPFpqgBXGb6P562+4LwBeALwBfAL4AcPoXPQNkSCHK7NkAAAAASUVORK5CYII=",
})

local function buildIcon()
	if type(writefile) ~= "function" or type(getcustomasset) ~= "function" then
		return DEFAULT_ICON
	end

	local decode
	if crypt and type(crypt.base64decode) == "function" then
		decode = crypt.base64decode
	elseif crypt and crypt.base64 and type(crypt.base64.decode) == "function" then
		decode = crypt.base64.decode
	elseif type(base64_decode) == "function" then
		decode = base64_decode
	elseif base64 and type(base64.decode) == "function" then
		decode = base64.decode
	end
	if not decode then return DEFAULT_ICON end

	local ok, asset = pcall(function()
		local path = "StealAnEgg_Icon.png"
		writefile(path, decode(ICON_B64))
		return getcustomasset(path)
	end)
	if ok and type(asset) == "string" and asset ~= "" then return asset end
	return DEFAULT_ICON
end

local HUB_ICON = buildIcon()

local setStatus, setBoard, setLogBox, setPets, destroyUI, toggleUI
local setRunToggle   -- ใช้สั่งให้สวิตช์ "เริ่มฟาร์ม" ขยับตามสถานะจริง

local ICONS = {}
local Lib, Win, UILib

local function tryLoadLibrary()
	local ok, mod = pcall(function()
		return loadstring(game:HttpGet(UI_URL))()
	end)
	if not (ok and type(mod) == "table" and mod.UILibrary) then return nil end

	local built = pcall(function()
		UILib = mod.UILibrary
		Lib = UILib.New({
			WindowPill = true,
			Theme = UILib.Themes.Dark,
			Accent = UILib.Accents.Yellow,
		})
		Win = Lib:Window({
			Title = "Hamsterdiwa",
			Subtitle = "Steal An Egg · เก็บไข่ · วางแปลง · ฟัก · อัปฐาน · ขายตัวล้น",
			Size = UserInputService.TouchEnabled and UDim2.fromOffset(560, 330) or UDim2.fromOffset(840, 520),
			UIBlur = false,
			Dropshadow = false,
		})
	end)
	if not (built and Win) then return nil end

	pcall(function()
		if mod.MinimizeButton then
			mod.MinimizeButton(HUB_ICON, function()
				Win.Minimized = not Win.Minimized
			end)
		end
	end)

	local S = UILib.Symbols or {}
	ICONS = {
		main   = S.hare,
		speed  = S.figureRun,
		base   = S.house,
		eggs   = S.shippingbox,
		misc   = S.gear,
	}
	return mod
end

--------------------------------------------------------------------
-- อะแดปเตอร์ของไลบรารี
--------------------------------------------------------------------
local function makeLibAdapter()
	local page
	local A = {}

	function A.tab(title, iconKey, selected)
		local sec = Win:Section({ Disclosure = false, Title = title })
		local tab = sec:Tab({ Selected = selected or false, Title = title, Icon = ICONS[iconKey] })
		page = tab:PageSection({ Title = title, Subtitle = "" }):Form()
	end

	local function row(title, subtitle)
		local r = page:Row({ SearchIndex = title })
		r:Left():TitleStack({ Title = title, Subtitle = subtitle or "" })
		return r
	end

	-- คืนฟังก์ชันสำหรับสั่งเปลี่ยนหน้าตาสวิตช์จากโค้ด
	-- จำเป็นตอน AutoStart เพราะมันเปิดฟาร์มเองหลัง UI ถูกสร้างไปแล้ว
	-- ถ้าไม่มีตัวนี้ สวิตช์จะค้างเป็นปิดทั้งที่บอทวิ่งอยู่
	function A.toggle(title, subtitle, default, cb)
		local tog = row(title, subtitle):Right():Toggle({
			Value = default and true or false,
			ValueChanged = function(_, v) cb(v and true or false) markDirty() end,
		})
		return function(v) pcall(function() tog.Value = v and true or false end) end
	end

	function A.input(title, subtitle, default, cb)
		row(title, subtitle):Right():TextField({
			Value = tostring(default),
			Placeholder = "...",
			ValueChanged = function(_, v)
				local n = tonumber((tostring(v):gsub("[^%d%.]", "")))
				if n then cb(n) markDirty() end
			end,
		})
	end

	function A.button(title, subtitle, label, cb)
		local btn
		btn = row(title, subtitle):Right():Button({
			Label = label,
			State = "Primary",
			Pushed = function()
				local res = cb()
				if type(res) == "string" then
					pcall(function() btn.Label = res end)
					task.delay(2.5, function() pcall(function() btn.Label = label end) end)
				end
			end,
		})
		return btn
	end

	-- ปุ่มวนค่า ใช้แทน dropdown เพราะ API ของ PopUpButton ยังไม่ยืนยัน
	function A.choice(title, subtitle, options, current, cb)
		local index = 1
		for i, v in ipairs(options) do if v == current then index = i end end
		local btn
		btn = row(title, subtitle):Right():Button({
			Label = tostring(options[index]),
			State = "Secondary",
			Pushed = function()
				index = index % #options + 1
				pcall(function() btn.Label = tostring(options[index]) end)
				cb(options[index])
				markDirty()
			end,
		})
	end

	function A.label(title, subtitle)
		local lbl = row(title, subtitle):Right():Label({ Text = "..." })
		return function(text) pcall(function() lbl.Text = text end) end
	end

	return A
end

--------------------------------------------------------------------
-- UI สำรองในตัว (ใช้ตอนโหลดไลบรารีไม่ได้)
--------------------------------------------------------------------
local function makeFallbackAdapter()
	local BG      = Color3.fromRGB(20, 21, 28)
	local BG2     = Color3.fromRGB(29, 31, 42)
	local BG3     = Color3.fromRGB(40, 43, 58)
	local TXT     = Color3.fromRGB(236, 239, 245)
	local TXT_DIM = Color3.fromRGB(150, 156, 172)
	local ACCENT  = Color3.fromRGB(250, 204, 21)
	local GREEN   = Color3.fromRGB(74, 222, 128)

	local function corner(p, r)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, r or 8)
		c.Parent = p
	end

	local ScreenGui = Instance.new("ScreenGui")
	ScreenGui.Name = "EggFarmUI_" .. tostring(math.random(10000, 99999))
	ScreenGui.ResetOnSpawn = false
	ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	ScreenGui.IgnoreGuiInset = true

	local parented = false
	if gethui then parented = pcall(function() ScreenGui.Parent = gethui() end) end
	if not parented then
		if not pcall(function() ScreenGui.Parent = game:GetService("CoreGui") end) then
			ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
		end
	end

	local Main = Instance.new("Frame")
	Main.Size = UDim2.fromOffset(340, 500)
	Main.Position = UDim2.new(0, 24, 0.5, -250)
	Main.BackgroundColor3 = BG
	Main.BorderSizePixel = 0
	Main.Active = true
	Main.Draggable = true
	Main.Parent = ScreenGui
	corner(Main, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = ACCENT
	stroke.Thickness = 1.5
	stroke.Parent = Main

	local Header = Instance.new("TextLabel")
	Header.Size = UDim2.new(1, -20, 0, 32)
	Header.Position = UDim2.fromOffset(12, 6)
	Header.BackgroundTransparency = 1
	Header.Font = Enum.Font.GothamBold
	Header.Text = "HAMSTERDIWA"
	Header.TextSize = 13
	Header.TextColor3 = ACCENT
	Header.TextXAlignment = Enum.TextXAlignment.Left
	Header.Parent = Main

	local Sub = Instance.new("TextLabel")
	Sub.Size = UDim2.new(1, -20, 0, 14)
	Sub.Position = UDim2.fromOffset(12, 26)
	Sub.BackgroundTransparency = 1
	Sub.Font = Enum.Font.Gotham
	Sub.Text = "Steal An Egg — Auto Farm"
	Sub.TextSize = 10
	Sub.TextColor3 = TXT_DIM
	Sub.TextXAlignment = Enum.TextXAlignment.Left
	Sub.Parent = Main

	local Body = Instance.new("ScrollingFrame")
	Body.Size = UDim2.new(1, -16, 1, -56)
	Body.Position = UDim2.fromOffset(8, 48)
	Body.BackgroundTransparency = 1
	Body.BorderSizePixel = 0
	Body.ScrollBarThickness = 3
	Body.ScrollBarImageColor3 = ACCENT
	Body.CanvasSize = UDim2.new()
	Body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	Body.Parent = Main
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = Body

	local order = 0
	local function nextOrder() order += 1 return order end

	local A = {}

	function A.tab(title)
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -6, 0, 22)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.Text = title
		label.TextSize = 11
		label.TextColor3 = ACCENT
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.LayoutOrder = nextOrder()
		label.Parent = Body
	end

	function A.toggle(title, subtitle, default, cb)
		local button = Instance.new("TextButton")
		button.Size = UDim2.new(1, -6, 0, 30)
		button.BackgroundColor3 = BG2
		button.AutoButtonColor = false
		button.Text = ""
		button.LayoutOrder = nextOrder()
		button.Parent = Body
		corner(button, 7)

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -60, 1, 0)
		label.Position = UDim2.fromOffset(10, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Gotham
		label.Text = title
		label.TextSize = 12
		label.TextColor3 = TXT
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Parent = button

		local pill = Instance.new("Frame")
		pill.Size = UDim2.fromOffset(38, 18)
		pill.Position = UDim2.new(1, -48, 0.5, -9)
		pill.BackgroundColor3 = default and GREEN or BG3
		pill.BorderSizePixel = 0
		pill.Parent = button
		corner(pill, 9)

		local knob = Instance.new("Frame")
		knob.Size = UDim2.fromOffset(14, 14)
		knob.Position = default and UDim2.fromOffset(22, 2) or UDim2.fromOffset(2, 2)
		knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		knob.BorderSizePixel = 0
		knob.Parent = pill
		corner(knob, 7)

		local state = default
		local function paint()
			TweenService:Create(pill, TweenInfo.new(0.15), { BackgroundColor3 = state and GREEN or BG3 }):Play()
			TweenService:Create(knob, TweenInfo.new(0.15),
				{ Position = state and UDim2.fromOffset(22, 2) or UDim2.fromOffset(2, 2) }):Play()
		end

		button.MouseButton1Click:Connect(function()
			state = not state
			paint()
			cb(state)
			markDirty()
		end)

		return function(v)
			state = v and true or false
			paint()
		end
	end

	function A.input(title, subtitle, default, cb)
		local holder = Instance.new("Frame")
		holder.Size = UDim2.new(1, -6, 0, 30)
		holder.BackgroundColor3 = BG2
		holder.BorderSizePixel = 0
		holder.LayoutOrder = nextOrder()
		holder.Parent = Body
		corner(holder, 7)

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -110, 1, 0)
		label.Position = UDim2.fromOffset(10, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Gotham
		label.Text = title
		label.TextSize = 12
		label.TextColor3 = TXT
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Parent = holder

		local box = Instance.new("TextBox")
		box.Size = UDim2.fromOffset(92, 22)
		box.Position = UDim2.new(1, -100, 0.5, -11)
		box.BackgroundColor3 = BG3
		box.BorderSizePixel = 0
		box.Font = Enum.Font.GothamBold
		box.TextSize = 11
		box.TextColor3 = TXT
		box.Text = tostring(default)
		box.ClearTextOnFocus = false
		box.Parent = holder
		corner(box, 5)

		box.FocusLost:Connect(function()
			local n = tonumber((box.Text:gsub("[^%d%.]", "")))
			if n then cb(n) markDirty() box.Text = tostring(n) else box.Text = tostring(default) end
		end)
	end

	function A.button(title, subtitle, labelText, cb)
		local button = Instance.new("TextButton")
		button.Size = UDim2.new(1, -6, 0, 30)
		button.BackgroundColor3 = Color3.fromRGB(120, 96, 20)
		button.AutoButtonColor = true
		button.Font = Enum.Font.GothamBold
		button.Text = labelText
		button.TextSize = 12
		button.TextColor3 = TXT
		button.LayoutOrder = nextOrder()
		button.Parent = Body
		corner(button, 7)
		button.MouseButton1Click:Connect(function()
			local res = cb()
			if type(res) == "string" then
				button.Text = res
				task.delay(2.5, function()
					if button and button.Parent then button.Text = labelText end
				end)
			end
		end)
	end

	function A.choice(title, subtitle, options, current, cb)
		local index = 1
		for i, v in ipairs(options) do if v == current then index = i end end

		local button = Instance.new("TextButton")
		button.Size = UDim2.new(1, -6, 0, 30)
		button.BackgroundColor3 = BG2
		button.AutoButtonColor = false
		button.Text = ""
		button.LayoutOrder = nextOrder()
		button.Parent = Body
		corner(button, 7)

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -130, 1, 0)
		label.Position = UDim2.fromOffset(10, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Gotham
		label.Text = title
		label.TextSize = 12
		label.TextColor3 = TXT
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Parent = button

		local value = Instance.new("TextLabel")
		value.Size = UDim2.fromOffset(112, 22)
		value.Position = UDim2.new(1, -120, 0.5, -11)
		value.BackgroundColor3 = BG3
		value.BorderSizePixel = 0
		value.Font = Enum.Font.GothamBold
		value.Text = tostring(options[index]) .. "  >"
		value.TextSize = 11
		value.TextColor3 = ACCENT
		value.Parent = button
		corner(value, 5)

		button.MouseButton1Click:Connect(function()
			index = index % #options + 1
			value.Text = tostring(options[index]) .. "  >"
			cb(options[index])
			markDirty()
		end)
	end

	function A.label(title, subtitle)
		local head = Instance.new("TextLabel")
		head.Size = UDim2.new(1, -6, 0, 16)
		head.BackgroundTransparency = 1
		head.Font = Enum.Font.GothamMedium
		head.Text = title
		head.TextSize = 10
		head.TextColor3 = TXT_DIM
		head.TextXAlignment = Enum.TextXAlignment.Left
		head.LayoutOrder = nextOrder()
		head.Parent = Body

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, -6, 0, 0)
		lbl.AutomaticSize = Enum.AutomaticSize.Y
		lbl.BackgroundColor3 = BG2
		lbl.BorderSizePixel = 0
		lbl.Font = Enum.Font.Code
		lbl.TextSize = 10
		lbl.TextColor3 = TXT_DIM
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.TextYAlignment = Enum.TextYAlignment.Top
		lbl.TextWrapped = true
		lbl.Text = "..."
		lbl.LayoutOrder = nextOrder()
		lbl.Parent = Body
		corner(lbl, 7)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 8)
		pad.PaddingRight = UDim.new(0, 8)
		pad.PaddingTop = UDim.new(0, 6)
		pad.PaddingBottom = UDim.new(0, 6)
		pad.Parent = lbl

		return function(text) lbl.Text = text end
	end

	A.__destroy = function() pcall(function() ScreenGui:Destroy() end) end
	A.__toggle = function() Main.Visible = not Main.Visible end
	return A
end

--------------------------------------------------------------------
-- ผังหน้าจอ เขียนครั้งเดียว ใช้ได้กับทั้งสอง UI
--------------------------------------------------------------------
local function buildUI(A)
	A.tab("หลัก", "main", true)
	setRunToggle = A.toggle("เริ่มฟาร์ม", "เก็บไข่ -> กลับฐาน -> วาง -> ฟัก -> ขายตัวล้น", Config.Running, function(v)
		Config.Running = v
		if v then
			log(("เริ่ม | %s | %d studs/s"):format(Config.Area, math.floor(Config.Step / Config.Gap)))
		else
			log("หยุดแล้ว")
			setNoclip(false)
			-- กดหยุดตอนกำลังบินอยู่ ต้องพาลงพื้นก่อน ห้ามดับพื้นเสกทิ้งกลางอากาศ
		end
	end)
	A.choice("ด่าน", "ALL = คัดไข่ $/s สูงสุดจากทุกด่าน", AREAS, Config.Area, function(v)
		Config.Area = v
		log("เปลี่ยนด่านเป็น " .. v)
	end)
	A.toggle("เริ่มฟาร์มอัตโนมัติตอนโหลด", "เปิดแล้วไม่ต้องมากดเริ่มเอง", Config.AutoStart, function(v)
		Config.AutoStart = v
	end)
	setStatus = A.label("สถานะ", "อัปเดตทุกครึ่งวินาที")
	setLogBox = A.label("ล็อก", "6 บรรทัดล่าสุด")

	A.tab("ความเร็ว", "speed")

	-- พรีเซ็ตสำเร็จรูป  กดแล้วตั้งค่าให้ครบชุด ไม่ต้องไล่ปรับเอง
	-- ต้องรันสคริปต์ใหม่ถ้าอยากให้ตัวเลขในช่องอัปเดตตาม (ค่าจริงเปลี่ยนทันที)
	local PRESETS = {
		{ name = "เร็วสุด",   mode = "step",  gap = 0.10, cam = true,  desc = "550 st/s · ภาพนิ่งด้วยกล้องนิ่ม" },
		{ name = "สมดุล",    mode = "step",  gap = 0.15, cam = true,  desc = "366 st/s · เสี่ยงโดนดึงน้อยลง" },
		{ name = "ปลอดภัย",  mode = "step",  gap = 0.25, cam = true,  desc = "220 st/s · แทบไม่โดนดึง" },
		{ name = "ภาพลื่น",   mode = "tween", gap = 0.55, cam = false, desc = "100 st/s · ลากต่อเนื่องจริง ช้าลงมาก" },
	}
	local presetNames = {}
	for i, p in ipairs(PRESETS) do presetNames[i] = p.name end

	A.choice("พรีเซ็ต", "กดวนเพื่อเลือก แล้วค่าจะเปลี่ยนทันที", presetNames, PRESETS[1].name, function(v)
		for _, p in ipairs(PRESETS) do
			if p.name == v then
				Config.MoveMode = p.mode
				Config.Gap = p.gap
				Config.SmoothCam = p.cam
				if p.cam then startSmoothCam() else stopSmoothCam() end
				log(("พรีเซ็ต %s: %s = %d studs/s"):format(p.name, p.mode, math.floor(Config.Step / Config.Gap)))
			end
		end
	end)

	-- ต้องมี warp ให้เลือกด้วย
	--
	-- รายการเดิมมีแค่ step/fly/tween ทั้งที่โหมดหลักที่ใช้จริงคือ warp
	-- ใครเผลอกดปุ่มนี้ครั้งเดียวจะหลุดออกจาก warp แล้วกลับเข้าไม่ได้อีกเลย
	-- แล้วค่านั้นถูกบันทึกลงไฟล์ ทำให้ติดอยู่กับโหมดผิดข้ามการรันครั้งถัดไป
	-- (เจอจริง: เครื่องผู้ใช้ตั้งเป็น step อยู่ เลยไม่วาปเลยสักครั้ง)
	A.choice("โหมดเคลื่อนที่", "warp = วาปตรง เร็วสุด · auto = เลือกให้เอง · step/tween = เดิน",
		{ "warp", "auto", "step", "tween" }, Config.MoveMode, function(v)
			Config.MoveMode = v
			log("โหมดเคลื่อนที่: " .. v)
		end)

	A.input("ก้าวละกี่ studs", "เพดานที่วัดได้ = 60 เกินนี้โดนลากกลับ", Config.Step, function(v)
		Config.Step = math.clamp(math.floor(v), 5, 120)
	end)
	A.input("พักกี่วินาที", "step: ต่ำสุด 0.06 · tween: 0.55 ขึ้นไปถึงจะรอด", Config.Gap, function(v)
		Config.Gap = math.clamp(v, 0.02, 1.2)
	end)
	A.input("กันเวลาก่อนรีเซ็ต (วิ)", "เหลือน้อยกว่านี้ = ไม่ออกไปไหน", Config.TripReserve, function(v)
		Config.TripReserve = math.clamp(math.floor(v), 0, 300)
	end)
	A.input("พักที่ SAFE ZONE ก่อนเข้าแปลง (วิ)", "ขากลับ ตรึงให้นิ่งก่อน กันสะดุด", Config.SafeZonePause, function(v)
		Config.SafeZonePause = math.clamp(v, 0, 10)
	end)
	A.input("ออกตัวช้าๆ กี่ก้าว", "ขาออก หลังข้ามเส้นแล้วค่อยๆ ไต่ก่อนเร่ง", Config.WarmupSteps, function(v)
		Config.WarmupSteps = math.clamp(math.floor(v), 0, 40)
	end)
	A.input("ช่วงออกตัว ช้าลงกี่เท่า", "2.5 = เหลือราว 220 studs/s · ยิ่งมากยิ่งช้า", Config.WarmupGapMul, function(v)
		Config.WarmupGapMul = math.clamp(v, 1, 8)
	end)
	-- ปุ่ม Noclip ถูกถอดออก อย่าใส่กลับ
	--
	-- บรรทัด 680 บังคับ Config.Noclip = false เพื่อไม่ให้ลูกค้าโดนเตะ
	-- แต่ปุ่มนี้เขียน Config.Noclip = v ทับทีหลังได้ตรงๆ ไม่มีตัวกั้น
	-- กดครั้งเดียว = CanCollide = false ซึ่ง replicate ขึ้นเซิร์ฟ = ลายเซ็นโกงที่เช็คง่ายที่สุด
	--
	-- และค่าเริ่มต้นของ ShowUI ในไฟล์นี้คือ true (บรรทัด 351 กับในเทมเพลต 556)
	-- ลูกค้าที่ใช้ loader รุ่นเก่าซึ่งยังไม่มีคีย์ ShowUI จะเห็น UI แล้วกดปุ่มนี้ได้
	-- = คำอธิบายที่ตรงที่สุดของอาการ "บางคนโดนเตะ บางคนไม่โดน" ทั้งที่รันบิลด์เดียวกัน
	--
	-- สวิตช์ที่โกหกแย่กว่าไม่มีสวิตช์ ถอดทิ้งดีกว่าปล่อยให้กดแล้วหลุด
	A.toggle("กล้องนิ่ม", "แก้ภาพกระตุกตอนวาป ไม่แตะตัวละคร", Config.SmoothCam, function(v)
		Config.SmoothCam = v
		if v then startSmoothCam() else stopSmoothCam() end
	end)
	A.input("ความนุ่มของกล้อง", "สูง = ตามไว · ต่ำ = นุ่มขึ้น (แนะนำ 6-10)", Config.CamSmooth, function(v)
		Config.CamSmooth = math.clamp(v, 1, 30)
	end)
	A.tab("ฐาน", "base")
	A.toggle("ฟักไข่ + ปล่อยสัตว์ลงคอก", "ยิง RequestHatchEgg แล้วตามด้วย Equip Best", Config.AutoHatch, function(v)
		Config.AutoHatch = v
	end)
	A.toggle("อัปเกรดฐานเมื่อเงินถึง", "ใช้เงินในเกม ไม่ใช่ Robux", Config.AutoUpgrade, function(v)
		Config.AutoUpgrade = v
	end)
	A.toggle("ขายสัตว์ตัวที่ล้นคอก", "ขายแล้วเอาคืนไม่ได้", Config.AutoSell, function(v)
		Config.AutoSell = v
	end)
	A.input("เก็บสำรองเกินช่องกี่ตัว", "0 = ขายทุกตัวที่ล้นช่อง", Config.KeepExtra, function(v)
		Config.KeepExtra = math.clamp(math.floor(v), 0, 200)
	end)
	A.input("เก็บตัวที่ $/s ตั้งแต่", "0 = ไม่สนราคา ขายตามอันดับล้วนๆ", Config.KeepAbove, function(v)
		Config.KeepAbove = math.max(0, math.floor(v))
	end)
	setPets = A.label("สัตว์ในกระเป๋า", "ตัวที่จะโดนขายรอบหน้า")
	A.button("ขายตัวที่ล้นตอนนี้", "ไม่แตะตัวที่อยู่ในคอก · ขายแล้วเอาคืนไม่ได้", "ขายเลย", function()
		local list = sellCandidates()
		if #list == 0 then return "ไม่มีตัวที่เข้าข่ายขาย" end
		local n = autoSellWeak(true)
		return n > 0 and ("ขายไป " .. n .. " ตัว") or "ขายไม่สำเร็จ"
	end)
	setBoard = A.label("ไข่ดีที่สุดตอนนี้", "อัปเดตทุก 5 วินาที")

	A.tab("อื่นๆ", "misc")
	A.toggle("ไม่ไปเก็บไข่ที่กากกว่าในคอก", "เทียบกับตัวอ่อนสุดที่ยังได้ลงสนาม", Config.SkipWeak, function(v)
		Config.SkipWeak = v
	end)
	A.toggle("เร่งเฟรม", "ตัดเงา พื้นผิว อนุภาค · ลดคุณภาพภาพ", Config.FpsBoost, function(v)
		Config.FpsBoost = v
		if v then task.spawn(function()
			log(("เร่งเฟรม: ตัดของออก %d ชิ้น"):format(Hub.fpsBoost()))
		end) end
	end)
	A.toggle("จอขาว (เฟรมสูงสุด)", "ปิดการวาดภาพ 3 มิติ · เปิดเมื่อไม่ได้ดูจอ", Config.BlankScreen, function(v)
		Config.BlankScreen = v
		task.spawn(function() Hub.setBlankScreen(v) end)
	end)
	A.toggle("ตั้งค่าประหยัดเครื่อง", "ซ่อนสัตว์คนอื่น · ปิดวิดีโอ · ปิดเพลง/เสียง", Config.PerfMode, function(v)
		Config.PerfMode = v
		if v then task.spawn(applyPerfSettings) end
	end)
	A.button("ตั้งค่าประหยัดเครื่องตอนนี้", "ใช้ตัวตั้งค่าของเกมเอง ไม่ไล่ปิดทั้งแมพ", "ตั้งเลย", function()
		local n = applyPerfSettings()
		return n > 0 and ("ตั้งไป " .. n .. " อย่าง") or "ตั้งไว้ครบแล้ว"
	end)
	A.toggle("Anti-AFK", "", Config.AntiAFK, function(v) Config.AntiAFK = v end)
	A.toggle("บันทึกค่าอัตโนมัติ", "ปรับอะไรแล้วเซฟให้เลย", Config.AutoSaveConfig, function(v)
		Config.AutoSaveConfig = v
		if v then saveConfig() end
	end)
	A.button("บันทึกค่าตอนนี้", "เขียนลงไฟล์ " .. CONFIG_FILE, "บันทึก", function()
		return saveConfig() and "บันทึกแล้ว" or "executor ไม่รองรับ writefile"
	end)
	A.button("สร้างไฟล์คอนฟิกใหม่", "เขียนทับ " .. USER_CONFIG_FILE .. " ด้วยค่าเริ่มต้น", "สร้าง", function()
		return writeUserConfig() and ("เขียน " .. USER_CONFIG_FILE .. " แล้ว") or "executor ไม่รองรับ writefile"
	end)
	A.button("รีเซ็ตกลับค่าเริ่มต้น", "ต้องรันสคริปต์ใหม่เพื่อให้ UI อัปเดตตาม", "รีเซ็ต", function()
		resetConfig()
		return "รีเซ็ตแล้ว รันใหม่อีกที"
	end)
	A.button("หยุดและปิดฮับ", "ปิด UI + หยุดทุกลูป", "ปิดฮับ", function()
		task.spawn(function() Hub.Destroy() end)
		return "กำลังปิด..."
	end)
end

--------------------------------------------------------------------
-- สร้างจริง
--------------------------------------------------------------------
local usingLibrary = false

-- ไม่ต้องสร้าง UI เลย
--
-- ใช้ตอนสั่งงานผ่านคอนฟิกล้วนๆ (_G.HamsterConfig + AutoStart)
-- ประหยัดทั้งเฟรมและหน่วยความจำ เหมาะกับเปิดหลายจอทิ้งไว้
-- ทุกตัวตั้งค่า UI จะเป็นฟังก์ชันเปล่าที่ท้ายไฟล์อยู่แล้ว ลูปทุกตัวจึงทำงานปกติ
if not Config.ShowUI then
	log("ปิด UI ไว้ (ShowUI = false) สั่งงานผ่านคอนฟิกอย่างเดียว")

elseif tryLoadLibrary() then
	local A = makeLibAdapter()
	if pcall(buildUI, A) then
		usingLibrary = true
		destroyUI = function() pcall(function() if Win and Win.Destroy then Win:Destroy() end end) end
		toggleUI = function() pcall(function() Win.Minimized = not Win.Minimized end) end
	else
		pcall(function() if Win and Win.Destroy then Win:Destroy() end end)
		setStatus, setBoard, setLogBox, setPets = nil, nil, nil, nil
	end
end

if Config.ShowUI and not usingLibrary then
	local A = makeFallbackAdapter()
	buildUI(A)
	destroyUI = A.__destroy
	toggleUI = A.__toggle
end

if not setStatus then setStatus = function() end end
if not setBoard then setBoard = function() end end
if not setLogBox then setLogBox = function() end end
if not setPets then setPets = function() end end
if not destroyUI then destroyUI = function() end end
if not toggleUI then toggleUI = function() end end

Hub.UsingLibrary = usingLibrary

--==================================================================
-- ข้อความสถานะลอยกลางจอ
--
-- ไม่ใช่หน้าต่าง UI  มี TextLabel ใบเดียว พื้นหลังโปร่ง ไม่มีกรอบ ไม่มีปุ่ม
-- TextLabel ไม่กินคลิก (ต่างจากพวก TextButton) เลยกดของในเกมทะลุผ่านได้ปกติ
--
-- ดึงข้อมูลจากลูปสถานะกับลูปกระดานไข่ที่มีอยู่แล้ว ไม่ยิงรีโมทเพิ่มแม้แต่ครั้งเดียว
--==================================================================
local overlayLabel
local overlayHead, overlayBoard = "", ""

local function renderOverlay()
	if not overlayLabel or not overlayLabel.Parent then return end
	if overlayBoard == "" then
		overlayLabel.Text = overlayHead
	else
		overlayLabel.Text = overlayHead .. "\n" .. overlayBoard
	end
end

local function buildOverlay()
	if not Config.StatusText then return end

	local gui = Instance.new("ScreenGui")
	-- ชื่อต้องมีคำว่า EggFarm เพื่อให้ตัวเก็บกวาดตอนรันทับหาเจอแล้วลบทิ้ง
	gui.Name = "EggFarmStatusText_" .. tostring(math.random(10000, 99999))
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 999

	-- ต้องเช็คว่า "ติดพ่อจริงไหม" ห้ามเชื่อค่าที่ pcall คืนมา
	--
	-- executor บางตัวมี gethui อยู่แต่คืน nil  การเขียน gui.Parent = nil ไม่ error
	-- pcall เลยคืน true ทั้งที่ไม่ได้ติดอะไรเลย = ป้ายลอยเคว้ง มองไม่เห็นตลอดกาล
	-- แล้วยังข้ามทางสำรอง CoreGui/PlayerGui ไปด้วย เพราะนึกว่าสำเร็จแล้ว
	if gethui then pcall(function() gui.Parent = gethui() end) end
	if not gui.Parent then
		pcall(function() gui.Parent = game:GetService("CoreGui") end)
	end
	if not gui.Parent then
		gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	end

	-- จดไว้ทันทีที่ติดพ่อ ก่อนจะไปตั้งค่าอย่างอื่น
	-- ถ้าบรรทัดถัดๆ ไปพัง Hub.Destroy() จะยังตามลบป้ายใบนี้เจอ ไม่ค้างในเกม
	Hub.OverlayGui = gui

	local lb = Instance.new("TextLabel")
	lb.Name = "Status"
	lb.Active = false               -- ย้ำอีกชั้น ห้ามกินอินพุต
	lb.BackgroundTransparency = 1
	lb.BorderSizePixel = 0
	lb.AnchorPoint = Vector2.new(0.5, 0.5)
	lb.Position = UDim2.fromScale(0.5,
		math.clamp(tonumber(Config.StatusTextY) or 0.5, 0.05, 0.95))
	lb.Size = UDim2.fromScale(0.9, 0.4)
	lb.Font = Enum.Font.GothamBold
	lb.TextSize = math.clamp(tonumber(Config.StatusTextSize) or 18, 10, 48)
	lb.TextColor3 = Color3.fromRGB(255, 255, 255)

	-- สนามเป็นสีเขียวสว่างจ้า ตัวหนังสือขาวล้วนอ่านไม่ออก ต้องมีขอบดำเสมอ
	lb.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	lb.TextStrokeTransparency = 0

	lb.TextXAlignment = Enum.TextXAlignment.Center
	lb.TextYAlignment = Enum.TextYAlignment.Center
	lb.TextWrapped = false
	lb.RichText = false
	lb.Text = ""
	lb.Parent = gui

	overlayLabel = lb
end

pcall(buildOverlay)

-- ปุ่มลัด: RightControl ซ่อน/โชว์
local inputConn = UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not alive() then return end
	if input.KeyCode == Enum.KeyCode.RightControl then toggleUI() end
end)

--==================================================================
-- LOOPS
--==================================================================

-- ลูปฟาร์มหลัก
task.spawn(function()
	local lastLine
	while alive() do
		if Config.Running then
			local ok, err, success = pcall(cycle)
			if not ok then
				log("error:", err)
			elseif err then
				-- ตอนยืนรอไข่ดีๆ ข้อความจะซ้ำทุก 2 วิ ไม่ต้องถมล็อก
				if err ~= lastLine then log(err) end
				lastLine = err
			elseif success then
				log("✓ ส่งไข่เข้าฐานแล้ว")
				lastLine = nil
			end
			-- โหมดวาปทำงานจบรอบใน ~2 วิ ถ้ายังคั่น 2 วิเท่าเดิมคือเสียเวลาไปครึ่งหนึ่ง
			task.wait(Config.MoveMode == "warp"
				and math.min(0.3, tonumber(Config.LoopDelay) or 2)
				or Config.LoopDelay)
		else
			Hub.Phase = "พัก"
			task.wait(0.5)
		end
	end
end)

-- กระดานไข่ดีสุด
task.spawn(function()
	while alive() do
		pcall(function()
			local ranked = rankedEggs(Config.Area)
			local rows = {}
			for i = 1, 3 do
				local e = ranked[i]
				rows[#rows + 1] = e
					and ("%d. %s [%s] $%s/s"):format(i, e.rec.AssetCategory, e.rec.AreaId, comma(e.rate))
					or ("%d. -"):format(i)
			end
			setBoard(table.concat(rows, "\n"))

			-- ป้อนกระดานชุดเดียวกันให้ข้อความกลางจอ ไม่ต้องยิงรีโมทซ้ำ
			overlayBoard = "— ไข่ดีสุดในสนาม —\n" .. table.concat(rows, "\n")
			renderOverlay()
		end)
		task.wait(5)
	end
end)

-- แถบสถานะ
task.spawn(function()
	while alive() do
		pcall(function()
			local lvl, cap, money = baseInfo()
			local pets = #myPets()
			local text = ("%s  •  %d studs/s\nรอบ %d · ได้ %d · พลาด %d · ฟัก %d · ขาย %d · อัป %d\nฐาน Lv%s (%s ตัว) · มีสัตว์ %d · เงิน $%s")
				:format(
					tostring(Hub.Phase), math.floor(Config.Step / Config.Gap),
					Stats.cycles, Stats.stolen, Stats.failed, Stats.hatched, Stats.sold, Stats.upgrades,
					tostring(lvl), tostring(cap), pets, comma(money or 0)
				)
			local left = secondsToReset()
			if left then text = text .. ("\nรีเซ็ตอีก %ds"):format(left) end
			if isResetting() then text = text .. "  (กำลังรีเซ็ต)" end
			setStatus(text)
			setLogBox(recentLog(6))

			-- ข้อความกลางจอ: จัดใหม่ให้อ่านเร็วกว่าแถบใน UI
			-- บรรทัดแรกคือ "ตอนนี้ทำอะไรอยู่" ตัวใหญ่สุด ที่เหลือเป็นตัวเลขประกอบ
			local head = ("【 Hamsterdiwa 】 %s"):format(tostring(Hub.Phase))
			if not Config.Running then head = head .. "  (หยุดอยู่)" end
			if isResetting() then
				head = head .. "  · กำลังรีเซ็ตสนาม"
			elseif left then
				head = head .. ("  · รีเซ็ตอีก %ds"):format(left)
			end

			overlayHead = table.concat({
				head,
				("ได้ %d · พลาด %d · ฟัก %d · ขาย %d · อัปฐาน %d")
					:format(Stats.stolen, Stats.failed, Stats.hatched, Stats.sold, Stats.upgrades),
				("ฐาน Lv%s · คอก %s ช่อง · มีสัตว์ %d ตัว · $%s")
					:format(tostring(lvl), tostring(cap), pets, comma(money or 0)),
			}, "\n")
			renderOverlay()
		end)
		task.wait(0.6)
	end
end)

-- แผงสัตว์ในกระเป๋า
-- แยกลูปของตัวเอง เพราะต้องอ่านข้อมูลก้อนใหญ่ ไปปนกับแถบสถานะที่วิ่งทุก 0.6 วิ ไม่ไหว
task.spawn(function()
	while alive() do
		pcall(function()
			local list, total, keep = sellCandidates()
			local rows = { ("มีทั้งหมด %d ตัว · ในคอก %d · เข้าข่ายขาย %d")
				:format(total, equipCap(), #list) }
			for i = 1, math.min(4, #list) do
				rows[#rows + 1] = ("  %s  $%s/s"):format(list[i].cat, comma(list[i].mps))
			end
			if #list > 4 then rows[#rows + 1] = ("  ... อีก %d ตัว"):format(#list - 4) end
			if #list == 0 then rows[#rows + 1] = "  ไม่มีตัวเข้าข่าย" end
			setPets(table.concat(rows, "\n"))
		end)
		task.wait(10)
	end
end)

-- ลูปเซฟค่า (เซฟเมื่อมีการเปลี่ยนแปลงเท่านั้น ไม่เขียนไฟล์รัวๆ)
task.spawn(function()
	while alive() do
		if configDirty and Config.AutoSaveConfig then
			configDirty = false
			pcall(saveConfig)
		end
		task.wait(3)
	end
end)

-- Anti-AFK
--
-- ของเดิมใช้ บริการจำลองอินพุตของ CoreScript ซึ่งเป็นวิธีมาตรฐาน
-- แต่ บริการจำลองอินพุต เป็นบริการต้องห้าม แค่เรียกก็โดนเตะข้อหาโกงใน 10 วินาที
-- (ดูบันทึกการวัดที่หัวไฟล์ ตรงที่ถอด GetService ออก)
--
-- แทนด้วยการขยับตัวเองนิดเดียวเมื่อเกมแจ้งว่าเราอยู่เฉยๆ นานเกินไป
-- Roblox นับ AFK จาก "ไม่มีอินพุต" แต่การขยับตัวละครก็รีเซ็ตตัวนับให้เหมือนกัน
-- ฟาร์มที่วิ่งอยู่ตลอดแทบไม่มีทางเข้าเงื่อนไขนี้ ตัวนี้เป็นแค่ตาข่ายกันเหนียว
local afkConn
pcall(function()
	afkConn = LocalPlayer.Idled:Connect(function()
		if not Config.AntiAFK or not alive() then return end
		pcall(function()
			local _, hrp = char()
			if hrp then
				hrp.CFrame = hrp.CFrame + Vector3.new(0, 0.15, 0)
				task.wait(0.15)
				hrp.CFrame = hrp.CFrame - Vector3.new(0, 0.15, 0)
			end
		end)
	end)
end)

--==================================================================
-- DESTROY
--==================================================================
function Hub.Destroy()
	Config.Running = false
	Hub.Alive = false
	-- ล้างเฉพาะตารางที่เลขตรงกับตัวเราจริงๆ
	--
	-- ของเดิมเช็ค genv แล้วล้างทั้งสองตารางพร้อมกัน
	-- แต่บาง executor คืน genv ใหม่ทุกครั้งที่รัน ตัวเก่าจึงเห็นเลขตรงกับตัวเองเสมอ
	-- พอมันปิดตัวเอง จะไปล้าง _G ซึ่งเป็นของสคริปต์ตัวใหม่ด้วย
	-- ตัวใหม่เห็นเลขกลายเป็น 0 ก็คิดว่าตัวเองล้าสมัยแล้วปิดตามไปอีก = ดับทั้งคู่
	if genv.EGG_FARM_GEN == GEN then genv.EGG_FARM_GEN = 0 end
	if _G.EGG_FARM_GEN == GEN then _G.EGG_FARM_GEN = 0 end
	pcall(setNoclip, false)

	-- ร่อนลงก่อนดับพื้นเสก ไม่ใช่ตัดทิ้งเฉยๆ
	--
	-- Destroy ถูกเรียกตอนรันสคริปต์ทับด้วย ถ้าตอนนั้นตัวกำลังบินอยู่ที่ y=82
	-- แล้วดับพื้นทันที ตัวจะร่วงแล้วตายทันทีที่โหลดตัวใหม่เสร็จพอดี
	-- ท่านี้ใช้เวลาราว 0.3 วิ ยอมรอได้
	pcall(stopSmoothCam)   -- คืนกล้องให้เกาะตัวละครตามเดิม ไม่งั้นกล้องค้าง
	if afkConn then pcall(function() afkConn:Disconnect() end) end
	if inputConn then pcall(function() inputConn:Disconnect() end) end
	pcall(destroyUI)
	pcall(function()
		if Hub.OverlayGui then Hub.OverlayGui:Destroy() Hub.OverlayGui = nil end
	end)
	genv.EGG_FARM_HUB = nil
end

--==================================================================
-- กล่องดำ  บันทึกสถานะลงไฟล์ตลอดเวลา
--
-- ทำไมต้องมี:
-- อาการ "โดนเตะ" เกิดเฉพาะบางเครื่อง และเครื่องที่ใช้พัฒนาไม่เคยเป็น
-- เดาจากภาพหน้าจอทีละใบแล้วผิดมาหลายรอบ เพราะไม่มีข้อมูลว่าตอนนั้นทำอะไรอยู่
--
-- ตัวนี้เขียนสถานะลงไฟล์ทุก 2 วินาที เก็บย้อนหลัง 150 บรรทัด (ราว 5 นาที)
-- พอโดนเตะ ไฟล์ยังอยู่ในเครื่อง เปิดอ่านได้ว่าวินาทีสุดท้ายทำอะไร
--
-- ไฟล์: HamsterTrace.txt ในโฟลเดอร์ workspace ของตัวรัน
-- ปิดได้ด้วย Config.Trace = false  (เขียนไฟล์เล็กมาก ไม่กินเฟรม)
--==================================================================
if Config.Trace ~= false and type(writefile) == "function" then
	task.spawn(function()
		local TRACE = "HamsterTrace.txt"
		local buf, MAX = {}, 150
		local t0 = os.clock()
		pcall(function()
			writefile(TRACE, ("=== Hamsterdiwa %s | %s | ver %d | job %s ===\n")
				:format(tostring(Hub.Build), tostring(Hub.Caps and Hub.Caps.executor),
					game.PlaceVersion, string.sub(tostring(game.JobId), 1, 8)))
		end)
		while alive() do
			local ok = pcall(function()
				local c = LocalPlayer.Character
				local hum = c and c:FindFirstChildOfClass("Humanoid")
				local hrp = c and c:FindFirstChild("HumanoidRootPart")
				local S = Hub.Stats or {}
				buf[#buf + 1] = ("%.0f %s|xz %d,%d|hp %s|md %.1f|v %.0f|col %s|dead %s|got %s|f %s|boost %s|%s")
					:format(
						os.clock() - t0,
						tostring(Hub.Phase),
						hrp and hrp.Position.X or 0, hrp and hrp.Position.Z or 0,
						hum and math.floor(hum.Health) or -1,
						hum and hum.MoveDirection.Magnitude or -1,
						hrp and hrp.AssemblyLinearVelocity.Magnitude or -1,
						hrp and tostring(hrp.CanCollide) or "?",
						hum and tostring(hum:GetStateEnabled(Enum.HumanoidStateType.Dead)) or "?",
						tostring(S.stolen), tostring(S.failed),
						tostring(Hub.ACState ~= nil),
						tostring(Hub.LastCarryMsg))
				if #buf > MAX then table.remove(buf, 1) end
				-- เขียนทับทั้งไฟล์ทุกครั้ง ไฟล์จึงไม่โตไม่จำกัด
				writefile(TRACE, table.concat(buf, "\n"))
			end)
			if not ok then break end
			task.wait(2)
		end
	end)
end

-- ล้างของที่รุ่นเก่าอาจทิ้งค้างไว้ในตัวละคร
--
-- สองอย่างนี้ replicate ขึ้นเซิร์ฟเวอร์ ถ้าค้างอยู่คือลายเซ็นโกงติดตัวไปเรื่อยๆ
-- แม้รุ่นใหม่จะไม่ได้สั่งอะไรเลยก็ตาม  ต้องคืนค่าให้ตั้งแต่โหลด
pcall(function() setNoclip(false) end)
pcall(function()
	local c = LocalPlayer.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if hum and not hum:GetStateEnabled(Enum.HumanoidStateType.Dead) then
		hum:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
	end
end)

-- เปิดของที่ควรเปิดตั้งแต่โหลด
if Config.SmoothCam then task.spawn(startSmoothCam) end
if Config.PerfMode then task.spawn(applyPerfSettings) end
if Config.FpsBoost then
	task.spawn(function()
		task.wait(2)   -- รอฉากโหลดครบก่อน ไม่งั้นตัดไม่หมด
		local n = Hub.fpsBoost()
		log(("เร่งเฟรม: ตัดของออก %d ชิ้น"):format(n))
	end)
end
if Config.BlankScreen then task.spawn(function() Hub.setBlankScreen(true) end) end

-- เริ่มฟาร์มเองถ้าสั่งไว้
-- หน่วงนิดนึงให้ UI/ตัวละคร/ข้อมูลเกมพร้อมก่อน ไม่งั้นรอบแรกพลาดฟรี
if Config.AutoStart then
	task.spawn(function()
		task.wait(3)
		if not alive() then return end
		Config.Running = true
		if setRunToggle then setRunToggle(true) end   -- ให้สวิตช์ใน UI ขยับตามด้วย
		log(("เริ่มฟาร์มอัตโนมัติ | %s | %d studs/s"):format(
			Config.Area, math.floor(Config.Step / Config.Gap)))
	end)
end

log("พร้อมใช้งาน — Hamster Diwa")
log("ทดสอบแล้ว: Hamster ของดีบอกต่อ")

-- บอกให้ชัดว่าค่าที่ใช้อยู่มาจากไหน เวลาแก้แล้วไม่เปลี่ยนจะได้รู้ว่าโดนตัวไหนทับ
local configSource = "ค่าเริ่มต้น"
if configLoaded then configSource = CONFIG_FILE end
if userConfigLoaded then configSource = USER_CONFIG_FILE end
if globalConfigLoaded then configSource = "_G.HamsterConfig" end

log("ค่าที่ใช้มาจาก: " .. configSource)
if not userConfigLoaded and not globalConfigLoaded then
	log("สร้างไฟล์ " .. USER_CONFIG_FILE .. " ให้แล้ว แก้แล้วรันใหม่")
end
log(("โหมด %s · %d studs/s · ด่าน %s"):format(
	Config.MoveMode, math.floor(Config.Step / Config.Gap), Config.Area))

print(("[Hamsterdiwa · Steal An Egg] โหลดเสร็จ | UI: %s | คอนฟิกจาก: %s | กด RightControl ซ่อน/โชว์"):format(
	usingLibrary and "Venoz Eiei" or "ในตัว", configSource))
