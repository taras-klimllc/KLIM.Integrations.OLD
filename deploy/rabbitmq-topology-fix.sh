# RabbitMQ Topology Cleanup Script
# Run these commands to fix the current RabbitMQ configuration

# 1. Remove incorrect exchange-to-exchange binding
rabbitmqctl delete_binding klim.events.integration klim.integration.affinity.sqlwriter ""

# 2. Remove unnecessary fanout exchange (this should not exist)
rabbitmqctl delete_exchange klim.integration.affinity.sqlwriter

# 3. Create/Update the correct queue with new name
rabbitmqctl declare_queue klim.affinity.sqlwriter durable=true

# 4. Create correct exchange-to-queue binding
rabbitmqctl declare_binding klim.events.integration klim.affinity.sqlwriter klim.integration.affinity.#

# 5. Remove old queue if it exists (optional - can be done after migration)
# rabbitmqctl delete_queue klim.integration.affinity.sqlwriter

# Verify the corrected topology:
rabbitmqctl list_exchanges
rabbitmqctl list_queues
rabbitmqctl list_bindings