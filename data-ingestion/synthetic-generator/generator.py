"""
E-Commerce Synthetic Event Generator

A high-performance synthetic data generator that creates realistic e-commerce events
for testing, development, and demonstration purposes. Capable of generating up to
200,000 events per minute with configurable event types and user behaviors.

Features:
- Realistic user session simulation
- Multiple event types (page views, purchases, cart actions)
- Configurable event rates and patterns
- Kafka producer with retry logic and error handling
- Prometheus metrics for monitoring
- Feature flag support for seamless data source transitions
"""

import asyncio
import json
import logging
import os
import random
import time
import uuid
from datetime import datetime, timedelta
from typing import Dict, List, Optional
from dataclasses import dataclass, asdict
from concurrent.futures import ThreadPoolExecutor

import aiohttp
import boto3
from confluent_kafka import Producer
from faker import Faker
from prometheus_client import Counter, Histogram, Gauge, start_http_server
import redis
import structlog

# Configure structured logging
structlog.configure(
    processors=[
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.add_log_level,
        structlog.processors.JSONRenderer()
    ],
    wrapper_class=structlog.make_filtering_bound_logger(logging.INFO),
    logger_factory=structlog.PrintLoggerFactory(),
    context_class=dict,
    cache_logger_on_first_use=True
)

logger = structlog.get_logger()

# Prometheus metrics
EVENTS_GENERATED = Counter('events_generated_total', 'Total events generated', ['event_type', 'source'])
EVENT_GENERATION_TIME = Histogram('event_generation_seconds', 'Time spent generating events')
KAFKA_SEND_TIME = Histogram('kafka_send_seconds', 'Time spent sending to Kafka')
ACTIVE_SESSIONS = Gauge('active_sessions', 'Number of active user sessions')
CURRENT_RATE = Gauge('current_event_rate', 'Current event generation rate per minute')

@dataclass
class ECommerceEvent:
    """E-commerce event data structure"""
    event_id: str
    event_type: str
    timestamp: str
    user_id: str
    session_id: str
    source: str = "synthetic"
    properties: Dict = None
    metadata: Dict = None

    def __post_init__(self):
        if self.properties is None:
            self.properties = {}
        if self.metadata is None:
            self.metadata = {}

class UserSession:
    """Simulates a realistic user session with state"""
    
    def __init__(self, user_id: str, faker: Faker):
        self.user_id = user_id
        self.session_id = str(uuid.uuid4())
        self.faker = faker
        self.start_time = datetime.utcnow()
        self.last_activity = self.start_time
        self.page_views = 0
        self.cart_items = []
        self.current_category = random.choice([
            'electronics', 'clothing', 'books', 'home', 'sports', 'beauty'
        ])
        self.is_returning_user = random.choice([True, False])
        self.session_duration = random.randint(60, 3600)  # 1 min to 1 hour
        
    def is_expired(self) -> bool:
        """Check if session has expired"""
        elapsed = (datetime.utcnow() - self.start_time).total_seconds()
        return elapsed > self.session_duration
    
    def get_next_event(self) -> Optional[ECommerceEvent]:
        """Generate the next event for this session"""
        if self.is_expired():
            return None
            
        # Update last activity
        self.last_activity = datetime.utcnow()
        
        # Determine next event type based on session state
        event_type = self._choose_event_type()
        
        if event_type == "page_view":
            return self._generate_page_view()
        elif event_type == "product_view":
            return self._generate_product_view()
        elif event_type == "add_to_cart":
            return self._generate_add_to_cart()
        elif event_type == "remove_from_cart":
            return self._generate_remove_from_cart()
        elif event_type == "purchase":
            return self._generate_purchase()
        
        return None
    
    def _choose_event_type(self) -> str:
        """Choose next event type based on user behavior patterns"""
        # Higher probability of page views early in session
        if self.page_views < 3:
            return "page_view"
        
        # Cart-related actions if items in cart
        if self.cart_items:
            return random.choices(
                ["page_view", "product_view", "add_to_cart", "remove_from_cart", "purchase"],
                weights=[30, 25, 15, 10, 20]
            )[0]
        else:
            return random.choices(
                ["page_view", "product_view", "add_to_cart"],
                weights=[40, 40, 20]
            )[0]
    
    def _generate_page_view(self) -> ECommerceEvent:
        """Generate a page view event"""
        self.page_views += 1
        
        pages = [
            "/", "/products", f"/category/{self.current_category}",
            "/search", "/account", "/cart", "/checkout"
        ]
        
        return ECommerceEvent(
            event_id=str(uuid.uuid4()),
            event_type="page_view",
            timestamp=datetime.utcnow().isoformat() + "Z",
            user_id=self.user_id,
            session_id=self.session_id,
            properties={
                "page_url": random.choice(pages),
                "referrer": self.faker.url() if random.random() < 0.3 else None,
                "user_agent": self.faker.user_agent(),
                "ip_address": self.faker.ipv4(),
                "viewport_size": f"{random.choice([1920, 1366, 1440])}x{random.choice([1080, 768, 900])}"
            },
            metadata={
                "sdk_version": "1.0.0",
                "platform": "web",
                "environment": os.getenv("ENVIRONMENT", "prod")
            }
        )
    
    def _generate_product_view(self) -> ECommerceEvent:
        """Generate a product view event"""
        product_id = str(uuid.uuid4())
        price = round(random.uniform(10.0, 500.0), 2)
        
        return ECommerceEvent(
            event_id=str(uuid.uuid4()),
            event_type="product_view",
            timestamp=datetime.utcnow().isoformat() + "Z",
            user_id=self.user_id,
            session_id=self.session_id,
            properties={
                "product_id": product_id,
                "product_name": self.faker.catch_phrase(),
                "product_category": self.current_category,
                "price": price,
                "currency": "USD",
                "brand": self.faker.company(),
                "page_url": f"/product/{product_id}",
                "user_agent": self.faker.user_agent(),
                "ip_address": self.faker.ipv4()
            },
            metadata={
                "sdk_version": "1.0.0",
                "platform": "web",
                "environment": os.getenv("ENVIRONMENT", "prod")
            }
        )
    
    def _generate_add_to_cart(self) -> ECommerceEvent:
        """Generate an add to cart event"""
        product_id = str(uuid.uuid4())
        price = round(random.uniform(10.0, 500.0), 2)
        quantity = random.randint(1, 3)
        
        # Add to session cart
        self.cart_items.append({
            "product_id": product_id,
            "price": price,
            "quantity": quantity
        })
        
        return ECommerceEvent(
            event_id=str(uuid.uuid4()),
            event_type="add_to_cart",
            timestamp=datetime.utcnow().isoformat() + "Z",
            user_id=self.user_id,
            session_id=self.session_id,
            properties={
                "product_id": product_id,
                "product_name": self.faker.catch_phrase(),
                "product_category": self.current_category,
                "price": price,
                "quantity": quantity,
                "currency": "USD",
                "cart_total": sum(item["price"] * item["quantity"] for item in self.cart_items),
                "user_agent": self.faker.user_agent(),
                "ip_address": self.faker.ipv4()
            },
            metadata={
                "sdk_version": "1.0.0",
                "platform": "web",
                "environment": os.getenv("ENVIRONMENT", "prod")
            }
        )
    
    def _generate_remove_from_cart(self) -> ECommerceEvent:
        """Generate a remove from cart event"""
        if not self.cart_items:
            return None
            
        # Remove random item from cart
        removed_item = self.cart_items.pop(random.randint(0, len(self.cart_items) - 1))
        
        return ECommerceEvent(
            event_id=str(uuid.uuid4()),
            event_type="remove_from_cart",
            timestamp=datetime.utcnow().isoformat() + "Z",
            user_id=self.user_id,
            session_id=self.session_id,
            properties={
                "product_id": removed_item["product_id"],
                "quantity": removed_item["quantity"],
                "cart_total": sum(item["price"] * item["quantity"] for item in self.cart_items),
                "user_agent": self.faker.user_agent(),
                "ip_address": self.faker.ipv4()
            },
            metadata={
                "sdk_version": "1.0.0",
                "platform": "web",
                "environment": os.getenv("ENVIRONMENT", "prod")
            }
        )
    
    def _generate_purchase(self) -> ECommerceEvent:
        """Generate a purchase event"""
        if not self.cart_items:
            return None
            
        total_amount = sum(item["price"] * item["quantity"] for item in self.cart_items)
        order_id = str(uuid.uuid4())
        
        # Clear cart after purchase
        purchased_items = self.cart_items.copy()
        self.cart_items.clear()
        
        return ECommerceEvent(
            event_id=str(uuid.uuid4()),
            event_type="purchase",
            timestamp=datetime.utcnow().isoformat() + "Z",
            user_id=self.user_id,
            session_id=self.session_id,
            properties={
                "order_id": order_id,
                "total_amount": round(total_amount, 2),
                "currency": "USD",
                "items": purchased_items,
                "payment_method": random.choice(["credit_card", "paypal", "apple_pay", "google_pay"]),
                "shipping_method": random.choice(["standard", "express", "overnight"]),
                "discount_amount": round(random.uniform(0, total_amount * 0.2), 2),
                "user_agent": self.faker.user_agent(),
                "ip_address": self.faker.ipv4()
            },
            metadata={
                "sdk_version": "1.0.0",
                "platform": "web",
                "environment": os.getenv("ENVIRONMENT", "prod")
            }
        )

class SyntheticEventGenerator:
    """Main synthetic event generator class"""
    
    def __init__(self):
        self.kafka_config = {
            'bootstrap.servers': os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'localhost:9092'),
            'client.id': f'synthetic-generator-{uuid.uuid4()}',
            'acks': 'all',
            'retries': 3,
            'retry.backoff.ms': 100,
            'batch.size': 16384,
            'linger.ms': 5,
            'compression.type': 'snappy',
            'max.in.flight.requests.per.connection': 5,
            'enable.idempotence': True
        }
        
        self.producer = Producer(self.kafka_config)
        self.faker = Faker()
        self.active_sessions: Dict[str, UserSession] = {}
        self.redis_client = None
        self.feature_flags = {}
        
        # Configuration
        self.target_rate = int(os.getenv('TARGET_EVENT_RATE', '1000'))  # events per minute
        self.max_concurrent_sessions = int(os.getenv('MAX_SESSIONS', '1000'))
        self.topic_name = os.getenv('KAFKA_TOPIC', 'ecommerce-events')
        
        # Initialize Redis for feature flags
        self._init_redis()
        
        # Start metrics server
        start_http_server(8000)
        
        logger.info("Synthetic event generator initialized", 
                   target_rate=self.target_rate,
                   max_sessions=self.max_concurrent_sessions,
                   topic=self.topic_name)
    
    def _init_redis(self):
        """Initialize Redis connection for feature flags"""
        try:
            redis_host = os.getenv('REDIS_HOST', 'localhost')
            redis_port = int(os.getenv('REDIS_PORT', '6379'))
            self.redis_client = redis.Redis(host=redis_host, port=redis_port, decode_responses=True)
            self.redis_client.ping()
            logger.info("Connected to Redis for feature flags")
        except Exception as e:
            logger.warning("Failed to connect to Redis", error=str(e))
    
    def _get_feature_flag(self, flag_name: str, default: bool = True) -> bool:
        """Get feature flag value from Redis"""
        if not self.redis_client:
            return default
            
        try:
            value = self.redis_client.get(f"feature_flags:{flag_name}")
            return value.lower() == 'true' if value else default
        except Exception as e:
            logger.warning("Failed to get feature flag", flag=flag_name, error=str(e))
            return default
    
    def _delivery_report(self, err, msg):
        """Kafka delivery callback"""
        if err is not None:
            logger.error("Message delivery failed", error=str(err))
        else:
            logger.debug("Message delivered", topic=msg.topic(), partition=msg.partition())
    
    async def _send_event(self, event: ECommerceEvent):
        """Send event to Kafka"""
        try:
            with KAFKA_SEND_TIME.time():
                self.producer.produce(
                    self.topic_name,
                    key=event.user_id,
                    value=json.dumps(asdict(event)),
                    callback=self._delivery_report
                )
                
                EVENTS_GENERATED.labels(
                    event_type=event.event_type,
                    source=event.source
                ).inc()
                
        except Exception as e:
            logger.error("Failed to send event to Kafka", error=str(e), event_id=event.event_id)
    
    def _create_new_session(self) -> UserSession:
        """Create a new user session"""
        user_id = str(uuid.uuid4())
        session = UserSession(user_id, self.faker)
        self.active_sessions[session.session_id] = session
        ACTIVE_SESSIONS.set(len(self.active_sessions))
        return session
    
    def _cleanup_expired_sessions(self):
        """Remove expired sessions"""
        expired_sessions = [
            session_id for session_id, session in self.active_sessions.items()
            if session.is_expired()
        ]
        
        for session_id in expired_sessions:
            del self.active_sessions[session_id]
        
        ACTIVE_SESSIONS.set(len(self.active_sessions))
        
        if expired_sessions:
            logger.info("Cleaned up expired sessions", count=len(expired_sessions))
    
    async def generate_events(self):
        """Main event generation loop"""
        logger.info("Starting event generation")
        
        # Calculate delay between events to achieve target rate
        events_per_second = self.target_rate / 60
        delay_between_events = 1 / events_per_second if events_per_second > 0 else 1
        
        last_rate_update = time.time()
        event_count = 0
        
        while True:
            try:
                # Check if synthetic generation is enabled
                if not self._get_feature_flag('synthetic_generation_enabled', True):
                    logger.info("Synthetic generation disabled by feature flag")
                    await asyncio.sleep(60)
                    continue
                
                # Cleanup expired sessions periodically
                if random.random() < 0.01:  # 1% chance per iteration
                    self._cleanup_expired_sessions()
                
                # Create new sessions if below max
                if len(self.active_sessions) < self.max_concurrent_sessions:
                    if random.random() < 0.1:  # 10% chance to create new session
                        self._create_new_session()
                
                # Generate events from active sessions
                events_to_send = []
                
                for session in list(self.active_sessions.values()):
                    if random.random() < 0.3:  # 30% chance each session generates event
                        event = session.get_next_event()
                        if event:
                            events_to_send.append(event)
                
                # Send events
                for event in events_to_send:
                    await self._send_event(event)
                    event_count += 1
                
                # Flush producer
                self.producer.poll(0)
                
                # Update rate metrics
                current_time = time.time()
                if current_time - last_rate_update >= 60:  # Update every minute
                    current_rate = (event_count / (current_time - last_rate_update)) * 60
                    CURRENT_RATE.set(current_rate)
                    logger.info("Event generation rate", 
                               events_per_minute=int(current_rate),
                               active_sessions=len(self.active_sessions))
                    
                    event_count = 0
                    last_rate_update = current_time
                
                # Wait before next iteration
                await asyncio.sleep(delay_between_events)
                
            except Exception as e:
                logger.error("Error in event generation loop", error=str(e))
                await asyncio.sleep(1)

async def main():
    """Main function"""
    generator = SyntheticEventGenerator()
    
    try:
        await generator.generate_events()
    except KeyboardInterrupt:
        logger.info("Shutting down event generator")
    finally:
        generator.producer.flush()

if __name__ == "__main__":
    asyncio.run(main())
