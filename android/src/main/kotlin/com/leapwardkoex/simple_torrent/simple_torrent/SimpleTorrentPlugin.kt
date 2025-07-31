package com.leapwardkoex.simple_torrent.simple_torrent

import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.Keep
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.util.Collections

@Keep
class SimpleTorrentPlugin : FlutterPlugin,
    MethodChannel.MethodCallHandler {

    companion object {
        private val pluginInstances =
            Collections.synchronizedSet(mutableSetOf<SimpleTorrentPlugin>())
        private val mainHandler = Handler(Looper.getMainLooper())
        private const val TAG = "SimpleTorrentPlugin"
        private const val METHOD_TIMEOUT_MS = 10000L // 10 seconds

        // ── static bridge for native code ──────────────────────────────
        @Keep
        @JvmStatic
        fun sendStats(stats: Map<String, Any>) {
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
    
    // Coroutine scope for async operations
    private val coroutineScope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    // Buffer for stats and metadata when no listener is active
    private val statsBuffer = mutableListOf<Map<String, Any>>()
    private val metadataBuffer = mutableListOf<Map<String, Any>>()
    private val maxBufferSize = 10 // Keep only the latest 10 items

    // ── native interface ────────────────────────────────────────────────
    @Keep
    private external fun startTorrent(magnet: String, dest: String): Int

    @Keep
    private external fun startTorrentWithName(magnet: String, dest: String, name: String): Int

    @Keep
    private external fun pauseTorrent(id: Int)

    @Keep
    private external fun resumeTorrent(id: Int)

    @Keep
    private external fun cancelTorrent(id: Int)

    @Keep
    private external fun finaliseTorrent(id: Int)

    @Keep
    private external fun getActiveTorrentIds(): IntArray

    @Keep
    private external fun torrentExists(id: Int): Boolean

    @Keep
    private external fun getTorrentState(id: Int): String

    @Keep
    private external fun getTorrentInfo(id: Int): Map<String, Any>

    @Keep
    private external fun getLastError(id: Int): String

    @Keep
    private external fun applyConfig(config: Map<String, Any>)

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

        // Cancel all running coroutines
        coroutineScope.cancel()

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
    private fun handleStatsUpdate(stats: Map<String, Any>) {
        val sink = progressSink
        if (sink != null) {
            try {
                sink.success(stats)
                return
            } catch (exception: Exception) {
                Log.w(TAG, "Failed to send stats: ${exception.message}")
                progressSink = null // Clear invalid sink
            }
        }
        // Buffer the stats if send failed or no listener
        synchronized(statsBuffer) {
            statsBuffer.add(stats)
            while (statsBuffer.size > maxBufferSize) {
                statsBuffer.removeAt(0)
            }
        }
        Log.d(TAG, "Stats buffered, current buffer size: ${statsBuffer.size}")
    }

    private fun handleMetadataUpdate(metadata: Map<String, Any>) {
        val sink = metadataSink
        if (sink != null) {
            try {
                sink.success(metadata)
                return
            } catch (exception: Exception) {
                Log.w(TAG, "Failed to send metadata: ${exception.message}")
                metadataSink = null // Clear invalid sink
            }
        }
        // Buffer the metadata if send failed or no listener
        synchronized(metadataBuffer) {
            metadataBuffer.add(metadata)
            while (metadataBuffer.size > maxBufferSize) {
                metadataBuffer.removeAt(0)
            }
        }
        Log.d(TAG, "Metadata buffered, current buffer size: ${metadataBuffer.size}")
    }

    // ── MethodChannel handling ─────────────────────────────────────────
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> {
                coroutineScope.launch {
                    try {
                        val config = call.argument<Map<String, Any>>("config")
                        if (config != null) {
                            Log.d(TAG, "Init called with config: $config")
                            withContext(Dispatchers.IO) {
                                applyConfig(config)
                            }
                            Log.d(TAG, "Configuration applied successfully")
                        } else {
                            Log.d(TAG, "Init called without config - using defaults")
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to apply configuration: ${e.message}")
                        result.error("ERROR", "Failed to initialize: ${e.message}", null)
                    }
                }
            }

            "start" -> {
                val magnet = call.argument<String>("magnet")
                val destination = call.argument<String>("destination")
                val displayName = call.argument<String>("displayName")
                
                if (magnet.isNullOrEmpty() || destination.isNullOrEmpty()) {
                    result.error("INVALID_ARGS", "magnet and destination are required", null)
                    return
                }

                coroutineScope.launch {
                    try {
                        val torrentId = withTimeoutOrNull(METHOD_TIMEOUT_MS) {
                            withContext(Dispatchers.IO) {
                                if (displayName.isNullOrEmpty()) {
                                    startTorrent(magnet, destination)
                                } else {
                                    startTorrentWithName(magnet, destination, displayName)
                                }
                            }
                        }
                        
                        if (torrentId == null) {
                            result.error("TIMEOUT", "Torrent start operation timed out", null)
                        } else if (torrentId == 0) {
                            result.error("FAILED", "Could not start torrent", null)
                        } else {
                            result.success(torrentId)
                        }
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to start torrent: ${e.message}", null)
                    }
                }
            }

            "pause" -> {
                val id = call.argument<Int>("id")
                if (id == null) {
                    result.error("INVALID_ARGS", "id is required", null)
                    return
                }

                coroutineScope.launch {
                    try {
                        withContext(Dispatchers.IO) {
                            pauseTorrent(id)
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to pause torrent: ${e.message}", null)
                    }
                }
            }

            "resume" -> {
                val id = call.argument<Int>("id")
                if (id == null) {
                    result.error("INVALID_ARGS", "id is required", null)
                    return
                }

                coroutineScope.launch {
                    try {
                        withContext(Dispatchers.IO) {
                            resumeTorrent(id)
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to resume torrent: ${e.message}", null)
                    }
                }
            }

            "cancel" -> {
                val id = call.argument<Int>("id")
                if (id == null) {
                    result.error("INVALID_ARGS", "id is required", null)
                    return
                }

                coroutineScope.launch {
                    try {
                        withContext(Dispatchers.IO) {
                            cancelTorrent(id)
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to cancel torrent: ${e.message}", null)
                    }
                }
            }

            "finalise" -> {
                val id = call.argument<Int>("id")
                if (id == null) {
                    result.error("INVALID_ARGS", "id is required", null)
                    return
                }

                coroutineScope.launch {
                    try {
                        withContext(Dispatchers.IO) {
                            finaliseTorrent(id)
                        }
                        
                        // Send final completion stats message
                        val completionStats = mapOf(
                            "eventType" to "stats",
                            "id" to id,
                            "download_rate" to 0,
                            "upload_rate" to 0,
                            "pieces" to 0,
                            "pieces_total" to 0,
                            "progress" to 1.0f,
                            "seeds" to 0,
                            "peers" to 0,
                            "phase" to "completed",
                            "state" to "completed"
                        )
                        sendStats(completionStats)
                        
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to finalise torrent: ${e.message}", null)
                    }
                }
            }

            "getActiveTorrentIds" -> {
                coroutineScope.launch {
                    try {
                        val ids = withContext(Dispatchers.IO) {
                            getActiveTorrentIds().toList()
                        }
                        result.success(ids)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to get active torrents: ${e.message}", null)
                    }
                }
            }

            "exists" -> {
                val id = call.argument<Int>("id")
                if (id == null) {
                    result.error("INVALID_ARGS", "id is required", null)
                    return
                }

                coroutineScope.launch {
                    try {
                        val exists = withContext(Dispatchers.IO) {
                            torrentExists(id)
                        }
                        result.success(exists)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to check torrent existence: ${e.message}", null)
                    }
                }
            }

            "getState" -> {
                val id = call.argument<Int>("id")
                if (id == null) {
                    result.error("INVALID_ARGS", "id is required", null)
                    return
                }

                coroutineScope.launch {
                    try {
                        val state = withContext(Dispatchers.IO) {
                            getTorrentState(id)
                        }
                        result.success(state)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to get torrent state: ${e.message}", null)
                    }
                }
            }

            "getTorrentInfo" -> {
                val id = call.argument<Int>("id")
                if (id == null) {
                    result.error("INVALID_ARGS", "id is required", null)
                    return
                }

                coroutineScope.launch {
                    try {
                        val info = withContext(Dispatchers.IO) {
                            getTorrentInfo(id)
                        }
                        result.success(info)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to get torrent info: ${e.message}", null)
                    }
                }
            }

            "getLastError" -> {
                val id = call.argument<Int>("id")
                if (id == null) {
                    result.error("INVALID_ARGS", "id is required", null)
                    return
                }

                coroutineScope.launch {
                    try {
                        val error = withContext(Dispatchers.IO) {
                            getLastError(id)
                        }
                        result.success(error)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to get error: ${e.message}", null)
                    }
                }
            }

            else -> result.notImplemented()
        }
    }
}
