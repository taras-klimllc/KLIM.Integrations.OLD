using System.Threading;
using System.Threading.Tasks;
using KLIM.Integrations.Affinity.SqlWriter.Upsert;
using KLIM.Integrations.Contracts.Events;
using KLIM.Integrations.Contracts.Infrastructure;
using MassTransit;
using Microsoft.Extensions.Logging;

public sealed class AffinityOrganizationCreatedConsumer : IConsumer<AffinityOrganizationCreatedV1>
{
    private readonly SqlUpserter _upserter;
    private readonly ILogger<AffinityOrganizationCreatedConsumer> _logger;

    public AffinityOrganizationCreatedConsumer(SqlUpserter upserter, ILogger<AffinityOrganizationCreatedConsumer> logger)
    {
        _upserter = upserter;
        _logger = logger;
    }

    public async Task Consume(ConsumeContext<AffinityOrganizationCreatedV1> context)
    {
        try
        {
            await _upserter.UpsertOrganizationCreatedAsync(context.Message, context.CancellationToken);
            _logger.LogInformation("Processed organization.created for {AffinityOrganizationId}", context.Message.AffinityOrganizationId);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed processing organization.created for {AffinityOrganizationId}", context.Message.AffinityOrganizationId);
            throw; // Let MassTransit retry/fault policies handle
        }
    }
}

public sealed class AffinityOrganizationMergedConsumer : IConsumer<AffinityOrganizationMergedV1>
{
    private readonly SqlUpserter _upserter;
    private readonly ILogger<AffinityOrganizationMergedConsumer> _logger;

    public AffinityOrganizationMergedConsumer(SqlUpserter upserter, ILogger<AffinityOrganizationMergedConsumer> logger)
    {
        _upserter = upserter;
        _logger = logger;
    }

    public async Task Consume(ConsumeContext<AffinityOrganizationMergedV1> context)
    {
        try
        {
            await _upserter.ApplyOrganizationMergedAsync(context.Message, context.CancellationToken);
            _logger.LogInformation("Processed organization.merged source={Source} target={Target}",
                context.Message.SourceAffinityOrganizationId, context.Message.TargetAffinityOrganizationId);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed processing organization.merged source={Source} target={Target}",
                context.Message.SourceAffinityOrganizationId, context.Message.TargetAffinityOrganizationId);
            throw;
        }
    }
}
