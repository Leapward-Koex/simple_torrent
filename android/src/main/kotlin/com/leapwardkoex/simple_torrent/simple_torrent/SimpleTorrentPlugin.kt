package com.leapwardkoex.simple_torrent.simple_torrent

import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.Keep
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Collections

@Keep
class SimpleTorrentPlugin : FlutterPlugin,
    MethodChannel.MethodCallHandler {

    companion object {
        private val pluginInstances =
            Collections.synchronizedSet(mutableSetOf<SimpleTorrentPlugin>())
        private val mainHandler = Handler(Looper.getMainLooper())
        private const val TAG = "SimpleTorrentPlugin"

        // ── static bridge for native code ──────────────────────────────
        @Keep
        @JvmStatic
        fun sendStats(stats: Map<String, Int>) {
            Log.d(TAG, "sendStats: $stats")
            mainHandler.post {
                synchronized(pluginInstances) {
                    pluginInstances.forEach { plugin ->
                        plugin.handleStatsUpdate(stats)
                    }
                }
            }
        }

        @Keep
        @JvmStatic
        fun sendMetadata(metadata: Map<String, Any>) {
            Log.d(TAG, "sendMetadata: $metadata")
            mainHandler.post {
                synchronized(pluginInstances) {
                    pluginInstances.forEach { plugin ->
                        plugin.handleMetadataUpdate(metadata)
                    }
                }
            }
        }
    }

    private lateinit var methodChannel: MethodChannel
    private lateinit var progressChannel: EventChannel
    private lateinit var metadataChannel: EventChannel
    private var progressSink: EventChannel.EventSink? = null
    private var metadataSink: EventChannel.EventSink? = null

    // Buffer for stats and metadata when no listener is active
    private val statsBuffer = mutableListOf<Map<String, Int>>()
    private val metadataBuffer = mutableListOf<Map<String, Any>>()
    private val maxBufferSize = 10 // Keep only the latest 10 items

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
        pluginInstances.add(this)

        methodChannel = MethodChannel(binding.binaryMessenger, "simple_torrent/methods")
        progressChannel = EventChannel(binding.binaryMessenger, "simple_torrent/progress")
        metadataChannel = EventChannel(binding.binaryMessenger, "simple_torrent/metadata")

        methodChannel.setMethodCallHandler(this)

        progressChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                Log.d(TAG, "Progress stream listener attaching…")
                progressSink = events
                // Flush any buffered stats
                synchronized(statsBuffer) {
                    statsBuffer.forEach { bufferedStats ->
                        try {
                            progressSink?.success(bufferedStats)
                        } catch (exception: Exception) {
                            Log.w(TAG, "Failed to send buffered stats: ${exception.message}")
                        }
                    }
                    statsBuffer.clear()
                    Log.d(TAG, "Progress listener attached and buffer flushed")
                }
            }

            override fun onCancel(arguments: Any?) {
                Log.d(TAG, "Progress stream listener cancelling…")
                progressSink = null
            }
        })

        metadataChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                Log.d(TAG, "Metadata stream listener attaching…")
                metadataSink = events
                // Flush any buffered metadata
                synchronized(metadataBuffer) {
                    metadataBuffer.forEach { bufferedMeta ->
                        try {
                            metadataSink?.success(bufferedMeta)
                        } catch (exception: Exception) {
                            Log.w(TAG, "Failed to send buffered metadata: ${exception.message}")
                        }
                    }
                    metadataBuffer.clear()
                    Log.d(TAG, "Metadata listener attached and buffer flushed")
                }
            }

            override fun onCancel(arguments: Any?) {
                Log.d(TAG, "Metadata stream listener cancelling…")
                metadataSink = null
            }
        })

        // Load native libraries once
        System.loadLibrary("torrent-rasterbar")
        System.loadLibrary("torrent_plugin")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        pluginInstances.remove(this)

        methodChannel.setMethodCallHandler(null)
        progressChannel.setStreamHandler(null)
        metadataChannel.setStreamHandler(null)

        // Clear buffers to prevent memory leaks
        synchronized(statsBuffer) {
            statsBuffer.clear()
        }
        synchronized(metadataBuffer) {
            metadataBuffer.clear()
        }
    }

    // ── Internal handlers for buffering and sending data ───────────────
    private fun handleStatsUpdate(stats: Map<String, Int>) {
        val sink = progressSink
        if (sink != null) {
            try {
                sink.success(stats)
                Log.v(TAG, "Stats sent to active listener")
                return
            } catch (exception: Exception) {
                Log.w(TAG, "Failed to send stats: ${exception.message}")
            }
        }
        // Buffer the stats if send failed or no listener
        synchronized(statsBuffer) {
            statsBuffer.add(stats)
            while (statsBuffer.size > maxBufferSize) {
                statsBuffer.removeAt(0);
            }
        }
        Log.d(TAG, "Stats buffered, current buffer size: ${statsBuffer.size}")
    }

    private fun handleMetadataUpdate(metadata: Map<String, Any>) {
        val sink = metadataSink
        if (sink != null) {
            try {
                sink.success(metadata)
                Log.v(TAG, "Metadata sent to active listener")
                return
            } catch (exception: Exception) {
                Log.w(TAG, "Failed to send metadata: ${exception.message}")
            }
        }
        // Buffer the metadata if send failed or no listener
        synchronized(metadataBuffer) {
            metadataBuffer.add(metadata)
            while (metadataBuffer.size > maxBufferSize) {
                metadataBuffer.removeFirst()
            }
        }
        Log.d(TAG, "Metadata buffered, current buffer size: ${metadataBuffer.size}")
    }

    // ── MethodChannel handling ─────────────────────────────────────────
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                val magnet = call.argument<String>("magnet")
                val destination = call.argument<String>("destination")
                if (magnet.isNullOrEmpty() || destination.isNullOrEmpty()) {
                    result.error("INVALID_ARGS", "magnet and destination are required", null)
                } else {
                    val torrentId = startTorrent(magnet, destination)
                    if (torrentId == 0) {
                        result.error("FAILED", "could not start torrent", null)
                    } else {
                        result.success(torrentId)
                    }
                }
            }

            "pause" -> call.argument<Int>("id")?.let {
                pauseTorrent(it)
                result.success(null)
            }

            "resume" -> call.argument<Int>("id")?.let {
                resumeTorrent(it)
                result.success(null)
            }

            "cancel" -> call.argument<Int>("id")?.let {
                cancelTorrent(it)
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }
}
