import Foundation

/**
 * Network manager for handling HTTP requests
 */
class NetworkManager {
    
    private let config: AnalyticsConfig
    private let session: URLSession
    
    init(config: AnalyticsConfig) {
        self.config = config
        
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = config.networkTimeout
        configuration.timeoutIntervalForResource = config.networkTimeout * 2
        
        self.session = URLSession(configuration: configuration)
    }
    
    func sendEvents(_ events: [AnalyticsEvent], completion: @escaping (Result<Void, Error>) -> Void) {
        guard let url = URL(string: "\(config.endpoint)/events") else {
            completion(.failure(NetworkError.invalidURL))
            return
        }
        
        let payload: [String: Any] = [
            "events": events.map { event in
                return [
                    "event_name": event.eventName,
                    "properties": event.properties,
                    "timestamp": event.timestamp,
                    "session_id": event.sessionId as Any,
                    "user_id": event.userId as Any
                ]
            },
            "api_key": config.apiKey,
            "environment": config.environment
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: payload)
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = jsonData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("EComPulse-iOS-SDK/1.0.0", forHTTPHeaderField: "User-Agent")
            
            let task = session.dataTask(with: request) { data, response, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                        completion(.success(()))
                    } else {
                        completion(.failure(NetworkError.httpError(httpResponse.statusCode)))
                    }
                } else {
                    completion(.failure(NetworkError.invalidResponse))
                }
            }
            
            task.resume()
            
        } catch {
            completion(.failure(error))
        }
    }
}

/**
 * Network error types
 */
enum NetworkError: Error {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case serializationError
}

/**
 * Event queue for batching and offline support
 */
class EventQueue {
    
    private let config: AnalyticsConfig
    private let networkManager: NetworkManager
    private var queue: [AnalyticsEvent] = []
    private let queueLock = NSLock()
    private let fileManager = FileManager.default
    private let queueFileURL: URL
    
    init(config: AnalyticsConfig, networkManager: NetworkManager) {
        self.config = config
        self.networkManager = networkManager
        
        // Setup persistent storage
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.queueFileURL = documentsPath.appendingPathComponent("ecompulse_event_queue.json")
        
        loadPersistedEvents()
    }
    
    func enqueue(_ event: AnalyticsEvent) {
        queueLock.lock()
        defer { queueLock.unlock() }
        
        if queue.count >= config.maxQueueSize {
            queue.removeFirst() // Remove oldest event
        }
        
        queue.append(event)
        
        if config.enableOfflineSupport {
            persistEvents()
        }
    }
    
    func processBatch() {
        queueLock.lock()
        
        guard !queue.isEmpty else {
            queueLock.unlock()
            return
        }
        
        let batchSize = min(config.batchSize, queue.count)
        let batch = Array(queue.prefix(batchSize))
        
        queueLock.unlock()
        
        networkManager.sendEvents(batch) { [weak self] result in
            switch result {
            case .success:
                self?.removeSentEvents(count: batch.count)
                if self?.config.enableLogging == true {
                    print("[EComPulse] Batch sent successfully: \(batch.count) events")
                }
                
            case .failure(let error):
                if self?.config.enableLogging == true {
                    print("[EComPulse] Failed to send batch: \(error)")
                }
            }
        }
    }
    
    func flush() {
        while !queue.isEmpty {
            processBatch()
            Thread.sleep(forTimeInterval: 0.1) // Small delay between batches
        }
    }
    
    func clear() {
        queueLock.lock()
        queue.removeAll()
        queueLock.unlock()
        
        try? fileManager.removeItem(at: queueFileURL)
    }
    
    private func removeSentEvents(count: Int) {
        queueLock.lock()
        defer { queueLock.unlock() }
        
        queue.removeFirst(min(count, queue.count))
        
        if config.enableOfflineSupport {
            persistEvents()
        }
    }
    
    private func persistEvents() {
        do {
            let data = try JSONEncoder().encode(queue)
            try data.write(to: queueFileURL)
        } catch {
            if config.enableLogging {
                print("[EComPulse] Failed to persist events: \(error)")
            }
        }
    }
    
    private func loadPersistedEvents() {
        guard config.enableOfflineSupport,
              fileManager.fileExists(atPath: queueFileURL.path) else {
            return
        }
        
        do {
            let data = try Data(contentsOf: queueFileURL)
            queue = try JSONDecoder().decode([AnalyticsEvent].self, from: data)
            
            if config.enableLogging {
                print("[EComPulse] Loaded \(queue.count) persisted events")
            }
        } catch {
            if config.enableLogging {
                print("[EComPulse] Failed to load persisted events: \(error)")
            }
        }
    }
}

/**
 * Session manager for handling user sessions
 */
class SessionManager {
    
    private let config: AnalyticsConfig
    private let userDefaults: UserDefaults
    private let sessionTimeout: TimeInterval = 24 * 60 * 60 // 24 hours
    
    private struct Keys {
        static let sessionId = "ecompulse_session_id"
        static let sessionStartTime = "ecompulse_session_start_time"
        static let lastActiveTime = "ecompulse_last_active_time"
    }
    
    var currentSessionId: String? {
        return userDefaults.string(forKey: Keys.sessionId)
    }
    
    init(config: AnalyticsConfig, userDefaults: UserDefaults) {
        self.config = config
        self.userDefaults = userDefaults
        
        restoreSessionIfValid()
    }
    
    func startNewSession() {
        let sessionId = generateSessionId()
        let now = Date().timeIntervalSince1970
        
        userDefaults.set(sessionId, forKey: Keys.sessionId)
        userDefaults.set(now, forKey: Keys.sessionStartTime)
        userDefaults.set(now, forKey: Keys.lastActiveTime)
        
        if config.enableLogging {
            print("[EComPulse] New session started: \(sessionId)")
        }
    }
    
    func endSession() {
        userDefaults.removeObject(forKey: Keys.sessionId)
        userDefaults.removeObject(forKey: Keys.sessionStartTime)
        userDefaults.removeObject(forKey: Keys.lastActiveTime)
        
        if config.enableLogging {
            print("[EComPulse] Session ended")
        }
    }
    
    func updateLastActiveTime() {
        userDefaults.set(Date().timeIntervalSince1970, forKey: Keys.lastActiveTime)
    }
    
    func shouldStartNewSession() -> Bool {
        guard let lastActiveTime = userDefaults.object(forKey: Keys.lastActiveTime) as? TimeInterval else {
            return true
        }
        
        let timeSinceLastActive = Date().timeIntervalSince1970 - lastActiveTime
        return timeSinceLastActive > sessionTimeout
    }
    
    func getSessionDuration() -> TimeInterval {
        guard let startTime = userDefaults.object(forKey: Keys.sessionStartTime) as? TimeInterval else {
            return 0
        }
        
        return Date().timeIntervalSince1970 - startTime
    }
    
    private func restoreSessionIfValid() {
        guard currentSessionId != nil else {
            return // No existing session
        }
        
        if shouldStartNewSession() {
            endSession()
        }
    }
    
    private func generateSessionId() -> String {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let random = Int.random(in: 1000...9999)
        return "session_\(timestamp)_\(random)"
    }
}
