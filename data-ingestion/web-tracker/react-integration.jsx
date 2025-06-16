// React integration example for E-ComPulse Tracker

import React, { useEffect, useState, useCallback } from 'react';
import { EComPulseTracker } from './ecompulse-tracker';

// Custom hook for E-ComPulse tracking
export const useEComPulseTracker = (config = {}) => {
    const [tracker, setTracker] = useState(null);
    const [isReady, setIsReady] = useState(false);

    useEffect(() => {
        const trackerInstance = new EComPulseTracker({
            kafkaRestProxy: process.env.REACT_APP_KAFKA_REST_PROXY,
            topic: process.env.REACT_APP_KAFKA_TOPIC || 'ecommerce-events',
            environment: process.env.NODE_ENV,
            autoTrack: true,
            debugMode: process.env.NODE_ENV === 'development',
            ...config
        });

        setTracker(trackerInstance);
        setIsReady(true);

        // Cleanup on unmount
        return () => {
            trackerInstance.flush(true);
        };
    }, []);

    const trackEvent = useCallback((eventType, properties) => {
        if (tracker) {
            tracker.trackEvent(eventType, properties);
        }
    }, [tracker]);

    const trackPageView = useCallback((properties) => {
        if (tracker) {
            tracker.trackPageView(properties);
        }
    }, [tracker]);

    const trackProductView = useCallback((productId, properties) => {
        if (tracker) {
            tracker.trackProductView(productId, properties);
        }
    }, [tracker]);

    const trackAddToCart = useCallback((productId, properties) => {
        if (tracker) {
            tracker.trackAddToCart(productId, properties);
        }
    }, [tracker]);

    const trackPurchase = useCallback((orderId, properties) => {
        if (tracker) {
            tracker.trackPurchase(orderId, properties);
        }
    }, [tracker]);

    return {
        tracker,
        isReady,
        trackEvent,
        trackPageView,
        trackProductView,
        trackAddToCart,
        trackPurchase
    };
};

// Higher-order component for automatic page tracking
export const withEComPulseTracking = (WrappedComponent, options = {}) => {
    return function TrackedComponent(props) {
        const { trackPageView } = useEComPulseTracker();

        useEffect(() => {
            trackPageView({
                component_name: WrappedComponent.name,
                ...options.pageProperties
            });
        }, [trackPageView]);

        return <WrappedComponent {...props} />;
    };
};

// Context for sharing tracker across components
export const EComPulseContext = React.createContext(null);

export const EComPulseProvider = ({ children, config = {} }) => {
    const trackerData = useEComPulseTracker(config);

    return (
        <EComPulseContext.Provider value={trackerData}>
            {children}
        </EComPulseContext.Provider>
    );
};

export const useEComPulseContext = () => {
    const context = React.useContext(EComPulseContext);
    if (!context) {
        throw new Error('useEComPulseContext must be used within an EComPulseProvider');
    }
    return context;
};

// Example usage components

// Product component with automatic tracking
export const ProductCard = ({ product, onAddToCart }) => {
    const { trackProductView, trackAddToCart } = useEComPulseContext();

    useEffect(() => {
        trackProductView(product.id, {
            product_name: product.name,
            product_category: product.category,
            price: product.price,
            currency: product.currency,
            brand: product.brand
        });
    }, [product, trackProductView]);

    const handleAddToCart = () => {
        trackAddToCart(product.id, {
            product_name: product.name,
            product_category: product.category,
            price: product.price,
            quantity: 1,
            currency: product.currency
        });
        onAddToCart(product);
    };

    return (
        <div className="product-card">
            <img src={product.image} alt={product.name} />
            <h3>{product.name}</h3>
            <p>${product.price}</p>
            <button onClick={handleAddToCart}>Add to Cart</button>
        </div>
    );
};

// Shopping cart component
export const ShoppingCart = ({ items, onCheckout }) => {
    const { trackEvent, trackPurchase } = useEComPulseContext();

    const handleCheckoutStart = () => {
        trackEvent('checkout_started', {
            cart_total: items.reduce((total, item) => total + item.price * item.quantity, 0),
            item_count: items.length,
            items: items.map(item => ({
                product_id: item.id,
                quantity: item.quantity,
                price: item.price
            }))
        });
        onCheckout();
    };

    const handlePurchaseComplete = (orderId) => {
        const totalAmount = items.reduce((total, item) => total + item.price * item.quantity, 0);
        
        trackPurchase(orderId, {
            total_amount: totalAmount,
            currency: 'USD',
            items: items.map(item => ({
                product_id: item.id,
                product_name: item.name,
                quantity: item.quantity,
                price: item.price
            })),
            payment_method: 'credit_card',
            item_count: items.length
        });
    };

    return (
        <div className="shopping-cart">
            <h2>Shopping Cart</h2>
            {items.map(item => (
                <div key={item.id} className="cart-item">
                    <span>{item.name}</span>
                    <span>Qty: {item.quantity}</span>
                    <span>${item.price}</span>
                </div>
            ))}
            <button onClick={handleCheckoutStart}>
                Checkout (${items.reduce((total, item) => total + item.price * item.quantity, 0)})
            </button>
        </div>
    );
};

// App component with provider
export const App = () => {
    return (
        <EComPulseProvider config={{
            userId: localStorage.getItem('user_id'),
            environment: process.env.NODE_ENV
        }}>
            <div className="app">
                <Header />
                <ProductListing />
                <ShoppingCart />
            </div>
        </EComPulseProvider>
    );
};
