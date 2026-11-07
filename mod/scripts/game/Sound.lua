-- Roadside Emergencies: a sound from the game's own files, once, at a place in the world: a sheep, a car's horn. A sound is only ever a nicety, so if one
-- can't be played that goes in the log once and the job carries on without it.

RseSound = {
    sources = {},
    failed = false
}

local function sourceFor(self, file, range)
    local source = self.sources[file]
    if source ~= nil then
        return source
    end
    local filename = Utils.getFilename(file, RoadsideEmergencies.MOD_DIR)
    local node = createAudioSource("rse_" .. file, filename, range, range * RseConfig.SOUND_INNER, 1, 1)
    setAudioSourceAutoPlay(node, false)
    link(getRootNode(), node)
    local sample = getAudioSourceSample(node)
    setSampleGroup(sample, AudioGroup.ENVIRONMENT)
    source = { node = node, sample = sample }
    self.sources[file] = source
    return source
end

local function playNow(self, file, x, y, z, range, volume)
    local source = sourceFor(self, file, range)
    setWorldTranslation(source.node, x, y, z)
    playSample(source.sample, 1, volume or 1, 0, 0, 0)
end

function RseSound:play(file, x, y, z, range, volume)
    if self.failed then
        return
    end
    if not RseLog.try("play a sound", playNow, self, file, x, y, z, range, volume) then
        self.failed = true
    end
end

-- while the map unloads
function RseSound:unload()
    for _, source in pairs(self.sources) do
        if source.node ~= nil and entityExists(source.node) then
            delete(source.node)
        end
    end
    self.sources, self.failed = {}, false
end
