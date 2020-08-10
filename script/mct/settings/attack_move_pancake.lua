local this_mod_key = "attack_move_pancake";

local mct_mod = mct:register_mod(this_mod_key);

-------------------------------------------------------------------------------------------------------------------------------
--- @section Helper functions
-------------------------------------------------------------------------------------------------------------------------------

local function file_exists(filename)
    -- see https://stackoverflow.com/a/4991602/1019330
    local f = io.open(filename,"r");
    if f ~= nil then io.close(f) return true; else return false; end;
end;

local function create_local_option(section_key, ...)
    local tmp = mct_mod:add_new_option(...);
    tmp:set_local_only(true);
    tmp:set_assigned_section(section_key);
    return tmp;
end;

local function create_configured_hotkey_dropdown(section_key, option_key, camera_bookmark_number, use_camera_bookmark_as_default)

    local new_dropdown = create_local_option(section_key, option_key, "dropdown");
    new_dropdown:add_dropdown_value("no", "No", "", not use_camera_bookmark_as_default);

    if is_number(camera_bookmark_number) then

         --NOTE: camera_bookmark_save5 in English localization appears as "Save Camera Bookmark 6"
        local bookmark_key = "camera_bookmark_save"..tostring(camera_bookmark_number);
        local bookmark_loc = "shortcut_localisation_onscreen_"..bookmark_key;

        new_dropdown:add_dropdown_value(bookmark_key, bookmark_loc, "Bind to whatever keys you want in the Controls menu.", use_camera_bookmark_as_default);
    end;

    new_dropdown:add_dropdown_value("script_F2", "F2", "");
    new_dropdown:add_dropdown_value("script_shift_F2", "Shift + F2", "");
    new_dropdown:add_dropdown_value("script_ctrl_F2", "Ctrl + F2", "");
    new_dropdown:add_dropdown_value("script_F3", "F3", "");
    new_dropdown:add_dropdown_value("script_shift_F3", "Shift + F3", "");
    new_dropdown:add_dropdown_value("script_ctrl_F3", "Ctrl + F3", "");
    new_dropdown:add_dropdown_value("script_F4", "F4", "");
    new_dropdown:add_dropdown_value("script_shift_F4", "Shift + F4", "");
    new_dropdown:add_dropdown_value("script_ctrl_F4", "Ctrl + F4", "");

    return new_dropdown;
end;

-------------------------------------------------------------------------------------------------------------------------------
--- @section default section (renamed to "Configuration Source")
-------------------------------------------------------------------------------------------------------------------------------

--rename the default section
local default_section_title = "Configuration Source";
local default_section_title_is_localized = false;

local default_section = mct_mod:get_section_by_key("default");
if default_section then
    default_section:set_localised_text(default_section_title, default_section_title_is_localized);
else
    mct_mod:add_new_section("default", default_section_title, default_section_title_is_localized);
end;

-----------------

local option_which_config = create_local_option("default", "option_which_config", "dropdown");
option_which_config:add_dropdown_value("mct", "MCT Settings", "");
option_which_config:add_dropdown_value("file", "File (aigeneral_config.txt)", "");
option_which_config:add_dropdown_value("original", "Original Settings", "");

if file_exists("./mod_config/ai_general_config.txt") then
    option_which_config:set_default_value("file");
else
    option_which_config:set_default_value("mct");
end;

-------------------------------------------------------------------------------------------------------------------------------
--- @section Main Hotkeys
-------------------------------------------------------------------------------------------------------------------------------

mct_mod:add_new_section("section_main", "MCT Settings for Attack Move - Main Section", false);

local hotkey_for_set_ai_selection = create_configured_hotkey_dropdown("section_main", "hotkey_for_attack_move_lock", 6, true);

local add_button_for_attack_move_lock = create_local_option("section_main", "add_button_for_attack_move_lock", "dropdown");
add_button_for_attack_move_lock:add_dropdown_value("right", "On the Right", "", true);
add_button_for_attack_move_lock:add_dropdown_value("left", "On the Left", "");
add_button_for_attack_move_lock:add_dropdown_value("no", "No", "");

local redirect_radius = create_local_option("section_main", "redirect_radius", "slider");
redirect_radius:slider_set_min_max(0, 999999);
redirect_radius:slider_set_precision(0);
redirect_radius:set_default_value(64);
redirect_radius:slider_set_step_size(4, 0);

local seconds_between_attack_move_checks = create_local_option("section_main", "seconds_between_attack_move_checks", "slider");
seconds_between_attack_move_checks:slider_set_min_max(0.3, 20);
seconds_between_attack_move_checks:slider_set_precision(1);
seconds_between_attack_move_checks:set_default_value(1.1);
seconds_between_attack_move_checks:slider_set_step_size(0.2, 1);

local can_target_routing_enemies = create_local_option("section_main", "can_target_routing_enemies", "checkbox");
can_target_routing_enemies:set_default_value(true);

local can_target_shattered_enemies = create_local_option("section_main", "can_target_shattered_enemies", "checkbox");
can_target_shattered_enemies:set_default_value(false);


-------------------------------------------------------------------------------------------------------------------------------
--- @section section_experimental
-------------------------------------------------------------------------------------------------------------------------------

mct_mod:add_new_section("section_experimental", "MCT Settings for Attack Move - Experimental Options", false);

--[[
local ui_only__enable_experimental_options = create_local_option("section_experimental", "ui_only__enable_experimental_options", "checkbox");
ui_only__enable_experimental_options:set_default_value(false);
--]]

local enable_during_siege_battles = create_local_option("section_experimental", "enable_during_siege_battles", "checkbox");
enable_during_siege_battles:set_default_value(false);


-------------------------------------------------------------------------------------------------------------------------------
--- @section section_advanced
-------------------------------------------------------------------------------------------------------------------------------

mct_mod:add_new_section("section_advanced", "MCT Settings for Attack Move - Advanced Options", false);

--first, some helper functions for this section
local function new_angle_adjust(section_key, option_key, default_val)
    local new_option = create_local_option(section_key, option_key, "slider");
    new_option:slider_set_min_max(5, 180);
    new_option:slider_set_precision(0);
    new_option:set_default_value(default_val);
    new_option:slider_set_step_size(5, 0);

    return new_option;
end;

local function new_mult_adjust(section_key, option_key, default_val)

    local new_option = create_local_option(section_key, option_key, "slider");
    new_option:slider_set_min_max(1, 100);
    new_option:slider_set_precision(1);
    new_option:set_default_value(default_val);
    new_option:slider_set_step_size(0.1, 1);

    return new_option;
end;

local function new_add_adjust(section_key, option_key, default_val, allow_negatives)
    local new_option = create_local_option(section_key, option_key, "slider");

    if allow_negatives then
        new_option:slider_set_min_max(-995, 995);
    else
        new_option:slider_set_min_max(0, 995);
    end;

    new_option:slider_set_precision(0);
    new_option:set_default_value(default_val);
    new_option:slider_set_step_size(5, 0);

    return new_option;
end;

-- Bearing adjustments
local angle_for_max_bearing_adjustment = new_angle_adjust("section_advanced", "angle_for_max_bearing_adjustment", 45);
local max_mult_adjust_for_bearing = new_mult_adjust("section_advanced", "max_mult_adjust_for_bearing", 1.4);
local max_add_adjust_for_bearing = new_add_adjust("section_advanced", "max_add_adjust_for_bearing", 10);

-- Desired Direction adjustments
local angle_for_max_desired_direction_adjustment = new_angle_adjust("section_advanced", "angle_for_max_desired_direction_adjustment", 90);
local max_mult_adjust_for_desired_direction = new_mult_adjust("section_advanced", "max_mult_adjust_for_desired_direction", 1.3);
local max_add_adjust_for_desired_direction = new_add_adjust("section_advanced", "max_add_adjust_for_desired_direction", 0);

-- Two Flying adjustments
local mult_adjust_for_two_flying = new_mult_adjust("section_advanced", "mult_adjust_for_two_flying", 1);
local add_adjust_for_two_flying = new_add_adjust("section_advanced", "add_adjust_for_two_flying", -20, true);

-- Ranged vs Flying adjustments
local mult_adjust_ranged_vs_flying = new_mult_adjust("section_advanced", "mult_adjust_ranged_vs_flying", 1);
local add_adjust_ranged_vs_flying = new_add_adjust("section_advanced", "add_adjust_ranged_vs_flying", -20, true);

-- Chasing adjustments
local mult_chasing_adjust = new_mult_adjust("section_advanced", "mult_chasing_adjust", 1.1);
local add_chasing_adjust = new_add_adjust("section_advanced", "add_chasing_adjust", 5);

-- Adjust ranged if target in melee
local allow_ranged_to_target_melee = create_local_option("section_advanced", "allow_ranged_to_target_melee", "checkbox");
allow_ranged_to_target_melee:set_default_value(true);
local mult_adjust_ranged_if_target_in_melee = new_mult_adjust("section_advanced", "mult_adjust_ranged_if_target_in_melee", 1.1);
local add_adjust_ranged_if_target_in_melee = new_add_adjust("section_advanced", "add_adjust_ranged_if_target_in_melee", 50);

-- seconds_buffer_after_melee_ends
local seconds_buffer_after_melee_ends = create_local_option("section_advanced", "seconds_buffer_after_melee_ends", "slider");
seconds_buffer_after_melee_ends:slider_set_min_max(0.6, 9999);
seconds_buffer_after_melee_ends:slider_set_precision(1);
seconds_buffer_after_melee_ends:set_default_value(1.8);
seconds_buffer_after_melee_ends:slider_set_step_size(0.6, 1);

-- Tolerances
local tolerance_for_arrived_at_position = create_local_option("section_advanced", "tolerance_for_arrived_at_position", "slider");
tolerance_for_arrived_at_position:slider_set_min_max(10, 70);
tolerance_for_arrived_at_position:slider_set_precision(0);
tolerance_for_arrived_at_position:set_default_value(25);
tolerance_for_arrived_at_position:slider_set_step_size(3, 0);

local tolerance_for_arrived_at_position = create_local_option("section_advanced", "tolerance_for_arrived_at_position", "slider");
tolerance_for_arrived_at_position:slider_set_min_max(2, 180);
tolerance_for_arrived_at_position:slider_set_precision(0);
tolerance_for_arrived_at_position:set_default_value(10);
tolerance_for_arrived_at_position:slider_set_step_size(2, 0);

-------------------------------------------------------------------------------------------------------------------------------
--- @section MCT Listeners and other management
-------------------------------------------------------------------------------------------------------------------------------

mct_mod:set_section_sort_function("index_sort");
mct_mod:set_option_sort_function_for_all_sections("index_sort");

--[[
local function update_experimental_option_states(panel_just_populated)
    local should_lock_experimentals = not ui_only__enable_experimental_options:get_selected_setting();

    if should_lock_experimentals then
        enable_during_siege_battles:ui_select_value(false);
    end;

    if panel_just_populated or not should_lock_experimentals then --TODO: remove panel_just_populated parameter once the MCT bug is fixed that causes checkboxes to revert
        enable_during_siege_battles:set_uic_locked(should_lock_experimentals);
    end;
end;

ui_only__enable_experimental_options:add_option_set_callback(
    function(this_option)
        update_experimental_option_states();
    end
);
]]--

local function set_enabled_for_all_options(should_enable)
    local options_table = mct_mod:get_options();
    for k, current_option in next, options_table do
        if k ~= "option_which_config" then
            --current_option:set_uic_locked(should_lock); --if locking, watch out for other options that should stay locked for other reasons
            current_option:set_uic_visibility(should_enable);
        end;
    end;
end;

local function update_my_option_states(option_which_config)
    set_enabled_for_all_options(option_which_config:get_selected_setting() == "mct");
end;

option_which_config:add_option_set_callback(
    function(option)
        update_my_option_states(option);
    end
);

core:add_listener(
    "mct_populated_enable_check_for_"..tostring(this_mod_key),
    "MctPanelPopulated",
    function(context) return context:mod():get_key() == this_mod_key end,
    function(context)

        if not core:is_battle() then --all options are currently disabled during battle 

            context:mod():get_option_by_key("option_which_config");

            update_my_option_states(option_which_config);

            update_experimental_option_states(true);

        end;

    end,
    true
);
