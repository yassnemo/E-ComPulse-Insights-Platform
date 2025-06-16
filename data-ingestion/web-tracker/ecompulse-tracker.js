/**
 * E-ComPulse Web Tracker SDK
 * 
 * A comprehensive JavaScript SDK for tracking e-commerce events on web applications.
 * Supports React, Angular, Vue.js, and vanilla JavaScript implementations.
 * 
 * Features:
 * - Automatic page view tracking
 * - E-commerce event tracking (product views, cart actions, purchases)
 * - Session management
 * - Offline support with event queuing
 * - Privacy compliance (GDPR, CCPA)
 * - Real-time event delivery via Kafka REST Proxy
 */

class EComPulseTracker {
    constructor(config = {}) {
        this.config = {
            kafkaRestProxy: config.kafkaRestProxy || 'https://kafka-proxy.ecompulse.com',
            topic: config.topic || 'ecommerce-events',
            userId: config.userId || this.generateUserId(),
            sessionId: this.generateSessionId(),
            source: 'web',
            environment: config.environment || 'prod',
            autoTrack: config.autoTrack !== false, // Default to true
            batchSize: config.batchSize || 10,
            flushInterval: config.flushInterval || 5000, // 5 seconds
            retryAttempts: config.retryAttempts || 3,
            privacyMode: config.privacyMode || false,
            debugMode: config.debugMode || false,
            ...config
        };

        this.eventQueue = [];
        this.isOnline = navigator.onLine;
        this.sessionStartTime = Date.now();
        this.lastActivity = Date.now();
        
        this.init();
    }

    init() {
        this.log('Initializing E-ComPulse Tracker', this.config);
        
        // Set up session management
        this.setupSessionManagement();
        
        // Set up automatic tracking if enabled
        if (this.config.autoTrack) {
            this.setupAutoTracking();
        }
        
        // Set up event flushing
        this.setupEventFlushing();
        
        // Set up offline/online detection
        this.setupConnectivityDetection();
        
        // Set up privacy controls
        this.setupPrivacyControls();
        
        // Track initial page view
        if (this.config.autoTrack) {
            this.trackPageView();
        }
    }

    generateUserId() {
        // Generate or retrieve persistent user ID
        let userId = localStorage.getItem('ecompulse_user_id');
        if (!userId) {
            userId = 'user_' + this.generateUUID();
            localStorage.setItem('ecompulse_user_id', userId);
        }
        return userId;
    }

    generateSessionId() {
        return 'session_' + this.generateUUID();
    }

    generateUUID() {
        return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
            const r = Math.random() * 16 | 0;
            const v = c === 'x' ? r : (r & 0x3 | 0x8);
            return v.toString(16);
        });
    }

    setupSessionManagement() {
        // Session timeout: 30 minutes of inactivity
        this.sessionTimeout = 30 * 60 * 1000;
        
        // Track user activity
        const activityEvents = ['click', 'scroll', 'keypress', 'mousemove'];
        activityEvents.forEach(event => {
            document.addEventListener(event, () => {
                this.updateLastActivity();
            }, { passive: true });
        });

        // Check session validity periodically
        setInterval(() => {
            this.checkSessionValidity();
        }, 60000); // Check every minute
    }

    updateLastActivity() {
        this.lastActivity = Date.now();
    }

    checkSessionValidity() {
        const timeSinceLastActivity = Date.now() - this.lastActivity;
        if (timeSinceLastActivity > this.sessionTimeout) {
            // Start new session
            this.config.sessionId = this.generateSessionId();
            this.sessionStartTime = Date.now();
            this.lastActivity = Date.now();
            this.log('New session started due to inactivity');
        }
    }

    setupAutoTracking() {
        // Auto-track page changes in SPAs
        this.setupSPATracking();
        
        // Auto-track form submissions
        this.setupFormTracking();
        
        // Auto-track link clicks
        this.setupLinkTracking();
    }

    setupSPATracking() {
        // Override history methods for SPA tracking
        const originalPushState = history.pushState;
        const originalReplaceState = history.replaceState;
        
        history.pushState = (...args) => {
            originalPushState.apply(history, args);
            setTimeout(() => this.trackPageView(), 100);
        };
        
        history.replaceState = (...args) => {
            originalReplaceState.apply(history, args);
            setTimeout(() => this.trackPageView(), 100);
        };
        
        // Listen for popstate events
        window.addEventListener('popstate', () => {
            setTimeout(() => this.trackPageView(), 100);
        });
    }

    setupFormTracking() {
        document.addEventListener('submit', (event) => {
            const form = event.target;
            if (form.tagName === 'FORM') {
                this.trackEvent('form_submit', {
                    form_id: form.id || 'unknown',
                    form_name: form.name || 'unknown',
                    page_url: window.location.href
                });
            }
        });
    }

    setupLinkTracking() {
        document.addEventListener('click', (event) => {
            const link = event.target.closest('a');
            if (link && link.href) {
                this.trackEvent('link_click', {
                    link_url: link.href,
                    link_text: link.textContent?.trim() || '',
                    page_url: window.location.href
                });
            }
        });
    }

    setupEventFlushing() {
        // Flush events periodically
        setInterval(() => {
            this.flush();
        }, this.config.flushInterval);

        // Flush events before page unload
        window.addEventListener('beforeunload', () => {
            this.flush(true); // Synchronous flush
        });

        // Flush events when page becomes hidden
        document.addEventListener('visibilitychange', () => {
            if (document.hidden) {
                this.flush();
            }
        });
    }

    setupConnectivityDetection() {
        window.addEventListener('online', () => {
            this.isOnline = true;
            this.log('Connection restored, flushing queued events');
            this.flush();
        });

        window.addEventListener('offline', () => {
            this.isOnline = false;
            this.log('Connection lost, events will be queued');
        });
    }

    setupPrivacyControls() {
        // Check for Do Not Track
        if (navigator.doNotTrack === '1' || this.config.privacyMode) {
            this.log('Privacy mode enabled, tracking disabled');
            this.privacyMode = true;
        }
    }

    // Public API Methods

    trackPageView(properties = {}) {
        const event = this.createEvent('page_view', {
            page_url: window.location.href,
            page_title: document.title,
            referrer: document.referrer,
            viewport_size: `${window.innerWidth}x${window.innerHeight}`,
            ...properties
        });
        
        this.queueEvent(event);
    }

    trackProductView(productId, properties = {}) {
        const event = this.createEvent('product_view', {
            product_id: productId,
            page_url: window.location.href,
            ...properties
        });
        
        this.queueEvent(event);
    }

    trackAddToCart(productId, properties = {}) {
        const event = this.createEvent('add_to_cart', {
            product_id: productId,
            page_url: window.location.href,
            ...properties
        });
        
        this.queueEvent(event);
    }

    trackRemoveFromCart(productId, properties = {}) {
        const event = this.createEvent('remove_from_cart', {
            product_id: productId,
            page_url: window.location.href,
            ...properties
        });
        
        this.queueEvent(event);
    }

    trackPurchase(orderId, properties = {}) {
        const event = this.createEvent('purchase', {
            order_id: orderId,
            page_url: window.location.href,
            ...properties
        });
        
        this.queueEvent(event);
    }

    trackEvent(eventType, properties = {}) {
        const event = this.createEvent(eventType, {
            page_url: window.location.href,
            ...properties
        });
        
        this.queueEvent(event);
    }

    // Core Methods

    createEvent(eventType, properties = {}) {
        return {
            event_id: this.generateUUID(),
            event_type: eventType,
            timestamp: new Date().toISOString(),
            user_id: this.config.userId,
            session_id: this.config.sessionId,
            source: this.config.source,
            properties: {
                user_agent: navigator.userAgent,
                ip_address: null, // Will be filled by server
                ...properties
            },
            metadata: {
                sdk_version: '1.0.0',
                platform: 'web',
                environment: this.config.environment,
                session_start_time: new Date(this.sessionStartTime).toISOString()
            }
        };
    }

    queueEvent(event) {
        if (this.privacyMode) {
            this.log('Event blocked by privacy mode', event);
            return;
        }

        this.eventQueue.push(event);
        this.log('Event queued', event);

        // Auto-flush if batch size reached
        if (this.eventQueue.length >= this.config.batchSize) {
            this.flush();
        }
    }

    async flush(synchronous = false) {
        if (this.eventQueue.length === 0) {
            return;
        }

        const events = [...this.eventQueue];
        this.eventQueue = [];

        this.log('Flushing events', { count: events.length, synchronous });

        if (synchronous) {
            this.sendEventsSync(events);
        } else {
            await this.sendEventsAsync(events);
        }
    }

    async sendEventsAsync(events) {
        if (!this.isOnline) {
            this.log('Offline, re-queuing events');
            this.eventQueue.unshift(...events);
            return;
        }

        try {
            const response = await fetch(`${this.config.kafkaRestProxy}/topics/${this.config.topic}`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/vnd.kafka.json.v2+json',
                    'Accept': 'application/vnd.kafka.v2+json'
                },
                body: JSON.stringify({
                    records: events.map(event => ({
                        key: event.user_id,
                        value: event
                    }))
                })
            });

            if (!response.ok) {
                throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }

            this.log('Events sent successfully', { count: events.length });
        } catch (error) {
            this.log('Failed to send events', { error: error.message, count: events.length });
            
            // Re-queue events for retry
            this.eventQueue.unshift(...events);
        }
    }

    sendEventsSync(events) {
        // Use sendBeacon for synchronous sending (e.g., on page unload)
        const payload = JSON.stringify({
            records: events.map(event => ({
                key: event.user_id,
                value: event
            }))
        });

        const success = navigator.sendBeacon(
            `${this.config.kafkaRestProxy}/topics/${this.config.topic}`,
            payload
        );

        if (success) {
            this.log('Events sent synchronously', { count: events.length });
        } else {
            this.log('Failed to send events synchronously', { count: events.length });
        }
    }

    // Utility Methods

    setUserId(userId) {
        this.config.userId = userId;
        localStorage.setItem('ecompulse_user_id', userId);
        this.log('User ID updated', { userId });
    }

    getUserId() {
        return this.config.userId;
    }

    getSessionId() {
        return this.config.sessionId;
    }

    enablePrivacyMode() {
        this.privacyMode = true;
        this.eventQueue = []; // Clear any queued events
        this.log('Privacy mode enabled');
    }

    disablePrivacyMode() {
        this.privacyMode = false;
        this.log('Privacy mode disabled');
    }

    log(message, data = {}) {
        if (this.config.debugMode) {
            console.log(`[E-ComPulse] ${message}`, data);
        }
    }
}

// React Hook for easy integration
function useEComPulseTracker(config = {}) {
    const [tracker, setTracker] = React.useState(null);

    React.useEffect(() => {
        const trackerInstance = new EComPulseTracker(config);
        setTracker(trackerInstance);
        
        return () => {
            trackerInstance.flush(true);
        };
    }, []);

    return tracker;
}

// Export for different module systems
if (typeof module !== 'undefined' && module.exports) {
    module.exports = { EComPulseTracker, useEComPulseTracker };
} else if (typeof window !== 'undefined') {
    window.EComPulseTracker = EComPulseTracker;
    if (typeof React !== 'undefined') {
        window.useEComPulseTracker = useEComPulseTracker;
    }
}

// AMD support
if (typeof define === 'function' && define.amd) {
    define([], function() {
        return { EComPulseTracker, useEComPulseTracker };
    });
}
