# E-ComPulse Mobile SDK

## Overview

The E-ComPulse Mobile SDK provides seamless event tracking capabilities for both Android and iOS applications. It automatically collects user interactions, app lifecycle events, and custom business events with offline support and intelligent batching.

## Features

- 🚀 **Real-time Event Tracking**: Instant event collection and transmission
- 📱 **Cross-Platform**: Native support for Android (Kotlin/Java) and iOS (Swift/Objective-C)
- 🔄 **Offline Support**: Local storage with automatic sync when connectivity resumes
- 📊 **Automatic Events**: App lifecycle, screen views, crashes, and performance metrics
- 🎯 **Custom Events**: Business-specific event tracking with custom properties
- 🔒 **Privacy First**: GDPR/CCPA compliant with configurable data collection
- 📈 **Performance Optimized**: Minimal battery and CPU impact
- 🛡️ **Error Handling**: Robust error handling with retry mechanisms

## Architecture

```
Mobile App
    ↓
SDK Event Collector
    ↓
Local SQLite Queue
    ↓
HTTP/Kafka REST Proxy
    ↓
Apache Kafka
```

## Installation

### Android (Kotlin)

Add to your `build.gradle` (Module: app):

```gradle
dependencies {
    implementation 'com.ecompulse:analytics-android:1.0.0'
}
```

### iOS (Swift)

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/ecompulse/analytics-ios", from: "1.0.0")
]
```

Or via CocoaPods in `Podfile`:

```ruby
pod 'EComPulseAnalytics', '~> 1.0.0'
```

## Quick Start

### Android Implementation

```kotlin
// Initialize in Application class
class MyApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        
        EComPulseAnalytics.initialize(
            context = this,
            config = AnalyticsConfig.Builder()
                .apiKey("your-api-key")
                .endpoint("https://your-kafka-proxy.com")
                .environment("production")
                .enableAutoTracking(true)
                .enableOfflineSupport(true)
                .batchSize(20)
                .flushInterval(30000) // 30 seconds
                .build()
        )
    }
}

// Track events in activities/fragments
class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Track custom events
        EComPulseAnalytics.track("product_viewed", mapOf(
            "product_id" to "12345",
            "category" to "electronics",
            "price" to 299.99,
            "currency" to "USD"
        ))
    }
}
```

### iOS Implementation

```swift
// Initialize in AppDelegate
import EComPulseAnalytics

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, 
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        let config = AnalyticsConfig.builder()
            .apiKey("your-api-key")
            .endpoint("https://your-kafka-proxy.com")
            .environment("production")
            .enableAutoTracking(true)
            .enableOfflineSupport(true)
            .batchSize(20)
            .flushInterval(30)
            .build()
            
        EComPulseAnalytics.initialize(config: config)
        return true
    }
}

// Track events in view controllers
class ProductViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Track custom events
        EComPulseAnalytics.track("product_viewed", properties: [
            "product_id": "12345",
            "category": "electronics",
            "price": 299.99,
            "currency": "USD"
        ])
    }
}
```

## Event Types

### Automatic Events

The SDK automatically tracks these events:

- `app_opened` - App startup
- `app_backgrounded` - App goes to background
- `app_foregrounded` - App returns to foreground
- `screen_viewed` - Screen/Activity transitions
- `app_crashed` - Application crashes
- `session_started` - New user session
- `session_ended` - Session completion

### E-commerce Events

Pre-defined e-commerce events with standardized schemas:

```kotlin
// Product events
EComPulseAnalytics.trackProductViewed("product_id", productData)
EComPulseAnalytics.trackProductAdded("product_id", cartData)
EComPulseAnalytics.trackProductRemoved("product_id", cartData)

// Purchase events
EComPulseAnalytics.trackPurchaseStarted(orderData)
EComPulseAnalytics.trackPurchaseCompleted(orderData)
EComPulseAnalytics.trackPurchaseFailed(orderData, errorReason)

// User events
EComPulseAnalytics.trackUserRegistered(userData)
EComPulseAnalytics.trackUserLoggedIn(userData)
EComPulseAnalytics.trackUserLoggedOut()
```

## Configuration Options

| Option | Description | Default |
|--------|-------------|---------|
| `apiKey` | Your E-ComPulse API key | Required |
| `endpoint` | Kafka REST Proxy endpoint | Required |
| `environment` | Environment (dev/staging/prod) | "production" |
| `enableAutoTracking` | Auto-track app lifecycle events | true |
| `enableOfflineSupport` | Store events offline | true |
| `batchSize` | Events per batch | 20 |
| `flushInterval` | Batch upload interval (ms) | 30000 |
| `maxQueueSize` | Max offline events | 1000 |
| `enableLogging` | Debug logging | false |

## Privacy & Compliance

### GDPR Compliance

```kotlin
// Opt user out of tracking
EComPulseAnalytics.optOut()

// Opt user back in
EComPulseAnalytics.optIn()

// Check opt-out status
val isOptedOut = EComPulseAnalytics.isOptedOut()

// Delete all user data
EComPulseAnalytics.deleteUserData()
```

### Data Collection Control

```kotlin
// Disable specific automatic events
val config = AnalyticsConfig.Builder()
    .disableAutoEvent(AutoEvent.SCREEN_VIEWED)
    .disableAutoEvent(AutoEvent.APP_CRASHED)
    .build()
```

## Advanced Usage

### Custom User Properties

```kotlin
// Set user properties
EComPulseAnalytics.setUserProperties(mapOf(
    "user_id" to "12345",
    "email" to "user@example.com",
    "subscription_tier" to "premium",
    "registration_date" to "2024-01-15"
))

// Set single property
EComPulseAnalytics.setUserProperty("last_purchase_date", "2024-01-20")
```

### Session Management

```kotlin
// Manual session control
EComPulseAnalytics.startSession()
EComPulseAnalytics.endSession()

// Get current session ID
val sessionId = EComPulseAnalytics.getSessionId()
```

### Performance Monitoring

```kotlin
// Track custom timing events
val timer = EComPulseAnalytics.startTimer("api_call")
// ... perform operation
timer.end(mapOf("endpoint" to "/api/products"))

// Track app performance
EComPulseAnalytics.trackPerformance("screen_load_time", 1250, mapOf(
    "screen_name" to "ProductList"
))
```

## Testing

### Debug Mode

```kotlin
// Enable debug logging
val config = AnalyticsConfig.Builder()
    .enableLogging(true)
    .endpoint("https://debug-proxy.com")
    .build()

// Validate events before sending
EComPulseAnalytics.setEventValidator { event ->
    // Custom validation logic
    event.properties.containsKey("required_field")
}
```

### Mock Testing

```kotlin
// Use mock endpoint for testing
val config = AnalyticsConfig.Builder()
    .endpoint("https://mock-api.com")
    .enableLogging(true)
    .build()
```

## Error Handling

The SDK includes comprehensive error handling:

- **Network Errors**: Automatic retry with exponential backoff
- **Validation Errors**: Invalid events are logged and discarded
- **Storage Errors**: Graceful degradation when local storage fails
- **Crash Protection**: SDK errors won't crash your app

## Performance Considerations

- **Minimal Impact**: <1% CPU usage, <5MB memory footprint
- **Battery Optimized**: Intelligent batching and networking
- **Background Processing**: Non-blocking event collection
- **Efficient Storage**: Compressed SQLite storage for offline events

## Support

For technical support and questions:
- 📧 Email: sdk-support@ecompulse.com
- 📚 Documentation: https://docs.ecompulse.com/mobile-sdk
- 🐛 Issues: https://github.com/ecompulse/mobile-sdk/issues
