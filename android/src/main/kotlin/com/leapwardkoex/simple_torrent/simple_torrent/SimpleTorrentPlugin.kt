package com.leapwardkoex.simple_torrent.simple_torrent

import android.os.Handler
import android.os.Looper
import androidx.annotation.Keep
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

@Keep
class SimpleTorrentPlugin : FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    companion object {
        private var active: SimpleTorrentPlugin? = null
        private val main = Handler(Looper.getMainLooper())

        @Keep
        @JvmStatic
        fun sendStats(stats: Map<String, Int>) {
            main.post { active?.eventSink?.success(stats) }
        }
    }

    private lateinit var methodChannel: MethodChannel
    private lateinit var progressChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null

    // ── native interface ────────────────────────────────────────────────
    @Keep
    private external fun startTorrent(magnet: String, dest: String): Int
    @Keep
    private external fun pauseTorrent(id: Int)
    @Keep
    private external fun resumeTorrent(id: Int)
    @Keep
    private external fun cancelTorrent(id: Int)

    // ── FlutterPlugin lifecycle ─────────────────────────────────────────
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        active = this
        methodChannel = MethodChannel(binding.binaryMessenger, "simple_torrent/methods")
        progressChannel = EventChannel(binding.binaryMessenger, "simple_torrent/progress")
        methodChannel.setMethodCallHandler(this)
        progressChannel.setStreamHandler(this)

        // load native libraries once
        System.loadLibrary("torrent-rasterbar")
        System.loadLibrary("torrent_plugin")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        active = null
        methodChannel.setMethodCallHandler(null)
        progressChannel.setStreamHandler(null)
    }

    // ── MethodChannel handling ─────────────────────────────────────────
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                val magnet = call.argument<String>("magnet")
                val dest   = call.argument<String>("destination")
                if (magnet.isNullOrEmpty() || dest.isNullOrEmpty()) {
                    result.error("INVALID_ARGS", "magnet and destination are required", null)
                } else {
                    val id = startTorrent(magnet, dest)
                    if (id == 0) result.error("FAILED", "could not start torrent", null)
                    else result.success(id)
                }
            }
            "pause"   -> call.argument<Int>("id")?.let { pauseTorrent(it); result.success(null) }
            "resume"  -> call.argument<Int>("id")?.let { resumeTorrent(it); result.success(null) }
            "cancel"  -> call.argument<Int>("id")?.let { cancelTorrent(it); result.success(null) }
            else        -> result.notImplemented()
        }
    }

    // ── EventChannel plumbing ──────────────────────────────────────────
    override fun onListen(arguments: Any?, events: EventChannel.EventSink) { eventSink = events }
    override fun onCancel(arguments: Any?) { eventSink = null }
}
