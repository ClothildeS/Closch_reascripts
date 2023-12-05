-- USER CONFIG AREA ---------------------------------------------------------

function Msg(variable)
  reaper.ShowConsoleMsg(tostring(variable).."\n")
end
----------------------------------------------------- END OF USER CONFIG AREA
local track_names_list = {}
local render_presets_list = {}
local offset_position_minute = 1

--read lines from csv file and register them in lists
function Read_lines(filepath)

  local file = io.input(filepath)

  for line in io.lines(filepath) do

      line = line:gsub("%s+", "") -- delete space character
      local name, render_preset = line:match("%s*(.-),%s*(.*)")
      table.insert(track_names_list, name) --register names of tracks
      table.insert(render_presets_list, render_preset) -- register render presets
      --Msg(name)
      --Msg(render_preset)
  end

  --delete first lines of tables (category labels)
  table.remove(track_names_list, 1)
  table.remove(render_presets_list,1)


  file:close()

end

--create tracks from table
function Create_Tracks()
  
  for i=1, #track_names_list do
    reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
    local track = reaper.GetTrack(0, reaper.CountTracks(0)-1)
    reaper.GetSetMediaTrackInfo_String(track, "P_NAME", track_names_list[i], true)
    reaper.SetTrackSelected(track, true)
  end

  return 1

end

-- Get user input for selection duration
local function getSelectionDuration()
  local retval, duration = reaper.GetUserInputs("Selection duration of subprojects", 1, "Duration in minutes:", "")
  if retval then
    return tonumber(duration)
  end
  return nil
end

-- Create table of selected tracks with their indices and names
function getSelectedTracks()
  local selected_tracks = {}
  for i = 0, reaper.CountSelectedTracks() - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    local track_index = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
    local retval, track_name = reaper.GetTrackName(track)
    selected_tracks[i + 1] = {track = track, index = track_index, name = track_name}
  end
  return selected_tracks
end

-- Create project markers for eachtrack
function create_markers(duration, tracks)
 
  -- create markers for the selected tracks
  for i, track in ipairs(tracks) do
 
      --create first marker
      if i == 1 then do
        -- first marker with track name
        reaper.AddProjectMarker2(0, false, offset_position_minute*60 , 0, track.name, i, 0)
        -- first marker with render presets (index start at 101)
        reaper.AddProjectMarker2(0, false, offset_position_minute*60 , 0, render_presets_list[i], i+100, 0)
        end

      else
         -- create markers with track name
         reaper.AddProjectMarker2(0, false, ((track.index-1) * 2 * duration+ offset_position_minute)* 60, 0, track.name, i, 0)
         -- create markers with render presets
         reaper.AddProjectMarker2(0, false, ((track.index-1) * 2 * duration+ offset_position_minute)* 60, 0, render_presets_list[i], i+100, 0)
      end
  end
end

-- Deselect all tracks selected
function deselect_tracks(tracks)
    for i, track in ipairs(tracks) do
        reaper.SetTrackSelected(track.track, false)
    end
end


-- set time selection for the current track
function set_time_selection(marker_index, duration)
    reaper.GoToMarker(0, marker_index, false)
    marker_position = reaper.GetCursorPosition()
    reaper.GetSet_LoopTimeRange(true, false, marker_position, marker_position + duration * 60, false)
end

--create subprojects at marker with duration
function create_subprojects(tracks)
  for i, track in ipairs(tracks) do
      deselect_tracks(tracks)
      reaper.SetTrackSelected(track.track, true)
      set_time_selection(i , duration)
      reaper.Main_OnCommand(41997, 0)
  end
end

--select and rename the tracks on which the subprojects has been created
function rename_tracks(tracks)

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
  local retval, filetxt = reaper.GetUserFileNameForRead("", "Create tracks and subprojects from file", "csv")

  if retval then
    Read_lines(filetxt)
    local tracks_Ready = Create_Tracks()
    if not tracks_Ready then return end
    duration = getSelectionDuration()
    if not duration then return end
    local tracks = getSelectedTracks()
    create_markers(duration, tracks)

    create_subprojects(tracks)
    rename_tracks(tracks)
  end

  
end


-- INIT ---------------------------------------------------------------------


reaper.PreventUIRefresh(1)

reaper.Undo_BeginBlock() -- Beginning of the undo block. Leave it at the top of your main function.

Main()

reaper.Undo_EndBlock("Create tracks and subprojects from csv file", -1)

reaper.PreventUIRefresh(-1)

