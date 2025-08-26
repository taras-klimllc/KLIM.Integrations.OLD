# KLIM.Events RabbitMQ Naming Conventions & Topology Standards

**Document Version**: 1.0  
**Date**: August 25, 2025  
**Based on**: KLIM.Integrations.Affinity Implementation  
**Purpose**: Template for standardizing RabbitMQ implementations across KLIM ecosystem

---

## **?? Overview**

This document defines the standardized RabbitMQ naming conventions and topology patterns used across all KLIM integration services. It's derived from the successfully implemented KLIM.Integrations.Affinity solution and serves as a template for future similar solutions.

---

## **?? Naming Convention Standards**

### **1. Exchange Naming Pattern**
```
klim.events.{domain}
```

**Examples**:
- `klim.events.integration` - For all integration-related events
- `klim.events.business` - For business domain events
- `klim.events.datachanged` - For data change notifications

**Rules**:
- Always use **topic** exchange type
- Use lowercase with dot notation
- Domain should be descriptive but concise
- Avoid service-specific exchanges (use shared exchanges)

### **2. Queue Naming Pattern**
```
klim.{service}.{purpose}
```

**Examples**:
- `klim.affinity.sqlwriter` - Affinity SQL data writer service
- `klim.hubspot.processor` - HubSpot event processor service
- `klim.salesforce.sync` - Salesforce synchronization service

**Rules**:
- Always use lowercase with dot notation
- Service name should match the integration source
- Purpose should describe the consumer's function
- Keep names concise but descriptive

### **3. Routing Key Pattern**
```
klim.{domain}.{service}.{event}.{version}
```

**Examples**:
- `klim.integration.affinity.organization.created.v1`
- `klim.integration.hubspot.contact.updated.v1`
- `klim.business.order.processed.v2`

**Rules**:
- Always include version suffix (v1, v2, etc.)
- Use past tense for events (created, updated, deleted)
- Maintain hierarchical structure for topic routing
- Event names should be specific but not overly verbose

### **4. Binding Key Pattern**
```
klim.{domain}.{service}.#
```

**Examples**:
- `klim.integration.affinity.#` - Matches all Affinity events
- `klim.integration.hubspot.#` - Matches all HubSpot events
- `klim.business.order.#` - Matches all order-related events

**Rules**:
- Use wildcard (`#`) to match all events for a service
- Allows flexible event expansion without reconfiguration
- Supports topic-based routing for scalability

---

## **??? Topology Architecture**

### **Standard Topology Pattern**
```
???????????????????????    Topic Routing     ????????????????????????
?  klim.events.{domain} ? ?????????????????? ?  klim.{service}.{purpose}  ?
?     (Exchange)      ?   {routing.key.#}   ?       (Queue)        ?
?      [Topic]        ?                     ?      [Durable]       ?
???????????????????????                     ????????????????????????
```

### **Key Principles**:
1. **Single Domain Exchange**: One topic exchange per domain (integration, business, etc.)
2. **Direct Queue Binding**: No intermediate exchanges or complex routing
3. **Topic-Based Routing**: Use hierarchical routing keys with wildcards
4. **Durable Components**: All exchanges and queues are durable for reliability

### **? Anti-Patterns to Avoid**:
- Service-specific exchanges (use shared domain exchanges)
- Exchange-to-exchange bindings (use direct exchange-to-queue)
- Fanout exchanges for integration events (use topic routing)
- Non-durable queues for persistent data

---

## **?? Configuration Templates**

### **1. RabbitMQ Configuration Class**
```csharp
public sealed class RabbitMQOptions
{
    public string Host { get; init; } = "rabbitmq";
    public string Username { get; init; } = "guest";
    public string Password { get; init; } = "guest";
    public string ExchangeName { get; init; } = "klim.events.integration"; // Domain exchange
    public string RoutingKeyPrefix { get; init; } = "klim.integration.{service}"; // Replace {service}
}
```

### **2. Consumer Configuration Class**
```csharp
public sealed class ConsumerOptions
{
    public string QueueName { get; init; } = "klim.{service}.{purpose}"; // Replace placeholders
    public string BindingKey { get; init; } = "klim.integration.{service}.#"; // Wildcard pattern
    public ushort Prefetch { get; init; } = 50; // Standard prefetch count
}
```

### **3. appsettings.json Template**
```json
{
  "RabbitMQ": {
    "Host": "rabbitmq",
    "Username": "guest", 
    "Password": "guest",
    "ExchangeName": "klim.events.integration",
    "RoutingKeyPrefix": "klim.integration.{SERVICE_NAME}"
  },
  "Consumer": {
    "QueueName": "klim.{SERVICE_NAME}.{PURPOSE}",
    "BindingKey": "klim.integration.{SERVICE_NAME}.#",
    "Prefetch": 50
  }
}
```

### **4. Environment Variables Template**
```bash
# RabbitMQ Configuration
RABBITMQ__HOST=localhost
RABBITMQ__USERNAME=guest
RABBITMQ__PASSWORD=guest
RABBITMQ__EXCHANGENAME=klim.events.integration
RABBITMQ__ROUTINGKEYPREFIX=klim.integration.{SERVICE_NAME}

# Consumer Configuration
CONSUMER__QUEUENAME=klim.{SERVICE_NAME}.{PURPOSE}
CONSUMER__BINDINGKEY=klim.integration.{SERVICE_NAME}.#
CONSUMER__PREFETCH=50
```

---

## **?? MassTransit Implementation Patterns**

### **1. Publisher Configuration (API/Webhook Service)**
```csharp
builder.Services.AddMassTransit(x =>
{
    x.UsingRabbitMq((context, cfg) =>
    {
        var mq = context.GetRequiredService<IOptions<RabbitMQOptions>>().Value;
        
        cfg.Host(mq.Host, h => { 
            h.Username(mq.Username); 
            h.Password(mq.Password); 
        });

        // Configure messages to use shared integration exchange
        cfg.Message<YourEventV1>(m => m.SetEntityName(mq.ExchangeName));
        cfg.Publish<YourEventV1>(p => p.ExchangeType = "topic");
    });
});
```

### **2. Consumer Configuration (Worker Service)**
```csharp
builder.Services.AddMassTransit(x =>
{
    x.AddConsumer<YourEventConsumer>();

    x.UsingRabbitMq((context, cfg) =>
    {
        var mq = context.GetRequiredService<IOptions<RabbitMQOptions>>().Value;
        var co = context.GetRequiredService<IOptions<ConsumerOptions>>().Value;

        cfg.Host(mq.Host, h => { 
            h.Username(mq.Username); 
            h.Password(mq.Password); 
        });

        // Configure messages for publishing (if needed)
        cfg.Message<YourEventV1>(m => m.SetEntityName(mq.ExchangeName));
        cfg.Publish<YourEventV1>(p => p.ExchangeType = "topic");

        // Configure consumer endpoint with topic binding
        cfg.ReceiveEndpoint(co.QueueName, e =>
        {
            e.PrefetchCount = co.Prefetch;
            
            // Bind to integration exchange with wildcard routing
            e.Bind(mq.ExchangeName, x =>
            {
                x.RoutingKey = co.BindingKey;
                x.ExchangeType = "topic";
            });

            e.ConfigureConsumer<YourEventConsumer>(context);
        });
    });
});
```

### **3. Message Publishing Pattern**
```csharp
public class IntegrationMessagePublisher
{
    private readonly IBus _bus;
    
    public async Task PublishEventAsync<T>(
        T message,
        string eventName,
        string version = "v1",
        IDictionary<string, object?>? headers = null,
        CancellationToken ct = default) where T : class
    {
        var routingKey = $"klim.integration.{SERVICE_NAME}.{eventName}.{version}";
        
        await _bus.Publish(message, ctx =>
        {
            ctx.SetRoutingKey(routingKey);
            ctx.Headers.Set("source", "{SERVICE_NAME}.webhook");
            ctx.Headers.Set("event_type", eventName);
            ctx.Headers.Set("version", version);
            
            if (headers != null)
                foreach (var h in headers)
                    ctx.Headers.Set(h.Key, h.Value);
        }, ct);
    }
}
```

---

## **?? Message Header Standards**

### **Standard Headers**
All messages should include these standard headers:

```csharp
var standardHeaders = new Dictionary<string, object?>
{
    ["source"] = "{service}.webhook",           // Message source
    ["event_type"] = "organization.created",    // Event type
    ["version"] = "v1",                        // Schema version
    ["correlation_id"] = correlationId,        // Tracing ID
    ["timestamp_utc"] = DateTime.UtcNow,       // Event timestamp
    ["payload_size_bytes"] = payloadSize       // Size monitoring
};
```

### **Optional Headers**
```csharp
var optionalHeaders = new Dictionary<string, object?>
{
    ["trace_id"] = traceId,                    // Distributed tracing
    ["user_id"] = userId,                      // User context
    ["tenant_id"] = tenantId,                  // Multi-tenant context
    ["retry_count"] = retryCount               // Retry tracking
};
```

---

## **?? Implementation Checklist**

### **For New Integration Services:**

#### **? Naming Compliance**
- [ ] Exchange follows `klim.events.{domain}` pattern
- [ ] Queue follows `klim.{service}.{purpose}` pattern  
- [ ] Routing keys follow `klim.{domain}.{service}.{event}.{version}` pattern
- [ ] Binding keys use wildcard pattern `klim.{domain}.{service}.#`

#### **? Configuration Structure**
- [ ] `RabbitMQOptions` class implemented
- [ ] `ConsumerOptions` class implemented (for consumers)
- [ ] Configuration sections in appsettings.json
- [ ] Environment variable mapping

#### **? MassTransit Setup**
- [ ] Topic exchange configuration
- [ ] Direct exchange-to-queue binding (no intermediate exchanges)
- [ ] Proper message entity name mapping
- [ ] Consumer endpoint with topic binding

#### **? Message Standards**
- [ ] Standard headers included in all messages
- [ ] Versioned event contracts
- [ ] Correlation ID tracking
- [ ] Payload size monitoring

#### **? Topology Verification**
- [ ] No fanout exchanges created for integration events
- [ ] No exchange-to-exchange bindings
- [ ] Durable exchanges and queues
- [ ] Topic routing with wildcards

---

## **?? Verification Commands**

### **RabbitMQ Management API Verification**
```bash
# Check exchanges
curl -u guest:guest http://localhost:15672/api/exchanges

# Check queues  
curl -u guest:guest http://localhost:15672/api/queues

# Check bindings
curl -u guest:guest http://localhost:15672/api/bindings
```

### **Expected Topology Results**
```json
// Exchanges (should only see domain exchanges)
{
  "name": "klim.events.integration",
  "type": "topic",
  "durable": true
}

// Queues (service-specific)
{
  "name": "klim.{service}.{purpose}",
  "durable": true,
  "arguments": {"x-queue-type": "classic"}
}

// Bindings (direct exchange-to-queue)
{
  "source": "klim.events.integration",
  "destination": "klim.{service}.{purpose}",
  "destination_type": "queue",
  "routing_key": "klim.integration.{service}.#"
}
```

---

## **?? Benefits of This Standard**

### **Scalability**
- Topic-based routing supports multiple consumers
- Wildcard bindings allow event expansion without reconfiguration
- Shared exchanges reduce infrastructure complexity

### **Maintainability**  
- Consistent naming across all services
- Predictable message routing patterns
- Clear service boundaries and responsibilities

### **Observability**
- Standardized headers enable consistent monitoring
- Correlation IDs support distributed tracing
- Routing keys provide clear event categorization

### **Performance**
- Direct exchange-to-queue routing (no extra hops)
- Efficient topic matching
- Optimized prefetch settings

---

## **?? Service Implementation Template**

When implementing a new integration service, replace placeholders:

- `{SERVICE_NAME}` ? actual service name (e.g., "hubspot", "salesforce")
- `{PURPOSE}` ? service function (e.g., "processor", "sync", "writer")
- `{domain}` ? event domain (e.g., "integration", "business")

**Example for HubSpot Integration:**
- Exchange: `klim.events.integration`
- Queue: `klim.hubspot.processor`
- Routing Keys: `klim.integration.hubspot.contact.created.v1`
- Binding Key: `klim.integration.hubspot.#`

This standardized approach ensures consistency, scalability, and maintainability across the entire KLIM integration ecosystem.

---

**This document serves as the definitive guide for RabbitMQ implementation standards across all KLIM integration services.** ??