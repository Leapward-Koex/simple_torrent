package com.leapwardkoex.simple_torrent.simple_torrent

import android.os.Handler
import android.os.Looper
import bt.Bt
import bt.data.file.FileSystemStorage
import bt.runtime.BtClient
import bt.torrent.TorrentSessionState
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.file.Paths
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentLinkedQueue

/**
 * Multi‑torrent plugin with a download queue.
 * Dart → Kotlin methods:
 *   init(concurrency)
 *   start(magnet, path)   – returns id (queued or running)
 *   pause(id)
 *   resume(id)
 *   cancel(id)
 * Emits progress maps on EventChannel "simple_torrent/progress":
 *   { id, downloaded, uploaded, left, piecesTotal, piecesComplete, piecesRemaining, progress }
 */
class SimpleTorrentPlugin : FlutterPlugin,
  MethodChannel.MethodCallHandler,
  EventChannel.StreamHandler {

  /* ────────────────────────── Android ⇄ Flutter plumbing ───────────────── */
  private lateinit var methods: MethodChannel
  private lateinit var progressChannel: EventChannel
  private val ui = Handler(Looper.getMainLooper())
  private var sink: EventChannel.EventSink? = null

  /* ───────────────────────────── torrent bookkeeping ───────────────────── */
  private val active   = ConcurrentHashMap<String, TorrentWrapper>()   // currently downloading/seeding
  private val pendingQ = ConcurrentLinkedQueue<TorrentRequest>()       // queued requests
  private var nextId = 1
  private var maxConcurrent = 2

  /* ───────────────────────── FlutterPlugin overrides ───────────────────── */
  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    methods = MethodChannel(binding.binaryMessenger, "simple_torrent/methods")
    progressChannel = EventChannel(binding.binaryMessenger, "simple_torrent/progress")
    methods.setMethodCallHandler(this)
    progressChannel.setStreamHandler(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    active.values.forEach { it.stop() }
    active.clear()
    pendingQ.clear()
    methods.setMethodCallHandler(null)
    progressChannel.setStreamHandler(null)
  }

  /* ─────────────────────────── MethodChannel handling ───────────────────── */
  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "init"   -> { maxConcurrent = call.argument<Int>("concurrency") ?: 2; result.success(null) }
      "start"  -> handleStart(call, result)
      "pause", "resume", "cancel" -> handleControl(call, result)
      else     -> result.notImplemented()
    }
  }

  private fun handleStart(call: MethodCall, result: MethodChannel.Result) {
    val magnet = call.argument<String>("magnet")
    val path   = call.argument<String>("path") ?: "/storage/emulated/0/Download"
    if (magnet.isNullOrEmpty()) { result.error("ARG", "Missing magnet URI", null); return }

    val id = "t${nextId++}"
    val request = TorrentRequest(id, magnet, path)

    if (active.size < maxConcurrent) {
      startRequest(request)
    } else {
      pendingQ.add(request)
    }
    result.success(id) // always succeed; may be queued
  }

  private fun handleControl(call: MethodCall, result: MethodChannel.Result) {
    val id = call.argument<String>("id")
    val wrapper = active[id]
    when (call.method) {
      "pause" -> wrapper?.pause()
      "resume" -> wrapper?.resume()
      "cancel" -> {
        wrapper?.stop()
        active.remove(id)
        pendingQ.removeIf { it.id == id }
        startNextIfPossible()
      }
    }
    result.success(null)
  }

  /* ───────────────────────────── queue helpers ──────────────────────────── */
  private fun startRequest(req: TorrentRequest) {
    val wrapper = TorrentWrapper(req.id, req.magnet, req.path,
      push = { map -> ui.post { sink?.success(map) } },
      finished = { finishedId ->
        active.remove(finishedId)
        startNextIfPossible()
      })
    active[req.id] = wrapper
  }

  private fun startNextIfPossible() {
    while (active.size < maxConcurrent) {
      val next = pendingQ.poll() ?: return
      startRequest(next)
    }
  }

  /* ─────────────────────────── EventChannel plumbing ────────────────────── */
  override fun onListen(args: Any?, events: EventChannel.EventSink) { sink = events }
  override fun onCancel(args: Any?) { sink = null }

  /* ───────────────────────────── data classes ───────────────────────────── */
  private data class TorrentRequest(val id: String, val magnet: String, val path: String)

  /* ───────────────────────────── wrapper class ──────────────────────────── */
  private class TorrentWrapper(
    private val id: String,
    magnet: String,
    downloadDir: String,
    private val push: (Map<String, Any>) -> Unit,
    private val finished: (String) -> Unit
  ) {
    private val client: BtClient
    private var isPaused = false

    private val stateCallback: (TorrentSessionState) -> Unit = { s ->
      val downloaded = s.downloaded
      val uploaded   = s.uploaded
      val left       = s.left.takeIf { it != TorrentSessionState.UNKNOWN } ?: 0L
      val piecesTot  = s.piecesTotal
      val piecesComp = s.piecesComplete
      val piecesRem  = s.piecesRemaining
      val progress   = if (piecesTot > 0) piecesComp * 100.0 / piecesTot else 0.0

      push(
        mapOf(
          "id" to id,
          "downloaded" to downloaded,
          "uploaded" to uploaded,
          "left" to left,
          "piecesTotal" to piecesTot,
          "piecesComplete" to piecesComp,
          "piecesRemaining" to piecesRem,
          "progress" to progress
        )
      )

      // Detect completion (all pieces downloaded)
      if (piecesRem == 0 && !isPaused) {
        finished(id)
      }
    }

    init {
      val storage = FileSystemStorage(Paths.get(downloadDir))
      client = Bt.client()
        .storage(storage)
        .magnet(magnet)
        .autoLoadModules()
        .build()
      client.startAsync(stateCallback, 1000L)
    }

    fun pause() { isPaused = true; client.stop() }
    fun resume() { if (isPaused) { isPaused = false; client.startAsync(stateCallback, 1000L) } }
    fun stop() { client.stop(); isPaused = true }
  }
}
