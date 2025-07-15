import 'package:flutter/material.dart';
import 'package:iboard_app/pages/main_page.dart';
import 'package:iboard_app/providers/announcement_provider.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:iboard_app/providers/state_provider.dart'; // Added CarouselStateProvider import
import 'package:provider/provider.dart';
import 'pages/mainscreen_page.dart';
import 'pages/fullscreen_ads_page.dart';
import 'pages/settings_page.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (context) =>
              AppDataProvider(baseUrl: 'http://test.iboard.skylinedances.com'),
        ),
        ChangeNotifierProxyProvider<AppDataProvider, AnnouncementProvider>(
          create: (context) => AnnouncementProvider(
            Provider.of<AppDataProvider>(context, listen: false).apiClient,
            Provider.of<AppDataProvider>(context, listen: false),
          ),
          update: (context, appDataProvider, previousAnnouncementProvider) =>
              AnnouncementProvider(
            appDataProvider.apiClient,
            appDataProvider,
          ),
        ),
        ChangeNotifierProvider(
            create: (_) =>
                CarouselStateProvider()), // Add CarouselStateProvider here
      ],
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iBoard App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: HomePage(),
      routes: {
        '/main': (context) => MainPage(),
        '/announcement': (context) => AnnouncementPage(),
        '/fullscreen-ads': (context) => FullscreenAdsPage(),
        '/settings': (context) => SettingsPage(),
      },
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isAnnouncementLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('iBoard 主頁'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () async {
                String deviceIdToUse =
                    "DEVICE_25E970A5"; // Default or production device ID
                try {
                  await Provider.of<AppDataProvider>(context, listen: false)
                      .initializeAndLogin(deviceIdToSet: deviceIdToUse);
                  if (context.mounted) {
                    Navigator.pushNamed(context, '/main');
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Login failed: $e')),
                    );
                  }
                  print("Login failed: $e");
                }
              },
              child: Text('Main'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.pushNamed(context, '/settings');
              },
              child: Text('設置頁面'),
            ),
          ],
        ),
      ),
    );
  }
}
