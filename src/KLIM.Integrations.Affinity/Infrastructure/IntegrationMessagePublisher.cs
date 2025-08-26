using MassTransit;
using System.Text;
using System.Text.Json;

namespace KLIM.Integrations.Affinity.Infrastructure;

public sealed class IntegrationMessagePublisher
{
    private readonly IBus _bus;
    private readonly ILogger<IntegrationMessagePublisher> _logger;

    private const int LARGE_PAYLOAD_THRESHOLD = 500 * 1024;   // 500KB
    private const int MAX_PAYLOAD_SIZE_BYTES = 2 * 1024 * 1024; // 2MB (informational)

    public IntegrationMessagePublisher(IBus bus, ILogger<IntegrationMessagePublisher> logger)
    {
        _bus = bus;
        _logger = logger;
    }

    public async Task PublishWebhookEventAsync<T>(
        T message,
        string routingKey,
        IDictionary<string, object?>? headers = null,
        CancellationToken ct = default) where T : class
    {
        // Payload monitoring aligned with KLIM.Events
        var json = JsonSerializer.Serialize(message);
        var size = Encoding.UTF8.GetByteCount(json);
        MonitorPayloadSize(Guid.NewGuid(), size);

        await _bus.Publish(message, ctx =>
        {
            ctx.SetRoutingKey(routingKey);
            ctx.Headers.Set("PayloadSizeBytes", size);
            ctx.Headers.Set("PayloadSizeKB", size / 1024);
            if (headers != null)
                foreach (var h in headers)
                    ctx.Headers.Set(h.Key, h.Value);
        }, ct);
    }

    private void MonitorPayloadSize(Guid messageId, int payloadSizeBytes)
    {
        if (payloadSizeBytes > LARGE_PAYLOAD_THRESHOLD)
        {
            using var scope = _logger.BeginScope(new Dictionary<string, object?>
            {
                ["MessageId"] = messageId,
                ["PayloadSizeBytes"] = payloadSizeBytes,
                ["PayloadSizeKB"] = payloadSizeBytes / 1024,
                ["PayloadSizeMB"] = payloadSizeBytes / (1024.0 * 1024.0)
            });
            _logger.LogWarning("Large payload detected: {PayloadSizeKB} KB for message {MessageId} (threshold {ThresholdKB} KB)",
                payloadSizeBytes / 1024, messageId, LARGE_PAYLOAD_THRESHOLD / 1024);
        }
    }
}