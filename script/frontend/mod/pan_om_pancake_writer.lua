
package.path = "/script/pancake_lib/?.lua;" .. package.path
require("pan_om_config_loader");

local pancake_default_config_text = 
[[
-- Anything that starts with a -- is a comment.
-- Comments are just notes to yourself. They don't do anything.
-- You can add, change, or delete comments all you'd like.
-- I put my comments above or on the line they refer to.

----------------------------------------------------------------------------------------------
-- This option allows you to change this mod's primary hotkeys or get rid of them altogether
-- You probably don't need to edit this unless you need it for another mod or you need
-- a lot of camera bookmark hotkeys and wish this mod didn't use so many.
-- Set these to true to use the hotkey in the mod's description ("Save Camera Bookmark 12")
-- Set this to false to not use the hotkey at all
-- Or you can set this to one of the allowed modding hotkeys (F2 to F4) like "script_shift_F2"

hotkey_for_attack_move_lock = true

----------------------------------------------------------------------------------------------
-- Do you want this mod to add a button to the bottom bar? I recommend it, since this is
-- currently the only visual indication that a unit has an attack-move lock.
-- Use "right", "left", or false

add_button_for_attack_move_lock = "right"

----------------------------------------------------------------------------------------------
-- About how close should an enemy be to your melee units before your unit gets an attack order?
-- (The effective distance between units can get modified for this mod in specific situations;
-- see the other options below.) 

redirect_radius = 64

----------------------------------------------------------------------------------------------
-- This controls how often this mod checks for nearby targets and updates orders for units
-- under its control

seconds_between_attack_move_checks = 0.7

----------------------------------------------------------------------------------------------
-- Should attack-moving units consider routing and/or shattered enemies to be
-- valid targets before victory is declared? (Once victory is declared, all enemies are shattered, so
-- this mod assumes they can be targets at that point).

can_target_routing_enemies = true
can_target_shattered_enemies = false

----------------------------------------------------------------------------------------------
-- When your attack-moving unit gets into melee, the attack move is either suspended or canceled
-- Once the melee is finished, should the attack move be automatically resumed?

resume_attack_move_after_combat = true

----------------------------------------------------------------------------------------------
-- When your attack-moving unit starts to flee, the attack move is either suspended or canceled
-- If that unit rallies, should the attack move be automatically resumed?

resume_attack_move_once_rallied = false

----------------------------------------------------------------------------------------------
-- !!!WARNING!!!: This option is experimental and certainly not polished. Giving attack-move orders
--                during siege battles might cause strange behavior when your units are on or
--                within the redirect_radius distance of a wall, especially for units that
--                can't climb walls, like cavalry.

enable_during_siege_battles = false

----------------------------------------------------------------------------------------------
-- These settings allow your units to prioritize enemies they are directly facing (to hopefully
-- reduce clumping and make things more intuitive). Enemies at an angle are gradually considered further away.
-- For multiplicative adjustments, 1 results in no adjustment
-- For additive adjustments, 0 results in no adjustment

angle_for_max_bearing_adjustment = 45
max_mult_adjust_for_bearing = 1.4
max_add_adjust_for_bearing = 10

----------------------------------------------------------------------------------------------
-- These settings allow your units to prioritize enemies that are on the way to their ordered position.
-- Targets at an angle are gradually considered further away.
-- For multiplicative adjustments, 1 results in no adjustment
-- For additive adjustments, 0 results in no adjustment

angle_for_max_desired_direction_adjustment = 90
max_mult_adjust_for_desired_direction = 1.3
max_add_adjust_for_desired_direction = 0

----------------------------------------------------------------------------------------------
-- These settings allow your units in the air to prefer attacking enemy units in the air
-- by using negatives for the additive adjustment and/or a value less than 1 for the multiplicative
-- For multiplicative adjustments, 1 results in no adjustment
-- For additive adjustments, 0 results in no adjustment

mult_adjust_for_two_flying = 1
add_adjust_for_two_flying = -20

----------------------------------------------------------------------------------------------
-- These settings allow your ranged units to prefer attacking enemy units in the air
-- by using negatives for the additive adjustment and/or a value less than 1 for the multiplicative
-- This adjustment will only be made if the enemy flier is not in currently in melee.
-- For multiplicative adjustments, 1 results in no adjustment
-- For additive adjustments, 0 results in no adjustment

mult_adjust_ranged_vs_flying = 1
add_adjust_ranged_vs_flying = -20

----------------------------------------------------------------------------------------------
--  This modifies the redirect_radius when chasing.
--  I highly recommend that there is at least some amount of chasing adjust
--  Set this higher if you want to allow your units to chase enemies further
--  (For example, setting this to 2 will allow units to chase enemies until they are twice as far away)

mult_chasing_adjust = 1.1
add_chasing_adjust = 5

----------------------------------------------------------------------------------------------
-- Attack-moving ranged units will target the closest enemy unit, but you can modify how this mod
-- perceives the effective distance of enemies that are in melee so they are prioritized less.
-- This lowers the chance of friendly fire, but those enemies could still be considered valid targets
-- eventually unless you set allow_range_to_target_melee to false

allow_ranged_to_target_melee = true
mult_adjust_ranged_if_target_in_melee = 1.1
add_adjust_ranged_if_target_in_melee = 50

----------------------------------------------------------------------------------------------
-- When your unit finishes a melee engagement, how many seconds should it wait before charging
-- another enemy or returning to its post? You can increase this if you want units to rest a bit.
-- Setting this too low (lower than maybe 1.2 or so?) might result in your units sometimes
-- switching targets during battle if there are multiple nearby enemy units.

seconds_buffer_after_melee_ends = 1.4

----------------------------------------------------------------------------------------------
-- This position tolerance is large because the game's ordered_positions for cavalry
-- refer to the front of the unit whereas their position vector refers to the center
-- The bearing tolerance is in degrees.

tolerance_for_arrived_at_position = 25
tolerance_for_arrived_at_bearing = 10

]]

local pancake_20XX_XX_update_text = 
[[
----------------------------------------------------------------------------------------------
--        ******* New for &&&&& Future Date &&&&& *********
----------------------------------------------------------------------------------------------

-- Future update stuff goes here. Be sure to also edit pancake_update_config_file_if_needed(), below

]]

local config_filename = "./mod_config/attack_move_config.txt";

--@param a config table that reflects the current environmnet state (variables and their values) that are in the config file
local function pancake_update_config_file_if_needed(config)

    --[[    This is commented out because there are not yet any updates to check for 
    local text_to_append = "";

    --update for XXXX-XX
    if config.XXXX == nil
            and config.XXXX == nil then
        text_to_append = text_to_append .. pancake_XXXX_XX_update_text;
    end;

    if text_to_append ~= "" then
        local file, err_str = io.open(config_filename, "a");
        if file then
            file:write("");
            file:write(text_to_append);
            file:close();
            out("&&&& added an update to the end of "..tostring(config_filename));
        else
            out("&&&& Could not update the config file at "..tostring(config_filename));
            out("&&&& "..tostring(err_str));
        end;
    end;
    ]]--
end;

--don't call this function if the file already exists
local function pancake_write_default_file(config_filename)

    local file, err_str = io.open(config_filename, "w");
    if file then
        file:write(pancake_default_config_text);
        file:close();
        out("&&&& created default config file: "..config_filename);
    else
        --out("&&&& pancake could not write the config file. Perhaps the folder doesn't exist.\n"..tostring(err_str));
    end;
end;

local load_success, file_found, msg;
local config;

--TODO: Ideally this would inform the user if there was an error in their config file, but can we use the advisor on the front end?
--      If not, we can always try to make our own dialog

--set default values before loading the config file
config = {};

load_success, file_found, msg, config = pancake_config_loader.load_file(config_filename, config);

if load_success then
    pancake_update_config_file_if_needed(config);
else
    if not file_found then
        pancake_write_default_file(config_filename);
    else
        out("&&&& "..config_filename.." was found, but it could not be read perhaps due to an error in it.");
        out("&&&& The message: "..tostring(msg));
    end;
end;
