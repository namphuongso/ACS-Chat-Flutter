package com.npp.chatnative

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.NonNull
import com.azure.android.communication.chat.ChatClient
import com.azure.android.communication.chat.ChatClientBuilder
import com.azure.android.communication.chat.models.ChatEventType
import com.azure.android.communication.chat.models.ChatMessageReceivedEvent
import com.azure.android.communication.common.CommunicationTokenCredential
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * ĐÚNG PHẠM VI mục 3 kế hoạch gốc: không UI, không business logic,
 * không gửi tin/load lịch sử ở đây — chỉ init connection realtime và
 * forward sự kiện tin nhắn mới về Flutter qua EventChannel.
 *
 * API đã verify với SDK thật:
 *   - azure-communication-chat:2.1.0
 *   - azure-communication-common:1.2.1
 * Xem REALTIME_PROGRESS.md để biết chi tiết đối chiếu.
 */
class ChatNativePlugin : FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {

    private companion object {
        private const val TAG = "ChatNativePlugin"
    }

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    private var chatClient: ChatClient? = null
    private var applicationContext: Context? = null

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, "com.npp.chatnative/methods")
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, "com.npp.chatnative/events")
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        stopRealtimeNotifications()
        applicationContext = null
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
                initializeChatClientAsync(token, endpoint, result)
            }
            "stopRealtimeNotifications" -> {
                stopRealtimeNotifications()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun initializeChatClientAsync(token: String, endpoint: String, result: Result) {
        val context = applicationContext
        if (context == null) {
            result.error("NATIVE_INIT_FAILED", "Plugin chưa attach vào engine", null)
            return
        }
        // startRealtimeNotifications() chứa HTTP đồng bộ tới chat gateway +
        // blocking getToken() — bắt buộc chạy ngoài main thread để tránh ANR.
        Thread {
            try {
                initializeChatClient(context, token, endpoint)
                Handler(Looper.getMainLooper()).post { result.success(null) }
            } catch (e: Exception) {
                Log.e(TAG, "Initialize realtime failed", e)
                Handler(Looper.getMainLooper()).post {
                    result.error("NATIVE_INIT_FAILED", e.message, null)
                }
            }
        }.start()
    }

    private fun initializeChatClient(context: Context, token: String, endpoint: String) {
        // Đóng client cũ nếu có (vd re-init sau khi refresh token) trước
        // khi tạo mới, tránh leak connection.
        stopRealtimeNotifications()

        val credential = CommunicationTokenCredential(token)
        val client = ChatClientBuilder()
            .endpoint(endpoint)
            .credential(credential)
            .buildClient()

        // Đồng bộ (blocking): lấy token + đăng ký Trouter với chat gateway.
        // Error handler chỉ báo lỗi async (vd token hết hạn, renewal fail).
        client.startRealtimeNotifications(context) { throwable ->
            Log.w(TAG, "Realtime error: ${throwable.message}", throwable)
        }

        // Gọi sau startRealtimeNotifications() vì addEventHandler ném
        // IllegalStateException nếu realtime chưa bắt đầu (đã verify).
        client.addEventHandler(ChatEventType.CHAT_MESSAGE_RECEIVED) { chatEvent ->
            val messageEvent = chatEvent as? ChatMessageReceivedEvent ?: return@addEventHandler
            // Chỉ gửi field cần thiết qua channel (mục 6 kế hoạch gốc) —
            // KHÔNG serialize nguyên object ACS SDK.
            val payload = mapOf(
                "threadId" to messageEvent.chatThreadId,
                "messageId" to messageEvent.id,
                "senderId" to (messageEvent.sender?.rawId ?: ""),
                "senderDisplayName" to (messageEvent.senderDisplayName ?: ""),
                "content" to (messageEvent.content ?: ""),
                "createdAt" to messageEvent.createdOn.toString(),
            )
            // Trouter callback chạy trên background thread — event phải gửi
            // về Flutter trên main thread.
            Handler(Looper.getMainLooper()).post { eventSink?.success(payload) }
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
