class Game extends AppChildProcess {
	public static var ME : Game;

	public var options(get,never) : Options; inline function get_options() return App.ME.options;

	/** Game controller (pad or keyboard) **/
	public var ca : ControllerAccess<GameAction>;
	public var mouseDowns : Map<MouseButton, Bool> = new Map();

	/** Particles **/
	public var fx : Fx;

	/** Basic viewport control **/
	public var camera : Camera;

	public var hero : en.Hero;

	/** Container of all visual game objects. Ths wrapper is moved around by Camera. **/
	public var scroller : h2d.Layers;

	/** Level data **/
	public var level : Level;

	/** UI **/
	public var hud : ui.Hud;

	/** Slow mo internal values**/
	var curGameSpeed = 1.0;
	var slowMos : Map<SlowMoId, { id:SlowMoId, t:Float, f:Float }> = new Map();


	public function new() {
		super();

		ME = this;
		ca = App.ME.controller.createAccess();
		ca.lockCondition = isGameControllerLocked;
		createRootInLayers(App.ME.root, Const.DP_BG);
		dn.Gc.runNow();

		scroller = new h2d.Layers();
		root.add(scroller, Const.DP_BG);
		scroller.filter = new h2d.filter.Nothing(); // force rendering for pixel perfect

		fx = new Fx();
		hud = new ui.Hud();
		camera = new Camera();

		App.ME.scene.addEventListener(onEvent);

		startLevel(Assets.worldData.all_worlds.SampleWorld.all_levels.FirstLevel);
	}


	function onEvent(ev:hxd.Event) {
		switch ev.kind {
			case EPush: mouseDowns.set(ev.button==0?MB_Left:MB_Right, true);
			case ERelease: mouseDowns.remove(ev.button==0?MB_Left:MB_Right);
			case EMove:
			case EOver:
			case EOut:
			case EWheel:
			case EFocus:
			case EFocusLost:
			case EKeyDown:
			case EKeyUp:
			case EReleaseOutside:
			case ETextInput:
			case ECheck:
		}
	}

	public function onAppBlur() {
		mouseDowns = new Map();
	}

	public function onMouseLeave() {
		mouseDowns = new Map();
	}

	public inline function isMouseDown(btn:MouseButton) {
		return mouseDowns.exists(btn);
	}

	public static function isGameControllerLocked() {
		return !exists() || ME.isPaused() || App.ME.anyInputHasFocus();
	}


	public static inline function exists() {
		return ME!=null && !ME.destroyed;
	}


	/** Load a level **/
	function startLevel(l:World.World_Level) {
		// Delete existing level
		if( level!=null )
			level.destroy();
		fx.clear();
		for(e in Entity.ALL) // <---- Replace this with more adapted entity destruction (eg. keep the player alive)
			e.destroy();
		garbageCollectEntities();

		// Create level
		level = new Level(l);
		var inf = level.data.l_Entities.all_PlayerStart[0];
		hero = new en.Hero(inf.cx, inf.cy);
		for(inf in level.data.l_Entities.all_Enemy)
			new en.Mob(inf.cx, inf.cy);

		// Init misc stuff
		camera.centerOnTarget();
		camera.trackEntity(hero, true);
		hud.onLevelStart();
		dn.Process.resizeAll();
		dn.Gc.runNow();

		// #if !debug
		if( !App.ME.cd.hasSetS("disclaimerOnce",Const.INFINITE) ) {
			var win = new ui.win.SimpleMenu();
			win.content.horizontalAlign = Middle;
			win.content.padding = 8;
			win.addText("This demo is not an actual game, but a playable demonstration of various game feel techniques.");
			win.addText("Press ENTER (keyboard) or START (gamepad) to open the menu.");
			win.addSpacer();
			win.addButton("Continue", ()->{});
		}
		// #end
	}

	public function restartLevel() {
		startLevel(level.data);
	}



	/** Called when either CastleDB or `const.json` changes on disk **/
	@:allow(App)
	function onDbReload() {
		hud.notify("DB reloaded");
	}


	/** Called when LDtk file changes on disk **/
	@:allow(assets.Assets)
	function onLdtkReload() {
		hud.notify("LDtk reloaded");
		if( level!=null )
			startLevel( Assets.worldData.all_worlds.SampleWorld.getLevel(level.data.uid) );
	}

	/** Window/app resize event **/
	override function onResize() {
		super.onResize();
	}


	/** Garbage collect any Entity marked for destruction. This is normally done at the end of the frame, but you can call it manually if you want to make sure marked entities are disposed right away, and removed from lists. **/
	public function garbageCollectEntities() {
		if( Entity.GC==null || Entity.GC.allocated==0 )
			return;

		for(e in Entity.GC)
			e.dispose();
		Entity.GC.empty();
	}

	/** Called if game is destroyed, but only at the end of the frame **/
	override function onDispose() {
		super.onDispose();

		App.ME.scene.removeEventListener(onEvent);
		fx.destroy();
		for(e in Entity.ALL)
			e.destroy();
		garbageCollectEntities();

		if( ME==this )
			ME = null;
	}


	/**
		Start a cumulative slow-motion effect that will affect `tmod` value in this Process
		and all its children.

		@param sec Realtime second duration of this slowmo
		@param speedFactor Cumulative multiplier to the Process `tmod`
	**/
	public function addSlowMo(id:SlowMoId, sec:Float, speedFactor=0.3) {
		if( slowMos.exists(id) ) {
			var s = slowMos.get(id);
			s.f = speedFactor;
			s.t = M.fmax(s.t, sec);
		}
		else
			slowMos.set(id, { id:id, t:sec, f:speedFactor });
	}


	/** The loop that updates slow-mos **/
	final function updateSlowMos() {
		// Timeout active slow-mos
		for(s in slowMos) {
			s.t -= utmod * 1/Const.FPS;
			if( s.t<=0 )
				slowMos.remove(s.id);
		}

		// Update game speed
		var targetGameSpeed = 1.0;
		for(s in slowMos)
			targetGameSpeed*=s.f;
		curGameSpeed += (targetGameSpeed-curGameSpeed) * (targetGameSpeed>curGameSpeed ? 0.2 : 0.6);

		if( M.fabs(curGameSpeed-targetGameSpeed)<=0.001 )
			curGameSpeed = targetGameSpeed;
	}


	/**
		Pause briefly the game for 1 frame: very useful for impactful moments,
		like when hitting an opponent in Street Fighter ;)
	**/
	public inline function stopFrame() {
		ucd.setS("stopFrame", 4/Const.FPS);
	}


	/** Loop that happens at the beginning of the frame **/
	override function preUpdate() {
		super.preUpdate();

		for(e in Entity.ALL) if( !e.destroyed ) e.preUpdate();
	}

	/** Loop that happens at the end of the frame **/
	override function postUpdate() {
		super.postUpdate();

		// Update slow-motions
		updateSlowMos();
		baseTimeMul = ( 0.2 + 0.8*curGameSpeed ) * ( ucd.has("stopFrame") ? 0.1 : 1 );
		Assets.tiles.tmod = tmod;

		// Entities post-updates
		for(e in Entity.ALL) if( !e.destroyed ) e.postUpdate();

		// Entities final updates
		for(e in Entity.ALL) if( !e.destroyed ) e.finalUpdate();

		// Dispose entities marked as "destroyed"
		garbageCollectEntities();
	}


	/** Main loop but limited to 30 fps (so it might not be called during some frames) **/
	override function fixedUpdate() {
		super.fixedUpdate();

		// Entities "30 fps" loop
		for(e in Entity.ALL) if( !e.destroyed ) e.fixedUpdate();
	}

	/** Main loop **/
	override function update() {
		super.update();

		// Entities main loop
		for(e in Entity.ALL) if( !e.destroyed ) e.frameUpdate();


		// Global key shortcuts
		if( !App.ME.anyInputHasFocus() && !ui.Window.hasAnyModal() && !Console.ME.isActive() ) {
			// Attach debug drone (CTRL-SHIFT-D)
			#if debug
			if( ca.isPressed(A_ToggleDebugDrone) )
				new DebugDrone(); // <-- HERE: provide an Entity as argument to attach Drone near it
			#end

			// Restart whole game
			if( ca.isPressed(A_Restart) )
				App.ME.startGame();

		}
	}
}

