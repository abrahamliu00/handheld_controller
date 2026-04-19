package com.abraham.handheld_controller

import android.content.Intent
import android.provider.Settings
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. 物理摇杆和按键的秘密通道
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.retroid.gamepad/events"
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )

        // 2. 新增：接收 Flutter 指令跳转 WiFi 设置的通道
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.retroid.gamepad/methods"
        ).setMethodCallHandler { call, result ->
            if (call.method == "openWiFiSettings") {
                startActivity(Intent(Settings.ACTION_WIFI_SETTINGS))
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onGenericMotionEvent(event: MotionEvent): Boolean {
        if ((event.source and InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK && event.action == MotionEvent.ACTION_MOVE) {
            val leftX = event.getAxisValue(MotionEvent.AXIS_X)
            val leftY = event.getAxisValue(MotionEvent.AXIS_Y)
            val rightX = event.getAxisValue(MotionEvent.AXIS_Z)
            val rightY = event.getAxisValue(MotionEvent.AXIS_RZ)
            eventSink?.success(
                mapOf(
                    "type" to "analog",
                    "leftX" to leftX,
                    "leftY" to leftY,
                    "rightX" to rightX,
                    "rightY" to rightY
                )
            )
            return true
        }
        return super.onGenericMotionEvent(event)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if ((event.source and InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD ||
            (event.source and InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK
        ) {
            eventSink?.success(mapOf("type" to "button", "keyCode" to keyCode, "isPressed" to true))
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean {
        if ((event.source and InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD ||
            (event.source and InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK
        ) {
            eventSink?.success(
                mapOf(
                    "type" to "button",
                    "keyCode" to keyCode,
                    "isPressed" to false
                )
            )
            return true
        }
        return super.onKeyUp(keyCode, event)
    }
}