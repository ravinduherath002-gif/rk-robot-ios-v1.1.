import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'wifi_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const App());
}

enum Profile { eco, normal, sport }
enum Motion { stop, forward, back, left, right }

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
    home: const Dash(),
  );
}

class Dash extends StatefulWidget {
  const Dash({super.key});
  @override
  State<Dash> createState() => _DashState();
}

class _DashState extends State<Dash> with TickerProviderStateMixin {
  static const ip = '192.168.4.1';
  static const port = 8080;
  static const blue = Color(0xFF39DFFF);
  static const green = Color(0xFF60F0A2);
  static const orange = Color(0xFFFFA13D);
  static const red = Color(0xFFFF4B45);
  static const yellow = Color(0xFFFFE04A);
  static const panel = Color(0xE006111D);

  final wifi = WifiService();
  StreamSubscription<bool>? sub;
  Timer? moveTimer;
  late final AnimationController blink;
  late final AnimationController pulse;
  late final AnimationController themeTransition;

  Color _themeFrom = green;
  Color _themeTo = green;

  bool connected = false, connecting = false;
  bool front = false, rear = false, flash = false, turbo = false;
  bool horn = false, siren = false, auto = false, dance = false;
  bool doubleSignal = false;
  double speed = 179, steer = 0, throttle = 0;
  Profile profile = Profile.normal;
  Motion motion = Motion.stop;
  String last = 'S';

  @override
  void initState() {
    super.initState();
    blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    )..repeat(reverse: true);

    pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    themeTransition = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
      value: 1.0,
    );

    _themeFrom = green;
    _themeTo = green;
    sub = wifi.connectionStream.listen((v) {
      if (!mounted) return;
      setState(() {
        connected = v;
        if (!v) {
          motion = Motion.stop;
          steer = throttle = 0;
          turbo = horn = false;
          doubleSignal = false;
          _themeFrom = smoothThemeColor;
          _themeTo = base;
          themeTransition.value = 1.0;
          moveTimer?.cancel();
          moveTimer = null;
        }
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => connect(show: false));
  }

  @override
  void dispose() {
    moveTimer?.cancel();
    sub?.cancel();
    blink.dispose();
    pulse.dispose();
    themeTransition.dispose();
    wifi.dispose();
    super.dispose();
  }

  int get pct => ((speed / 255) * 100).round();

  Color get base {
    if (profile == Profile.eco) return blue;
    if (profile == Profile.normal) return green;

    // SPORT default stays orange.
    // Only near-maximum manual speed becomes red.
    return pct >= 90 ? red : orange;
  }

  Color get smoothThemeColor {
    return Color.lerp(
          _themeFrom,
          _themeTo,
          Curves.easeInOutCubic.transform(themeTransition.value),
        ) ??
        _themeTo;
  }

  void animateThemeTo(Color target) {
    if (_themeTo.value == target.value && themeTransition.isCompleted) {
      return;
    }

    final current = smoothThemeColor;

    _themeFrom = current;
    _themeTo = target;

    themeTransition
      ..stop()
      ..value = 0
      ..forward();
  }

  void syncThemeTarget() {
    animateThemeTo(base);
  }

  String get profileText => switch (profile) {
    Profile.eco => 'ECO',
    Profile.normal => 'NORMAL',
    Profile.sport => 'SPORT',
  };

  String get motionText => switch (motion) {
    Motion.stop => 'STOPPED',
    Motion.forward => 'FORWARD',
    Motion.back => 'BACKWARD',
    Motion.left => 'LEFT',
    Motion.right => 'RIGHT',
  };

  Future<void> connect({bool show = true}) async {
    if (connected || connecting) return;
    setState(() => connecting = true);
    final ok = await wifi.connect(ip, port);
    if (!mounted) return;
    setState(() {
      connected = ok;
      connecting = false;
      if (ok) last = 'LINK';
    });
    if (ok) {
      wifi.send('V${speed.round()}');
      syncThemeTarget();
      sendProfile();
    }
    if (show) msg(ok ? 'RK ROBOT connected' : 'Connect to RK_ROBOT Wi-Fi');
  }

  Future<void> disconnect() async {
    moveTimer?.cancel();
    moveTimer = null;
    if (connected) {
      for (final c in ['S', 'h', 't', 'z', 'd', 'y']) {
        wifi.send(c);
      }
    }
    await wifi.disconnect();
    if (!mounted) return;
    setState(() {
      connected = false;
      connecting = false;
      motion = Motion.stop;
      steer = throttle = 0;
      turbo = horn = false;
      doubleSignal = false;
      last = 'OFF';
    });
    msg('Robot disconnected');
  }

  Future<void> toggleLink() => connected ? disconnect() : connect();

  void msg(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s), duration: const Duration(milliseconds: 800)));
  }

  bool send(String c, {bool warn = true}) {
    if (!connected) {
      if (warn) msg('Robot not connected');
      return false;
    }
    final ok = wifi.send(c);
    if (mounted) setState(() => last = c);
    return ok;
  }

  void startMove(String c, Motion m) {
    if (!send(c)) return;
    moveTimer?.cancel();
    setState(() => motion = m);
    moveTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => send(c, warn: false),
    );
  }

  void stopMove() {
    moveTimer?.cancel();
    moveTimer = null;
    setState(() {
      motion = Motion.stop;
      throttle = 0;
    });
    send('S', warn: false);
  }

  void setSteer(double v) {
    v = v.clamp(-1.0, 1.0);
    setState(() => steer = v);
    if (v < -0.28) {
      startMove('L', Motion.left);
    } else if (v > 0.28) {
      startMove('R', Motion.right);
    } else if (motion == Motion.left || motion == Motion.right) {
      stopMove();
    }
  }

  void setThrottle(double v) {
    v = v.clamp(-1.0, 1.0);
    setState(() => throttle = v);
    if (v > 0.24) {
      startMove('F', Motion.forward);
    } else if (v < -0.24) {
      startMove('B', Motion.back);
    } else {
      stopMove();
    }
  }

  double get profilePwm => switch (profile) {
    Profile.eco => 102.0,
    Profile.normal => 179.0,
    Profile.sport => 217.0,
  };

  void applyProfile(Profile nextProfile) {
    final nextSpeed = switch (nextProfile) {
      Profile.eco => 102.0,
      Profile.normal => 179.0,
      Profile.sport => 217.0,
    };

    setState(() {
      profile = nextProfile;
      speed = nextSpeed;
    });

    syncThemeTarget();

    // Keep both the UI PWM display and the robot selected speed in sync.
    send(
      switch (nextProfile) {
        Profile.eco => 'E',
        Profile.normal => 'N',
        Profile.sport => 'P',
      },
      warn: false,
    );
    send('V${nextSpeed.round()}', warn: false);
  }

  void sendProfile() => send(
    switch (profile) {
      Profile.eco => 'E',
      Profile.normal => 'N',
      Profile.sport => 'P',
    },
    warn: false,
  );

  BoxDecoration box(Color c, [double r = 20]) => BoxDecoration(
    color: panel,
    borderRadius: BorderRadius.circular(r),
    border: Border.all(color: c.withOpacity(.72), width: 1.5),
    boxShadow: [BoxShadow(color: c.withOpacity(.1), blurRadius: 22)],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: AnimatedBuilder(
      animation: Listenable.merge([
        blink,
        themeTransition,
      ]),
      builder: (_, __) {
        final modeColor = smoothThemeColor;

        // Turbo uses a continuous red <-> yellow blend instead of hard blinking.
        final turboColor = Color.lerp(
          red,
          yellow,
          Curves.easeInOutSine.transform(blink.value),
        )!;

        final c = turbo
            ? Color.lerp(
                modeColor,
                turboColor,
                Curves.easeInOutCubic.transform(themeTransition.value),
              )!
            : modeColor;

        return Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -.4),
              radius: 1.2,
              colors: [c.withOpacity(.1), const Color(0xFF06111C), const Color(0xFF02060A)],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: 1366,
                  height: 720,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        top(c),
                        const SizedBox(height: 9),
                        Expanded(
                          child: Row(
                            children: [
                              SizedBox(width: 360, child: steering(c)),
                              const SizedBox(width: 10),
                              Expanded(child: center(c)),
                              const SizedBox(width: 10),
                              SizedBox(width: 350, child: throttlePanel(c)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 9),
                        SizedBox(height: 83, child: bottom(c)),
                        const SizedBox(height: 7),
                        footer(c),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );

  Widget top(Color c) {
    final lc = connected ? green : connecting ? orange : const Color(0xFFFF5A73);
    return SizedBox(
      height: 83,
      child: Row(
        children: [
          InkWell(
            onTap: toggleLink,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 330,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: box(lc),
              child: Row(
                children: [
                  Icon(connected ? Icons.wifi : Icons.wifi_off, color: lc, size: 32),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        connected ? 'TAP TO DISCONNECT' : connecting ? 'CONNECTING...' : 'TAP TO CONNECT',
                        style: TextStyle(color: lc, fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      const Text(ip, style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              decoration: box(c),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('RK ROBOT', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 2)),
                  Text('V9.2.6 SMOOTH DYNAMIC CONTROL  •  $profileText',
                    style: TextStyle(color: c, fontWeight: FontWeight.w800, letterSpacing: 1)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 300,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: box(c),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('BATTERY • SIM', style: TextStyle(color: Colors.white54, fontSize: 10)),
                      SizedBox(height: 4),
                      Text('N/A', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.battery_unknown, color: c, size: 30),
                const SizedBox(width: 14),
                Icon(Icons.settings, color: c, size: 29),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget steering(Color c) => Container(
    padding: const EdgeInsets.fromLTRB(16, 15, 16, 12),
    decoration: box(c),
    child: Column(
      children: [
        Text('STEERING', style: TextStyle(color: c, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1)),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (_, q) {
              final w = q.maxWidth;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (e) => setSteer((e.localPosition.dx - w / 2) / (w * .38)),
                onPanUpdate: (e) => setSteer((e.localPosition.dx - w / 2) / (w * .38)),
                onPanEnd: (_) {
                  setState(() => steer = 0);
                  if (motion == Motion.left || motion == Motion.right) stopMove();
                },
                onPanCancel: () {
                  setState(() => steer = 0);
                  if (motion == Motion.left || motion == Motion.right) stopMove();
                },
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(size: Size.infinite, painter: SteeringPainter(c)),
                    Positioned(left: 24, child: Column(children: [
                      Icon(Icons.chevron_left, color: c, size: 45),
                      const Text('LEFT', style: TextStyle(color: Colors.white60, fontSize: 10)),
                    ])),
                    Positioned(right: 24, child: Column(children: [
                      Icon(Icons.chevron_right, color: c, size: 45),
                      const Text('RIGHT', style: TextStyle(color: Colors.white60, fontSize: 10)),
                    ])),
                    Transform.translate(
                      offset: Offset(steer * w * .27, 8),
                      child: Container(
                        width: 126,
                        height: 126,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(colors: [c.withOpacity(.8), const Color(0xFF07111B)]),
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [BoxShadow(color: c.withOpacity(.45), blurRadius: 28, spreadRadius: 4)],
                        ),
                        child: const Icon(Icons.sports_esports, color: Colors.black, size: 48),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const Text('DRAG LEFT / RIGHT  •  RELEASE = CENTER',
          style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w700)),
      ],
    ),
  );

  Widget center(Color c) => Container(
    padding: const EdgeInsets.all(13),
    decoration: box(c),
    child: Column(
      children: [
        SizedBox(
          height: 170,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                top: 0,
                child: Row(
                  children: [
                    Icon(Icons.circle, color: connected ? green : const Color(0xFFFF5A73), size: 12),
                    const SizedBox(width: 8),
                    Text(connected ? 'SYSTEM ONLINE' : 'SYSTEM OFFLINE',
                      style: TextStyle(
                        color: connected ? green : const Color(0xFFFF5A73),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      )),
                  ],
                ),
              ),
              Positioned.fill(
                top: 22,
                child: AnimatedBuilder(
                  animation: pulse,
                  builder: (_, __) => Transform.scale(
                    scale: .96 + pulse.value * .04,
                    child: CustomPaint(
                      painter: CarPainter(
                        c: c,
                        motion: motion,
                        steer: steer,
                        front: front || flash,
                        rear: rear || motion == Motion.back,
                        turbo: turbo,
                        horn: horn,
                        siren: siren,
                        connected: connected,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 5),
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            decoration: box(c, 18),
            child: Column(
              children: [
                const Text('MOTOR POWER',
                  style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.3)),
                Text('$pct%', style: TextStyle(color: c, fontSize: 31, fontWeight: FontWeight.w900)),
                Row(
                  children: [
                    tag('PWM ${speed.round()}', c, 108),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: c,
                          inactiveTrackColor: Colors.white12,
                          thumbColor: Colors.white,
                          trackHeight: 5,
                        ),
                        child: Slider(
                          min: 0, max: 255, divisions: 255, value: speed,
                          onChanged: (v) {
                            final oldTarget = base;
                            setState(() => speed = v);
                            final newTarget = base;

                            if (oldTarget.value != newTarget.value) {
                              animateThemeTo(newTarget);
                            }

                            send('V${v.round()}', warn: false);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    tag('MODE $profileText', c, 125),
                  ],
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    profileBtn(Profile.eco, 'ECO', blue),
                    const SizedBox(width: 10),
                    profileBtn(Profile.normal, 'NORMAL', green),
                    const SizedBox(width: 10),
                    profileBtn(Profile.sport, 'SPORT', orange),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget tag(String s, Color c, double w) => Container(
    width: w, height: 36,
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: c.withOpacity(.7))),
    alignment: Alignment.center,
    child: Text(s, style: TextStyle(color: c, fontWeight: FontWeight.w900, fontSize: 11)),
  );

  Widget profileBtn(Profile p, String s, Color c) {
    final on = profile == p;
    return InkWell(
      onTap: () => applyProfile(p),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: on ? c.withOpacity(.24) : Colors.transparent,
          border: Border.all(
            color: on ? c : Colors.white24,
            width: on ? 2.0 : 1,
          ),
          boxShadow: on
              ? [
                  BoxShadow(
                    color: c.withOpacity(.34),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Text(
          s,
          style: TextStyle(
            color: on ? Colors.white : Colors.white54,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget throttlePanel(Color c) => Container(
    padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
    decoration: box(c),
    child: Column(
      children: [
        Text('THROTTLE', style: TextStyle(color: c, fontSize: 16, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (_, q) {
              final h = q.maxHeight;
              final y = ((1 - ((throttle + 1) / 2)) * (h - 105)) + 18;
              void update(double dy) => setThrottle((h / 2 - dy) / (h * .38));
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (e) => update(e.localPosition.dy),
                onPanUpdate: (e) => update(e.localPosition.dy),
                onPanEnd: (_) => stopMove(),
                onPanCancel: stopMove,
                child: Stack(
                  children: [
                    Positioned(
                      top: 18, bottom: 18, left: 48, width: 98,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(44),
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter, end: Alignment.bottomCenter,
                            colors: [green, Color(0xFF167044), Color(0xFF17242B), Color(0xFF7B1C2F), Color(0xFFFF3C52)],
                          ),
                          border: Border.all(color: c.withOpacity(.85), width: 2),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 30, top: y,
                      child: Container(
                        width: 135, height: 73,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(23),
                          gradient: const LinearGradient(colors: [Color(0xFF8EECFF), Color(0xFF2EA9D5)]),
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: const Icon(Icons.drag_handle, color: Color(0xFF06253A), size: 36),
                      ),
                    ),
                    const Positioned(top: 62, right: 14,
                      child: Text('FORWARD', style: TextStyle(color: green, fontWeight: FontWeight.w900))),
                    const Positioned(right: 22, top: 205,
                      child: Text('RELEASE', style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w900))),
                    const Positioned(bottom: 58, right: 8,
                      child: Text('BACKWARD', style: TextStyle(color: Color(0xFFFF5A73), fontWeight: FontWeight.w900))),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    ),
  );

  Widget bottom(Color c) => Row(
    children: [
      tile('FRONT LIGHT', Icons.lightbulb_outline, blue, front, () {
        setState(() => front = !front);
        send(front ? 'I' : 'i', warn: false);
      }),
      gap(),
      tile('BACK LIGHT', Icons.highlight, const Color(0xFFFF5A73), rear, () {
        setState(() => rear = !rear);
        send(rear ? 'K' : 'k', warn: false);
      }),
      gap(),
      tile('HEAD FLASH', Icons.flash_on, orange, flash, () {
        setState(() => flash = !flash);
        send(flash ? 'J' : 'j', warn: false);
      }),
      gap(),
      Expanded(
        flex: 2,
        child: Listener(
          onPointerDown: (_) {
            setState(() => turbo = true);
            // Enter turbo smoothly from the current mode color.
            _themeFrom = smoothThemeColor;
            _themeTo = red;
            themeTransition
              ..stop()
              ..value = 0
              ..forward();
            send('T', warn: false);
          },
          onPointerUp: (_) {
            setState(() => turbo = false);
            // Return smoothly to the selected mode color.
            animateThemeTo(base);
            send('t', warn: false);
          },
          onPointerCancel: (_) {
            setState(() => turbo = false);
            animateThemeTo(base);
            send('t', warn: false);
          },
          child: turboTileBody(
            turbo ? yellow : orange,
            turbo,
          ),
        ),
      ),
      gap(),
      Expanded(
        child: Listener(
          onPointerDown: (_) {
            setState(() => horn = true);
            send('H', warn: false);
          },
          onPointerUp: (_) {
            setState(() => horn = false);
            send('h', warn: false);
          },
          onPointerCancel: (_) {
            setState(() => horn = false);
            send('h', warn: false);
          },
          child: tileBody('HORN\nHOLD', Icons.campaign, yellow, horn),
        ),
      ),
      gap(),
      tile(
        'DOUBLE SIGNAL',
        Icons.warning_amber_rounded,
        yellow,
        doubleSignal,
        () {
          setState(() => doubleSignal = !doubleSignal);
          send(doubleSignal ? 'Y' : 'y', warn: false);
        },
      ),
      gap(),
      tile('SIREN', Icons.emergency, const Color(0xFFE04DFF), siren, () {
        setState(() => siren = !siren);
        send(siren ? 'Z' : 'z', warn: false);
      }),
      gap(),
      tile('AUTO MODE', Icons.smart_toy_outlined, blue, auto, () {
        setState(() => auto = !auto);
        send(auto ? 'A' : 'a', warn: false);
      }),
      gap(),
      tile('DANCE', Icons.music_note, const Color(0xFFFF54D7), dance, () {
        setState(() => dance = !dance);
        send(dance ? 'D' : 'd', warn: false);
      }),
    ],
  );

  Widget gap() => const SizedBox(width: 7);

  Widget tile(String s, IconData i, Color c, bool on, VoidCallback f) => Expanded(
    child: InkWell(
      onTap: f,
      borderRadius: BorderRadius.circular(17),
      child: tileBody(s, i, c, on),
    ),
  );

  Widget turboTileBody(Color c, bool on) => AnimatedContainer(
    duration: const Duration(milliseconds: 170),
    curve: Curves.easeOutCubic,
    decoration: BoxDecoration(
      color: on ? c.withOpacity(.25) : panel,
      borderRadius: BorderRadius.circular(19),
      border: Border.all(
        color: on ? c : c.withOpacity(.58),
        width: on ? 2.6 : 1.5,
      ),
      boxShadow: on
          ? [
              BoxShadow(
                color: c.withOpacity(.58),
                blurRadius: 24,
                spreadRadius: 3,
              ),
              BoxShadow(
                color: c.withOpacity(.20),
                blurRadius: 38,
                spreadRadius: 5,
              ),
            ]
          : [
              BoxShadow(
                color: c.withOpacity(.10),
                blurRadius: 14,
              ),
            ],
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedScale(
          duration: const Duration(milliseconds: 140),
          scale: on ? 1.16 : 1.0,
          child: Icon(
            Icons.bolt_rounded,
            color: on ? Colors.white : c,
            size: 38,
          ),
        ),
        const SizedBox(width: 10),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TURBO',
              style: TextStyle(
                color: on ? Colors.white : Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: .9,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              on ? 'ACTIVE' : 'HOLD',
              style: TextStyle(
                color: c,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: .8,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget tileBody(String s, IconData i, Color c, bool on) => AnimatedContainer(
    duration: const Duration(milliseconds: 170),
    curve: Curves.easeOutCubic,
    decoration: BoxDecoration(
      color: on ? c.withOpacity(.22) : panel,
      borderRadius: BorderRadius.circular(17),
      border: Border.all(
        color: on ? c : c.withOpacity(.48),
        width: on ? 2.3 : 1.2,
      ),
      boxShadow: on
          ? [
              BoxShadow(
                color: c.withOpacity(.48),
                blurRadius: 20,
                spreadRadius: 2,
              ),
              BoxShadow(
                color: c.withOpacity(.18),
                blurRadius: 34,
                spreadRadius: 4,
              ),
            ]
          : [
              BoxShadow(
                color: c.withOpacity(.07),
                blurRadius: 12,
              ),
            ],
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedScale(
          duration: const Duration(milliseconds: 140),
          scale: on ? 1.13 : 1.0,
          child: Icon(
            i,
            color: on ? Colors.white : c,
            size: 27,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          s,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: on ? Colors.white : Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: on ? 1.0 : 0.0,
          child: Text(
            'ACTIVE',
            style: TextStyle(
              color: c,
              fontSize: 7,
              fontWeight: FontWeight.w900,
              letterSpacing: .8,
            ),
          ),
        ),
      ],
    ),
  );

  Widget footer(Color c) => Container(
    height: 44,
    padding: const EdgeInsets.symmetric(horizontal: 18),
    decoration: box(c, 17),
    child: Row(
      children: [
        Icon(Icons.home, color: c, size: 25),
        const SizedBox(width: 16),
        Text(connected ? 'SYSTEM ONLINE' : 'SYSTEM OFFLINE',
          style: TextStyle(
            color: connected ? green : const Color(0xFFFF5A73),
            fontWeight: FontWeight.w900,
          )),
        const Spacer(),
        Text('ROBOT  •  ${connected ? 'LINK ACTIVE' : 'LINK OFF'}  •  $motionText',
          style: TextStyle(color: c, fontWeight: FontWeight.w900)),
        const Spacer(),
        Text('CMD $last  •  PWM ${speed.round()}',
          style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w800)),
      ],
    ),
  );
}

class SteeringPainter extends CustomPainter {
  final Color c;
  SteeringPainter(this.c);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..color = c.withOpacity(.34);
    final center = Offset(size.width / 2, size.height * .53);
    final r = math.min(size.width, size.height) * .37;
    canvas.drawArc(Rect.fromCircle(center: center, radius: r), math.pi * 1.12, math.pi * .76, false, p);
  }
  @override
  bool shouldRepaint(covariant SteeringPainter old) => old.c != c;
}

class CarPainter extends CustomPainter {
  final Color c;
  final Motion motion;
  final double steer;
  final bool front, rear, turbo, horn, siren, connected;
  CarPainter({
    required this.c, required this.motion, required this.steer,
    required this.front, required this.rear, required this.turbo,
    required this.horn, required this.siren, required this.connected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .58);
    double dx = 0, dy = 0, a = steer * .035;
    if (motion == Motion.forward) dy = -4;
    if (motion == Motion.back) dy = 4;
    if (motion == Motion.left) { dx = -5; a -= .06; }
    if (motion == Motion.right) { dx = 5; a += .06; }

    canvas.save();
    canvas.translate(center.dx + dx, center.dy + dy);
    canvas.rotate(a);

    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, 33), width: 195, height: 36),
      Paint()..color = Colors.black54,
    );

    final body = Path()
      ..moveTo(-74, -30)..lineTo(54, -42)..lineTo(84, 28)..lineTo(-58, 40)..close();
    final bp = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xFF254762), Color(0xFF0A1520), Color(0xFF020509)],
      ).createShader(const Rect.fromLTWH(-90, -55, 190, 110));
    canvas.drawPath(body, bp);
    canvas.drawPath(body, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = c.withOpacity(.8));

    final roof = Path()
      ..moveTo(-38, -48)..lineTo(30, -55)..lineTo(50, -14)..lineTo(-48, -7)..close();
    canvas.drawPath(roof, Paint()..color = c.withOpacity(.25));

    void wheel(Offset o, double rot) {
      canvas.save();
      canvas.translate(o.dx, o.dy);
      canvas.rotate(rot);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: 32, height: 64),
          const Radius.circular(12),
        ),
        Paint()..color = const Color(0xFF030406),
      );
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 18, height: 42),
        Paint()..style = PaintingStyle.stroke..strokeWidth = 4..color = c.withOpacity(.45),
      );
      canvas.restore();
    }

    wheel(const Offset(-70, 24), 0);
    wheel(const Offset(70, 15), 0);
    wheel(const Offset(-55, -27), steer * .22);
    wheel(const Offset(54, -36), steer * .22);

    final rk = TextPainter(
      text: const TextSpan(text: 'RK', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
      textDirection: TextDirection.ltr,
    )..layout();
    rk.paint(canvas, const Offset(-12, 6));

    if (front) {
      final g = Paint()
        ..color = const Color(0xFF7DEAFF).withOpacity(.72)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
      canvas.drawCircle(const Offset(-44, 26), 13, g);
      canvas.drawCircle(const Offset(45, 19), 13, g);
    }

    if (rear) {
      final g = Paint()
        ..color = const Color(0xFFFF304A).withOpacity(.7)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawCircle(const Offset(-60, -17), 9, g);
      canvas.drawCircle(const Offset(54, -29), 9, g);
    }

    if (turbo) {
      canvas.drawOval(
        const Rect.fromLTWH(-95, -70, 205, 132),
        Paint()
          ..color = const Color(0xFFFFD23F).withOpacity(.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
      );
    }

    if (horn) {
      final p = Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = const Color(0xFFFFD93D);
      canvas.drawArc(const Rect.fromLTWH(74, -25, 35, 35), -.8, 1.6, false, p);
      canvas.drawArc(const Rect.fromLTWH(80, -32, 48, 48), -.8, 1.6, false, p);
    }

    if (siren) {
      canvas.drawCircle(
        const Offset(4, -62),
        10,
        Paint()
          ..color = const Color(0xFFE04DFF).withOpacity(.8)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      );
    }

    if (!connected) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(-98, -75, 210, 148), const Radius.circular(20)),
        Paint()..color = Colors.black45,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CarPainter old) =>
      old.c != c || old.motion != motion || old.steer != steer ||
      old.front != front || old.rear != rear || old.turbo != turbo ||
      old.horn != horn || old.siren != siren || old.connected != connected;
}
