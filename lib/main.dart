import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:math';
import 'dart:io';

import 'package:window_manager/window_manager.dart';

import 'package:dps_meter/src/rust/api/screenshot.dart';
import 'package:dps_meter/src/rust/frb_generated.dart';

double logBase(num x, num base) => log(x) / log(base);

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
  return (dps / pow(1000, magnitude)).toStringAsFixed(decimalPlaces) + letter;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  await windowManager.ensureInitialized();

  windowManager.setAlwaysOnTop(true);
  windowManager.setOpacity(0.6);

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
  var overallDps = 0.0;

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

  void _calculateOverallDps() {
    overallDps = 1000 * max(0, damageHistory[damageHistory.length - 1]) / elapsedTime; // Converting to damage per second
  }

  void _calculateWindowDps() {
    windowDps = 1000 * max(0, damageHistory[damageHistory.length - 1] -
                        damageHistory[max(0, damageHistory.length - windowIndexSize - 1)]) / timeWindow;
  }

  void _startTimer() {
    timer = Timer.periodic(Duration(milliseconds: dt), (timer) {
      if (isCapturing) { // Check the flag inside the timer callback
        _captureDamage();
      } else {
        _stopTimer(); // Stop if the flag is set to false
      }
    });
  }

  void _stopTimer() {
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
}

class MainPage extends StatelessWidget {
  const MainPage({super.key});

  @override
  Widget build(BuildContext context) {   
    var appState = context.watch<MyAppState>();
    var overallDps = appState.overallDps;
    var windowDps = appState.windowDps;

    IconData icon;
    if (appState.isCapturing) {
      icon = Icons.pause;
    } else {
      icon = Icons.play_arrow;
    }

    return MaterialApp(
      theme: ThemeData(fontFamily: 'Fontin'),
      home: Scaffold(
        backgroundColor: Color.fromRGBO(0, 0, 0, 0.0),
        body: Center(
          child: Row(
            children: [
              IconButton(icon: Icon(icon), onPressed: appState.toggleCapturing),
              DragToMoveArea(
                child: Column(
                  children: [
                    Text("Overall DPS: ${dpsDisplay(overallDps)}", style: TextStyle(color: Colors.white)),
                    SizedBox(height: 2),
                    Text("Recent DPS: ${dpsDisplay(windowDps)}", style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              CloseButton(onPressed: () {
                exit(0);
              }),
            ],
          ),
        ),
      ),
    );
  }
}
