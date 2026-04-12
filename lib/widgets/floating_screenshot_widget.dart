
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_floating_window/flutter_floating_window.dart';
import 'package:media_projection_screenshot/media_projection_screenshot.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'package:permission_handler/permission_handler.dart';

class FloatingScreenshotWidget extends StatefulWidget {
  const FloatingScreenshotWidget({super.key});

  @override
  State<FloatingScreenshotWidget> createState() => _FloatingScreenshotWidgetState();
}

class _FloatingScreenshotWidgetState extends State<FloatingScreenshotWidget> {
  bool _isFloating = false;
  bool _isCapturing = false;
  double _dragDistance = 0;
  double _windowX = 0;
  double _windowY = 200;

  @override
  void initState() {
    super.initState();
    _checkFloatingPermission();
  }

  Future<void> _checkFloatingPermission() async {
    final status = await Permission.overlay.request();
    if (status.isGranted) {
      _showFloatingWindow();
    } else {
      print('浮窗权限被拒绝');
    }
  }

  Future<void> _showFloatingWindow() async {
    final window = FloatingWindow(
      width: 60,
      height: 60,
      gravity: Gravity.right | Gravity.bottom,
      x: _windowX.toInt(),
      y: _windowY.toInt(),
      view: _buildFloatingView(),
      flags: WindowFlag.notFocusable | WindowFlag.notTouchModal,
      type: WindowType.phone,
      onTouchEvent: (event) {
        if (event.action == MotionEvent.actionDown) {
          _dragDistance = event.rawX;
        } else if (event.action == MotionEvent.actionMove) {
          final distance = event.rawX - _dragDistance;
          _windowX -= distance;
          _dragDistance = event.rawX;
          // 更新窗口位置
          // 这里需要实现窗口移动逻辑
        }
      },
    );

    await window.show();
    setState(() => _isFloating = true);
  }

  Widget _buildFloatingView() {
    return GestureDetector(
      onTap: _captureAndUploadScreenshot,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.8),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Icon(Icons.camera_alt, color: Colors.white, size: 30),
      ),
    );
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

      // 捕获截图
      final screenshotData = await MediaProjectionScreenshot.takeScreenshot();

      if (screenshotData != null) {
        // 转换为jpg格式
        final image = img.decodePng(screenshotData);
        final jpgData = img.encodeJpg(image, quality: 85);

        // 保存到文件
        final tempDir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final filePath = '${tempDir.path}/screenshot_$timestamp.jpg';
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
      final serverUrl = prefs.getString('server_url') ?? 'https://track-api.rethinkos.com';

      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: 'screenshot.jpg'),
      });

      final response = await Dio().post('$server_url/api/screenshots/upload', data: formData);

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
    return Container(); // 这个widget只是用来初始化浮窗，不实际显示UI
  }
}
