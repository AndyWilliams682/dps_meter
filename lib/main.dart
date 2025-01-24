import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dps_meter/src/rust/api/simple.dart';
import 'package:dps_meter/src/rust/frb_generated.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const MyApp());
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
  var result = "";

  void getTime() async {
    result = await hello(a: "Hey there");
    notifyListeners();
  }
}

class MainPage extends StatelessWidget {
  const MainPage({super.key});

  @override
  Widget build(BuildContext context) {   
    var appState = context.watch<MyAppState>();
    var result = appState.result;

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('flutter_rust_bridge quickstart')),
        body: Center(
          child: Column(
            children: [
              Text(
                'Action: Call Rust `greet("Tom")`\nResult: `${greet(name: "Tom")}`'
              ),
              ElevatedButton(onPressed: appState.getTime, child: Text(result))
            ],
          ),
        ),
      ),
    );
  }
}
