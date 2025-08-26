# KLIM.Events Unified Naming Convention & RabbitMQ Topology

## **?? Proposed Unified Naming Standards**

### **1. Exchange Naming Convention**
```
klim.events.{domain}
```
- **Integration Events**: `klim.events.integration`
- **Data Change Events**: `klim.events.datachanged` 
- **Business Events**: `klim.events.business`

### **2. Routing Key Convention**
```
klim.{domain}.{service}.{event}.{version}
```
- **Affinity Created**: `klim.integration.affinity.organization.created.v1`
- **Affinity Merged**: `klim.integration.affinity.organization.merged.v1`
- **Data Changed**: `klim.datachanged.entity.changed.v1`

### **3. Queue Naming Convention**
```
klim.{service}.{consumer-purpose}
```
- **Affinity SqlWriter**: `klim.affinity.sqlwriter`
- **Integration Processor**: `klim.integration.processor`
- **Data Sync Service**: `klim.datasync.consumer`

---

## **?? Current Issues in RabbitMQ Configuration**

### **? Problems Identified:**

1. **Incorrect Exchange-to-Exchange Binding**
   ```json
   // WRONG: Exchange binding to exchange
   {
     "source": "klim.events.integration",
     "destination": "klim.integration.affinity.sqlwriter", // This should be a QUEUE
     "destination_type": "exchange" // ? WRONG
   }
   ```

2. **Unnecessary Exchange Creation**
   ```json
   // WRONG: Service-specific exchange should not exist
   {
     "name": "klim.integration.affinity.sqlwriter",
     "type": "fanout" // ? Should not exist
   }
   ```

3. **Inconsistent Naming**
   - Queue name: `klim.integration.affinity.sqlwriter` (too long)
   - Routing key: `klim.integration.affinity.#` (correct pattern)

---

## **? Corrected RabbitMQ Topology**

### **Exchanges (Topic-based)**
```json
{
  "name": "klim.events.integration",
  "type": "topic",
  "durable": true
}
```

### **Queues (Service-specific)**
```json
{
  "name": "klim.affinity.sqlwriter",
  "durable": true,
  "arguments": {"x-queue-type": "classic"}
}
```

### **Bindings (Direct exchange-to-queue)**
```json
{
  "source": "klim.events.integration",
  "destination": "klim.affinity.sqlwriter",
  "destination_type": "queue",
  "routing_key": "klim.integration.affinity.#"
}
```

---

## **?? Implementation Plan**

### **Phase 1: Update Configuration Classes**
- Update `ConsumerOptions.QueueName` to use shorter naming
- Ensure routing keys follow consistent pattern
- Remove exchange-to-exchange binding configuration

### **Phase 2: Update MassTransit Configuration**
- Fix consumer binding to bind directly to target exchange
- Remove unnecessary exchange creation
- Ensure proper topic routing

### **Phase 3: Clean Up RabbitMQ**
- Remove incorrect `klim.integration.affinity.sqlwriter` exchange
- Update queue bindings to be direct exchange-to-queue
- Verify routing key patterns

### **Phase 4: Standardize Across Services**
- Apply naming convention to all KLIM services
- Document standard patterns
- Create configuration templates

---

## **?? Benefits of Unified Naming**

1. **Consistency**: All KLIM services follow same patterns
2. **Clarity**: Easy to understand purpose from names
3. **Scalability**: Consistent approach for new services
4. **Maintainability**: Predictable naming reduces errors
5. **Monitoring**: Easier to identify and track components

---

## **?? Verification Checklist**

- [ ] Exchange names follow `klim.events.{domain}` pattern
- [ ] Queue names follow `klim.{service}.{purpose}` pattern  
- [ ] Routing keys follow `klim.{domain}.{service}.{event}.{version}` pattern
- [ ] No exchange-to-exchange bindings
- [ ] All bindings are exchange-to-queue with topic routing
- [ ] MassTransit configuration uses correct topology

---

This unified approach ensures consistency across all KLIM services while maintaining the flexibility of topic-based routing and proper message distribution.