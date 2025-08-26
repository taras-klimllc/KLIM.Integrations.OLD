using Azure.Core;
using Azure.Identity;
using KLIM.Integrations.Affinity.SqlWriter.Configuration;
using KLIM.Integrations.Affinity.SqlWriter.Infrastructure;
using KLIM.Integrations.Affinity.SqlWriter.Upsert;
using KLIM.Integrations.Contracts.Events;
using KLIM.Integrations.Contracts.Infrastructure;
using MassTransit;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Options;

var builder = Host.CreateApplicationBuilder(args);

// Options - aligned with KLIM.Events standardized configuration
builder.Services.Configure<DatabaseOptions>(builder.Configuration.GetSection("Database"));
builder.Services.Configure<RabbitMQOptions>(builder.Configuration.GetSection("RabbitMQ"));
builder.Services.Configure<ConsumerOptions>(builder.Configuration.GetSection("Consumer"));

// Logging
builder.Logging.ClearProviders();
builder.Logging.AddSimpleConsole(o =>
{
    o.UseUtcTimestamp = true;
    o.TimestampFormat = "yyyy-MM-ddTHH:mm:ss.fffZ ";
});
builder.Logging.SetMinimumLevel(LogLevel.Information);

// Core services - aligned with KLIM.Events pattern
builder.Services.AddSingleton<SqlAuthenticationService>();
builder.Services.AddSingleton(sp =>
{
    var dbOpts = sp.GetRequiredService<IOptions<DatabaseOptions>>().Value;
    return dbOpts;
});
builder.Services.AddSingleton<SqlUpserter>();

// Diagnostics service
builder.Services.AddHostedService(sp =>
{
    var dbOpts = sp.GetRequiredService<IOptions<DatabaseOptions>>().Value;
    return new IntegrationDiagnosticService(
        sp.GetRequiredService<ILogger<IntegrationDiagnosticService>>(),
        sp.GetRequiredService<SqlAuthenticationService>(),
        dbOpts,
        dbOpts.DiagnosticsIntervalMinutes);
});

// ---------- MassTransit (Consumers + ReceiveEndpoint binding) ----------
builder.Services.AddMassTransit(x =>
{
    x.AddConsumer<AffinityOrganizationCreatedConsumer>();
    x.AddConsumer<AffinityOrganizationMergedConsumer>();

    x.UsingRabbitMq((context, cfg) =>
    {
        var mq = context.GetRequiredService<IOptions<RabbitMQOptions>>().Value;
        var co = context.GetRequiredService<IOptions<ConsumerOptions>>().Value;

        cfg.Host(mq.Host, h => { h.Username(mq.Username); h.Password(mq.Password); });

        // Ensure messages publish to the shared integration exchange
        cfg.Message<AffinityOrganizationCreatedV1>(m => m.SetEntityName(mq.FullExchangeName));
        cfg.Message<AffinityOrganizationMergedV1>(m => m.SetEntityName(mq.FullExchangeName));
        cfg.Publish<AffinityOrganizationCreatedV1>(p => p.ExchangeType = "topic");
        cfg.Publish<AffinityOrganizationMergedV1>(p => p.ExchangeType = "topic");

        // Receive endpoint with topic binding key
        cfg.ReceiveEndpoint(co.QueueName, e =>
        {
            e.PrefetchCount = co.Prefetch;

            // Bind to the integration exchange using topic key
            e.Bind(mq.FullExchangeName, x =>
            {
                x.RoutingKey = co.BindingKey;
                x.ExchangeType = "topic";
            });

            e.ConfigureConsumer<AffinityOrganizationCreatedConsumer>(context);
            e.ConfigureConsumer<AffinityOrganizationMergedConsumer>(context);
        });
    });
});

var app = builder.Build();
await app.RunAsync();
