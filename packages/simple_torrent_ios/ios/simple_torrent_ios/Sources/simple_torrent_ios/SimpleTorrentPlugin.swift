import Flutter
import CoreFoundation
import Darwin
import Foundation

private let nativeCreationLock = NSLock()
private let embeddedCABundleName = "mozilla-ca-2026-08-13.pem"
private let maxBufferedEvents = 10

private struct NativeConfig {
    var structSize: Int
    var maxTorrents: Int32
    var downloadRateLimit: Int64
    var uploadRateLimit: Int64
    var connectionsLimit: Int32
    var enableDht: UInt8
    var userAgent: UnsafePointer<CChar>?
}

private struct NativeStats {
    var id: Int32
    var downloadRate: Int64
    var uploadRate: Int64
    var pieces: Int32
    var piecesTotal: Int32
    var progress: Double
    var seeds: Int32
    var peers: Int32
    var state: Int32
}

private struct NativeFile {
    var index: Int32
    var path: UnsafePointer<CChar>?
    var size: Int64
    var offset: Int64
}

private struct NativeMetadata {
    var id: Int32
    var name: UnsafePointer<CChar>?
    var totalBytes: Int64
    var pieceSize: Int32
    var pieceCount: Int32
    var fileCount: Int32
    var creationDate: Int64
    var isPrivate: UInt8
    var isV2: UInt8
    var v1InfoHash: UnsafePointer<CChar>?
    var v2InfoHash: UnsafePointer<CChar>?
    var files: UnsafePointer<NativeFile>?
    var filesCount: Int
}

private struct NativeTorrentInfo {
    var id: Int32
    var magnetUri: UnsafeMutablePointer<CChar>?
    var savePath: UnsafeMutablePointer<CChar>?
    var displayName: UnsafeMutablePointer<CChar>?
    var state: Int32
    var lastError: UnsafeMutablePointer<CChar>?
    var createdAtMilliseconds: Int64
}

private typealias StatsCallback = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeRawPointer?
) -> Void
private typealias MetadataCallback = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeRawPointer?
) -> Void

private final class CallbackContext {
    weak var plugin: SimpleTorrentPlugin?

    init(plugin: SimpleTorrentPlugin) {
        self.plugin = plugin
    }
}

@_silgen_name("simple_torrent_native_abi_version")
private func nativeAbiVersion() -> UInt32

@_silgen_name("simple_torrent_embedded_ca_bundle")
private func nativeEmbeddedCABundle(
    _ sizeOut: UnsafeMutablePointer<Int>?
) -> UnsafePointer<UInt8>?

@_silgen_name("simple_torrent_manager_create")
private func nativeCreate(
    _ config: UnsafePointer<NativeConfig>?,
    _ statsCallback: StatsCallback?,
    _ metadataCallback: MetadataCallback?,
    _ userData: UnsafeMutableRawPointer?,
    _ managerOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) -> Int32

@_silgen_name("simple_torrent_manager_destroy")
private func nativeDestroy(_ manager: UnsafeMutableRawPointer?)

@_silgen_name("simple_torrent_manager_update_config")
private func nativeUpdateConfig(
    _ manager: UnsafeMutableRawPointer?, _ config: UnsafePointer<NativeConfig>?
) -> Int32

@_silgen_name("simple_torrent_manager_set_transfers_suspended")
private func nativeSetTransfersSuspended(
    _ manager: UnsafeMutableRawPointer?, _ suspended: UInt8
) -> Int32

@_silgen_name("simple_torrent_manager_transfers_suspended")
private func nativeTransfersSuspended(
    _ manager: UnsafeMutableRawPointer?, _ suspendedOut: UnsafeMutablePointer<UInt8>?
) -> Int32

@_silgen_name("simple_torrent_manager_start")
private func nativeStart(
    _ manager: UnsafeMutableRawPointer?, _ magnet: UnsafePointer<CChar>?,
    _ destination: UnsafePointer<CChar>?, _ displayName: UnsafePointer<CChar>?,
    _ torrentIdOut: UnsafeMutablePointer<Int32>?
) -> Int32

@_silgen_name("simple_torrent_manager_start_from_data")
private func nativeStartFromData(
    _ manager: UnsafeMutableRawPointer?, _ data: UnsafePointer<UInt8>?,
    _ dataSize: Int, _ destination: UnsafePointer<CChar>?,
    _ displayName: UnsafePointer<CChar>?, _ torrentIdOut: UnsafeMutablePointer<Int32>?
) -> Int32

@_silgen_name("simple_torrent_manager_start_from_file")
private func nativeStartFromFile(
    _ manager: UnsafeMutableRawPointer?, _ torrentFilePath: UnsafePointer<CChar>?,
    _ destination: UnsafePointer<CChar>?, _ displayName: UnsafePointer<CChar>?,
    _ torrentIdOut: UnsafeMutablePointer<Int32>?
) -> Int32

@_silgen_name("simple_torrent_manager_pause")
private func nativePause(_ manager: UnsafeMutableRawPointer?, _ id: Int32) -> Int32
@_silgen_name("simple_torrent_manager_resume")
private func nativeResume(_ manager: UnsafeMutableRawPointer?, _ id: Int32) -> Int32
@_silgen_name("simple_torrent_manager_cancel")
private func nativeCancel(_ manager: UnsafeMutableRawPointer?, _ id: Int32) -> Int32
@_silgen_name("simple_torrent_manager_finalise")
private func nativeFinalise(_ manager: UnsafeMutableRawPointer?, _ id: Int32) -> Int32

@_silgen_name("simple_torrent_manager_active_ids")
private func nativeActiveIds(
    _ manager: UnsafeMutableRawPointer?, _ idsOut: UnsafeMutablePointer<UnsafeMutablePointer<Int32>?>?,
    _ countOut: UnsafeMutablePointer<Int>?
) -> Int32
@_silgen_name("simple_torrent_active_ids_free")
private func nativeActiveIdsFree(_ ids: UnsafeMutablePointer<Int32>?)

@_silgen_name("simple_torrent_manager_exists")
private func nativeExists(
    _ manager: UnsafeMutableRawPointer?, _ id: Int32,
    _ existsOut: UnsafeMutablePointer<UInt8>?
) -> Int32
@_silgen_name("simple_torrent_manager_state")
private func nativeState(
    _ manager: UnsafeMutableRawPointer?, _ id: Int32,
    _ stateOut: UnsafeMutablePointer<Int32>?
) -> Int32
@_silgen_name("simple_torrent_manager_torrent_info")
private func nativeTorrentInfo(
    _ manager: UnsafeMutableRawPointer?, _ id: Int32,
    _ infoOut: UnsafeMutablePointer<NativeTorrentInfo>?
) -> Int32
@_silgen_name("simple_torrent_torrent_info_free")
private func nativeTorrentInfoFree(_ info: UnsafeMutablePointer<NativeTorrentInfo>?)
@_silgen_name("simple_torrent_manager_last_error")
private func nativeLastError(
    _ manager: UnsafeMutableRawPointer?, _ id: Int32,
    _ errorOut: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> Int32
@_silgen_name("simple_torrent_string_free")
private func nativeStringFree(_ value: UnsafeMutablePointer<CChar>?)
@_silgen_name("simple_torrent_state_name")
private func nativeStateName(_ state: Int32) -> UnsafePointer<CChar>?
@_silgen_name("simple_torrent_result_name")
private func nativeResultName(_ result: Int32) -> UnsafePointer<CChar>?

private let statsCallback: StatsCallback = { userData, statsPointer in
    guard let userData, let statsPointer else { return }
    let context = Unmanaged<CallbackContext>.fromOpaque(userData).takeUnretainedValue()
    guard let plugin = context.plugin else { return }
    let stats = statsPointer.assumingMemoryBound(to: NativeStats.self).pointee
    let event: [String: Any] = [
        "eventType": "stats",
        "id": Int(stats.id),
        "download_rate": stats.downloadRate,
        "upload_rate": stats.uploadRate,
        "pieces": Int(stats.pieces),
        "pieces_total": Int(stats.piecesTotal),
        "progress": stats.progress,
        "seeds": Int(stats.seeds),
        "peers": Int(stats.peers),
        "state": stateName(stats.state),
    ]
    DispatchQueue.main.async { [weak plugin] in plugin?.emitProgress(event) }
}

private let metadataCallback: MetadataCallback = { userData, metadataPointer in
    guard let userData, let metadataPointer else { return }
    let context = Unmanaged<CallbackContext>.fromOpaque(userData).takeUnretainedValue()
    guard let plugin = context.plugin else { return }
    let metadata = metadataPointer.assumingMemoryBound(to: NativeMetadata.self).pointee
    var files: [[String: Any]] = []
    if let nativeFiles = metadata.files {
        files.reserveCapacity(metadata.filesCount)
        for index in 0..<metadata.filesCount {
            let file = nativeFiles[index]
            files.append([
                "index": Int(file.index),
                "path": string(file.path),
                "size": file.size,
                "offset": file.offset,
            ])
        }
    }
    let event: [String: Any] = [
        "eventType": "metadata",
        "id": Int(metadata.id),
        "name": string(metadata.name),
        "total_bytes": metadata.totalBytes,
        "piece_size": Int(metadata.pieceSize),
        "piece_count": Int(metadata.pieceCount),
        "file_count": Int(metadata.fileCount),
        "creation_date": metadata.creationDate,
        "private": metadata.isPrivate != 0,
        "v2": metadata.isV2 != 0,
        "v1_info_hash": string(metadata.v1InfoHash),
        "v2_info_hash": string(metadata.v2InfoHash),
        "files": files,
    ]
    DispatchQueue.main.async { [weak plugin] in plugin?.emitMetadata(event) }
}

private func installEmbeddedCABundle() throws {
    var byteCount = 0
    guard let bytes = nativeEmbeddedCABundle(&byteCount), byteCount > 0 else {
        throw NSError(
            domain: "simple_torrent", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Native Mozilla CA bundle is missing"]
        )
    }

    let fileManager = FileManager.default
    let support = try fileManager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )
    let directory = support.appendingPathComponent("simple_torrent", isDirectory: true)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let destination = directory.appendingPathComponent(embeddedCABundleName)
    let embedded = Data(bytes: bytes, count: byteCount)
    if (try? Data(contentsOf: destination)) != embedded {
        try embedded.write(to: destination, options: .atomic)
    }
    guard setenv("SSL_CERT_FILE", destination.path, 1) == 0 else {
        throw NSError(
            domain: NSPOSIXErrorDomain, code: Int(errno),
            userInfo: [NSLocalizedDescriptionKey: "Could not configure the native CA bundle"]
        )
    }
}

public final class SimpleTorrentPlugin: NSObject, FlutterPlugin {
    fileprivate var progressSink: FlutterEventSink?
    fileprivate var metadataSink: FlutterEventSink?
    private var progressBuffer: [[String: Any]] = []
    private var metadataBuffer: [Int: [String: Any]] = [:]
    private var manager: UnsafeMutableRawPointer?
    private var callbackContext: Unmanaged<CallbackContext>?
    private var initializationError: String?
    private let finaliseQueue = DispatchQueue(
        label: "com.leapwardkoex.simple-torrent.finalise",
        qos: .userInitiated
    )

    public override init() {
        super.init()
        if let layoutFailure = nativeLayoutFailure() {
            initializationError = layoutFailure
            return
        }

        nativeCreationLock.lock()
        defer { nativeCreationLock.unlock() }
        do {
            try installEmbeddedCABundle()
        } catch {
            initializationError = "Native CA bundle setup failed: \(error.localizedDescription)"
            return
        }

        let context = Unmanaged.passRetained(CallbackContext(plugin: self))
        callbackContext = context
        var created: UnsafeMutableRawPointer?
        let code = withConfig(nil) { config in
            nativeCreate(config, statsCallback, metadataCallback, context.toOpaque(), &created)
        }
        if code == 0, let created {
            manager = created
        } else {
            context.takeUnretainedValue().plugin = nil
            nativeDestroy(created)
            context.release()
            callbackContext = nil
            initializationError = code == 0
                ? "Native manager creation returned a null manager"
                : "Native manager creation failed: \(string(nativeResultName(code)))"
        }
    }

    deinit {
        callbackContext?.takeUnretainedValue().plugin = nil
        let managerToDestroy = manager
        let contextToRelease = callbackContext
        manager = nil
        callbackContext = nil
        // FIFO queue ownership keeps both native values alive until every
        // accepted finalise call has returned, without blocking this thread.
        finaliseQueue.async {
            nativeDestroy(managerToDestroy)
            contextToRelease?.release()
        }
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let plugin = SimpleTorrentPlugin()
        let methods = FlutterMethodChannel(
            name: "simple_torrent/methods", binaryMessenger: registrar.messenger()
        )
        let progress = FlutterEventChannel(
            name: "simple_torrent/progress", binaryMessenger: registrar.messenger()
        )
        let metadata = FlutterEventChannel(
            name: "simple_torrent/metadata", binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(plugin, channel: methods)
        progress.setStreamHandler(EventHandler(
            onListen: { plugin.listenForProgress($0) },
            onCancel: { plugin.progressSink = nil }
        ))
        metadata.setStreamHandler(EventHandler(
            onListen: { plugin.listenForMetadata($0) },
            onCancel: { plugin.metadataSink = nil }
        ))
    }

    fileprivate func emitProgress(_ event: [String: Any]) {
        if let progressSink {
            progressSink(event)
            return
        }
        progressBuffer.append(event)
        if progressBuffer.count > maxBufferedEvents {
            progressBuffer.removeFirst(progressBuffer.count - maxBufferedEvents)
        }
    }

    fileprivate func emitMetadata(_ event: [String: Any]) {
        if let metadataSink {
            metadataSink(event)
            return
        }
        guard let id = event["id"] as? Int else { return }
        metadataBuffer[id] = event
    }

    private func listenForProgress(_ sink: FlutterEventSink?) {
        progressSink = sink
        guard let sink else { return }
        progressBuffer.forEach { sink($0) }
        progressBuffer.removeAll(keepingCapacity: true)
    }

    private func listenForMetadata(_ sink: FlutterEventSink?) {
        metadataSink = sink
        guard let sink else { return }
        metadataBuffer.values.forEach { sink($0) }
        metadataBuffer.removeAll(keepingCapacity: true)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let manager else {
            result(FlutterError(
                code: "not_initialized",
                message: initializationError ?? "Native manager creation failed",
                details: nil
            ))
            return
        }
        let arguments = call.arguments as? [String: Any]
        switch call.method {
        case "init", "updateConfig":
            if call.arguments != nil, arguments == nil {
                invalidConfig("arguments must be a map", result)
                return
            }
            if call.method == "init", arguments?["config"] == nil {
                result(nil)
                return
            }
            if call.method == "updateConfig", arguments?["config"] == nil {
                invalidConfig("config is required", result)
                return
            }
            do {
                let config = try validatedConfig(from: arguments?["config"])
                finish(withConfig(config) { nativeUpdateConfig(manager, $0) }, result: result)
            } catch let error as AdapterValidationError {
                invalidConfig(error.message, result)
            } catch {
                invalidConfig("config is invalid", result)
            }
        case "setTransfersSuspended":
            guard let rawSuspended = arguments?["suspended"],
                  let number = rawSuspended as? NSNumber,
                  CFGetTypeID(number) == CFBooleanGetTypeID() else {
                invalidArguments("suspended must be a boolean", result)
                return
            }
            finish(
                nativeSetTransfersSuspended(manager, number.boolValue ? 1 : 0),
                result: result
            )
        case "areTransfersSuspended":
            var suspended: UInt8 = 0
            let code = nativeTransfersSuspended(manager, &suspended)
            code == 0 ? result(suspended != 0) : finish(code, result: result)
        case "start":
            guard let magnet = arguments?["magnet"] as? String,
                  let destination = arguments?["destination"] as? String else {
                invalidArguments("magnet and destination are required", result)
                return
            }
            if let rawDisplayName = arguments?["displayName"], !(rawDisplayName is String) {
                invalidArguments("displayName must be a string", result)
                return
            }
            let displayName = arguments?["displayName"] as? String
            if let field = embeddedNulField([
                ("magnet", magnet),
                ("destination", destination),
                ("displayName", displayName),
            ]) {
                invalidArguments("\(field) must not contain an embedded NUL", result)
                return
            }
            var id: Int32 = 0
            let code = magnet.withCString { magnetPointer in
                destination.withCString { destinationPointer in
                    withOptionalCString(displayName) { displayPointer in
                        nativeStart(manager, magnetPointer, destinationPointer, displayPointer, &id)
                    }
                }
            }
            finishId(code, id: id, invalidTorrentCode: "invalid_magnet", result: result)
        case "startFromData":
            guard let data = arguments?["data"] as? FlutterStandardTypedData,
                  let destination = arguments?["destination"] as? String else {
                invalidArguments("data and destination are required", result)
                return
            }
            if let rawDisplayName = arguments?["displayName"], !(rawDisplayName is String) {
                invalidArguments("displayName must be a string", result)
                return
            }
            let displayName = arguments?["displayName"] as? String
            if let field = embeddedNulField([
                ("destination", destination),
                ("displayName", displayName),
            ]) {
                invalidArguments("\(field) must not contain an embedded NUL", result)
                return
            }
            var id: Int32 = 0
            let code = data.data.withUnsafeBytes { bytes in
                destination.withCString { destinationPointer in
                    withOptionalCString(displayName) { displayPointer in
                        nativeStartFromData(
                            manager, bytes.bindMemory(to: UInt8.self).baseAddress,
                            bytes.count, destinationPointer, displayPointer, &id
                        )
                    }
                }
            }
            finishId(
                code, id: id, invalidTorrentCode: "invalid_torrent_data", result: result
            )
        case "startFromFile":
            guard let filePath = arguments?["torrentFilePath"] as? String,
                  let destination = arguments?["destination"] as? String else {
                invalidArguments("torrentFilePath and destination are required", result)
                return
            }
            if let rawDisplayName = arguments?["displayName"], !(rawDisplayName is String) {
                invalidArguments("displayName must be a string", result)
                return
            }
            let displayName = arguments?["displayName"] as? String
            if let field = embeddedNulField([
                ("torrentFilePath", filePath),
                ("destination", destination),
                ("displayName", displayName),
            ]) {
                invalidArguments("\(field) must not contain an embedded NUL", result)
                return
            }
            var id: Int32 = 0
            let code = filePath.withCString { filePointer in
                destination.withCString { destinationPointer in
                    withOptionalCString(displayName) { displayPointer in
                        nativeStartFromFile(manager, filePointer, destinationPointer, displayPointer, &id)
                    }
                }
            }
            finishId(
                code, id: id, invalidTorrentCode: "invalid_torrent_file", result: result
            )
        case "pause", "resume", "cancel":
            guard let id = id(from: arguments) else {
                invalidArguments("id is required", result)
                return
            }
            let code: Int32
            switch call.method {
            case "pause": code = nativePause(manager, id)
            case "resume": code = nativeResume(manager, id)
            default: code = nativeCancel(manager, id)
            }
            finish(code, result: result)
        case "finalise":
            guard let id = id(from: arguments) else {
                invalidArguments("id is required", result)
                return
            }
            finaliseQueue.async {
                let code = nativeFinalise(manager, id)
                DispatchQueue.main.async {
                    finish(code, result: result)
                }
            }
        case "getActiveTorrentIds":
            var pointer: UnsafeMutablePointer<Int32>?
            var count = 0
            let code = nativeActiveIds(manager, &pointer, &count)
            guard code == 0 else { finish(code, result: result); return }
            defer { nativeActiveIdsFree(pointer) }
            result(pointer.map { Array(UnsafeBufferPointer(start: $0, count: count)).map(Int.init) } ?? [])
        case "exists":
            guard let torrentId = id(from: arguments) else {
                invalidArguments("id is required", result); return
            }
            var exists: UInt8 = 0
            let code = nativeExists(manager, torrentId, &exists)
            code == 0 ? result(exists != 0) : finish(code, result: result)
        case "getState":
            guard let torrentId = id(from: arguments) else {
                invalidArguments("id is required", result); return
            }
            var state: Int32 = 0
            let code = nativeState(manager, torrentId, &state)
            code == 0 ? result(stateName(state)) : finish(code, result: result)
        case "getTorrentInfo":
            guard let torrentId = id(from: arguments) else {
                invalidArguments("id is required", result); return
            }
            var info = NativeTorrentInfo(
                id: 0, magnetUri: nil, savePath: nil, displayName: nil,
                state: 0, lastError: nil, createdAtMilliseconds: 0
            )
            let code = nativeTorrentInfo(manager, torrentId, &info)
            guard code == 0 else { finish(code, result: result); return }
            result([
                "id": Int(info.id), "magnetUri": string(info.magnetUri),
                "savePath": string(info.savePath), "displayName": string(info.displayName),
                "state": stateName(info.state), "lastError": string(info.lastError),
                "createdAt": info.createdAtMilliseconds,
            ])
            nativeTorrentInfoFree(&info)
        case "getLastError":
            guard let torrentId = id(from: arguments) else {
                invalidArguments("id is required", result); return
            }
            var errorPointer: UnsafeMutablePointer<CChar>?
            let code = nativeLastError(manager, torrentId, &errorPointer)
            guard code == 0 else { finish(code, result: result); return }
            result(string(errorPointer))
            nativeStringFree(errorPointer)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

private final class EventHandler: NSObject, FlutterStreamHandler {
    let onListenHandler: (FlutterEventSink?) -> Void
    let onCancelHandler: () -> Void
    init(onListen: @escaping (FlutterEventSink?) -> Void, onCancel: @escaping () -> Void) {
        onListenHandler = onListen
        onCancelHandler = onCancel
    }
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        onListenHandler(events); return nil
    }
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        onCancelHandler(); return nil
    }
}

private func nativeLayoutFailure() -> String? {
    let checks: [(String, Int?, Int)] = [
        ("pointer width", MemoryLayout<UnsafeRawPointer>.size, 8),
        ("Swift Int width", MemoryLayout<Int>.size, 8),

        ("NativeConfig size", MemoryLayout<NativeConfig>.size, 48),
        ("NativeConfig stride", MemoryLayout<NativeConfig>.stride, 48),
        ("NativeConfig.structSize", MemoryLayout<NativeConfig>.offset(of: \NativeConfig.structSize), 0),
        ("NativeConfig.maxTorrents", MemoryLayout<NativeConfig>.offset(of: \NativeConfig.maxTorrents), 8),
        ("NativeConfig.downloadRateLimit", MemoryLayout<NativeConfig>.offset(of: \NativeConfig.downloadRateLimit), 16),
        ("NativeConfig.uploadRateLimit", MemoryLayout<NativeConfig>.offset(of: \NativeConfig.uploadRateLimit), 24),
        ("NativeConfig.connectionsLimit", MemoryLayout<NativeConfig>.offset(of: \NativeConfig.connectionsLimit), 32),
        ("NativeConfig.enableDht", MemoryLayout<NativeConfig>.offset(of: \NativeConfig.enableDht), 36),
        ("NativeConfig.userAgent", MemoryLayout<NativeConfig>.offset(of: \NativeConfig.userAgent), 40),

        ("NativeStats size", MemoryLayout<NativeStats>.size, 52),
        ("NativeStats stride", MemoryLayout<NativeStats>.stride, 56),
        ("NativeStats.id", MemoryLayout<NativeStats>.offset(of: \NativeStats.id), 0),
        ("NativeStats.downloadRate", MemoryLayout<NativeStats>.offset(of: \NativeStats.downloadRate), 8),
        ("NativeStats.uploadRate", MemoryLayout<NativeStats>.offset(of: \NativeStats.uploadRate), 16),
        ("NativeStats.pieces", MemoryLayout<NativeStats>.offset(of: \NativeStats.pieces), 24),
        ("NativeStats.piecesTotal", MemoryLayout<NativeStats>.offset(of: \NativeStats.piecesTotal), 28),
        ("NativeStats.progress", MemoryLayout<NativeStats>.offset(of: \NativeStats.progress), 32),
        ("NativeStats.seeds", MemoryLayout<NativeStats>.offset(of: \NativeStats.seeds), 40),
        ("NativeStats.peers", MemoryLayout<NativeStats>.offset(of: \NativeStats.peers), 44),
        ("NativeStats.state", MemoryLayout<NativeStats>.offset(of: \NativeStats.state), 48),

        ("NativeFile size", MemoryLayout<NativeFile>.size, 32),
        ("NativeFile stride", MemoryLayout<NativeFile>.stride, 32),
        ("NativeFile.index", MemoryLayout<NativeFile>.offset(of: \NativeFile.index), 0),
        ("NativeFile.path", MemoryLayout<NativeFile>.offset(of: \NativeFile.path), 8),
        ("NativeFile.size", MemoryLayout<NativeFile>.offset(of: \NativeFile.size), 16),
        ("NativeFile.offset", MemoryLayout<NativeFile>.offset(of: \NativeFile.offset), 24),

        ("NativeMetadata size", MemoryLayout<NativeMetadata>.size, 88),
        ("NativeMetadata stride", MemoryLayout<NativeMetadata>.stride, 88),
        ("NativeMetadata.id", MemoryLayout<NativeMetadata>.offset(of: \NativeMetadata.id), 0),
        ("NativeMetadata.name", MemoryLayout<NativeMetadata>.offset(of: \NativeMetadata.name), 8),
        ("NativeMetadata.totalBytes", MemoryLayout<NativeMetadata>.offset(of: \NativeMetadata.totalBytes), 16),
        ("NativeMetadata.pieceSize", MemoryLayout<NativeMetadata>.offset(of: \NativeMetadata.pieceSize), 24),
        ("NativeMetadata.pieceCount", MemoryLayout<NativeMetadata>.offset(of: \NativeMetadata.pieceCount), 28),
        ("NativeMetadata.fileCount", MemoryLayout<NativeMetadata>.offset(of: \NativeMetadata.fileCount), 32),
        ("NativeMetadata.creationDate", MemoryLayout<NativeMetadata>.offset(of: \NativeMetadata.creationDate), 40),
        ("NativeMetadata.isPrivate", MemoryLayout<NativeMetadata>.offset(of: \NativeMetadata.isPrivate), 48),
        ("NativeMetadata.isV2", MemoryLayout<NativeMetadata>.offset(of: \NativeMetadata.isV2), 49),
        ("NativeMetadata.v1InfoHash", MemoryLayout<NativeMetadata>.offset(of: \NativeMetadata.v1InfoHash), 56),
        ("NativeMetadata.v2InfoHash", MemoryLayout<NativeMetadata>.offset(of: \NativeMetadata.v2InfoHash), 64),
        ("NativeMetadata.files", MemoryLayout<NativeMetadata>.offset(of: \NativeMetadata.files), 72),
        ("NativeMetadata.filesCount", MemoryLayout<NativeMetadata>.offset(of: \NativeMetadata.filesCount), 80),

        ("NativeTorrentInfo size", MemoryLayout<NativeTorrentInfo>.size, 56),
        ("NativeTorrentInfo stride", MemoryLayout<NativeTorrentInfo>.stride, 56),
        ("NativeTorrentInfo.id", MemoryLayout<NativeTorrentInfo>.offset(of: \NativeTorrentInfo.id), 0),
        ("NativeTorrentInfo.magnetUri", MemoryLayout<NativeTorrentInfo>.offset(of: \NativeTorrentInfo.magnetUri), 8),
        ("NativeTorrentInfo.savePath", MemoryLayout<NativeTorrentInfo>.offset(of: \NativeTorrentInfo.savePath), 16),
        ("NativeTorrentInfo.displayName", MemoryLayout<NativeTorrentInfo>.offset(of: \NativeTorrentInfo.displayName), 24),
        ("NativeTorrentInfo.state", MemoryLayout<NativeTorrentInfo>.offset(of: \NativeTorrentInfo.state), 32),
        ("NativeTorrentInfo.lastError", MemoryLayout<NativeTorrentInfo>.offset(of: \NativeTorrentInfo.lastError), 40),
        ("NativeTorrentInfo.createdAtMilliseconds", MemoryLayout<NativeTorrentInfo>.offset(of: \NativeTorrentInfo.createdAtMilliseconds), 48),
    ]

    for (name, actual, expected) in checks where actual != expected {
        let actualDescription = actual.map { String($0) } ?? "unavailable"
        return "Native C ABI layout mismatch for \(name): expected \(expected), got \(actualDescription)"
    }
    let abiVersion = nativeAbiVersion()
    if abiVersion != 2 {
        return "Native C ABI version mismatch: expected 2, got \(abiVersion)"
    }
    return nil
}


private struct ValidatedConfig {
    var maxTorrents: Int32
    var downloadRateLimit: Int64
    var uploadRateLimit: Int64
    var connectionsLimit: Int32
    var enableDht: Bool
    var userAgent: String

    static let defaults = ValidatedConfig(
        maxTorrents: 20,
        downloadRateLimit: 0,
        uploadRateLimit: 0,
        connectionsLimit: 200,
        enableDht: true,
        userAgent: "simple_torrent/2.0.0"
    )
}

private enum AdapterValidationError: Error {
    case invalidConfig(String)

    var message: String {
        switch self {
        case .invalidConfig(let message): return message
        }
    }
}

private func validatedConfig(from rawValue: Any?) throws -> ValidatedConfig {
    guard let rawValue else { return .defaults }
    guard let values = rawValue as? [String: Any] else {
        throw AdapterValidationError.invalidConfig("config must be a map")
    }

    let maxTorrents = try exactInteger(
        values["maxTorrents"], fallback: 20, field: "maxTorrents"
    )
    let downloadRateLimit = try exactInteger(
        values["downloadRateLimit"], fallback: 0, field: "downloadRateLimit"
    )
    let uploadRateLimit = try exactInteger(
        values["uploadRateLimit"], fallback: 0, field: "uploadRateLimit"
    )
    let connectionsLimit = try exactInteger(
        values["connectionsLimit"], fallback: 200, field: "connectionsLimit"
    )

    guard maxTorrents > 0, maxTorrents <= 10_000 else {
        throw AdapterValidationError.invalidConfig("maxTorrents must be between 1 and 10000")
    }
    guard downloadRateLimit >= 0, downloadRateLimit <= Int64(Int32.max) else {
        throw AdapterValidationError.invalidConfig(
            "downloadRateLimit must be between 0 and \(Int32.max)"
        )
    }
    guard uploadRateLimit >= 0, uploadRateLimit <= Int64(Int32.max) else {
        throw AdapterValidationError.invalidConfig(
            "uploadRateLimit must be between 0 and \(Int32.max)"
        )
    }
    guard connectionsLimit > 0, connectionsLimit <= 100_000 else {
        throw AdapterValidationError.invalidConfig(
            "connectionsLimit must be between 1 and 100000"
        )
    }

    let enableDht: Bool
    if let rawEnableDht = values["enableDht"] {
        guard let number = rawEnableDht as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw AdapterValidationError.invalidConfig("enableDht must be a boolean")
        }
        enableDht = number.boolValue
    } else {
        enableDht = true
    }

    let userAgent: String
    if let rawUserAgent = values["userAgent"] {
        guard let value = rawUserAgent as? String, !value.isEmpty else {
            throw AdapterValidationError.invalidConfig(
                "userAgent must be a non-empty string"
            )
        }
        guard !value.utf8.contains(0) else {
            throw AdapterValidationError.invalidConfig(
                "userAgent must not contain an embedded NUL"
            )
        }
        userAgent = value
    } else {
        userAgent = ValidatedConfig.defaults.userAgent
    }

    return ValidatedConfig(
        maxTorrents: Int32(maxTorrents),
        downloadRateLimit: downloadRateLimit,
        uploadRateLimit: uploadRateLimit,
        connectionsLimit: Int32(connectionsLimit),
        enableDht: enableDht,
        userAgent: userAgent
    )
}

private func exactInteger(
    _ rawValue: Any?,
    fallback: Int64,
    field: String
) throws -> Int64 {
    guard let rawValue else { return fallback }
    guard let number = rawValue as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID(),
          let value = Int64(number.stringValue) else {
        throw AdapterValidationError.invalidConfig("\(field) must be an integer")
    }
    return value
}

private func withConfig<T>(
    _ values: ValidatedConfig?,
    _ body: (UnsafePointer<NativeConfig>) -> T
) -> T {
    let values = values ?? .defaults
    return values.userAgent.withCString { userAgentPointer in
        var config = NativeConfig(
            structSize: MemoryLayout<NativeConfig>.stride,
            maxTorrents: values.maxTorrents,
            downloadRateLimit: values.downloadRateLimit,
            uploadRateLimit: values.uploadRateLimit,
            connectionsLimit: values.connectionsLimit,
            enableDht: values.enableDht ? 1 : 0,
            userAgent: userAgentPointer
        )
        return withUnsafePointer(to: &config, body)
    }
}

private func withOptionalCString<T>(_ value: String?, _ body: (UnsafePointer<CChar>?) -> T) -> T {
    guard let value else { return body(nil) }
    return value.withCString(body)
}

private func embeddedNulField(
    _ fields: [(name: String, value: String?)]
) -> String? {
    fields.first { $0.value?.utf8.contains(0) == true }?.name
}

private func id(from arguments: [String: Any]?) -> Int32? {
    guard let rawValue = arguments?["id"],
          let value = try? exactInteger(rawValue, fallback: 0, field: "id"),
          value > 0,
          value <= Int64(Int32.max) else {
        return nil
    }
    return Int32(value)
}

private func string(_ pointer: UnsafePointer<CChar>?) -> String {
    pointer.map { String(cString: $0) } ?? ""
}

private func stateName(_ value: Int32) -> String {
    string(nativeStateName(value))
}

private func finishId(
    _ code: Int32,
    id: Int32,
    invalidTorrentCode: String,
    result: FlutterResult
) {
    if code == 0 {
        result(Int(id))
    } else if code == 4 {
        result(FlutterError(
            code: invalidTorrentCode,
            message: "Native operation failed: \(invalidTorrentCode)",
            details: nil
        ))
    } else {
        finish(code, result: result)
    }
}

private func finish(_ code: Int32, result: FlutterResult) {
    guard code != 0 else { result(nil); return }
    let name = string(nativeResultName(code))
    result(FlutterError(code: name, message: "Native operation failed: \(name)", details: nil))
}

private func invalidArguments(_ message: String, _ result: FlutterResult) {
    result(FlutterError(code: "invalid_argument", message: message, details: nil))
}

private func invalidConfig(_ message: String, _ result: FlutterResult) {
    result(FlutterError(code: "invalid_config", message: message, details: nil))
}
