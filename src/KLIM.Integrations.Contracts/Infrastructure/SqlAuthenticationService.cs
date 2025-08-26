using Azure.Core;
using Azure.Identity;
using Microsoft.Data.SqlClient;

namespace KLIM.Integrations.Contracts.Infrastructure;

/// <summary>
/// KLIM Standard: SQL Authentication Service for Azure SQL Database integration
/// Provides centralized authentication handling for both Azure AD and SQL Auth
/// </summary>
public sealed class SqlAuthenticationService
{
    private const string AZURE_SQL_SCOPE = "https://database.windows.net/.default";

    /// <summary>
    /// Acquires Azure AD token for SQL Database access
    /// Uses DefaultAzureCredential for automatic credential discovery
    /// </summary>
    /// <param name="cancellationToken">Cancellation token</param>
    /// <returns>Access token for Azure SQL Database</returns>
    public async Task<string> AcquireTokenAsync(CancellationToken cancellationToken = default)
    {
        var credential = new DefaultAzureCredential();
        var token = await credential.GetTokenAsync(
            new TokenRequestContext(new[] { AZURE_SQL_SCOPE }),
            cancellationToken);
        return token.Token;
    }

    /// <summary>
    /// Sanitizes connection string for Azure AD authentication
    /// Removes User ID and Password when using Azure AD
    /// </summary>
    /// <param name="connectionString">Original connection string</param>
    /// <param name="useAzureAd">Whether to use Azure AD authentication</param>
    /// <returns>Sanitized connection string</returns>
    public string SanitizeConnectionString(string connectionString, bool useAzureAd)
    {
        if (!useAzureAd) return connectionString;

        var builder = new SqlConnectionStringBuilder(connectionString);
        builder.Remove("User ID");
        builder.Remove("Password");
        return builder.ConnectionString;
    }

    /// <summary>
    /// Creates a SQL connection with appropriate authentication
    /// Handles both Azure AD and SQL authentication methods
    /// </summary>
    /// <param name="connectionString">Database connection string</param>
    /// <param name="useAzureAd">Whether to use Azure AD authentication</param>
    /// <param name="cancellationToken">Cancellation token</param>
    /// <returns>Configured SqlConnection</returns>
    public async Task<SqlConnection> CreateConnectionAsync(string connectionString, bool useAzureAd, CancellationToken cancellationToken = default)
    {
        var sanitizedConnectionString = SanitizeConnectionString(connectionString, useAzureAd);
        var conn = new SqlConnection(sanitizedConnectionString);

        // Check if connection string already has Azure AD authentication configured
        var csBuilder = new SqlConnectionStringBuilder(sanitizedConnectionString);
        var hasAzureAdAuth = csBuilder.Authentication == SqlAuthenticationMethod.ActiveDirectoryDefault ||
                            csBuilder.Authentication == SqlAuthenticationMethod.ActiveDirectoryIntegrated ||
                            csBuilder.Authentication == SqlAuthenticationMethod.ActiveDirectoryInteractive ||
                            csBuilder.Authentication == SqlAuthenticationMethod.ActiveDirectoryManagedIdentity ||
                            csBuilder.Authentication == SqlAuthenticationMethod.ActiveDirectoryServicePrincipal ||
                            csBuilder.Authentication == SqlAuthenticationMethod.ActiveDirectoryDeviceCodeFlow;

        // Only set AccessToken if using Azure AD but connection string doesn't already specify Azure AD authentication
        if (useAzureAd && !hasAzureAdAuth)
        {
            conn.AccessToken = await AcquireTokenAsync(cancellationToken);
        }

        return conn;
    }

    /// <summary>
    /// Opens a SQL connection with appropriate authentication
    /// Convenience method that creates and opens the connection
    /// </summary>
    /// <param name="connectionString">Database connection string</param>
    /// <param name="useAzureAd">Whether to use Azure AD authentication</param>
    /// <param name="ct">Cancellation token</param>
    /// <returns>Open SqlConnection</returns>
    public async Task<SqlConnection> OpenConnectionAsync(string connectionString, bool useAzureAd, CancellationToken ct = default)
    {
        var conn = await CreateConnectionAsync(connectionString, useAzureAd, ct);
        await conn.OpenAsync(ct);
        return conn;
    }
}