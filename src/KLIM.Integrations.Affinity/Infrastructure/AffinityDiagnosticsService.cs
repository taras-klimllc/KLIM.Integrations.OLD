using KLIM.Integrations.Contracts.Infrastructure;

namespace KLIM.Integrations.Affinity.Infrastructure;

/// <summary>
/// KLIM Standard: Integration diagnostic service for Affinity API
/// Provides health monitoring for webhook processing and message publishing
/// </summary>
public sealed class AffinityDiagnosticsService : IntegrationDiagnosticServiceBase
{
    public AffinityDiagnosticsService(
        ILogger<AffinityDiagnosticsService> logger,
        SqlAuthenticationService authService,
        DatabaseOptions databaseOptions,
        int intervalMinutes)
        : base(logger, authService, databaseOptions, intervalMinutes)
    {
    }

    protected override async Task RunOnce(CancellationToken ct)
    {
        await SafeExecute("Webhook", async ct =>
        {
            var webhookCount = await ExecuteScalarAsync<long>(
                "SELECT COUNT_BIG(1) FROM aff.WebhookEvents", ct);

            var lastWebhook = await ExecuteScalarAsync<DateTime?>(
                "SELECT MAX(ReceivedAtUtc) FROM aff.WebhookEvents", ct);

            _logger.LogInformation("Diagnostics: webhookCount={Count}, lastReceivedUtc={Last}",
                webhookCount, lastWebhook?.ToUniversalTime().ToString("o") ?? "n/a");
        }, ct);
    }
}