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
  await RustLib.init();

  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  windowManager.setAlwaysOnTop(true);
  
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
        title: 'Test App',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        ),
        home: MainPage(),
      ),
    );
  }
}

class MyAppState extends ChangeNotifier {
  var isCapturing = false;
  var capturingLabel = "Idle";
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
      capturingLabel = "Measuring";
      _startTimer();
    } else {
      capturingLabel = "Idle";
      _stopTimer();
    }
    notifyListeners();
  }

  void _captureDamage() async {
    var start = DateTime.now();
    damageReading = (await readDamage(x: 576, y: 0, width: 1344, height: 65));
    print(start.difference(DateTime.now()));

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
        // print(damageHistory);
        // print(accumulatedDamage);
        // print(elapsedTime);
        // print(damageReading);
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
    var capturingLabel = appState.capturingLabel;
    var overallDps = appState.overallDps;
    var windowDps = appState.windowDps;

    return MaterialApp(
      theme: ThemeData(fontFamily: 'Fontin'),
      home: Scaffold(
        body: Center(
          child: Column(
            children: [
              Text("Overall DPS: ${dpsDisplay(overallDps)}"),
              Text("Recent DPS: ${dpsDisplay(windowDps)}"),
              ElevatedButton(onPressed: appState.toggleCapturing, child: Text(capturingLabel)), // TODO: replace with other syntax
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
