import 'package:flutter/material.dart';
import 'package:iboard_app/widgets/mainscreen/live_monitor_widget.dart';

///實時監控頁面 - WebView四宮格方案
class LiveMonitorWebViewPage extends StatefulWidget {
  const LiveMonitorWebViewPage({super.key});

  @override
  State<LiveMonitorWebViewPage> createState() => _LiveMonitorWebViewPageState();
}

class _LiveMonitorWebViewPageState extends State<LiveMonitorWebViewPage> {
  final GlobalKey<LiveMonitorWidgetState> _liveMonitorKey = GlobalKey<LiveMonitorWidgetState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('實時監控'),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            onPressed: _refreshMonitorChannels,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新监控通道',
          ),
        ],
      ),
      body: LiveMonitorWidget(
        key: _liveMonitorKey,
      ),
    );
  }

  ///1, 刷新监控通道
  void _refreshMonitorChannels() async {
    if (_liveMonitorKey.currentState != null) {
      await _liveMonitorKey.currentState!.refreshMonitorChannels();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('监控通道已刷新'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // 检查是否从设置页面返回并需要更新
    final result = ModalRoute.of(context)?.settings.arguments;
    if (result == true) {
      // 延迟执行刷新，确保页面已经完全加载
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _refreshMonitorChannels();
      });
    }
  }
}
