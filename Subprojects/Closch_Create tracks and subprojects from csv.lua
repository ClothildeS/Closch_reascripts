-- USER CONFIG AREA ---------------------------------------------------------

function Msg(variable)
  reaper.ShowConsoleMsg(tostring(variable).."\n")
end

sep = "," -- default separator
default_name = "Name"
default_renderpreset = "Render preset"
default_duration = 1 --default length of subprojects
offset_position_minute = 1
----------------------------------------------------- END OF USER CONFIG AREA
name_column = 0
renderpreset_column = 0 
track_list = {}

function ParseCSVLine (line,sep)
  local res = {}
  local pos = 1
  sep = sep or ','
  while true do
    local c = string.sub(line,pos,pos)
    if (c == "") then break end
    if (c == '"') then
      -- quoted value (ignore separator within)
      local txt = ""
      repeat
        local startp,endp = string.find(line,'^%b""',pos)
        txt = txt..string.sub(line,startp+1,endp-1)
        pos = endp + 1
        c = string.sub(line,pos,pos)
        if (c == '"') then txt = txt..'"' end
        -- check first char AFTER quoted string, if it is another
        -- quoted string without separator, then append it
        -- this is the way to "escape" the quote char in a quote. example:
        --   value1,"blub""blip""boing",value3  will result in blub"blip"boing  for the middle
      until (c ~= '"')
      table.insert(res,txt)
      assert(c == sep or c == "")
      pos = pos + 1
    else
      -- no quotes used, just look for the first separator
      local startp,endp = string.find(line,sep,pos)
      if (startp) then
        table.insert(res,string.sub(line,pos,startp-1))
        pos = endp + 1
      else
        -- no separator found -> use rest of string and terminate
        table.insert(res,string.sub(line,pos))
        break
      end
    end
  end
  return res
end


-- read lines from csv file and register them in lists
-- to read : track_list[line index][field index]
function Read_lines(filepath)

  local file = io.input(filepath)

  repeat

    local line = file:read ("*l") -- read one line

    if line then  -- if not end of file (EOF)
      table.insert(track_list, ParseCSVLine (line,sep))
    end

  until not line  -- until end of file


  file:close()

  -- find useful columns (on first line) and store their index
  for i=1, #track_list[1] do
    local s = track_list[1][i]
    if s == default_name then
      name_column = i
    else if s == default_renderpreset then
      renderpreset_column = i
    end
    end

  end

  -- remove fields' labels from table
  table.remove(track_list, 1)
end

--create tracks from table
function Create_Tracks()
  reaper.Main_OnCommand(40297,0) --unselect all tracks

  local bool = false

  for i=1, #track_list do
    if not IsAlreadyCreated(track_list[i][name_column]) then
      reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
      local track = reaper.GetTrack(0, reaper.CountTracks(0)-1)
      reaper.GetSetMediaTrackInfo_String(track, "P_NAME", track_list[i][name_column], true)
      reaper.SetTrackSelected(track, true)
      bool = true
    end
  end

  return bool

end

function IsAlreadyCreated(tracklist_name)
  local bool = false
  for i=0, reaper.CountTracks(0)-1 do
      local track_ref = reaper.GetTrack(0, i)
      local retval, track_name = reaper.GetTrackName(track_ref)
      if tracklist_name == track_name then
        --Msg("Track already created")
        bool = true
      end
  end
  return bool
end

-- Get user input for selection duration
function GetSelectionDuration()
  local retval, duration = reaper.GetUserInputs("Selection duration of subprojects", 1, "Duration in minutes:", "")
  if retval then
    return tonumber(duration)
  end
  return nil
end

-- Create table of selected tracks with their indices and names
function GetSelectedTracks()
  local selected_tracks = {}
  for i = 0, reaper.CountSelectedTracks(0) - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    local track_index = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
    local retval, track_name = reaper.GetTrackName(track)
    selected_tracks[i + 1] = {track = track, index = track_index, name = track_name}
  end
  return selected_tracks
end

function GetLineIndex(track_name)
  for i=1, #track_list do
    local list_name = track_list[i][name_column]
    if list_name == track_name then
      return i
    end
  end
end

-- Create project markers for eachtrack
function Create_markers(duration, tracks)
 
  -- create markers for the selected tracks
  for i, track in ipairs(tracks) do
    local track_ref = track.track
    local track_index = reaper.GetMediaTrackInfo_Value(track_ref, "IP_TRACKNUMBER")
    local retval, track_name = reaper.GetTrackName(track.track)
    local line_index = GetLineIndex(track_name)


    -- create markers with track name
    reaper.AddProjectMarker2(0, false, ((track_index-1) * 2 * duration+ offset_position_minute)* 60, 0, track_list[line_index][name_column], track_index, 0)
    -- create markers with render presets
    reaper.AddProjectMarker2(0, false, ((track_index-1) * 2 * duration+ offset_position_minute)* 60, 0, track_list[line_index][renderpreset_column], track_index+100, 0)
      
  end
end

-- Deselect all tracks selected
function Deselect_tracks(tracks)
    for i, track in ipairs(tracks) do
        reaper.SetTrackSelected(track.track, false)
    end
end


-- set time selection for the current track
function Set_time_selection(marker_index, duration)
    reaper.GoToMarker(0, marker_index, false)
    local marker_position = reaper.GetCursorPosition()
    reaper.GetSet_LoopTimeRange(true, false, marker_position, marker_position + duration * 60, false)
end

--create subprojects at marker with duration
function Create_subprojects(duration, tracks)
  for i, track in ipairs(tracks) do
      Deselect_tracks(tracks)
      local track_ref = track.track
      local track_index = reaper.GetMediaTrackInfo_Value(track_ref, "IP_TRACKNUMBER")
      reaper.SetTrackSelected(track.track, true)
      Set_time_selection(track_index , duration)
      reaper.Main_OnCommand(41997, 0) -- move tracks to subprojects
  end
end

--select and rename the tracks on which the subprojects has been created
function Rename_tracks(tracks)

  for i = 0, reaper.CountTracks(0) - 1 do
      local track = reaper.GetTrack(0, i)
      local retval, track_name = reaper.GetTrackName(track)
      if string.match(track_name, " - subproject") then
        local new_track_name = string.gsub(track_name, " ", "")
        new_track_name = string.gsub(new_track_name, "-subproject", "")
        reaper.GetSetMediaTrackInfo_String(track, "P_NAME", new_track_name, true)
      end
  end
end


-- Main function
function Main()
  local relativePath = reaper.GetProjectPath()
  local retval, filetxt = reaper.GetUserFileNameForRead(relativePath, "Create tracks and subprojects from file", "csv")

  if retval then
    Read_lines(filetxt)
    local tracks_Ready = Create_Tracks()
    if not tracks_Ready then return end

    -- duration = GetSelectionDuration()
    -- if not duration then return end

    local tracks = GetSelectedTracks()
    Create_markers(default_duration, tracks)
    Create_subprojects(default_duration, tracks)
    Rename_tracks(tracks)
  end

  
end


-- INIT ---------------------------------------------------------------------


reaper.PreventUIRefresh(1)

reaper.Undo_BeginBlock() -- Beginning of the undo block. Leave it at the top of your main function.

Main()

reaper.Undo_EndBlock("Create tracks and subprojects from csv file", -1)

reaper.PreventUIRefresh(-1)

