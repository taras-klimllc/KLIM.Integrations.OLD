using Dapper;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace KLIM.Integrations.Contracts.Infrastructure;

/// <summary>
/// KLIM Standard: Base diagnostic service for integration services
/// Provides standardized health monitoring and diagnostics logging
/// </summary>
public abstract class IntegrationDiagnosticServiceBase : BackgroundService
{
    protected readonly ILogger _logger;
    protected readonly SqlAuthenticationService _authService;
    protected readonly DatabaseOptions _databaseOptions;
    protected readonly TimeSpan _interval;

    protected IntegrationDiagnosticServiceBase(
        ILogger logger,
        SqlAuthenticationService authService,
        DatabaseOptions databaseOptions,
        int intervalMinutes)
    {
        _logger = logger;
        _authService = authService;
        _databaseOptions = databaseOptions;
        _interval = TimeSpan.FromMinutes(Math.Max(1, intervalMinutes));
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        // Run once on startup for immediate visibility
        await RunOnce(stoppingToken);

        using var timer = new PeriodicTimer(_interval);
        while (!stoppingToken.IsCancellationRequested && await timer.WaitForNextTickAsync(stoppingToken))
        {
            await RunOnce(stoppingToken);
        }
    }

    /// <summary>
    /// Executes diagnostic checks once
    /// Derived classes should override to implement specific diagnostic logic
    /// </summary>
    /// <param name="ct">Cancellation token</param>
    protected abstract Task RunOnce(CancellationToken ct);

    /// <summary>
    /// Helper method to execute a SQL query and return a scalar result
    /// </summary>
    protected async Task<T> ExecuteScalarAsync<T>(string sql, CancellationToken ct = default)
    {
        await using var conn = await _authService.OpenConnectionAsync(
            _databaseOptions.ConnectionString,
            _databaseOptions.UseAzureAd,
            ct);

        return await conn.ExecuteScalarAsync<T>(new CommandDefinition(sql, cancellationToken: ct));
    }

    /// <summary>
    /// Helper method to safely execute diagnostic operations with error handling
    /// </summary>
    protected async Task SafeExecute(string operationName, Func<CancellationToken, Task> operation, CancellationToken ct)
    {
        try
        {
            await operation(ct);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "{Operation} diagnostics failed", operationName);
        }
    }
}