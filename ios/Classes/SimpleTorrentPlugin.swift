import Flutter
import UIKit

// The C interface is made available via the bridging header. No need for
// `_silgen_name` declarations here.

public class SimpleTorrentPlugin: NSObject, FlutterPlugin {
    private var torrentManager: UnsafeMutableRawPointer?
    private var progressChannel: FlutterEventChannel?
    private var metadataChannel: FlutterEventChannel?
    // Make these internal so the stream handlers can access them
    internal var progressSink: FlutterEventSink?
    internal var metadataSink: FlutterEventSink?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(name: "simple_torrent/methods", binaryMessenger: registrar.messenger())
        let progressChannel = FlutterEventChannel(name: "simple_torrent/progress", binaryMessenger: registrar.messenger())
        let metadataChannel = FlutterEventChannel(name: "simple_torrent/metadata", binaryMessenger: registrar.messenger())
        
        let instance = SimpleTorrentPlugin()
        instance.progressChannel = progressChannel
        instance.metadataChannel = metadataChannel
        
        // Set the shared instance here since awakeFromNib won't be called for Flutter plugins
        SimpleTorrentPlugin.sharedInstance = instance
        
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        
        progressChannel.setStreamHandler(ProgressStreamHandler(plugin: instance))
        metadataChannel.setStreamHandler(MetadataStreamHandler(plugin: instance))
    }
    
    override init() {
        super.init()
        torrentManager = torrent_manager_create()
    }
    
    deinit {
        if let manager = torrentManager {
            torrent_manager_destroy(manager)
        }
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let manager = torrentManager else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "Torrent manager not initialized", details: nil))
            return
        }
        
        switch call.method {
        case "init":
            handleInit(call: call, result: result, manager: manager)
        case "start":
            handleStart(call: call, result: result, manager: manager)
        case "pause":
            handlePause(call: call, result: result, manager: manager)
        case "resume":
            handleResume(call: call, result: result, manager: manager)
        case "cancel":
            handleCancel(call: call, result: result, manager: manager)
        case "getActiveTorrentIds":
            handleGetActiveTorrentIds(result: result, manager: manager)
        case "exists":
            handleExists(call: call, result: result, manager: manager)
        case "getState":
            handleGetState(call: call, result: result, manager: manager)
        case "getTorrentInfo":
            handleGetTorrentInfo(call: call, result: result, manager: manager)
        case "getLastError":
            handleGetLastError(call: call, result: result, manager: manager)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func handleInit(call: FlutterMethodCall, result: @escaping FlutterResult, manager: UnsafeMutableRawPointer) {
        if let args = call.arguments as? [String: Any],
           let config = args["config"] as? [String: Any] {
            
            let maxTorrents = config["maxTorrents"] as? Int ?? 20
            let maxDownloadRate = config["maxDownloadRate"] as? Int ?? 0
            let maxUploadRate = config["maxUploadRate"] as? Int ?? 0
            let enableDHT = config["enableDHT"] as? Bool ?? true
            let userAgent = config["userAgent"] as? String ?? "simple_torrent/1.0"
            
            userAgent.withCString { userAgentPtr in
                torrent_manager_apply_config(manager, Int32(maxTorrents), Int32(maxDownloadRate), Int32(maxUploadRate), enableDHT, userAgentPtr)
            }
        }
        result(nil)
    }
    
    private func handleStart(call: FlutterMethodCall, result: @escaping FlutterResult, manager: UnsafeMutableRawPointer) {
        guard let args = call.arguments as? [String: Any],
              let magnet = args["magnet"] as? String,
              let destination = args["destination"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "magnet and destination are required", details: nil))
            return
        }
        
        let displayName = args["displayName"] as? String
        
        let statsCallback: @convention(c) (Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, UnsafePointer<CChar>, UnsafePointer<CChar>) -> Void = { id, dlRate, ulRate, pieces, piecesTotal, progressPct, seeds, peers, phase, state in
            DispatchQueue.main.async {
                if let instance = SimpleTorrentPlugin.sharedInstance {
                    instance.sendStats(id: Int(id), dlRate: Int(dlRate), ulRate: Int(ulRate), pieces: Int(pieces), piecesTotal: Int(piecesTotal), progressPct: Int(progressPct), seeds: Int(seeds), peers: Int(peers), phase: String(cString: phase), state: String(cString: state))
                }
            }
        }
        
        let metadataCallback: @convention(c) (Int32, UnsafePointer<CChar>, Int64, Int32, Int32, Int32, Int64, Bool, Bool) -> Void = { id, name, totalBytes, pieceSize, pieceCount, fileCount, creationDate, isPrivate, isV2 in
            DispatchQueue.main.async {
                if let instance = SimpleTorrentPlugin.sharedInstance {
                    instance.sendMetadata(id: Int(id), name: String(cString: name), totalBytes: Int(totalBytes), pieceSize: Int(pieceSize), pieceCount: Int(pieceCount), fileCount: Int(fileCount), creationDate: Int(creationDate), isPrivate: isPrivate, isV2: isV2)
                }
            }
        }
        
        let torrentId = magnet.withCString { magnetPtr in
            destination.withCString { pathPtr in
                if let displayName = displayName {
                    return displayName.withCString { namePtr in
                        torrent_manager_start(manager, magnetPtr, pathPtr, namePtr, statsCallback, metadataCallback)
                    }
                } else {
                    return torrent_manager_start(manager, magnetPtr, pathPtr, nil, statsCallback, metadataCallback)
                }
            }
        }
        
        if torrentId > 0 {
            result(Int(torrentId))
        } else {
            result(FlutterError(code: "FAILED", message: "Could not start torrent", details: nil))
        }
    }
    
    private func handlePause(call: FlutterMethodCall, result: @escaping FlutterResult, manager: UnsafeMutableRawPointer) {
        guard let args = call.arguments as? [String: Any],
              let id = args["id"] as? Int else {
            result(FlutterError(code: "INVALID_ARGS", message: "id is required", details: nil))
            return
        }
        
        torrent_manager_pause(manager, Int32(id))
        result(nil)
    }
    
    private func handleResume(call: FlutterMethodCall, result: @escaping FlutterResult, manager: UnsafeMutableRawPointer) {
        guard let args = call.arguments as? [String: Any],
              let id = args["id"] as? Int else {
            result(FlutterError(code: "INVALID_ARGS", message: "id is required", details: nil))
            return
        }
        
        torrent_manager_resume(manager, Int32(id))
        result(nil)
    }
    
    private func handleCancel(call: FlutterMethodCall, result: @escaping FlutterResult, manager: UnsafeMutableRawPointer) {
        guard let args = call.arguments as? [String: Any],
              let id = args["id"] as? Int else {
            result(FlutterError(code: "INVALID_ARGS", message: "id is required", details: nil))
            return
        }
        
        torrent_manager_cancel(manager, Int32(id))
        result(nil)
    }
    
    private func handleGetActiveTorrentIds(result: @escaping FlutterResult, manager: UnsafeMutableRawPointer) {
        var count: Int32 = 0
        if let idsPtr = torrent_manager_get_active_ids(manager, &count) {
            let ids = Array(UnsafeBufferPointer(start: idsPtr, count: Int(count))).map { Int($0) }
            torrent_manager_free_int_array(idsPtr)
            result(ids)
        } else {
            result([])
        }
    }
    
    private func handleExists(call: FlutterMethodCall, result: @escaping FlutterResult, manager: UnsafeMutableRawPointer) {
        guard let args = call.arguments as? [String: Any],
              let id = args["id"] as? Int else {
            result(FlutterError(code: "INVALID_ARGS", message: "id is required", details: nil))
            return
        }
        
        let exists = torrent_manager_exists(manager, Int32(id))
        result(exists)
    }
    
    private func handleGetState(call: FlutterMethodCall, result: @escaping FlutterResult, manager: UnsafeMutableRawPointer) {
        guard let args = call.arguments as? [String: Any],
              let id = args["id"] as? Int else {
            result(FlutterError(code: "INVALID_ARGS", message: "id is required", details: nil))
            return
        }
        
        if let statePtr = torrent_manager_get_state(manager, Int32(id)) {
            let state = String(cString: statePtr)
            torrent_manager_free_string(statePtr)
            result(state)
        } else {
            result("unknown")
        }
    }
    
    private func handleGetTorrentInfo(call: FlutterMethodCall, result: @escaping FlutterResult, manager: UnsafeMutableRawPointer) {
        guard let args = call.arguments as? [String: Any],
              let id = args["id"] as? Int else {
            result(FlutterError(code: "INVALID_ARGS", message: "id is required", details: nil))
            return
        }
        
        if let infoPtr = torrent_manager_get_info(manager, Int32(id)) {
            let info = infoPtr.pointee
            
            let torrentInfo: [String: Any] = [
                "id": Int(info.id),
                "magnetUri": info.magnetUri != nil ? String(cString: info.magnetUri!) : "",
                "savePath": info.savePath != nil ? String(cString: info.savePath!) : "",
                "displayName": info.displayName != nil ? String(cString: info.displayName!) : "",
                "state": info.state != nil ? String(cString: info.state!) : "unknown",
                "lastError": info.lastError != nil ? String(cString: info.lastError!) : "",
                "createdAt": Int(info.createdAt)
            ]
            
            torrent_manager_free_torrent_info(infoPtr)
            result(torrentInfo)
        } else {
            result(FlutterError(code: "NOT_FOUND", message: "Torrent not found", details: nil))
        }
    }
    
    private func handleGetLastError(call: FlutterMethodCall, result: @escaping FlutterResult, manager: UnsafeMutableRawPointer) {
        guard let args = call.arguments as? [String: Any],
              let id = args["id"] as? Int else {
            result(FlutterError(code: "INVALID_ARGS", message: "id is required", details: nil))
            return
        }
        
        if let errorPtr = torrent_manager_get_last_error(manager, Int32(id)) {
            let error = String(cString: errorPtr)
            torrent_manager_free_string(errorPtr)
            result(error)
        } else {
            result("")
        }
    }
    
    // Event channel handlers
    private func sendStats(id: Int, dlRate: Int, ulRate: Int, pieces: Int, piecesTotal: Int, progressPct: Int, seeds: Int, peers: Int, phase: String, state: String) {
        let stats: [String: Any] = [
            "eventType": "stats",
            "id": id,
            "download_rate": dlRate,
            "upload_rate": ulRate,
            "pieces": pieces,
            "pieces_total": piecesTotal,
            "progress": progressPct,
            "seeds": seeds,
            "peers": peers,
            "phase": phase,
            "state": state
        ]
        progressSink?(stats)
    }
    
    private func sendMetadata(id: Int, name: String, totalBytes: Int, pieceSize: Int, pieceCount: Int, fileCount: Int, creationDate: Int, isPrivate: Bool, isV2: Bool) {
        let metadata: [String: Any] = [
            "eventType": "metadata",
            "id": id,
            "name": name,
            "total_bytes": totalBytes,
            "piece_size": pieceSize,
            "piece_count": pieceCount,
            "file_count": fileCount,
            "creation_date": creationDate,
            "private": isPrivate,
            "v2": isV2
        ]
        metadataSink?(metadata)
    }
    
    static var sharedInstance: SimpleTorrentPlugin?
}

class ProgressStreamHandler: NSObject, FlutterStreamHandler {
    weak var plugin: SimpleTorrentPlugin?
    
    init(plugin: SimpleTorrentPlugin) {
        self.plugin = plugin
    }
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        plugin?.progressSink = events
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        plugin?.progressSink = nil
        return nil
    }
}

class MetadataStreamHandler: NSObject, FlutterStreamHandler {
    weak var plugin: SimpleTorrentPlugin?
    
    init(plugin: SimpleTorrentPlugin) {
        self.plugin = plugin
    }
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        plugin?.metadataSink = events
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        plugin?.metadataSink = nil
        return nil
    }
}
