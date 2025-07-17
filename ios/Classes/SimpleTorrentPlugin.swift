import Flutter
import UIKit

// Bridge to the C++ torrent manager
@_silgen_name("torrent_manager_create")
func torrent_manager_create() -> UnsafeMutableRawPointer?

@_silgen_name("torrent_manager_destroy")
func torrent_manager_destroy(_ manager: UnsafeMutableRawPointer)

@_silgen_name("torrent_manager_apply_config")
func torrent_manager_apply_config(_ manager: UnsafeMutableRawPointer, _ maxTorrents: Int32, _ maxDownloadRate: Int32, _ maxUploadRate: Int32, _ enableDHT: Bool, _ userAgent: UnsafePointer<CChar>?)

@_silgen_name("torrent_manager_start")
func torrent_manager_start(_ manager: UnsafeMutableRawPointer, _ magnet: UnsafePointer<CChar>, _ path: UnsafePointer<CChar>, _ displayName: UnsafePointer<CChar>?, _ statsCallback: @convention(c) (Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, UnsafePointer<CChar>, UnsafePointer<CChar>) -> Void, _ metadataCallback: @convention(c) (Int32, UnsafePointer<CChar>, Int64, Int32, Int32, Int32, Int64, Bool, Bool) -> Void) -> Int32

@_silgen_name("torrent_manager_pause")
func torrent_manager_pause(_ manager: UnsafeMutableRawPointer, _ id: Int32)

@_silgen_name("torrent_manager_resume")
func torrent_manager_resume(_ manager: UnsafeMutableRawPointer, _ id: Int32)

@_silgen_name("torrent_manager_cancel")
func torrent_manager_cancel(_ manager: UnsafeMutableRawPointer, _ id: Int32)

@_silgen_name("torrent_manager_get_active_ids")
func torrent_manager_get_active_ids(_ manager: UnsafeMutableRawPointer, _ count: UnsafeMutablePointer<Int32>) -> UnsafeMutablePointer<Int32>?

@_silgen_name("torrent_manager_exists")
func torrent_manager_exists(_ manager: UnsafeMutableRawPointer, _ id: Int32) -> Bool

@_silgen_name("torrent_manager_get_state")
func torrent_manager_get_state(_ manager: UnsafeMutableRawPointer, _ id: Int32) -> UnsafePointer<CChar>?

@_silgen_name("torrent_manager_get_last_error")
func torrent_manager_get_last_error(_ manager: UnsafeMutableRawPointer, _ id: Int32) -> UnsafePointer<CChar>?

@_silgen_name("torrent_manager_free_int_array")
func torrent_manager_free_int_array(_ array: UnsafeMutablePointer<Int32>)

public class SimpleTorrentPlugin: NSObject, FlutterPlugin {
    private var torrentManager: UnsafeMutableRawPointer?
    private var progressChannel: FlutterEventChannel?
    private var metadataChannel: FlutterEventChannel?
    private var progressSink: FlutterEventSink?
    private var metadataSink: FlutterEventSink?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(name: "simple_torrent/methods", binaryMessenger: registrar.messenger())
        let progressChannel = FlutterEventChannel(name: "simple_torrent/progress", binaryMessenger: registrar.messenger())
        let metadataChannel = FlutterEventChannel(name: "simple_torrent/metadata", binaryMessenger: registrar.messenger())
        
        let instance = SimpleTorrentPlugin()
        instance.progressChannel = progressChannel
        instance.metadataChannel = metadataChannel
        
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
            result(state)
        } else {
            result("unknown")
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
    
    override func awakeFromNib() {
        super.awakeFromNib()
        SimpleTorrentPlugin.sharedInstance = self
    }
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
