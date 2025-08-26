using System.ComponentModel.DataAnnotations;

namespace KLIM.Integrations.Contracts.Infrastructure;

/// <summary>
/// KLIM Standard: Database configuration options for integration services
/// Provides consistent database connection settings across all services
/// </summary>
public sealed class DatabaseOptions
{
    /// <summary>
    /// SQL Server connection string
    /// Should include server, database, and authentication details
    /// </summary>
    [Required]
    public string ConnectionString { get; set; } = string.Empty;
    
    /// <summary>
    /// Whether to use Azure Active Directory authentication
    /// When true, uses DefaultAzureCredential for authentication
    /// When false, uses connection string credentials (SQL Auth)
    /// </summary>
    public bool UseAzureAd { get; set; } = false;
    
    /// <summary>
    /// Diagnostic service interval in minutes
    /// Controls how often diagnostic information is logged
    /// Minimum value is 1 minute, default is 5 minutes
    /// </summary>
    [Range(1, 1440, ErrorMessage = "Diagnostics interval must be between 1 and 1440 minutes")]
    public int DiagnosticsIntervalMinutes { get; set; } = 5;
}