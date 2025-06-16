import Foundation
import UIKit

/**
 * E-ComPulse Analytics SDK for iOS
 *
 * Provides real-time event tracking with offline support, automatic batching,
 * and intelligent retry mechanisms for e-commerce analytics.
 */
@objc public class EComPulseAnalytics: NSObject {
    
    // MARK: - Private Properties
    
    private static var shared: EComPulseAnalytics?
    private var config: AnalyticsConfig
    private var eventQueue: EventQueue
    private var sessionManager: SessionManager
    private var networkManager: NetworkManager
    private var userDefaults: UserDefaults
    
    private let isInitialized = NSLock()
    private var initialized = false
    
    // MARK: - Constants
    
    private struct Constants {
        static let sdkVersion = "1.0.0"
        static let userDefaultsSuiteName = "com.ecompulse.analytics"
        static let optOutKey = "ecompulse_opt_out"
        static let userIdKey = "ecompulse_user_id"
    }
    
    // MARK: - Initialization
    
    private init(config: AnalyticsConfig) {
        self.config = config
        self.userDefaults = UserDefaults(suiteName: Constants.userDefaultsSuiteName) ?? .standard
        self.networkManager = NetworkManager(config: config)
        self.eventQueue = EventQueue(config: config, networkManager: networkManager)
        self.sessionManager = SessionManager(config: config, userDefaults: userDefaults)
        
        super.init()
        
        setupAutoTracking()
        startEventProcessor()
    }
    
    /**
     * Initialize the SDK with configuration
     */
    @objc public static func initialize(config: AnalyticsConfig) {
        guard shared == nil else {
            if config.enableLogging {
                print("[EComPulse] SDK already initialized")
            }
            return
        }
        
        shared = EComPulseAnalytics(config: config)
        shared?.markAsInitialized()
        
        if config.enableLogging {
            print("[EComPulse] Analytics SDK initialized successfully")
        }
    }
    
    private func markAsInitialized() {
        isInitialized.lock()
        initialized = true
        isInitialized.unlock()
    }
    
    private func checkInitialized() -> Bool {
        isInitialized.lock()
        let result = initialized
        isInitialized.unlock()
        return result
    }
    
    // MARK: - Event Tracking
    
    /**
     * Track a custom event
     */
    @objc public static func track(_ eventName: String, properties: [String: Any] = [:]) {
        guard let instance = shared, instance.checkInitialized() else {
            print("[EComPulse] Error: SDK not initialized. Call initialize() first.")
            return
        }
        
        instance.trackEvent(eventName, properties: properties)
    }
    
    private func trackEvent(_ eventName: String, properties: [String: Any]) {
        guard !isOptedOut() else {
            if config.enableLogging {
                print("[EComPulse] User opted out, skipping event: \(eventName)")
            }
            return
        }
        
        var eventProperties = properties
        eventProperties.merge(getCommonProperties()) { (_, new) in new }
        
        let event = AnalyticsEvent(
            eventName: eventName,
            properties: eventProperties,
            timestamp: Date().timeIntervalSince1970 * 1000,
            sessionId: sessionManager.currentSessionId,
            userId: getCurrentUserId()
        )
        
        eventQueue.enqueue(event)
        
        if config.enableLogging {
            print("[EComPulse] Event tracked: \(eventName)")
        }
    }
    
    // MARK: - E-commerce Events
    
    /**
     * Track product viewed event
     */
    @objc public static func trackProductViewed(_ productId: String, productData: [String: Any] = [:]) {
        var properties = productData
        properties["product_id"] = productId
        properties["event_category"] = "ecommerce"
        track("product_viewed", properties: properties)
    }
    
    /**
     * Track product added to cart
     */
    @objc public static func trackProductAdded(_ productId: String, cartData: [String: Any] = [:]) {
        var properties = cartData
        properties["product_id"] = productId
        properties["event_category"] = "ecommerce"
        track("product_added", properties: properties)
    }
    
    /**
     * Track purchase completed
     */
    @objc public static func trackPurchaseCompleted(_ orderData: [String: Any]) {
        var properties = orderData
        properties["event_category"] = "ecommerce"
        track("purchase_completed", properties: properties)
    }
    
    // MARK: - User Management
    
    /**
     * Set user properties
     */
    @objc public static func setUserProperties(_ properties: [String: Any]) {
        guard let instance = shared, instance.checkInitialized() else {
            print("[EComPulse] Error: SDK not initialized")
            return
        }
        
        properties.forEach { key, value in
            instance.setUserProperty(key, value: value)
        }
    }
    
    /**
     * Set single user property
     */
    @objc public static func setUserProperty(_ key: String, value: Any) {
        guard let instance = shared, instance.checkInitialized() else {
            print("[EComPulse] Error: SDK not initialized")
            return
        }
        
        instance.userDefaults.set(value, forKey: "user_prop_\(key)")
    }
    
    /**
     * Set user ID
     */
    @objc public static func setUserId(_ userId: String?) {
        guard let instance = shared, instance.checkInitialized() else {
            print("[EComPulse] Error: SDK not initialized")
            return
        }
        
        if let userId = userId {
            instance.userDefaults.set(userId, forKey: Constants.userIdKey)
        } else {
            instance.userDefaults.removeObject(forKey: Constants.userIdKey)
        }
    }
    
    private func getCurrentUserId() -> String? {
        return userDefaults.string(forKey: Constants.userIdKey)
    }
    
    // MARK: - Session Management
    
    /**
     * Start new session
     */
    @objc public static func startNewSession() {
        guard let instance = shared, instance.checkInitialized() else {
            print("[EComPulse] Error: SDK not initialized")
            return
        }
        
        instance.sessionManager.startNewSession()
        
        if instance.config.enableAutoTracking {
            instance.trackEvent("session_started", properties: [:])
        }
    }
    
    /**
     * End current session
     */
    @objc public static func endSession() {
        guard let instance = shared, instance.checkInitialized() else {
            return
        }
        
        if instance.config.enableAutoTracking && instance.sessionManager.currentSessionId != nil {
            instance.trackEvent("session_ended", properties: [
                "session_duration": instance.sessionManager.getSessionDuration()
            ])
        }
        
        instance.sessionManager.endSession()
    }
    
    /**
     * Get current session ID
     */
    @objc public static func getSessionId() -> String? {
        guard let instance = shared, instance.checkInitialized() else {
            return nil
        }
        
        return instance.sessionManager.currentSessionId
    }
    
    // MARK: - Privacy Controls
    
    /**
     * Opt user out of tracking
     */
    @objc public static func optOut() {
        guard let instance = shared, instance.checkInitialized() else {
            return
        }
        
        instance.userDefaults.set(true, forKey: Constants.optOutKey)
        instance.eventQueue.clear()
        
        if instance.config.enableLogging {
            print("[EComPulse] User opted out of tracking")
        }
    }
    
    /**
     * Opt user back in
     */
    @objc public static func optIn() {
        guard let instance = shared, instance.checkInitialized() else {
            return
        }
        
        instance.userDefaults.set(false, forKey: Constants.optOutKey)
        
        if instance.config.enableLogging {
            print("[EComPulse] User opted in to tracking")
        }
    }
    
    /**
     * Check if user is opted out
     */
    @objc public static func isOptedOut() -> Bool {
        guard let instance = shared, instance.checkInitialized() else {
            return false
        }
        
        return instance.isOptedOut()
    }
    
    private func isOptedOut() -> Bool {
        return userDefaults.bool(forKey: Constants.optOutKey)
    }
    
    /**
     * Delete all user data
     */
    @objc public static func deleteUserData() {
        guard let instance = shared, instance.checkInitialized() else {
            return
        }
        
        instance.userDefaults.removePersistentDomain(forName: Constants.userDefaultsSuiteName)
        instance.eventQueue.clear()
        instance.sessionManager.endSession()
        
        if instance.config.enableLogging {
            print("[EComPulse] All user data deleted")
        }
    }
    
    /**
     * Flush all pending events immediately
     */
    @objc public static func flush() {
        guard let instance = shared, instance.checkInitialized() else {
            return
        }
        
        instance.eventQueue.flush()
    }
    
    // MARK: - Private Methods
    
    private func setupAutoTracking() {
        guard config.enableAutoTracking else { return }
        
        // App lifecycle tracking
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        // Start initial session
        sessionManager.startNewSession()
        trackEvent("app_opened", properties: [:])
    }
    
    @objc private func appDidBecomeActive() {
        if sessionManager.shouldStartNewSession() {
            sessionManager.startNewSession()
            trackEvent("session_started", properties: [:])
        }
        trackEvent("app_foregrounded", properties: [:])
    }
    
    @objc private func appWillResignActive() {
        trackEvent("app_backgrounded", properties: [:])
    }
    
    @objc private func appDidEnterBackground() {
        sessionManager.updateLastActiveTime()
        eventQueue.flush()
    }
    
    private func startEventProcessor() {
        let timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(config.flushInterval / 1000), repeats: true) { _ in
            if !self.isOptedOut() {
                self.eventQueue.processBatch()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }
    
    private func getCommonProperties() -> [String: Any] {
        var properties: [String: Any] = [
            "sdk_version": Constants.sdkVersion,
            "platform": "ios",
            "app_version": getAppVersion(),
            "device_model": UIDevice.current.model,
            "os_version": UIDevice.current.systemVersion,
            "timestamp": Date().timeIntervalSince1970 * 1000
        ]
        
        // Add user properties
        if let suiteName = Constants.userDefaultsSuiteName,
           let suiteDefaults = UserDefaults(suiteName: suiteName) {
            for (key, value) in suiteDefaults.dictionaryRepresentation() {
                if key.hasPrefix("user_prop_") {
                    let propertyKey = String(key.dropFirst("user_prop_".count))
                    properties[propertyKey] = value
                }
            }
        }
        
        return properties
    }
    
    private func getAppVersion() -> String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }
}

// MARK: - Configuration Classes

/**
 * Analytics configuration class
 */
@objc public class AnalyticsConfig: NSObject {
    
    @objc public let apiKey: String
    @objc public let endpoint: String
    @objc public let environment: String
    @objc public let enableAutoTracking: Bool
    @objc public let enableOfflineSupport: Bool
    @objc public let batchSize: Int
    @objc public let flushInterval: Int64
    @objc public let maxQueueSize: Int
    @objc public let enableLogging: Bool
    @objc public let networkTimeout: TimeInterval
    
    private init(apiKey: String, endpoint: String, environment: String, 
                enableAutoTracking: Bool, enableOfflineSupport: Bool,
                batchSize: Int, flushInterval: Int64, maxQueueSize: Int,
                enableLogging: Bool, networkTimeout: TimeInterval) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.environment = environment
        self.enableAutoTracking = enableAutoTracking
        self.enableOfflineSupport = enableOfflineSupport
        self.batchSize = batchSize
        self.flushInterval = flushInterval
        self.maxQueueSize = maxQueueSize
        self.enableLogging = enableLogging
        self.networkTimeout = networkTimeout
        super.init()
    }
    
    @objc public static func builder() -> AnalyticsConfigBuilder {
        return AnalyticsConfigBuilder()
    }
}

/**
 * Builder for AnalyticsConfig
 */
@objc public class AnalyticsConfigBuilder: NSObject {
    
    private var apiKey: String = ""
    private var endpoint: String = ""
    private var environment: String = "production"
    private var enableAutoTracking: Bool = true
    private var enableOfflineSupport: Bool = true
    private var batchSize: Int = 20
    private var flushInterval: Int64 = 30000
    private var maxQueueSize: Int = 1000
    private var enableLogging: Bool = false
    private var networkTimeout: TimeInterval = 10.0
    
    @objc public func apiKey(_ apiKey: String) -> AnalyticsConfigBuilder {
        self.apiKey = apiKey
        return self
    }
    
    @objc public func endpoint(_ endpoint: String) -> AnalyticsConfigBuilder {
        self.endpoint = endpoint
        return self
    }
    
    @objc public func environment(_ environment: String) -> AnalyticsConfigBuilder {
        self.environment = environment
        return self
    }
    
    @objc public func enableAutoTracking(_ enable: Bool) -> AnalyticsConfigBuilder {
        self.enableAutoTracking = enable
        return self
    }
    
    @objc public func enableOfflineSupport(_ enable: Bool) -> AnalyticsConfigBuilder {
        self.enableOfflineSupport = enable
        return self
    }
    
    @objc public func batchSize(_ size: Int) -> AnalyticsConfigBuilder {
        self.batchSize = size
        return self
    }
    
    @objc public func flushInterval(_ interval: Int64) -> AnalyticsConfigBuilder {
        self.flushInterval = interval
        return self
    }
    
    @objc public func maxQueueSize(_ size: Int) -> AnalyticsConfigBuilder {
        self.maxQueueSize = size
        return self
    }
    
    @objc public func enableLogging(_ enable: Bool) -> AnalyticsConfigBuilder {
        self.enableLogging = enable
        return self
    }
    
    @objc public func networkTimeout(_ timeout: TimeInterval) -> AnalyticsConfigBuilder {
        self.networkTimeout = timeout
        return self
    }
    
    @objc public func build() -> AnalyticsConfig {
        guard !apiKey.isEmpty else {
            fatalError("API key is required")
        }
        
        guard !endpoint.isEmpty else {
            fatalError("Endpoint is required")
        }
        
        return AnalyticsConfig(
            apiKey: apiKey,
            endpoint: endpoint,
            environment: environment,
            enableAutoTracking: enableAutoTracking,
            enableOfflineSupport: enableOfflineSupport,
            batchSize: batchSize,
            flushInterval: flushInterval,
            maxQueueSize: maxQueueSize,
            enableLogging: enableLogging,
            networkTimeout: networkTimeout
        )
    }
}

// MARK: - Supporting Classes

/**
 * Analytics event structure
 */
struct AnalyticsEvent: Codable {
    let eventName: String
    let properties: [String: Any]
    let timestamp: TimeInterval
    let sessionId: String?
    let userId: String?
    
    enum CodingKeys: String, CodingKey {
        case eventName = "event_name"
        case properties
        case timestamp
        case sessionId = "session_id"
        case userId = "user_id"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(eventName, forKey: .eventName)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(sessionId, forKey: .sessionId)
        try container.encodeIfPresent(userId, forKey: .userId)
        
        // Encode properties
        var propsContainer = container.nestedContainer(keyedBy: DynamicKey.self, forKey: .properties)
        for (key, value) in properties {
            let dynamicKey = DynamicKey(stringValue: key)!
            if let stringValue = value as? String {
                try propsContainer.encode(stringValue, forKey: dynamicKey)
            } else if let intValue = value as? Int {
                try propsContainer.encode(intValue, forKey: dynamicKey)
            } else if let doubleValue = value as? Double {
                try propsContainer.encode(doubleValue, forKey: dynamicKey)
            } else if let boolValue = value as? Bool {
                try propsContainer.encode(boolValue, forKey: dynamicKey)
            }
        }
    }
}

struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    
    init?(stringValue: String) {
        self.stringValue = stringValue
    }
    
    init?(intValue: Int) {
        self.intValue = intValue
        self.stringValue = String(intValue)
    }
}
