import 'package:flutter/material.dart';
import 'package:iboard_app/widgets/mainscreen/live_monitor_widget.dart';

///實時監控頁面 - WebView四宮格方案
class LiveMonitorWebViewPage extends StatelessWidget {
  const LiveMonitorWebViewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('實時監控'),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: const LiveMonitorWidget(),
    );
  }
}
