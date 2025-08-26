using System.ComponentModel.DataAnnotations;

namespace KLIM.Integrations.Contracts.Infrastructure;

/// <summary>
/// KLIM Standard: RabbitMQ Configuration Options
/// Implements enterprise naming conventions for exchanges, routing keys, and queues
/// Based on KLIM.Events production standards
/// </summary>
public sealed class RabbitMQOptions
{
    /// <summary>RabbitMQ host (e.g., "rabbitmq.company.com" or "localhost")</summary>
    [Required]
    public string Host { get; init; } = "localhost";
    
    /// <summary>RabbitMQ username for authentication</summary>
    [Required]
    public string Username { get; init; } = "guest";
    
    /// <summary>RabbitMQ password for authentication</summary>
    [Required]
    public string Password { get; init; } = "guest";
    
    /// <summary>
    /// Base exchange name following {company}.{domain} pattern
    /// Examples: "klim.events", "acme.commands", "contoso.notifications"
    /// </summary>
    [Required]
    [RegularExpression(@"^[a-z]+\.[a-z]+", ErrorMessage = "Exchange name must follow 'company.domain' pattern with lowercase letters")]
    public string ExchangeName { get; init; } = "klim.events.integration";
    
    /// <summary>
    /// Environment identifier for multi-environment deployments
    /// Examples: "dev", "staging", "prod"
    /// </summary>
    [RegularExpression(@"^[a-z]*$", ErrorMessage = "Environment must be lowercase letters only")]
    public string Environment { get; init; } = string.Empty;
    
    /// <summary>
    /// Routing key prefix following {company}.{domain} pattern
    /// Used as base for all message routing keys
    /// </summary>
    [Required]
    [RegularExpression(@"^[a-z]+\.[a-z]+", ErrorMessage = "Routing key prefix must follow 'company.domain' pattern")]
    public string RoutingKeyPrefix { get; init; } = "klim.integration.affinity";
    
    /// <summary>
    /// Environment-aware full exchange name
    /// Pattern: {ExchangeName}.{Environment} or {ExchangeName} if no environment
    /// Examples: "klim.events.dev", "klim.events.prod", "klim.events.integration"
    /// </summary>
    public string FullExchangeName => string.IsNullOrEmpty(Environment) ? ExchangeName : $"{ExchangeName}.{Environment}";
    
    /// <summary>
    /// Generates a routing key for integration events
    /// </summary>
    /// <param name="entityType">Entity type (e.g., "organization", "deal")</param>
    /// <param name="operation">Operation type (e.g., "created", "updated", "merged")</param>
    /// <param name="version">Message version (e.g., "v1", "v2")</param>
    /// <returns>Formatted routing key</returns>
    public string GetRoutingKey(string entityType, string operation, string version = "v1") =>
        $"{RoutingKeyPrefix}.{entityType.ToLowerInvariant()}.{operation.ToLowerInvariant()}.{version.ToLowerInvariant()}";
}

/// <summary>
/// Consumer-specific configuration options for Worker Services
/// </summary>
public sealed class ConsumerOptions
{
    /// <summary>
    /// Queue name following KLIM naming convention
    /// Pattern: klim.{service}.{purpose}
    /// </summary>
    [Required]
    public string QueueName { get; init; } = "klim.affinity.sqlwriter";
    
    /// <summary>
    /// Topic binding key pattern for receiving messages
    /// Uses wildcard patterns to subscribe to relevant message types
    /// </summary>
    [Required]
    public string BindingKey { get; init; } = "klim.integration.affinity.#";
    
    /// <summary>
    /// Message prefetch count for consumer performance tuning
    /// </summary>
    [Range(1, 1000, ErrorMessage = "Prefetch must be between 1 and 1000")]
    public ushort Prefetch { get; init; } = 50;
}