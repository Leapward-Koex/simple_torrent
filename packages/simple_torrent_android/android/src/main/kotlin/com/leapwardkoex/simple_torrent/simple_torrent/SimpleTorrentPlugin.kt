package com.leapwardkoex.simple_torrent.simple_torrent

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.system.Os
import android.util.Base64
import androidx.annotation.Keep
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.security.KeyStore
import java.security.cert.X509Certificate
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

/** Serialises blocking finalise calls and manager destruction off the UI thread. */
internal class NativeFinaliseWorker(
    private val postToPlatformThread: (() -> Unit) -> Unit,
    private val executor: ExecutorService = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "simple-torrent-finalise").apply { isDaemon = true }
    },
) {
    companion object {
        private const val NATIVE_ERROR = 6
    }

    private val lock = Any()
    private var closed = false

    fun submit(
        operation: () -> Int,
        completion: (Int) -> Unit,
    ): Boolean = synchronized(lock) {
        if (closed) return@synchronized false
        try {
            executor.execute {
                val code = try {
                    operation()
                } catch (_: Throwable) {
                    NATIVE_ERROR
                }
                postToPlatformThread { completion(code) }
            }
            true
        } catch (_: RejectedExecutionException) {
            false
        }
    }

    /** Queues destruction after every accepted finalise call, then rejects new work. */
    fun close(destroy: () -> Unit) = synchronized(lock) {
        if (closed) return@synchronized
        closed = true
        executor.execute {
            try {
                destroy()
            } catch (_: Throwable) {
                // Destruction is a C ABI exception barrier and has no Dart result.
            }
        }
        executor.shutdown()
    }
}

/** Android adapter for the bundled simple_torrent C ABI runtime. */
class SimpleTorrentPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    companion object {
        private const val METHODS_CHANNEL = "simple_torrent/methods"
        private const val PROGRESS_CHANNEL = "simple_torrent/progress"
        private const val METADATA_CHANNEL = "simple_torrent/metadata"
        private const val MAX_BUFFERED_EVENTS = 10

        private var nativeLoaded = false

        @Synchronized
        private fun ensureNativeLoaded() {
            if (!nativeLoaded) {
                System.loadLibrary("simple_torrent_native")
                nativeLoaded = true
            }
        }

        @Synchronized
        private fun exportAndroidTrustStore(context: Context): File {
            val output = File(context.noBackupFilesDir, "simple_torrent_android_ca.pem")
            val temporary = File(context.noBackupFilesDir, "${output.name}.tmp")
            val store = KeyStore.getInstance("AndroidCAStore").apply { load(null) }
            val aliases = store.aliases().asSequence().toList().sorted()

            FileOutputStream(temporary, false).bufferedWriter(Charsets.US_ASCII).use { writer ->
                for (alias in aliases) {
                    val certificate = store.getCertificate(alias) as? X509Certificate ?: continue
                    writer.appendLine("-----BEGIN CERTIFICATE-----")
                    val encoded = Base64.encodeToString(certificate.encoded, Base64.NO_WRAP)
                    encoded.chunked(64).forEach(writer::appendLine)
                    writer.appendLine("-----END CERTIFICATE-----")
                }
                writer.flush()
            }
            FileOutputStream(temporary, true).use { it.fd.sync() }
            check(temporary.length() > 0L) { "AndroidCAStore contained no X.509 certificates" }
            // rename(2) atomically replaces an older bundle on the same private filesystem.
            Os.rename(temporary.absolutePath, output.absolutePath)
            return output
        }
    }

    private lateinit var mainHandler: Handler
    private val statsBuffer = ArrayDeque<Map<String, Any>>()
    private val metadataBuffer = LinkedHashMap<Int, Map<String, Any>>()
    private lateinit var methodChannel: MethodChannel
    private lateinit var progressChannel: EventChannel
    private lateinit var metadataChannel: EventChannel
    private var progressSink: EventChannel.EventSink? = null
    private var metadataSink: EventChannel.EventSink? = null
    private var nativeHandle: Long = 0
    private var initializationError: String? = null
    private var finaliseWorker: NativeFinaliseWorker? = null

    @Volatile
    private var attached = false

    @Keep private external fun nativeCreate(
        config: Map<String, Any>?,
        caBundlePath: String,
    ): Long
    @Keep private external fun nativeDestroy(handle: Long)
    @Keep private external fun nativeUpdateConfig(handle: Long, config: Map<String, Any>): Int
    @Keep private external fun nativeSetTransfersSuspended(handle: Long, suspended: Boolean): Int
    @Keep private external fun nativeTransfersSuspended(handle: Long): Map<String, Any>?
    @Keep private external fun nativeStart(
        handle: Long,
        magnet: String,
        destination: String,
        displayName: String?,
    ): IntArray
    @Keep private external fun nativeStartFromData(
        handle: Long,
        data: ByteArray,
        destination: String,
        displayName: String?,
    ): IntArray
    @Keep private external fun nativeStartFromFile(
        handle: Long,
        torrentFilePath: String,
        destination: String,
        displayName: String?,
    ): IntArray
    @Keep private external fun nativePause(handle: Long, id: Int): Int
    @Keep private external fun nativeResume(handle: Long, id: Int): Int
    @Keep private external fun nativeCancel(handle: Long, id: Int): Int
    @Keep private external fun nativeFinalise(handle: Long, id: Int): Int
    @Keep private external fun nativeActiveIds(handle: Long): Map<String, Any>?
    @Keep private external fun nativeExists(handle: Long, id: Int): Map<String, Any>?
    @Keep private external fun nativeState(handle: Long, id: Int): Map<String, Any>?
    @Keep private external fun nativeTorrentInfo(handle: Long, id: Int): Map<String, Any>?
    @Keep private external fun nativeLastError(handle: Long, id: Int): Map<String, Any>?

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        mainHandler = Handler(Looper.getMainLooper())
        finaliseWorker = NativeFinaliseWorker(
            postToPlatformThread = { callback -> mainHandler.post(callback) },
        )
        methodChannel = MethodChannel(binding.binaryMessenger, METHODS_CHANNEL)
        progressChannel = EventChannel(binding.binaryMessenger, PROGRESS_CHANNEL)
        metadataChannel = EventChannel(binding.binaryMessenger, METADATA_CHANNEL)
        methodChannel.setMethodCallHandler(this)
        progressChannel.setStreamHandler(streamHandler(statsBuffer) { progressSink = it })
        metadataChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                metadataSink = events
                metadataBuffer.values.forEach(events::success)
                metadataBuffer.clear()
            }

            override fun onCancel(arguments: Any?) {
                metadataSink = null
            }
        })

        attached = true
        try {
            ensureNativeLoaded()
            val caBundle = exportAndroidTrustStore(binding.applicationContext)
            nativeHandle = nativeCreate(null, caBundle.absolutePath)
            if (nativeHandle == 0L) {
                initializationError = "Failed to create the simple_torrent native manager"
            }
        } catch (error: Throwable) {
            nativeHandle = 0
            initializationError = error.message ?: error.javaClass.simpleName
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        attached = false
        methodChannel.setMethodCallHandler(null)
        progressChannel.setStreamHandler(null)
        metadataChannel.setStreamHandler(null)
        progressSink = null
        metadataSink = null
        statsBuffer.clear()
        metadataBuffer.clear()
        initializationError = null
        val handle = nativeHandle
        nativeHandle = 0
        finaliseWorker?.close {
            if (handle != 0L) nativeDestroy(handle)
        }
        finaliseWorker = null
    }

    private fun streamHandler(
        buffer: ArrayDeque<Map<String, Any>>,
        setSink: (EventChannel.EventSink?) -> Unit,
    ) = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            setSink(events)
            while (buffer.isNotEmpty()) events.success(buffer.removeFirst())
        }

        override fun onCancel(arguments: Any?) = setSink(null)
    }

    /** Called on the native worker; EventSink is touched only on Android's main thread. */
    @Keep
    private fun dispatchStatsFromNative(stats: Map<String, Any>) {
        val owned = HashMap(stats)
        mainHandler.post { if (attached) emit(owned, progressSink, statsBuffer) }
    }

    /** Called on the native worker; EventSink is touched only on Android's main thread. */
    @Keep
    private fun dispatchMetadataFromNative(metadata: Map<String, Any>) {
        val owned = HashMap(metadata)
        mainHandler.post { if (attached) emitMetadata(owned) }
    }

    private fun emit(
        event: Map<String, Any>,
        sink: EventChannel.EventSink?,
        buffer: ArrayDeque<Map<String, Any>>,
    ) {
        if (sink != null) {
            sink.success(event)
            return
        }
        buffer.addLast(event)
        while (buffer.size > MAX_BUFFERED_EVENTS) buffer.removeFirst()
    }

    private fun emitMetadata(event: Map<String, Any>) {
        val sink = metadataSink
        if (sink != null) {
            sink.success(event)
            return
        }
        val id = (event["id"] as? Number)?.toInt() ?: return
        metadataBuffer[id] = event
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (nativeHandle == 0L) {
            result.error(
                "not_initialized",
                initializationError ?: "Native manager is not available",
                null,
            )
            return
        }
        when (call.method) {
            "init" -> {
                val config = readConfig(call, result, allowMissing = true) ?: return
                if (config.isEmpty()) result.success(null)
                else complete(nativeUpdateConfig(nativeHandle, config), result, "invalid_config")
            }
            "updateConfig" -> {
                val config = readConfig(call, result, allowMissing = false) ?: return
                complete(nativeUpdateConfig(nativeHandle, config), result, "invalid_config")
            }
            "setTransfersSuspended" -> withSuspendedArgument(call, result) { suspended ->
                complete(nativeSetTransfersSuspended(nativeHandle, suspended), result)
            }
            "areTransfersSuspended" -> completeNativeQuery(
                nativeTransfersSuspended(nativeHandle),
                result,
                Boolean::class.javaObjectType,
            )
            "start" -> start(call, result)
            "startFromData" -> startFromData(call, result)
            "startFromFile" -> startFromFile(call, result)
            "pause" -> lifecycle(call, result, ::nativePause)
            "resume" -> lifecycle(call, result, ::nativeResume)
            "cancel" -> lifecycle(call, result, ::nativeCancel)
            "finalise" -> finalise(call, result)
            "getActiveTorrentIds" -> completeNativeQuery(
                nativeActiveIds(nativeHandle),
                result,
                IntArray::class.java,
            ) { (it as IntArray).toList() }
            "exists" -> withId(call, result) { id ->
                completeNativeQuery(
                    nativeExists(nativeHandle, id),
                    result,
                    Boolean::class.javaObjectType,
                )
            }
            "getState" -> withId(call, result) { id ->
                completeNativeQuery(
                    nativeState(nativeHandle, id),
                    result,
                    String::class.java,
                )
            }
            "getTorrentInfo" -> withId(call, result) { id ->
                completeNativeQuery(
                    nativeTorrentInfo(nativeHandle, id),
                    result,
                    Map::class.java,
                )
            }
            "getLastError" -> withId(call, result) { id ->
                completeNativeQuery(
                    nativeLastError(nativeHandle, id),
                    result,
                    String::class.java,
                )
            }
            else -> result.notImplemented()
        }
    }

    private fun start(call: MethodCall, result: MethodChannel.Result) {
        val magnet = rawArgument(call, "magnet") as? String
        val destination = rawArgument(call, "destination") as? String
        val rawDisplayName = rawArgument(call, "displayName")
        val displayName = rawDisplayName as? String
        if (magnet.isNullOrBlank() || destination.isNullOrBlank()) {
            invalid(result, "magnet and destination are required")
            return
        }
        if (rawDisplayName != null && displayName == null) {
            invalid(result, "displayName must be a string")
            return
        }
        completeStart(
            nativeStart(nativeHandle, magnet, destination, displayName),
            result,
            "invalid_magnet",
        )
    }

    private fun startFromData(call: MethodCall, result: MethodChannel.Result) {
        val data = rawArgument(call, "data") as? ByteArray
        val destination = rawArgument(call, "destination") as? String
        val rawDisplayName = rawArgument(call, "displayName")
        val displayName = rawDisplayName as? String
        if (data == null || data.isEmpty() || destination.isNullOrBlank()) {
            invalid(result, "data and destination are required")
            return
        }
        if (rawDisplayName != null && displayName == null) {
            invalid(result, "displayName must be a string")
            return
        }
        completeStart(
            nativeStartFromData(nativeHandle, data, destination, displayName),
            result,
            "invalid_torrent_data",
        )
    }

    private fun startFromFile(call: MethodCall, result: MethodChannel.Result) {
        val torrentFilePath = rawArgument(call, "torrentFilePath") as? String
        val destination = rawArgument(call, "destination") as? String
        val rawDisplayName = rawArgument(call, "displayName")
        val displayName = rawDisplayName as? String
        if (torrentFilePath.isNullOrBlank() || destination.isNullOrBlank()) {
            invalid(result, "torrentFilePath and destination are required")
            return
        }
        if (rawDisplayName != null && displayName == null) {
            invalid(result, "displayName must be a string")
            return
        }
        completeStart(
            nativeStartFromFile(
                nativeHandle,
                torrentFilePath,
                destination,
                displayName,
            ),
            result,
            "invalid_torrent_file",
        )
    }

    private fun lifecycle(
        call: MethodCall,
        result: MethodChannel.Result,
        operation: (Long, Int) -> Int,
    ) = withId(call, result) { id -> complete(operation(nativeHandle, id), result) }

    private fun finalise(call: MethodCall, result: MethodChannel.Result) =
        withId(call, result) { id ->
            val handle = nativeHandle
            val worker = finaliseWorker
            if (handle == 0L || worker == null || !worker.submit(
                    operation = { nativeFinalise(handle, id) },
                    completion = { code -> complete(code, result) },
                )
            ) {
                result.error(
                    "not_initialized",
                    "Native manager is not available",
                    null,
                )
            }
        }

    internal fun withSuspendedArgument(
        call: MethodCall,
        result: MethodChannel.Result,
        action: (Boolean) -> Unit,
    ) {
        val arguments = call.arguments as? Map<*, *>
        val suspended = arguments?.get("suspended")
        if (arguments?.containsKey("suspended") != true || suspended !is Boolean) {
            invalid(result, "suspended must be a boolean")
            return
        }
        action(suspended)
    }

    private fun withId(
        call: MethodCall,
        result: MethodChannel.Result,
        action: (Int) -> Unit,
    ) {
        val rawId = rawArgument(call, "id")
        val id = when (rawId) {
            is Int -> rawId
            is Long -> rawId.takeIf { it in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong() }?.toInt()
            else -> null
        }
        if (id == null || id <= 0) invalid(result, "id must be a positive integer")
        else action(id)
    }

    private fun rawArgument(call: MethodCall, key: String): Any? =
        (call.arguments as? Map<*, *>)?.get(key)

    private fun readConfig(
        call: MethodCall,
        result: MethodChannel.Result,
        allowMissing: Boolean,
    ): Map<String, Any>? {
        val rawArguments = call.arguments
        if (rawArguments != null && rawArguments !is Map<*, *>) {
            result.error("invalid_config", "arguments must be a map", null)
            return null
        }
        val arguments = rawArguments
        val hasConfig = arguments?.containsKey("config") == true
        val rawConfig = arguments?.get("config")
        if (!hasConfig || rawConfig == null) {
            if (allowMissing) return emptyMap()
            result.error("invalid_config", "config is required", null)
            return null
        }
        if (rawConfig !is Map<*, *>) {
            result.error("invalid_config", "config must be a map", null)
            return null
        }
        val config = LinkedHashMap<String, Any>(rawConfig.size)
        for ((key, value) in rawConfig) {
            if (key !is String || value == null) {
                result.error("invalid_config", "config keys and values must be non-null", null)
                return null
            }
            config[key] = value
        }
        return config
    }

    private fun completeStart(
        nativeResult: IntArray,
        result: MethodChannel.Result,
        invalidTorrentCode: String,
    ) {
        if (nativeResult.size != 2) {
            result.error("native_error", "Invalid response from native runtime", null)
        } else if (nativeResult[0] == 0) {
            result.success(nativeResult[1])
        } else {
            complete(nativeResult[0], result, invalidTorrentCode)
        }
    }

    internal fun completeNativeQuery(
        nativeResult: Map<String, Any>?,
        result: MethodChannel.Result,
        expectedValueType: Class<*>,
        transform: (Any) -> Any? = { it },
    ) {
        val code = nativeResult?.get("code") as? Int
        if (code == null) {
            result.error("native_error", "Invalid query response from native runtime", null)
            return
        }
        if (code != 0) {
            complete(code, result)
            return
        }
        val value = nativeResult["value"]
        if (value == null || !expectedValueType.isInstance(value)) {
            result.error("native_error", "Invalid query value from native runtime", null)
            return
        }
        result.success(transform(value))
    }

    private fun complete(
        code: Int,
        result: MethodChannel.Result,
        invalidCode: String = "invalid_argument",
    ) {
        if (code == 0) result.success(null)
        else {
            val name = codeName(code, invalidCode)
            result.error(name, "Native operation failed: $name", null)
        }
    }

    private fun invalid(result: MethodChannel.Result, message: String) {
        result.error("invalid_argument", message, null)
    }

    private fun codeName(code: Int, invalidCode: String) = when (code) {
        1 -> invalidCode
        2 -> "torrent_not_found"
        3 -> "torrent_limit_reached"
        4 -> invalidCode
        5 -> "io_error"
        7 -> "duplicate_torrent"
        else -> "native_error"
    }
}
