using KLIM.Integrations.Affinity.SqlWriter.Infrastructure;
using KLIM.Integrations.Affinity.SqlWriter.Upsert;
using KLIM.Integrations.Contracts.Events;
using KLIM.Integrations.Contracts.Infrastructure;
using MassTransit;
using Microsoft.Extensions.Options;

var builder = Host.CreateApplicationBuilder(args);

// Configuration
builder.Services.Configure<DatabaseOptions>(builder.Configuration.GetSection("Database"));
builder.Services.Configure<RabbitMQOptions>(builder.Configuration.GetSection("RabbitMQ"));
builder.Services.Configure<ConsumerOptions>(builder.Configuration.GetSection("Consumer"));

// Logging optimization
builder.Logging.ClearProviders();
builder.Logging.AddSimpleConsole(options =>
{
    options.UseUtcTimestamp = true;
    options.TimestampFormat = "yyyy-MM-ddTHH:mm:ss.fffZ ";
    options.SingleLine = true;
});
builder.Logging.SetMinimumLevel(LogLevel.Information);

// Core services
builder.Services.AddSingleton<SqlAuthenticationService>();
builder.Services.AddSingleton<SqlUpserter>();

// Diagnostics service
builder.Services.AddHostedService(sp =>
{
    var dbOpts = sp.GetRequiredService<IOptions<DatabaseOptions>>().Value;
    var authSvc = sp.GetRequiredService<SqlAuthenticationService>();
    var logger = sp.GetRequiredService<ILogger<IntegrationDiagnosticService>>();
    var diagnosticsInterval = builder.Configuration.GetValue<int>("DiagnosticsIntervalMinutes", dbOpts.DiagnosticsIntervalMinutes);
    return new IntegrationDiagnosticService(logger, authSvc, dbOpts, diagnosticsInterval);
});

// MassTransit configuration
builder.Services.AddMassTransit(x =>
{
    x.AddConsumer<AffinityOrganizationCreatedConsumer>();
    x.AddConsumer<AffinityOrganizationMergedConsumer>();

    x.UsingRabbitMq((context, cfg) =>
    {
        var mqOptions = context.GetRequiredService<IOptions<RabbitMQOptions>>().Value;
        var consumerOptions = context.GetRequiredService<IOptions<ConsumerOptions>>().Value;
        var logger = context.GetRequiredService<ILogger<Program>>();

        logger.LogInformation("Connecting to RabbitMQ: Host={Host}, Exchange={Exchange}, Queue={Queue}",
            mqOptions.Host, mqOptions.FullExchangeName, consumerOptions.QueueName);

        cfg.Host(mqOptions.Host, h => 
        { 
            h.Username(mqOptions.Username); 
            h.Password(mqOptions.Password); 
        });

        // Message configuration
        cfg.Message<AffinityOrganizationCreatedV1>(m => m.SetEntityName(mqOptions.FullExchangeName));
        cfg.Message<AffinityOrganizationMergedV1>(m => m.SetEntityName(mqOptions.FullExchangeName));
        cfg.Publish<AffinityOrganizationCreatedV1>(p => p.ExchangeType = "topic");
        cfg.Publish<AffinityOrganizationMergedV1>(p => p.ExchangeType = "topic");

        // Consumer endpoint configuration
        cfg.ReceiveEndpoint(consumerOptions.QueueName, e =>
        {
            e.PrefetchCount = consumerOptions.Prefetch;
            e.Durable = consumerOptions.Durable;
            e.AutoDelete = consumerOptions.AutoDelete;

            e.Bind(mqOptions.FullExchangeName, x =>
            {
                x.RoutingKey = consumerOptions.BindingKey;
                x.ExchangeType = "topic";
            });

            // Retry configuration
            e.UseMessageRetry(r =>
            {
                r.Interval(3, TimeSpan.FromSeconds(5));
                r.Handle<Exception>();
            });

            e.ConfigureConsumer<AffinityOrganizationCreatedConsumer>(context, c =>
                c.UseMessageRetry(r => r.Interval(3, TimeSpan.FromSeconds(2))));

            e.ConfigureConsumer<AffinityOrganizationMergedConsumer>(context, c =>
                c.UseMessageRetry(r => r.Interval(3, TimeSpan.FromSeconds(2))));
        });

        // Connection resilience
        cfg.UseDelayedRedelivery(r => r.Intervals(
            TimeSpan.FromMinutes(5), 
            TimeSpan.FromMinutes(15), 
            TimeSpan.FromMinutes(30)));
        
        cfg.ConfigureEndpoints(context);
    });
});

var app = builder.Build();

// Startup logging
var logger = app.Services.GetRequiredService<ILogger<Program>>();
var mqOptions = app.Services.GetRequiredService<IOptions<RabbitMQOptions>>().Value;
var consumerOptions = app.Services.GetRequiredService<IOptions<ConsumerOptions>>().Value;

logger.LogInformation("KLIM Affinity SqlWriter starting");
logger.LogInformation("RabbitMQ: Host={Host} ({ConnectionType}), Exchange={Exchange}",
    mqOptions.Host,
    mqOptions.IsExternalConnection ? "External" : "Internal",
    mqOptions.FullExchangeName);
logger.LogInformation("Consumer: Queue={Queue}, BindingKey={BindingKey}, Prefetch={Prefetch}",
    consumerOptions.QueueName,
    consumerOptions.BindingKey,
    consumerOptions.Prefetch);

await app.RunAsync();
