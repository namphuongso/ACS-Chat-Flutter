import Flutter
import UIKit
import AzureCommunicationChat
import AzureCommunicationCommon
import AzureCore

/// ĐÚNG PHẠM VI mục 3 kế hoạch gốc: không UI, không business logic,
/// không gửi tin/load lịch sử ở đây — chỉ init connection realtime và
/// forward sự kiện tin nhắn mới về Flutter qua EventChannel.
///
/// API đã verify với SDK thật:
///   - AzureCommunicationChat:1.3.7 (CocoaPods)
///   - AzureCore:1.0.0-beta.16
/// Xem REALTIME_PROGRESS.md để biết chi tiết đối chiếu.
public class ChatNativePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    private var chatClient: ChatClient?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = ChatNativePlugin()

        let methodChannel = FlutterMethodChannel(
            name: "com.npp.chatnative/methods",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(instance, channel: methodChannel)

        let eventChannel = FlutterEventChannel(
            name: "com.npp.chatnative/events",
            binaryMessenger: registrar.messenger()
        )
        eventChannel.setStreamHandler(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            guard let args = call.arguments as? [String: Any],
                  let token = args["token"] as? String,
                  let endpoint = args["endpoint"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "token/endpoint không được null", details: nil))
                return
            }
            do {
                try initializeChatClient(token: token, endpoint: endpoint)
                result(nil)
            } catch {
                result(FlutterError(code: "NATIVE_INIT_FAILED", message: error.localizedDescription, details: nil))
            }
        case "stopRealtimeNotifications":
            stopRealtimeNotifications()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    private func initializeChatClient(token: String, endpoint: String) throws {
        // Đóng client cũ nếu có (vd re-init sau khi refresh token) trước
        // khi tạo mới, tránh leak connection.
        stopRealtimeNotifications()

        let credential = try CommunicationTokenCredential(token: token)
        let client = try ChatClient(
            endpoint: endpoint,
            credential: credential,
            withOptions: AzureCommunicationChatClientOptions()
        )
        chatClient = client

        // register() phải gọi SAU khi realtime đã start (SDK tự bỏ qua
        // handler nếu signaling chưa chạy) — nên đăng ký trong completion
        // handler của startRealTimeNotifications.
        client.startRealTimeNotifications { [weak self] result in
            switch result {
            case .success:
                self?.chatClient?.register(event: ChatEventId.chatMessageReceived) { event in
                    self?.handleChatEvent(event)
                }
            case .failure(let error):
                NSLog("ChatNative: startRealTimeNotifications failed: %@", error.localizedDescription)
            }
        }
    }

    private func handleChatEvent(_ event: TrouterEvent) {
        guard case .chatMessageReceivedEvent(let messageEvent) = event else { return }
        guard let eventSink = eventSink else { return }

        // Chỉ gửi field cần thiết qua channel (mục 6 kế hoạch gốc) —
        // KHÔNG serialize nguyên object ACS SDK.
        let payload: [String: Any] = [
            "threadId": messageEvent.threadId,
            "messageId": messageEvent.id,
            "senderId": messageEvent.sender?.rawId ?? "",
            "senderDisplayName": messageEvent.senderDisplayName ?? "",
            "content": messageEvent.message,
            "createdAt": messageEvent.createdOn?.requestString ?? "",
        ]
        // Event có thể tới trên queue nền — phải gửi về Flutter trên main.
        DispatchQueue.main.async { eventSink(payload) }
    }

    private func stopRealtimeNotifications() {
        chatClient?.stopRealTimeNotifications()
        chatClient = nil
    }
}
