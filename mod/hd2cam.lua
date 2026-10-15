-- HD2CAM: over-the-shoulder camera and mouse-look aiming for Helldivers 1.
--
-- Installed in place of foundation/lua/build_date_information, which the
-- game requires very early during boot. We first do what that file did,
-- then wrap `require` so we can patch game classes as soon as they load.

_G.BUILD_DATE_INFORMATION = "2020-12-22 09:33:14"

if rawget(_G, "HD2CAM") then
	return
end

local VERSION = "1.0.0"

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
	sky_day_luminance = 0.8, -- fog this bright or more keeps the engine dome at full brightness
	sky_min_brightness = 0.15, -- darkest the engine dome gets (night)
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

local function key_pressed(name)
	local idx = Keyboard.button_index(name)
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
local function pad_value(pad, kind, names)
	for _, name in ipairs(names) do
		local ok, idx = pcall(pad[kind .. "_index"], name)
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
	local o = cm.follow_offset or { x = 0, y = 0, z = 0 }
	M.saved = {
		follow_spin = cm.follow_spin,
		follow_angle = cm.follow_angle,
		follow_distance = cm.follow_distance,
		min_follow_distance = cm.min_follow_distance,
		max_follow_distance = cm.max_follow_distance,
		fov = cm.fov,
		follow_position_interp = cm.follow_position_interp,
		ignore_level_bounds = cm.ignore_level_bounds,
		offset = { x = o.x, y = o.y, z = o.z },
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
	if cm.follow_offset then
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
local function camera_distance(cm, side, dt)
	local wanted = M.distance
	local unit = next(cm.targets or {})
	if M.camera_collision and unit and Unit.alive(unit) then
		local pivot = Unit.world_position(unit, 0) + side + Vector3(0, 0, M.height)
		local rot = Quaternion.multiply(Quaternion(Vector3.up(), M.yaw), Quaternion(Vector3(-1, 0, 0), M.pitch_rad))
		local back = Quaternion.rotate(rot, Vector3(0, -1, 0))
		local hit, _, dist = PhysicsWorld.immediate_raycast(World.physics_world(camera_world(cm)), pivot, back,
			M.distance + 0.3, "closest", "types", "statics", "collision_filter", "default")
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
	if M.disable_dof then
		if active and not M.dof_off then
			Application.set_renderer_setting("dof_enabled", "false")
			M.dof_off = true
		elseif not active and M.dof_off then
			local user = Application.user_setting("render_settings", "dof_enabled")
			Application.set_renderer_setting("dof_enabled", tostring(user ~= false))
			M.dof_off = false
		end
	end

	if not active then
		if M.fog_applied then
			vp:remove_shading_environment_variable("fog_depth_range")
			M.fog_applied = false
		end
		if M.saved_far then
			Camera.set_far_range(camera, M.saved_far)
		end
		M.saved_far, M.fog_base, M.view_frames = nil, nil, 0
		return
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
		local factor = math.max(M.sky_min_brightness, math.min(1, lum / M.sky_day_luminance))
		set_dome_intensity(M.engine_sky, SKYDOME_INTENSITY * factor)
		log("sky: fog luminance %.2f -> dome brightness x%.2f", lum, factor)
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
	local delta = Mouse.axis(Mouse.axis_index("mouse"))
	if delta then
		local s = math.rad(M.sensitivity)
		local dy = M.invert_y and -delta.y or delta.y
		M.yaw = M.yaw - delta.x * s
		M.pitch_rad = M.pitch_rad + dy * s
		looked_vertically = math.abs(delta.y) > 0.5
	end

	-- Right stick of the pad the player is using (set by the input hook).
	local pad = M.player_pad
	if pad and dt then
		local stick = pad_value(pad, "axis", { "right" })
		if stick then
			local mult = pad_aiming(pad) and M.pad_aim_slowdown or 1
			local sy = M.pad_invert_y and -stick.y or stick.y
			M.yaw = M.yaw - stick_curve(stick.x) * math.rad(M.pad_yaw_speed) * mult * dt
			M.pitch_rad = M.pitch_rad - stick_curve(sy) * math.rad(M.pad_pitch_speed) * mult * dt
			looked_vertically = looked_vertically or stick_curve(sy) ~= 0
		end
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

	-- Zoom while aiming.
	if M.saved and M.saved.fov then
		local want = M.saved.fov * (M.aiming_now and M.aim_zoom or 1)
		M.cur_fov = (M.cur_fov or M.saved.fov) + (want - (M.cur_fov or M.saved.fov)) * math.min(1, (dt or 0) * 10)
		cm.fov = M.cur_fov
	end

	local side = flat_right(M.yaw) * (M.shoulder * M.cur_side)
	local distance = camera_distance(cm, side, dt)

	cm.follow_spin = M.yaw
	cm.follow_angle = M.pitch_rad - M.recoil
	cm.follow_distance = distance
	cm.min_follow_distance = distance
	cm.max_follow_distance = distance

	-- The game eases the camera toward its goal at 0.6 x dt per frame, which
	-- suits a top-down view but makes an orbit camera trail behind mouse
	-- turns. Snap to the goal instead. Also skip the push that keeps the
	-- top-down view point inside the map; a low camera trips it constantly.
	if dt and dt > 0 then
		cm.follow_position_interp = 1 / dt
	end
	cm.ignore_level_bounds = true

	-- The game adds (offset.x - 1, offset.y - 1, offset.z) to the target.
	cm.follow_offset = cm.follow_offset or {}
	cm.follow_offset.x = side.x + 1
	cm.follow_offset.y = side.y + 1
	cm.follow_offset.z = M.height

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

		local bridge_targets
		M.on_bridge = false
		if M.enabled and M.bridge_camera and self.state == "follow_menu" and in_game_cursor() then
			local avatar
			pcall(function()
				for _, p in pairs(players or {}) do
					if p.player_go and p.player_go:owned() then
						local u = p.player_go:get("avatar_unit")
						if u and Unit.alive(u) then
							avatar = u
						end
					end
				end
			end)
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
		try("camera", update_camera, self, dt)
		if M.update_bend_amount then
			try("spine amount", M.update_bend_amount, dt)
		end
		-- Not camera_active(): keep the view distance while the pause menu is up.
		-- Missions only: the bridge's shading environment lacks the fog
		-- variables, and reading a missing one crashes the engine outright.
		local mission = M.on() and self.state == "follow" and not M.on_bridge
		try("view distance", update_view_distance, self, mission)
		try("sky", update_sky, self, mission)
		-- Co-op: the vanilla camera frames every player; follow only yours.
		local coop_targets
		if mission and not bridge_targets and M.local_unit and self.targets and self.targets[M.local_unit]
			and next(self.targets, next(self.targets)) ~= nil then
			coop_targets = self.targets
			self.targets = { [M.local_unit] = coop_targets[M.local_unit] }
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
		M.hit_seen, M.ping_request, M.throwing = nil, false, false
		M.coop_blocked, M.coop_blocked_since = true, nil
		if M.forget_units then
			M.forget_units()
		end
		M.saved, M.yaw, M.cur_distance, M.cur_fov, M.recoil = nil, nil, nil, nil, 0
		M.fog_applied, M.fog_base, M.saved_far, M.view_frames = false, nil, nil, 0
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

-- World point under the crosshair: cast along the camera's view ray, the
-- same way bullets collide ("damage_ray"), starting past the player so the
-- ray cannot hit them.
local function crosshair_point()
	local cam_pos = CameraManager:get_position()
	local fwd = Quaternion.forward(CameraManager:get_rotation())
	local start = cam_pos + fwd * ((M.cur_distance or M.distance) + 0.5)
	local hit, pos = PhysicsWorld.immediate_raycast(World.physics_world(camera_world(CameraManager)), start, fwd,
		M.aim_distance, "closest", "types", "both", "collision_filter", "damage_ray")
	if hit and pos then
		M.stats.ray_hit = M.stats.ray_hit + 1
		return pos, fwd
	end
	return start + fwd * M.aim_distance, fwd
end

-- Muzzle position for the given body facing, from the weapon's settings.
local function muzzle_position(unit, facing)
	local pos = Unit.world_position(unit, 0)
	local cs = EntityAux.state(unit, "character")
	local weapon = cs and cs.current_weapon
	if not (weapon and Unit.alive(weapon)) then
		return pos
	end
	local settings = LuaSettingsManager:get_settings_by_unit(weapon)
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
local function crosshair_direction(unit)
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
	local info = LuaSettingsManager:get_settings_by_unit(weapon)
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
		M.shot_screen = { sp.x, sp.y }
	end
end

local function apply_crosshair_aim(input_component, unit, data)
	M.local_unit = unit
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

local function patch_world_proxy()
	local wp = rawget(_G, "WorldProxy")
	if not wp or is_patched(wp, "anim") then
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
	vp.render = function(self, ...)
		if M.spine_bend then
			try("spine render", spine_render_check)
		end
		return original(self, ...)
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

	local R3, LB, D_UP = { "right_thumb", "r3" }, { "left_shoulder", "l1" }, { "d_up" }
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
		-- D-pad up (without LB, which is stratagem input) pings.
		local lb = pad_value(pad, "button", LB)
		if not (lb and lb > 0.5) and pad_pressed(pad, D_UP) then
			M.ping_request = true
			data.communication_yes = false
		end
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
	sm.update = function(unit, context, ...)
		return after_update(unit, context, original(unit, context, ...))
	end
	log("turn hook installed")
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
		if heap > last_heap then
			perf.win_alloc = perf.win_alloc + (heap - last_heap)
		end
		if perf.win_t >= 30 then
			local n = perf.win_frames
			log("perf: %d frames, avg %.1f ms (%.0f fps), worst %.0f ms, %d hitch(es); mod avg %.2f ms max %.1f ms; lua heap %.0f MB, allocating %.0f kB/s",
				n, perf.win_ms / n, 1000 * n / perf.win_ms, perf.win_worst, perf.win_hitches,
				perf.win_mod / n, perf.win_mod_max, heap / 1024, perf.win_alloc / perf.win_t)
			perf.win_t, perf.win_frames, perf.win_hitches, perf.win_mod, perf.win_mod_max = 0, 0, 0, 0, 0
			perf.win_alloc, perf.win_worst, perf.win_ms = 0, 0, 0
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
local scaled_states = setmetatable({}, { __mode = "k" })

local function scale_range(context)
	local st = type(context) == "table" and context.state
	if not st or scaled_states[st] or not M.on() then
		return
	end
	scaled_states[st] = true
	if type(st.range) == "number" then
		st.range = st.range * M.range_scale
	end
	local info = st.weapon_info
	if type(info) == "table" and not scaled_infos[info] then
		scaled_infos[info] = true
		for _, key in ipairs({ "max_range", "min_range" }) do
			if type(info[key]) == "number" then
				info[key] = info[key] * M.range_scale
			end
		end
	end
end

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
		local owner = st and not scaled_states[st] and st.owner_unit
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
		cls.update_masters = function(self, masters, ...)
			try("range " .. class_name, scale_owned, masters)
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
local function is_owned(p)
	if p.owned == true then
		return true
	end
	local ok, owned = pcall(function()
		return p.player_go and p.player_go:owned()
	end)
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

-- Every player's map mark: { ping, owned, player_go, index }. Index is the
-- player's slot, which picks their colour (GameSettings.player_colors).
local function all_pings(hud)
	local list = {}
	-- The bridge's player objects have no map_ping; reading it there crashes.
	if M.scene ~= "mission" or M.on_bridge then
		return list
	end
	for i, p in ipairs(hud.players or {}) do
		if type(p) == "table" and p.player_go and p.player_go:exists() then
			local ping = p.player_go:get("map_ping")
			if has_ping(ping) then
				list[#list + 1] = { ping = ping, owned = is_owned(p), player_go = p.player_go, index = i }
			end
		end
	end
	return list
end

local function player_color(index)
	local ok, c = pcall(function()
		return GameSettings.player_colors[index]
	end)
	if ok and c then
		return Color(255, c.y, c.z, c.w)
	end
	return Color(255, 255, 210, 60)
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
		pcall(function()
			local hs = EntityAux.state(unit, "character").health_state
			dead = hs and hs.is_dead or false
		end)
	end
	for _, m in ipairs(all_pings(hud)) do
		if m.owned then
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
				log("map mark cleared (%s)", dead and "died" or "reached")
			end
		end
	end
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
	local span = math.rad(M.compass_span) / 2
	local layer = 60

	local function rect(x, y, rw, rh, color, z)
		Gui.rect(raw, Vector3(x, y, z or layer), Vector2(rw, rh), color)
	end
	local function text(str, x, y, size, color, z)
		-- Centre horizontally on x.
		local px = size * k
		local width = #str * px * 0.55
		local ok, lo, hi = pcall(Gui.text_extents, raw, str, font.font, px, font.material)
		if ok and lo and hi then
			width = hi.x - lo.x
		end
		Gui.text(raw, str, font.font, px, font.material, Vector3(x - width / 2, y, z or layer + 2), color)
	end

	-- HD2-style circles and diamonds, built from thin horizontal strips
	-- (this GUI's triangles don't draw; rectangles do).
	local function strips(x, y, r, color, z, half_width)
		local rows = math.max(5, math.floor(r * 2 / math.max(1, k)))
		local h = r * 2 / rows
		for i = 0, rows - 1 do
			local dy = -r + (i + 0.5) * h
			local hw = half_width(dy)
			if hw > 0.3 then
				Gui.rect(raw, Vector3(x - hw, y + dy - h / 2, z or layer + 3), Vector2(hw * 2, h + 0.6), color)
			end
		end
	end
	local function circle(x, y, r, color, z)
		strips(x, y, r, color, z, function(dy)
			return math.sqrt(math.max(0, r * r - dy * dy))
		end)
	end
	local function diamond(x, y, r, color, z)
		strips(x, y, r, color, z, function(dy)
			return (r - math.abs(dy)) * 0.75
		end)
	end

	local function x_for(angle)
		-- Bearings increase counter-clockwise, so "left" is a positive offset.
		local rel = wrap_angle(angle - M.yaw)
		if math.abs(rel) > span then
			return nil, rel
		end
		return cx - rel / span * inner, rel
	end

	rect(cx - half_w, cy, half_w * 2, bar_h, Color(110, 0, 0, 0))
	rect(cx - k, cy - 4 * k, 2 * k, bar_h + 8 * k, Color(220, 255, 220, 120), layer + 1) -- heading

	local north_bearing = north()
	for i = 0, 23 do
		local x = x_for(north_bearing + i * math.rad(15))
		if x then
			if i % 3 == 0 then
				text(CARDINALS[i / 3 + 1], x, cy + 5 * k, 13, Color(230, 255, 255, 255))
			else
				rect(x - k, cy + 2 * k, 2 * k, 6 * k, Color(160, 255, 255, 255), layer + 1)
			end
		end
	end

	local level = hud.generated_level or hud.custom_level
	if not (level and level.width and M.local_unit and Unit.alive(M.local_unit)) then
		return
	end
	local here = Unit.world_position(M.local_unit, 0)

	-- Enemy patrols the radar has picked up (the map's red icons): patrols
	-- within the ping radius of the squad. Refreshed once a second.
	if M.compass_enemies and hud.patrol_manager then
		if M.clock - (M.patrols_at or -10) > 1 then
			M.patrols_at = M.clock
			local ok, list = pcall(hud.patrol_manager.get_patrol_hud_info, hud.patrol_manager)
			M.patrols = ok and list or nil
		end
		local red = Color(230, 235, 60, 50)
		for _, info in ipairs(M.patrols or {}) do
			local ok, pos = pcall(Vector3Aux.unbox, info.position)
			if ok and pos then
				local x = x_for(bearing(flat(pos - here)))
				if x then
					local radius = math.min(5, 2.5 + 0.5 * (info.amount or 1)) * k
					circle(x, cy + bar_h / 2, radius, red, layer + 2)
				end
			end
		end
	end

	-- Objectives and extraction (the map's objective icons). Undiscovered
	-- ones point at the map's search circle, not the exact spot.
	if M.compass_objectives and hud.mission_manager then
		if M.clock - (M.objectives_at or -10) > 1 then
			M.objectives_at = M.clock
			local list = {}
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
							list[#list + 1] = { pos = Vector3Aux.box({}, pos), extract = extract }
						end
					end
				end
			end)
			M.objectives = list
		end
		for _, o in ipairs(M.objectives or {}) do
			local d = flat(Vector3Aux.unbox(o.pos) - here)
			local x = x_for(bearing(d))
			if x then
				local c = o.extract and Color(255, 80, 220, 110) or Color(255, 255, 210, 60)
				diamond(x, cy + bar_h + 1 * k, 5 * k, c, layer + 3)
				text(string.format("%dm", math.floor(Vector3.length(d) + 0.5)), x, cy + bar_h + 8 * k, 11, c, layer + 3)
			end
		end
	end

	-- Teammates: a thin tick in their colour along the top edge of the bar.
	if M.compass_teammates then
		for i, p in ipairs(hud.players or {}) do
			if type(p) == "table" and not is_owned(p) and p.player_go and p.player_go:exists() then
				local ok, u = pcall(p.player_go.get, p.player_go, "avatar_unit")
				if ok and u and Unit.alive(u) then
					local x = x_for(bearing(flat(Unit.world_position(u, 0) - here)))
					if x then
						circle(x, cy + bar_h + 2 * k, 3 * k, player_color(i), layer + 3)
					end
				end
			end
		end
	end

	for _, m in ipairs(all_pings(hud)) do
		local d = flat(ping_to_world(level, m.ping) - here)
		local x, rel = x_for(bearing(d))
		local color = player_color(m.index)
		if x then
			diamond(x, cy + bar_h / 2, 7 * k, color, layer + 3)
		else
			-- Off the bar: pin to the nearer end with an arrow.
			x = rel > 0 and (cx - inner) or (cx + inner)
			text(rel > 0 and "<" or ">", x, cy + 4 * k, 15, color, layer + 3)
		end
		text(string.format("%dm", math.floor(Vector3.length(d) + 0.5)), x, cy - 16 * k, 12, color, layer + 3)
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
	local function text(str, x, y, size, color)
		Gui.text(raw, str, font.font, size * k, font.material, Vector3(x, y, layer), color)
	end

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
		for _, o in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
			Gui.rect(raw, Vector3(cx + o[1] * r - sz / 2, cy + o[2] * r - sz / 2, layer), Vector2(sz, sz), c)
		end
	end

	-- Ammo, below-right of the crosshair, while in combat or reloading.
	if st and type(st.rounds) == "number" then
		local reloading = st.is_reloading
		if M.combat_now or reloading then
			local info = st.weapon_info or {}
			local low = st.rounds <= (info.low_ammo_warning or 0)
			local c = low and Color(255, 255, 80, 60) or Color(230, 255, 255, 255)
			local mags = type(st.magazines) == "number" and (" | " .. st.magazines) or ""
			text(reloading and "RELOADING" or (st.rounds .. mags), cx + 26 * k, cy - 22 * k, 12, c)
		end
	end

	-- Throw range: distance to the crosshair point while holding a throw.
	if M.throwing then
		local ok, target = pcall(crosshair_point)
		if ok and target then
			local d = Vector3.length(flat(target - Unit.world_position(M.local_unit, 0)))
			text(string.format("%dm", math.floor(d + 0.5)), cx + 26 * k, cy + 10 * k, 12, Color(230, 255, 210, 60))
		end
	end
end

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
			log("environment: %s (%s) -> view distance fog x%g (F7 to change)", tostring(env),
				tostring(level.mission_type_name), M.fog_scale)
		end
		-- Missions only: the bridge's player objects have no map_ping.
		if CameraManager and CameraManager.state == "follow" and not M.on_bridge then
			try("co-op", coop_update, self.players)
		end
		try("map flag", update_map_flag, self)
		try("map marks", clear_own_marks, self, self.generated_level or self.custom_level)
		try("compass", draw_compass, self)
		if camera_active() and not M.on_bridge then
			try("ping", handle_ping, self)
			try("reticle hud", draw_reticle_hud, self)
		end
		return ...
	end
	hud.update = function(self, ...)
		return after_hud(self, original(self, ...))
	end
	log("compass hook installed")
end)


-- In case the world proxy class was loaded before this file ran.
try("world proxy", patch_world_proxy)
try("viewport proxy", patch_viewport_proxy)

log("HD2CAM %s loaded (press %s in a mission to toggle)", VERSION, M.toggle_key)
