using KLIM.Integrations.Contracts.Infrastructure;

namespace KLIM.Integrations.Affinity.SqlWriter.Infrastructure;

/// <summary>
/// KLIM Standard: Integration diagnostic service for Affinity SqlWriter
/// Provides health monitoring for webhook processing and database integration
/// </summary>
public sealed class IntegrationDiagnosticService : IntegrationDiagnosticServiceBase
{
    public IntegrationDiagnosticService(
        ILogger<IntegrationDiagnosticService> logger,
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

            var mappingCount = await ExecuteScalarAsync<long>(
                "SELECT COUNT_BIG(1) FROM integration.AffinityOrganizations", ct);

            var linkedIssuers = await ExecuteScalarAsync<long>(
                "SELECT COUNT_BIG(1) FROM integration.AffinityOrganizations WHERE IssuerID IS NOT NULL", ct);

            var lastUpdated = await ExecuteScalarAsync<DateTime?>(
                "SELECT MAX(UpdatedDate) FROM integration.AffinityOrganizations", ct);

            _logger.LogInformation("Diagnostics: webhooks={Webhooks}, lastWebhookUtc={LastWebhook}, mappings={Mappings}, linkedIssuers={Linked}, lastUpdatedUtc={LastUpdated}",
                webhookCount,
                lastWebhook?.ToUniversalTime().ToString("o") ?? "n/a",
                mappingCount,
                linkedIssuers,
                lastUpdated?.ToUniversalTime().ToString("o") ?? "n/a");
        }, ct);
    }
}