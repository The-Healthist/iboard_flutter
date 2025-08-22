import 'package:flutter/material.dart';

class ErrorPage extends StatelessWidget {
  final String errorMessage;
  final VoidCallback onRetry;

  const ErrorPage({
    super.key,
    required this.errorMessage,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Container(
          width: double.infinity,
          height: double.infinity,
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 错误图标
              const Icon(
                Icons.error_outline,
                size: 80,
                color: Colors.redAccent,
              ),
              const SizedBox(height: 30),

              // 错误标题
              Text(
                '初始化失败',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.redAccent,
                    ),
              ),
              const SizedBox(height: 20),

              // 错误描述
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Text(
                  errorMessage,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.grey[700],
                      ),
                ),
              ),
              const SizedBox(height: 30),

              // 重新加载按钮
              ElevatedButton(
                onPressed: () {
                  // _logger.i('🔄 用户点击重新加载按钮');
                  onRetry();
                },
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  backgroundColor: Theme.of(context).primaryColor,
                ),
                child: const Text(
                  '重新加载',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // 返回主页按钮
              TextButton(
                onPressed: () {
                  // _logger.i('🏠 用户点击返回主页按钮');
                  onRetry();
                },
                child: Text(
                  '返回主页',
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).primaryColor,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
