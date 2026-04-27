# player.gd
# Repak, Lukky (base script)
#
# Player moveset (strictly movement)
extends CharacterBody3D

# Playerobj references
@onready var head: Node3D = $Head
@onready var standing_collider: CollisionShape3D = $StandingCollider
@onready var crouching_collider: CollisionShape3D = $CrouchingCollider
@onready var ray_cast_3d: RayCast3D = $RayCast3D
@onready var camera_3d: Camera3D = $Head/Camera3D

# Speed variables
var curr_speed = 5.0
const walk_speed = 8.0
const crouch_speed = 3.0

# Movement variables
var lerp_speed = 10.0
const jump_velocity = 12.0
var crouch_depth = -0.5
const mouse_sens = 0.4
var direction = Vector3.ZERO

# Slide constants
const slide_boost = 10.0
const slide_min_entry_speed = 2.0
const max_slide_speed = 40.0
const slide_cancel_jump_boost = 14.0
const slide_grace_distance = 0.3
const slide_steer_speed = 6.0

# Jump constants
const coyote_time = 0.25

# Air constants
const air_control = 0.08
const air_friction = 0.98

# FOV constants
const fov_default = 75.0
const fov_max = 100.0
const fov_lerp_speed = 8.0

# Head bob constants
const bob_freq_walk = 2.2
const bob_freq_slide = 1.4
const bob_amp_walk = 0.09
const bob_amp_slide = 0.03
const bob_lerp_speed = 10.0

# Landing constants
const landing_dip_speed_threshold = 4.0
const landing_dip_max = 0.50
const landing_dip_lerp_in = 35.0
const landing_dip_lerp_out = 4.0

# States
var walking = false
var crouching = false
var sliding = false
var slide_cancel_jumping = false
var was_on_floor = false

# Coyote time state
var coyote_timer = 0.0

# Head bob state
var bob_timer = 0.0
var bob_target = Vector3.ZERO

# Landing state
var landing_dip = 0.0
var pre_land_velocity_y = 0.0
var is_landing = false


func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	camera_3d.fov = fov_default


func _input(event):
	if event is InputEventMouseMotion:
		rotate_y(deg_to_rad(-event.relative.x * mouse_sens))
		head.rotate_x(deg_to_rad(-event.relative.y * mouse_sens))
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-90), deg_to_rad(90))


func _is_near_floor() -> bool:
	if is_on_floor():
		return true
	var space = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + Vector3.DOWN * slide_grace_distance,
		collision_mask
	)
	query.exclude = [self]
	var result = space.intersect_ray(query)
	return result.size() > 0


func _start_slide() -> void:
	sliding = true
	var boost_dir = Vector3(velocity.x, 0, velocity.z).normalized()
	velocity.x += boost_dir.x * slide_boost
	velocity.z += boost_dir.z * slide_boost
	var flat = Vector2(velocity.x, velocity.z)
	if flat.length() > max_slide_speed:
		flat = flat.normalized() * max_slide_speed
		velocity.x = flat.x
		velocity.z = flat.y


func _physics_process(delta: float) -> void:
	var near_floor = _is_near_floor()

	# Track vertical velocity before landing for dip intensity
	if not is_on_floor():
		pre_land_velocity_y = velocity.y

	# Coyote timer
	if is_on_floor():
		coyote_timer = coyote_time
	elif coyote_timer > 0.0:
		coyote_timer -= delta

	var can_jump = coyote_timer > 0.0

	if not is_on_floor():
		# Gravity
		velocity += get_gravity() * delta

		if slide_cancel_jumping:
			# slide cancel jump — air control and friction
			var input_dir := Input.get_vector("left", "right", "forward", "backward")
			if input_dir != Vector2.ZERO:
				var wish_dir = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
				velocity.x += wish_dir.x * air_control * walk_speed
				velocity.z += wish_dir.z * air_control * walk_speed
			velocity.x *= air_friction
			velocity.z *= air_friction
		else:
			# normal jump — hard set horizontal to walk speed
			var input_dir := Input.get_vector("left", "right", "forward", "backward")
			if input_dir != Vector2.ZERO:
				var wish_dir = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
				velocity.x = wish_dir.x * walk_speed
				velocity.z = wish_dir.z * walk_speed
			else:
				velocity.x = move_toward(velocity.x, 0, walk_speed)
				velocity.z = move_toward(velocity.z, 0, walk_speed)

	# Clear slide cancel jump on landing
	if is_on_floor():
		slide_cancel_jumping = false

	# Auto slide on landing while holding slide
	if near_floor and not was_on_floor and Input.is_action_pressed("slide") and not sliding:
		var flat_speed = Vector2(velocity.x, velocity.z).length()
		if flat_speed >= slide_min_entry_speed:
			_start_slide()

	# Jump
	if Input.is_action_just_pressed("ui_accept") and can_jump:
		if sliding:
			# slide cancel jump — full catapult
			var boost_dir = Vector3(velocity.x, 0, velocity.z).normalized()
			velocity.x = boost_dir.x * slide_cancel_jump_boost
			velocity.z = boost_dir.z * slide_cancel_jump_boost
			velocity.y = jump_velocity
			sliding = false
			slide_cancel_jumping = true
			coyote_timer = 0.0
		else:
			# normal jump — lock horizontal to walk speed
			var input_dir := Input.get_vector("left", "right", "forward", "backward")
			if input_dir != Vector2.ZERO:
				var wish_dir = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
				velocity.x = wish_dir.x * walk_speed
				velocity.z = wish_dir.z * walk_speed
			else:
				velocity.x = move_toward(velocity.x, 0, walk_speed)
				velocity.z = move_toward(velocity.z, 0, walk_speed)
			velocity.y = jump_velocity
			slide_cancel_jumping = false
			coyote_timer = 0.0

	# Slide start on press
	if Input.is_action_just_pressed("slide") and near_floor and not sliding:
		var flat_speed = Vector2(velocity.x, velocity.z).length()
		if flat_speed >= slide_min_entry_speed:
			_start_slide()

	# Slide stops only when control released
	if sliding and Input.is_action_just_released("slide"):
		sliding = false

	# Collider states
	if Input.is_action_pressed("crouch"):
		head.position.y = lerp(head.position.y, 0.8 + crouch_depth, delta * lerp_speed)
		standing_collider.disabled = true
		crouching_collider.disabled = false
		crouching = true
		walking = false

	elif sliding:
		head.position.y = lerp(head.position.y, 0.8 + crouch_depth, delta * lerp_speed)
		standing_collider.disabled = true
		crouching_collider.disabled = false

	elif not ray_cast_3d.is_colliding():
		head.position.y = lerp(head.position.y, 0.8, delta * lerp_speed)
		standing_collider.disabled = false
		crouching_collider.disabled = true
		walking = true
		crouching = false
		sliding = false

	# Movement
	if is_on_floor():
		if sliding:
			var slope = get_floor_normal()
			velocity.x += slope.x * 20.0 * delta
			velocity.z += slope.z * 20.0 * delta
			var cam_forward = -transform.basis.z
			cam_forward.y = 0.0
			cam_forward = cam_forward.normalized()
			var current_speed = Vector2(velocity.x, velocity.z).length()
			var current_dir = Vector3(velocity.x, 0, velocity.z).normalized()
			var steered_dir = current_dir.lerp(cam_forward, delta * slide_steer_speed).normalized()
			velocity.x = steered_dir.x * current_speed
			velocity.z = steered_dir.z * current_speed
		else:
			var input_dir := Input.get_vector("left", "right", "forward", "backward")
			var speed = crouch_speed if Input.is_action_pressed("crouch") else walk_speed
			direction = lerp(direction, (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized(), delta * lerp_speed)
			if input_dir != Vector2.ZERO:
				velocity.x = direction.x * speed
				velocity.z = direction.z * speed
			else:
				velocity.x = move_toward(velocity.x, 0, speed)
				velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()

	# Everything below here runs after move_and_slide so floor state is accurate

	# Detect landing this frame
	if is_on_floor() and not was_on_floor:
		if abs(pre_land_velocity_y) > landing_dip_speed_threshold:
			is_landing = true

	# Track floor state for next frame
	was_on_floor = near_floor

	# FOV based on speed
	var flat_speed = Vector2(velocity.x, velocity.z).length()
	var target_fov = lerp(fov_default, fov_max, clamp(flat_speed / max_slide_speed, 0.0, 1.0))
	camera_3d.fov = lerp(camera_3d.fov, target_fov, delta * fov_lerp_speed)

	# Landing dip — snaps down fast, recovers slowly
	if is_landing:
		var dip_strength = clamp(abs(pre_land_velocity_y) / 20.0, 0.0, 1.0) * landing_dip_max
		landing_dip = lerp(landing_dip, dip_strength, delta * landing_dip_lerp_in)
		if landing_dip >= dip_strength * 0.9:
			is_landing = false
	else:
		landing_dip = lerp(landing_dip, 0.0, delta * landing_dip_lerp_out)

	# Head bob
	var bob_freq = bob_freq_slide if sliding else bob_freq_walk
	var bob_amp = bob_amp_slide if sliding else bob_amp_walk

	if is_on_floor() and flat_speed > 0.5:
		bob_timer += delta * bob_freq * flat_speed
		bob_target = Vector3(
			cos(bob_timer * 0.5) * bob_amp,
			sin(bob_timer) * bob_amp,
			0.0
		)
	else:
		bob_timer = 0.0
		bob_target = Vector3.ZERO

	# Combine bob and landing dip on camera
	var combined = bob_target
	combined.y -= landing_dip
	camera_3d.position = camera_3d.position.lerp(combined, delta * bob_lerp_speed)
