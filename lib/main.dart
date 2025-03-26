import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:developer' as developer;
import 'dart:async';
import 'dart:math' as math;
import 'dart:io';

import 'package:window_manager/window_manager.dart';
import 'package:flutter_logs/flutter_logs.dart';

import 'package:dps_meter/src/rust/api/screenshot.dart';
import 'package:dps_meter/src/rust/frb_generated.dart';


Future setupLogger() async {
    setupLogStream().listen((msg){
        developer.log("(Rust) ${msg.logLevel} ${msg.lbl.padRight(8)}: ${msg.msg}");
    });
}

double logBase(num x, num base) => math.log(x) / math.log(base);

String dpsDisplay(double dps) {
  if(dps <= 0) {
    return "0";
  }
  var magnitude = logBase(dps, 1000).floor();
  var letter = "";
  var decimalPlaces = (2 - logBase(dps, 10).floor()) % 3;
  switch (magnitude) {
    case < 1:
      letter = "";
      decimalPlaces = 0;
    case 1:
      letter = "k"; // thousands
    case 2:
      letter = "m"; // millions
    case 3:
      letter = "b"; // billions
    case 4:
      letter = "t"; // trillions
    case > 4:
      letter = "e$magnitude"; // Use scientific beyond trillions
  }
  return (dps / math.pow(1000, magnitude)).toStringAsFixed(decimalPlaces) + letter;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  await setupLogger();
  await windowManager.ensureInitialized();

  windowManager.setAlwaysOnTop(true);
  windowManager.setOpacity(1.0);

  await windowManager.center();
  var currentPosition = await windowManager.getPosition();
  windowManager.setPosition(Offset(currentPosition.dx, 0));
  windowManager.setSize(Size(200, 50));
  
  runApp(const MyApp());
  windowManager.waitUntilReadyToShow().then((_) async{
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => MyAppState(),
      child: MaterialApp(
        title: 'DPS Meter',
        theme: ThemeData(
          useMaterial3: true,
          textTheme: TextTheme(
            bodySmall: TextStyle(
              fontFamily: 'Fontin',
              color: Colors.white
            )
          )
        ),
        home: MainPage(),
      ),
    );
  }
}

class MyAppState extends ChangeNotifier {
  var isCapturing = false;
  Timer? timer;

  var damageReading = 0;
  var accumulatedDamage = 0;
  var damageHistory = <int>[];

  var dt = 1000; // ms
  var timeWindow = 4000; // ms
  var windowIndexSize = 4000 ~/ 1000;
  var elapsedTime = 0;

  var windowDps = 0.0;
  var overallDps = 0.0; // TODO: Add a stopwatch-like time thing in the label (for measuring TTK a boss?)

  var isExpanded = false;

  void toggleCapturing() async {
    isCapturing = !isCapturing;
    if (isCapturing) {
      _startTimer();
    } else {
      _stopTimer();
    }
    notifyListeners();
  }

  void _captureDamage() async {
    damageReading = (await readDamage(x: 576, y: 0, width: 1344, height: 65)); // TODO: Remove hard-coded values

    if (damageReading == 0) {
      if (damageHistory.isEmpty) {
        return;
      } else if (accumulatedDamage < damageHistory[damageHistory.length - 1]) {
        accumulatedDamage = damageHistory[damageHistory.length - 1];
      }
    }
    elapsedTime += dt;
    damageHistory.add(accumulatedDamage + damageReading);

    if ((damageHistory.length <= 1) || (damageReading == 0)) {
      return;
    }
    _calculateOverallDps();
    _calculateWindowDps();
    notifyListeners();
  }

  void _calculateOverallDps() { // TODO: Move to a utils file
    overallDps = 1000 * math.max(0, damageHistory[damageHistory.length - 1]) / elapsedTime; // Converting to damage per second
  }

  void _calculateWindowDps() {
    windowDps = 1000 * math.max(0, damageHistory[damageHistory.length - 1] -
                        damageHistory[math.max(0, damageHistory.length - windowIndexSize - 1)]) / timeWindow;
  }

  void _startTimer() {
    developer.log("Starting capture loop");
    timer = Timer.periodic(Duration(milliseconds: dt), (timer) {
      if (isCapturing) { // Check the flag inside the timer callback
        _captureDamage();
      } else {
        _stopTimer(); // Stop if the flag is set to false
      }
    });
  }

  void _stopTimer() {
    developer.log("Stopping capture loop");
    damageHistory = [];
    accumulatedDamage = 0;
    elapsedTime = 0;
    timer?.cancel();
    timer = null;
  }

  @override
  void dispose() {
    _stopTimer(); // Important: Cancel the timer when the widget is disposed
    super.dispose();
  }

  void toggleExpanded() {
    isExpanded = !isExpanded;
    if (isExpanded) {
      windowManager.setSize(Size(600, 500)); // TODO: Add these values somewhere as constants
    } else {
      windowManager.setSize(Size(200, 50));
    }
    notifyListeners();
  }
}

class MainPage extends StatelessWidget {
  const MainPage({super.key});

  @override
  Widget build(BuildContext context) {   
    var appState = context.watch<MyAppState>();
    var overallDps = appState.overallDps;
    var windowDps = appState.windowDps;

    IconData capturingIcon;
    if (appState.isCapturing) {
      capturingIcon = Icons.pause;
    } else {
      capturingIcon = Icons.play_arrow;
    }

    final theme = Theme.of(context);
    final fontStyle = theme.textTheme.bodySmall;

    return MaterialApp(
      theme: theme,
      home: Scaffold(
        backgroundColor: Color.fromRGBO(0, 0, 0, 1.0),
        body: Center(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(icon: Icon(Icons.menu), onPressed: appState.toggleExpanded),
                  IconButton(icon: Icon(capturingIcon), onPressed: appState.toggleCapturing),
                  DragToMoveArea(
                    child: Column(
                      children: [
                        Text("Overall DPS: ${dpsDisplay(overallDps)}", style: fontStyle),
                        SizedBox(height: 2),
                        Text("Recent DPS: ${dpsDisplay(windowDps)}", style: fontStyle),
                      ],
                    ),
                  ),
                  IconButton(icon: Icon(Icons.close), onPressed: () {
                    exit(0);
                  }),
                ],
              ),
              Visibility(
                visible: appState.isExpanded,
                child: _tabSection(context),
              )
            ],
          ),
        ),
      ),
    );
  }
}

Widget _tabSection(BuildContext context) {
  return DefaultTabController(
    length: 3,
    child: Column(
      mainAxisSize: MainAxisSize.min,

      children: <Widget>[
        TabBar(
          tabs: [
            Tab(text: "History"),
            Tab(text: "Settings"),
            Tab(text: "Debug"),
          ],
          labelStyle: TextStyle(color: Colors.white), // TODO: Need to make the theme inherited from the top
          unselectedLabelStyle: TextStyle(color: Colors.grey),
        ),
        SizedBox(
          height: MediaQuery.of(context).size.height,
          child: TabBarView(
            children: [
              Text("History Body"),
              Text("Settings Body"),
              Text("Debug Body", style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ],
    ),
  );
}
