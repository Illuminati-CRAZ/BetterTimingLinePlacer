--all of this is probably jank idk
--also the persistent (?) memory implementation is largely unneccessary
memory = {}

MEMORY_INCREMENT = .25

--------------------------------------------------------------------------------------------------------------------------------------------

BPM = 600
MSPTL = 240000 / BPM --milliseconds per timing line (400 ms per timing line)
INCREMENT = .125

CURRENT_FREE_TIMING_POINT_OFFSET = -4000002
INITIAL_SET_UP_MEMORY_OFFSET = -4000001
MEMORY_OFFSET = -4000000 --allows for supporting the first 50 minutes of a map without having SVs be placed in timing points territory
TIMING_POINT_OFFSET = -1000000 --allows for 2.5k timing lines using 600 BPM

---------------------------------------------------------------------------------------------------------------------------------------------

function initialize()
    local offset = map.TimingPoints[1].StartTime
    local signature = 4 --default 4 because I don't feel like actually dealing with it
    local msptl = 60000 / map.TimingPoints[1].Bpm * signature
    while offset > -3000 do
        offset = offset - msptl
    end

    actions.PlaceTimingPoint(utils.CreateTimingPoint(TIMING_POINT_OFFSET, BPM))
    actions.PlaceTimingPoint(utils.CreateTimingPoint(offset, map.TimingPoints[1].Bpm))
    memory.write(INITIAL_SET_UP_MEMORY_OFFSET, 1)
    memory.write(CURRENT_FREE_TIMING_POINT_OFFSET, 1)

    --for some reason deleting the first timing line causes all timing lines to be hidden
    --also this is jank
    --and doesn't work for some reason
    --[[temp = {}
    table.insert(temp, 10000000) --prevent user from being able to normally remove this timing line
    placeTimingLines(temp)]]--

    memory.correctDisplacement(TIMING_POINT_OFFSET)
end

function generateOrigins(starttime, msptl, free_index, amount)
    local origins = {}
    for i = 0, amount - 1 do
        table.insert(origins, starttime + msptl * (free_index - 1 + i))
    end
    return(origins)
end

function generateTeleportSV(origin, destination, increment)
    local svs = {}
    table.insert(svs, utils.CreateScrollVelocity(origin - increment, (destination - origin) / increment))
    table.insert(svs, utils.CreateScrollVelocity(origin, -(destination - origin) / increment + 2))
    table.insert(svs, utils.CreateScrollVelocity(origin + increment, 1)) --technically speaking not even really needed
    return(svs)
end

function batchGenerateTeleportSV(origins, destinations, increment)
    if #origins != #destinations then
        return(nil)
    end

    local svs = {}
    for i = 1, #origins do
        sv = generateTeleportSV(origins[i], destinations[i], increment)
        for k, v in pairs(sv) do
            svs[k + 3 * (i-1)] = v
        end
    end

    return(svs)
end

function removeTimingLineAt(destination)
    local origin = memory.delete(state.SongTime + MEMORY_OFFSET)
    local svs = {}
    table.insert(svs, getScrollVelocityAtExactly(origin - INCREMENT))
    table.insert(svs, getScrollVelocityAtExactly(origin))
    table.insert(svs, getScrollVelocityAtExactly(origin + INCREMENT))
    actions.RemoveScrollVelocityBatch(svs)
end

function placeTimingLines(destinations)
    local origins = generateOrigins(TIMING_POINT_OFFSET, MSPTL, memory.read(CURRENT_FREE_TIMING_POINT_OFFSET), #destinations)
    local svs = batchGenerateTeleportSV(origins, destinations, INCREMENT)
    actions.PlaceScrollVelocityBatch(svs)

    local links = {}
    for i = 1, #destinations do
        links[destinations[i] + 1] = origins[i] --the +1 is to counteract the -1 in memory.write()
    end
    memory.write(MEMORY_OFFSET, links)

    memory.write(CURRENT_FREE_TIMING_POINT_OFFSET, memory.delete(CURRENT_FREE_TIMING_POINT_OFFSET) + #destinations)
end

----------------------------------------------------------------------------------------------------------------------------------------

--maybe i should change "offset" to "index"
function memory.write(offset, data, step, mirror)
    if type(data) != "number" and type(data) != "table" then
        return(offset) --return same offset to use since nothing is written
    end

    step = step or 1 --non-int step will be fine when utils.CreateScrollVelocity() accepts floats for StartTime
    mirror = mirror or false --setting mirror to true causes effect of sv to be (mostly) negated by an equal and opposite sv and then a 1x sv is placed

    if type(data) == "number" then
        if mirror then
            local svs = {}
            table.insert(svs, utils.CreateScrollVelocity(offset, data))
            table.insert(svs, utils.CreateScrollVelocity(offset + MEMORY_INCREMENT, -data))
            table.insert(svs, utils.CreateScrollVelocity(offset + 2 * MEMORY_INCREMENT, 1))
            actions.PlaceScrollVelocityBatch(svs)
        else
            actions.PlaceScrollVelocity(utils.CreateScrollVelocity(offset, data))
        end
        return(offset + step) --one sv placed, so increment offset by 1 step
    else --data is a table
        local svs = {}
        for i, value in pairs(data) do
            table.insert(svs, utils.CreateScrollVelocity(offset + step * (i-1), value))
            if mirror then
                table.insert(svs, utils.CreateScrollVelocity(offset + step * (i-1) + MEMORY_INCREMENT, -value))
                table.insert(svs, utils.CreateScrollVelocity(offset + step * (i-1) + 2 * MEMORY_INCREMENT, 1))
            end
        end
        actions.PlaceScrollVelocityBatch(svs)
        return(offset + #data * step) --increment offset by number of elements in data times step
    end
end

function memory.search(start, stop)
    local svs = map.ScrollVelocities --I'm assuming this returns the svs in order so I'm not sorting them
    local selection = {}
    for _, sv in pairs(svs) do
        if (start <= sv.StartTime) and (sv.StartTime <= stop) then
            table.insert(selection, sv)
        elseif sv.StartTime > stop then --since they're in order, I should be able to return once StartTime exceeds stop
            break
        end
    end
    return(selection) --returns table of svs
end

function memory.read(start, stop, step)
    if not start then
        return(false)
    end

    step = step or 1 --step indicated which svs are for data and which are for mirroring
    stop = stop or start --stop defaults to start, so without a stop provided, function returns one item
    local selection = {}
    local x
    for _, sv in pairs(memory.search(start, stop)) do
        if not x then
            x = sv.StartTime - 1 --assume first sv is actual data
        end
        if (sv.StartTime - x) % step == 0 then --by default, anything without integer starttime is not included
            selection[sv.StartTime - x] = sv.Multiplier
        end
    end
    if #selection == 1 then --if table of only one element
        return(selection[1]) --return element
    else --otherwise
        return(selection) --return table of elements
    end
end

function memory.delete(start, stop, step)
    if not start then
        return(false)
    end

    step = step or 1
    stop = stop or start + 2 * MEMORY_INCREMENT

    local svs = memory.search(start, stop)
    local selection = {}
    local x

    for _, sv in pairs(svs) do
        if not x then
            x = sv.StartTime - 1
        end
        if (sv.StartTime - x) % step == 0 then
            selection[sv.StartTime - x] = sv.Multiplier
        end
    end

    actions.RemoveScrollVelocityBatch(svs)
    if #selection == 1 then --if table of only one element
        return(selection[1]) --return element
    else --otherwise
        return(selection) --return table of elements
    end
end

function memory.generateCorrectionSVs(limit, offset)
    local svs = map.ScrollVelocities --if these don't come in order i'm going to hurt someone

    local totaldisplacement = 0

    for i, sv in pairs(svs) do
        if (sv.StartTime < limit) and not (sv.StartTime == offset or sv.StartTime == offset + 1) then
            length = svs[i+1].StartTime - sv.StartTime
            displacement = length * (sv.Multiplier - 1) --displacement in ms as a distance
            totaldisplacement = totaldisplacement + displacement --total displacement in ms as a distance
        else
            break
        end
    end

    corrections = {}
    table.insert(corrections, utils.CreateScrollVelocity(offset, -totaldisplacement + 1)) --i think this is correct?
    table.insert(corrections, utils.CreateScrollVelocity(offset + 1, 1))

    return(corrections)
end

function memory.correctDisplacement(limit, offset) --will not work if there's an ultra large number at the end
    local limit = limit or 0 --where the memory ends
    local offset = offset or -10000002 --SVs will return with StartTime = offset and offset + 10000

    local currentsvs = {}
    table.insert(currentsvs, getScrollVelocityAtExactly(offset))
    table.insert(currentsvs, getScrollVelocityAtExactly(offset + 1))
    actions.RemoveScrollVelocityBatch(currentsvs)

    actions.PlaceScrollVelocityBatch(memory.generateCorrectionSVs(limit, offset))
end

----------------------------------------------------------------------------------------------------------------------------------------

function tableToString(table)
    local result = ""
    for i,value in pairs(table) do
        result = result .. "[" .. i .. "]: " .. value .. ", "
    end
    result:sub(1,-3)

    return(result)
end

function getScrollVelocityAtExactly(time)
    local currentsv = map.GetScrollVelocityAt(time)
    if currentsv.StartTime == time then
        return(currentsv)
    end
end

function getStartTimesFromSelection()
    local notes = state.SelectedHitObjects

    local starttimes = {}

    for _, note in pairs(notes) do
        if not has(starttimes, note.StartTime) then
            table.insert(starttimes, note.StartTime)
        end
    end

    return(starttimes)
end

function has(thing, val)
    for _, value in pairs(thing) do
        if value == val then
            return(true)
        end
    end

    return(false)
end

----------------------------------------------------------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------------------------------------------------------
function draw()
    imgui.Begin("Timing Line Ultra Spammer Supreme+++")

    state.IsWindowHovered = imgui.IsWindowHovered()

    imgui.TextWrapped("DO NOT MANUALLY UNDO ANY ACTION THIS PLUGIN PERFORMS")

    debug = state.GetValue("debug") or "hi"
    imgui.TextWrapped("Debug: " .. debug)

    --check to see if initial setup has been performed on map yet
    if memory.read(INITIAL_SET_UP_MEMORY_OFFSET) != 1 then
        if imgui.Button("Initialize") then
            initialize()
        end
        return(0) --prevents everything else from loading until stuff is initialized
    end

    local destination = state.GetValue("destination") or 0
    local destinations = state.GetValue("destinations") or {}
    local destinationsstring = state.GetValue("destinationsstring") or ""

    if imgui.Button("Current") then destination = state.SongTime end

    imgui.SameLine(0, 4)
    _, destination = imgui.InputFloat("Destination", destination, 1)
    if imgui.Button("Add Time to Destinations") then
        table.insert(destinations, destination)
        destinationsstring = tableToString(destinations)
    end

    imgui.SameLine(0, 4)
    if imgui.Button("Clear") then
        destinations = {}
        destinationsstring = ""
    end

    if imgui.Button("Add Selected Notes to Destinations") then
        for _, time in pairs(getStartTimesFromSelection()) do
            table.insert(destinations, time)
        end
        destinationsstring = tableToString(destinations)
    end

    if imgui.Button("Place Timing Lines") then
        placeTimingLines(destinations)

        destinations = {}
        destinationsstring = ""

        --memory.correctDisplacement(TIMING_POINT_OFFSET) --WHY DOES THIS NOT WORK???????????????
    end

    if imgui.Button("Correct Displacement") then --WHY DOES THIS PROPERLY CORRECT DISPLACEMENT WHILE THE LITERAL SAME FUNCTION IN THE BUTTON ABOVE DOESNT
        memory.correctDisplacement(TIMING_POINT_OFFSET)
    end

    if imgui.Button("Remove Timing Line at Current Time") then
        removeTimingLineAt(SongTime)
    end

    imgui.TextWrapped("Destinations: " .. destinationsstring)

    state.SetValue("destination", destination)
    state.SetValue("destinations", destinations)
    state.SetValue("destinationsstring", destinationsstring)

    imgui.End()
end
