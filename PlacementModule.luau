-----------------------------
--* DEPENDENCIES --
local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local GameConstants = require(ReplicatedStorage.Databases:WaitForChild("GameConstants"))
local RemappedMaterials = require(ReplicatedStorage.Databases:WaitForChild("RemappedMaterials"))
local switch = require(ReplicatedStorage.Libraries.MyLibraries:WaitForChild("switch"))
--------------!--------------

-----------------------------
--* TYPES --
--------------!--------------

-----------------------------
--* VARIABLES --
local CurrentPixel: Part?
local CanPlace = false
local IsPlacementInDebounce = false
local OverwriteProtection = {}
local IsAutoPlacementEnabled = false
local IsActive = false
local PlacementDebounce = 0.1
--------------!--------------

-----------------------------
--* CONSTANTS --
local Player = Players.LocalPlayer
local GridSize = 1
local Preferred = UserInputService.PreferredInput
local GridOrigin = Vector3.zero
local ValuesFolder = Player:WaitForChild("Values")
local PlaceablePixels = ValuesFolder:WaitForChild("PlaceablePixels") :: NumberValue
local Permissions = ValuesFolder:WaitForChild("Permissions") :: BoolValue
local Sound = ReplicatedStorage.Assets.GuiSounds:WaitForChild("Place")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ClientInputRemote = Remotes.Events:WaitForChild("ClientInputRemote")
local DataFetch = Remotes.Functions:WaitForChild("DataFetch")
local ServerUpdateOrder = Remotes.Events:WaitForChild("ServerUpdateOrder")

local PixelValues = Player.PlayerScripts:WaitForChild("PixelValues")
local PixelColor = PixelValues:WaitForChild("PixelColor")
local PixelMaterial = PixelValues:WaitForChild("PixelMaterial")
local PixelEffect = PixelValues:WaitForChild("PixelEffect")

local CanvasSize = ReplicatedStorage.Values:WaitForChild("CanvasSize")

local conn: { [string]: RBXScriptConnection? } = {}
local Events = {
	OnToggled = Instance.new("BindableEvent"),
}
--------------!--------------

local PlacementModule = {}

-----------------------------
--* PRIVATE FUNCTIONS --
local function snapToGrid(pos: Vector3)
	local half = GridSize * 0.5
	local gridSize = CanvasSize.Value - 0.5

	local x = math.floor(((pos.X - GridOrigin.X) - half) / GridSize + 0.5) * GridSize + GridOrigin.X + half
	local z = math.floor(((pos.Z - GridOrigin.Z) - half) / GridSize + 0.5) * GridSize + GridOrigin.Z + half

	x = math.clamp(x, -gridSize, gridSize)
	z = math.clamp(z, -gridSize, gridSize)

	return Vector3.new(x, 1, z)
end

local function CheckForCorrectPlacement()
	if not CurrentPixel then
		return
	end

	local hl = CurrentPixel:FindFirstChild("Highlight") :: Highlight

	local function color(c: number) -- 0 green, 1 yellow, 2 red
		CanPlace = c == 0
		hl.OutlineColor = switch(c, {
			{
				case = 0,
				resolver = Color3.new(0, 1, 0),
			},
			{
				case = 1,
				resolver = Color3.new(1, 1, 0),
			},
			{
				case = 2,
				resolver = Color3.new(1, 0, 0),
			},
		})
	end

	if not CurrentPixel.Parent or not hl then
		PlacementModule.DeactivePlacemantSystem()
		return
	end

	if PlaceablePixels.Value <= 0 then
		color(2)
		return
	end

	if IsAutoPlacementEnabled then
		if table.find(OverwriteProtection, CurrentPixel.Position) then
			color(2)
			return
		end
	end

	if IsPlacementInDebounce then
		color(1)
		return
	end

	color(0)
end

local function BindInput()
	ContextActionService:BindActionAtPriority(
		"Place",
		function(actionName: string, inputState: Enum.UserInputState, inputObject: InputObject)
			if not IsActive then
				return Enum.ContextActionResult.Pass
			end

			if inputState == Enum.UserInputState.Begin then
				PlacementModule.ActiveAutoPlacement()
			elseif inputState == Enum.UserInputState.End then
				PlacementModule.DeactivateAutoPlacement()
			end

			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.UserInputType.MouseButton1,
		Enum.KeyCode.ButtonA,
		Enum.KeyCode.ButtonR2
	)
end

local function RayCheck(): boolean
	local canvas = CollectionService:GetTagged("Canvas")[1]

	if not CurrentPixel or not canvas then
		return false
	end

	local cameraPos = workspace.CurrentCamera.CFrame.Position
	local pixelPos = CurrentPixel.Position
	local dir = (pixelPos - cameraPos).Unit * 500

	local rParam = RaycastParams.new()
	rParam.FilterDescendantsInstances = { canvas }
	rParam.FilterType = Enum.RaycastFilterType.Include

	local ray = Workspace:Raycast(cameraPos, dir, rParam)

	if not ray then
		warn("Out of canvas")
	end

	return ray ~= nil
end

local function CheckTurboPlacement()
	local gpOwned = DataFetch:InvokeServer("Gamepasses").TurboPlacement
	local vips = DataFetch:InvokeServer("VIPs")
	local activated = gpOwned or table.find(vips, Player.UserId)

	PlacementDebounce = GameConstants.BasePlayerValues.PixelPlacedDebounce / (activated and 2 or 1)
end

local function BindServerUpdate()
	ServerUpdateOrder.OnClientEvent:Connect(function(event)
		if event ~= "PixelPlacement" then
			return
		end

		CheckTurboPlacement()
	end)
end
--------------!--------------

-----------------------------
--* PUBLIC FUNCTIONS --
function PlacementModule.Init()
	Permissions.Changed:Connect(function(v)
		if not v then
			PlacementModule.DeactivePlacemantSystem()
		end
	end)

	task.delay(3, CheckTurboPlacement)
	BindInput()
	BindServerUpdate()
end

function PlacementModule.ActivePlacemantSystem()
	if not Permissions.Value then
		return
	end

	if CanvasSize.Value == 0 or Player.PlayerGui:FindFirstChild("LoadingGui") then
		return
	end

	IsActive = true
	Events.OnToggled:Fire()

	local p = Instance.new("Part", Workspace)
	p.Name = "CurrentPixel"
	CurrentPixel = p
	p.Material = RemappedMaterials[PixelMaterial.Value]
	p.Color = PixelColor.Value
	p.Size = Vector3.one
	p.CanCollide = false
	p.Transparency = 0.5

	if PixelEffect.Value > 0 then
		p:AddTag("Effect")
		p:SetAttribute("EffectId", PixelEffect.Value)
	end

	local hl = Instance.new("Highlight", p)
	hl.FillTransparency = 1
	hl.OutlineTransparency = 0

	if Preferred == Enum.PreferredInput.KeyboardAndMouse then
		local mouse = Player:GetMouse()

		conn.Snap = RunService.RenderStepped:Connect(function()
			p.CFrame = CFrame.new(snapToGrid(mouse.Hit.Position))

			CheckForCorrectPlacement()
		end)
	else
		conn.Snap = RunService.RenderStepped:Connect(function()
			p.CFrame = CFrame.new(snapToGrid(workspace.CurrentCamera.CFrame.Position))

			CheckForCorrectPlacement()
		end)
	end

	conn.ConnectColor = PixelColor.Changed:Connect(function(v)
		p.Color = v
	end)

	conn.ConnectMaterial = PixelMaterial.Changed:Connect(function(v)
		p.Material = RemappedMaterials[v]
	end)

	conn.ConnectEffect = PixelEffect.Changed:Connect(function(v)
		if v > 0 then
			p:AddTag("Effect")
			p:SetAttribute("EffectId", v)
		else
			p:RemoveTag("Effect")
			p:SetAttribute("EffectId", nil)
		end
	end)
end

function PlacementModule.DeactivePlacemantSystem()
	for i, v in conn do
		v:Disconnect()
		conn[i] = nil
	end

	if CurrentPixel then
		CurrentPixel:Destroy()
		CurrentPixel = nil
	end

	IsActive = false
	Events.OnToggled:Fire()
	PlacementModule.DeactivateAutoPlacement()
end

function PlacementModule.IsActive(): boolean
	return IsActive
end

function PlacementModule.ConfirmPlacement()
	if not CanPlace or not CurrentPixel or IsPlacementInDebounce or not RayCheck() or not IsActive then
		return
	end

	ClientInputRemote:FireServer({
		CurrentPixel.Position,
		CurrentPixel.Color,
		CurrentPixel.Material,
		PixelEffect.Value,
	})
	IsPlacementInDebounce = true

	if IsAutoPlacementEnabled then
		table.insert(OverwriteProtection, CurrentPixel.Position)
	end

	SoundService:PlayLocalSound(Sound)

	task.delay(PlacementDebounce, function()
		IsPlacementInDebounce = false
	end)
end

function PlacementModule.OnToggledConnect(func: (enabled: boolean) -> ()): RBXScriptConnection
	return Events.OnToggled.Event:Connect(function()
		func(IsActive)
	end)
end

function PlacementModule.ActiveAutoPlacement()
	IsAutoPlacementEnabled = true
	OverwriteProtection = {}

	task.spawn(function()
		while IsAutoPlacementEnabled do
			PlacementModule.ConfirmPlacement()
			task.wait(PlacementDebounce)
		end
	end)
end

function PlacementModule.DeactivateAutoPlacement()
	IsAutoPlacementEnabled = false
	OverwriteProtection = {}
end
--------------!--------------

return PlacementModule
