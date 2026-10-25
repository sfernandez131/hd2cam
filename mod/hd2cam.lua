-- HD2CAM: over-the-shoulder camera and mouse-look aiming for Helldivers 1.
--
-- Installed in place of foundation/lua/build_date_information, which the
-- game requires very early during boot. We first do what that file did,
-- then wrap `require` so we can patch game classes as soon as they load.

_G.BUILD_DATE_INFORMATION = "2020-12-22 09:33:14"

if rawget(_G, "HD2CAM") then
	return
end

local VERSION = "1.1.0"

local M = {
	version = VERSION,
	enabled = true,
	toggle_key = "f8",
	status_log = false, -- every-5-second status lines in hd2cam.log (diagnostics only)
	perf_log = false,   -- log frame hitches (and a 30 s summary) to hd2cam.log (diagnostics)

	-- Camera rig. Angles are in degrees.
	distance = 5.0,      -- metres behind the player
	height = 1.7,        -- metres above the player's feet
	shoulder = 0.9,      -- metres to the right
	pitch = 12,          -- starting tilt (positive looks down)
	aim_pitch_reset = true, -- releasing aim eases the tilt back to this
	min_pitch = -10,
	max_pitch = 70,
	sensitivity = 0.15,  -- degrees per mouse count
	invert_y = false,
	aim_distance = 100,  -- crosshair ray length when it hits nothing
	min_aim_distance = 3, -- closer hits than this fall back to the camera direction
	pin_cursor = true,   -- keep the OS cursor centred so it acts as a crosshair
	bridge_camera = true, -- also use the over-the-shoulder camera on the ship's bridge

	-- Combat facing (HD2 style): while aiming, firing or throwing, the body
	-- turns to the crosshair; otherwise it turns toward where it is running.
	combat_linger = 0.6, -- seconds to keep facing the crosshair after firing
	-- The game turns the body by keeping (value ^ frame_time) of the old
	-- facing each frame: 0 snaps instantly, 1 never turns.
	combat_turn_retention = 0,

	camera_collision = true, -- pull the camera in rather than clip into rocks
	camera_min_distance = 1.2,
	-- How quickly the camera closes on its goal, per second. The body moves
	-- in physics and network steps; a camera glued to it (0 = snap, the old
	-- behaviour) shows every step as judder. Higher follows more tightly.
	camera_smoothing = 30,

	-- Controller: right stick turns the camera, left trigger aims.
	pad_remap = true,          -- HD2-style button layout (see remap_pad_bindings)
	pad_yaw_speed = 220,       -- degrees per second at full stick
	pad_pitch_speed = 130,
	pad_deadzone = 0.15,
	pad_aim_slowdown = 0.5,    -- camera speed multiplier while aiming
	pad_invert_y = false,
	pad_aim_threshold = 0.3,   -- left trigger travel that counts as aiming
	crosshair_size = 32,       -- pixels

	-- View distance. The top-down camera never needed to see far, so levels
	-- fade out close by. Scale the level's own fog distances and push the
	-- camera's far clip plane out to match.
	fog_scale = 6,       -- default; see fog_scale_by_environment
	fog_scales = { 6, 3, 1 }, -- F7 cycles these in a mission
	-- Per planet type (desert, forest, snow, lava, city, provinggrounds).
	-- Burning cities are dense and heavy to draw far out; open ground isn't.
	fog_scale_by_environment = { city = 3, lava = 3 },
	sky = true,           -- draw a sky dome (F9 toggles in a mission)
	sky_distance = 850,   -- metres; between the fog end and the far clip plane
	sky_day_luminance = 3.0, -- fog this bright or more keeps the engine dome at full brightness (fog is HDR)
	sky_min_brightness = 0.08, -- darkest the engine dome gets
	-- Dome brightness by the level's time of day, on top of the fog luminance.
	sky_time_brightness = { dawn = 0.55, day = 1, dusk = 0.45, night = 0.12 },
	far_range = 600,
	-- Depth of field blurs everything past the top-down focus distance, and
	-- smears it into the empty sky when the camera turns. Off in missions;
	-- the player's own setting is restored on the ship and with F8.
	disable_dof = true,

	vertical_aim = false, -- tilt shots up/down toward the crosshair (off: level shots, as HD1)
	max_shot_pitch = 60, -- degrees up or down a shot can be tilted toward the crosshair
	mark_reach_distance = 8, -- metres: reaching your map mark clears it
	ping_distance = 300,     -- metres: how far a ping reaches
	compass = true,
	compass_width = 460,  -- design pixels (HUD is laid out at 1280x720)
	compass_span = 180,   -- degrees of heading shown across the bar
	compass_top = 46,     -- distance from the top of the screen

	range_scale = 2.0,    -- weapon range multiplier (firearms, beams, launchers, flamers)
	aim_zoom = 0.75,      -- field of view multiplier while aiming
	shoulder_key = "c",   -- swap shoulder (controller: R3 while aiming); V is push-to-talk in HD1
	recoil_kick = 0.6,    -- degrees the camera kicks up per shot
	recoil_recover = 7,   -- how fast the kick settles
	reticle_hud = true,   -- ammo, hit markers and throw range by the crosshair
	ping_button = "middle", -- mouse button that pings (controller: D-pad up without LB)
	compass_objectives = true,
	compass_teammates = true,
	compass_enemies = true, -- radar-detected enemy patrols on the compass
	aim_spread_scale = 0.35, -- weapon spread multiplier while aiming
	hip_spread_scale = 0.75, -- and when firing from the hip

	-- HD2 feel. Each of these is its own switch.
	aim_distance_scale = 0.7,   -- camera distance while aiming, as a share of `distance`
	aim_shoulder_scale = 1.3,   -- shoulder offset while aiming
	aim_sensitivity = 0.6,      -- mouse sensitivity multiplier while aiming (pads: pad_aim_slowdown)
	-- HD1 creeps while aiming (base aim speed x the weapon's own factor, a
	-- crawl with heavy weapons); HD2 walks. Multiplier on the speed the
	-- character hands the mover while in the aim and fire states.
	aim_walk_speed = 2.0,
	sprint_distance_scale = 1.15, -- the camera pulls back a little while sprinting
	sprint_fov = 1.06,          -- and the view widens
	prone_height = 0.9,         -- camera height while downed (prone)
	auto_center = true,         -- running with the look input idle eases the view behind you
	auto_center_sprint_only = true, -- HD2 leaves the camera alone; only while sprinting, and gently
	auto_center_delay = 2.0,    -- seconds without look input first
	auto_center_rate = 0.8,     -- how quickly it swings behind (share of the gap per second)
	camera_shake = true,        -- the game's own camera shaker, on explosions and when hit
	explosion_shake = "grenade", -- CameraShakeSettings presets
	hit_shake = "pistol",
	dynamic_crosshair = true,   -- reticle ticks open with the weapon's spread
	weapon_panel = true,        -- ammo, magazines and fire mode, bottom right
	damage_arcs = true,         -- red arc around the reticle toward whatever hit you
	throw_arc = true,           -- grenade / stratagem arc to the crosshair while holding a throw
	throw_to_crosshair = true,  -- mouse throws land on the crosshair point (the game aims them at the cursor)
	stratagem_panel = false,    -- HD2-style stratagem list with arrow codes, replacing the game's (off: the game's own list)
	death_cam = true,           -- dead: follow a living teammate, else orbit your body
	pad_aim_assist = true,      -- controller: the camera slows while the reticle is on an enemy
	aim_assist_radius = 1.6,    -- metres around the crosshair point
	aim_assist_slowdown = 0.45,
	ping_callout = true,        -- pinging also sends the "move" voice callout

	-- Graphics. Renderer settings the options menu never shows, applied for
	-- the session only (your saved settings are untouched) and put back when
	-- the mod is off; each one is logged. Shadow map size isn't here: the
	-- engine reads it at startup from the graphics menu's own option.
	renderer_settings = {
		ssao_enabled = true, particles_cast_shadows = true,
		-- Batch two, each logged as accepted or refused. Tessellation detail
		-- and triangle size (the saved values are 1 and 8), the scatter and
		-- decoration density and object LOD multiplier the executable names,
		-- and reflection cubemaps.
		g_tessellation_detail = 2, g_tessellation_tri_size = 4,
		lod_scatter_density = 2, lod_decoration_density = 2, lod_object_multiplier = 2,
		generate_cubemap = true,
		-- Global illumination (voxel cone tracing): very heavy if it still
		-- works at all; flip to true to find out.
		voxel_cone_tracing = false,
	},
	aim_dof = true,             -- depth of field focused on the crosshair while aiming (overrides disable_dof)
	aim_dof_amount = 0.7,       -- 0..1
	-- Fog colour multipliers per planet type (the level's own fog, tinted).
	fog_grading = {
		desert = { 1.08, 0.98, 0.85 }, snow = { 0.9, 0.98, 1.12 }, forest = { 0.95, 1.05, 0.9 },
		city = { 0.95, 0.95, 1.05 }, lava = { 1.15, 0.9, 0.8 },
	},
	fog_grading_strength = 1,   -- 0 = off, 1 = as listed, more = stronger
	hit_vignette = true,        -- red edges when you take damage
	compass_enemy_range = 45,   -- metres: enemies this close and in view show on the compass
	compass_enemy_los = true,   -- only enemies with a clear line from you (HD2 shows spotted ones)
	-- Weather on any planet: "auto" picks by planet type from weather_effects,
	-- "off" none, or a planet type / effect path to force one.
	weather = "auto",
	weather_effects = {
		desert = "effects/generated/camera_desert_wind",
		forest = "effects/generated/camera_forest_light_rain",
		snow = "effects/generated/camera_snow_light_snow",
		city = "effects/generated/camera_city_embers",
		lava = "effects/generated/camera_city_embers",
	},
	-- Ambient dressing around objectives: burning debris, from the one
	-- looping effect every mission has loaded. Particles carry no logic, so
	-- this cannot crash. Gear units (crates, wire, barricades, the crashed
	-- shuttle) run their own flow scripts when spawned and the engine died a
	-- few seconds after a batch of them; a unit goes in prop_units only once
	-- it has been spawned on its own and survived a mission (each spawn is
	-- logged by name so a crash can be pinned).
	ambient_props = true,
	prop_effects = { "effects/generated/status_fire" },
	props_per_objective = 3,
	prop_units = {},
	prop_wreck = nil,
	-- In-game settings menu (saved to hd2cam.cfg next to the log).
	menu_key = "insert",        -- opens / closes it (controller: L3 + R3 together)
	prone_fire = true,          -- firing while prone (crawl) or downed shoots
	prone_key = "z",            -- keyboard: go prone / stand up without diving (controller: hold dive)
	prone_hold = 0.35,          -- seconds: hold the dive button this long to go prone instead (HD2); a tap dives
	-- Escort NPCs are killed off after a while out of the camera's view (a
	-- top-down rule; with a free camera they're out of view constantly).
	escort_offscreen_safe = true,

	-- Bend the upper body toward the crosshair while aiming, so the arms and
	-- gun visibly point up or down. Spread across the spine joints, most at
	-- the chest; legs stay planted.
	spine_bend = false,   -- the engine won't let scripts override the animated pose (tested)
	spine_max = 45,       -- degrees
	spine_smooth = 14,    -- how quickly the bend follows the aim
	spine_sign = 1,       -- flip to -1 if the body leans the wrong way

	-- Runtime state.
	yaw = nil,
	saved = nil,
	clock = 0,
	combat_until = 0,
	player_unit = nil,
	stats = { frames = 0, aim_set = 0, aim_zero = 0, aim_hip = 0, ray_hit = 0, t = 0 },
}
_G.HD2CAM = M

-- The retail build may not write a console log, so also keep our own file:
-- %APPDATA%\Arrowhead\Helldivers\hd2cam.log
local log_file
pcall(function()
	log_file = io.open(os.getenv("APPDATA") .. "\\Arrowhead\\Helldivers\\hd2cam.log", "w")
end)

local function log(fmt, ...)
	local line = "[hd2cam] " .. string.format(fmt, ...)
	print(line)
	if log_file then
		pcall(function()
			log_file:write(os.date("%H:%M:%S "), line, "\n")
			log_file:flush()
		end)
	end
end

local error_counts = {}

-- Frame-time diagnostics (perf_log); see "Frame timing" further down.
local SKY_MODE_NAME -- defined with the sky code
local clock = os.clock
local perf = {
	depth = 0, mod = 0, sections = {}, update = 0, render = 0,
	win_t = 0, win_frames = 0, win_hitches = 0, win_mod = 0, win_mod_max = 0,
	win_alloc = 0, win_worst = 0, win_ms = 0,
	win_slow = 0, win_over16 = 0, win_sec_max = {},
}

local function try(where, f, ...)
	-- Time top-level sections only (nested ones are part of their caller).
	local t0
	if M.perf_log and perf.depth == 0 then
		perf.depth = 1
		t0 = clock()
	end
	local ok, err = pcall(f, ...)
	if t0 then
		local ms = (clock() - t0) * 1000
		perf.depth = 0
		perf.mod = perf.mod + ms
		perf.sections[where] = (perf.sections[where] or 0) + ms
	end
	if not ok then
		-- Most hooks run every frame; log the first few failures only.
		local n = (error_counts[where] or 0) + 1
		error_counts[where] = n
		if n <= 3 then
			log("error in %s: %s%s", where, tostring(err), n == 3 and " (further errors here not logged)" or "")
		end
	end
	return ok, err
end

local hooks = {}

-- Which game tables we have already patched. Kept here rather than as
-- fields on the game's tables, since game code may iterate those.
local patched = setmetatable({}, { __mode = "k" })

local function is_patched(t, what)
	return patched[t] ~= nil and patched[t][what] == true
end

local function mark_patched(t, what)
	patched[t] = patched[t] or {}
	patched[t][what] = true
end

local function run_hooks(name)
	local list = hooks[name]
	if list then
		for _, h in ipairs(list) do
			try("hook " .. name, h)
		end
	end
end

local function after_require(name, ...)
	run_hooks(name)
	return ...
end

local original_require = require
_G.require = function(name, ...)
	return after_require(name, original_require(name, ...))
end

local function on_require(name, f)
	hooks[name] = hooks[name] or {}
	table.insert(hooks[name], f)
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- Key indices never change; look each name up once (several keys are
-- polled every frame).
local key_index = {}

local function key_pressed(name)
	local idx = key_index[name]
	if idx == nil then
		idx = Keyboard.button_index(name) or false
		key_index[name] = idx
	end
	return idx and Keyboard.pressed(idx)
end

local function in_game_cursor()
	-- The in-mission pause menu shows the menu cursor; leave the mouse alone
	-- while that is up. On a controller the game keeps the menu cursor set
	-- but hidden during play, so only a *visible* menu cursor counts.
	if not CursorManager or not CursorManager.get_current_cursor then
		return true
	end
	local cur = CursorManager:get_current_cursor()
	if cur == nil or cur == "hud/cursors/game" or cur == "hud/cursors/game_inactive" then
		return true
	end
	return CursorManager.is_shown ~= nil and not CursorManager:is_shown()
end

-- Mod on? F8 (enabled) and the co-op check: in a session with anyone who
-- doesn't have the mod, everything stays vanilla (see "Co-op" below).
function M.on()
	return M.enabled and not M.coop_blocked
end

-- On the ship's bridge the camera runs in "follow_menu"; the mod drives it
-- too (see the camera hook), so that counts as active as well.
local function camera_active()
	local state = CameraManager and CameraManager.state
	-- The bridge (its camera is briefly presented as "follow" while the mod
	-- drives it) follows F8 only; the co-op check is for missions.
	if M.on_bridge or state == "follow_menu" then
		return M.enabled and M.on_bridge and in_game_cursor()
	end
	return M.on() and state == "follow" and in_game_cursor()
end

local function flat_forward(yaw)
	return Vector3(-math.sin(yaw), math.cos(yaw), 0)
end

-- One eased step from cur toward want (k = share of the gap per frame).
local function ease(cur, want, k)
	cur = cur or want
	return cur + (want - cur) * k
end

local PAD_RIGHT_STICK = { "right" }

local function flat_right(yaw)
	return Vector3(math.cos(yaw), math.sin(yaw), 0)
end

---------------------------------------------------------------------------
-- Controller
---------------------------------------------------------------------------

-- Raw device for a pad number (1..n); 0 is keyboard and mouse.
local function pad_device(pad_number)
	local pads = rawget(_G, "Pads")
	return pad_number and pad_number > 0 and pads and pads[pad_number] or nil
end

-- Pads name their buttons differently (xbox, ps4, ...); use the first name
-- this device knows.
local PAD_INDEX_OF = { button = "button_index", axis = "axis_index" }

local function pad_value(pad, kind, names)
	local index_of = pad[PAD_INDEX_OF[kind]]
	for _, name in ipairs(names) do
		local ok, idx = pcall(index_of, name)
		if ok and idx then
			return pad[kind](idx)
		end
	end
end

local function pad_pressed(pad, names)
	for _, name in ipairs(names) do
		local ok, idx = pcall(pad.button_index, name)
		if ok and idx then
			return pad.pressed(idx)
		end
	end
	return false
end

local function mouse_pressed(name)
	local ok, idx = pcall(Mouse.button_index, name)
	return ok and idx and Mouse.pressed(idx) or false
end

local function stick_curve(v)
	local a = math.abs(v)
	if a < M.pad_deadzone then
		return 0
	end
	local t = (a - M.pad_deadzone) / (1 - M.pad_deadzone)
	return (v < 0 and -1 or 1) * t * t
end

local function pad_aiming(pad)
	local lt = pad and pad_value(pad, "button", { "left_trigger", "l2", "l2_trigger" })
	return lt ~= nil and lt > M.pad_aim_threshold
end

-- HD2-style layout, applied to every pad's default bindings. Each pad type
-- names buttons differently, so read this pad's name for each physical
-- button from the stock binding that uses it, then move the actions.
--   LT aim (handled by the mod) | RT fire          | LB stratagems (unchanged)
--   RB grenade                  | X reload         | B dive
--   R3 melee                    | A interact, Y switch weapon, L3 sprint (unchanged)
-- Lists already remapped. Kept here, not as a field on the list: the game
-- walks every field of a binding list and expects each to be a binding.
-- Several pads can share one list, so this also prevents double remaps.
local remapped_lists = setmetatable({}, { __mode = "k" })
local remap_originals = setmetatable({}, { __mode = "k" })

local function remap_pad_bindings(bindings)
	for name, list in pairs(bindings) do
		if type(list) == "table" and string.sub(name, 1, 3) == "pad" and not remapped_lists[list] then
			local key_of = {}
			for _, e in ipairs(list) do
				if e.func ~= "filter" and e.output_name then
					key_of[e.output_name] = key_of[e.output_name] or e.key
				end
			end
			local lt, rb, x, b, r3 = key_of.throw, key_of.reload_button, key_of.dodge_button, key_of.melee, key_of.reserved
			local move = {
				throw = rb,
				reload_button = x,
				reload_pressed = x,
				reserved = x,
				dodge_button = b,
				melee = r3,
			}
			if lt and rb and x and b and r3 then
				local originals = {}
				for _, e in ipairs(list) do
					if e.func ~= "filter" and move[e.output_name] then
						originals[e] = e.key
						e.key = move[e.output_name]
					end
				end
				remap_originals[list] = originals
				remapped_lists[list] = true
				log("remapped %s (LT %s, RB %s, X %s, B %s, R3 %s)", name, lt, rb, x, b, r3)
			else
				log("skipped remapping %s: stock layout not recognised", name)
			end
		end
	end
end

on_require("lua/utility/input_rebinder", function()
	local ir = InputRebinder
	if is_patched(ir, "setup") then
		return
	end
	local original = ir.setup
	mark_patched(ir, "setup")
	ir.setup = function(self, bindings, ...)
		if type(bindings) == "table" then
			M.last_bindings = bindings
			if M.pad_remap and not M.pad_remap_suspended then
				try("pad remap", remap_pad_bindings, bindings)
			end
		end
		return original(self, bindings, ...)
	end

	-- Switch the HD2 layout off (vanilla session) or back on, by restoring
	-- or re-applying the bindings and re-running the game's own setup.
	function M.set_pad_remap(on)
		if M.pad_remap_on == on or not M.last_bindings then
			return
		end
		M.pad_remap_on = on
		M.pad_remap_suspended = not on
		if not on then
			for list, originals in pairs(remap_originals) do
				for e, key in pairs(originals) do
					e.key = key
				end
				remapped_lists[list] = nil
			end
			remap_originals = setmetatable({}, { __mode = "k" })
		end
		local ok, err = pcall(ir.setup, ir, M.last_bindings)
		log("controller layout: %s%s", on and "HD2" or "vanilla", ok and "" or (" (setup failed: " .. tostring(err) .. ")"))
	end
	M.pad_remap_on = true
	log("pad remap hook installed")
end)

---------------------------------------------------------------------------
-- Camera
---------------------------------------------------------------------------

local function save_camera(cm)
	if M.saved then
		return
	end
	local o = cm.follow_offset
	M.saved = {
		follow_spin = cm.follow_spin,
		follow_angle = cm.follow_angle,
		follow_distance = cm.follow_distance,
		min_follow_distance = cm.min_follow_distance,
		max_follow_distance = cm.max_follow_distance,
		fov = cm.fov,
		follow_position_interp = cm.follow_position_interp,
		ignore_level_bounds = cm.ignore_level_bounds,
		-- nil when the game had no offset table: the camera update makes
		-- one, and restoring must take it away again (the game adds
		-- (x - 1, y - 1) from any table it finds).
		offset = o and { x = o.x, y = o.y, z = o.z } or nil,
		look_ahead = {},
	}
end

local function restore_camera(cm)
	local s = M.saved
	if not s then
		return
	end
	cm.follow_spin = s.follow_spin
	cm.follow_angle = s.follow_angle
	cm.follow_distance = s.follow_distance
	cm.min_follow_distance = s.min_follow_distance
	cm.max_follow_distance = s.max_follow_distance
	cm.follow_position_interp = s.follow_position_interp
	if s.fov then
		cm.fov = s.fov
	end
	cm.ignore_level_bounds = s.ignore_level_bounds
	if not s.offset then
		cm.follow_offset = nil
	elseif cm.follow_offset then
		cm.follow_offset.x, cm.follow_offset.y, cm.follow_offset.z = s.offset.x, s.offset.y, s.offset.z
	end
	for _, props in pairs(cm.targets or {}) do
		if s.look_ahead[props] then
			props.look_ahead = s.look_ahead[props]
		end
	end
	M.saved = nil
	M.yaw = nil
	M.cur_distance = nil
end

local function camera_world(cm)
	return cm:get_viewport():get_world_proxy():get_world()
end

-- Distance from the shoulder pivot to the camera, shortened when level
-- geometry is in the way. Pulls in instantly, eases back out.
local function camera_distance(cm, side, dt, wanted, height)
	local unit = next(cm.targets or {})
	if M.camera_collision and unit and Unit.alive(unit) then
		local pivot = Unit.world_position(unit, 0) + side + Vector3(0, 0, height)
		local rot = Quaternion.multiply(Quaternion(Vector3.up(), M.yaw), Quaternion(Vector3(-1, 0, 0), M.pitch_rad))
		local back = Quaternion.rotate(rot, Vector3(0, -1, 0))
		local hit, _, dist = PhysicsWorld.immediate_raycast(World.physics_world(camera_world(cm)), pivot, back,
			wanted + 0.3, "closest", "types", "statics", "collision_filter", "default")
		if hit and dist then
			wanted = math.max(M.camera_min_distance, dist - 0.3)
		end
	end
	local cur = M.cur_distance or wanted
	if wanted < cur then
		cur = wanted
	else
		cur = math.min(wanted, cur + 6 * (dt or 0))
	end
	M.cur_distance = cur
	return cur
end

-- Renderer settings for the session: the mod's own (DOF off unless the aim
-- DOF drives it, plus the hidden ones in `renderer_settings`) while active,
-- the player's saved values when not. Values go in as strings, as the
-- options menu sends them.
local function apply_renderer_settings(on)
	local dof_wanted
	if M.aim_dof then
		dof_wanted = true
	elseif M.disable_dof then
		dof_wanted = false
	end
	if dof_wanted ~= nil then
		local value = dof_wanted
		if not on then
			value = Application.user_setting("render_settings", "dof_enabled") ~= false
		end
		Application.set_renderer_setting("dof_enabled", tostring(value))
	end
	for name, wanted in pairs(M.renderer_settings or {}) do
		local user = Application.user_setting("render_settings", name)
		local value = on and wanted or user
		if value == nil then
			value = wanted
		end
		local ok, err = pcall(Application.set_renderer_setting, name, tostring(value))
		log("renderer: %s = %s (saved setting %s)%s", name, tostring(value), tostring(user),
			ok and "" or (" failed: " .. tostring(err)))
	end
end

-- Push fog and the far clip plane out while the mod's camera is active, and
-- put both back otherwise. The level's fog is read a few frames into the
-- mission (before we override it) and scaled, so each planet keeps its look.
local function update_view_distance(cm, active)
	local vp = cm.viewport
	if not vp then
		return
	end
	local camera = vp:get_camera()

	-- Renderer settings are global; set_renderer_setting changes them for this
	-- session only, without touching the saved user settings.
	if active and not M.render_applied then
		M.render_applied = true
		try("renderer settings", apply_renderer_settings, true)
	elseif not active and M.render_applied then
		M.render_applied = false
		try("renderer settings", apply_renderer_settings, false)
	end

	if not active then
		if M.fog_applied then
			vp:remove_shading_environment_variable("fog_depth_range")
			M.fog_applied = false
		end
		if M.fog_graded then
			vp:remove_shading_environment_variable("fog_color")
			M.fog_graded = false
		end
		if M.dof_vars_set then
			vp:remove_shading_environment_variable("dof_amount")
			vp:remove_shading_environment_variable("dof_near_setting")
			vp:remove_shading_environment_variable("dof_far_setting")
			M.dof_vars_set, M.dof_amount_set = false, nil
		end
		if M.saved_far then
			Camera.set_far_range(camera, M.saved_far)
		end
		M.saved_far, M.fog_base, M.fog_color_base, M.view_frames = nil, nil, nil, 0
		return
	end

	-- Aim depth of field: focus at the crosshair's distance while aiming,
	-- none otherwise (the game's top-down focus distance blurs everything).
	if M.aim_dof then
		local want = M.aiming_now and M.aim_dof_amount or 0
		if want > 0 or want ~= M.dof_amount_set then
			local d = 20
			if M.aim_point then
				d = Vector3.distance(cm:get_position(), Vector3Aux.unbox(M.aim_point))
			end
			d = math.max(3, d)
			local near, far = M.dof_near_buf or {}, M.dof_far_buf or {}
			near[1], near[2] = 0, math.max(0.5, d * 0.5)
			far[1], far[2] = d * 1.6, d * 5
			M.dof_near_buf, M.dof_far_buf = near, far
			vp:set_shading_environment_variable("dof_near_setting", "vector2", near)
			vp:set_shading_environment_variable("dof_far_setting", "vector2", far)
			vp:set_shading_environment_variable("dof_amount", "scalar", want)
			M.dof_vars_set, M.dof_amount_set = true, want
		end
	end

	M.view_frames = (M.view_frames or 0) + 1
	if M.saved_far == nil then
		local ok, far = pcall(Camera.far_range, camera)
		M.saved_far = ok and far or false
		log("camera far range was %s", tostring(far))
	end
	Camera.set_far_range(camera, math.max(M.far_range, M.saved_far or 0))

	if M.fog_base == nil and M.view_frames >= 3 then
		local ok, v = pcall(ShadingEnvironment.vector2, vp:get_shading_environment(), "fog_depth_range")
		if ok and v then
			M.fog_base = { v.x, v.y }
			log("level fog_depth_range %.1f..%.1f -> x%.1f", v.x, v.y, M.fog_scale)
		else
			M.fog_base = false
			log("could not read fog_depth_range: %s", tostring(v))
		end
	end
	if M.fog_base and not M.fog_applied then
		vp:set_shading_environment_variable("fog_depth_range", "vector2",
			{ M.fog_base[1] * M.fog_scale, M.fog_base[2] * M.fog_scale })
		M.fog_applied = true
	end

	-- Fog grading: tint the level's own fog colour per planet type, once the
	-- HUD has told us which planet this is.
	if M.fog_color_base == nil and M.view_frames >= 5 then
		local ok, c = pcall(ShadingEnvironment.vector3, vp:get_shading_environment(), "fog_color")
		M.fog_color_base = ok and c and { c.x, c.y, c.z } or false
	end
	if M.fog_color_base and not M.fog_graded and M.environment and (M.fog_grading_strength or 0) > 0 then
		local g = M.fog_grading and M.fog_grading[M.environment]
		if g then
			local s, b = M.fog_grading_strength, M.fog_color_base
			local graded = { b[1] * (1 + (g[1] - 1) * s), b[2] * (1 + (g[2] - 1) * s), b[3] * (1 + (g[3] - 1) * s) }
			vp:set_shading_environment_variable("fog_color", "vector3", graded)
			M.sky_color = graded -- the sky takes the graded fog colour too
			M.engine_sky_tinted = false
			log("fog grading %s: x%.2f %.2f %.2f", tostring(M.environment), g[1], g[2], g[3])
		end
		M.fog_graded = true
	end
end

---------------------------------------------------------------------------
-- Sky. Levels have no sky (from above you never saw one): past the terrain
-- there's empty black. Draw a dome of panels around the camera on a world
-- GUI, far out but inside the far clip plane, coloured from the level's own
-- fog colour at the horizon and darkening upward. F9 toggles it.
---------------------------------------------------------------------------

-- Elevation bands (degrees) and panels around each: thin near the horizon,
-- where the colour changes fastest, so no band edge stands out.
local SKY_BANDS = {}
do
	local el = -14
	while el < 90 do
		local step = el < 30 and 3 or (el < 60 and 6 or 10)
		local top = math.min(90, el + step)
		local mid = math.rad((el + top) / 2)
		SKY_BANDS[#SKY_BANDS + 1] = { el, top, math.max(6, math.floor(56 * math.cos(mid) + 0.5)) }
		el = top
	end
end

-- Sky shade at an elevation: exactly the fog colour at and below the
-- horizon, easing toward a darker, bluer top.
local function sky_shade(fog, el_deg)
	local t = math.max(0, math.min(1, el_deg / 80))
	t = t * t * (3 - 2 * t) -- smoothstep
	return fog[1] * (1 - 0.5 * t), fog[2] * (1 - 0.4 * t), math.min(1, fog[3] * (1 - 0.2 * t) + 0.05 * t)
end

local function clamp255(v)
	return math.max(0, math.min(255, math.floor(v * 255 + 0.5)))
end

local function read_fog_color(vp)
	local ok, c = pcall(ShadingEnvironment.vector3, vp:get_shading_environment(), "fog_color")
	if ok and c then
		log("level fog_color %.2f %.2f %.2f", c.x, c.y, c.z)
		return { c.x, c.y, c.z }
	end
	log("could not read fog_color: %s", tostring(c))
	return { 0.35, 0.45, 0.6 }
end

local function draw_sky(cm)
	if not M.sky_gui then
		M.sky_gui = World.create_world_gui(camera_world(cm), Matrix4x4.identity(), 1, 1, "immediate")
		log("sky: world gui created (F9 toggles)")
	end
	local gui = M.sky_gui
	local fog = M.sky_color
	local eye = cm:get_position()
	local R = M.sky_distance
	local up = Vector3.up()
	for _, band in ipairs(SKY_BANDS) do
		local lo, hi, count = math.rad(band[1]), math.rad(band[2]), band[3]
		local mid = (lo + hi) / 2
		local r, g, b = sky_shade(fog, (band[1] + band[2]) / 2)
		local color = Color(255, clamp255(r), clamp255(g), clamp255(b))
		-- Generous overlap so neighbouring flat panels never open a gap.
		local width = 2 * R * math.cos(mid) * math.tan(math.pi / count) * 1.3 + 4
		local height = R * (hi - lo) * 1.4 + 4
		for i = 0, count - 1 do
			local az = (i + 0.5) / count * 2 * math.pi
			local flat_dir = Vector3(math.cos(az), math.sin(az), 0)
			local dir = flat_dir * math.cos(mid) + up * math.sin(mid)
			local rot = Quaternion.look(dir, math.abs(math.sin(mid)) > 0.95 and flat_dir or up)
			local right, panel_up = Quaternion.right(rot), Quaternion.up(rot)
			local corner = eye + dir * R - right * (width / 2) - panel_up * (height / 2)
			Gui.rect_3d(gui, Matrix4x4.from_quaternion_position(rot, corner), Vector3(0, 0, 0), 1,
				Vector2(width, height), color)
		end
	end
end

-- Engine sky dome (experimental, F9). The GUI sky above is drawn after
-- translucent effects, so smoke and beams vanish against it. The engine's
-- own sky dome draws in its sky pass, before them. Every level bundle has
-- the editor sky dome but never places it; it lives in the ship's package,
-- which isn't always loaded in missions. Spawning an unloaded unit crashes
-- the engine, so load that package through the game's package manager and
-- spawn only once it reports the package fully loaded.
local SKYDOME_UNIT = "core/editor_slave/units/skydome/skydome"
local SKYDOME_PACKAGE = "resource_packages/menu"
local SKY_MODES = { "overlay", "engine", "off" }
M.sky_mode = M.sky_mode or 2 -- engine sky by default
SKY_MODE_NAME = function()
	return SKY_MODES[M.sky_mode]
end

local function engine_sky_ready()
	local pm = rawget(_G, "Boot") and Boot.package_manager
	if not pm then
		return false
	end
	if not pm:has_package(SKYDOME_PACKAGE) then
		log("sky: loading %s for the engine sky dome", SKYDOME_PACKAGE)
		pm:load_package(SKYDOME_PACKAGE, false)
		return false
	end
	return not pm:is_package_loading(SKYDOME_PACKAGE)
end

-- The dome's material has one adjustable value, "intensity" (2.0 as
-- shipped); there's no colour tint. Scale it by how bright the level's fog
-- is, so night and gloomy missions get a dark sky rather than a daytime one.
local SKYDOME_INTENSITY = 2.0

local function set_dome_intensity(unit, value)
	for i = 0, Unit.num_meshes(unit) - 1 do
		local mesh = Unit.mesh(unit, i)
		for j = 0, Mesh.num_materials(mesh) - 1 do
			Material.set_scalar(Mesh.material(mesh, j), "intensity", value)
		end
	end
end

local function update_engine_sky(cm, want)
	if want and not M.engine_sky and engine_sky_ready() then
		M.engine_sky = World.spawn_unit(camera_world(cm), SKYDOME_UNIT, Vector3(0, 0, 0))
		M.engine_sky_tinted, M.engine_sky_visible = false, true
		log("sky: engine sky dome spawned")
	end
	if M.engine_sky and not M.engine_sky_tinted and M.sky_color then
		M.engine_sky_tinted = true
		local c = M.sky_color
		local lum = 0.2126 * c[1] + 0.7152 * c[2] + 0.0722 * c[3]
		local by_time = M.sky_time_brightness and M.time_of_day and M.sky_time_brightness[M.time_of_day] or 1
		local factor = math.max(M.sky_min_brightness, math.min(1, lum / M.sky_day_luminance) * by_time)
		set_dome_intensity(M.engine_sky, SKYDOME_INTENSITY * factor)
		log("sky: fog luminance %.2f, time of day %s -> dome brightness x%.2f", lum, tostring(M.time_of_day), factor)
	end
	if M.engine_sky and M.engine_sky_visible ~= want then
		M.engine_sky_visible = want
		Unit.set_unit_visibility(M.engine_sky, want)
	end
	return M.engine_sky ~= nil and want
end

local function update_sky(cm, active)
	if not active then
		return
	end
	if M.sky_color == nil and (M.view_frames or 0) >= 5 and cm.viewport then
		M.sky_color = read_fog_color(cm.viewport)
	end
	if key_pressed("f9") then
		M.sky_mode = M.sky_mode % #SKY_MODES + 1
		log("sky: %s (F9 for next)", SKY_MODES[M.sky_mode])
	end
	if not M.sky then
		return
	end
	local mode = SKY_MODES[M.sky_mode]
	local engine_shown = false
	if mode == "engine" or M.engine_sky then
		engine_shown = update_engine_sky(cm, mode == "engine")
	end
	-- The overlay also covers the wait while the engine dome's package loads.
	if (mode == "overlay" or (mode == "engine" and not engine_shown)) and M.sky_color then
		draw_sky(cm)
	end
end

-- Weather: one of the game's camera-attached effects (wind, rain, snow,
-- embers; all in the package every mission loads) started on any planet.
-- The key is unique per scene, since the camera manager remembers keys and
-- the old world's particles die with it.
local function update_weather(cm, active)
	local want = active and M.weather and M.weather ~= "off" and M.environment
	if want and M.weather_key == nil and cm.add_camera_particle then
		local effect
		if M.weather == "auto" then
			effect = M.weather_effects and M.weather_effects[M.environment]
		elseif M.weather_effects and M.weather_effects[M.weather] then
			effect = M.weather_effects[M.weather]
		elseif string.find(M.weather, "/") then
			effect = M.weather
		end
		if effect then
			M.weather_key = "hd2cam_weather_" .. (M.scene_serial or 0)
			cm:add_camera_particle(M.weather_key, effect, rawget(_G, "IS_PC") ~= false)
			log("weather: %s", effect)
		else
			M.weather_key = false -- nothing for this planet; don't ask again
		end
	elseif not active and M.weather_key and cm.remove_camera_particle then
		cm:remove_camera_particle(M.weather_key)
		M.weather_key = nil
	end
end

local function update_camera(cm, dt)
	if not camera_active() then
		return
	end
	save_camera(cm)

	if M.yaw == nil then
		M.yaw = cm.follow_spin or 0
		M.pitch_rad = math.rad(M.pitch)
	end

	local looked_vertically = false
	M.mouse_axis = M.mouse_axis or Mouse.axis_index("mouse")
	local delta = Mouse.axis(M.mouse_axis)
	if delta then
		local s = math.rad(M.sensitivity) * (M.aiming_now and M.aim_sensitivity or 1)
		local dy = M.invert_y and -delta.y or delta.y
		M.yaw = M.yaw - delta.x * s
		M.pitch_rad = M.pitch_rad + dy * s
		looked_vertically = math.abs(delta.y) > 0.5
		if delta.x ~= 0 or delta.y ~= 0 then
			M.look_at = M.clock
		end
	end

	-- Right stick of the pad the player is using (set by the input hook).
	local pad = M.player_pad
	if pad and dt then
		local stick = pad_value(pad, "axis", PAD_RIGHT_STICK)
		if stick then
			local mult = pad_aiming(pad) and M.pad_aim_slowdown or 1
			-- Aim assist: slower while the reticle sits on an enemy.
			if M.pad_aim_assist and M.clock - (M.assist_at or -10) < 0.15 then
				mult = mult * M.aim_assist_slowdown
			end
			local sy = M.pad_invert_y and -stick.y or stick.y
			local sx, sy2 = stick_curve(stick.x), stick_curve(sy)
			M.yaw = M.yaw - sx * math.rad(M.pad_yaw_speed) * mult * dt
			M.pitch_rad = M.pitch_rad - sy2 * math.rad(M.pad_pitch_speed) * mult * dt
			looked_vertically = looked_vertically or sy2 ~= 0
			if sx ~= 0 or sy2 ~= 0 then
				M.look_at = M.clock
			end
		end
	end

	-- Auto-centre: running with the look input idle eases the view round
	-- behind the body (which faces the way you run when out of combat).
	if M.auto_center and dt and not M.combat_now and not M.aiming_now and (M.move_amount or 0) > 0.3
		and (not M.auto_center_sprint_only or M.sprinting)
		and M.clock - (M.look_at or -10) > M.auto_center_delay and M.local_unit and Unit.alive(M.local_unit) then
		local f = Quaternion.forward(Unit.local_rotation(M.local_unit, 0))
		local d = math.atan2(-f.x, f.y) - M.yaw
		d = math.atan2(math.sin(d), math.cos(d))
		M.yaw = M.yaw + d * math.min(1, dt * M.auto_center_rate)
	end
	-- Death cam with nobody to follow: slowly orbit the body.
	if M.spectate_orbit and dt then
		M.yaw = M.yaw + 0.35 * dt
	end

	-- Letting go of aim eases the view back to level (the default tilt),
	-- unless you're actively looking up or down.
	if M.was_aiming and not M.aiming_now and M.aim_pitch_reset then
		M.pitch_resetting = true
	end
	M.was_aiming = M.aiming_now
	if M.aiming_now or looked_vertically then
		M.pitch_resetting = false
	end
	if M.pitch_resetting and dt then
		local level = math.rad(M.pitch)
		M.pitch_rad = M.pitch_rad + (level - M.pitch_rad) * math.min(1, dt * 8)
		if math.abs(M.pitch_rad - level) < math.rad(0.5) then
			M.pitch_rad, M.pitch_resetting = level, false
		end
	end
	M.pitch_rad = math.max(math.rad(M.min_pitch), math.min(math.rad(M.max_pitch), M.pitch_rad))
	M.yaw = math.atan2(math.sin(M.yaw), math.cos(M.yaw)) -- keep within -180..180

	-- Shoulder swap (key, or R3 while aiming on a pad: see the input hook).
	if key_pressed(M.shoulder_key) or M.swap_shoulder then
		M.swap_shoulder = false
		M.shoulder_side = -(M.shoulder_side or 1)
	end
	local target_side = M.shoulder_side or 1
	M.cur_side = (M.cur_side or target_side) + (target_side - (M.cur_side or target_side)) * math.min(1, (dt or 0) * 10)

	-- Recoil kick: an upward offset that settles back.
	M.recoil = (M.recoil or 0) * math.exp(-(dt or 0) * M.recoil_recover)

	-- HD2 feel, eased: closer and further over the shoulder while aiming, a
	-- little further back and wider while sprinting, lower while prone.
	local k = math.min(1, (dt or 0) * 8)
	M.aim_blend = ease(M.aim_blend, M.aiming_now and 1 or 0, k)
	M.sprint_blend = ease(M.sprint_blend, (M.sprinting and not M.aiming_now) and 1 or 0, k)
	M.cur_height = ease(M.cur_height, M.downed and M.prone_height or M.height, k)
	local dist_scale = (1 + (M.aim_distance_scale - 1) * M.aim_blend)
		* (1 + (M.sprint_distance_scale - 1) * M.sprint_blend)
	local shoulder_scale = 1 + (M.aim_shoulder_scale - 1) * M.aim_blend

	-- Zoom while aiming.
	if M.saved and M.saved.fov then
		local want = M.saved.fov * (M.aiming_now and M.aim_zoom or 1) * (1 + (M.sprint_fov - 1) * M.sprint_blend)
		M.cur_fov = (M.cur_fov or M.saved.fov) + (want - (M.cur_fov or M.saved.fov)) * math.min(1, (dt or 0) * 10)
		cm.fov = M.cur_fov
	end

	local side = flat_right(M.yaw) * (M.shoulder * shoulder_scale * M.cur_side)
	local distance = camera_distance(cm, side, dt, M.distance * dist_scale, M.cur_height)

	cm.follow_spin = M.yaw
	cm.follow_angle = M.pitch_rad - M.recoil
	cm.follow_distance = distance
	cm.min_follow_distance = distance
	cm.max_follow_distance = distance

	-- The game eases the camera toward its goal at 0.6 x dt per frame, which
	-- suits a top-down view but makes an orbit camera trail behind mouse
	-- turns. Close on it much faster (camera_smoothing per second), but never
	-- past the goal in one frame (1 / dt is a snap). Also skip the push that
	-- keeps the top-down view point inside the map; a low camera trips it
	-- constantly.
	if dt and dt > 0 then
		local snap = 1 / dt
		local rate = M.camera_smoothing or 0
		cm.follow_position_interp = rate > 0 and math.min(rate, snap) or snap
	end
	cm.ignore_level_bounds = true

	-- The game adds (offset.x - 1, offset.y - 1, offset.z) to the target.
	cm.follow_offset = cm.follow_offset or {}
	cm.follow_offset.x = side.x + 1
	cm.follow_offset.y = side.y + 1
	cm.follow_offset.z = M.cur_height

	for _, props in pairs(cm.targets or {}) do
		if M.saved.look_ahead[props] == nil then
			M.saved.look_ahead[props] = props.look_ahead or 0
		end
		props.look_ahead = 0
	end

	if M.pin_cursor then
		if M.shot_screen and not M.on_bridge then
			-- Same coordinates the game itself passes here (world_to_screen).
			CursorManager:set_cursor_position(Vector3(math.floor(M.shot_screen[1]), math.floor(M.shot_screen[2]), 0))
		else
			local w, h = Application.resolution()
			Window.set_cursor_position(Vector2(math.floor(w / 2), math.floor(h / 2)))
		end
	end
end

on_require("lua/managers/camera_manager", function()
	local cm = CameraManager
	if is_patched(cm, "update") then
		return
	end
	local original_update = cm.update
	mark_patched(cm, "update")

	local function check_toggle_keys(self)
		if key_pressed(M.toggle_key) then
			M.enabled = not M.enabled
			log("enabled = %s", tostring(M.enabled))
			if not M.enabled then
				restore_camera(self)
			end
		end
		if M.prone_key and key_pressed(M.prone_key) then
			M.prone_request = true
		end
		-- F11: camera smoothing on/off, to compare the feel in-game.
		if key_pressed("f11") then
			if (M.camera_smoothing or 0) > 0 then
				M.camera_smoothing_saved, M.camera_smoothing = M.camera_smoothing, 0
			else
				M.camera_smoothing = M.camera_smoothing_saved or 30
			end
			log("camera smoothing: %s (F11 toggles)",
				M.camera_smoothing > 0 and string.format("%g per second", M.camera_smoothing) or "off (snaps to the body)")
		end
		if key_pressed("f7") then
			local list, at = M.fog_scales, 1
			for i, v in ipairs(list) do
				if v == M.fog_scale then
					at = i
				end
			end
			M.fog_scale = list[at % #list + 1]
			M.fog_applied = false -- re-applied with the new scale next frame
			log("view distance: fog x%g (F7 for next)", M.fog_scale)
		end
	end

	-- Your own avatar on the bridge (called under pcall every frame there, so
	-- no closure).
	local function own_avatar(players)
		local avatar
		for _, p in pairs(players or {}) do
			if p.player_go and p.player_go:owned() then
				local u = p.player_go:get("avatar_unit")
				if u and Unit.alive(u) then
					avatar = u
				end
			end
		end
		return avatar
	end

	-- One reused targets table holding just the unit the camera follows.
	local DEATH_PROPS = { bias = 1, look_ahead = 0, is_reverse = false }
	local target_buf = {}
	local function single_target(unit, props)
		for k in pairs(target_buf) do
			target_buf[k] = nil
		end
		target_buf[unit] = props
		return target_buf
	end

	-- Mouse throws aim at the point under the cursor, which the mod pins to
	-- the crosshair: hand the throw the crosshair's world point instead of
	-- the cursor projected to the camera's height.
	local function first_replaced(repl, _, ...)
		return repl, ...
	end
	if type(cm.screen_to_world) == "function" and not is_patched(cm, "s2w") then
		local original_s2w = cm.screen_to_world
		mark_patched(cm, "s2w")
		cm.screen_to_world = function(self, v, ...)
			if M.throw_to_crosshair and M.throwing and M.aim_point and camera_active() and not M.on_bridge
				and M.shot_screen and is_engine_object(v)
				and math.abs(v.x - M.shot_screen[1]) < 4 and math.abs(v.y - M.shot_screen[2]) < 4 then
				return first_replaced(Vector3Aux.unbox(M.aim_point), original_s2w(self, v, ...))
			end
			return original_s2w(self, v, ...)
		end
	end

	-- Put back what was swapped for the vanilla update, passing its results on.
	local function finish_update(self, coop_targets, bridge_targets, ...)
		if coop_targets then
			self.targets = coop_targets
		end
		if bridge_targets then
			self.state = "follow_menu"
			self.targets = bridge_targets
		end
		return ...
	end

	cm.update = function(self, dt, players, ...)
		M.clock = M.clock + (dt or 0)
		M.last_dt = dt

		-- The bridge camera ("follow_menu") frames the players' avatars from
		-- a fixed angle and ignores the follow settings. For this frame, run
		-- it as a normal follow camera on your avatar instead, then put it
		-- back. Menus on the bridge show the menu cursor, which pauses this.
		-- (No co-op check here: the bridge's player objects have no map_ping,
		-- and touching a missing network field crashes the engine. The
		-- bridge camera only affects this screen, so it follows F8 alone.)
		-- Leaving modded mode (F8 or a vanilla player): restore the camera.
		local on = M.on() and self.state == "follow"
		if M.was_on and not on and self.state == "follow" then
			restore_camera(self)
			if M.engine_sky and M.engine_sky_visible then
				M.engine_sky_visible = false
				Unit.set_unit_visibility(M.engine_sky, false)
			end
		end
		M.was_on = on
		-- Weapon ranges follow the mod on/off state, whatever the scene.
		local want = M.on()
		if want ~= M.range_scaled_on and M.apply_range_scaling then
			M.range_scaled_on = want
			try("range toggle", M.apply_range_scaling, want)
		end

		local bridge_targets
		M.on_bridge = false
		if M.enabled and M.bridge_camera and self.state == "follow_menu" and in_game_cursor() then
			local ok, avatar = pcall(own_avatar, players)
			avatar = ok and avatar or nil
			if avatar then
				if not M.bridge_logged then
					M.bridge_logged = true
					log("bridge camera engaged")
				end
				M.on_bridge = true
				bridge_targets = self.targets
				self.targets = { [avatar] = { bias = 1, look_ahead = 0, is_reverse = false } }
				self.state = "follow"
			end
		end
		try("toggle", check_toggle_keys, self)
		-- Not camera_active(): keep the view distance while the pause menu is up.
		-- Missions only: the bridge's shading environment lacks the fog
		-- variables, and reading a missing one crashes the engine outright.
		local mission = M.on() and self.state == "follow" and not M.on_bridge
		-- Co-op: the vanilla camera frames every player; follow only yours.
		-- Dead (death_cam): follow the nearest living teammate, or orbit your
		-- body. Swapped before the camera update so collision uses the right
		-- pivot, and put back after the vanilla update.
		local coop_targets
		if mission and not bridge_targets and M.local_unit and self.targets then
			local follow = M.local_unit
			M.spectate_orbit = false
			if M.death_cam and M.local_dead then
				local mate = M.teammates and M.teammates[1]
				if mate and Unit.alive(mate) then
					follow = mate
				elseif Unit.alive(M.local_unit) then
					M.spectate_orbit = true
				end
			end
			local own = self.targets[M.local_unit]
			local several = next(self.targets, next(self.targets)) ~= nil
			if follow ~= M.local_unit or (own and several) then
				coop_targets = self.targets
				self.targets = single_target(follow, self.targets[follow] or own or DEATH_PROPS)
			end
		end
		try("camera", update_camera, self, dt)
		if M.spine_bend and M.update_bend_amount then
			try("spine amount", M.update_bend_amount, dt)
		end
		if mission and M.update_aim_assist then
			try("aim assist", M.update_aim_assist)
		end
		try("view distance", update_view_distance, self, mission)
		try("sky", update_sky, self, mission)
		try("weather", update_weather, self, mission)
		if M.patch_prone_fire then
			try("prone fire", M.patch_prone_fire)
		end
		return finish_update(self, coop_targets, bridge_targets, original_update(self, dt, players, ...))
	end
	-- A new scene (bridge <-> mission) re-initialises the camera manager with
	-- a new world and viewport: forget what we remembered about the old one.
	local original_init = cm.init
	-- Units from the old world are dangling pointers now: asking the
	-- engine anything about them (even Unit.alive) crashes the game.
	-- Missions call cm.init; the ship's bridge doesn't (see the stats hook).
	function M.reset_scene()
		M.local_unit, M.player_unit, M.player_pad, M.input_masters = nil, nil, nil, nil
		M.last_aim, M.aim_point, M.shot_screen, M.combat_now, M.aiming_now = nil, nil, nil, false, false
		M.combat_until, M.map_open, M.spine_written, M.spine_base = 0, false, nil, nil
		M.patrols, M.patrols_at, M.objectives, M.objectives_at = nil, nil, nil, nil
		M.hit_seen, M.ping_request, M.throwing, M.crawl_firing = nil, false, false, false
		M.input_fields_logged, M.back_logged_at = false, nil
		M.dressed = false
		for j = #M.props, 1, -1 do
			M.props[j] = nil
		end
		M.coop_blocked, M.coop_blocked_since = true, nil
		M.world_gui, M.strat_list_src, M.strat_queue_src, M.strat_probe_at = nil, nil, nil, nil
		M.weather_key, M.scene_serial, M.enemy_count, M.enemies_at = nil, (M.scene_serial or 0) + 1, 0, nil
		M.local_dead, M.spectate_orbit, M.hit_from, M.hit_from_at, M.assist_at = false, false, nil, nil, nil
		M.sprinting, M.move_amount, M.downed, M.callout_pending = false, 0, false, false
		for j = #M.teammates, 1, -1 do
			M.teammates[j] = nil
		end
		if M.forget_units then
			M.forget_units()
		end
		M.saved, M.yaw, M.cur_distance, M.cur_fov, M.recoil = nil, nil, nil, nil, 0
		M.fog_applied, M.fog_base, M.saved_far, M.view_frames = false, nil, nil, 0
		M.fog_graded, M.fog_color_base, M.dof_vars_set, M.dof_amount_set = false, nil, false, nil
		-- The sky GUI belonged to the old world, which destroyed it.
		M.sky_gui, M.sky_color, M.engine_sky = nil, nil, nil
		M.environment, M.own_mark, M.own_mark_armed = nil, nil, false
	end
	cm.init = function(self, ...)
		M.reset_scene()
		M.scene = "mission"
		return original_init(self, ...)
	end
	log("camera hook installed")
end)

---------------------------------------------------------------------------
-- Aim: point the character where the crosshair (screen centre) is.
---------------------------------------------------------------------------

local function flat(v)
	return Vector3(v.x, v.y, 0)
end

-- Frame number (the stats hook counts camera updates), for work that several
-- hooks want in the same frame and need computing only once.
local function frame_number()
	return M.stats.frames
end

-- World point under the crosshair: cast along the camera's view ray, the
-- same way bullets collide ("damage_ray"), starting past the player so the
-- ray cannot hit them. Cast once per frame: the aim hook, the shot marker
-- and the throw-range label all ask (boxed, since engine vectors are
-- temporaries that don't survive the frame).
local ray_cache = { frame = -1, pos = {}, fwd = {} }

local function crosshair_point()
	local frame = frame_number()
	if ray_cache.frame == frame then
		return Vector3Aux.unbox(ray_cache.pos), Vector3Aux.unbox(ray_cache.fwd)
	end
	local cam_pos = CameraManager:get_position()
	local fwd = Quaternion.forward(CameraManager:get_rotation())
	local start = cam_pos + fwd * ((M.cur_distance or M.distance) + 0.5)
	local hit, pos = PhysicsWorld.immediate_raycast(World.physics_world(camera_world(CameraManager)), start, fwd,
		M.aim_distance, "closest", "types", "both", "collision_filter", "damage_ray")
	if hit and pos then
		M.stats.ray_hit = M.stats.ray_hit + 1
	else
		pos = start + fwd * M.aim_distance
	end
	ray_cache.frame = frame
	Vector3Aux.box(ray_cache.pos, pos)
	Vector3Aux.box(ray_cache.fwd, fwd)
	return pos, fwd
end

-- A weapon's settings table never changes for the life of the unit, and the
-- manager's lookup runs several times a frame while aiming.
local weapon_settings = setmetatable({}, { __mode = "k" })

local function settings_of(weapon)
	local s = weapon_settings[weapon]
	if s == nil then
		s = LuaSettingsManager:get_settings_by_unit(weapon)
		weapon_settings[weapon] = s -- a nil answer is asked again next time
	end
	return s
end

-- Muzzle position for the given body facing, from the weapon's settings.
local function muzzle_position(unit, facing)
	local pos = Unit.world_position(unit, 0)
	local cs = EntityAux.state(unit, "character")
	local weapon = cs and cs.current_weapon
	if not (weapon and Unit.alive(weapon)) then
		return pos
	end
	local settings = settings_of(weapon)
	local offset = settings and settings.weapon_info and settings.weapon_info.ray_source_offset
	if not offset then
		return pos
	end
	local rot = Quaternion.look(facing, Vector3.up())
	return pos + Quaternion.rotate(rot, Vector3Aux.unbox(offset))
end

-- Direction (flat) the body must face for the muzzle line to pass through
-- the crosshair point. One refinement step: the muzzle moves as the body
-- turns, so solve from the centre first, then again from the muzzle.
-- Solved once per frame per unit: the shot marker and the aim both need it.
local dir_cache = { frame = -1, unit = nil, dir = {}, target = {} }

local function solve_crosshair_direction(unit)
	local target, cam_fwd = crosshair_point()
	local dir = flat(target - Unit.world_position(unit, 0))
	if Vector3.length(dir) < M.min_aim_distance then
		return Vector3.normalize(flat(cam_fwd)), target
	end
	dir = Vector3.normalize(dir)
	local refined = flat(target - muzzle_position(unit, dir))
	if Vector3.length(refined) >= M.min_aim_distance then
		dir = Vector3.normalize(refined)
	end
	return dir, target
end

local function crosshair_direction(unit)
	local frame = frame_number()
	if dir_cache.frame == frame and dir_cache.unit == unit then
		return Vector3Aux.unbox(dir_cache.dir), Vector3Aux.unbox(dir_cache.target)
	end
	local dir, target = solve_crosshair_direction(unit)
	dir_cache.frame, dir_cache.unit = frame, unit
	Vector3Aux.box(dir_cache.dir, dir)
	Vector3Aux.box(dir_cache.target, target)
	return dir, target
end

local function firing(data)
	M.throwing = data.throw or (data.throw_amount or 0) > 0.1
	return data.fire or data.fire_auto or M.throwing
end

-- Holding aim right now? pad is the player's controller, or nil on mouse.
local function aiming(aim, pad)
	if pad then
		-- On a pad the game turns right-stick deflection into aim; that stick
		-- now drives the camera, so only the left trigger means "aiming".
		return pad_aiming(pad)
	end
	return Vector3.length_squared(aim) > 0.0001 -- right mouse, decided by the game
end

-- Crosshair drawn while aiming on a controller (the mouse already has the
-- game cursor pinned at screen centre). Same icon the game uses for its
-- own controller cursor, on the input component's immediate-mode GUI.
local function draw_crosshair(input_component)
	local gui = input_component and input_component.cursor_gui
	if not gui then
		return
	end
	local w, h = Application.resolution()
	local x, y = w / 2, h / 2
	if M.shot_screen then
		x, y = M.shot_screen[1], M.shot_screen[2]
	end
	local size = M.crosshair_size
	Gui.bitmap_uv(gui, "cursor_game", Vector2(0, 0), Vector2(1, 1),
		Vector2(math.floor(x - size / 2), math.floor(y - size / 2)),
		Vector2(size, size), Color(255, 255, 255, 255))
end

local function player_weapon_of(unit)
	if not (unit and Unit.alive(unit)) then
		return nil
	end
	local ok, cs = pcall(EntityAux.state, unit, "character")
	local weapon = ok and cs and cs.current_weapon
	if weapon and Unit.alive(weapon) then
		return weapon
	end
	return nil
end

-- Where a level shot (vanilla HD1 shots fly flat from shoulder height, dipping
-- slightly so they reach the ground at max range) passes at the distance of
-- what's under the screen centre. The crosshair is drawn there, so it shows
-- where you'll actually hit while the camera tilts freely.
local function update_shot_marker(unit)
	M.shot_screen, M.shot_point = nil, nil
	-- Only with a weapon in hand (not while the hellpod lands, etc.). Engine
	-- calls given a missing unit crash the game outright, past any pcall.
	local weapon = player_weapon_of(unit)
	if not weapon then
		return
	end
	local dir, target = crosshair_direction(unit)
	local from = muzzle_position(unit, dir)
	local range, drop = 30, 1.5
	local info = settings_of(weapon)
	info = info and info.weapon_info
	if info then
		range = (info.range or range) * M.range_scale
		if info.ray_source_offset then
			drop = Vector3Aux.unbox(info.ray_source_offset).z
		end
	end
	local d = math.max(3, math.min(range, Vector3.length(flat(target - from))))
	local point = from + dir * d - Vector3(0, 0, drop * d / range)
	M.shot_point = Vector3Aux.box(M.shot_point or {}, point)
	local sp = CameraManager:world_to_screen(point)
	if sp and sp.z > 0 then
		local ss = M.shot_screen_buf or {}
		ss[1], ss[2] = sp.x, sp.y
		M.shot_screen_buf, M.shot_screen = ss, ss
	end
end

-- The mover keeps each player inside the camera's view (with a margin) by
-- refusing steps that leave it; with a close, zoomed camera the body sits
-- near that margin, so walking backwards stopped. The mover's own switch
-- for it is per player: turn it off for you while the mod's camera is up,
-- and put the game's value back otherwise. (The camera manager's frustum
-- test itself is left alone: enemy spawners and AI rely on it.)
local EMPTY_STATE = {}

-- The engine names its own types: a unit's type() is "unit", a vector's is
-- its class. Anything that isn't a plain Lua value is an engine object.
local PLAIN = { ["nil"] = true, boolean = true, number = true, string = true, table = true, ["function"] = true }

local function is_engine_object(v)
	return not PLAIN[type(v)]
end

-- Diagnostics for "can't walk backwards while aiming". The input code
-- sends the stick to the mover itself (a "set_movement" command) before
-- this copy of it reaches the character, so log the stick, this copy and
-- the camera yaw side by side whenever you aim and move (every 1.5 s).
local PAD_LEFT_STICK = { "left" }

local function log_backward_move(unit, data, mv)
	if not M.aiming_now or not M.yaw or M.clock - (M.back_logged_at or -10) < 1.5 then
		return
	end
	if type(mv) == "table" then
		mv = Vector3Aux.unbox(mv)
	elseif not is_engine_object(mv) then
		return
	end
	local rel = Vector3.dot(flat_forward(M.yaw), mv)
	local stick = M.player_pad and pad_value(M.player_pad, "axis", PAD_LEFT_STICK)
	local stick_len = stick and Vector3.length(stick) or 0
	if Vector3.length(mv) < 0.3 and stick_len < 0.3 then
		return
	end
	M.back_logged_at = M.clock
	log("aim+move: stick %s, move copy %.2f,%.2f (along view %.2f), yaw %.0f deg",
		stick and string.format("%.2f,%.2f", stick.x, stick.y) or "n/a", mv.x, mv.y, rel, math.deg(M.yaw))
	local ok, cs = pcall(EntityAux.state, unit, "character")
	cs = ok and type(cs) == "table" and cs or EMPTY_STATE
	-- The mover's own state, from the entity manager (the character's
	-- mover_state reference holds only the velocity).
	local ms = EMPTY_STATE
	local em = M.entity_manager
	if em then
		local ok3, movers = pcall(em.get_master_entities, em, "mover")
		local ctx = ok3 and type(movers) == "table" and movers[unit]
		if type(ctx) == "table" and type(ctx.state) == "table" then
			ms = ctx.state
		end
	end
	local vel = ms.velocity or (type(cs.mover_state) == "table" and cs.mover_state.velocity)
	local speed = -1
	if type(vel) == "table" then
		speed = Vector3.length(Vector3Aux.unbox(vel))
	end
	local held = type(ms.movement) == "table" and Vector3Aux.unbox(ms.movement)
	log("  mover: wanted %s, velocity_scale %s, slow %s, accel %s, decel %s, lock %s/%s, movement %s, constant %s",
		tostring(ms.wanted_move_speed), tostring(ms.velocity_scale), tostring(ms.slow_multiplier),
		tostring(ms.acceleration), tostring(ms.deceleration), tostring(ms.lock_direction),
		tostring(ms.lock_direction_backwards), held and string.format("%.2f,%.2f", held.x, held.y) or type(ms.movement),
		tostring(ms.constant_movement))
	local state = M.state_name_of and M.state_name_of(cs.current_state) or tostring(cs.current_state)
	log("backward while aiming: move %.2f,%.2f (rel %.2f), velocity %.2f, wanted speed %s, state %s, forced rot %s, aim %s",
		mv.x, mv.y, rel, speed, tostring(cs.wanted_move_speed), state, tostring(cs.forced_rotation_speed),
		tostring(M.aiming_now))
end

local function apply_crosshair_aim(input_component, unit, data)
	M.local_unit = unit
	-- Movement state for the camera: sprinting, how hard you're moving, prone.
	M.sprinting = data.sprint == true or (type(data.sprint_amount) == "number" and data.sprint_amount > 0.5)
	-- The stick arrives as "movement", a boxed table (x, y, z); engine calls
	-- with the wrong argument type crash past any pcall, so measure a boxed
	-- vector by hand and call the engine only on a real one.
	local mv = data.movement or data.move
	local amount = 0
	if type(mv) == "table" and type(mv.x) == "number" and type(mv.y) == "number" then
		amount = math.sqrt(mv.x * mv.x + mv.y * mv.y + (type(mv.z) == "number" and mv.z * mv.z or 0))
	elseif type(mv) == "number" then
		amount = math.abs(mv)
	elseif is_engine_object(mv) then
		amount = Vector3.length(mv)
	end
	M.move_amount = amount
	-- Once per mission: what the character's input copy actually holds.
	if not M.input_fields_logged then
		M.input_fields_logged = true
		local names = {}
		for k, v in pairs(data) do
			if type(k) == "string" then
				names[#names + 1] = k .. "=" .. type(v)
			end
		end
		table.sort(names)
		log("input fields: %s", table.concat(names, " "))
	end
	try("backward log", log_backward_move, unit, data, mv)
	local ok2, cs = pcall(EntityAux.state, unit, "character")
	M.downed = ok2 and type(cs) == "table" and cs.is_downed == true
	if not M.vertical_aim then
		try("shot marker", update_shot_marker, unit)
	end
	local ctx = M.input_masters and M.input_masters[unit]
	local pad_number = ctx and ctx.state and ctx.state.pad_number
	local pad = pad_device(pad_number)
	-- Switching devices flips this for a moment; log at most every 2 seconds.
	if pad ~= M.player_pad and M.clock - (M.input_logged_at or -10) > 2 then
		M.input_logged_at = M.clock
		log("player input: %s", pad and string.format("pad %d (%s)", pad_number, tostring(pad.type())) or "keyboard/mouse")
	end
	M.player_pad = pad

	-- In combat while aiming or firing, and for a short linger after firing
	-- so bursts don't swing the body back and forth. Releasing aim without
	-- having fired ends combat at once.
	local aim = Vector3Aux.unbox(data.aim)
	local is_aiming = aiming(aim, pad)
	if firing(data) then
		if not is_aiming then
			M.stats.aim_hip = M.stats.aim_hip + 1
		end
		M.combat_until = M.clock + M.combat_linger
	end
	M.combat_now = is_aiming or M.clock < M.combat_until
	M.aiming_now = is_aiming
	if not M.combat_now then
		M.stats.aim_zero = M.stats.aim_zero + 1
		M.last_aim = nil
		M.aim_point = nil
		if Vector3.length_squared(aim) > 0.0001 then
			Vector3Aux.box(data.aim, Vector3(0, 0, 0))
		end
		return -- out of combat: leave aim empty so the body faces movement
	end
	M.player_unit = unit
	if pad and is_aiming then
		draw_crosshair(input_component)
	end

	-- Diagnostics: how far the body's facing lags the aim we sent last frame.
	if M.last_aim then
		local facing = Vector3.normalize(flat(Quaternion.forward(Unit.local_rotation(unit, 0))))
		local err = math.deg(math.acos(math.max(-1, math.min(1, Vector3.dot(facing, Vector3Aux.unbox(M.last_aim))))))
		M.stats.err_sum = (M.stats.err_sum or 0) + err
		M.stats.err_n = (M.stats.err_n or 0) + 1
		M.stats.err_max = math.max(M.stats.err_max or 0, err)
	end

	local dir, target = crosshair_direction(unit)
	Vector3Aux.box(data.aim, dir)
	M.last_aim = Vector3Aux.box(M.last_aim or {}, dir)
	M.aim_point = Vector3Aux.box(M.aim_point or {}, target)

	-- Vertical angle from the muzzle to the crosshair point, for the spine bend.
	local d = target - muzzle_position(unit, dir)
	local horizontal = Vector3.length(flat(d))
	M.aim_pitch = horizontal >= M.min_aim_distance and math.atan2(d.z, horizontal) or 0
	M.stats.aim_set = M.stats.aim_set + 1
end

local function in_combat(unit)
	return not M.on_bridge and unit == M.player_unit and M.combat_now and camera_active()
end

---------------------------------------------------------------------------
-- Vertical aim. HD1 fires every shot level with the ground (the body only
-- turns around the vertical axis), so aiming up or down only moved the
-- crosshair. Tilt the player's shots, and their laser sight, toward the
-- 3D point under the crosshair.
---------------------------------------------------------------------------

local function player_weapon()
	local cs = M.player_unit and Unit.alive(M.player_unit) and EntityAux.state(M.player_unit, "character")
	return cs and cs.current_weapon
end

-- Pitched version of a level shot direction, or nil when the shot is not
-- the player's aimed shot (turrets, AI, other players, or not in combat).
local function pitched_forward(forward)
	if not (M.aim_point and in_combat(M.player_unit) and Unit.alive(M.player_unit)) then
		return nil
	end
	local f = flat(forward)
	if Vector3.length(f) < 0.5 then
		return nil
	end
	f = Vector3.normalize(f)
	local facing = Vector3.normalize(flat(Quaternion.forward(Unit.local_rotation(M.player_unit, 0))))
	if Vector3.dot(f, facing) < 0.95 then -- ~18 deg; the hand sways with animation
		return nil -- not fired along the player's facing: someone else's shot
	end
	if not M.vertical_aim then
		return f, false
	end
	local d = Vector3Aux.unbox(M.aim_point) - muzzle_position(M.player_unit, f)
	local horizontal = Vector3.length(flat(d))
	if horizontal < M.min_aim_distance then
		return nil
	end
	local limit = math.rad(M.max_shot_pitch)
	local pitch = math.max(-limit, math.min(limit, math.atan2(d.z, horizontal)))
	return f * math.cos(pitch) + Vector3.up() * math.sin(pitch), true
end

on_require("lua/utility/weapon_utility", function()
	local wu = WeaponUtility
	if is_patched(wu, "spread") then
		return
	end
	local original = wu.get_random_spread
	mark_patched(wu, "spread")

	-- get_random_spread(source_offset, forward, spread, range, up, fixed)
	-- returns the shot direction. Besides spread, it tilts every shot down by
	-- source_offset.z / range so a level shot from shoulder height lands at
	-- max range; a shot aimed at the crosshair point must not get that tilt.
	wu.get_random_spread = function(offset, forward, spread, range, up, fixed, ...)
		M.stats.shots_total = (M.stats.shots_total or 0) + 1
		local ok, dir, tilted = pcall(pitched_forward, forward)
		if ok and dir and offset then
			M.stats.shots_pitched = (M.stats.shots_pitched or 0) + 1
			if M.recoil_frame ~= M.clock then
				M.recoil_frame = M.clock
				M.recoil = math.min(math.rad(8), (M.recoil or 0) + math.rad(M.recoil_kick))
			end
			-- HD1 spreads shots widely (built for twin-stick spray). Tighten
			-- it like HD2: a lot when aiming down sights, a little from the hip.
			local scale = M.aiming_now and M.aim_spread_scale or M.hip_spread_scale
			-- A shot tilted at the crosshair point must not also get the game's
			-- built-in downward tilt; a level shot keeps it, as in HD1.
			local src = tilted and Vector3(offset.x, offset.y, 0) or offset
			return original(src, dir, (spread or 0) * scale, range, up, fixed, ...)
		end
		return original(offset, forward, spread, range, up, fixed, ...)
	end
	log("shot pitch hook installed")
end)

-- Spine joints of the Helldiver rig (characters/helldiver_private_01:
-- root > hips > spine1 > spine2 > spine3 > spine4 > neck > head), with the
-- share of the bend each takes. Other rigs in the game use a j_ prefix.
local SPINE = {
	{ "spine1", 0.15 }, { "spine2", 0.25 }, { "spine3", 0.3 }, { "spine4", 0.3 },
	{ "j_spine1", 0.2 }, { "j_spine2", 0.35 }, { "j_spine3", 0.45 },
}
local spine_cache = setmetatable({}, { __mode = "k" })

local function spine_nodes(unit)
	local list = spine_cache[unit]
	if list then
		return list
	end
	list = {}
	local found, total = {}, 0
	for _, s in ipairs(SPINE) do
		local prefixed = string.sub(s[1], 1, 2) == "j_"
		if Unit.has_node(unit, s[1]) and not (prefixed and #found > 0) then
			list[#list + 1] = { node = Unit.node(unit, s[1]), weight = s[2] }
			found[#found + 1] = s[1]
			total = total + s[2]
		end
	end
	for _, e in ipairs(list) do
		e.weight = e.weight / total
	end
	spine_cache[unit] = list
	log("spine bend joints: %s", #found > 0 and table.concat(found, ", ") or "none found")
	return list
end

-- Units attached to the player's skeleton: customization items (armour,
-- helmet, cape...) and the weapon in hand. Re-collected every 2 seconds.
local linked_cache = { unit = nil, at = -100, list = {} }

-- Called on scene change: drop cached units from the old world.
function M.forget_units()
	linked_cache.unit, linked_cache.list = nil, {}
end

function M.linked_units(unit)
	if linked_cache.unit == unit and M.clock - linked_cache.at < 2 then
		return linked_cache.list
	end
	local list, seen = {}, { [unit] = true }
	local function add(u)
		if type(u) == "userdata" and not seen[u] then
			local ok, alive = pcall(Unit.alive, u)
			if ok and alive then
				seen[u] = true
				list[#list + 1] = u
			end
		end
	end
	pcall(function()
		for k, v in pairs(EntityAux.state(unit, "customization") or {}) do
			if type(k) == "string" and string.sub(k, -5) == "_unit" then
				add(v)
			end
		end
	end)
	pcall(function()
		add(EntityAux.state(unit, "character").current_weapon)
	end)
	if #list ~= #linked_cache.list or linked_cache.unit ~= unit then
		log("spine: refreshing %d attached unit(s) with the bend", #list)
	end
	linked_cache.unit, linked_cache.at, linked_cache.list = unit, M.clock, list
	return list
end

-- Same rotation? q and -q are the same rotation, and the engine may hand
-- back either after storing a joint as a matrix.
local function same_rotation(a, b)
	local ax, ay, az, aw = Quaternion.to_elements(a)
	local bx, by, bz, bw = Quaternion.to_elements(b)
	return math.abs(ax * bx + ay * by + az * bz + aw * bw) > 1 - 1e-5
end

-- Where the bend is written each frame. "callback" is the engine's
-- after-animation hook; "render" is just before the frame is drawn (then the
-- unit's scene graph is pushed). F7 cycles a forced 40-degree test bend
-- through each (F10 is taken by Windows), to see which one shows on screen.
local SPINE_MODES = {
	{ "normal (aim-driven, both phases)", "both", false },
	{ "TEST forced 40 deg, animation callback only", "callback", true },
	{ "TEST forced 40 deg, before render only", "render", true },
	{ "TEST forced 40 deg, both phases", "both", true },
}
M.spine_mode = 1
M.logged_states = {}

-- Once per frame, from the camera update: ease the bend toward the aim.
local function update_bend_amount(dt)
	local mode = SPINE_MODES[M.spine_mode]
	local want = 0
	if mode[3] then
		want = math.rad(40) * M.spine_sign
	elseif camera_active() and M.combat_now and M.aim_pitch then
		local limit = math.rad(M.spine_max)
		want = math.max(-limit, math.min(limit, M.aim_pitch)) * M.spine_sign
	end
	local bend = M.bend or 0
	M.bend = bend + (want - bend) * math.min(1, (dt or 0.016) * M.spine_smooth)
	M.stats.bend_max = math.max(M.stats.bend_max or 0, math.abs(math.deg(M.bend)))
end

local function bend_spine(phase)
	local mode = SPINE_MODES[M.spine_mode]
	if mode[2] ~= "both" and mode[2] ~= phase then
		return
	end
	local unit = M.local_unit
	local bend = M.bend or 0
	if not (M.spine_bend and unit and Unit.alive(unit) and math.abs(bend) >= 0.001) then
		return
	end
	M.stats["spine_" .. phase] = (M.stats["spine_" .. phase] or 0) + 1

	-- Bend around the body's right axis: +angle tips the chest up.
	local right = Quaternion.right(Unit.local_rotation(unit, 0))
	M.spine_written = M.spine_written or {}
	M.spine_base = M.spine_base or {}
	local nodes = spine_nodes(unit)
	for _, e in ipairs(nodes) do
		local current = Unit.local_rotation(unit, e.node)
		-- If the joint still holds what we last wrote, animation hasn't
		-- refreshed it: bend from the stored pose instead of stacking bends.
		local written = M.spine_written[e.node]
		local base = current
		if written and same_rotation(current, QuaternionAux.unbox(written)) and M.spine_base[e.node] then
			base = QuaternionAux.unbox(M.spine_base[e.node])
		end
		M.spine_base[e.node] = QuaternionAux.box(M.spine_base[e.node] or {}, base)

		-- The body's right axis in the joint's own space, then rotate about it.
		local axis = Quaternion.rotate(Quaternion.inverse(Unit.world_rotation(unit, e.node)), right)
		local bent = Quaternion.multiply(base, Quaternion(axis, bend * e.weight))
		Unit.set_local_rotation(unit, e.node, bent)
		M.spine_written[e.node] = QuaternionAux.box(written or {}, bent)
	end

	if phase == "render" and nodes[1] then
		local world = Unit.world(unit)
		World.update_unit(world, unit)
		-- What you see is mostly armour, helmet and gun: separate units linked
		-- joint-by-joint to this skeleton (UnitAux.skin_item). Refresh them so
		-- they pick up the bent joints this frame.
		for _, child in ipairs(M.linked_units(unit)) do
			World.update_unit(world, child)
		end
		-- Did pushing the scene graph keep our joint, or re-run animation?
		local kept = same_rotation(Unit.local_rotation(unit, nodes[1].node),
			QuaternionAux.unbox(M.spine_written[nodes[1].node]))
		local key = kept and "render_kept" or "render_reverted"
		M.stats[key] = (M.stats[key] or 0) + 1
	end
end

local function apply_spine_bend()
	bend_spine("callback")
end

local function cycle_spine_mode()
	M.spine_mode = M.spine_mode % #SPINE_MODES + 1
	log("spine bend: %s (F7 for next)", SPINE_MODES[M.spine_mode][1])
end

-- Called from the camera update, which is defined earlier in this file.
M.update_bend_amount = update_bend_amount
M.cycle_spine_mode = cycle_spine_mode

-- The spine bend is an experiment that the engine defeats (see spine_bend);
-- with it off, neither of its per-frame hooks is installed.
local function patch_world_proxy()
	local wp = rawget(_G, "WorldProxy")
	if not M.spine_bend or not wp or is_patched(wp, "anim") then
		return
	end
	local original = wp.set_update_animations_callback
	mark_patched(wp, "anim")
	-- The game's mission state installs a callback the world runs between
	-- animation and scene update; chain the spine bend after it.
	wp.set_update_animations_callback = function(self, callback, ...)
		local chained = callback
		if callback then
			local function after(...)
				if M.spine_bend then
					try("spine", apply_spine_bend)
				end
				return ...
			end
			chained = function(...)
				return after(callback(...))
			end
		end
		return original(self, chained, ...)
	end
	log("spine hook installed")
end
on_require("foundation/lua/world/world_proxy", patch_world_proxy)

-- Just before the frame renders.
local function spine_render_check()
	bend_spine("render")
end

local function patch_viewport_proxy()
	local vp = rawget(_G, "ViewportProxy")
	if not vp or is_patched(vp, "render") then
		return
	end
	local original = vp.render
	mark_patched(vp, "render")

	-- A point behind the camera projects to a mirrored spot in front, so HUD
	-- markers (health bars, names, objectives) showed on the wrong side; the
	-- top-down camera never looked away from them. Send such points far
	-- off-screen in the true direction (a marker pinned to the screen edge
	-- then lands on the correct edge). world_to_viewport is (x, depth, y);
	-- world_to_screen is (x, y, depth).
	local function behind_fix(w, h, ox, oy, x, y)
		local cx, cy = ox + w / 2, oy + h / 2
		return cx - (x - cx) * 1000, cy - (y - cy) * 1000
	end
	local to_viewport = vp.world_to_viewport
	vp.world_to_viewport = function(self, pos, ...)
		local r = to_viewport(self, pos, ...)
		if M.on() and r and r.y <= 0 then
			local w, h = self:window()
			local x, y = behind_fix(w, h, 0, 0, r.x, r.z)
			return Vector3(x, r.y, y)
		end
		return r
	end
	local to_screen = vp.world_to_screen
	vp.world_to_screen = function(self, pos, ...)
		local r = to_screen(self, pos, ...)
		if M.on() and r and r.z <= 0 then
			local w, h, ox, oy = self:window()
			local x, y = behind_fix(w, h, ox or 0, oy or 0, r.x, r.y)
			return Vector3(x, y, r.z)
		end
		return r
	end
	if M.spine_bend then
		vp.render = function(self, ...)
			try("spine render", spine_render_check)
			return original(self, ...)
		end
	end
	log("render hook installed")
end
on_require("foundation/lua/world/viewport_proxy", patch_viewport_proxy)

-- The laser sight is drawn as a particle beam from the gun to where a level
-- ray hits. Redraw the player's beam toward the crosshair point (capped at
-- the laser's range) so it shows where shots actually go.
local function retarget_laser(world, unit, st)
	-- Where the laser should end: the crosshair point when shots tilt toward
	-- it, else the level shot's path at the aimed distance (HD1's own laser
	-- dips into the ground at the laser's range, which reads as a miss).
	local target = M.vertical_aim and M.aim_point or M.shot_point
	if not (st.laser_enabled and st.particle_effect and target) then
		if st.laser_enabled and not target and not M.laser_skip_logged then
			M.laser_skip_logged = true
			log("laser: not redrawn (no shot point yet)")
		end
		return
	end
	local function skip(reason)
		if not M.laser_skip_logged then
			M.laser_skip_logged = true
			log("laser: not redrawn (%s)", reason)
		end
	end
	if not in_combat(M.player_unit) then
		return
	end
	-- The laser can sit on its own attachment unit rather than the player or
	-- the weapon, so match it by being on the player's body.
	if unit ~= M.player_unit and unit ~= player_weapon()
		and Vector3.distance(Unit.world_position(unit, 0), Unit.world_position(M.player_unit, 0)) > 2.5 then
		return skip("laser unit is not on the player")
	end
	if not M.laser_logged then
		M.laser_logged = true
		log("laser: redrawn straight out of the gun")
	end
	M.stats.laser_retargeted = (M.stats.laser_retargeted or 0) + 1
	local from = Unit.world_position(unit, st.attach_node or 0)
	local to
	if M.vertical_aim then
		to = Vector3Aux.unbox(target)
		local range = (st.range or 20) * 4
		if Vector3.distance(from, to) > range then
			to = from + Vector3.normalize(to - from) * range
		end
	else
		-- Straight out of the gun (no dip), stopping at what it hits.
		local fwd = Quaternion.forward(Unit.world_rotation(unit, st.attach_node or 0))
		local range = (st.range or 20) * M.range_scale
		local hit, pos = PhysicsWorld.immediate_raycast(World.physics_world(world), from + fwd * 0.3, fwd, range,
			"closest", "types", "both", "collision_filter", "damage_ray")
		to = hit and pos or (from + fwd * range)
	end
	World.set_particles_variable(world, st.particle_effect, st.particle_end_variable, to)
	World.move_particles(world, st.particle_effect, to)
end

on_require("lua/components/laser_sight_component", function()
	local ls = LaserSightComponent
	if is_patched(ls, "update_slaves") then
		return
	end
	local original = ls.update_slaves
	mark_patched(ls, "update_slaves")

	local function retarget_all(self, slaves)
		if not camera_active() then
			return
		end
		local world = self.world_proxy:get_world()
		for unit, ctx in pairs(slaves) do
			if ctx.state then
				retarget_laser(world, unit, ctx.state)
			end
		end
	end
	local function after(self, slaves, ...)
		try("laser", retarget_all, self, slaves)
		return ...
	end
	ls.update_slaves = function(self, slaves, ...)
		return after(self, slaves, original(self, slaves, ...))
	end
	log("laser hook installed")
end)

on_require("lua/components/input_component", function()
	local ic = InputComponent
	if is_patched(ic, "qcm") then
		return
	end
	local original = ic.queue_command_master
	mark_patched(ic, "qcm")

	-- Remember this frame's masters so the hook below can see which pad
	-- (if any) each player is using.
	local original_update_masters = ic.update_masters
	ic.update_masters = function(self, masters, ...)
		M.input_masters = masters
		-- The input code turns stick directions by CameraManager.follow_spin,
		-- which now follows the view. The map is drawn at the game's original
		-- fixed angle, so while it is open give the input code that angle.
		local spin = CameraManager and CameraManager.follow_spin
		-- Set by the HUD hook from the HUD's own per-player map flag.
		local map_open = M.hud_map_open == true
		if M.map_open and not map_open then
			M.map_closed_at = M.clock
		end
		if map_open ~= M.map_open then
			log("map %s", map_open and "opened (stick follows the map)" or "closed")
		end
		M.map_open = map_open
		-- The HUD always draws the map turned to the old isometric camera's
		-- angle (-45 degrees; hud.lua world_to_map), so use that constant.
		local swap = map_open and CameraManager ~= nil
		if swap then
			CameraManager.follow_spin = math.rad(-45)
		end
		if not swap then
			return original_update_masters(self, masters, ...)
		end
		original_update_masters(self, masters, ...)
		CameraManager.follow_spin = spin
	end

	local R3, LB, D_UP, D_DOWN = { "right_thumb", "r3" }, { "left_shoulder", "l1" }, { "d_up" }, { "d_down" }
	local function pad_extras(data)
		local pad = M.player_pad
		if not pad then
			return
		end
		-- R3 while aiming swaps shoulder instead of meleeing.
		if pad_aiming(pad) and pad_pressed(pad, R3) then
			M.swap_shoulder = true
			data.melee = false
		end
		-- D-pad up (without LB, which is stratagem input) pings; the rest of
		-- the D-pad keeps the game's own callouts (prone is hold-dive, or
		-- the keyboard prone key). With the settings menu open the D-pad
		-- drives the menu and the game's own D-pad actions are held off.
		if M.menu_open then
			data.communication_yes, data.communication_no = false, false
			data.communication_stay, data.communication_move = false, false
			return
		end
		local lb = pad_value(pad, "button", LB)
		if not (lb and lb > 0.5) and pad_pressed(pad, D_UP) then
			M.ping_request = true
			data.communication_yes = false
		end
	end

	-- Hold the dive button to go prone, tap it to dive (HD2). The game dives
	-- on the press, so the press is held back while the button is down: a
	-- release before prone_hold dives then, a hold past it goes prone (or
	-- stands you up from the crawl) and the dive is dropped.
	-- The raw dive button: B / circle on a pad, or the keyboard key the
	-- "dodge_button" binding names (the input table only carries the
	-- filtered press).
	local PAD_DIVE = { "b", "circle" }
	local function dive_key_index()
		if M.dive_key_index ~= nil then
			return M.dive_key_index
		end
		M.dive_key_index = false
		local list = type(M.last_bindings) == "table" and M.last_bindings.keyboard_mouse
		if type(list) == "table" then
			for _, e in ipairs(list) do
				if type(e) == "table" and e.output_name == "dodge_button" and type(e.key) == "string" then
					local ok, idx = pcall(Keyboard.button_index, e.key)
					if ok and idx then
						M.dive_key_index = idx
						log("dive hold: keyboard dive key is %s", e.key)
					end
					break
				end
			end
		end
		return M.dive_key_index
	end
	local function dive_button_down()
		local pad = M.player_pad
		if pad then
			local v = pad_value(pad, "button", PAD_DIVE)
			return v ~= nil and v > 0.5
		end
		local idx = dive_key_index()
		if idx then
			local ok, v = pcall(Keyboard.button, idx)
			return ok and type(v) == "number" and v > 0.5
		end
		return false
	end

	local function dive_hold(data)
		if not (M.prone_hold and M.prone_hold > 0) then
			return
		end
		local down = dive_button_down()
		if down then
			if not M.dive_down then
				M.dive_down_at, M.dive_consumed = M.clock, false
			end
			if not M.dive_consumed and M.clock - M.dive_down_at >= M.prone_hold then
				M.dive_consumed = true
				M.prone_request = true
			end
			if data.dodge then
				data.dodge = false
				M.dive_pending = not M.dive_consumed
			end
		elseif M.dive_down then
			if M.dive_pending and not M.dive_consumed then
				data.dodge = true
			end
			M.dive_pending, M.dive_consumed = false, false
		end
		M.dive_down = down
	end

	ic.queue_command_master = function(self, unit, component, command, data, ...)
		-- B both closes the map and dives. Ignore dive while the map is open and
		-- briefly after, and clear the game's latched dive press.
		if component == "character" and command == "input" and type(data) == "table" and unit == M.local_unit
			and M.on() and (M.map_open or M.clock - (M.map_closed_at or -10) < 0.5) and data.dodge then
			data.dodge = false
			pcall(EntityAux.queue_command_master, unit, "input", "reset_filter", "dodge_pressed")
		end
		if component == "character" and command == "input" and type(data) == "table"
			and unit == M.local_unit and camera_active() and not M.on_bridge then
			try("pad extras", pad_extras, data)
			try("dive hold", dive_hold, data)
			-- A ping also calls out "move" (the game's own voice line and icon).
			if M.callout_pending then
				M.callout_pending = false
				data.communication_move = true
			end
		end
		if component == "character" and command == "input" and type(data) == "table"
			and data.aim and camera_active() then
			if M.on_bridge then
				-- Bridge: camera only. Just track which pad drives it.
				pcall(function()
					local ctx = M.input_masters and M.input_masters[unit]
					M.player_pad = pad_device(ctx and ctx.state and ctx.state.pad_number)
				end)
			else
				try("aim", apply_crosshair_aim, self, unit, data)
			end
		end
		return original(self, unit, component, command, data, ...)
	end
	log("aim hook installed")
end)

-- The body normally turns toward the aim at a capped rate, and bullets leave
-- along the body's facing, so fast mouse sweeps put shots behind the
-- crosshair. The game resets forced_rotation_speed before running the state
-- machine each frame; set it afterwards, unless a state already forced one.
on_require("lua/character_states/character_state_machine", function()
	local sm = CharacterStateMachine
	if is_patched(sm, "update") then
		return
	end
	local original = sm.update
	mark_patched(sm, "update")

	local function force_turn(unit, context)
		local st = type(context) == "table" and context.state
		if st and st.forced_rotation_speed == nil and in_combat(unit) then
			st.forced_rotation_speed = M.combat_turn_retention
		end
	end
	local function after_update(unit, context, ...)
		try("turn", force_turn, unit, context)
		return ...
	end
	-- Every character (enemies too) runs this each frame; only the player's
	-- own update needs the protected call. The prone key acts here, before
	-- the state machine runs, so a state change set now is applied this frame.
	sm.update = function(unit, context, ...)
		if unit == M.local_unit and M.prone_request and M.prone_toggle then
			try("prone toggle", M.prone_toggle, unit, context)
		end
		if unit ~= M.player_unit then
			return original(unit, context, ...)
		end
		return after_update(unit, context, original(unit, context, ...))
	end
	log("turn hook installed")
end)

---------------------------------------------------------------------------
-- Prone fire. Downed (after a dive), the game only shoots from its "downed
-- aim" states, which it enters once the aim vector is non-zero; a bare fire
-- press does nothing there. Give the downed states an aim toward the
-- crosshair whenever fire is held, so the next frame shoots. The state
-- classes live in scripts without recoverable names, so they are patched
-- once their globals exist (polled from the camera update).
---------------------------------------------------------------------------

-- (Scoped in a block: a Lua chunk may hold at most 200 locals. Entry points
-- are M.patch_prone_fire, M.prone_toggle and M.state_name_of.)
do

local function prone_fire_fix(unit, context)
	if unit ~= M.local_unit or not (M.prone_fire and camera_active() and not M.on_bridge) then
		return
	end
	local st = type(context) == "table" and context.state
	local input = st and st.input
	if type(input) ~= "table" or not (input.fire or input.fire_auto) then
		return
	end
	local aim = input.aim
	if type(aim) == "table" and M.last_aim then
		local x, y = tonumber(aim.x) or 0, tonumber(aim.y) or 0
		if x * x + y * y < 0.0001 then
			Vector3Aux.box(aim, Vector3Aux.unbox(M.last_aim))
		end
	end
end

local function prone_single_shot(context)
	local st = type(context) == "table" and context.state
	local weapon = st and st.current_weapon
	if weapon and Unit.alive(weapon) then
		EntityAux.queue_command_master_interface(weapon, "weapon", "firing_single")
	end
end

-- Class table -> global name, from _G; rebuilt when a table is unknown
-- (the state scripts are loaded again per mission), at most every 5 s.
local state_names, state_names_at = {}, -10

local function state_name(cls)
	local name = state_names[cls]
	if not name and M.clock - state_names_at > 5 then
		state_names_at = M.clock
		for k, v in pairs(_G) do
			if type(k) == "string" and type(v) == "table" and string.sub(k, 1, 14) == "CharacterState" then
				state_names[v] = k
			end
		end
		name = state_names[cls]
	end
	return name or tostring(cls)
end
M.state_name_of = state_name

local function prone_state(name)
	return string.find(name, "Downed") or string.find(name, "Crawl") or string.find(name, "Dodge")
end

local function trace_state_change(context, new_state)
	local name = state_name(new_state)
	if not prone_state(name) and not prone_state(state_name(M.last_state or false)) then
		M.last_state = new_state
		return
	end
	M.last_state = new_state
	local st = type(context) == "table" and context.state
	local input = st and st.input
	local aim = type(input) == "table" and input.aim
	local aim_len = type(aim) == "table" and ((tonumber(aim.x) or 0) ^ 2 + (tonumber(aim.y) or 0) ^ 2) or -1
	log("state -> %s (fire %s, aim len^2 %.3f, mod combat %s)", name,
		tostring(type(input) == "table" and input.fire), aim_len, tostring(M.combat_now))
end

-- Prone proper: a dive while moving lands in CharacterStateCrawl, which
-- only knows how to stand up. Fire from it the way the standing fire state
-- does: one single-shot command as fire goes down, the auto command while
-- held, and a stop when it is released or the state is left.
local function crawl_fire(unit, context)
	if unit ~= M.local_unit or not (M.prone_fire and camera_active() and not M.on_bridge) then
		return
	end
	local st = type(context) == "table" and context.state
	local input = st and st.input
	local weapon = st and st.current_weapon
	if type(input) ~= "table" or not (weapon and Unit.alive(weapon)) then
		return
	end
	local held = input.fire and true or false
	if held and not M.crawl_firing then
		EntityAux.queue_command_master_interface(weapon, "weapon", "firing_single")
		if not M.crawl_fire_logged then
			M.crawl_fire_logged = true
			log("prone fire: shooting while crawling")
		end
	end
	if held or M.crawl_firing then
		EntityAux.queue_command_master_interface(weapon, "weapon", "firing_auto", held and input.fire_auto or false)
	end
	-- No crawling while firing (as HD2): the crawl's speed comes from the
	-- character's wanted speed, so zero it while firing and give the crawl
	-- speed back on release. The body turns toward the crawl direction in
	-- this state (only the aim states turn to the aim), so point it at the
	-- crosshair ourselves; with no movement the game's own turn code idles.
	if held then
		if M.crawl_speed_saved == nil then
			M.crawl_speed_saved = st.wanted_move_speed or false
		end
		st.wanted_move_speed = 0
		if M.last_aim then
			local aim = Vector3Aux.unbox(M.last_aim)
			if Vector3.length(aim) > 0.5 then
				Unit.set_local_rotation(unit, 0, Quaternion.look(aim, Vector3.up()))
			end
			if M.clock - (M.prone_face_logged_at or -10) > 2 then
				M.prone_face_logged_at = M.clock
				local facing = flat(Quaternion.forward(Unit.local_rotation(unit, 0)))
				local err = math.deg(math.acos(math.max(-1, math.min(1, Vector3.dot(Vector3.normalize(facing), aim)))))
				log("prone fire: facing is %.0f deg off the crosshair", err)
			end
		end
	elseif M.crawl_speed_saved ~= nil then
		local info = type(context.settings) == "table" and context.settings.character_info
		st.wanted_move_speed = (type(info) == "table" and info.move_speed_crawl) or M.crawl_speed_saved or nil
		M.crawl_speed_saved = nil
	end
	M.crawl_firing = held
end

-- The prone key: from a standing state straight into the crawl state (the
-- same one a dive lands in), and from the crawl state back up the game's
-- own way (its dodge input stands you up with the roll animation).
local STANDING = {
	CharacterStateIdle = true, CharacterStateWalk = true, CharacterStateSprint = true,
	CharacterStateAim = true, CharacterStateAimWalk = true,
}

function M.prone_toggle(unit, context)
	M.prone_request = false
	local st = type(context) == "table" and context.state
	if not st or st.new_state ~= nil or not (camera_active() and not M.on_bridge) then
		return
	end
	local name = state_name(st.current_state)
	if name == "CharacterStateCrawl" then
		if type(st.input) == "table" then
			st.input.dodge = true
		end
	elseif STANDING[name] then
		local crawl = rawget(_G, "CharacterStateCrawl")
		if crawl then
			-- The crawl is the dive's landing state: its update compares the
			-- dive timer the dive set on the way in. Seed what a finished dive
			-- would have left: timer at the end of the dive (no slide, timer
			-- frozen until you get up), get-up not started.
			local info = type(context.settings) == "table" and context.settings.character_info
			st.dive_timer = type(info) == "table" and tonumber(info.dive_duration) or 1
			st.dive_get_up = false
			CharacterStateMachine.change_state(unit, context, crawl)
			if not M.prone_key_logged then
				M.prone_key_logged = true
				log("prone: went prone from %s", name)
			end
		end
	end
end

local function crawl_fire_stop(unit, context)
	if unit ~= M.local_unit then
		return
	end
	M.crawl_speed_saved = nil -- the next state sets its own speed
	if not M.crawl_firing then
		return
	end
	M.crawl_firing = false
	local st = type(context) == "table" and context.state
	local weapon = st and st.current_weapon
	if weapon and Unit.alive(weapon) then
		EntityAux.queue_command_master_interface(weapon, "weapon", "firing_auto", false)
	end
end

-- Called every camera update: the state scripts are loaded again for each
-- mission, so whatever table is current gets patched (is_patched is per
-- table, so this is a few lookups a frame once done).
function M.patch_prone_fire()
	local idle, crawl = rawget(_G, "CharacterStateDownedIdle"), rawget(_G, "CharacterStateDownedCrawl")
	local fire = rawget(_G, "CharacterStateDownedAimFire")
	local prone = rawget(_G, "CharacterStateCrawl")
	if not (idle and crawl and fire and prone) then
		return
	end
	if type(prone.update) == "function" and not is_patched(prone, "prone") then
		local original_update, original_exit = prone.update, prone.on_exit
		mark_patched(prone, "prone")
		prone.update = function(unit, context, ...)
			try("crawl fire", crawl_fire, unit, context)
			return original_update(unit, context, ...)
		end
		if type(original_exit) == "function" then
			prone.on_exit = function(unit, context, ...)
				try("crawl fire stop", crawl_fire_stop, unit, context)
				return original_exit(unit, context, ...)
			end
		end
		log("prone fire hooks installed (crawl)")
	end
	for _, cls in ipairs({ idle, crawl }) do
		if type(cls.update) == "function" and not is_patched(cls, "prone") then
			local original = cls.update
			mark_patched(cls, "prone")
			cls.update = function(unit, context, ...)
				try("prone fire", prone_fire_fix, unit, context)
				return original(unit, context, ...)
			end
		end
	end
	if type(fire.on_enter) == "function" and not is_patched(fire, "prone") then
		local original = fire.on_enter
		mark_patched(fire, "prone")
		-- The downed fire state only ever sends "firing_auto", so semi-automatic
		-- and burst weapons never fire there. The standing fire state sends one
		-- "firing_single" as it is entered; do the same here.
		fire.on_enter = function(unit, context, ...)
			if unit == M.local_unit and M.prone_fire then
				try("prone single shot", prone_single_shot, context)
				if not M.prone_fire_logged then
					M.prone_fire_logged = true
					log("prone fire: shooting while downed")
				end
			end
			return original(unit, context, ...)
		end
	end
	-- Diagnostics: your character's downed-state changes, with the inputs
	-- the states saw, so the log shows where prone fire stops.
	local sm = rawget(_G, "CharacterStateMachine")
	if sm and type(sm.change_state) == "function" and not is_patched(sm, "trace") then
		local original = sm.change_state
		mark_patched(sm, "trace")
		sm.change_state = function(unit, context, new_state, ...)
			if unit == M.local_unit then
				try("state trace", trace_state_change, context, new_state)
			end
			return original(unit, context, new_state, ...)
		end
		log("prone fire hooks installed (downed, trace)")
	end
end

end -- prone

---------------------------------------------------------------------------
-- Escort NPCs. Each one counts down while outside the camera's view and is
-- killed (hitpoints set to -100) when the timer runs out. With the mod's
-- camera they are out of view most of the time, so keep that timer topped
-- up; dying to enemies is untouched.
---------------------------------------------------------------------------

on_require("lua/components/npc_escort_component", function()
	local ec = rawget(_G, "NpcEscortComponent")
	if not ec or type(ec.update_derived_master) ~= "function" or is_patched(ec, "offscreen") then
		return
	end
	local original = ec.update_derived_master
	mark_patched(ec, "offscreen")
	local function keep_alive(context)
		local st = type(context) == "table" and context.state
		if st and type(st.outside_screen_timer) == "number" and M.escort_offscreen_safe and M.on() then
			st.outside_screen_timer = 1000000
		end
	end
	ec.update_derived_master = function(self, unit, context, ...)
		try("escort", keep_alive, context)
		return original(self, unit, context, ...)
	end
	log("escort hook installed")
end)

---------------------------------------------------------------------------
-- Camera shake and hits. The game ships a camera shaker with presets
-- (CameraShakeSettings) that only airstrikes and a few scripted events use.
-- Shake on every explosion and when you take damage, as HD2 does, and
-- remember where the hit came from for the damage arc on the HUD.
---------------------------------------------------------------------------

local function add_shake(preset_name, pos)
	local presets = rawget(_G, "CameraShakeSettings")
	local preset = presets and presets[preset_name]
	if preset and CameraManager and CameraManager.add_shake then
		CameraManager:add_shake(preset, Vector3Aux.box({}, pos))
	end
end

on_require("lua/managers/explosion_manager", function()
	local em = rawget(_G, "ExplosionManager")
	if not em or type(em.do_explosion) ~= "function" or is_patched(em, "shake") then
		return
	end
	local original = em.do_explosion
	mark_patched(em, "shake")
	local function shake(pos)
		if M.camera_shake and camera_active() and not M.on_bridge and type(pos) == "table" then
			add_shake(M.explosion_shake, Vector3Aux.unbox(pos))
		end
	end
	-- do_explosion(self, unit, position (boxed), explosive_info, ...)
	em.do_explosion = function(self, unit, pos, info, ...)
		try("explosion shake", shake, pos)
		return original(self, unit, pos, info, ...)
	end
	log("explosion shake hook installed")
end)

on_require("lua/components/health_component", function()
	local hc = rawget(_G, "HealthComponent")
	if not hc or type(hc.command_master) ~= "function" or is_patched(hc, "hits") then
		return
	end
	local original = hc.command_master
	mark_patched(hc, "hits")
	local function on_hit(unit, data)
		if unit ~= M.local_unit or not camera_active() or M.on_bridge then
			return
		end
		M.hit_taken_at = M.clock
		-- The damage carries the attacking unit and the owner of whatever did
		-- the damage; prefer the attacker (a projectile's owner is the shooter,
		-- but a melee hit's owner may be the limb).
		local attacker = type(data) == "table" and (data.attacker_unit or data.owner_unit)
		if is_engine_object(attacker) and attacker ~= unit and Unit.alive(attacker) then
			M.hit_from = Vector3Aux.box(M.hit_from or {}, Unit.world_position(attacker, 0))
			M.hit_from_at = M.clock
			-- Diagnostics for the arc direction: the first few hits in detail.
			M.hits_logged = (M.hits_logged or 0) + 1
			if M.hits_logged <= 6 and M.yaw then
				local d = flat(Unit.world_position(attacker, 0) - Unit.world_position(unit, 0))
				local rel = math.atan2(-d.x, d.y) - M.yaw
				rel = math.deg(math.atan2(math.sin(rel), math.cos(rel)))
				log("hit: from %s (attacker %s, owner %s) %.1f m away, %.0f deg %s of view; angle_hit %s, power %s",
					tostring(attacker), tostring(data.attacker_unit), tostring(data.owner_unit), Vector3.length(d),
					math.abs(rel), rel > 0 and "left" or "right", tostring(data.angle_hit), tostring(data.power))
			end
		end
		if M.camera_shake then
			add_shake(M.hit_shake, Unit.world_position(unit, 0))
		end
	end
	-- The "do_damage" command carries power and the damage source's owner.
	hc.command_master = function(self, unit, context, command, data, ...)
		if command == "do_damage" then
			try("hit", on_hit, unit, data)
		end
		return original(self, unit, context, command, data, ...)
	end
	log("hit hook installed")
end)

---------------------------------------------------------------------------
-- Frame timing (perf_log). Every frame much slower than the ones around it
-- is logged with where the time went: the game's whole Lua update and
-- render calls, the mod's own sections, and how the Lua heap moved (a big
-- drop means the garbage collector freed memory that frame). Everything
-- outside those is the engine itself (physics, streaming, the GPU...).
---------------------------------------------------------------------------

-- Time the game's global update/render. The engine looks them up by name
-- every frame; the boot script defines them after this file has loaded, so
-- wrap them on first sight (and again if a reload replaces them).
local function wrap_global(name, field)
	local f = rawget(_G, name)
	if type(f) ~= "function" or f == perf["wrapper_" .. name] then
		return
	end
	local inner = f
	local function after(t0, ...)
		perf[field] = perf[field] + (clock() - t0) * 1000
		perf.globals_called = true
		return ...
	end
	local wrapper = function(...)
		return after(clock(), inner(...))
	end
	perf["wrapper_" .. name] = wrapper
	rawset(_G, name, wrapper)
	log("perf: timing global %s()", name)
end

local function top_sections(n)
	local list = {}
	for k, v in pairs(perf.sections) do
		if v >= 0.05 then
			list[#list + 1] = { k, v }
		end
	end
	table.sort(list, function(a, b) return a[2] > b[2] end)
	local out = {}
	for i = 1, math.min(n, #list) do
		out[i] = string.format("%s %.1f", list[i][1], list[i][2])
	end
	return #out > 0 and table.concat(out, ", ") or "-"
end

-- The mod sections with the slowest single frame this window, then cleared.
local function max_sections(n)
	local list = {}
	for k, v in pairs(perf.win_sec_max) do
		if v >= 0.5 then
			list[#list + 1] = { k, v }
		end
		perf.win_sec_max[k] = 0
	end
	table.sort(list, function(a, b) return a[2] > b[2] end)
	local out = {}
	for i = 1, math.min(n, #list) do
		out[i] = string.format("%s %.1f", list[i][1], list[i][2])
	end
	return #out > 0 and table.concat(out, ", ") or "-"
end

-- Once per frame, at the start of the camera update. The time since the
-- previous call is the whole previous frame.
local function perf_frame(cm)
	wrap_global("update", "update")
	wrap_global("render", "render")
	local now = clock()
	local heap = collectgarbage("count")
	local last, last_heap = perf.last, perf.heap
	perf.last, perf.heap = now, heap
	if last then
		local ms = (now - last) * 1000
		local typical = perf.typical or ms
		local hitch = ms > typical * 1.8 and ms > typical + 15
		if hitch then
			-- If the engine kept its own reference, the wrappers never run.
			local wrapped = perf.globals_called
			log("HITCH %.0f ms (typical %.1f): game lua update %s (typical %.1f), mod %.1f [%s]; lua heap %+.0f kB (%.0f MB); %s since last; state %s, mod %s, fog x%g, sky %s",
				ms, typical,
				wrapped and string.format("%.1f", perf.update) or "n/a", perf.typical_update or 0,
				perf.mod, top_sections(3), heap - last_heap, heap / 1024,
				perf.last_hitch and string.format("%.1f s", now - perf.last_hitch) or "first",
				tostring(cm.state), M.on() and "on" or "off", M.fog_scale, tostring(M.sky and SKY_MODE_NAME and SKY_MODE_NAME()))
			perf.last_hitch = now
			perf.win_hitches = perf.win_hitches + 1
		else
			-- Slow-moving baselines that hitches don't drag up.
			perf.typical = typical + (ms - typical) * 0.05
			local tu = perf.typical_update or perf.update
			perf.typical_update = tu + (perf.update - tu) * 0.05
		end
		perf.win_t = perf.win_t + ms / 1000
		perf.win_ms = perf.win_ms + ms
		perf.win_frames = perf.win_frames + 1
		perf.win_mod = perf.win_mod + perf.mod
		perf.win_mod_max = math.max(perf.win_mod_max, perf.mod)
		perf.win_worst = math.max(perf.win_worst, ms)
		-- Frames too slow to count as hitches but slow enough to see: twice
		-- the usual frame, or past a 60 Hz refresh.
		if ms > typical * 2 then
			perf.win_slow = perf.win_slow + 1
		end
		if ms > 16.7 then
			perf.win_over16 = perf.win_over16 + 1
		end
		local sec_max = perf.win_sec_max
		for k, v in pairs(perf.sections) do
			if v > (sec_max[k] or 0) then
				sec_max[k] = v
			end
		end
		if heap > last_heap then
			perf.win_alloc = perf.win_alloc + (heap - last_heap)
		end
		if perf.win_t >= 30 then
			local n = perf.win_frames
			log("perf: %d frames, avg %.1f ms (%.0f fps), worst %.0f ms, %d hitch(es), %d frames over 2x typical, %d over 16.7 ms; mod avg %.2f ms max %.1f ms [%s]; lua heap %.0f MB, allocating %.0f kB/s",
				n, perf.win_ms / n, 1000 * n / perf.win_ms, perf.win_worst, perf.win_hitches, perf.win_slow, perf.win_over16,
				perf.win_mod / n, perf.win_mod_max, max_sections(3), heap / 1024, perf.win_alloc / perf.win_t)
			perf.win_t, perf.win_frames, perf.win_hitches, perf.win_mod, perf.win_mod_max = 0, 0, 0, 0, 0
			perf.win_alloc, perf.win_worst, perf.win_ms, perf.win_slow, perf.win_over16 = 0, 0, 0, 0, 0
		end
	end
	-- Reset per-frame totals (keep the keys, so no table churn).
	perf.mod, perf.update, perf.render = 0, 0, 0
	for k in pairs(perf.sections) do
		perf.sections[k] = 0
	end
end

-- Periodic diagnostics so the console log shows what the mod is doing.
on_require("lua/managers/camera_manager", function()
	local cm = CameraManager
	local inner = cm.update
	if is_patched(cm, "stats") then
		return
	end
	mark_patched(cm, "stats")
	cm.update = function(self, dt, ...)
		-- Scene tracking. The bridge never calls cm.init, so notice the switch
		-- here (the state as the game set it, before the mod touches it).
		local scene = self.state == "follow_menu" and "bridge" or (self.state == "follow" and "mission") or M.scene
		if scene ~= M.scene then
			if scene == "bridge" and M.reset_scene then
				-- Same camera manager (no cm.init): hand it back its own settings.
				pcall(restore_camera, self)
				M.reset_scene()
				log("scene: ship bridge (mission state forgotten)")
			end
			M.scene = scene
		end
		if M.perf_log then
			local ok, err = pcall(perf_frame, self)
			if not ok then
				M.perf_log = false
				log("perf logging stopped: %s", tostring(err))
			end
		end
		local st = M.stats
		st.frames = st.frames + 1
		st.t = st.t + (dt or 0)
		if st.t > 5 and not M.status_log then
			st.t = 0
		elseif st.t > 5 then
			log("state=%s enabled=%s active=%s cursor=%s shown=%s yaw=%.1f pitch=%.1f aim_set=%d (hip %d) aim_zero=%d ray_hit=%d",
				tostring(self.state), tostring(M.enabled), tostring(camera_active()),
				tostring(CursorManager and CursorManager.get_current_cursor and CursorManager:get_current_cursor()),
				tostring(CursorManager and CursorManager.is_shown and CursorManager:is_shown()),
				math.deg(M.yaw or 0), math.deg(M.pitch_rad or 0),
				st.aim_set, st.aim_hip, st.aim_zero, st.ray_hit)
			if (st.err_n or 0) > 0 then
				log("  facing error vs aim: avg %.1f deg, max %.1f deg over %d frames; camera distance %.2f",
					st.err_sum / st.err_n, st.err_max, st.err_n, M.cur_distance or -1)
			end
			if (st.shots_total or 0) > 0 then
				log("  shots tilted toward crosshair: %d of %d; laser redrawn %d frames",
					st.shots_pitched or 0, st.shots_total, st.laser_retargeted or 0)
			end
			if (st.bend_max or 0) > 0.05 then
				log("  spine: max bend %.1f deg; applied in callback %d, before render %d (kept %d, reverted %d)",
					st.bend_max, st.spine_callback or 0, st.spine_render or 0, st.render_kept or 0, st.render_reverted or 0)
			end
			st.spine_callback, st.spine_render, st.render_kept, st.render_reverted = 0, 0, 0, 0
			st.t, st.aim_set, st.aim_hip, st.aim_zero, st.ray_hit = 0, 0, 0, 0, 0
			st.err_sum, st.err_n, st.err_max, st.shots_pitched, st.shots_total = 0, 0, 0, 0, 0
			st.laser_retargeted, st.spine_calls, st.bend_max, st.spine_kept, st.spine_lost = 0, 0, 0, 0, 0
		end
		return inner(self, dt, ...)
	end
end)

---------------------------------------------------------------------------
-- Compass bar (HD2 style) across the top of the screen, with a marker for
-- the point you plotted on the map.
---------------------------------------------------------------------------

-- The map is drawn turned 45 degrees to match the old isometric camera; the
-- HUD converts world -> map with this rotation (hud.lua, world_to_map).
local function map_rotation()
	return Quaternion(Vector3(0, 0, -1), math.rad(-45))
end
local TILE = 24 -- metres per level tile

-- World position of a map ping. Pings are stored as rotate(world - centre) * 2
-- (the HUD scales by 2 * zoom when drawing, and pings omit the zoom).
-- The HUD draws the map with zoom = map_zoom * fit, where fit squeezes the
-- level into 350 map units (hud.lua draw_map); pings are stored without it.
local function map_fit(level)
	local ok, size = pcall(Vector2Aux.unbox, level.map_size)
	if ok and size and size.x > 0 and size.y > 0 then
		return math.min(350 / (size.x * 48), 350 / (size.y * 48))
	end
	return 1
end

local function ping_to_world(level, ping)
	local centre = Vector3(level.width * TILE * 0.5, level.height * TILE * 0.5, 0)
	local k = 2 * map_fit(level)
	return Quaternion.rotate(Quaternion.inverse(map_rotation()), Vector3(ping[1] / k, ping[2] / k, 0)) + centre
end

-- Compass bearing of a flat world direction, same convention as camera yaw.
local function bearing(d)
	return math.atan2(-d.x, d.y)
end

local function wrap_angle(a)
	while a > math.pi do a = a - 2 * math.pi end
	while a <= -math.pi do a = a + 2 * math.pi end
	return a
end

-- "North" is the map's up direction, so the compass agrees with the map.
local function north()
	return bearing(Quaternion.rotate(Quaternion.inverse(map_rotation()), Vector3(0, 1, 0)))
end
local CARDINALS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

---------------------------------------------------------------------------
-- Weapon range. Each weapon copies its range into its state when set up
-- (and HD1 shots dip so they reach the ground at that range). Raise it after
-- setup. Flamers grow their flame from min_range to max_range every frame,
-- so raise those in their settings, once per settings table.
---------------------------------------------------------------------------

local scaled_infos = setmetatable({}, { __mode = "k" })
local RANGE_KEYS = { "max_range", "min_range" }

local function set_state_range(st, orig, on)
	if orig then
		st.range = on and orig * M.range_scale or orig
	end
end

local function set_info_ranges(info, ranges, on)
	for key, v in pairs(ranges) do
		info[key] = on and v * M.range_scale or v
	end
end
local scaled_states = setmetatable({}, { __mode = "k" })

local function scale_range(context)
	local st = type(context) == "table" and context.state
	if not st or scaled_states[st] ~= nil or not M.on() then
		return
	end
	-- Remember the vanilla values (state: the range or false; settings: the
	-- ranges it has), so the mod going off can put them back.
	local orig = type(st.range) == "number" and st.range or false
	scaled_states[st] = orig
	set_state_range(st, orig, true)
	local info = st.weapon_info
	if type(info) == "table" and scaled_infos[info] == nil then
		local ranges = {}
		for _, key in ipairs(RANGE_KEYS) do
			if type(info[key]) == "number" then
				ranges[key] = info[key]
			end
		end
		scaled_infos[info] = ranges
		set_info_ranges(info, ranges, true)
	end
end

-- Mod off (F8, or a vanilla player in the session): every range back to
-- vanilla. On again: scaled again. Idempotent, since each write starts
-- from the remembered vanilla value.
local function apply_range_scaling(on)
	for st, orig in pairs(scaled_states) do
		set_state_range(st, orig, on)
	end
	for info, ranges in pairs(scaled_infos) do
		set_info_ranges(info, ranges, on)
	end
end
M.apply_range_scaling = apply_range_scaling

local function hook_weapon_range(path, class_name)
	on_require(path, function()
		local cls = rawget(_G, class_name)
		if not cls or is_patched(cls, "range") then
			return
		end
		local original = cls.setup_master
		mark_patched(cls, "range")
		local function after(context, ...)
			try("range " .. class_name, scale_range, context)
			return ...
		end
		cls.setup_master = function(self, unit, context, ...)
			return after(context, original(self, unit, context, ...))
		end
	end)
end

-- Firearms, launchers and flamers are also used by boss attachments; they
-- learn their owner after setup (owner_unit), so scale them on their first
-- update with an owner, and only if that owner is a Helldiver (bosses have no
-- character component).
local function scale_owned(masters)
	for _, ctx in pairs(masters or {}) do
		local st = type(ctx) == "table" and ctx.state
		local owner = st and scaled_states[st] == nil and st.owner_unit
		if owner and Unit.alive(owner) and EntityAux.has_component(owner, "character") then
			scale_range(ctx)
		end
	end
end

local function hook_owned_weapon_range(path, class_name)
	on_require(path, function()
		local cls = rawget(_G, class_name)
		if not cls or is_patched(cls, "range") then
			return
		end
		local original = cls.update_masters
		mark_patched(cls, "range")
		local label = "range " .. class_name
		cls.update_masters = function(self, masters, ...)
			try(label, scale_owned, masters)
			return original(self, masters, ...)
		end
	end)
end

-- Beam weapons don't track an owner and aren't used by bosses.
hook_weapon_range("lua/components/beamweapon_component", "BeamweaponComponent")
hook_owned_weapon_range("lua/components/firearm_component", "FirearmComponent")
hook_owned_weapon_range("lua/components/launcher_component", "LauncherComponent")
hook_owned_weapon_range("lua/components/flameweapon_component", "FlameweaponComponent")

-- Is this HUD player entry the local player? Ownership lives on the
-- player's game object (player_go:owned()), as the camera code checks it.
-- Asked for every player several times a frame, so no closure here. Not
-- remembered: the HUD's player objects answer "not owned" while a level
-- loads and only become yours once it's up, so a cached answer goes stale.
local function go_owned(go)
	return go:owned()
end

local function is_owned(p)
	if p.owned == true then
		return true
	end
	local go = p.player_go
	if not go then
		return false
	end
	local ok, owned = pcall(go_owned, go)
	return ok and owned == true
end

local NO_PING = { -1000, -1000 }

-- "No map point" is {-1000, -1000}. Modded players use {-1000, -1003}
-- instead: still no point (a vanilla map draws it far off-screen), but it
-- tells other modded players "I have HD2CAM". Whole numbers so the value
-- survives however the network packs it.
local NO_PING_MODDED = { -1000, -1003 }

local function is_mod_signal(ping)
	return ping and ping[1] == -1000 and ping[2] == -1003
end

local function has_ping(ping)
	return ping and ping[1] and not (ping[1] == -1000 and (ping[2] == -1000 or ping[2] == -1003))
end

-- Every player's map mark: { ping, owned, player_go, index, cleared }. Index
-- is the player's slot, which picks their colour (GameSettings.player_colors).
-- Collected once per frame into one reused list (the mark check and the
-- compass both read it); a mark cleared this frame is flagged, not drawn.
local pings_cache = { frame = -1, list = {} }

local function all_pings(hud)
	local frame = frame_number()
	local list = pings_cache.list
	if pings_cache.frame == frame then
		return list
	end
	pings_cache.frame = frame
	local n = 0
	-- The bridge's player objects have no map_ping; reading it there crashes.
	if M.scene == "mission" and not M.on_bridge then
		for i, p in ipairs(hud.players or {}) do
			if type(p) == "table" and p.player_go and p.player_go:exists() then
				local ping = p.player_go:get("map_ping")
				if has_ping(ping) then
					n = n + 1
					local m = list[n] or {}
					list[n] = m
					m.ping, m.owned, m.player_go, m.index, m.cleared = ping, is_owned(p), p.player_go, i, false
				end
			end
		end
	end
	for i = #list, n + 1, -1 do
		list[i] = nil
	end
	return list
end

local function color_at(colors, index)
	return colors[index]
end

local function player_color(index)
	local gs = rawget(_G, "GameSettings")
	local ok, c = pcall(color_at, gs and gs.player_colors, index)
	if ok and c then
		return Color(255, c.y, c.z, c.w)
	end
	return Color(255, 255, 210, 60)
end

local function dead_state(unit)
	local hs = EntityAux.state(unit, "character").health_state
	return hs and hs.is_dead or false
end

-- Your own mark clears when you reach it or die. Each player's game clears
-- their own mark, since only the owner may change it.
local function clear_own_marks(hud, level)
	local unit = M.local_unit
	if not unit or M.on_bridge then
		return -- player not identified yet (e.g. mod toggled off), or on the ship
	end
	local dead = not Unit.alive(unit)
	if not dead then
		local ok, d = pcall(dead_state, unit)
		dead = ok and d or false
	end
	M.local_dead = dead
	for _, m in ipairs(all_pings(hud)) do
		if m.owned and not m.cleared then
			-- A new mark (map or ping) starts unarmed: one placed close by
			-- would otherwise count as reached the moment it's placed.
			local own = M.own_mark
			if not own or own[1] ~= m.ping[1] or own[2] ~= m.ping[2] then
				M.own_mark = { m.ping[1], m.ping[2] }
				M.own_mark_armed = false
			end
			local reached = false
			if not dead and level and level.width then
				local d = Vector3.length(flat(ping_to_world(level, m.ping) - Unit.world_position(unit, 0)))
				if d > M.mark_reach_distance + 4 then
					M.own_mark_armed = true
				end
				reached = M.own_mark_armed and d < M.mark_reach_distance
			end
			if dead or reached then
				m.player_go:set("map_ping", NO_PING_MODDED)
				m.cleared = true
				log("map mark cleared (%s)", dead and "died" or "reached")
			end
		end
	end
end

-- Compass drawing helpers. They read this frame's layout from `cb` (set by
-- draw_compass) so they are plain functions, not closures made every frame.
local cb = { raw = nil, font = nil, k = 1, cx = 0, cy = 0, inner = 0, span = 1, layer = 60, yaw = 0 }

-- Distance labels ("123m") by metre count, made once each.
local metre_labels = {}

local function metres_label(d)
	local n = math.floor(d + 0.5)
	local s = metre_labels[n]
	if not s then
		s = n .. "m"
		metre_labels[n] = s
	end
	return s
end

-- Text widths (the font measure is a per-label engine call) by pixel size
-- and string; dropped if the HUD font changes.
local width_cache, width_cache_font = {}, nil

local function text_width(str, px)
	if cb.font.font ~= width_cache_font then
		width_cache, width_cache_font = {}, cb.font.font
	end
	local by_size = width_cache[px]
	if not by_size then
		by_size = {}
		width_cache[px] = by_size
	end
	local width = by_size[str]
	if not width then
		width = #str * px * 0.55
		local ok, lo, hi = pcall(Gui.text_extents, cb.raw, str, cb.font.font, px, cb.font.material)
		if ok and lo and hi then
			width = hi.x - lo.x
		end
		by_size[str] = width
	end
	return width
end

local function cb_rect(x, y, rw, rh, color, z)
	Gui.rect(cb.raw, Vector3(x, y, z or cb.layer), Vector2(rw, rh), color)
end

-- Centred horizontally on x.
local function cb_text(str, x, y, size, color, z)
	local px = size * cb.k
	local font = cb.font
	Gui.text(cb.raw, str, font.font, px, font.material, Vector3(x - text_width(str, px) / 2, y, z or cb.layer + 2), color)
end

-- HD2-style circles and diamonds, built from thin horizontal strips
-- (this GUI's triangles don't draw; rectangles do).
local function cb_strips(x, y, r, color, z, diamond)
	local rows = math.max(5, math.floor(r * 2 / math.max(1, cb.k)))
	local h = r * 2 / rows
	for i = 0, rows - 1 do
		local dy = -r + (i + 0.5) * h
		local hw
		if diamond then
			hw = (r - math.abs(dy)) * 0.75
		else
			hw = math.sqrt(math.max(0, r * r - dy * dy))
		end
		if hw > 0.3 then
			Gui.rect(cb.raw, Vector3(x - hw, y + dy - h / 2, z or cb.layer + 3), Vector2(hw * 2, h + 0.6), color)
		end
	end
end

local function cb_circle(x, y, r, color, z)
	cb_strips(x, y, r, color, z, false)
end

local function cb_diamond(x, y, r, color, z)
	cb_strips(x, y, r, color, z, true)
end

-- Bar position of a bearing, or nil (and the offset) when off the bar.
local function cb_x_for(angle)
	-- Bearings increase counter-clockwise, so "left" is a positive offset.
	local rel = wrap_angle(angle - cb.yaw)
	if math.abs(rel) > cb.span then
		return nil, rel
	end
	return cb.cx - rel / cb.span * cb.inner, rel
end

-- Spotted enemies for the compass: every living enemy entity (the entity
-- manager keeps hosts' masters and clients' slaves apart) close enough and,
-- with compass_enemy_los, with nothing static between your head and its
-- chest. Positions are boxed into one reused list.
M.enemies, M.enemy_count = {}, 0
local MAX_SPOTTED = 32

local function enemy_unit_of(key, ctx)
	if is_engine_object(key) then
		return key
	end
	return type(ctx) == "table" and is_engine_object(ctx.unit) and ctx.unit or nil
end

local function enemy_is_dead(unit)
	local ok, hs = pcall(EntityAux.state, unit, "health")
	return ok and type(hs) == "table" and hs.is_dead == true
end

local function scan_enemy_table(t, here, eye, physics, range_sq, n)
	if type(t) ~= "table" then
		return n
	end
	for key, ctx in pairs(t) do
		if n >= MAX_SPOTTED then
			return n
		end
		local unit = enemy_unit_of(key, ctx)
		if unit and Unit.alive(unit) and not enemy_is_dead(unit) then
			local pos = Unit.world_position(unit, 0)
			if Vector3.distance_squared(pos, here) <= range_sq then
				local seen = true
				if M.compass_enemy_los then
					local chest = pos + Vector3(0, 0, 1)
					local dir = chest - eye
					local dist = Vector3.length(dir)
					if dist > 0.5 then
						local hit = PhysicsWorld.immediate_raycast(physics, eye, dir * (1 / dist), dist - 0.3,
							"closest", "types", "statics", "collision_filter", "default")
						seen = not hit
					end
				end
				if seen then
					n = n + 1
					local e = M.enemies[n] or {}
					M.enemies[n] = e
					e.pos = Vector3Aux.box(e.pos or {}, pos)
				end
			end
		end
	end
	return n
end

local function update_spotted_enemies(hud, here)
	local em = hud.entity_manager
	local n = 0
	if em and M.local_unit and Unit.alive(M.local_unit) then
		local eye = here + Vector3(0, 0, 1.5)
		local physics = World.physics_world(camera_world(CameraManager))
		local range_sq = M.compass_enemy_range * M.compass_enemy_range
		local ok, masters = pcall(em.get_master_entities, em, "enemy")
		local ok2, slaves = pcall(em.get_slave_entities, em, "enemy")
		n = scan_enemy_table(ok and masters, here, eye, physics, range_sq, n)
		n = scan_enemy_table(ok2 and slaves, here, eye, physics, range_sq, n)
		if not M.enemies_logged and (masters or slaves) then
			M.enemies_logged = true
			local t = masters or slaves
			local k, v = next(t)
			log("compass enemies: entity table keyed by %s, values %s", type(k), type(v))
		end
	end
	M.enemy_count = n
end

-- Drawn straight onto the HUD's screen GUI in pixels (not through hd_gui,
-- which scales positions and sizes differently), with our own 720p scale.
local function draw_compass(hud)
	local hd = hud.hd_gui
	local font = hd and hd.current_font
	local raw = hd and hd.gui
	if M.on_bridge or not (M.compass and raw and font and camera_active() and M.yaw) then
		return
	end
	local w, h = Application.resolution()
	local k = h / 720 -- layout below is in 720p units
	local cx, cy = w / 2, h - M.compass_top * k
	local half_w, bar_h = M.compass_width / 2 * k, 20 * k
	local inner = half_w - 18 * k -- marks stay this far inside the bar's ends
	local layer = 60
	cb.raw, cb.font, cb.k, cb.cx, cb.cy, cb.inner, cb.layer, cb.yaw = raw, font, k, cx, cy, inner, layer, M.yaw
	cb.span = math.rad(M.compass_span) / 2

	cb_rect(cx - half_w, cy, half_w * 2, bar_h, Color(110, 0, 0, 0))
	cb_rect(cx - k, cy - 4 * k, 2 * k, bar_h + 8 * k, Color(220, 255, 220, 120), layer + 1) -- heading

	local north_bearing = north()
	for i = 0, 23 do
		local x = cb_x_for(north_bearing + i * math.rad(15))
		if x then
			if i % 3 == 0 then
				cb_text(CARDINALS[i / 3 + 1], x, cy + 5 * k, 13, Color(230, 255, 255, 255))
			else
				cb_rect(x - k, cy + 2 * k, 2 * k, 6 * k, Color(160, 255, 255, 255), layer + 1)
			end
		end
	end

	local level = hud.generated_level or hud.custom_level
	if not (level and level.width and M.local_unit and Unit.alive(M.local_unit)) then
		return
	end
	local here = Unit.world_position(M.local_unit, 0)

	-- Enemies you can see (HD2 shows spotted ones): living enemy units within
	-- compass_enemy_range with a clear line from you, refreshed twice a second.
	if M.compass_enemies and hud.entity_manager then
		if M.clock - (M.enemies_at or -10) > 0.5 then
			M.enemies_at = M.clock
			try("spotted enemies", update_spotted_enemies, hud, here)
		end
		local red = Color(230, 235, 60, 50)
		local list = M.enemies
		for i = 1, M.enemy_count or 0 do
			local e = list[i]
			local d = flat(Vector3Aux.unbox(e.pos) - here)
			local x = cb_x_for(bearing(d))
			if x then
				local radius = math.max(2, 4.5 - Vector3.length(d) / 15) * k
				cb_circle(x, cy + bar_h / 2, radius, red, layer + 2)
			end
		end
	end

	-- Objectives and extraction (the map's objective icons). Undiscovered
	-- ones point at the map's search circle, not the exact spot.
	if M.compass_objectives and hud.mission_manager then
		if M.clock - (M.objectives_at or -10) > 1 then
			M.objectives_at = M.clock
			-- Entries (and their boxed positions) are reused across refreshes.
			local list, n = M.objectives or {}, 0
			pcall(function()
				for _, obj in ipairs(hud.mission_manager:get_objectives() or {}) do
					local state = tostring(obj.state)
					if not M.logged_states[state] then
						M.logged_states[state] = true
						log("objective state seen: %s", state)
					end
					local done = state == "completed" or state == "complete" or state == "done" or state == "succeeded"
					if not obj.hide and not done and type(obj.position) == "table" then
						local first = obj.position[1]
						if first then
							local pos = Vector3Aux.unbox(first)
							if obj.objective_hidden_data and obj.objective_hidden_data.offset then
								pos = pos + Vector3Aux.unbox(obj.objective_hidden_data.offset)
							end
							local icon = tostring(obj.icon or "")
							if not M.logged_states["icon:" .. icon] then
								M.logged_states["icon:" .. icon] = true
								log("objective icon seen: %s", icon)
							end
							local extract = string.find(icon, "extract") ~= nil or string.find(icon, "shuttle") ~= nil
							n = n + 1
							local e = list[n] or {}
							list[n] = e
							e.pos = Vector3Aux.box(e.pos or {}, pos)
							e.extract = extract
						end
					end
				end
			end)
			for i = #list, n + 1, -1 do
				list[i] = nil
			end
			M.objectives = list
		end
		for _, o in ipairs(M.objectives or {}) do
			local d = flat(Vector3Aux.unbox(o.pos) - here)
			local x = cb_x_for(bearing(d))
			if x then
				local c = o.extract and Color(255, 80, 220, 110) or Color(255, 255, 210, 60)
				cb_diamond(x, cy + bar_h + 1 * k, 5 * k, c, layer + 3)
				cb_text(metres_label(Vector3.length(d)), x, cy + bar_h + 8 * k, 11, c, layer + 3)
			end
		end
	end

	-- Teammates: a thin tick in their colour along the top edge of the bar.
	if M.compass_teammates then
		for i, p in ipairs(hud.players or {}) do
			if type(p) == "table" and not is_owned(p) and p.player_go and p.player_go:exists() then
				local ok, u = pcall(p.player_go.get, p.player_go, "avatar_unit")
				if ok and u and Unit.alive(u) then
					local x = cb_x_for(bearing(flat(Unit.world_position(u, 0) - here)))
					if x then
						cb_circle(x, cy + bar_h + 2 * k, 3 * k, player_color(i), layer + 3)
					end
				end
			end
		end
	end

	for _, m in ipairs(all_pings(hud)) do
		if not m.cleared then
			local d = flat(ping_to_world(level, m.ping) - here)
			local x, rel = cb_x_for(bearing(d))
			local color = player_color(m.index)
			if x then
				cb_diamond(x, cy + bar_h / 2, 7 * k, color, layer + 3)
			else
				-- Off the bar: pin to the nearer end with an arrow.
				x = rel > 0 and (cx - inner) or (cx + inner)
				cb_text(rel > 0 and "<" or ">", x, cy + 4 * k, 15, color, layer + 3)
			end
			cb_text(metres_label(Vector3.length(d)), x, cy - 16 * k, 12, color, layer + 3)
		end
	end
end

---------------------------------------------------------------------------
-- Co-op. Each player's game runs its own camera. Vanilla frames every
-- player and kills your character after 4 s off your own screen, so a
-- vanilla player can't share a session with free cameras. Modded players
-- signal through their "no map point" value; the mod is on only while every
-- player in the session shows the signal (solo: always), else fully vanilla.
---------------------------------------------------------------------------

M.coop_blocked = true -- until the first check decides
M.coop_seen = setmetatable({}, { __mode = "k" })

local function coop_update(players)
	if M.scene ~= "mission" then
		return -- map_ping is a mission-only field
	end
	local total, modded, local_players = 0, 0, 0
	for _, p in pairs(players or {}) do
		local go = type(p) == "table" and p.player_go
		if go and go:exists() then
			total = total + 1
			local ping = go:get("map_ping")
			if is_owned(p) then
				local_players = local_players + 1
				-- Advertise: replace the vanilla "no point" with ours.
				if ping and ping[1] == -1000 and ping[2] == -1000 then
					go:set("map_ping", NO_PING_MODDED)
				end
				M.coop_seen[go] = true
			elseif is_mod_signal(ping) then
				M.coop_seen[go] = true
			end
			if M.coop_seen[go] then
				modded = modded + 1
			end
		end
	end
	-- Several players on this PC share one screen: a camera that follows one
	-- of them would push the others off it, so stay vanilla.
	local blocked = (total > 1 and modded < total) or local_players > 1
	if blocked ~= M.coop_blocked then
		M.coop_blocked = blocked
		log("co-op: %d player(s), %d with the mod, %d on this PC -> mod %s", total, modded, local_players,
			blocked and "OFF (vanilla)" or "ON")
	end
	-- Controller layout follows only a settled decision (10 s), to avoid churn.
	if blocked then
		M.coop_blocked_since = M.coop_blocked_since or M.clock
		if M.clock - M.coop_blocked_since > 10 and M.set_pad_remap then
			M.set_pad_remap(false)
		end
	else
		M.coop_blocked_since = nil
		if M.set_pad_remap then
			M.set_pad_remap(true)
		end
	end
end
M.coop_update = coop_update

---------------------------------------------------------------------------
-- Pinging (HD2 style): mark the point under the crosshair as your map
-- point, so it shows on everyone's compass and map.
---------------------------------------------------------------------------

local function world_to_ping(level, world)
	local centre = Vector3(level.width * TILE * 0.5, level.height * TILE * 0.5, 0)
	local m = Quaternion.rotate(map_rotation(), flat(world - centre)) * (2 * map_fit(level))
	return { m.x, m.y }
end

-- Where a ping lands: the first thing along the view past your own
-- character (the view ray passes right by it and used to ping your feet).
local function ping_point()
	local world = World.physics_world(camera_world(CameraManager))
	local fwd = Quaternion.forward(CameraManager:get_rotation())
	local origin = CameraManager:get_position() + fwd * ((M.cur_distance or M.distance) + 0.5)
	local me = Unit.world_position(M.local_unit, 0)
	local start, range = origin, M.ping_distance
	for _ = 1, 4 do
		local hit, pos, dist = PhysicsWorld.immediate_raycast(world, start, fwd, range,
			"closest", "types", "both", "collision_filter", "damage_ray")
		if not (hit and pos) then
			break
		end
		if Vector3.length(pos - me) > M.min_aim_distance then
			return pos
		end
		-- Hit yourself (or the ground at your feet): look further along.
		local step = (dist or Vector3.length(pos - start)) + 0.3
		start, range = start + fwd * step, range - step
		if range <= 0 then
			break
		end
	end
	return origin + fwd * M.ping_distance
end

local function handle_ping(hud)
	if mouse_pressed(M.ping_button) then
		M.ping_request = true
	end
	if not M.ping_request then
		return
	end
	M.ping_request = false
	local level = hud.generated_level or hud.custom_level
	if not (level and level.width and M.local_unit and Unit.alive(M.local_unit)) then
		return
	end
	local target = ping_point()
	for _, p in ipairs(hud.players or {}) do
		if type(p) == "table" and is_owned(p) and p.player_go and p.player_go:exists() then
			p.player_go:set("map_ping", world_to_ping(level, target))
			log("pinged (%.0f, %.0f), %.0f m away", target.x, target.y,
				Vector3.length(flat(target - Unit.world_position(M.local_unit, 0))))
			-- The input hook turns this into the game's "move" callout.
			M.callout_pending = M.ping_callout == true
		end
	end
end

---------------------------------------------------------------------------
-- By the crosshair: ammo, reload, hit / kill markers, throw range.
---------------------------------------------------------------------------

local function weapon_state()
	local weapon = M.local_unit and player_weapon_of(M.local_unit)
	if not weapon then
		return nil
	end
	local ok, st = pcall(EntityAux.state_interface, weapon, "weapon")
	return ok and type(st) == "table" and st or nil
end

-- Hits: the weapon marks each shot that connected in shot_id_has_hit.
local function count_new_hits(st)
	local t = st and st.shot_id_has_hit
	if type(t) ~= "table" then
		return 0
	end
	M.hit_seen = M.hit_seen or setmetatable({}, { __mode = "k" })
	local seen = M.hit_seen[t]
	if not seen then
		seen = {}
		M.hit_seen[t] = seen
	end
	local n, new = #t, 0
	for i = math.max(1, n - 64), n do
		if t[i] and not seen[i] then
			seen[i] = true
			new = new + 1
		end
	end
	return new
end

-- Corners of the hit marker, relative to the crosshair.
local HIT_TICKS = { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }

-- "rounds | magazines" labels, made once per combination.
local ammo_labels = {}

local function ammo_label(rounds, mags)
	local by_mags = ammo_labels[rounds]
	if not by_mags then
		by_mags = {}
		ammo_labels[rounds] = by_mags
	end
	local key = mags or false
	local s = by_mags[key]
	if not s then
		s = mags and (rounds .. " | " .. mags) or tostring(rounds)
		by_mags[key] = s
	end
	return s
end

local function reticle_text(raw, font, k, str, x, y, size, color)
	Gui.text(raw, str, font.font, size * k, font.material, Vector3(x, y, 70), color)
end

local function hud_text(raw, font, k, str, x, y, size, color, layer)
	Gui.text(raw, str, font.font, size * k, font.material, Vector3(x, y, layer), color)
end

---------------------------------------------------------------------------
-- HD2-style HUD pieces: spread reticle, weapon panel, damage arc, throw arc.
-- (Scoped in a block: a Lua chunk may hold at most 200 locals.)
---------------------------------------------------------------------------

local hud2 = {}
do

-- How far open the reticle is, 0..1, from the firearm's live spread. Spread
-- is in the weapon's own units; size it between the weapon's min and max,
-- or against the widest this weapon has shown when it has no range.
local spread_widest = setmetatable({}, { __mode = "k" })

local function spread_openness(st)
	local spread = type(st.spread) == "number" and st.spread or 0
	spread = spread * (M.aiming_now and M.aim_spread_scale or M.hip_spread_scale)
	local lo = type(st.spread_min) == "number" and st.spread_min * M.hip_spread_scale or 0
	local hi = type(st.spread_max) == "number" and st.spread_max * M.hip_spread_scale or 0
	if hi > lo then
		return math.max(0, math.min(1, (spread - lo) / (hi - lo)))
	end
	local widest = math.max(spread_widest[st] or 0.0001, spread)
	spread_widest[st] = widest
	return spread / widest
end

-- "weapon_assault_rifle" -> "ASSAULT RIFLE", made once per name.
local display_names = {}

local function display_name(name, prefix)
	local s = display_names[name]
	if not s then
		s = name
		if prefix and string.sub(s, 1, #prefix) == prefix then
			s = string.sub(s, #prefix + 1)
		end
		s = string.upper((string.gsub(s, "_", " ")))
		display_names[name] = s
	end
	return s
end

local capacity_labels = {}

local function capacity_label(n)
	local s = capacity_labels[n]
	if not s then
		s = "/ " .. n
		capacity_labels[n] = s
	end
	return s
end

-- Bottom right: weapon name, rounds / capacity, magazines as pips, fire mode.
local function draw_weapon_panel(raw, font, k, w, h, st)
	if not (M.weapon_panel and st and type(st.rounds) == "number") then
		return
	end
	local layer = 68
	local x, y = w - 236 * k, h - 100 * k
	Gui.rect(raw, Vector3(x, y, layer - 1), Vector2(216 * k, 76 * k), Color(120, 0, 0, 0))
	local info = st.weapon_info or st
	local name = type(info.name) == "string" and info.name or (type(st.name) == "string" and st.name) or nil
	if name then
		hud_text(raw, font, k, display_name(name, "weapon_"), x + 12 * k, y + 6 * k, 11, Color(200, 255, 255, 255), layer)
	end
	local low = st.rounds <= (info.low_ammo_warning or 0)
	local c = low and Color(255, 255, 80, 60) or Color(240, 255, 255, 255)
	if st.is_reloading then
		hud_text(raw, font, k, "RELOADING", x + 12 * k, y + 24 * k, 20, Color(255, 255, 210, 60), layer)
	else
		hud_text(raw, font, k, ammo_label(st.rounds, nil), x + 12 * k, y + 20 * k, 30, c, layer)
		if type(st.magazine_capacity) == "number" then
			hud_text(raw, font, k, capacity_label(st.magazine_capacity), x + 74 * k, y + 36 * k, 12, Color(170, 255, 255, 255), layer)
		end
	end
	local mode = "SEMI"
	if type(st.burst_rounds) == "number" and st.burst_rounds > 1 then
		mode = "BURST"
	elseif st.fully_automatic then
		mode = "AUTO"
	end
	hud_text(raw, font, k, mode, x + 168 * k, y + 8 * k, 11, Color(200, 255, 255, 255), layer)
	-- Magazines: one pip each, dim for the ones used.
	local mags, max_mags = st.magazines, st.magazines_max
	if type(mags) == "number" and type(max_mags) == "number" then
		local n = math.min(max_mags, 14)
		for i = 1, n do
			local full = i <= mags
			Gui.rect(raw, Vector3(x + 12 * k + (i - 1) * 14 * k, y + 56 * k, layer), Vector2(10 * k, 13 * k),
				full and Color(230, 255, 255, 255) or Color(70, 255, 255, 255))
		end
		if max_mags > n then
			hud_text(raw, font, k, ammo_label(mags, nil), x + 12 * k + n * 14 * k + 4 * k, y + 55 * k, 11, Color(200, 255, 255, 255), layer)
		end
	end
end

-- Red edges when you take damage: three nested frames fading inward.
local function draw_hit_vignette(raw, k, w, h)
	if not (M.hit_vignette and M.hit_taken_at) then
		return
	end
	local age = M.clock - M.hit_taken_at
	if age < 0 or age > 0.45 then
		return
	end
	local strength = 1 - age / 0.45
	for band = 1, 3 do
		local width = (70 - band * 18) * k
		local c = Color(math.floor(60 * strength), 255, 20, 10)
		Gui.rect(raw, Vector3(0, 0, 64), Vector2(w, width), c)
		Gui.rect(raw, Vector3(0, h - width, 64), Vector2(w, width), c)
		Gui.rect(raw, Vector3(0, 0, 64), Vector2(width, h), c)
		Gui.rect(raw, Vector3(w - width, 0, 64), Vector2(width, h), c)
	end
end

-- Red arc around the reticle toward whatever hit you last, fading out.
local function draw_damage_arc(raw, k, cx, cy, layer)
	if not (M.damage_arcs and M.hit_from and M.hit_from_at and M.local_unit and Unit.alive(M.local_unit)) then
		return
	end
	local age = M.clock - M.hit_from_at
	if age > 0.7 or age < 0 then
		return
	end
	local d = flat(Vector3Aux.unbox(M.hit_from) - Unit.world_position(M.local_unit, 0))
	if Vector3.length(d) < 0.1 or not M.yaw then
		return
	end
	-- Angle of the attacker relative to the view: 0 = ahead, positive = left.
	local rel = wrap_angle(bearing(d) - M.yaw)
	local radius, half, n = 58 * k, math.rad(22), 9
	local c = Color(math.floor(230 * (1 - age / 0.7)), 255, 50, 40)
	for i = 0, n - 1 do
		local a = rel - half + (i + 0.5) / n * 2 * half
		local px, py = cx - math.sin(a) * radius, cy - math.cos(a) * radius
		Gui.rect(raw, Vector3(px - 2.5 * k, py - 2.5 * k, layer), Vector2(5 * k, 5 * k), c)
	end
end

-- A GUI in the world, for the throw arc. Belongs to the current world:
-- forgotten on a scene change (reset_scene).
local function world_gui()
	if not M.world_gui then
		M.world_gui = World.create_world_gui(camera_world(CameraManager), Matrix4x4.identity(), 1, 1, "immediate")
	end
	return M.world_gui
end

local function world_dot(gui, rot, p, size, color)
	local corner = p - Quaternion.right(rot) * (size / 2) - Quaternion.up(rot) * (size / 2)
	Gui.rect_3d(gui, Matrix4x4.from_quaternion_position(rot, corner), Vector3(0, 0, 0), 1, Vector2(size, size), color)
end

-- Dotted arc from the hand to the crosshair point while holding a throw,
-- with a ring where it lands. The arc is a drawing, not the physics: it
-- shows where, not exactly how high.
local function draw_throw_arc()
	if not (M.throw_arc and M.throwing and M.aim_point and M.local_unit and Unit.alive(M.local_unit)) then
		return
	end
	local target = Vector3Aux.unbox(M.aim_point)
	local hand = Unit.world_position(M.local_unit, 0) + Vector3(0, 0, 1.4)
	local flat_d = Vector3.length(flat(target - hand))
	local apex = math.max(1, math.min(6, flat_d * 0.25))
	local gui = world_gui()
	local rot = CameraManager:get_rotation()
	local size = 0.1 + flat_d * 0.004
	local c = Color(200, 255, 255, 255)
	local n = 14
	for i = 2, n - 1 do
		local t = i / n
		local p = hand + (target - hand) * t + Vector3(0, 0, apex * 4 * t * (1 - t))
		world_dot(gui, rot, p, size, c)
	end
	for i = 0, 11 do
		local a = i / 12 * 2 * math.pi
		world_dot(gui, rot, target + Vector3(math.cos(a) * 0.6, math.sin(a) * 0.6, 0.08), size * 0.8, Color(220, 255, 210, 60))
	end
end

---------------------------------------------------------------------------
-- Stratagem panel (HD2 style): the loadout's stratagems with their arrow
-- codes down the left while the stratagem input is held, the arrows you've
-- entered lit, codes that no longer match dimmed. The list and the entered
-- queue live in game tables found once at runtime (logged).
---------------------------------------------------------------------------

local STATE_NAMES = { "character", "stratagem", "input", "inventory", "stratagems" }
local EMPTY = {}

local function find_stratagem_tables(hud, p, i)
	local info = hud.hud_info and hud.hud_info[i]
	local list_src, queue_src, list_name, queue_name
	if type(info) == "table" and type(info.stratagems) == "table" then
		list_src, list_name = info, "hud_info"
	elseif type(p.stratagems) == "table" then
		list_src, list_name = p, "player"
	end
	if type(info) == "table" and type(info.stratagems_queue) == "table" then
		queue_src, queue_name = info, "hud_info"
	elseif type(p.stratagems_queue) == "table" then
		queue_src, queue_name = p, "player"
	end
	local unit = M.local_unit
	if unit then
		for _, name in ipairs(STATE_NAMES) do
			local ok, st = pcall(EntityAux.state, unit, name)
			if ok and type(st) == "table" then
				if not list_src and type(st.stratagems) == "table" then
					list_src, list_name = st, name .. " state"
				end
				if not queue_src and type(st.stratagems_queue) == "table" then
					queue_src, queue_name = st, name .. " state"
				end
			end
		end
	end
	return list_src, queue_src, list_name, queue_name
end

-- Which HUD player entry is yours.
local function local_player_entry(hud)
	for i, p in ipairs(hud.players or {}) do
		if type(p) == "table" and is_owned(p) then
			return i, p
		end
	end
end

-- Small solid arrow: r is half its size.
local function draw_arrow(raw, k, x, y, r, dir, color, layer)
	local rows = math.max(4, math.floor(r * 2 / math.max(1, k)))
	local h = r * 2 / rows
	for i = 0, rows - 1 do
		local dy = -r + (i + 0.5) * h
		local x0, width
		if dir == "up" then
			local hw = (dy + r) / 2
			x0, width = x - hw, 2 * hw
		elseif dir == "down" then
			local hw = (r - dy) / 2
			x0, width = x - hw, 2 * hw
		elseif dir == "left" then
			x0, width = x - r + math.abs(dy), 2 * r - math.abs(dy)
		else
			x0, width = x - r, 2 * r - math.abs(dy)
		end
		if width > 0.3 then
			Gui.rect(raw, Vector3(x0, y + dy - h / 2, layer), Vector2(width, h + 0.6), color)
		end
	end
end

local seconds_labels = {}

local function seconds_label(n)
	local s = seconds_labels[n]
	if not s then
		s = n .. "s"
		seconds_labels[n] = s
	end
	return s
end

local function draw_stratagem_panel(hud, raw, font, k, w, h)
	if not M.stratagem_panel then
		return
	end
	local i, p = local_player_entry(hud)
	local info = i and hud.hud_info and hud.hud_info[i]
	if not (info and info.state == "stratagems") then
		return
	end
	-- Find (and re-find after a scene change) the game's tables, once a second.
	if not (M.strat_list_src and M.strat_queue_src) and M.clock - (M.strat_probe_at or -10) > 1 then
		M.strat_probe_at = M.clock
		local list_src, queue_src, ln, qn = find_stratagem_tables(hud, p, i)
		M.strat_list_src, M.strat_queue_src = list_src, queue_src
		if list_src and queue_src then
			log("stratagem panel: list in %s, entered arrows in %s", ln, qn)
		elseif not M.strat_probe_logged then
			M.strat_probe_logged = true
			log("stratagem panel: list %s, entered arrows %s", ln or "not found", qn or "not found")
		end
	end
	local list = M.strat_list_src and M.strat_list_src.stratagems
	if type(list) ~= "table" then
		return
	end
	local queue = M.strat_queue_src and M.strat_queue_src.stratagems_queue or EMPTY
	local entered = #queue
	if entered > 0 and not M.strat_queue_logged then
		M.strat_queue_logged = true
		log("stratagem panel: entered arrow looks like %s", tostring(queue[1]))
	end
	local layer = 68
	local rows = 0
	for _, s in ipairs(list) do
		if type(s) == "table" then
			rows = rows + 1
		end
	end
	local x, y = 22 * k, h / 2 - rows * 15 * k
	local base_x = x + 10 * k
	Gui.rect(raw, Vector3(x, y - 6 * k, layer - 1), Vector2(200 * k, rows * 30 * k + 12 * k), Color(110, 0, 0, 0))
	for _, s in ipairs(list) do
		if type(s) == "table" then
			local li = type(s.loadout_info) == "table" and s.loadout_info or EMPTY
			local combo = type(li.combo) == "table" and li.combo or EMPTY
			local matches = true
			for j = 1, entered do
				if combo[j] ~= queue[j] then
					matches = false
					break
				end
			end
			local uses = s.uses_left
			local cooldown = type(s.cooldown_timer) == "number" and s.cooldown_timer or 0
			local available = (uses == nil or uses > 0) and not s.blocked and cooldown <= 0
			local dim = not matches or not available
			local base = dim and Color(110, 200, 200, 200) or Color(230, 255, 255, 255)
			if type(li.name) == "string" then
				hud_text(raw, font, k, display_name(li.name, "stratagem_"), base_x, y, 11, base, layer)
			end
			for j, dir in ipairs(combo) do
				local lit = matches and j <= entered
				draw_arrow(raw, k, base_x + 5 * k + (j - 1) * 14 * k, y + 20 * k, 5 * k, dir,
					lit and Color(255, 255, 220, 60) or base, layer)
			end
			if cooldown > 0 then
				hud_text(raw, font, k, seconds_label(math.ceil(cooldown)), x + 160 * k, y + 14 * k, 11, Color(200, 255, 120, 80), layer)
			elseif type(uses) == "number" then
				hud_text(raw, font, k, ammo_label(uses, nil), x + 170 * k, y + 14 * k, 11, base, layer)
			end
			y = y + 30 * k
		end
	end
end

---------------------------------------------------------------------------
-- Death cam and pad aim assist.
---------------------------------------------------------------------------

-- Living teammates' avatar units, nearest first, refreshed each HUD frame
-- into one reused list.
M.teammates = {}

local function nearer_to_sort_here(a, b)
	local here = Vector3Aux.unbox(M.sort_here)
	return Vector3.distance_squared(Unit.world_position(a, 0), here)
		< Vector3.distance_squared(Unit.world_position(b, 0), here)
end

local function update_teammates(hud)
	local list = M.teammates
	local n = 0
	local here = M.local_unit and Unit.alive(M.local_unit) and Unit.world_position(M.local_unit, 0)
	for _, p in ipairs(hud.players or {}) do
		if type(p) == "table" and not is_owned(p) and p.player_go and p.player_go:exists() then
			local ok, u = pcall(p.player_go.get, p.player_go, "avatar_unit")
			if ok and u and Unit.alive(u) then
				n = n + 1
				list[n] = u
			end
		end
	end
	for j = #list, n + 1, -1 do
		list[j] = nil
	end
	if here and n > 1 then
		M.sort_here = Vector3Aux.box(M.sort_here or {}, here)
		table.sort(list, nearer_to_sort_here)
	end
end

-- Overlap callback: any living enemy near the crosshair point.
local function assist_callback(actors)
	for _, actor in ipairs(actors or {}) do
		local ok, unit = pcall(Actor.unit, actor)
		if ok and unit and Unit.alive(unit) then
			local ok2, enemy = pcall(EntityAux.has_component, unit, "enemy")
			if ok2 and enemy then
				local ok3, hs = pcall(EntityAux.state, unit, "health")
				if not (ok3 and type(hs) == "table" and hs.is_dead) then
					M.assist_at = M.clock
					return
				end
			end
		end
	end
end

-- Asked every frame on a pad; the physics answers on the next step.
local function update_aim_assist()
	if not (M.pad_aim_assist and M.player_pad and camera_active() and not M.on_bridge and M.local_unit) then
		return
	end
	local target = crosshair_point()
	PhysicsWorld.overlap(World.physics_world(camera_world(CameraManager)), assist_callback,
		"shape", "sphere", "position", target, "size", M.aim_assist_radius, "collision_filter", "damage_query")
end
M.update_aim_assist = update_aim_assist

hud2.spread_openness = spread_openness
hud2.draw_weapon_panel = draw_weapon_panel
hud2.draw_damage_arc = draw_damage_arc
hud2.draw_hit_vignette = draw_hit_vignette
hud2.draw_throw_arc = draw_throw_arc
hud2.draw_stratagem_panel = draw_stratagem_panel
hud2.update_teammates = update_teammates
end -- hud2

-- (A second scoped block: the one above already holds as many locals as
-- the chunk allows while it is open.)
do

---------------------------------------------------------------------------
-- Ambient dressing. Once the objectives are known, drop a few pieces of
-- abandoned gear around each (random ring, settled onto the ground by a
-- downward ray) and one crashed shuttle between two of them. Plain units:
-- no game object, so nothing to sync and nothing for the game to track;
-- the world takes them with it on a scene change.
---------------------------------------------------------------------------

M.props = {}

local function ground_at(physics, x, y, z)
	local hit, pos = PhysicsWorld.immediate_raycast(physics, Vector3(x, y, z + 30), Vector3(0, 0, -1), 80,
		"closest", "types", "statics", "collision_filter", "default")
	return hit and pos or nil
end

local function spawn_prop(world, physics, name, x, y, z)
	local pos = ground_at(physics, x, y, z)
	if not pos then
		return false
	end
	local rot = Quaternion(Vector3.up(), math.random() * 2 * math.pi)
	log("ambient props: spawning unit %s", name)
	local unit = World.spawn_unit(world, name, pos, rot)
	M.props[#M.props + 1] = unit
	return true
end

local function spawn_fire(world, physics, effect, x, y, z)
	local pos = ground_at(physics, x, y, z)
	if not pos then
		return false
	end
	M.props[#M.props + 1] = World.create_particles(world, effect, pos)
	return true
end

local function dress_level()
	if not (M.ambient_props and M.on() and M.scene == "mission" and not M.dressed) then
		return
	end
	local objectives = M.objectives
	if type(objectives) ~= "table" or #objectives < 1 then
		return
	end
	M.dressed = true
	local world = camera_world(CameraManager)
	local physics = World.physics_world(world)
	local units, effects = M.prop_units or {}, M.prop_effects or {}
	local placed, count = 0, math.min(#objectives, 4)
	for i = 1, count do
		local centre = Vector3Aux.unbox(objectives[i].pos)
		for _ = 1, M.props_per_objective or 0 do
			local a, r = math.random() * 2 * math.pi, 7 + math.random() * 6
			local x, y = centre.x + math.cos(a) * r, centre.y + math.sin(a) * r
			if #effects > 0 and spawn_fire(world, physics, effects[math.random(#effects)], x, y, centre.z) then
				placed = placed + 1
			end
			if #units > 0 and spawn_prop(world, physics, units[math.random(#units)], x + 2, y + 2, centre.z) then
				placed = placed + 1
			end
		end
	end
	if M.prop_wreck and count >= 2 then
		local a, b = Vector3Aux.unbox(objectives[1].pos), Vector3Aux.unbox(objectives[2].pos)
		local mid = (a + b) * 0.5
		local side = Vector3.normalize(Vector3(-(b.y - a.y), b.x - a.x, 0)) * 25
		if spawn_prop(world, physics, M.prop_wreck, mid.x + side.x, mid.y + side.y, mid.z) then
			placed = placed + 1
		end
	end
	log("ambient props: %d placed around %d objective(s)", placed, count)
end
hud2.dress_level = dress_level

---------------------------------------------------------------------------
-- In-game settings menu. A list of the mod's switches and numbers, drawn
-- on the HUD, moved through with the arrow keys or the D-pad, changed with
-- left / right, saved to hd2cam.cfg next to the log (and loaded at boot).
-- Each entry names the setting it edits and, where a change has to be
-- pushed somewhere, how.
---------------------------------------------------------------------------

local SKY_CHOICES = { "overlay", "engine", "off" }
local WEATHER_CHOICES = { "auto", "off", "desert", "forest", "snow", "city" }

local function refog()
	M.fog_default = M.fog_scale
	M.fog_applied = false
end

local function regrade()
	M.fog_graded = false
end

local function rerender()
	M.render_applied = false -- the view-distance update re-applies next frame
	M.dof_amount_set = nil
end

local function reweather()
	if CameraManager then
		update_weather(CameraManager, false)
	end
	M.weather_key = nil
end

local function remap(v)
	if M.set_pad_remap then
		M.set_pad_remap(v)
	end
end

local function rerange()
	if M.apply_range_scaling then
		M.apply_range_scaling(M.on())
	end
end

local SETTINGS = {
	{ "CAMERA" },
	{ "Camera distance", "distance", 3, 8, 0.5 },
	{ "Camera height", "height", 1, 2.5, 0.1 },
	{ "Shoulder offset", "shoulder", 0, 1.5, 0.1 },
	{ "Camera smoothing", "camera_smoothing", 0, 60, 5 },
	{ "Mouse sensitivity", "sensitivity", 0.05, 0.5, 0.01 },
	{ "Invert mouse Y", "invert_y" },
	{ "Pad look speed", "pad_yaw_speed", 100, 400, 20, function(v) M.pad_pitch_speed = v * 0.6 end },
	{ "Pad invert Y", "pad_invert_y" },
	{ "Aim zoom", "aim_zoom", 0.5, 1, 0.05 },
	{ "Aim camera distance", "aim_distance_scale", 0.5, 1, 0.05 },
	{ "Aim sensitivity", "aim_sensitivity", 0.3, 1, 0.05 },
	{ "Auto-centre when running", "auto_center" },
	{ "Auto-centre only when sprinting", "auto_center_sprint_only" },
	{ "Auto-centre strength", "auto_center_rate", 0.2, 3, 0.2 },
	{ "Camera shake", "camera_shake" },
	{ "GAMEPLAY" },
	{ "Aim walk speed", "aim_walk_speed", 1, 3, 0.25 },
	{ "Hold dive to go prone (s, 0 off)", "prone_hold", 0, 0.6, 0.05 },
	{ "Prone fire", "prone_fire" },
	{ "Pad aim assist", "pad_aim_assist" },
	{ "HD2 pad layout", "pad_remap", nil, nil, nil, remap },
	{ "Ping voice callout", "ping_callout" },
	{ "Escort NPCs safe off-screen", "escort_offscreen_safe" },
	{ "Weapon range x", "range_scale", 1, 3, 0.25, rerange },
	{ "HUD" },
	{ "Compass", "compass" },
	{ "Enemies on compass", "compass_enemies" },
	{ "Reticle ammo / markers", "reticle_hud" },
	{ "Dynamic crosshair", "dynamic_crosshair" },
	{ "Weapon panel", "weapon_panel" },
	{ "Damage arcs", "damage_arcs" },
	{ "Hit vignette", "hit_vignette" },
	{ "Throw arc", "throw_arc" },
	{ "Stratagem panel (mod's)", "stratagem_panel" },
	{ "Crosshair size (pad)", "crosshair_size", 16, 64, 4 },
	{ "GRAPHICS" },
	{ "View distance (fog x)", "fog_scale", 1, 8, 0.5, refog },
	{ "Fog tint strength", "fog_grading_strength", 0, 2, 0.25, regrade },
	{ "Sky", "sky_mode", SKY_CHOICES },
	{ "Weather", "weather", WEATHER_CHOICES, nil, nil, reweather },
	{ "Aim depth of field", "aim_dof", nil, nil, nil, rerender },
	{ "Ambient occlusion", { "renderer_settings", "ssao_enabled" }, nil, nil, nil, rerender },
	{ "Particle shadows", { "renderer_settings", "particles_cast_shadows" }, nil, nil, nil, rerender },
	{ "Tessellation detail", { "renderer_settings", "g_tessellation_detail" }, 1, 4, 1, rerender },
	{ "Tessellation triangle size", { "renderer_settings", "g_tessellation_tri_size" }, 2, 16, 2, rerender },
}

local function setting_get(key)
	if type(key) == "table" then
		local t = M[key[1]]
		return type(t) == "table" and t[key[2]] or nil
	end
	return M[key]
end

local function setting_set(key, v)
	if type(key) == "table" then
		M[key[1]] = M[key[1]] or {}
		M[key[1]][key[2]] = v
	else
		M[key] = v
	end
end

local function key_name(key)
	return type(key) == "table" and (key[1] .. "." .. key[2]) or key
end

local CFG_PATH = os.getenv("APPDATA") .. "\\Arrowhead\\Helldivers\\hd2cam.cfg"

local function save_settings()
	local f = io.open(CFG_PATH, "w")
	if not f then
		log("settings: could not write %s", CFG_PATH)
		return
	end
	f:write("-- HD2CAM settings (edited in-game with ", tostring(M.menu_key), "; delete to reset)\n")
	for _, e in ipairs(SETTINGS) do
		if e[2] then
			local v = setting_get(e[2])
			if type(e[3]) == "table" then
				v = e[3][v] or v -- choices are stored by index
			end
			f:write(key_name(e[2]), "=", tostring(v), "\n")
		end
	end
	f:close()
	log("settings saved to %s", CFG_PATH)
end

local function load_settings()
	local f = io.open(CFG_PATH, "r")
	if not f then
		return
	end
	local by_name = {}
	for _, e in ipairs(SETTINGS) do
		if e[2] then
			by_name[key_name(e[2])] = e
		end
	end
	local n = 0
	for line in f:lines() do
		local k, v = string.match(line, "^%s*([%w_%.]+)%s*=%s*(.-)%s*$")
		local e = k and by_name[k]
		if e then
			local value
			if type(e[3]) == "table" then
				for i, name in ipairs(e[3]) do
					if name == v then
						value = i
					end
				end
			elseif v == "true" or v == "false" then
				value = v == "true"
			else
				value = tonumber(v)
			end
			if value ~= nil then
				setting_set(e[2], value)
				n = n + 1
			end
		end
	end
	f:close()
	log("settings: %d loaded from %s", n, CFG_PATH)
end

local PAD_L3, PAD_R3, PAD_D_LEFT, PAD_D_RIGHT = { "left_thumb", "l3" }, { "right_thumb", "r3" }, { "d_left" }, { "d_right" }
local D_UP_NAMES, D_DOWN_NAMES = { "d_up" }, { "d_down" }
M.menu_row = 2

local function menu_pressed(pad, key, names)
	if key_pressed(key) then
		return true
	end
	return pad ~= nil and pad_pressed(pad, names)
end

local function menu_step(e, dir)
	local v = setting_get(e[2])
	if type(e[3]) == "table" then
		local n = #e[3]
		v = ((tonumber(v) or 1) - 1 + dir) % n + 1
	elseif e[3] then
		v = math.max(e[3], math.min(e[4], (tonumber(v) or e[3]) + dir * e[5]))
		v = math.floor(v / e[5] + 0.5) * e[5]
	else
		v = not v
	end
	setting_set(e[2], v)
	if type(e[6]) == "function" then
		e[6](v)
	end
end

local function value_text(e)
	local v = setting_get(e[2])
	if type(e[3]) == "table" then
		return tostring(e[3][v] or v)
	elseif e[3] then
		return string.format(e[5] < 1 and "%.2f" or "%g", tonumber(v) or 0)
	end
	return v and "on" or "off"
end

-- Open / close: the menu key or Home, or both sticks pressed in together on
-- a pad (an edge on the combined state, so a simultaneous press counts).
local function menu_toggle_pressed(pad)
	local down = key_pressed(M.menu_key) or key_pressed("home")
	if pad then
		local l3 = pad_value(pad, "button", PAD_L3) or 0
		local r3 = pad_value(pad, "button", PAD_R3) or 0
		local both = l3 > 0.5 and r3 > 0.5
		if both and not M.menu_combo_down then
			down = true
		end
		M.menu_combo_down = both
	end
	return down
end

-- Called every HUD frame in a mission: handles the keys, draws when open.
local function settings_menu(hud, raw, font, k, w, h)
	local pad = M.player_pad
	if not M.menu_keys_logged then
		M.menu_keys_logged = true
		log("settings menu: key %s %s, home %s; pad: L3 + R3 together",
			tostring(M.menu_key), Keyboard.button_index(M.menu_key) and "ok" or "UNKNOWN",
			Keyboard.button_index("home") and "ok" or "UNKNOWN")
	end
	if menu_toggle_pressed(pad) and M.clock - (M.menu_toggled_at or -10) > 0.4 then
		M.menu_toggled_at = M.clock
		M.menu_open = not M.menu_open
		if not M.menu_open then
			save_settings()
		else
			log("settings menu opened")
		end
	end
	if not M.menu_open then
		return
	end
	-- Navigation. Section headers are skipped.
	local rows = #SETTINGS
	if menu_pressed(pad, "down", D_DOWN_NAMES) then
		repeat
			M.menu_row = M.menu_row % rows + 1
		until SETTINGS[M.menu_row][2]
	elseif menu_pressed(pad, "up", D_UP_NAMES) then
		repeat
			M.menu_row = (M.menu_row - 2) % rows + 1
		until SETTINGS[M.menu_row][2]
	end
	local e = SETTINGS[M.menu_row]
	if e and e[2] then
		if menu_pressed(pad, "right", PAD_D_RIGHT) then
			menu_step(e, 1)
		elseif menu_pressed(pad, "left", PAD_D_LEFT) then
			menu_step(e, -1)
		end
	end
	-- Drawing: a column on the left, the selected row kept in view.
	local layer = 90
	local visible = 18
	local first = math.max(1, math.min(M.menu_row - math.floor(visible / 2), rows - visible + 1))
	local x, y = 30 * k, 60 * k
	local row_h = 16 * k
	Gui.rect(raw, Vector3(x - 10 * k, y - 26 * k, layer - 1), Vector2(330 * k, (visible + 2) * row_h + 30 * k), Color(200, 0, 0, 0))
	hud_text(raw, font, k, "HD2CAM SETTINGS", x, y - 22 * k, 13, Color(255, 255, 220, 60), layer)
	for i = first, math.min(rows, first + visible - 1) do
		local entry = SETTINGS[i]
		local ry = y + (i - first) * row_h
		if not entry[2] then
			hud_text(raw, font, k, entry[1], x, ry + 2 * k, 11, Color(200, 255, 210, 60), layer)
		else
			local selected = i == M.menu_row
			if selected then
				Gui.rect(raw, Vector3(x - 6 * k, ry - 1 * k, layer - 1), Vector2(322 * k, row_h), Color(90, 255, 255, 255))
			end
			local c = selected and Color(255, 255, 255, 255) or Color(200, 220, 220, 220)
			hud_text(raw, font, k, entry[1], x, ry + 2 * k, 11, c, layer)
			hud_text(raw, font, k, value_text(entry), x + 230 * k, ry + 2 * k, 11, c, layer)
		end
	end
	hud_text(raw, font, k, string.upper(tostring(M.menu_key)) .. " / L3+R3 close & save   up/down pick   left/right change",
		x, y + visible * row_h + 6 * k, 9, Color(170, 255, 255, 255), layer)
end
hud2.settings_menu = settings_menu
M.load_settings = load_settings
end -- dressing + settings

local function draw_reticle_hud(hud)
	local hd = hud.hd_gui
	local font = hd and hd.current_font
	local raw = hd and hd.gui
	if M.on_bridge or not (M.reticle_hud and raw and font and camera_active() and M.local_unit) then
		return
	end
	local w, h = Application.resolution()
	local k = h / 720
	local cx, cy = w / 2, h / 2
	if M.shot_screen then
		cx, cy = M.shot_screen[1], M.shot_screen[2]
	end
	local layer = 70

	local st = weapon_state()
	if count_new_hits(st) > 0 then
		M.hit_at = M.clock
	end

	-- Hit (white) and kill (red, larger) markers: four ticks around the crosshair.
	local kill = M.clock - (M.kill_at or -10) < 0.35
	local hit = kill or M.clock - (M.hit_at or -10) < 0.15
	if hit then
		local r, sz = (kill and 14 or 10) * k, (kill and 4 or 3) * k
		local c = kill and Color(255, 255, 60, 50) or Color(255, 255, 255, 255)
		for _, o in ipairs(HIT_TICKS) do
			Gui.rect(raw, Vector3(cx + o[1] * r - sz / 2, cy + o[2] * r - sz / 2, layer), Vector2(sz, sz), c)
		end
	end

	-- Reticle ticks that open with the weapon's spread (HD2 style).
	if M.dynamic_crosshair and st and (M.combat_now or M.aiming_now) and not M.throwing then
		local open = hud2.spread_openness(st)
		local gap = (5 + 22 * open) * k
		local len, th = 7 * k, 2 * k
		local c = Color(220, 255, 255, 255)
		Gui.rect(raw, Vector3(cx - gap - len, cy - th / 2, layer), Vector2(len, th), c)
		Gui.rect(raw, Vector3(cx + gap, cy - th / 2, layer), Vector2(len, th), c)
		Gui.rect(raw, Vector3(cx - th / 2, cy - gap - len, layer), Vector2(th, len), c)
		Gui.rect(raw, Vector3(cx - th / 2, cy + gap, layer), Vector2(th, len), c)
	end

	hud2.draw_hit_vignette(raw, k, w, h)
	hud2.draw_damage_arc(raw, k, cx, cy, layer)
	hud2.draw_weapon_panel(raw, font, k, w, h, st)

	-- Ammo, below-right of the crosshair, while in combat or reloading
	-- (unless the weapon panel shows it).
	if st and type(st.rounds) == "number" and not M.weapon_panel then
		local reloading = st.is_reloading
		if M.combat_now or reloading then
			local info = st.weapon_info or {}
			local low = st.rounds <= (info.low_ammo_warning or 0)
			local c = low and Color(255, 255, 80, 60) or Color(230, 255, 255, 255)
			local mags = type(st.magazines) == "number" and st.magazines or nil
			reticle_text(raw, font, k, reloading and "RELOADING" or ammo_label(st.rounds, mags),
				cx + 26 * k, cy - 22 * k, 12, c)
		end
	end

	-- Throw range: distance to the crosshair point while holding a throw.
	if M.throwing then
		local ok, target = pcall(crosshair_point)
		if ok and target then
			local d = Vector3.length(flat(target - Unit.world_position(M.local_unit, 0)))
			reticle_text(raw, font, k, metres_label(d), cx + 26 * k, cy + 10 * k, 12, Color(230, 255, 210, 60))
		end
	end
end

-- Aim walk speed. Each frame the character sends the mover a "move_speed":
-- its state's wanted speed, times the weapon's move_speed_aim in the aim
-- and fire states (and a reload factor). Scale it while aiming or firing so
-- you can actually walk, as in HD2. Logged a few times so the numbers show.
on_require("lua/components/character_component", function()
	local cc = CharacterComponent
	if type(cc.queue_command_master) ~= "function" or is_patched(cc, "aim walk") then
		return
	end
	local original = cc.queue_command_master
	mark_patched(cc, "aim walk")
	cc.queue_command_master = function(self, unit, component, command, value, ...)
		if component == "mover" and command == "move_speed" and unit == M.local_unit
			and type(value) == "number" and M.combat_now and camera_active() and not M.on_bridge then
			local scaled = value * (M.aim_walk_speed or 1)
			M.aim_speed_logged = (M.aim_speed_logged or 0)
			if M.aim_speed_logged < 4 and M.clock - (M.aim_speed_logged_at or -10) > 1.5 then
				M.aim_speed_logged, M.aim_speed_logged_at = M.aim_speed_logged + 1, M.clock
				log("aim walk: game move speed %.2f -> %.2f", value, scaled)
			end
			return original(self, unit, component, command, scaled, ...)
		end
		return original(self, unit, component, command, value, ...)
	end
	log("aim walk hook installed")
end)

-- Kills: the game reports each enemy killed with the killer's unit.
on_require("lua/components/character_component", function()
	local cc = CharacterComponent
	if is_patched(cc, "kills") then
		return
	end
	local original = cc.on_enemy_killed
	mark_patched(cc, "kills")
	cc.on_enemy_killed = function(self, a, b, killer, ...)
		if killer ~= nil and killer == M.local_unit then
			M.kill_at = M.clock
		end
		return original(self, a, b, killer, ...)
	end
end)

on_require("lua/hud/hud", function()
	local hud = Hud
	if is_patched(hud, "update") then
		return
	end
	local original = hud.update
	mark_patched(hud, "update")
	-- The HUD tracks the map per player: hud_info[i].state == "map".
	local function update_map_flag(self)
		local open = false
		for i, p in ipairs(self.players or {}) do
			local info = self.hud_info and self.hud_info[i]
			if is_owned(p) and info and info.state == "map" then
				open = true
			end
		end
		M.hud_map_open = open
	end
	local function after_hud(self, ...)
		-- Pick the view distance for this planet type once per mission.
		local level = M.scene == "mission" and self.generated_level
		local env = level and level.environment_name
		if env and env ~= M.environment then
			M.environment = env
			if not M.fog_default then
				M.fog_default = M.fog_scale
			end
			M.fog_scale = M.fog_scale_by_environment[env] or M.fog_default
			M.fog_applied = false
			-- Time of day: the level stores an index into the difficulty
			-- settings' list (dawn, day, dusk, night), or the name itself.
			local tod = level.time_of_day
			local ds = rawget(_G, "DifficultySettings")
			if type(tod) == "number" and ds and type(ds.time_of_day_lookup) == "table" then
				tod = ds.time_of_day_lookup[tod]
			end
			M.time_of_day = type(tod) == "string" and tod or nil
			M.engine_sky_tinted = false
			log("environment: %s (%s, %s) -> view distance fog x%g (F7 to change)", tostring(env),
				tostring(level.mission_type_name), tostring(M.time_of_day), M.fog_scale)
		end
		-- Missions only: the bridge's player objects have no map_ping.
		if CameraManager and CameraManager.state == "follow" and not M.on_bridge then
			try("co-op", coop_update, self.players)
		end
		M.entity_manager = self.entity_manager
		try("map flag", update_map_flag, self)
		try("map marks", clear_own_marks, self, self.generated_level or self.custom_level)
		try("compass", draw_compass, self)
		if camera_active() and not M.on_bridge then
			try("teammates", hud2.update_teammates, self)
			try("ambient props", hud2.dress_level)
			try("ping", handle_ping, self)
			try("reticle hud", draw_reticle_hud, self)
			try("throw arc", hud2.draw_throw_arc)
			local hd = self.hd_gui
			if hd and hd.gui and hd.current_font then
				local w, h = Application.resolution()
				try("stratagem panel", hud2.draw_stratagem_panel, self, hd.gui, hd.current_font, h / 720, w, h)
				try("settings menu", hud2.settings_menu, self, hd.gui, hd.current_font, h / 720, w, h)
			end
		end
		return ...
	end
	-- Our stratagem panel replaces the game's list, once ours has its data.
	if type(hud.draw_stratagems) == "function" and not is_patched(hud, "stratagems") then
		local original_list = hud.draw_stratagems
		mark_patched(hud, "stratagems")
		hud.draw_stratagems = function(self, ...)
			if M.stratagem_panel and M.strat_list_src and camera_active() and not M.on_bridge then
				return
			end
			return original_list(self, ...)
		end
	end
	hud.update = function(self, ...)
		return after_hud(self, original(self, ...))
	end
	log("compass hook installed")
end)


-- In case the world proxy class was loaded before this file ran.
try("world proxy", patch_world_proxy)
try("viewport proxy", patch_viewport_proxy)

-- Saved in-game settings override the defaults above.
if M.load_settings then
	try("settings", M.load_settings)
end

log("HD2CAM %s loaded (press %s in a mission to toggle)", VERSION, M.toggle_key)
