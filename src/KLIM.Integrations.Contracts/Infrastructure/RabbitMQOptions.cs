using System.ComponentModel.DataAnnotations;

namespace KLIM.Integrations.Contracts.Infrastructure;

/// <summary>
/// KLIM Standard: RabbitMQ Configuration Options
/// Implements enterprise naming conventions for exchanges, routing keys, and queues
/// Based on KLIM.Events production standards
/// </summary>
public sealed class RabbitMQOptions
{
    /// <summary>RabbitMQ host (e.g., "rabbitmq.company.com", "localhost", "host.docker.internal")</summary>
    [Required]
    public string Host { get; init; } = "host.docker.internal";

    /// <summary>RabbitMQ username for authentication</summary>
    [Required]
    public string Username { get; init; } = "guest";

    /// <summary>RabbitMQ password for authentication</summary>
    [Required]
    public string Password { get; init; } = "guest";

    /// <summary>
    /// Exchange name following {company}.{domain} pattern
    /// Examples: "klim.events", "acme.commands", "contoso.notifications"
    /// </summary>
    [Required]
    [RegularExpression(@"^[a-z]+\.[a-z]+", ErrorMessage = "Exchange name must follow 'company.domain' pattern with lowercase letters")]
    public string ExchangeName { get; init; } = "klim.events";

    /// <summary>
    /// Routing key prefix following {company}.{domain} pattern
    /// Used as base for all message routing keys
    /// </summary>
    [Required]
    [RegularExpression(@"^[a-z]+\.[a-z]+", ErrorMessage = "Routing key prefix must follow 'company.domain' pattern")]
    public string RoutingKeyPrefix { get; init; } = "klim.integration";

    /// <summary>
    /// Full exchange name
    /// Examples: "klim.events", "klim.commands", "klim.notifications"
    /// </summary>
    public string FullExchangeName => ExchangeName;

    /// <summary>
    /// Dead letter exchange name
    /// Pattern: {ExchangeName}.dlq
    /// Examples: "klim.events.dlq", "klim.commands.dlq"
    /// </summary>
    public string DeadLetterExchangeName => $"{ExchangeName}.dlq";

    /// <summary>
    /// Generates a routing key for integration events
    /// Pattern: {RoutingKeyPrefix}.{entityType}.{operation}.{version}
    /// Examples: "klim.integration.affinity.organization.created.v1"
    /// </summary>
    /// <param name="entityType">Entity type (e.g., "organization", "deal")</param>
    /// <param name="operation">Operation type (e.g., "created", "updated", "merged")</param>
    /// <param name="version">Message version (e.g., "v1", "v2")</param>
    /// <returns>Formatted routing key</returns>
    public string GetRoutingKey(string entityType, string operation, string version = "v1") =>
        $"{RoutingKeyPrefix}.affinity.{entityType.ToLowerInvariant()}.{operation.ToLowerInvariant()}.{version.ToLowerInvariant()}";

    /// <summary>
    /// Validates connection to external RabbitMQ instance
    /// </summary>
    /// <returns>True if configuration appears valid for external connection</returns>
    public bool IsExternalConnection =>
        Host.Contains("docker.internal") ||
        Host.Contains("localhost") ||
        System.Net.IPAddress.TryParse(Host, out _);
}

/// <summary>
/// Consumer-specific configuration options for Worker Services
/// Aligned with external RabbitMQ deployment
/// </summary>
public sealed class ConsumerOptions
{
    /// <summary>
    /// Queue name following KLIM naming convention
    /// Pattern: {company}.{service}.{purpose}
    /// Examples: "klim.affinity.sqlwriter", "klim.crm.processor"
    /// </summary>
    [Required]
    public string QueueName { get; init; } = "klim.affinity.sqlwriter";

    /// <summary>
    /// Topic binding key pattern for receiving messages
    /// Uses wildcard patterns to subscribe to relevant message types
    /// Pattern: {company}.{domain}.{service}.# 
    /// Example: "klim.integration.affinity.#" matches all Affinity integration messages
    /// </summary>
    [Required]
    public string BindingKey { get; init; } = "klim.integration.affinity.#";

    /// <summary>
    /// Message prefetch count for consumer performance tuning
    /// Recommended: 50 for balanced throughput and memory usage
    /// </summary>
    [Range(1, 1000, ErrorMessage = "Prefetch must be between 1 and 1000")]
    public ushort Prefetch { get; init; } = 50;

    /// <summary>
    /// Queue durability setting for external RabbitMQ
    /// </summary>
    public bool Durable { get; init; } = true;

    /// <summary>
    /// Auto-delete queue when no consumers (typically false for persistent queues)
    /// </summary>
    public bool AutoDelete { get; init; } = false;
}