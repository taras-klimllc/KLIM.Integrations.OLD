using Dapper;
using KLIM.Integrations.Affinity.Infrastructure;
using KLIM.Integrations.Contracts.Events;
using KLIM.Integrations.Contracts.Infrastructure;
using MassTransit;
using Microsoft.Extensions.Options;
using System.Security.Cryptography;
using System.Text.Json;

var builder = WebApplication.CreateBuilder(args);

// ---------- Bind configuration ----------
builder.Services.Configure<DatabaseOptions>(builder.Configuration.GetSection("Database"));
builder.Services.Configure<WebhookOptions>(builder.Configuration.GetSection("Webhooks"));
builder.Services.Configure<RabbitMQOptions>(builder.Configuration.GetSection("RabbitMQ"));

// ---------- Services ----------
builder.Services.AddSingleton<SqlAuthenticationService>();
builder.Services.AddLogging();

// ---------- MassTransit (Publisher only) ----------
builder.Services.AddMassTransit(x =>
{
    x.UsingRabbitMq((context, cfg) =>
    {
        var mq = context.GetRequiredService<IOptions<RabbitMQOptions>>().Value;

        cfg.Host(mq.Host, h => { h.Username(mq.Username); h.Password(mq.Password); });

        // Use environment-aware exchange name for all integration messages
        cfg.Message<AffinityOrganizationCreatedV1>(m => m.SetEntityName(mq.FullExchangeName));
        cfg.Message<AffinityOrganizationMergedV1>(m => m.SetEntityName(mq.FullExchangeName));

        cfg.Publish<AffinityOrganizationCreatedV1>(p => p.ExchangeType = "topic");
        cfg.Publish<AffinityOrganizationMergedV1>(p => p.ExchangeType = "topic");
    });
});

// Aligned publisher abstraction
builder.Services.AddScoped<IntegrationMessagePublisher>();

// Dedicated diagnostics BackgroundService (PeriodicTimer pattern)
builder.Services.AddHostedService(sp =>
{
    var dbOpts = sp.GetRequiredService<IOptions<DatabaseOptions>>().Value;
    var authSvc = sp.GetRequiredService<SqlAuthenticationService>();
    var logger = sp.GetRequiredService<ILogger<DiagnosticsService>>();
    var diagnosticsInterval = builder.Configuration.GetValue<int>("DiagnosticsIntervalMinutes", dbOpts.DiagnosticsIntervalMinutes);
    return new DiagnosticsService(logger, authSvc, dbOpts, TimeSpan.FromMinutes(Math.Max(1, diagnosticsInterval)));
});

var app = builder.Build();

// ---------- /health ----------
app.MapGet("/health", async (IOptions<DatabaseOptions> dbOpts, SqlAuthenticationService authSvc, IBus bus, ILoggerFactory lf) =>
{
    var logger = lf.CreateLogger("Health");
    var checks = new Dictionary<string, object?>();

    try
    {
        await using var conn = await authSvc.OpenConnectionAsync(dbOpts.Value.ConnectionString, dbOpts.Value.UseAzureAd);
        var count = await conn.ExecuteScalarAsync<long>("SELECT COUNT_BIG(1) FROM aff.WebhookEvents");
        var last = await conn.ExecuteScalarAsync<DateTime?>("SELECT MAX(ReceivedAtUtc) FROM aff.WebhookEvents");
        checks["database"] = new { status = "healthy", webhooks = count, lastReceivedAtUtc = last?.ToUniversalTime().ToString("o") };
    }
    catch (Exception ex)
    {
        checks["database"] = new { status = "unhealthy", error = ex.Message };
    }

    try
    {
        // A lightweight publish-ready check: ensure bus is created
        checks["bus"] = new { status = (bus != null) ? "healthy" : "unhealthy" };
    }
    catch (Exception ex)
    {
        checks["bus"] = new { status = "unhealthy", error = ex.Message };
    }

    checks["timestampUtc"] = DateTime.UtcNow.ToString("o");
    var overall = checks.Values.Any(v => v?.ToString()?.Contains("unhealthy", StringComparison.OrdinalIgnoreCase) == true) ? "degraded" : "ok";
    return Results.Json(new { status = overall, checks });
});

// ---------- Helpers ----------
static bool SecretsMatch(string a, string b)
{
    if (a is null || b is null) return false;
    var ab = System.Text.Encoding.UTF8.GetBytes(a);
    var bb = System.Text.Encoding.UTF8.GetBytes(b);
    return CryptographicOperations.FixedTimeEquals(ab, bb);
}

// ---------- POST /webhooks/affinity/{secret} ----------
app.MapPost("/webhooks/affinity/{secret}", async (HttpRequest request, string secret,
    IOptions<WebhookOptions> wo,
    IOptions<RabbitMQOptions> ro,
    IOptions<DatabaseOptions> dbOpts,
    SqlAuthenticationService authSvc,
    IntegrationMessagePublisher publisher,
    ILoggerFactory lf) =>
{
    var logger = lf.CreateLogger("Webhook");
    if (!SecretsMatch(secret, wo.Value.Secret))
        return Results.Unauthorized();

    string body;
    using (var reader = new StreamReader(request.Body))
        body = await reader.ReadToEndAsync();

    // Correlation
    var correlationId = Guid.NewGuid().ToString("N");
    using var scope = logger.BeginScope(new Dictionary<string, object?>
    {
        ["CorrelationId"] = correlationId,
        ["Source"] = "affinity.webhook"
    });

    string detected = "unknown";
    try
    {
        using var doc = JsonDocument.Parse(body);
        if (doc.RootElement.TryGetProperty("type", out var typeEl) && typeEl.ValueKind == JsonValueKind.String)
            detected = typeEl.GetString()?.Trim().ToLowerInvariant() ?? "unknown";
    }
    catch { /* keep unknown */ }

    string eventSuffix = detected switch
    {
        "organization.created" => "organization.created",
        "organization.merged" => "organization.merged",
        _ => "unknown"
    };

    // Insert with SHA-256 dedupe
    await using var conn = await authSvc.OpenConnectionAsync(dbOpts.Value.ConnectionString, dbOpts.Value.UseAzureAd);
    await using var tx = await conn.BeginTransactionAsync(System.Data.IsolationLevel.Serializable);
    var (inserted, id) = await SqlHelpers.InsertWebhookEventIfNewAsync(conn, (System.Data.IDbTransaction)tx, eventSuffix, body, request.HttpContext.RequestAborted);
    await tx.CommitAsync();

    // Publish typed messages using KLIM standard routing keys
    var routingKey = ro.Value.GetRoutingKey(eventSuffix.Replace(".created", "").Replace(".merged", ""),
                                           eventSuffix.Contains(".created") ? "created" :
                                           eventSuffix.Contains(".merged") ? "merged" : "unknown");

    if (eventSuffix == "organization.created")
    {
        var msg = JsonSerializer.Deserialize<AffinityOrganizationCreatedV1>(body, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
        if (msg is not null)
        {
            await publisher.PublishWebhookEventAsync(msg, routingKey, new Dictionary<string, object?>
            {
                ["source"] = "affinity.webhook",
                ["event_type"] = eventSuffix,
                ["correlation_id"] = correlationId,
                ["environment"] = ro.Value.Environment ?? "unknown"
            }, request.HttpContext.RequestAborted);
        }
    }
    else if (eventSuffix == "organization.merged")
    {
        var msg = JsonSerializer.Deserialize<AffinityOrganizationMergedV1>(body, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
        if (msg is not null)
        {
            await publisher.PublishWebhookEventAsync(msg, routingKey, new Dictionary<string, object?>
            {
                ["source"] = "affinity.webhook",
                ["event_type"] = eventSuffix,
                ["correlation_id"] = correlationId,
                ["environment"] = ro.Value.Environment ?? "unknown"
            }, request.HttpContext.RequestAborted);
        }
    }
    else
    {
        // Unknown: publish nothing (stored for analysis) — extend when new events added
        logger.LogInformation("Unknown webhook type; stored only. correlationId={CorrelationId}", correlationId);
    }

    logger.LogInformation("Webhook {Event} processed; inserted={Inserted} id={Id}; routing={RoutingKey}; correlationId={CorrelationId}",
        eventSuffix, inserted, id, routingKey, correlationId);

    return Results.Accepted($"/webhooks/affinity/{secret}", new
    {
        status = "accepted",
        eventType = eventSuffix,
        deduplicated = !inserted,
        routingKey,
        correlationId
    });
});

app.Run();

// ---------- Diagnostics ----------
sealed class DiagnosticsService : BackgroundService
{
    private readonly ILogger<DiagnosticsService> _logger;
    private readonly SqlAuthenticationService _authService;
    private readonly DatabaseOptions _databaseOptions;
    private readonly TimeSpan _interval;

    public DiagnosticsService(ILogger<DiagnosticsService> logger, SqlAuthenticationService authService, DatabaseOptions databaseOptions, TimeSpan interval)
    {
        _logger = logger;
        _authService = authService;
        _databaseOptions = databaseOptions;
        _interval = interval;
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

    private async Task RunOnce(CancellationToken ct)
    {
        try
        {
            await using var conn = await _authService.OpenConnectionAsync(_databaseOptions.ConnectionString, _databaseOptions.UseAzureAd, ct);
            var count = await conn.ExecuteScalarAsync<long>(new Dapper.CommandDefinition(
                "SELECT COUNT_BIG(1) FROM aff.WebhookEvents", cancellationToken: ct));
            var last = await conn.ExecuteScalarAsync<DateTime?>(new Dapper.CommandDefinition(
                "SELECT MAX(ReceivedAtUtc) FROM aff.WebhookEvents", cancellationToken: ct));
            _logger.LogInformation("Diagnostics: webhookCount={Count}, lastReceivedUtc={Last}",
                count, last?.ToUniversalTime().ToString("o") ?? "n/a");
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Diagnostics encountered an error.");
        }
    }
}
