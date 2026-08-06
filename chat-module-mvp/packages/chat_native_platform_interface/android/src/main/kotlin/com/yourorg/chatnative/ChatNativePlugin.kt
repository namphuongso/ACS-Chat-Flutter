package com.yourorg.chatnative

import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

// TODO(verify-acs-android-sdk): các import + tên hàm dưới đây dựa theo
// cấu trúc SDK Azure Communication Chat Android mà mình nắm được, NHƯNG
// CHƯA compile-test được (sandbox không tải được Maven package). Việc
// đầu tiên khi có máy thật: build thử package này riêng, đối chiếu
// đúng tên class/method với version SDK cụ thể đang dùng (ghi version
// vào README theo mục 7.5 kế hoạch gốc), sửa lại nếu lệch.
import com.azure.android.communication.chat.ChatClient
import com.azure.android.communication.chat.models.ChatEventType
import com.azure.android.communication.chat.models.ChatMessageReceivedEvent
import com.azure.android.communication.common.CommunicationTokenCredential

/**
 * ĐÚNG PHẠM VI mục 3 kế hoạch gốc: không UI, không business logic,
 * không gửi tin/load lịch sử ở đây — chỉ init connection realtime và
 * forward sự kiện tin nhắn mới về Flutter qua EventChannel.
 */
class ChatNativePlugin : FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    private var chatClient: ChatClient? = null

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(binding.binaryMessenger, "com.yourorg.chatnative/methods")
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, "com.yourorg.chatnative/events")
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        stopRealtimeNotifications()
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "initialize" -> {
                val token = call.argument<String>("token")
                val endpoint = call.argument<String>("endpoint")
                if (token == null || endpoint == null) {
                    result.error("INVALID_ARGS", "token/endpoint không được null", null)
                    return
                }
                try {
                    initializeChatClient(token = token, endpoint = endpoint)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("NATIVE_INIT_FAILED", e.message, null)
                }
            }
            "stopRealtimeNotifications" -> {
                stopRealtimeNotifications()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun initializeChatClient(token: String, endpoint: String) {
        // Đóng client cũ nếu có (vd re-init sau khi refresh token) trước
        // khi tạo mới, tránh leak connection.
        stopRealtimeNotifications()

        val credential = CommunicationTokenCredential(token)
        val client = ChatClient.Builder()
            .endpoint(endpoint)
            .credential(credential)
            .build()

        client.startRealtimeNotifications()

        client.addEventHandler(ChatEventType.CHAT_MESSAGE_RECEIVED) { event ->
            val messageEvent = event as? ChatMessageReceivedEvent ?: return@addEventHandler
            // Chỉ gửi field cần thiết qua channel (mục 6 kế hoạch gốc) —
            // KHÔNG serialize nguyên object ACS SDK.
            val payload = mapOf(
                "threadId" to messageEvent.threadId,
                "messageId" to messageEvent.id,
                "senderId" to (messageEvent.senderCommunicationIdentifier?.rawId ?: ""),
                "senderDisplayName" to (messageEvent.senderDisplayName ?: ""),
                "content" to (messageEvent.content ?: ""),
                "createdAt" to messageEvent.createdOn.toString(),
            )
            eventSink?.success(payload)
        }

        chatClient = client
    }

    private fun stopRealtimeNotifications() {
        chatClient?.stopRealtimeNotifications()
        chatClient = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}
