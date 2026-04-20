import 'dart:async';
// import 'dart:io' if (dart.library.html) 'dart:html';
import 'package:universal_io/io.dart';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]).then((_) {
    runApp(const RobotControllerApp());
  });
}

const Map<String, Map<String, String>> localStrings = {
  'zh': {
    'nav_settings': '设置',
    'nav_link': '配置连接',
    'nav_linked': '已设置',
    'nav_network': '网络',
    'title_config': '连接配置',
    'ip_label': '下位机IP地址',
    'port_label': '端口号',
    'rtsp_label': '视频流(RTSP)地址',
    'btn_connect': '应用设置',
    'btn_disconnect': '取消设置',
    'btn_control_brief': '控制',
    'panel_title': '摇杆仪表盘',
    'panel_tip': '点击展开',
    'label_lx': 'LX (左右)',
    'label_ly': 'LY (前后)',
    'label_rx': '转向 (RX)',
    'desc_l': '左摇杆(平移)',
    'desc_r': '右摇杆(转向)',
    'soft_estop': '软急停',
    'btn_touch_op': '触屏操控',
    'btn_touch_exit': '结束触屏操控',
    'settings_title': '系统设置',
    'settings_lang': '语言 Language',
    'settings_lang_zh': '简体中文',
    'settings_lang_en': 'English',
    'settings_about': '关于开发者',
    'about_content':
        '版本号: v1.0.0\n联系邮箱: yuhan594@connect.hku.hk\n版权所有 © 2026 Abraham',
    'settings_exit': '退出程序',
  },
  'en': {
    'nav_settings': 'Settings',
    'nav_link': 'Config Connect',
    'nav_linked': 'Configured',
    'nav_network': 'Network',
    'title_config': 'Target Config',
    'ip_label': 'Target IP Address',
    'port_label': 'Port',
    'rtsp_label': 'RTSP Stream URL',
    'btn_connect': 'Apply Config',
    'btn_disconnect': 'Cancel Config',
    'btn_control_brief': 'Control',
    'panel_title': 'Dashboard',
    'panel_tip': 'Tap to expand',
    'label_lx': 'LX (L/R)',
    'label_ly': 'LY (F/B)',
    'label_rx': 'Turn (RX)',
    'desc_l': 'Left Stick (Trans)',
    'desc_r': 'Right Stick (Rot)',
    'soft_estop': 'E-STOP',
    'btn_touch_op': 'Touch Mode',
    'btn_touch_exit': 'Exit Touch Mode',
    'settings_title': 'Settings',
    'settings_lang': 'Language 语言',
    'settings_lang_zh': '简体中文',
    'settings_lang_en': 'English',
    'settings_about': 'About the Developer',
    'about_content':
        'Version: v1.0.0\nEmail: yuhan594@connect.hku.hk\nCopyright © 2026 Abraham',
    'settings_exit': 'Exit App',
  },
};

class RobotControllerApp extends StatelessWidget {
  const RobotControllerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Handheld Controller',
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF5F5F7),
        primaryColor: Colors.black,
        fontFamily: null,
        fontFamilyFallback: const [
          '.SF Pro Display',  // macOS/iOS 简体中文
          'Microsoft YaHei', // Windows 简体中文
          'PingFang SC',     // macOS/iOS 简体中文
          'Noto Sans SC',    // Android/Linux 简体中文
          'sans-serif',
        ],
      ),
      home: const ControllerHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ControllerHomePage extends StatefulWidget {
  const ControllerHomePage({super.key});

  @override
  State<ControllerHomePage> createState() => _ControllerHomePageState();
}

class _ControllerHomePageState extends State<ControllerHomePage> {
  int _currentView = 0;
  bool _isEnglish = false;
  bool _isPanelExpanded = false;

  final TextEditingController _ipController = TextEditingController(
    text: '192.168.2.129',
  );
  final TextEditingController _portController = TextEditingController(
    text: '12121',
  );
  final TextEditingController _rtspController = TextEditingController(
    text: 'rtsp://192.168.2.26:8554/hikvision',
  );

  RawDatagramSocket? _udpSocket;
  Timer? _timer;
  bool _isConnected = false;

  Player? _player;
  VideoController? _videoController;

  double leftX = 0.0, leftY = 0.0;
  double rightX = 0.0, rightY = 0.0;
  bool physicalBPressed = false;
  bool softEStopPressed = false;

  Offset? leftTouchStart;
  Offset? leftTouchCurrent;
  Offset? rightTouchStart;
  Offset? rightTouchCurrent;
  final double touchMaxRadius = 60.0;

  static const gamepadChannel = EventChannel('com.retroid.gamepad/events');
  static const methodChannel = MethodChannel('com.retroid.gamepad/methods');
  StreamSubscription? _channelSub;

  String getStr(String key) =>
      localStrings[_isEnglish ? 'en' : 'zh']?[key] ?? key;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _channelSub = gamepadChannel.receiveBroadcastStream().listen((event) {
        final data = Map<String, dynamic>.from(event);
        setState(() {
          if (data['type'] == 'analog') {
            if (leftTouchStart == null) {
              leftX = _applyDeadzone(data['leftX']);
              leftY = _applyDeadzone(-(data['leftY']));
            }
            if (rightTouchStart == null) {
              rightX = _applyDeadzone(data['rightX']);
              rightY = _applyDeadzone(-(data['rightY']));
            }
          } else if (data['type'] == 'button' && data['keyCode'] == 97) {
            physicalBPressed = data['isPressed'];
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _channelSub?.cancel();
    _timer?.cancel();
    if (!kIsWeb) _udpSocket?.close();

    _safelyDisposeVideo();

    _ipController.dispose();
    _portController.dispose();
    _rtspController.dispose();

    super.dispose();
  }

  Future<void> _safelyDisposeVideo() async {
    try {
      final p = _player;
      _player = null;
      _videoController = null;
      await p?.dispose();
    } catch (e) {
      debugPrint("MediaKit Dispose Warning: $e");
    }
  }

  double _applyDeadzone(double value) => value.abs() < 0.05 ? 0.0 : value;

  Future<void> _toggleConnection() async {
    if (_isConnected) {
      setState(() => _isConnected = false);
      _timer?.cancel();
      if (!kIsWeb) _udpSocket?.close();

      await _safelyDisposeVideo();
      if (mounted) setState(() {});
      return;
    }

    try {
      final targetIp = !kIsWeb ? InternetAddress(_ipController.text) : null;
      final targetPort = int.parse(_portController.text);

      if (!kIsWeb) {
        _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      }

      _player = Player(
        configuration: const PlayerConfiguration(bufferSize: 2 * 1024 * 1024),
      );
      _videoController = VideoController(_player!);

      await _player?.open(Media(_rtspController.text));
      _player?.play();

      setState(() => _isConnected = true);

      _timer = Timer.periodic(const Duration(milliseconds: 20), (timer) {
        if (!mounted) return;

        if (kIsWeb ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux) {
          final keys = HardwareKeyboard.instance.logicalKeysPressed;
          double tempLeftX = 0.0, tempLeftY = 0.0;
          double tempRightX = 0.0, tempRightY = 0.0;

          if (keys.contains(LogicalKeyboardKey.keyW)) tempLeftY = 1.0;
          if (keys.contains(LogicalKeyboardKey.keyS)) tempLeftY = -1.0;
          if (keys.contains(LogicalKeyboardKey.keyA)) tempLeftX = -1.0;
          if (keys.contains(LogicalKeyboardKey.keyD)) tempLeftX = 1.0;

          if (keys.contains(LogicalKeyboardKey.arrowUp)) tempRightY = 1.0;
          if (keys.contains(LogicalKeyboardKey.arrowDown)) tempRightY = -1.0;
          if (keys.contains(LogicalKeyboardKey.arrowLeft)) tempRightX = -1.0;
          if (keys.contains(LogicalKeyboardKey.arrowRight)) tempRightX = 1.0;

          final newBPressed = keys.contains(LogicalKeyboardKey.space);

          bool shouldUpdateUI = false;

          if (leftTouchStart == null &&
              (leftX != tempLeftX || leftY != tempLeftY)) {
            leftX = tempLeftX;
            leftY = tempLeftY;
            shouldUpdateUI = true;
          }

          if (rightTouchStart == null &&
              (rightX != tempRightX || rightY != tempRightY)) {
            rightX = tempRightX;
            rightY = tempRightY;
            shouldUpdateUI = true;
          }

          if (physicalBPressed != newBPressed) {
            physicalBPressed = newBPressed;
            shouldUpdateUI = true;
          }

          if (shouldUpdateUI) {
            setState(() {});
          }
        }

        if (!kIsWeb && targetIp != null) {
          _udpSocket?.send(_buildRetroidPacket(), targetIp, targetPort);
        }
      });
    } catch (e) {
      _timer?.cancel();

      await _safelyDisposeVideo();
      if (mounted)
        setState(() {
          _isConnected = false;
        });
    }
  }

  Uint8List _buildRetroidPacket() {
    var buffer = ByteData(42);
    buffer.setUint8(0, 0x55);
    buffer.setUint8(1, 0x66);
    buffer.setUint8(2, 0x00);
    buffer.setUint16(3, 32, Endian.little);
    buffer.setUint16(5, 0, Endian.little);
    buffer.setUint8(7, 0x01);

    if (physicalBPressed || softEStopPressed)
      buffer.setInt16(24, 1, Endian.little);

    buffer.setInt16(30, (leftX * 1000).toInt(), Endian.little);
    buffer.setInt16(32, (leftY * 1000).toInt(), Endian.little);
    buffer.setInt16(34, (rightX * 1570).toInt(), Endian.little);
    buffer.setInt16(36, (rightY * 1000).toInt(), Endian.little);

    int crc = 0;
    for (int i = 10; i < 42; i++) {
      crc += buffer.getUint8(i);
    }

    buffer.setUint16(8, crc, Endian.little);
    return buffer.buffer.asUint8List();
  }

  Future<void> _openWiFiSettings() async {
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await methodChannel.invokeMethod('openWiFiSettings');
      } else {
        debugPrint("当前平台暂不支持应用内跳转WiFi，请手动前往系统设置连接。");
      }
    } catch (e) {
      debugPrint("WiFi Error: $e");
    }
  }

  // ==================== UI View 0: Home Page ====================
  Widget _buildHomeView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            child: GestureDetector(
              onTap: _showSettingsModal,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  CupertinoIcons.settings_solid,
                  color: Colors.black54,
                  size: 24,
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 60,
            child: GestureDetector(
              onTap: _showConnectionModal,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.link_circle_fill,
                      color: _isConnected
                          ? CupertinoColors.activeBlue
                          : Colors.black38,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isConnected ? getStr('nav_linked') : getStr('nav_link'),
                      style: TextStyle(
                        color: _isConnected
                            ? CupertinoColors.activeBlue
                            : Colors.black87,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: GestureDetector(
              onTap: _openWiFiSettings,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Text(
                      getStr('nav_network'),
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      CupertinoIcons.wifi,
                      color: Colors.black87,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: RichText(
              textAlign: TextAlign.center,
              text: const TextSpan(
                children: [
                  TextSpan(
                    text: 'Handheld',
                    style: TextStyle(
                      color: Color(0xFF636366),
                      fontSize: 50,
                      fontWeight: FontWeight.w400,
                      fontStyle: FontStyle.italic,
                      letterSpacing: 1,
                    ),
                  ),
                  WidgetSpan(child: SizedBox(width: 40)),
                  TextSpan(
                    text: 'Controller',
                    style: TextStyle(
                      color: CupertinoColors.activeBlue,
                      fontSize: 50,
                      fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: GestureDetector(
              onTap: () => setState(() => _currentView = 1),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.08),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(
                      CupertinoIcons.gear_alt_fill,
                      color: Colors.black87,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      getStr('btn_control_brief'),
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== Modals ====================
  void _showConnectionModal() {
    showCupertinoDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, updateModalState) {
            return Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 400,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        getStr('title_config'),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  getStr('ip_label'),
                                  style: const TextStyle(
                                    color: Colors.black54,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                CupertinoTextField(
                                  controller: _ipController,
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 15,
                                  ),
                                  decoration: BoxDecoration(
                                    color: CupertinoColors.systemGrey6,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding: const EdgeInsets.all(10),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 1,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  getStr('port_label'),
                                  style: const TextStyle(
                                    color: Colors.black54,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                CupertinoTextField(
                                  controller: _portController,
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 15,
                                  ),
                                  decoration: BoxDecoration(
                                    color: CupertinoColors.systemGrey6,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding: const EdgeInsets.all(10),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        getStr('rtsp_label'),
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      CupertinoTextField(
                        controller: _rtspController,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 15,
                        ),
                        decoration: BoxDecoration(
                          color: CupertinoColors.systemGrey6,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.all(10),
                      ),
                      const SizedBox(height: 24),
                      GestureDetector(
                        onTap: () {
                          if (Navigator.canPop(context)) {
                            Navigator.pop(context);
                          }
                          _toggleConnection();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: double.infinity,
                          height: 45,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _isConnected
                                ? CupertinoColors.destructiveRed
                                : CupertinoColors.activeBlue,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _isConnected
                                ? getStr('btn_disconnect')
                                : getStr('btn_connect'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showSettingsModal() {
    showCupertinoDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 300,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 15),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    getStr('settings_title'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        getStr('settings_lang'),
                        style: const TextStyle(fontSize: 16),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        child: Text(
                          _isEnglish
                              ? getStr('settings_lang_zh')
                              : getStr('settings_lang_en'),
                          style: const TextStyle(fontSize: 16),
                        ),
                        onPressed: () {
                          setState(() => _isEnglish = !_isEnglish);
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                  const Divider(color: Colors.black12, height: 30),

                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: Text(
                      getStr('settings_about'),
                      style: const TextStyle(
                        fontSize: 16,
                        color: CupertinoColors.activeBlue,
                      ),
                    ),
                    onPressed: () {
                      showCupertinoDialog(
                        context: context,
                        builder: (context) => CupertinoAlertDialog(
                          title: const Text('Handheld Controller'),
                          content: Padding(
                            padding: const EdgeInsets.only(top: 10.0),
                            child: Text(
                              getStr('about_content'),
                              textAlign: TextAlign.left,
                              style: const TextStyle(height: 1.5),
                            ),
                          ),
                          actions: [
                            CupertinoDialogAction(
                              child: Text(
                                _isEnglish ? 'OK' : '确定',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const Divider(color: Colors.black12, height: 30),

                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: Text(
                      getStr('settings_exit'),
                      style: const TextStyle(
                        color: CupertinoColors.destructiveRed,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () async {
                      await _safelyDisposeVideo();
                      // SystemNavigator.pop();
                      if (kIsWeb) {
                      } else if (defaultTargetPlatform ==
                              TargetPlatform.android ||
                          defaultTargetPlatform == TargetPlatform.iOS) {
                        SystemNavigator.pop(); // 移动端标准退出
                      } else {
                        exit(0);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ==================== Reusable Components ====================
  Widget _buildEStopButton() {
    return Positioned(
      top: 20,
      left: 30,
      child: GestureDetector(
        onTapDown: (_) => setState(() => softEStopPressed = true),
        onTapUp: (_) => setState(() => softEStopPressed = false),
        onTapCancel: () => setState(() => softEStopPressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: softEStopPressed
                ? CupertinoColors.destructiveRed
                : Colors.white,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: CupertinoColors.destructiveRed,
              width: 1.5,
            ),
            boxShadow: softEStopPressed
                ? []
                : const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.stop_circle_rounded,
                color: softEStopPressed
                    ? Colors.white
                    : CupertinoColors.destructiveRed,
                size: 18,
              ),
              const SizedBox(width: 4),
              Text(
                getStr('soft_estop'),
                style: TextStyle(
                  color: softEStopPressed
                      ? Colors.white
                      : CupertinoColors.destructiveRed,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpandableDataPanel() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _isPanelExpanded = !_isPanelExpanded),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_isPanelExpanded ? 24 : 100),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 15,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_isPanelExpanded ? 24 : 100),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutQuart,
              width: _isPanelExpanded ? 320 : 150,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(
                  alpha: _isPanelExpanded ? 0.35 : 0.8,
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.5),
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(
                  _isPanelExpanded ? 24 : 100,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isPanelExpanded
                            ? CupertinoIcons.graph_circle_fill
                            : CupertinoIcons.graph_circle,
                        color: CupertinoColors.activeBlue,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          getStr('panel_title'),
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        _isPanelExpanded
                            ? CupertinoIcons.chevron_up
                            : CupertinoIcons.chevron_down,
                        color: Colors.black38,
                        size: 16,
                      ),
                    ],
                  ),
                  if (_isPanelExpanded) ...[
                    const SizedBox(height: 16),
                    const Divider(color: Colors.black12),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Text(
                          "L",
                          style: TextStyle(
                            color: Colors.black54,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                getStr('desc_l'),
                                style: const TextStyle(
                                  color: CupertinoColors.activeBlue,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 6),
                              _buildDataRow(getStr('label_ly'), leftY * 1.0, 'm/s'),
                              _buildDataRow(getStr('label_lx'), leftX * 1.0, 'm/s'),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text(
                          "R",
                          style: TextStyle(
                            color: Colors.black54,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                getStr('desc_r'),
                                style: const TextStyle(
                                  color: CupertinoColors.activeBlue,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 6),
                              _buildDataRow(getStr('label_rx'), rightX * 1.57, 'rad/s'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDataRow(String label, double value, String unit) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.black54, fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${value.toStringAsFixed(2)} $unit',
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 16,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoBackground(double screenWidth, double screenHeight) {
    if (_videoController == null) {
      return Container(color: Colors.black);
    }
    return SizedBox(
      width: screenWidth,
      height: screenHeight,
      child: Container(
        color: Colors.black,
        child: Video(
          controller: _videoController!,
          fit: BoxFit.cover,
          controls: NoVideoControls,
        ),
      ),
    );
  }

  Widget _buildCloseButton() {
    return Positioned(
      top: 20,
      right: 30,
      child: GestureDetector(
        onTap: () => setState(() {
          _currentView = 0;
          _isPanelExpanded = false;
          leftX = 0.0;
          leftY = 0.0;
          rightX = 0.0;
          rightY = 0.0;
        }),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.3),
              width: 1,
            ),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
          ),
          child: const Icon(
            CupertinoIcons.xmark,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }

  // ==================== UI View 1: Monitor View ====================
  Widget _buildMonitorView() {
    double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !_isPanelExpanded,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _isPanelExpanded = false),
              child: Container(color: Colors.transparent),
            ),
          ),
        ),

        _buildEStopButton(),

        AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutQuart,
          top: _isPanelExpanded ? (screenHeight - 240) / 2 : 20,
          left: _isPanelExpanded ? (screenWidth - 320) / 2 : 145,
          child: _buildExpandableDataPanel(),
        ),

        _buildCloseButton(),

        Positioned(
          bottom: 20,
          right: 30,
          child: GestureDetector(
            onTap: () => setState(() => _currentView = 2),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 8),
                ],
              ),
              child: Row(
                children: [
                  const Icon(
                    CupertinoIcons.hand_draw_fill,
                    color: Colors.black87,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    getStr('btn_touch_op'),
                    style: const TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ==================== UI View 2: Touch Control View ====================
  Widget _buildTouchView() {
    double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;

    return Stack(
      children: [
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (details) => setState(
                  () =>
                      leftTouchStart = leftTouchCurrent = details.localPosition,
                ),
                onPanUpdate: (details) {
                  setState(() {
                    leftTouchCurrent = details.localPosition;
                    double dx = leftTouchCurrent!.dx - leftTouchStart!.dx;
                    double dy = leftTouchCurrent!.dy - leftTouchStart!.dy;
                    double distance = math.sqrt(dx * dx + dy * dy);
                    if (distance > touchMaxRadius) {
                      dx = (dx / distance) * touchMaxRadius;
                      dy = (dy / distance) * touchMaxRadius;
                      leftTouchCurrent = Offset(
                        leftTouchStart!.dx + dx,
                        leftTouchStart!.dy + dy,
                      );
                    }
                    leftX = dx / touchMaxRadius;
                    leftY = -(dy / touchMaxRadius);
                  });
                },
                onPanEnd: (_) => setState(() {
                  leftTouchStart = null;
                  leftTouchCurrent = null;
                  leftX = 0.0;
                  leftY = 0.0;
                }),
              ),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (details) => setState(
                  () => rightTouchStart = rightTouchCurrent =
                      details.localPosition,
                ),
                onPanUpdate: (details) {
                  setState(() {
                    rightTouchCurrent = details.localPosition;
                    double dx = rightTouchCurrent!.dx - rightTouchStart!.dx;
                    double dy = rightTouchCurrent!.dy - rightTouchStart!.dy;
                    double distance = math.sqrt(dx * dx + dy * dy);
                    if (distance > touchMaxRadius) {
                      dx = (dx / distance) * touchMaxRadius;
                      dy = (dy / distance) * touchMaxRadius;
                      rightTouchCurrent = Offset(
                        rightTouchStart!.dx + dx,
                        rightTouchStart!.dy + dy,
                      );
                    }
                    rightX = dx / touchMaxRadius;
                    rightY = -(dy / touchMaxRadius);
                  });
                },
                onPanEnd: (_) => setState(() {
                  rightTouchStart = null;
                  rightTouchCurrent = null;
                  rightX = 0.0;
                  rightY = 0.0;
                }),
              ),
            ),
          ],
        ),

        if (leftTouchStart != null)
          Positioned(
            left: leftTouchStart!.dx - touchMaxRadius,
            top: leftTouchStart!.dy - touchMaxRadius,
            child: IgnorePointer(
              child: Container(
                width: touchMaxRadius * 2,
                height: touchMaxRadius * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.7),
                    width: 2,
                  ),
                  color: Colors.black.withValues(alpha: 0.2),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Center(
                  child: Transform.translate(
                    offset: Offset(
                      leftTouchCurrent!.dx - leftTouchStart!.dx,
                      leftTouchCurrent!.dy - leftTouchStart!.dy,
                    ),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.95),
                        border: Border.all(color: Colors.black38, width: 1),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black54,
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

        if (rightTouchStart != null)
          Positioned(
            left: screenWidth / 2 + rightTouchStart!.dx - touchMaxRadius,
            top: rightTouchStart!.dy - touchMaxRadius,
            child: IgnorePointer(
              child: Container(
                width: touchMaxRadius * 2,
                height: touchMaxRadius * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.7),
                    width: 2,
                  ),
                  color: Colors.black.withValues(alpha: 0.2),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Center(
                  child: Transform.translate(
                    offset: Offset(
                      rightTouchCurrent!.dx - rightTouchStart!.dx,
                      rightTouchCurrent!.dy - rightTouchStart!.dy,
                    ),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.95),
                        border: Border.all(color: Colors.black38, width: 1),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black54,
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

        _buildEStopButton(),

        AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutQuart,
          top: _isPanelExpanded ? (screenHeight - 240) / 2 : 20,
          left: _isPanelExpanded ? (screenWidth - 320) / 2 : 145,
          child: _buildExpandableDataPanel(),
        ),

        _buildCloseButton(),

        Positioned(
          bottom: 20,
          right: 30,
          child: GestureDetector(
            onTap: () => setState(() {
              _currentView = 1;
              leftX = 0.0;
              leftY = 0.0;
              rightX = 0.0;
              rightY = 0.0;
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: CupertinoColors.destructiveRed.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: CupertinoColors.destructiveRed.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    CupertinoIcons.clear_circled_solid,
                    color: CupertinoColors.destructiveRed,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    getStr('btn_touch_exit'),
                    style: const TextStyle(
                      color: CupertinoColors.destructiveRed,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFFF5F5F7),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),

        child: Stack(
          children: [
            if (_videoController != null)
              Offstage(
                offstage: _currentView == 0,
                child: _buildVideoBackground(screenWidth, screenHeight),
              ),

            if (_currentView == 0) Container(color: const Color(0xFFF5F5F7)),

            if (_currentView == 0) _buildHomeView(),
            if (_currentView == 1) _buildMonitorView(),
            if (_currentView == 2) _buildTouchView(),
          ],
        ),
      ),
    );
  }
}
