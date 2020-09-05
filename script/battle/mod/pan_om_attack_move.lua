-- Script author: Andrew Draper (paperpancake/paperpancake5)


--see also lib_battle_patrol_manager. This mod uses a different implementation
--because we also need to check for visibility, flying, etc, and I also want the unit cards to still be selectable,
--but you might be able to use lib_battle_patrol_manager in other situations or in other games


--A note on modifications while iterating:
--Some of this script relies on the behavior of Lua's next function described in the 5.1 documentation:
--    "The behavior of next is undefined if, during the traversal, you assign any value to a non-existent field in the table.
--     You may however modify existing fields. In particular, you may clear existing fields."
--That should allow us to set self.attack_move_orders[ui_id] = nil even when we are iterating over self.attack_move_orders[ui_id] using next

local this_mod_key = "attack_move_pancake";

local bm = get_bm();

--there may be some require() calls in as needed in functions below

if not is_function(toboolean) then
    --defined for readability
    function toboolean(arg)
        return not not arg;
    end;
end;

local function shallow_copy_simple_table(orig)
    local copy = {};
    for k, v in next, orig do
        copy[k] = v;
    end;
    return copy;
end;

--phases
local pan_phase = {
    NO_PHASE = 0, STARTUP = 1, DEPLOYMENT = 4, DEPLOYED = 5, --TODO: currently STARTUP is used for prebattle (due to a paradigm shift for using MCT). Refactor this to make it less confusing.
    MOCK_VICTORY_COUNTDOWN = 5.5, VICTORY_COUNTDOWN = 6, COMPLETE = 7
};

-- This is just a helper function that loops through all the unit cards
-- and calls function_to_do(uic_card) for each one
local function for_each_unit_card(function_to_do)
    local uic_parent = find_uicomponent(core:get_ui_root(), "battle_orders", "cards_panel", "review_DY");
	
	if uic_parent then
		for i = 0, uic_parent:ChildCount() - 1 do
			local uic_card = uic_parent:Find(i);
			if uic_card then
                uic_card = UIComponent(uic_card);
                function_to_do(uic_card);
            end;
		end;
    end;
end;

-- This is just a helper function that loops through all the units in the given_alliance
-- and calls function_to_do(current_unit, current_army, unit_index_in_army) for each one
local function for_each_unit_in_alliance(given_alliance, function_to_do)
	local all_armies_in_alliance = given_alliance:armies();

    for army_num = 1, all_armies_in_alliance:count() do
        local current_army = all_armies_in_alliance:item(army_num);
        local units = current_army:units();
		for unit_num = 1, units:count() do
			local current_unit = units:item(unit_num);
			if current_unit then
				function_to_do(current_unit, current_army, unit_num);
            end;
		end;
	end;
end;

--pancake orders manager
local pan_om = {
    map_ids_to_sus = {},        --a map of the ids of all friendly unique_ui_ids to script_units (which has a reference to the unit and unit_controller)
    
    attack_move_orders = {},    --attack_move_orders is a mapset. attack_move_orders[unique_ui_id] = order_set
                                --order_set is a table that stores the following to correspond with parameters for unit_controller:go_to_location_angle_width():
                                --    order_set["position"] = the desired position vector
                                --    order_set["bearing"]
                                --    order_set["width"] = width in m
                                --    order_set["move_fast"] = nil at first; we try to update this periodically, but it might not be completely accurate
                                --    order_set["melee_timestamp"] = nil, or the last timestamp in which the unit was known to be in melee
                                --
                                --    order_set.suspended_due_to_rout = nil, or true if a unit with an attack-move order is currently routing
                                --
                                --apart from "move_fast", these values are set at the time the order is given and remain static
                                --(instead of dynamically related to an enemy unit's position), which
                                --should be fine here since these will be given through move orders, not attack unit orders

    units_with_changed_melee_mode = {}, --units_with_changed_melee_mode[ui_id] = the boolean value of the "Change Melee" event if it fired while the unit was selected

    current_phase = pan_phase.NO_PHASE,

    DONT_ALLOW_REDIRECT = 999999999,

    attack_move_icons = {}, --attack_move_icons[ui_id] = the uic used to indicate there's an attack_move

    is_debug = false
                            --if you want to debug targets, you can use something like
                            -- --At the top of this file
                            --  local debug_old_target = nil;
                            --
                            -- --In find_attack_redirect_effective_distance:
                            --  if debug_old_target and other_unit:name() == debug_old_target:name() then
                            --        self:debug("your debug message here");
                            --  end;
                            --
                            -- --In pan_om:check_proximity_attacks(), under "if chosen_target then" use
                            -- debug_old_target = chosen_target;
};

function pan_om.out(msg)
    out("&&& Attack Move mod: "..tostring(msg));
end

function pan_om:debug(msg)
    if self.is_debug then
        self.out(msg);
    end;
end;


-------------------------------------------------------------------------------------------------------------------------------
--- @section Optional Configuration
--- @desc The user can provide a text file containing variable assignments, or they can use Vandy's Mod Configuration Tool
-------------------------------------------------------------------------------------------------------------------------------

local config = nil;
local already_loaded_config = false;
local mct_local_reference = false;

core:add_listener(
    "find_idle_mct_init_listener",
    "MctInitialized",
    true,
    function(context)

        mct_local_reference = context:mct();

        if already_loaded_config then

            local mct_order_warning = "Warning: Please let the author of the Attack Move mod know you received the following warning: MCT settings weren't available until after configuration was needed. We're ignoring them for this battle.";

            pan_om.out(mct_order_warning);

            --if we already have loaded configuration from the file and weren't supposed to,
            --provide some kind of visual indication of that the MCT settings are being ignored
            --it should appear whether or not the config file asks for no popup messages
            local mct = mct_local_reference;
            if mct then
                local mct_for_find_idle = mct:get_mod_by_key(this_mod_key);
        
                if mct_for_find_idle then
        
                    local option_which_config = mct_for_find_idle:get_option_by_key("option_which_config");
                    config_type = option_which_config:get_finalized_setting(); --"mct", "file", or "original" (shouldn't be nil here, but theoretically could be)
        
                    if config_type ~= "file" then
                        bm:callback(function() effect.advice(mct_order_warning) end, 3000, this_mod_key.."_mct_order_warning_dialog");
                    end;
                end;
            end;
        end;
    end,
    true
);

--returns the MCT (or nil if it's not found)
local function try_to_get_MCT()
    
    local mct = nil;

    --mct_local_reference will be nil unitl the MctInitialized event
    --we don't want to do anything with an uninitialized mct
    if mct_local_reference then
        if is_function(get_mct) then
            mct = get_mct();
            mct_local_reference = mct;
        else
            mct = mct_local_reference;
        end;
    end;
    
    return mct;
end;

--Note that the defaults for this mod are actually set in init_config_and_calc_values. This just handles variables that should be strings.
local function create_config_table_with_defaults()

    local config = {

        --This should save some text file users that might forget to put quotation marks around some strings like "script_F2"
        script_F2 = "script_F2",
        script_F3 = "script_F3",
        script_F4 = "script_F4",
        script_shift_F2 = "script_shift_F2",
        script_shift_F3 = "script_shift_F3",
        script_shift_F4 = "script_shift_F4",
        script_ctrl_F2 = "script_ctrl_F2",
        script_ctrl_F3 = "script_ctrl_F3",
        script_ctrl_F4 = "script_ctrl_F4",

        left = "left",
        right = "right",
    };

    return config;
end;

local function process_config_time_settings(config)

    config.seconds_buffer_after_melee_ends = pancake_config_loader.convert_to_ms(config.seconds_buffer_after_melee_ends, false);
    --if not config.seconds_buffer_after_melee_ends then
    --    config.seconds_buffer_after_melee_ends = 1400; --setting this default value is currently handled in init_config_and_calc_values()
    --end;

    config.seconds_between_attack_move_checks = pancake_config_loader.convert_to_ms(config.seconds_between_attack_move_checks, false);
    --if not config.seconds_buffer_after_melee_ends then
    --    config.seconds_buffer_after_melee_ends = 700; --setting this default value is currently handled in init_config_and_calc_values()
    --end;

end;

local function unpack_config_from_mct(mct, my_mod)

    local config, config_log_msg = nil, nil;

    config = create_config_table_with_defaults();

    local all_options = my_mod:get_options();
    for k, v in next, all_options do
        config[k] = v:get_finalized_setting();
    end;

    --handle any options that don't just directly transfer from MCT to file settings
    --(Note: we also do some of this handling in init_config_and_calc_values)

    return config, config_log_msg;
end;

local function try_loading_config_from_mct()

    local config, config_type, config_log_msg = nil, nil, nil;

    local mct = try_to_get_MCT();

    if mct then
        local my_mod = mct:get_mod_by_key(this_mod_key);

        if my_mod then

            local option_which_config = my_mod:get_option_by_key("option_which_config");
            config_type = option_which_config:get_finalized_setting(); --"mct", "file", or "original" (shouldn't be nil here, but theoretically could be)

            if config_type == "mct" then
                config, config_log_msg = unpack_config_from_mct(mct, my_mod);
            end;

        else
            --config_type = nil;
        end;
    else
        --config_type = nil;
    end;

    return config, config_type, config_log_msg;

end;

local function try_loading_config_from_file()

    local success, file_found, msg;

    local config, config_log_msg;

    config = create_config_table_with_defaults();

    success, file_found, msg, config = pancake_config_loader.load_file("./mod_config/attack_move_config.txt", config);

    if not file_found then
        --This might be the most common use case, so don't provide a visual dialog
        pan_om.out("No config file found; using default values.");
    else
        if not success then
            config_log_msg = "The config file could not be completely read. There might be an error in it.\n"
                            .."Loaded as much as could be read up to the error, which was:\n"
                            ..msg;
            pan_om.out(config_log_msg);
            --config_log_msg is also used further below
        else
            pan_om.out("Config was loaded.");
        end;
    end;

    return config, config_log_msg;
end;

--config_type is "mct", "file", or "original", or nil
--TODO: test this with and without the mct, and with and without the file
local function pancake_attack_move_load_config()

    local config, config_type, config_log_msg;
    
    if not pancake_config_loader then
        require("script/pancake_lib/pan_om_config_loader");
    end;

    config, config_type, config_log_msg = try_loading_config_from_mct();

    if config_type == "file" or config_type == nil then
        if config_type == nil then
            config_type = "file";
        end;
        config, config_log_msg = try_loading_config_from_file();

    elseif config_type == "original" then
        config = create_config_table_with_defaults();
    elseif config_type == "mct" then
        --config should already be set
    end;

    process_config_time_settings(config);
    already_loaded_config = true;

    if pan_om.is_debug then
        pan_om.out(" -- Config is: ");
        for k, v in next, config do
            pan_om.out(" -- "..tostring(k).." = "..tostring(v));
        end;
    end;

    return config, config_log_msg;
end;

-------------------------------------------------------------------------------------------------------------------------------
--- @section Extend the battle_manager's functionality
--- @desc This will allow me to more easily listen for any selection changes
-------------------------------------------------------------------------------------------------------------------------------
do
    local bm = get_bm();

    ----------------------------------------------------
    -- Extend listener for selections
    ----------------------------------------------------

    --both the callback_key (string) and the callback (function) are required
    --the order that the listeners will be called in is not guaranteed
    function bm:pan_om_set_listener_for_selections(callback_key, callback)
        if not (callback_key and is_string(callback_key) and callback and is_function(callback)) then
            pan_om.out("Bad arguments provided to bm:pan_om_set_listener_for_selections");
            return;
        end;

        if not self.pan_om_listeners_for_selections then
            self.pan_om_listeners_for_selections = {};
        end;

        self.pan_om_listeners_for_selections[callback_key] = callback;
    end;

    function bm:pan_om_clear_listeners_for_selections()
        self.pan_om_listeners_for_selections = nil;
    end;

    --overrides the old, global function
    local original_selection_handler = battle_manager_unit_selection_handler;
    battle_manager_unit_selection_handler = function(unit, is_selected)

        --note that this is a function, not a method; you can't use the self variable here

        if bm.pan_om_listeners_for_selections then
            for k, pan_om_callback in next, bm.pan_om_listeners_for_selections do
                pan_om_callback(unit, is_selected);
            end;
        end;

        original_selection_handler(unit, is_selected);
    end;

    --register a dummy listener so that the battle_manager registers its listener and keeps it registered
    --bm:register_unit_selection_callback(&&& needs a dummy unit &&&, function() --[[Do nothing]] end, "Pan_Om_Dummy_Selection");
    do
        local dummy_callback = {
            unit = nil,
            callback = function() --[[do nothing]] end;
        };
        
        if #bm.unit_selection_callback_list == 0 then
            bm:register_unit_selection_handler("battle_manager_unit_selection_handler");
        end;
        
        table.insert(bm.unit_selection_callback_list, dummy_callback);
    end;

end;


-------------------------------------------------------------------------------------------------------------------------------

local function num_check(val, default)
    if is_number(val) then
        return val;
    else
        return default;
    end;
end;

local function bool_check(val, default)
    if is_boolean(val) then
        return val;
    else
        return default;
    end;
end;

--note: If you later make config values editable mid-battle, you will need to handle the keyboard shortcut configurations
--      this doesen't currently do anything to edit listeners, etc.
--TOCONSIDER: Because we load the config values from files or MCT (both of which have default options), and then still specify
--            defaults here, that makes a lot of places that we need to update things if we change a default.
--            Is there a better way to do this?
function pan_om:init_config_and_calc_values(config)

    self.mult_chasing_adjust = num_check(config.mult_chasing_adjust, 1.1);
    self.add_chasing_adjust = num_check(config.mult_chasing_adjust, 5);

    self.seconds_buffer_after_melee_ends = num_check(config.seconds_buffer_after_melee_ends, 1400);

    self.seconds_between_attack_move_checks = num_check(config.seconds_between_attack_move_checks, 700);
    if self.seconds_between_attack_move_checks <= 100 then
        self.seconds_between_attack_move_checks = 100;
    end;

    self.enable_during_siege_battles = bool_check(config.enable_during_siege_battles, false);

    local tmp = config.add_button_for_attack_move_lock;
    if tmp == "left" then
        self.add_button_for_attack_move_lock = "left";
    elseif tmp == false or tmp == "no" or tmp == "No" or icon_choice == "NO" or tmp == "false" then
        self.add_button_for_attack_move_lock = false;
    else
        self.add_button_for_attack_move_lock = "right";
    end;

    local icon_choice = config.show_icon_above_attack_move_unit;
    if icon_choice == "no" or icon_choice == "No" or icon_choice == "NO" or icon_choice == false then
        self.show_icon_above_attack_move_unit = false;
    elseif icon_choice == "with other indicators" then
        self.show_icon_above_attack_move_unit = "with other indicators"
    else
        self.show_icon_above_attack_move_unit = "yes";
    end;

    if config.hotkey_for_attack_move_lock == "no" then
        config.hotkey_for_attack_move_lock = false;
    end;
    self.hotkey_for_attack_move_lock = bool_check(config.hotkey_for_attack_move_lock, true);

    self.resume_attack_move_after_combat = bool_check(config.resume_attack_move_after_combat, true);
    self.resume_attack_move_once_rallied = bool_check(config.resume_attack_move_once_rallied, false);

    self.tolerance_for_arrived_at_position = num_check(config.tolerance_for_arrived_at_position, 25);
    self.tolerance_for_arrived_at_bearing = num_check(config.tolerance_for_arrived_at_bearing, 10);

    self.redirect_radius = num_check(config.redirect_radius, 64);

    self.max_mult_adjust_for_bearing = num_check(config.max_mult_adjust_for_bearing, 1.4);
    self.max_add_adjust_for_bearing = num_check(config.max_add_adjust_for_bearing, 10);

    self.max_mult_adjust_for_desired_direction = num_check(config.max_mult_adjust_for_desired_direction, 1.3);
    self.max_add_adjust_for_desired_direction = num_check(config.max_add_adjust_for_desired_direction, 0);

    self.can_target_routing_enemies = bool_check(config.can_target_routing_enemies, true);
    self.can_target_shattered_enemies = bool_check(config.can_target_shattered_enemies, false);

    --TOCONSIDER
    --use_max_total_adjust_for_bearing_and_dir = false;
    --max_total_adjust_for_bearing_and_dir = 50;

    self.angle_for_max_bearing_adjustment = num_check(config.angle_for_max_bearing_adjustment, 45);
    if math.abs(self.angle_for_max_bearing_adjustment) < 0.1 then --prevent divide by 0
        self.angle_for_max_bearing_adjustment = 1;
    end;

    self.angle_for_max_desired_direction_adjustment = num_check(config.angle_for_max_desired_direction_adjustment, 90);
    if math.abs(self.angle_for_max_desired_direction_adjustment) < 0.1 then --prevent divide by 0
        self.angle_for_max_desired_direction_adjustment = 1;
    end;

    self.mult_adjust_for_two_flying = num_check(config.mult_adjust_for_two_flying, 1);
    self.add_adjust_for_two_flying = num_check(config.add_adjust_for_two_flying, -20);

    self.mult_adjust_ranged_vs_flying = num_check(config.mult_adjust_ranged_vs_flying, 1);
    self.add_adjust_ranged_vs_flying = num_check(config.add_adjust_ranged_vs_flying, -20);

    self.allow_range_to_target_melee = bool_check(config.allow_range_to_target_melee, true);

    self.mult_adjust_range_if_target_in_melee = num_check(config.mult_adjust_range_if_target_in_melee, 1.1);
    self.add_adjust_range_if_target_in_melee = num_check(config.add_adjust_range_if_target_in_melee, 50);

    --calculated values
    self.mult_adjust_for_bearing = (self.max_mult_adjust_for_bearing - 1) / self.angle_for_max_bearing_adjustment;
    self.add_adjust_for_bearing = self.max_add_adjust_for_bearing / self.angle_for_max_bearing_adjustment;
    self.mult_adjust_for_desired_direction = (self.max_mult_adjust_for_desired_direction - 1) / self.angle_for_max_desired_direction_adjustment;
    self.add_adjust_for_desired_direction = (self.max_add_adjust_for_desired_direction - 1) / self.angle_for_max_desired_direction_adjustment;

end;

function pan_om:create_attack_move_icon(ui_id)
    if self.show_icon_above_attack_move_unit then

        ui_id = tostring(ui_id);

        self:debug("Trying to create an icon above unit "..ui_id);

        local parent_uic = find_uicomponent(core:get_ui_root(), "unit_id_holder", ui_id);

        if parent_uic then

            if self.show_icon_above_attack_move_unit == "with other indicators" then
            
                local sibling_uic = find_uicomponent(parent_uic, "modular_parent", "icon_threat");
                if sibling_uic then

                    local attack_move_icon = UIComponent(sibling_uic:CopyComponent("attack_move_pancake_icon"));

                    if attack_move_icon then
                        
                        attack_move_icon:SetCanResizeWidth(true)
                        attack_move_icon:SetCanResizeHeight(true)
                        attack_move_icon:Resize(27, 36);
                        for i = 0, attack_move_icon:NumStates() do
                            attack_move_icon:SetImagePath("ui\\pancake_images\\icon_attack_move_above_unit.png", i);
                            attack_move_icon:SetVisible(true);
                        end;
                        attack_move_icon:SetVisible(true);

                        self.attack_move_icons[ui_id] = attack_move_icon;

                        self:debug("Created the icon above the unit");

                    else
                        self:debug("Failed to create the icon above the unit");
                    end;

                else
                    self:debug("No sibling component above unit was found");
                end;

            elseif self.show_icon_above_attack_move_unit == "yes" then

                --[[
                Just adding the component doesn't seem to work
                
                local attack_move_icon = UIComponent(parent_uic:CreateComponent(str_name, "ui/campaign ui/region_info_pip"));

                if attack_move_icon then
                    
                    attack_move_icon:SetCanResizeWidth(true)
                    attack_move_icon:SetCanResizeHeight(true)
                    attack_move_icon:Resize(27, 36);
                    attack_move_icon:SetImagePath("ui\\pancake_images\\icon_attack_move_above_unit.png", 0);
                    attack_move_icon:SetVisible(true);

                    self.attack_move_icons[ui_id] = attack_move_icon;

                    self:debug("Tried to create the icon above the unit");

                else
                    self:debug("Failed to create the icon above the unit");
                end;

                --]]

                local script_ping_parent = find_uicomponent(parent_uic, "script_ping_parent");
        
                if script_ping_parent then
        
                    local uic_ping_marker = UIComponent(script_ping_parent:CreateComponent(this_mod_key .. "_ping_icon", "ui/battle ui/unit_ping_indicator"));
 
                    local attack_move_icon = find_uicomponent(uic_ping_marker, "icon");

                    --local current_unit = bm:get_player_alliance():armies():item(1):units():item(1);
                    --attack_move_icon:SetContextObject("CcoBattleUnit" .. current_unit:unique_ui_id()); --this will make the icon zoom to the unit when clicked
                                                                                                         --TOCONSIDER: Should it unlock when clicked? Or just do nothing?
                    
                    if attack_move_icon then
        
                        --attack_move_icon:SetImagePath("ui\\pancake_images\\icon_attack_move_above_unit.png");
                        attack_move_icon:SetCanResizeWidth(true)
                        attack_move_icon:SetCanResizeHeight(true)
                        attack_move_icon:Resize(27, 36);
                        attack_move_icon:SetDockOffset(0, 40);
                        attack_move_icon:SetVisible(true);
                        
                        for i = 1, attack_move_icon:NumImages() - 1 do
                            attack_move_icon:SetImagePath("ui\\pancake_images\\attack_move_transparent_pixel.png", i);
                        end;
                        
                        attack_move_icon:SetImagePath("ui\\pancake_images\\icon_attack_move_above_unit.png", 0);
                        
                        self.attack_move_icons[ui_id] = attack_move_icon;

                    end;
                    
                    local tmp_arrow = find_uicomponent(uic_ping_marker, "arrow");
                    if tmp_arrow then
                        tmp_arrow:SetVisible(false);
                    end;

                    --TODO: I think I need some of this, but maybe not all of it
                    uic_ping_marker:StopPulseHighlight();
                    script_ping_parent:RemoveTopMost();
                    --script_ping_parent:UnLockPriority();
                    uic_ping_marker:RemoveTopMost();
                    --uic_ping_marker:UnLockPriority();
                    for i = 0, uic_ping_marker:ChildCount() - 1 do
                        local child_uic = UIComponent(uic_ping_marker:Find(i));
                        if is_uicomponent(child_uic) then
                            child_uic:StopPulseHighlight();
                            child_uic:RemoveTopMost();
                            --child_uic:UnLockPriority();
                        end;
                    end;

                    --script_ping_parent:PropagatePriority(-1);
                    
                    self:debug("Created the icon above the unit");
        
                else
                    self:debug("No script ping parent found");
                end;

            end;

        end;
    end;
end;

function pan_om:get_icon_above(ui_id)
    return self.attack_move_icons[ui_id];
end;

function pan_om:update_icon_above(ui_id)

    if self.show_icon_above_attack_move_unit then

        local attack_move_icon = self:get_icon_above(ui_id);

        if self:has_attack_move_turned_on(ui_id) then
            if attack_move_icon then
                attack_move_icon:SetVisible(true);
            else
                self:create_attack_move_icon(ui_id);
            end;
        else
            if attack_move_icon then
                attack_move_icon:SetVisible(false);
            end;
        end;

    end;
end;

function pan_om:has_attack_move_turned_on(ui_id)
    return toboolean(self.attack_move_orders[ui_id]);
end;

--Note: For internal use only. This does not update the UI
function pan_om:_clear_attack_move_from_unit(ui_id)
    self.attack_move_orders[ui_id] = nil;
    --self:debug("_clear_attack_move_from_unit for id "..tostring(ui_id));
end;

--Only called if self.resume_attack_move_once_rallied
--Don't call _clear_attack_move_from_unit. This will handle that.
function pan_om:_mark_unit_as_routing_with_attack_move(ui_id)

    local routed_order_set = self.attack_move_orders[ui_id];

    if routed_order_set then
        routed_order_set.suspended_due_to_rout = true;
    end;

    --self:debug("_mark_unit_as_routing_with_attack_move finished for unit with id "..tostring(ui_id));
end;

--this only gets called (and is only relevant) if self.resume_attack_move_once_rallied
function pan_om:_routing_attack_mover_has_rallied(ui_id)

    local order = self.attack_move_orders[ui_id];
    if order then
        order.suspended_due_to_rout = nil;
    end;
end;

--returns a numerically indexed array of unit ids that are selected in the UI (will be an empty table if none are selected)
function pan_om:get_selected_ui_ids()
    local uic_parent = find_uicomponent(core:get_ui_root(), "battle_orders", "cards_panel", "review_DY");
    local selected_ui_ids = {}; --list of string ids
    
    --populate selected_ui_ids
	if uic_parent then
		for i = 0, uic_parent:ChildCount() - 1 do
			local uic_card = uic_parent:Find(i);
			if uic_card then
                uic_card = UIComponent(uic_card);

                if tostring(uic_card:CurrentState()):lower():find("selected") then
                    local unique_ui_id = tostring(uic_card:Id());

                    table.insert(selected_ui_ids, unique_ui_id);
                end;
            end;
		end;
    end;
    
    return selected_ui_ids;
end;

--the currently selected units will either be all added or all removed from attack_move_orders
--returns true if the selected units are in attack_move_orders
--returns false if the selected units are no longer in attack_move_orders
--returns nil if nothing was selected
function pan_om:toggle_attack_move(is_callback_context)
    --self:debug("In toggle_attack_move");

    local selected_ui_ids = self:get_selected_ui_ids();

    if #selected_ui_ids == 0 then
        --TOCONSIDER: if nothing was selected, should it just do nothing?
        return nil;
    end;

    local first_selected_id = selected_ui_ids[1];
    local turn_on = not self:has_attack_move_turned_on(first_selected_id); --use the opposite of the current exclusion state

    --ensure all selected units have the same rule
    for i = 2, #selected_ui_ids do
        if turn_on == self:has_attack_move_turned_on(selected_ui_ids[i]) then
            --some of the selected units were attack-moving before and some weren't, so remove them all
            turn_on = false;
            break;
        end;
    end;
    
    self:set_attack_move_for_units(selected_ui_ids, turn_on, is_callback_context);

    --self:debug("End of toggle_attack_move");

    return turn_on;
end;

--this function excludes units in a batch so that the UI can be updated all at once
--This must be called from a callback context
--this function will also call set_attack_move_button_state if that function exists
--IMPORTANT: this function assumes the given units are already in map_key_to_mock_sus
--           most units should be anyway, but if in doubt, check before calling this function 
function pan_om:set_attack_move_for_units(table_of_unit_keys, turn_on, is_callback_context)

    --self:debug("In set_attack_move_for_units, turn_on is: "..tostring(turn_on));

    if not is_callback_context then
        bm:callback(
            function() self:set_attack_move_for_units(table_of_unit_keys, turn_on, true) end,
            0,
            "pan_om_callback_set_attack_move"
        );
        --self:debug("set_excluded_for_units will wait for a callback. Returning for now");
        return;
    end;

    if not is_table(table_of_unit_keys) then
        table_of_unit_keys = {table_of_unit_keys};
    end;

    if turn_on then
        modder_API_release_uc_for_ids(table_of_unit_keys, this_mod_key);
    end;

    local changed_attack_move = false;

    for i = 1, #table_of_unit_keys do
        local unit_key = table_of_unit_keys[i];

        if self:has_attack_move_turned_on(unit_key) ~= turn_on then
            changed_attack_move = true;
            if turn_on then
                local associated_su = self:find_su_with_id(unit_key);
                if associated_su and associated_su.unit then
                    local associated_unit = associated_su.unit;
                    local order_set = {
                        position = associated_unit:ordered_position();
                        bearing = associated_unit:ordered_bearing();
                        width = associated_unit:ordered_width();
                    };

                    --local radians_bearing = math.rad(order_set.bearing);
                    --For their angles, they treat their x like y and their z like x, so
                    -- x = math.sin(...) and z = math.cos(...)
                    --order_set.ordered_bearing_vector = battle_vector:new(math.sin(radians_bearing), 0, math.cos(radians_bearing));

                    --[[
                        I can't get debug_drawing to work. I think it requires enabling something we don't have access to
                    local end_v = battle_vector:new(order_set.position:get_x() + order_set.ordered_bearing_vector:get_x() * 20, order_set.position:get_y(), order_set.position:get_z() + order_set.ordered_bearing_vector:get_z() * 20);
                    local start_v = battle_vector:new(order_set.position:get_x(), order_set.position:get_y(), order_set.position:get_z());
                    debug_drawing:draw_white_line_on_terrain(start_v, end_v, 5000);
                    --]]

                    self.attack_move_orders[unit_key] = order_set;
                else
                    pan_om.out("Warning. Can't find a unit with the unique id "..tostring(unit_key));
                end;
            else
                self:_clear_attack_move_from_unit(unit_key);
            end;

            
            self:update_icon_above(unit_key);

            --self:debug("Tried to set attack_move_orders for "..tostring(unit_key).." to "..tostring(turn_on));
            --self:debug("Did it work? has_attack_move_turned_on = "..tostring(self:has_attack_move_turned_on(unit_key)));
        end;
    end;

    if changed_attack_move then

        --TOCONSIDER: update any UI elements here (including marks on unit cards if you add those later, etc)
        --            NOTE: currently I have to keep updating the visibility of the icons above the units, so that is done in the main loop

        if is_function(self.set_attack_move_button_state) then
            self:set_attack_move_button_state(turn_on, true);
        end;
    end;

    --self:debug("Done with set_attack_move_for_units");
end;

--TOCONSIDER: Thoughts for multiplayer gifting:
--            Should I check to see if the unit card exists here?
--            Is it ok to create a script unit for different
function pan_om:setup_map_ids_to_sus()
    self:debug("in setup_map_ids_to_sus");
    self:debug("in setup_map_ids_to_sus, player_alliance = "..tostring(bm:get_player_alliance()));

    for_each_unit_in_alliance(
        bm:get_player_alliance(),
        function(current_unit, current_army, unit_index_in_army)
            self:debug("Checking unit "..tostring(unit_index_in_army));
			local ui_id = tostring(current_unit:unique_ui_id());
            if not self.map_ids_to_sus[ui_id] then
                self:debug("Trying to create script unit for "..tostring(unit_index_in_army));
                self.map_ids_to_sus[ui_id] = script_unit:new(current_army, unit_index_in_army);
                self:debug("Was script unit created? "..tostring(self.map_ids_to_sus[ui_id]));
			end;
        end
	);
	self:debug("end of setup_map_ids_to_sus");
end;

function pan_om:find_su_with_id(unique_ui_id)
    local retval = self.map_ids_to_sus[unique_ui_id];
	if not retval then
		--self:debug("find_su_with_id didn't find the first time; trying to set it up again");
        --add all units to the map and search again (it might be a summon or something like that)
        self:setup_map_ids_to_sus(); --this is not the most performant, but it works
        retval = self.map_ids_to_sus[unique_ui_id];
	end;

    return retval;
end;

--this must be called from a callback, not a shortcut or UI event handler
--@return effective_distance between the two units (adjusted for orientation, flying, etc)
--        returns an effective distance of pan_om.DONT_ALLOW_REDIRECT (a large integer) if this mod shouldn't have this unit attack the other one
--@return other_is_in_chasing_area as nil or true
--@param this_alliance is an optional param that can be improve performance by not needing to look up the alliance repeatedly
--       this_alliance should be the alliance for this_unit; used to determine visibility
--@param this_order_set should be the current order_set for this_unit (we use it to find the desired ending position and the bearing_vector)
function pan_om:find_attack_redirect_effective_distance(this_unit, other_unit, this_alliance, this_order_set)

	if not this_alliance then
		this_alliance = bm:alliances():item(this_unit:alliance_index());
	end;

    --returns self.DONT_ALLOW_REDIRECT for any case that's not allowed; if we reach the end without returning false, we assume we can return true

    if not other_unit:is_valid_target() or other_unit:number_of_men_alive() == 0 then
        return self.DONT_ALLOW_REDIRECT;
    end;

    if self.current_phase < pan_phase.VICTORY_COUNTDOWN then --once victory is declared, shattered units should be valid targets no matter how this is configured
        if not self.can_target_routing_enemies then
            if other_unit:is_routing() then
                return self.DONT_ALLOW_REDIRECT;
            end;
        elseif not self.can_target_shattered_enemies then
            if other_unit:is_shattered() then
                return self.DONT_ALLOW_REDIRECT;
            end;
        end;
    end;

    if other_unit:is_hidden() or not other_unit:is_visible_to_alliance(this_alliance) then
        return self.DONT_ALLOW_REDIRECT;
    end;

    local effective_distance = this_unit:unit_distance(other_unit);
    local allowed_redirect_radius = self.redirect_radius; --this can change if the unit has a ranged attack

    local can_attack_with_range = self:unit_is_in_ranged_mode(tostring(this_unit:unique_ui_id())) and this_unit:ammo_left() > 0 and this_unit:unit_in_range(other_unit);

    if can_attack_with_range then

        if other_unit:is_in_melee() then
            if self.allow_range_to_target_melee then
                effective_distance = effective_distance * self.mult_adjust_range_if_target_in_melee + self.add_adjust_range_if_target_in_melee;
            else
                return self.DONT_ALLOW_REDIRECT;
            end;
        else
            if other_unit:is_currently_flying() then
                effective_distance = effective_distance * self.mult_adjust_ranged_vs_flying + self.add_adjust_ranged_vs_flying;
            end;
        end;

        local missile_range = this_unit:missile_range();
        if missile_range > allowed_redirect_radius then
            allowed_redirect_radius = missile_range;
        end;

    else

        if other_unit:is_currently_flying() then
            if not this_unit:can_fly() then
                return self.DONT_ALLOW_REDIRECT;
            elseif this_unit:is_currently_flying() then
                effective_distance = effective_distance * self.mult_adjust_for_two_flying - self.add_adjust_for_two_flying; --treat two currently flying units as effectively closer to each other
            end;
        end;

		--unit:can_reach_position() is a function that's listed in the documentation
		--but it's coming back as nil for me here as if it doesn't exist
        --we just...ignore this check for now? I'm not sure what else to do, but it's probably ok in non-siege battles
        --conceivably there might be custom maps that have weird situations, too, but players would probably be watching out for that, then
		--if is_function(this_unit.can_reach_position) then
		--	if not this_unit:can_reach_position(other_unit:position()) then
		--		return self.DONT_ALLOW_REDIRECT;
		--	end;
		--end;

    end;

    --if none of the above applies, assume we can attack
    --below we make other effective_distance adjustments before returning

    local this_position = this_unit:position();
    local other_position = other_unit:position();

    --self:debug("this_unit "..tostring(this_unit:name()).." , other_unit "..tostring(other_unit:name()));

    local angle_from_this_to_other = self:find_angle_from_vectors(other_position, this_position);

    --adjust the effective_distance based on the amount this_unit would need to turn to face other_unit
    local anglediff = self:calculate_angle_change_needed(angle_from_this_to_other, self:convert_bearing_to_lua_angle(this_unit:bearing()));

    --if debug_old_target and other_unit:name() == debug_old_target:name() then
        --out("MMMMMMM bearing: "..tostring(self:convert_bearing_to_lua_angle(this_unit:bearing()))..", a_from_this_to_other: "..tostring(angle_from_this_to_other));
        --out("MMMMMMM bearing anglediff: "..tostring(anglediff));
    --end;

    local factor_to_use = (1 + math.abs(anglediff) * self.mult_adjust_for_bearing);
    if factor_to_use > self.max_mult_adjust_for_bearing then
        factor_to_use = self.max_mult_adjust_for_bearing;
    end;

    local addition_to_use = math.abs(anglediff) * self.add_adjust_for_bearing;
    if addition_to_use > self.max_add_adjust_for_bearing then
        addition_to_use = self.max_add_adjust_for_bearing;
    end;

    local effective_dist_b4_adjust = effective_distance;

    effective_distance = effective_distance * factor_to_use + addition_to_use;


    --also adjust the effective_distance based on whether other_unit is in the direction that we ultimately want to be moving
    local desired_position = this_order_set.position;
    local distance_from_desired_location = other_position:distance_xz(desired_position);
    local desired_direction = nil;
    if distance_from_desired_location < self.tolerance_for_arrived_at_position * 2 then --TOCONSIDER: make this magic number a config option?
        --the unit is close to where we want to be anyway, so don't adjust the effective distance
    else
        
        local anglediff = self:calculate_angle_change_needed(angle_from_this_to_other, self:find_angle_from_vectors(desired_position, this_position));

        factor_to_use = (1 + math.abs(anglediff) * self.mult_adjust_for_desired_direction);
        if factor_to_use > self.max_mult_adjust_for_desired_direction then
            factor_to_use = self.max_mult_adjust_for_desired_direction;
        end;

        addition_to_use = math.abs(anglediff) * self.add_adjust_for_desired_direction;
        if addition_to_use > self.max_add_adjust_for_desired_direction then
            addition_to_use = self.max_add_adjust_for_desired_direction;
        end;

        effective_distance = effective_distance * factor_to_use + addition_to_use;
    end;

    local other_is_in_chasing_area = nil;

    if effective_distance > allowed_redirect_radius then

        --if debug_old_target and other_unit:name() == debug_old_target:name() then
            --out("MMMMMM not allowing redirect of "..tostring(this_unit:name()).." against "..tostring(other_unit:name()));
            --out("MMMMMM effective_distance: "..tostring(effective_distance).." compared to allowed_redirect_radius: "..tostring(allowed_redirect_radius));
        --end;

        effective_distance = self.DONT_ALLOW_REDIRECT;

        if effective_distance < (allowed_redirect_radius * self.mult_chasing_adjust + self.add_chasing_adjust) then
            other_is_in_chasing_area = true;
        end;
    end;

    --TOCONSIDER: make sure max_total_adjust_for_bearing_and_dir is nil if not use_max_total...
    --if self.max_total_adjust_for_bearing_and_dir and (effective_distance - effective_dist_b4_adjust) > self.max_total_adjust_for_bearing_and_dir then
    --    effective_distance = effective_dist_b4_adjust + self.max_total_adjust_for_bearing_and_dir;
    --end;

    --TOCONSIDER: also adjust the effective_distance based on whether other_unit is moving away from us?
    --      (less priority if the enemy is moving away; even less if is_moving_fast and is_cavalry or is_flying?)
    --      How long does bearing take to update when a unit's direction changes? This might
    --      cause head-scratching decisions. Consider caching unit positions if it's too long? In any case, save this for later.

    return effective_distance, other_is_in_chasing_area;

end;

function pan_om:try_to_update_movement_speed(unit_to_update, order_set_to_update)
    if unit_to_update:is_moving() then
        order_set_to_update.move_fast = unit_to_update:is_moving_fast();
    end;
end;

function pan_om:might_unit_still_be_in_combat(melee_timestamp)
    if not melee_timestamp then
        return false; --technically the unit could be in melee if it was assigned to this mod while in melee but briefly separated, but that is unlikely and won't hurt anything 
    else
        --if the current timestamp isn't long enough after the last time they were in combat, don't give them new orders because they might still be in combat
        --(or the user configured a resting period or something)
        return timestamp_tick <= melee_timestamp + self.seconds_buffer_after_melee_ends;
    end;
end;

function pan_om:find_angle_from_vectors(target_v, orig_v)
    --local dir_v = target_v - orig_v; -- there's a bug in battle_vector arithmethic that changes the first operand, so we need to break this down
    local x = target_v:get_x() - orig_v:get_x();
    local z = target_v:get_z() - orig_v:get_z();

    local desired_angle = math.deg(math.atan2(x, z));
    return desired_angle;
end;

--TWW2 uses bearings between 0 and 360. Convert that to be between -180 and 180 to match math.atan2
function pan_om:convert_bearing_to_lua_angle(bearing)
    if bearing > 180 then
        bearing = bearing - 360;
    end;

    return bearing;
end;

--finds the angle [-180, 180] degrees, inclusive, that the current_angle would need to turn in order to match desired_angle
--be sure to call this with either two bearings [0, 360] or with two angles [-180, 180]. Either is fine as long as both arguments match.
--note that a unit's bearing does not always match the direction the unit appears to be facing. It appears that the implementation is such that the
--bearing slowly approaches the ordered bearing over a few seconds, even if the unit has already visually turned and is moving in that direction
function pan_om:calculate_angle_change_needed(desired_angle, current_angle)

    local anglediff = desired_angle - current_angle;

    --force anglediff to be between -180 and 180
    if anglediff > 180 then
        anglediff = anglediff - 360;
    elseif anglediff < -180 then
        anglediff = anglediff + 360;
    end;

    return anglediff;
end;

function pan_om:unit_is_in_ranged_mode(ui_id)
    return not self.units_with_changed_melee_mode[ui_id];
end;

function pan_om:update_melee_mode_for_selected_units(melee_was_enabled)

    for_each_unit_card(
        function(uic_card)
            if tostring(uic_card:CurrentState()):lower():find("selected") then
                local ui_id = tostring(uic_card:Id());
                self.units_with_changed_melee_mode[ui_id] = melee_was_enabled;
            end;
        end
    );
end;

function pan_om:check_for_rallied_attack_movers()

    if self.resume_attack_move_once_rallied then
        for ui_id, current_order_set in next, self.attack_move_orders do

            if current_order_set.suspended_due_to_rout then

                local current_friendly_unit = self.map_ids_to_sus[ui_id].unit;

                --this should effectively check is_routing_or_dead, but broken into pieces to allow handling different cases
                if not current_friendly_unit or current_friendly_unit:number_of_men_alive() == 0 or current_friendly_unit:is_shattered() then
                    self:_clear_attack_move_from_unit(ui_id);
                elseif not current_friendly_unit:is_routing() then
                    self:_routing_attack_mover_has_rallied(ui_id);
                end;
            end;
        end;
    end;

end;

--this must be called from a callback, not a shortcut or UI event handler
function pan_om:check_proximity_attacks()
    
    self:check_for_rallied_attack_movers();

    for current_friendly_id, current_order_set in next, self.attack_move_orders do

        local current_friendly_su = self.map_ids_to_sus[current_friendly_id];
        local current_friendly_unit = current_friendly_su.unit;

        --this should effectively check is_routing_or_dead, but broken into pieces to allow handling different cases
        if not current_friendly_unit or current_friendly_unit:number_of_men_alive() == 0 or current_friendly_unit:is_shattered() then

            self:_clear_attack_move_from_unit(current_friendly_id);

        elseif current_order_set.suspended_due_to_rout then

            --intentionally left blank; we already called self:check_for_rallied_attack_movers() above this

        elseif current_friendly_unit:is_routing() then
            
            if self.resume_attack_move_once_rallied then
                self:_mark_unit_as_routing_with_attack_move(current_friendly_id);
            else
                self:_clear_attack_move_from_unit(current_friendly_id);
            end;

        elseif current_friendly_unit:is_in_melee() then

            if self.resume_attack_move_after_combat then
                --self:debug("unit "..tostring(current_friendly_unit:name()).." is_in_melee");
                current_order_set.melee_timestamp = timestamp_tick;
            else
                self:_clear_attack_move_from_unit(current_friendly_id);
            end;

        elseif self:might_unit_still_be_in_combat(current_order_set.melee_timestamp) or current_friendly_unit:is_rampaging() then
            --self:debug("unit "..tostring(current_friendly_unit:name()).." might still be in melee or is rampaging");
            --intentionally left blank
            --skip giving orders to units recently in melee and to rampaging units, but don't remove them from attack_move_orders

        else

            --try to update whether the unit is moving fast or not (it doesn't need to be here necessarily, but this is a convenient place for it)
            self:try_to_update_movement_speed(current_friendly_unit, current_order_set);

			local potential_targets = {}; --array of enemy unit objects
			
			local player_alliance = bm:get_player_alliance();

            local chosen_target = nil;
            local min_distance = self.DONT_ALLOW_REDIRECT - 1;
            local other_is_in_chasing_area = nil;

            for_each_unit_in_alliance(
                bm:get_non_player_alliance(),
                function(current_enemy_unit, current_enemy_army, unit_index_in_army)

                    local tmp_distance;
                    tmp_distance, other_is_in_chasing_area = self:find_attack_redirect_effective_distance(current_friendly_unit, current_enemy_unit, player_alliance, current_order_set);
                    if tmp_distance < min_distance then

                        min_distance = tmp_distance;
                        chosen_target = current_enemy_unit;

                    end;
                end
            );

			if chosen_target then
                --self:debug("ordering an attack against "..tostring(chosen_target:name()));
				local current_uc = current_friendly_su.uc;
                current_uc:attack_unit(chosen_target, nil, true); --Thankfully, this already takes into account whether ranged units are in melee mode
                current_uc:release_control();
				--self:debug("Done ordering attack");
            else
                --if other_is_in_chasing_area then don't reorder any moves unless our unit is effectively idle
                --otherwise, some small variable differences might have us ordering an attack and canceling it in confusing ways
                --we should be safe to not check is_idle over time because we already check if units are in melee over time, which I think is the only false positive
                local should_check_for_reordering_move = not other_is_in_chasing_area or current_friendly_unit:is_idle();

                if should_check_for_reordering_move then

                    local current_position = current_friendly_unit:position();
                    local bearing_diff = math.abs(self:calculate_angle_change_needed(current_order_set.bearing, current_friendly_unit:bearing()));

                    --this won't guarantee we're nicely in formation with the correct width, but I don't think there's a way to check that :(
                    if current_position:distance_xz(current_order_set.position) > self.tolerance_for_arrived_at_position 
                       or bearing_diff > self.tolerance_for_arrived_at_bearing then

                        local current_uc = current_friendly_su.uc;
                        current_uc:goto_location_angle_width(
                                                                current_order_set.position,
                                                                current_order_set.bearing,
                                                                current_order_set.width,
                                                                current_order_set.move_fast
                                                            );
                        current_uc:release_control();

                    elseif current_friendly_unit:is_idle() then --we have nothing to chase, we're idle and we've arrived at our position
                        --TOCONSIDER: Should we check config to see if units should be removed from attack_move_orders once they've arrived?
                        --            If so, we *can* remove the unit from attack_move_orders here with _clear_attack_move_from_unit(ui_id)
                        --                  The thing to watch out for is that doing it here might be confusing to the end user if a unit arrives
                        --                  at a time when an enemy is in the chasing_area.
                    end;
                end;
            end;
        end;
    end;
end;

function pan_om:phase_prebattle()

    self:debug("Starting phase_prebattle");

    if bm:is_tutorial() then pan_om.out("Attack Move mod is disabled for this battle. This battle is a tutorial.") return; end;

    local config_log_msg;
    
    config, config_log_msg = pancake_attack_move_load_config();

    self:debug("After loading config");

    self:init_config_and_calc_values(config);

    if not self.enable_during_siege_battles then
        if bm:is_siege_battle() then pan_om.out("Attack Move mod disabled. Skipping startup. This is a siege battle.") return; end;
    end;

    self.current_phase = pan_phase.STARTUP;

    self:setup_map_ids_to_sus();

    bm:set_volume(VOLUME_TYPE_VO, 0); --turn off the volume for unit responses, since attack and move reorders happen frequently

    if self.add_button_for_attack_move_lock then
        self:debug("Adding battlemod button for attack-move.");

        require("battlemod_button_ext_pan_om");

        self.pan_attack_move_button = battlemod_button_ext:add_battle_order_button("pan_attack_move_button",
                                                                                    self.add_button_for_attack_move_lock == "left",
                                                                                    "ui/templates/square_medium_button_toggle");
        self.pan_attack_move_button:SetImagePath("ui\\pancake_images\\icon_attack_move_no_lock.png", 0);

        function self:set_attack_move_button_state(selection_has_attack_move, any_unit_is_selected)
            if any_unit_is_selected then
                if selection_has_attack_move then
                    self.pan_attack_move_button:SetImagePath("ui\\pancake_images\\icon_attack_move.png", 0);
                    self.pan_attack_move_button:SetState("selected");
                else
                    self.pan_attack_move_button:SetImagePath("ui\\pancake_images\\icon_attack_move_no_lock.png", 0);
                    self.pan_attack_move_button:SetState("active");
                end;
            else
                self.pan_attack_move_button:SetImagePath("ui\\pancake_images\\icon_attack_move_no_lock.png", 0);
                self.pan_attack_move_button:SetState("inactive");
            end;
        end;

        function self:update_attack_move_button_state()

            local has_selection_with_attack_move = false;
            local has_selection_without = false;

            for_each_unit_card(
                function(uic_card)
                    local ui_id = tostring(uic_card:Id());
                    if tostring(uic_card:CurrentState()):lower():find("selected") then
                        if self:has_attack_move_turned_on(ui_id) then
                            has_selection_with_attack_move = true;
                        else
                            has_selection_without = true;
                        end;
                    end;
                end
            );

            local has_any_selection = has_selection_with_attack_move or has_selection_without;

            self:set_attack_move_button_state(has_selection_with_attack_move, has_any_selection);

        end;

        --this could get called whether a unit is selected or deselected
        --(it can get called multiple times if multiple units are selected/deselected)
        function self:respond_to_unit_selections()
            self:update_attack_move_button_state();
        end;

        bm:pan_om_set_listener_for_selections(
            "pan_om_respond_to_selections",
            function(unit, is_selected)
                self:respond_to_unit_selections();
            end
        );

        core:add_listener(
            "pan_attack_move_button",
            "ComponentLClickUp",
            function(context) return context.string == "pan_attack_move_button"; end,
            function()
                pan_om:toggle_attack_move(false);
            end,
            true
        );

        self:set_attack_move_button_state(false, false);
    end;

    self:add_configured_hotkey_listener(
        "pan_om_attack_move_listener",
        config.hotkey_for_attack_move_lock,
        "camera_bookmark_save6",
        function()
            local current_phase = pan_om.current_phase;
            if current_phase >= pan_phase.DEPLOYMENT and current_phase < pan_phase.COMPLETE then
                pan_om:toggle_attack_move(false);
            end;
        end
    );

    bm:register_command_handler_callback(
        "Change Melee",
        function(event)
            local melee_was_enabled = event:get_bool1();
            self:update_melee_mode_for_selected_units(melee_was_enabled);
        end,
        "pan_om_melee_mode_change_listener"
    );

    bm:register_phase_change_callback("Deployment", function() pan_om:phase_deployment(); end);
    bm:register_phase_change_callback("Deployed", function() pan_om:phase_deployed() end);
    bm:register_phase_change_callback("VictoryCountdown", function() pan_om.current_phase = pan_phase.VICTORY_COUNTDOWN end);

    -------------------------------------------------------------------------------------------------------------------------------
    --- Global API functions for cross-compatibility
    ---       This allows for compatibility between mods that need to use unit_controller objects
    ---       unit_controllers get confused if one takes control while another is still active with the same unit
    ---       there's nothing special about these functions otherwise; paperpancake made them up when he needed them
    -------------------------------------------------------------------------------------------------------------------------------

    --Important! Only call this function from within a callback of somekind.
    --If you want to call this during a UI-related event, such as ShortcutTriggered or ComponentLClickUp, you first
    --need to wrap the functionality in a bm:callback (you can use a callback with 0 ms.)
    --This function should cause all participating mods to have any unit_controllers release control over units
    --with unique_ui_ids given within the @param table_of_ui_ids
    --so we need a way to let other mods tell us to release control if their unit_controllers are about to take control
    --this currently could be called multiple times in a row with different table_of_ui_ids
    local original_uc_function_for_mods = modder_API_release_uc_for_ids;
    modder_API_release_uc_for_ids = function(table_of_ui_ids, key_of_requesting_mod)

        --pan_om:debug("In modder_API_release, #table is: "..tostring(#table_of_ui_ids).." and key is "..tostring(key_of_requesting_mod));
        
        --this is where I do what I need to for this mod
        if key_of_requesting_mod ~= this_mod_key then
            pan_om:debug("Doing modder_API for "..tostring(this_mod_key));
            pan_om:set_attack_move_for_units(table_of_ui_ids, false, true);
        end;

        --send the function call along to any other participating mods, as well
        if is_function(original_uc_function_for_mods) then
            original_uc_function_for_mods(table_of_ui_ids, key_of_requesting_mod);
        end;
    end;

    -------------------------------------------------------------------------------------------------------------------------------
    
	self:debug("End of prebattle setup");
end;

--This is a helper function that takes care of the details of adding a hotkey listener based on config values
--(creating the listener's functions using this function's parameters works because of closures and upvalues, in case you wondered)
function pan_om:add_configured_hotkey_listener(listener_key, config_setting, default_hotkey_string, function_for_hotkey)
    
    --Note that this listener is only added if the user has set this configuration option
    --config.use_hotkey_to_exclude_unit could be set to true or to a string key indicating the hotkey
    local hotkey_string = default_hotkey_string; -- save(#) appears in the game as save(# + 1)
    if config_setting then

        if is_string(config_setting) and config_setting ~= "true" then
            hotkey_string = config_setting;
        end;

        core:add_listener(
            listener_key,
            "ShortcutTriggered",
            function(context) return context.string == hotkey_string; end,
            function_for_hotkey,
            true
        );
    end;
end;

function pan_om:phase_deployment()
    self.current_phase = pan_phase.DEPLOYMENT;
end;

function pan_om:phase_deployed()
    self.current_phase = pan_phase.DEPLOYED;

    --Update all the order_set (positions, widths, etc). That way if the user sets countercharge in deployment
    --and then changes their troops locations before starting the battle, we will have the updated info.
    local copy_of_attack_move_table = shallow_copy_simple_table(self.attack_move_orders);
    self:set_attack_move_for_units(copy_of_attack_move_set, true, false);

    self:debug("Starting repeat callback for proximity check.");
    bm:repeat_callback(function() self:check_proximity_attacks() end, self.seconds_between_attack_move_checks, "pan_check_proximity_attacks");
end;

bm:register_phase_change_callback("PrebattleWeather", function() pan_om:phase_prebattle() end); --this kicks everything else off

--[[
Old notes to self when I was trying to make this mod automatically respond to user-given orders:

The unit_controller commands to attack are incorrectly clearing units from the attack_move list
Try having an intermediate method that ignores attack commands, etc, unless the root was recently clicked?
BUT that doesnt account for movement given by hotkeys, etc
Can we instead filter out attacks and other commands made by unit controllers? We could probably do that for this mod, but
it might get super messy to try to do that for other mods as well
and what about commands from rampaging units. Would those be affected as well?
You might just have to have a toggle instead, where the toggle acts permanently until turned off
If so, you need a visual indicator, so you probably want to add buttons,
or figure out how to overlay a color or image over the unit cards (keep in mind that the user could change the unit card's order)
We still need to know what the original order was, and that order could change

Ordered position appears to not change at all when an attack move is given, even as the unit is moving

When unit_controller gives orders, create an exception list
    ignore_commands[unit_id] = target (either order set or a target unit for an attack order, and possibly a flag for just ignoring everything from AI General II)
    When responding to commands and looping through the seclected unit cards, ignore selected unit cards of rampaging units/is_routing_or_dead, and also ignore selected unit cards matching both unit_id and target
    (This has a potential hole, where the user is giving an identical order to the identical unit selection that's being processed at the exact same time with the opposite attack move-state.
    But the probability of that happening is so small and this is the only way I can think to implement this.)

Best idea I have now:
    Set ignore_next_move_command or ignore_next_attack_command whenever issuing an order through a unit_controller
    The problem is I don't know if a user could give an attack or move command at the same time
    I also don't know if rampaging attack orders cause the listener to fire, which would still throw things off

    Thought: could I cache all the current orders (how to tell if an attack order was given?)
             and then compare orders for each unit to see which ones changed, and ignore rampaging units?
             That might be computationally intensive, but might be worth a shot
             Also get AI General II's list and ignore orders given to those units

             For attack orders, can we compare the attack order just given to the unit_controller's attack order?
             Theoretically, another unit could also have been told to attack the same target at the same time, but that
             is a smaller chance?
]]--
