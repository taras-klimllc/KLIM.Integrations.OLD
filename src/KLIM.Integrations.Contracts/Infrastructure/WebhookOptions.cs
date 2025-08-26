using System.ComponentModel.DataAnnotations;

namespace KLIM.Integrations.Contracts.Infrastructure;

/// <summary>
/// Webhook-specific configuration options for webhook endpoints
/// </summary>
public sealed class WebhookOptions
{
    /// <summary>
    /// Secret key for webhook authentication
    /// Should be a strong, randomly generated string
    /// </summary>
    [Required]
    public string Secret { get; set; } = "REPLACE_WITH_SECRET";
}