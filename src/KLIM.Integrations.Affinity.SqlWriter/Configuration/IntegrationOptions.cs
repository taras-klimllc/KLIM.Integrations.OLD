using System.ComponentModel.DataAnnotations;

namespace KLIM.Integrations.Affinity.SqlWriter.Configuration;

/// <summary>
/// Configuration options for the Affinity SqlWriter integration service
/// </summary>
public sealed class IntegrationOptions
{
    /// <summary>
    /// Service name identifier
    /// </summary>
    [Required]
    public string ServiceName { get; init; } = "KLIM.Integrations.Affinity.SqlWriter";
    
    /// <summary>
    /// Service version for telemetry and diagnostics
    /// </summary>
    public string Version { get; init; } = "1.0.0";
    
    /// <summary>
    /// Enable detailed diagnostic logging
    /// </summary>
    public bool EnableDiagnostics { get; init; } = true;
}