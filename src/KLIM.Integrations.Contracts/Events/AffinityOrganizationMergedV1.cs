namespace KLIM.Integrations.Contracts.Events;

public sealed class AffinityOrganizationMergedV1
{
    public string SourceAffinityOrganizationId { get; init; } = default!;
    public string TargetAffinityOrganizationId { get; init; } = default!;
    public DateTime MergedAtUtc { get; init; }
}