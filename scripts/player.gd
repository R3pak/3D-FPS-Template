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
const slide_cooldown = 0.3
const slide_friction = 18.0
const max_slide_speed = 40.0

# Air constants
const air_control = 0.08
const air_friction = 0.98

# States
var walking = false
var crouching = false
var sliding = false

# Slide state
var slide_cooldown_timer: float = 0.0


func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _input(event):
	if event is InputEventMouseMotion:
		rotate_y(deg_to_rad(-event.relative.x * mouse_sens))
		head.rotate_x(deg_to_rad(-event.relative.y * mouse_sens))
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-90), deg_to_rad(90))


func _physics_process(delta: float) -> void:
	# Cooldown timer
	if slide_cooldown_timer > 0.0:
		slide_cooldown_timer -= delta

	if not is_on_floor():
		# Gravity
		velocity += get_gravity() * delta
		# Air control
		var input_dir := Input.get_vector("left", "right", "forward", "backward")
		if input_dir != Vector2.ZERO:
			var wish_dir = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
			velocity.x += wish_dir.x * air_control * walk_speed
			velocity.z += wish_dir.z * air_control * walk_speed
		# Air friction
		velocity.x *= air_friction
		velocity.z *= air_friction

	# Jump
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		sliding = false
		velocity.y = jump_velocity

	# Slide start
	if Input.is_action_just_pressed("slide") and is_on_floor() and not sliding and slide_cooldown_timer <= 0.0:
		var flat_speed = Vector2(velocity.x, velocity.z).length()
		if flat_speed >= slide_min_entry_speed:
			sliding = true
			slide_cooldown_timer = slide_cooldown
			var boost_dir = Vector3(velocity.x, 0, velocity.z).normalized()
			velocity.x += boost_dir.x * slide_boost
			velocity.z += boost_dir.z * slide_boost
			var flat = Vector2(velocity.x, velocity.z)
			if flat.length() > max_slide_speed:
				flat = flat.normalized() * max_slide_speed
				velocity.x = flat.x
				velocity.z = flat.y

	# Slide cancel
	elif Input.is_action_just_pressed("slide") and sliding:
		sliding = false
		slide_cooldown_timer = slide_cooldown

	# Slide ends when momentum bleeds out
	if sliding and is_on_floor():
		var flat_speed = Vector2(velocity.x, velocity.z).length()
		if flat_speed <= walk_speed:
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
			velocity.x = move_toward(velocity.x, 0, slide_friction * delta)
			velocity.z = move_toward(velocity.z, 0, slide_friction * delta)
		else:
			# normal walk — direct control, no momentum nonsense
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
