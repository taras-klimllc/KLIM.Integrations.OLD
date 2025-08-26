namespace KLIM.Integrations.Contracts.Events;

public sealed class AffinityOrganizationCreatedV1
{
    public string AffinityOrganizationId { get; init; } = default!;
    public string? Name { get; init; }
    public string? Domain { get; init; }
    public DateTime CreatedAtUtc { get; init; }
}