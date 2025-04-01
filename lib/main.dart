import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:io';

import 'package:window_manager/window_manager.dart';
import 'package:logging_flutter/logging_flutter.dart';

import 'package:dps_meter/src/rust/api/screenshot.dart';
import 'package:dps_meter/src/rust/frb_generated.dart';


const collapsedSize = Size(230, 50);
const expandedSize = Size(600, 500);

Future setupLogger() async {
    setupLogStream().listen((msg){
      if (msg.logLevel.toString() == "Level.info") {
        Flogger.i(msg.msg);
      } else {
        Flogger.w(msg.msg);
      }
    });
}

double logBase(num x, num base) => math.log(x) / math.log(base);

String displayComparison(double referenceDps, double comparisonDps) {
  var multiplier = (comparisonDps / referenceDps - 1) * 100;
  var indicatingWord = "More";
  var indicatingArrow = "⯅";
  if (multiplier < 0) {
    indicatingWord = "Less";
    indicatingArrow = "⯆";
  }
  if (multiplier.abs() < 1) {
    return "<1% $indicatingWord";
  }
  return "$indicatingArrow${multiplier.abs().toStringAsFixed(2)}% $indicatingWord";
}

String displayDps(double dps) {
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

class MeasurementLabels {
  MeasurementLabels({
    required this.name,
    required this.totalTime,
    required this.totalDamage,
    required this.overallDps,
  });

  final String name;
  final String totalTime;
  final String totalDamage;
  final double overallDps;
  var comparisonMultiplier = "-";
  final DateTime dateTime = DateTime.now();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  await windowManager.ensureInitialized();

  Flogger.init(
    config: FloggerConfig(
      showDateTime: true,
      printClassName: false,
      printMethodName: false,
    )
  );
  Flogger.registerListener(
    (record) => LogConsole.add(
      OutputEvent(record.level, [record.printable()]),
      bufferSize: 100, // Remember the last X logs
    ),
  );

  windowManager.setAlwaysOnTop(true);
  windowManager.setOpacity(1.0);

  await windowManager.center();
  var currentPosition = await windowManager.getPosition();
  windowManager.setPosition(Offset(currentPosition.dx, 0));
  windowManager.setSize(collapsedSize);
  await setupLogger(); // TODO: Do I need to kill this when app is disposed?
  
  runApp(const MyApp());
  windowManager.waitUntilReadyToShow().then((_) async{
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
  });
  Flogger.i("App initalized");
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
          brightness: Brightness.dark,
          scaffoldBackgroundColor: Color.fromRGBO(0, 0, 0, 1.0),
          textTheme: TextTheme(
            labelLarge: TextStyle(
              fontFamily: 'Fontin',
              color: Colors.white
            ),
            bodyMedium: TextStyle(
              fontFamily: 'Fontin',
              color: Colors.grey
            ),
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
  var overallDps = 0.0;

  var isExpanded = false;

  var totalMeasurements = 0;
  var measurementHistory = <MeasurementLabels>[];
  List<bool> isRadioSelectedList = [];

  void setRadioSelected(int index, bool newValue) {
    // Deselect all others in the list
    for (int i = 0; i < isRadioSelectedList.length; i++) {
      if (i != index) {
        isRadioSelectedList[i] = false;
        measurementHistory[i].comparisonMultiplier = displayComparison(measurementHistory[index].overallDps, measurementHistory[i].overallDps);
      } else {
        measurementHistory[i].comparisonMultiplier = "-";
      }
    }
    isRadioSelectedList[index] = newValue;
    notifyListeners();
  }

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
    damageReading = (await readDamage(x: 0, y: 0, width: 0, height: 0)); // TODO: May need to pass dimensions from settings?

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
    Flogger.i("Starting capture loop");
    timer = Timer.periodic(Duration(milliseconds: dt), (timer) {
      if (isCapturing) { // Check the flag inside the timer callback
        _captureDamage();
      } else {
        _stopTimer(); // Stop if the flag is set to false
      }
    });
  }

  void _stopTimer() {
    Flogger.i("Stopping capture loop");
    if (overallDps > 0) {
      Flogger.i("Saving measurement as Trial ${measurementHistory.length + 1} with overall DPS = ${displayDps(overallDps)}");
      var newMeasurement = MeasurementLabels(
        name: "Trial ${measurementHistory.length + 1}",
        totalTime: "${elapsedTime}s",
        totalDamage: "accumulatedDamage",
        overallDps: overallDps,
      );
      measurementHistory.insert(0, newMeasurement);
      isRadioSelectedList.insert(0, false);
    }
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
      windowManager.setSize(expandedSize);
    } else {
      windowManager.setSize(collapsedSize);
    }
    notifyListeners();
  }
}

class MainPage extends StatelessWidget {
  const MainPage({super.key});

  @override
  Widget build(BuildContext context) {   
    var appState = context.watch<MyAppState>();

    final theme = Theme.of(context);
    final scaffoldColor = theme.scaffoldBackgroundColor;

    return MaterialApp(
      theme: theme,
      home: Scaffold(
        backgroundColor: scaffoldColor,
        body: Center(
          child: Column(
            children: [
              _collapsedSection(context),
              Visibility(
                visible: appState.isExpanded,
                child: _expandedSection(context),
              )
            ],
          ),
        ),
      ),
    );
  }
}

Widget _collapsedSection(BuildContext context) {
  var appState = context.watch<MyAppState>();
  var overallDps = appState.overallDps;
  var windowDps = appState.windowDps;

  final theme = Theme.of(context);
  final fontStyle = theme.textTheme.labelLarge;

  IconData capturingIcon;
    if (appState.isCapturing) {
      capturingIcon = Icons.pause;
    } else {
      capturingIcon = Icons.play_arrow;
    }

  return DragToMoveArea(
    child: Row(
      children: [
        IconButton(icon: Icon(Icons.menu), onPressed: appState.toggleExpanded),
        IconButton(icon: Icon(capturingIcon), onPressed: appState.toggleCapturing),
        Column(
          children: [
            Text("Overall DPS: ${displayDps(overallDps)}", style: fontStyle),
            SizedBox(height: 2),
            Text("Recent DPS: ${displayDps(windowDps)}", style: fontStyle),
          ],
        ),
        IconButton(icon: Icon(Icons.close), onPressed: () {
          exit(0);
        }),
      ],
    ),
  );
}

Widget _expandedSection(BuildContext context) {
  final theme = Theme.of(context);
  final selectedFontStyle = theme.textTheme.labelLarge;
  final unselectedFontStyle = theme.textTheme.bodySmall;

  return DefaultTabController(
    length: 2, // TODO: Set to 3 when adding Settings tab
    child: Column(
      mainAxisSize: MainAxisSize.min,

      children: <Widget>[
        TabBar(
          tabs: [
            Tab(text: "History"),
            // Tab(text: "Settings"),
            Tab(text: "Debug"),
          ],
          labelStyle: selectedFontStyle,
          unselectedLabelStyle: unselectedFontStyle,
        ),
        SizedBox(
          height: 402.8, // TODO: Un-hard-code this value
          child: TabBarView(
            children: [
              _historyTab(context),
              // Text("Settings Body"),
              _debugTab(context),
            ],
          ),
        ),
      ],
    ),
  );
}

class HistoryRadio extends StatelessWidget {
  const HistoryRadio({
    super.key,
    required this.labels,
    required this.padding,
    required this.groupValue,
    required this.value,
    required this.onChanged,
  });

  final MeasurementLabels labels;
  final EdgeInsets padding;
  final bool groupValue;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final bodyMore = TextStyle(
      fontFamily: 'Fontin',
      color: Colors.lightGreenAccent
    );
    final bodyLess = TextStyle(
      fontFamily: 'Fontin',
      color: Colors.red
    );
    final bodyNeutral = TextStyle(
      fontFamily: 'Fontin',
      color: Colors.white
    );
    var comparisonText = labels.comparisonMultiplier;

    return InkWell(
      onTap: () {
        if (value != groupValue) {
          onChanged(value);
        }
      },
      child: Padding(
        padding: padding,
        child: Row(
          children: <Widget>[
            Radio<bool>(
              groupValue: groupValue,
              value: value,
              onChanged: (bool? newValue) {
                onChanged(newValue!);
              },
            ),
            Expanded(flex: 2, child: Text(labels.name)),
            Expanded(child: Text(
              displayDps(labels.overallDps),
              textAlign: TextAlign.center
            )),
            Expanded(child: Text(
              labels.comparisonMultiplier,
              textAlign: TextAlign.center,
              style: comparisonText.contains("More") ? bodyMore : comparisonText.contains("Less") ? bodyLess : bodyNeutral
            )), 
          ],
        ),
      ),
    );
  }
}

Widget _historyTab(BuildContext context) {
  var appState = context.watch<MyAppState>();
  var history = appState.measurementHistory;

  return Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(8.0), // TODO: Change hard-coded value?
        child: Row(
          children: [
            SizedBox(width: 27), // TODO: Remove hard-coded value
            Expanded(flex: 2, child: Text('Name', textAlign: TextAlign.left,)),
            Expanded(child: Text('Overall\nDPS', textAlign: TextAlign.center)),
            Expanded(child: Text('Comparison\n(% More/Less)', textAlign: TextAlign.center)),
          ],
        ),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: history.length,
          itemBuilder: (context, index) {
            return HistoryRadio(
              labels: history[index],
              padding: const EdgeInsets.symmetric(horizontal: 5.0),
              value: true,
              groupValue: appState.isRadioSelectedList[index],
              onChanged: (bool newValue) {
                appState.setRadioSelected(index, newValue);
              },
            );
          },
        ),
      ),
    ],
  );
}

Widget _debugTab(BuildContext context) {
  return LogConsole(
    dark: true,
    showCloseButton: false,
  );
}
