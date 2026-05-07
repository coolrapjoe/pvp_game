local SoundService = game:GetService("SoundService")

local MUSIC_VOLUME = 0.2

local songsFolder = SoundService:WaitForChild("Songs")

local playlist = {}
local currentIndex = 0
local currentEndedConnection
local lastPlayedSong = nil

local function buildPlaylist()
	playlist = {}

	for _, obj in ipairs(songsFolder:GetChildren()) do
		if obj:IsA("Sound") then
			table.insert(playlist, obj)
		end
	end
end

local function shuffle(t)
	for i = #t, 2, -1 do
		local j = math.random(1, i)
		t[i], t[j] = t[j], t[i]
	end
end

local function stopAllSongs()
	for _, song in ipairs(playlist) do
		song:Stop()
	end
end

local function playNext()
	if #playlist == 0 then
		return
	end

	currentIndex += 1

	if currentIndex > #playlist then
		repeat
			shuffle(playlist)
		until #playlist <= 1 or playlist[1] ~= lastPlayedSong

		currentIndex = 1
	end

	stopAllSongs()

	local song = playlist[currentIndex]
	lastPlayedSong = song
	song.Volume = MUSIC_VOLUME
	song.TimePosition = 0
	song:Play()

	if currentEndedConnection then
		currentEndedConnection:Disconnect()
	end

	currentEndedConnection = song.Ended:Connect(function()
		playNext()
	end)
end

buildPlaylist()
shuffle(playlist)
playNext()