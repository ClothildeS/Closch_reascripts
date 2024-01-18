-- USER CONFIG AREA ---------------------------------------------------------
console = true -- true/false: display debug messages in the console

dofile(reaper.GetResourcePath().."/UserPlugins/ultraschall_api.lua")

--local selected_tracks = {}
----------------------------------------------------- END OF USER CONFIG AREA


-- Display a message in the console for debugging
function Msg(value)
  if console then
    reaper.ShowConsoleMsg(tostring(value) .. "\n")
  end
end

-- Create table of selected tracks with their indices and names
function Get_SelectedTracks()
  local selected_tracks = {}
  for i = 0, reaper.CountSelectedTracks(0) - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    local track_index = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
    local retval, track_name = reaper.GetTrackName(track)
    selected_tracks[i + 1] = {track = track, index = track_index, name = track_name}
  end
  return selected_tracks
end


-- Reset Subproject items bounds
function Reset_Subprojects(tracks)
  local items_to_trim = {} 

  for i=1, reaper.CountSelectedTracks(0) do
    local items_number = reaper.CountTrackMediaItems(tracks[i].track)
    if items_number > 0 then
      local item_on_track, isLoop = Get_SubprojectItem(tracks[i].track)
      reaper.Main_OnCommand(40289, 0) -- unselect all items
      reaper.SetMediaItemSelected(item_on_track, true) --select the right item
      reaper.Main_OnCommand(42228, 0) -- reset item start and end to source start and end

      if not isLoop then
        table.insert(items_to_trim, item_on_track)
        
      end

    else
      Msg("Select a track with items")
    end
  end
  
  if items_to_trim then
    Reset_OneShotItems(items_to_trim)
    Rename_Items()
  end
end

-- reset one shot items
function Reset_OneShotItems(items)
  Select_Items(items)
  reaper.Main_OnCommand(40315, 0) -- auto trim / remove silence

end

-- select items stored in table
function Select_Items(items)
  -- deselect all media items
  reaper.Main_OnCommand(40289,0)

  for i=1, #items do
    reaper.SetMediaItemSelected(items[i], true)
  end
end

-- get items on track
function Get_ItemsOnTrack(track)
  local items_on_track = {}
  local item_count = reaper.CountTrackMediaItems(track.track)
  for i=0, item_count-1 do
    local item = reaper.GetTrackMediaItem(track.track, i)
    table.insert(items_on_track, item)
  end
  return items_on_track
end

-- Rename items to match iteration number
function Rename_Items()
  local items_count = reaper.CountSelectedMediaItems(0)
  

  for i=0, items_count-1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local track = reaper.GetMediaItem_Track(item)
    local retval, track_name = reaper.GetTrackName(track)
    local item_idx = reaper.GetMediaItemInfo_Value(item, "IP_ITEMNUMBER")+1
    local take = reaper.GetTake(item, 0)

    local concat_name
    local new_concat_name

    if item_idx > 9 then
      concat_name = track_name.."_"..tostring(math.floor(item_idx))
      --new_concat_name = string.gsub(concat_name, ".0", "")
    else
      concat_name = track_name.."_0"..tostring(math.floor(item_idx))
      --new_concat_name = string.gsub(concat_name, ".0", "")
    end
    --Msg(concat_name)
    reaper.GetSetMediaItemTakeInfo_String( take, "P_NAME", concat_name, true )

  end

end


-- Get the subproject item
function Get_SubprojectItem(track)
  local subproject_item
  local isLoop
  local items_number = reaper.CountTrackMediaItems(track)

  -- deselect all media items
  reaper.Main_OnCommand(40289,0)

  if items_number > 1 then
    
    for i = 0, items_number - 1 do -- Delete media items after the first one
      
      if i ~= 0 then
        
        local item = reaper.GetTrackMediaItem(track, 1) -- always get second item because the next to delete is always the second
        reaper.DeleteTrackMediaItem(track, item)

      end
		end

    subproject_item = reaper.GetTrackMediaItem(track, 0)

  else
    subproject_item = reaper.GetTrackMediaItem(track, 0)
  
  end

  local retval,track_name = reaper.GetTrackName(track)

  if string.match(track_name, "_LP") then
    isLoop = true
  else
    isLoop = false
  end


  return subproject_item, isLoop
end

function Export_SelectedTracks(tracks)
  local bounds_name = "ITEMS"
  local options_format_names

  for i=1, #tracks do
    Queue_TrackItems(tracks[i])
  end
  
  -- open render queue
  --reaper.Main_OnCommand(40929, 0)

  -- render through render queue
  local retval = ultraschall.RenderProject_RenderQueue(-1)
end

-- add items on track to the render queue
function Queue_TrackItems(track)

  local items = Get_ItemsOnTrack(track)
  Select_Items(items)

  -- get render preset name from marker
  local retval, isrgn, pos, rgnend, render_preset, markrgnindexnumber = reaper.EnumProjectMarkers(track.index*2)

  -- get render table from render preset name
  local render_table = ultraschall.GetRenderPreset_RenderTable("ITEMS", render_preset )

  -- Set render table to project settings + correct path
  Correct_RenderTable_Path(render_table)
  
  -- add selected items to render queue
  reaper.Main_OnCommand( 41823, 0 ) -- Add to render queue with last settings
  
end

-- set rendertable to project settings and change path
function Correct_RenderTable_Path(render_table)
  
  -- Get path from first marker at start of the project
  local retbool, isrgn, pos, rgnend, marker_name, markrgnindexnumber = reaper.EnumProjectMarkers(0)
  local path

  if string.match(marker_name, "Path=") then
    path = string.gsub(marker_name, "Path=", "")
  else
    path = "Exports"
  end

  -- render preset to render settings of project, change directory, get render table from project settings and render from it
  local retval, dirty = ultraschall.ApplyRenderTable_Project(render_table, true, true )

  -- change directory for rendered files
  local returnvalue, valuestrNeedBig = reaper.GetSetProjectInfo_String(0, "RENDER_FILE", path, true )

  -- Disable Silently increment filenames
  local disableOK = reaper.SNM_SetIntConfigVar("renderclosewhendone", reaper.SNM_GetIntConfigVar("renderclosewhendone", -666)&(~16))
  

end

-- Main function
function main()
  Reset_Subprojects(Get_SelectedTracks())
  Export_SelectedTracks(Get_SelectedTracks())
  
end


-- INIT ---------------------------------------------------------------------


reaper.PreventUIRefresh(1)

reaper.Undo_BeginBlock() -- Beginning of the undo block. Leave it at the top of your main function.

main()

reaper.Undo_EndBlock("Export Subprojects with custom render presets", -1)

reaper.PreventUIRefresh(-1)
