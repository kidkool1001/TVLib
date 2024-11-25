TVLib = TVLib or {}

-- Function to convert military time (HHMM) to Zomboid minutes since midnight
local function timeToMinutes(timeStr)
    local hours = tonumber(timeStr:sub(1, 2))
    local minutes = tonumber(timeStr:sub(3, 4))
    return hours * 60 + minutes
end

-- Function to convert Zomboid time to continuous minutes (accounting for days)
local function zomboidTime(day, timeStr)
    local minutes = timeToMinutes(timeStr)
    return day * 1440 + minutes  -- 1440 minutes in a day
end

-- Function to read vanilla RadioData.xml
function TVLib.readVanillaRadioData()
    local vanillaDataPath = "media/radio/vanilla/RadioData.xml"  -- Path to vanilla radio data
    local modId = "TVLib"  -- Ensure this matches the id in your mod.info
    local file = getModFileReader(modId, vanillaDataPath, true)
    local xmlContent = ""
    
    if file then
        print("Reading vanillaRadioData.xml...")
        while true do
            local line = file:readLine()
            if not line then break end
            xmlContent = xmlContent .. line .. "\n"
        end
        file:close()
        print("Finished reading vanillaRadioData.xml.")
    else
        print("Failed to read vanillaRadioData.xml")
    end

    return xmlContent
end

-- Function to read CustomRadioData.xml
function TVLib.readCustomRadioData()
    local customDataPath = "media/radio/CustomRadioData.xml"  -- Path to custom radio data
    local modId = "TVLib"  -- Ensure this matches the id in your mod.info
    local file = getModFileReader(modId, customDataPath, true)
    local xmlContent = ""
    
    if file then
        print("Reading CustomRadioData.xml...")
        while true do
            local line = file:readLine()
            if not line then break end
            xmlContent = xmlContent .. line .. "\n"
        end
        file:close()
        print("Finished reading CustomRadioData.xml.")
    else
        print("Failed to read CustomRadioData.xml")
    end

    return xmlContent
end

-- Function to write to CustomRadioData.xml
function TVLib.writeCustomRadioData(xmlContent)
    local customDataPath = "media/radio/CustomRadioData.xml"  -- Specify full path within the mod directory
    local modId = "TVLib"  -- Ensure this matches the id in your mod.info
    local file = getModFileWriter(modId, customDataPath, true, false)  -- Write mode without append
    
    if file then
        print("Writing to CustomRadioData.xml in mod directory...")
        file:write(xmlContent)
        file:close()
        print("Finished writing to CustomRadioData.xml in mod directory.")
        --print("Written Content: " .. xmlContent)  -- Log the content being written
    else
        print("Failed to write to CustomRadioData.xml")
    end
end

-- Function to initialize CustomRadioData.xml from vanillaRadioData.xml
function TVLib.initializeCustomRadioData()
    print("Initializing CustomRadioData.xml from vanillaRadioData.xml")
    local vanillaContent = TVLib.readVanillaRadioData()
    TVLib.writeCustomRadioData(vanillaContent)
end

-- Helper function to split XML content into lines
function splitXmlContent(xmlContent)
    local lines = {}
    for line in xmlContent:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    return lines
end

-- Helper function to concatenate lines back into a string
function concatenateLines(lines)
    return table.concat(lines, "\n")
end

-- Modified addTVShow function to take xmlContentLines as a parameter
function TVLib.addTVShow(xmlContentLines, showData)
    print("Adding TV show: " .. showData.id)

    local startTime = zomboidTime(showData.day, showData.startTime)
    local endTime = startTime + 60  -- Assume shows are 1 hour long
    local broadcasts = {}
    local inCorrectChannel = false
    local inCorrectScript = false
    local currentScript = nil
    local inserted = false

    -- Extract and filter broadcasts by channel frequency and day
    for index, line in ipairs(xmlContentLines) do
        if line:match('<ChannelEntry') then
            local lineFreq = line:match('freq="(%d+)"')
            inCorrectChannel = lineFreq and tonumber(lineFreq) == showData.freq
            if inCorrectChannel then
                currentScript = line:match('startscript="(%w+)"')
            end
        elseif inCorrectChannel and line:match('<ScriptEntry') then
            local scriptName = line:match('name="(%w+)"')
            inCorrectScript = scriptName == currentScript
        elseif inCorrectScript and line:match('<BroadcastEntry') then
            local timestamp = line:match('timestamp="(%d+)"')
            local endstamp = line:match('endstamp="(%d+)"')
            local day = line:match('day="(%d+)"')
            if timestamp and endstamp and day then
                if tonumber(day) == showData.day then
                    table.insert(broadcasts, {
                        timestamp = tonumber(timestamp),
                        endstamp = tonumber(endstamp),
                        line = line,
                        index = index  -- Store the index of the line for easier updating
                    })
                    print("Broadcast found: timestamp=" .. timestamp .. ", day=" .. day .. ", endstamp=" .. endstamp)
                end
            else
                print("Error parsing line: " .. line)
            end
        elseif line:match('</BroadcastEntry>') and inCorrectScript and not inserted then
            -- Check for gaps and insert the new broadcast
            for i = 1, #broadcasts do
                local broadcast = broadcasts[i]
                local realEndTime = tonumber(broadcast.timestamp) + 60
                local nextEntryStart = tonumber(broadcast.endstamp)

                if startTime >= realEndTime and endTime <= nextEntryStart then
                    -- Found a suitable gap
                    print("Suitable gap found between " .. realEndTime .. " and " .. nextEntryStart)

                    -- Update endstamp of the previous broadcast
                    print("Updating endstamp of current broadcast from " .. broadcast.endstamp .. " to " .. startTime)
                    local updatedLine = broadcast.line:gsub('endstamp="(%d+)"', 'endstamp="' .. startTime .. '"')

                    -- Apply the update to the specific line in the list
                    xmlContentLines[broadcast.index] = updatedLine

                    -- Construct new broadcast entry
                    local newBroadcastEntry = '<BroadcastEntry ID="' .. showData.id .. '" timestamp="' .. startTime .. '" endstamp="' .. endTime .. '" type="ActivateBroadcast" day="' .. showData.day .. '" advertCat="' .. showData.advertCat .. '" isSegment="' .. tostring(showData.isSegment) .. '">\n'
                    for _, line in ipairs(showData.lines) do
                        local codesText = line.codes and ' codes="' .. line.codes .. '"' or ''
                        newBroadcastEntry = newBroadcastEntry .. '  <LineEntry ID="' .. line.ID .. '" r="' .. line.r .. '" g="' .. line.g .. '" b="' .. line.b .. '"' .. codesText .. '>' .. line.text .. '</LineEntry>\n'
                    end
                    newBroadcastEntry = newBroadcastEntry .. '</BroadcastEntry>\n'

                    -- Insert the new broadcast entry after the current closing tag
                    table.insert(xmlContentLines, index + 1, newBroadcastEntry)
                    print("Inserted new broadcast entry after entry " .. broadcast.line)
                    inserted = true  -- Set the flag to true to prevent further inserts
                    break
                end
            end
        elseif line:match('</ScriptEntry>') then
            inCorrectScript = false
        elseif line:match('</ChannelEntry>') then
            inCorrectChannel = false
        end
    end

    -- Return the updated content lines
    return xmlContentLines
end

-- New function to add multiple TV shows
function TVLib.addTVShows(showsData)
    print("Adding multiple TV shows...")
    local xmlContent = TVLib.readCustomRadioData()  -- Read from CustomRadioData
    local xmlContentLines = splitXmlContent(xmlContent)

    for _, showData in ipairs(showsData) do
        xmlContentLines = TVLib.addTVShow(xmlContentLines, showData)
    end

    -- Write the updated content back to the XML file
    local finalXmlContent = concatenateLines(xmlContentLines)
    TVLib.writeCustomRadioData(finalXmlContent)
    print("Successfully added multiple TV shows.")
end

-- Modified replaceTVShow function to take xmlContentLines as a parameter
function TVLib.replaceTVShow(xmlContentLines, showData)
    print("Replacing TV show with ID: " .. showData.replaceid)
    
    local inBroadcastEntry = false
    local replaced = false
    local updatedContent = ""

    -- Extract the new show data
    local newShow = {
        id = showData.id,
        isSegment = showData.isSegment,
        lines = showData.lines
    }

    local broadcastEntryContent = ""

    -- Iterate over each line in the XML content
    for _, line in ipairs(xmlContentLines) do
        if inBroadcastEntry then
            broadcastEntryContent = broadcastEntryContent .. line .. "\n"
            if line:match('</BroadcastEntry>') then
                -- End of the broadcast entry
                if broadcastEntryContent:match('ID="' .. escapePattern(showData.replaceid) .. '"') then
                    -- Extract necessary attributes from the line being replaced
                    local timestamp = broadcastEntryContent:match('timestamp="(%d+)"')
                    local endstamp = broadcastEntryContent:match('endstamp="(%d+)"')
                    local day = broadcastEntryContent:match('day="(%d+)"')
                    local advertCat = broadcastEntryContent:match('advertCat="(.-)"')
                    print("Found BroadcastEntry with ID: " .. showData.replaceid .. " - timestamp: " .. timestamp .. ", endstamp: " .. endstamp .. ", day: " .. day .. ", advertCat: " .. advertCat)

                    -- Construct new broadcast entry
                    local newBroadcastEntry = '<BroadcastEntry ID="' .. newShow.id .. '" timestamp="' .. timestamp .. '" endstamp="' .. endstamp .. '" type="ActivateBroadcast" day="' .. day .. '" advertCat="' .. advertCat .. '" isSegment="' .. tostring(newShow.isSegment) .. '">\n'
                    for _, line in ipairs(newShow.lines) do
                        local codesText = line.codes and (' codes="' .. line.codes .. '"') or ''
                        newBroadcastEntry = newBroadcastEntry .. '  <LineEntry ID="' .. line.ID .. '" r="' .. line.r .. '" g="' .. line.g .. '" b="' .. line.b .. '"' .. codesText .. '>' .. line.text .. '</LineEntry>\n'
                    end
                    newBroadcastEntry = newBroadcastEntry .. '</BroadcastEntry>\n'

                    -- Print the new broadcast entry for verification
                    --print("New Broadcast Entry:\n" .. newBroadcastEntry)

                    -- Add the new broadcast entry to updated content
                    updatedContent = updatedContent .. newBroadcastEntry
                    replaced = true
                else
                    -- Add the original broadcast entry to updated content
                    updatedContent = updatedContent .. broadcastEntryContent
                end
                inBroadcastEntry = false
                broadcastEntryContent = ""
            end
        else
            if line:match('<BroadcastEntry') then
                inBroadcastEntry = true
                broadcastEntryContent = line .. "\n"
            else
                updatedContent = updatedContent .. line .. "\n"
            end
        end
    end

    if replaced then
        print("Successfully replaced BroadcastEntry with ID: " .. showData.replaceid)
    else
        print("No BroadcastEntry found with ID: " .. showData.replaceid)
    end
    
    -- Return the updated content lines
    return splitXmlContent(updatedContent)
end

-- New function to replace multiple TV shows
function TVLib.replaceTVShows(showsData)
    print("Replacing multiple TV shows...")
    local xmlContent = TVLib.readCustomRadioData()  -- Read from CustomRadioData
    local xmlContentLines = splitXmlContent(xmlContent)

    for _, showData in ipairs(showsData) do
        xmlContentLines = TVLib.replaceTVShow(xmlContentLines, showData)
    end

    -- Write the updated content back to the XML file
    local finalXmlContent = concatenateLines(xmlContentLines)
    TVLib.writeCustomRadioData(finalXmlContent)
    print("Successfully replaced multiple TV shows.")
end

-- Helper function to escape special characters in patterns
function escapePattern(text)
    return text:gsub("([^%w])", "%%%1")
end











