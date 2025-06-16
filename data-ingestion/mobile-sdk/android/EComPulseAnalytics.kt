package com.ecompulse.analytics

import android.content.Context
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import android.util.Log
import kotlinx.coroutines.*
import kotlinx.serialization.*
import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.util.*
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.random.Random

/**
 * E-ComPulse Analytics SDK for Android
 * 
 * Provides real-time event tracking with offline support, automatic batching,
 * and intelligent retry mechanisms for e-commerce analytics.
 */
object EComPulseAnalytics {
    
    private const val TAG = "EComPulseAnalytics"
    private const val PREF_NAME = "ecompulse_analytics"
    private const val PREF_SESSION_ID = "session_id"
    private const val PREF_USER_ID = "user_id"
    private const val PREF_OPT_OUT = "opt_out"
    
    private lateinit var context: Context
    private lateinit var config: AnalyticsConfig
    private lateinit var eventQueue: EventQueue
    private lateinit var httpClient: OkHttpClient
    private lateinit var preferences: SharedPreferences
    
    private val isInitialized = AtomicBoolean(false)
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var sessionId: String? = null
    private var userId: String? = null
    
    /**
     * Initialize the SDK with configuration
     */
    fun initialize(context: Context, config: AnalyticsConfig) {
        if (isInitialized.getAndSet(true)) {
            Log.w(TAG, "SDK already initialized")
            return
        }
        
        this.context = context.applicationContext
        this.config = config
        this.preferences = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        
        // Initialize HTTP client
        httpClient = OkHttpClient.Builder()
            .connectTimeout(config.networkTimeout, java.util.concurrent.TimeUnit.MILLISECONDS)
            .readTimeout(config.networkTimeout, java.util.concurrent.TimeUnit.MILLISECONDS)
            .addInterceptor(createLoggingInterceptor())
            .build()
        
        // Initialize event queue
        eventQueue = EventQueue(context, config)
        
        // Restore session
        restoreSession()
        
        // Start session if auto-tracking enabled
        if (config.enableAutoTracking) {
            startNewSession()
            setupAutoTracking()
        }
        
        // Start background processing
        startEventProcessor()
        
        if (config.enableLogging) {
            Log.i(TAG, "E-ComPulse Analytics SDK initialized successfully")
        }
    }
    
    /**
     * Track a custom event
     */
    fun track(eventName: String, properties: Map<String, Any> = emptyMap()) {
        if (!isInitialized.get()) {
            Log.e(TAG, "SDK not initialized. Call initialize() first.")
            return
        }
        
        if (isOptedOut()) {
            if (config.enableLogging) {
                Log.d(TAG, "User opted out, skipping event: $eventName")
            }
            return
        }
        
        val event = AnalyticsEvent(
            eventName = eventName,
            properties = properties.toMutableMap().apply {
                putAll(getCommonProperties())
            },
            timestamp = System.currentTimeMillis(),
            sessionId = sessionId,
            userId = userId
        )
        
        eventQueue.enqueue(event)
        
        if (config.enableLogging) {
            Log.d(TAG, "Event tracked: $eventName")
        }
    }
    
    /**
     * Track product viewed event
     */
    fun trackProductViewed(productId: String, productData: Map<String, Any> = emptyMap()) {
        track("product_viewed", productData.toMutableMap().apply {
            put("product_id", productId)
            put("event_category", "ecommerce")
        })
    }
    
    /**
     * Track product added to cart
     */
    fun trackProductAdded(productId: String, cartData: Map<String, Any> = emptyMap()) {
        track("product_added", cartData.toMutableMap().apply {
            put("product_id", productId)
            put("event_category", "ecommerce")
        })
    }
    
    /**
     * Track purchase completed
     */
    fun trackPurchaseCompleted(orderData: Map<String, Any>) {
        track("purchase_completed", orderData.toMutableMap().apply {
            put("event_category", "ecommerce")
        })
    }
    
    /**
     * Set user properties
     */
    fun setUserProperties(properties: Map<String, Any>) {
        properties.forEach { (key, value) ->
            setUserProperty(key, value)
        }
    }
    
    /**
     * Set single user property
     */
    fun setUserProperty(key: String, value: Any) {
        preferences.edit()
            .putString("user_prop_$key", value.toString())
            .apply()
    }
    
    /**
     * Set user ID
     */
    fun setUserId(userId: String?) {
        this.userId = userId
        preferences.edit()
            .putString(PREF_USER_ID, userId)
            .apply()
    }
    
    /**
     * Start new session
     */
    fun startNewSession() {
        sessionId = generateSessionId()
        preferences.edit()
            .putString(PREF_SESSION_ID, sessionId)
            .putLong("session_start_time", System.currentTimeMillis())
            .apply()
        
        if (config.enableAutoTracking) {
            track("session_started")
        }
    }
    
    /**
     * End current session
     */
    fun endSession() {
        if (config.enableAutoTracking && sessionId != null) {
            track("session_ended", mapOf(
                "session_duration" to getSessionDuration()
            ))
        }
        
        sessionId = null
        preferences.edit()
            .remove(PREF_SESSION_ID)
            .remove("session_start_time")
            .apply()
    }
    
    /**
     * Get current session ID
     */
    fun getSessionId(): String? = sessionId
    
    /**
     * Opt user out of tracking
     */
    fun optOut() {
        preferences.edit()
            .putBoolean(PREF_OPT_OUT, true)
            .apply()
        
        eventQueue.clear()
        
        if (config.enableLogging) {
            Log.i(TAG, "User opted out of tracking")
        }
    }
    
    /**
     * Opt user back in
     */
    fun optIn() {
        preferences.edit()
            .putBoolean(PREF_OPT_OUT, false)
            .apply()
        
        if (config.enableLogging) {
            Log.i(TAG, "User opted in to tracking")
        }
    }
    
    /**
     * Check if user is opted out
     */
    fun isOptedOut(): Boolean = preferences.getBoolean(PREF_OPT_OUT, false)
    
    /**
     * Delete all user data
     */
    fun deleteUserData() {
        preferences.edit().clear().apply()
        eventQueue.clear()
        sessionId = null
        userId = null
        
        if (config.enableLogging) {
            Log.i(TAG, "All user data deleted")
        }
    }
    
    /**
     * Flush all pending events immediately
     */
    fun flush() {
        scope.launch {
            eventQueue.flush()
        }
    }
    
    // Private helper methods
    
    private fun restoreSession() {
        sessionId = preferences.getString(PREF_SESSION_ID, null)
        userId = preferences.getString(PREF_USER_ID, null)
        
        // Check if session expired (24 hours)
        val sessionStartTime = preferences.getLong("session_start_time", 0)
        val sessionTimeout = 24 * 60 * 60 * 1000L // 24 hours
        
        if (sessionId != null && System.currentTimeMillis() - sessionStartTime > sessionTimeout) {
            endSession()
        }
    }
    
    private fun setupAutoTracking() {
        // Track app lifecycle events using ActivityLifecycleCallbacks
        // This would be implemented with proper lifecycle management
        track("app_opened")
    }
    
    private fun startEventProcessor() {
        scope.launch {
            while (isActive) {
                try {
                    if (!isOptedOut()) {
                        eventQueue.processBatch()
                    }
                    delay(config.flushInterval)
                } catch (e: Exception) {
                    if (config.enableLogging) {
                        Log.e(TAG, "Error processing events", e)
                    }
                }
            }
        }
    }
    
    private fun getCommonProperties(): Map<String, Any> {
        return mutableMapOf<String, Any>().apply {
            put("sdk_version", "1.0.0")
            put("platform", "android")
            put("app_version", getAppVersion())
            put("device_model", android.os.Build.MODEL)
            put("os_version", android.os.Build.VERSION.RELEASE)
            put("timestamp", System.currentTimeMillis())
            
            // Add user properties
            preferences.all.forEach { (key, value) ->
                if (key.startsWith("user_prop_")) {
                    put(key.removePrefix("user_prop_"), value.toString())
                }
            }
        }
    }
    
    private fun getAppVersion(): String {
        return try {
            val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
            packageInfo.versionName ?: "unknown"
        } catch (e: Exception) {
            "unknown"
        }
    }
    
    private fun generateSessionId(): String {
        return "session_${System.currentTimeMillis()}_${Random.nextInt(10000)}"
    }
    
    private fun getSessionDuration(): Long {
        val startTime = preferences.getLong("session_start_time", 0)
        return if (startTime > 0) System.currentTimeMillis() - startTime else 0
    }
    
    private fun createLoggingInterceptor(): Interceptor {
        return object : Interceptor {
            override fun intercept(chain: Interceptor.Chain): Response {
                val request = chain.request()
                
                if (config.enableLogging) {
                    Log.d(TAG, "HTTP Request: ${request.method} ${request.url}")
                }
                
                val response = chain.proceed(request)
                
                if (config.enableLogging) {
                    Log.d(TAG, "HTTP Response: ${response.code} ${response.message}")
                }
                
                return response
            }
        }
    }
}

/**
 * Analytics configuration class
 */
data class AnalyticsConfig(
    val apiKey: String,
    val endpoint: String,
    val environment: String = "production",
    val enableAutoTracking: Boolean = true,
    val enableOfflineSupport: Boolean = true,
    val batchSize: Int = 20,
    val flushInterval: Long = 30000, // 30 seconds
    val maxQueueSize: Int = 1000,
    val enableLogging: Boolean = false,
    val networkTimeout: Long = 10000 // 10 seconds
) {
    class Builder {
        private var apiKey: String = ""
        private var endpoint: String = ""
        private var environment: String = "production"
        private var enableAutoTracking: Boolean = true
        private var enableOfflineSupport: Boolean = true
        private var batchSize: Int = 20
        private var flushInterval: Long = 30000
        private var maxQueueSize: Int = 1000
        private var enableLogging: Boolean = false
        private var networkTimeout: Long = 10000
        
        fun apiKey(apiKey: String) = apply { this.apiKey = apiKey }
        fun endpoint(endpoint: String) = apply { this.endpoint = endpoint }
        fun environment(environment: String) = apply { this.environment = environment }
        fun enableAutoTracking(enable: Boolean) = apply { this.enableAutoTracking = enable }
        fun enableOfflineSupport(enable: Boolean) = apply { this.enableOfflineSupport = enable }
        fun batchSize(size: Int) = apply { this.batchSize = size }
        fun flushInterval(interval: Long) = apply { this.flushInterval = interval }
        fun maxQueueSize(size: Int) = apply { this.maxQueueSize = size }
        fun enableLogging(enable: Boolean) = apply { this.enableLogging = enable }
        fun networkTimeout(timeout: Long) = apply { this.networkTimeout = timeout }
        
        fun build(): AnalyticsConfig {
            require(apiKey.isNotBlank()) { "API key is required" }
            require(endpoint.isNotBlank()) { "Endpoint is required" }
            
            return AnalyticsConfig(
                apiKey, endpoint, environment, enableAutoTracking,
                enableOfflineSupport, batchSize, flushInterval,
                maxQueueSize, enableLogging, networkTimeout
            )
        }
    }
}

/**
 * Analytics event data class
 */
@Serializable
data class AnalyticsEvent(
    val eventName: String,
    val properties: MutableMap<String, Any>,
    val timestamp: Long,
    val sessionId: String?,
    val userId: String?
)

/**
 * Event queue for offline support and batching
 */
private class EventQueue(
    private val context: Context,
    private val config: AnalyticsConfig
) {
    private val queue = ConcurrentLinkedQueue<AnalyticsEvent>()
    private val httpClient = OkHttpClient()
    private val json = Json { ignoreUnknownKeys = true }
    
    fun enqueue(event: AnalyticsEvent) {
        if (queue.size >= config.maxQueueSize) {
            queue.poll() // Remove oldest event
        }
        queue.offer(event)
    }
    
    suspend fun processBatch() {
        val batch = mutableListOf<AnalyticsEvent>()
        
        // Collect batch
        repeat(config.batchSize) {
            queue.poll()?.let { batch.add(it) }
        }
        
        if (batch.isNotEmpty()) {
            sendBatch(batch)
        }
    }
    
    private suspend fun sendBatch(events: List<AnalyticsEvent>) {
        try {
            val payload = json.encodeToString(mapOf(
                "events" to events,
                "api_key" to config.apiKey,
                "environment" to config.environment
            ))
            
            val request = Request.Builder()
                .url("${config.endpoint}/events")
                .post(payload.toRequestBody("application/json".toMediaType()))
                .addHeader("Content-Type", "application/json")
                .addHeader("User-Agent", "EComPulse-Android-SDK/1.0.0")
                .build()
            
            val response = httpClient.newCall(request).execute()
            
            if (!response.isSuccessful) {
                throw IOException("HTTP ${response.code}: ${response.message}")
            }
            
            if (config.enableLogging) {
                Log.d("EComPulseAnalytics", "Batch sent successfully: ${events.size} events")
            }
            
        } catch (e: Exception) {
            // Re-queue events on failure
            events.forEach { queue.offer(it) }
            
            if (config.enableLogging) {
                Log.e("EComPulseAnalytics", "Failed to send batch", e)
            }
        }
    }
    
    fun flush() {
        // Process all remaining events
        while (queue.isNotEmpty()) {
            runBlocking {
                processBatch()
            }
        }
    }
    
    fun clear() {
        queue.clear()
    }
}
