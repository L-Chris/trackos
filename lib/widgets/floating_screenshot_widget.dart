import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_floating_window/flutter_floating_window.dart';
import 'package:trackos_screenshot/trackos_screenshot.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';

import '../services/screenshot_service.dart';

class FloatingScreenshotWidget extends StatefulWidget {
  const FloatingScreenshotWidget({super.key});

  @override
  State<FloatingScreenshotWidget> createState() => _FloatingScreenshotWidgetState();
}

class _FloatingScreenshotWidgetState extends State<FloatingScreenshotWidget> {
  final _windowManager = FloatingWindowManager.instance;
  bool _isCapturing = false;
  String? _windowId;
  StreamSubscription<FloatingWindowEvent>? _eventSub;

  @override
  void initState() {
    super.initState();
    _initFloatingWindow();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    if (_windowId != null) {
      _windowManager.closeWindow(_windowId!).ignore();
    }
    super.dispose();
  }

  Future<void> _initFloatingWindow() async {
    try {
      // 1. 检查/申请浮窗权限
      bool hasPermission = await _windowManager.hasOverlayPermission();
      if (!hasPermission) {
        await _windowManager.requestOverlayPermission();
        // 等待用户授权后重新检查
        await Future.delayed(const Duration(seconds: 2));
        hasPermission = await _windowManager.hasOverlayPermission();
      }
      if (!hasPermission) {
        print('浮窗权限被拒绝');
        return;
      }

      // 2. 启动浮窗服务
      final serviceRunning = await _windowManager.isServiceRunning();
      if (!serviceRunning) {
        await _windowManager.startService();
      }

      // 3. 计算物理像素坐标，将浮窗吸附到右下角
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      final dpr = view.devicePixelRatio;
      final physW = view.physicalSize.width;
      final physH = view.physicalSize.height;

      const windowDp = 90;
      const marginRightDp = 16;
      const marginBottomDp = 80; // 底部导航栏 + 留白
      final windowPx = (windowDp * dpr).toInt();
      final marginRPx = (marginRightDp * dpr).toInt();
      final marginBPx = (marginBottomDp * dpr).toInt();

      final posX = (physW - windowPx - marginRPx).toInt();
      final posY = (physH - windowPx - marginBPx).toInt();

      // 4. 创建截图按钮浮窗
      _windowId = await _windowManager.createWindow(FloatingWindowConfig(
        width: windowPx,
        height: windowPx,
        isDraggable: true,
        stayOnTop: true,
        focusable: false,
        showCloseButton: false,
        backgroundColor: 0xCC1565C0, // 深蓝色半透明
        cornerRadius: (windowPx / 2).toDouble(),
        initialX: posX,
        initialY: posY,
        title: '📷',
      ));

      // 5. 监听点击事件触发截图
      _eventSub = _windowManager.eventStream.listen((event) {
        if (event.windowId == _windowId &&
            event.type == FloatingWindowEventType.windowClicked) {
          _captureAndUploadScreenshot();
        }
      });
    } catch (e) {
      print('浮窗初始化失败: $e');
    }
  }

  Future<void> _captureAndUploadScreenshot() async {
    if (_isCapturing) return;
    setState(() => _isCapturing = true);

    try {
      // 请求MediaProjection权限
      final granted = await MediaProjectionScreenshot.requestPermission();
      if (!granted) {
        print('MediaProjection权限被拒绝');
        return;
      }

      // 捕获截图（PNG字节）
      final screenshotData = await MediaProjectionScreenshot.takeScreenshot();

      if (screenshotData != null) {
        // 解码PNG并转换为JPG格式
        final image = img.decodePng(screenshotData);
        if (image == null) {
          print('截图PNG解码失败');
          return;
        }
        final jpgData = img.encodeJpg(image, quality: 85);

        // 保存到持久化外部存储目录（文件管理器可访问）
        final dir = await ScreenshotService.getDir();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final filePath = '${dir.path}/screenshot_$timestamp.jpg';
        await File(filePath).writeAsBytes(jpgData);

        // 上传到服务器
        await _uploadScreenshot(filePath);

        print('截图已保存并上传: $filePath');
      }
    } catch (e) {
      print('截图失败: $e');
    } finally {
      setState(() => _isCapturing = false);
    }
  }

  Future<void> _uploadScreenshot(String filePath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serverUrl =
          prefs.getString('server_url') ?? 'https://track-api.rethinkos.com';

      final formData = FormData.fromMap({
        'file':
            await MultipartFile.fromFile(filePath, filename: 'screenshot.jpg'),
      });

      final response =
          await Dio().post('$serverUrl/api/screenshots/upload', data: formData);

      if (response.statusCode == 200) {
        print('截图上传成功');
      } else {
        print('截图上传失败: ${response.statusCode}');
      }
    } catch (e) {
      print('上传失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink(); // 不实际显示UI，浮窗由系统层渲染
  }
}
