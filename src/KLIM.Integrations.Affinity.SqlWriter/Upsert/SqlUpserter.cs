using Dapper;
using KLIM.Integrations.Contracts.Events;
using KLIM.Integrations.Contracts.Infrastructure;
using Microsoft.Data.SqlClient;
using System.Data;

namespace KLIM.Integrations.Affinity.SqlWriter.Upsert;

public sealed class SqlUpserter
{
    private readonly SqlAuthenticationService _authService;
    private readonly DatabaseOptions _databaseOptions;

    public SqlUpserter(SqlAuthenticationService authService, DatabaseOptions databaseOptions)
    {
        _authService = authService;
        _databaseOptions = databaseOptions;
    }

    public async Task UpsertOrganizationCreatedAsync(AffinityOrganizationCreatedV1 evt, CancellationToken ct)
    {
        await using var conn = await _authService.OpenConnectionAsync(_databaseOptions.ConnectionString, _databaseOptions.UseAzureAd, ct);
        await using var tx = await conn.BeginTransactionAsync(IsolationLevel.Serializable, ct);

        // Resolve or create IssuerID (do NOT modify dbo.Issuers schema)
        var issuerId = await ResolveOrCreateIssuerAsync(conn, (SqlTransaction)tx, evt.Name, evt.Domain, ct);

        var mergeSql = """
            MERGE integration.AffinityOrganizations AS target
            USING (VALUES (@AffinityOrganizationId, @IssuerID, @Name, @Domain)) AS src (AffinityOrganizationId, IssuerID, Name, Domain)
            ON (target.AffinityOrganizationId = src.AffinityOrganizationId)
            WHEN MATCHED THEN UPDATE SET
                target.IssuerID = src.IssuerID,
                target.Name = COALESCE(src.Name, target.Name),
                target.Domain = COALESCE(src.Domain, target.Domain),
                target.UpdatedDate = SYSUTCDATETIME(),
                target.SyncStatus = CASE WHEN target.SyncStatus = 'Merged' THEN target.SyncStatus ELSE 'Active' END
            WHEN NOT MATCHED THEN
                INSERT (AffinityOrganizationId, IssuerID, Name, Domain, CreatedDate, UpdatedDate, SyncStatus)
                VALUES (src.AffinityOrganizationId, src.IssuerID, src.Name, src.Domain, SYSUTCDATETIME(), SYSUTCDATETIME(), 'Active');
            """;

        await conn.ExecuteAsync(new CommandDefinition(
            mergeSql,
            new { evt.AffinityOrganizationId, IssuerID = issuerId, evt.Name, evt.Domain },
            (SqlTransaction)tx, cancellationToken: ct));

        await tx.CommitAsync(ct);
    }

    public async Task ApplyOrganizationMergedAsync(AffinityOrganizationMergedV1 evt, CancellationToken ct)
    {
        await using var conn = await _authService.OpenConnectionAsync(_databaseOptions.ConnectionString, _databaseOptions.UseAzureAd, ct);
        await using var tx = await conn.BeginTransactionAsync(IsolationLevel.Serializable, ct);

        var updateSql = """
            UPDATE integration.AffinityOrganizations
            SET MergedIntoAffinityOrganizationId = @Target,
                SyncStatus = 'Merged',
                UpdatedDate = SYSUTCDATETIME()
            WHERE AffinityOrganizationId = @Source;
            """;

        await conn.ExecuteAsync(new CommandDefinition(
            updateSql, new { Source = evt.SourceAffinityOrganizationId, Target = evt.TargetAffinityOrganizationId },
            (SqlTransaction)tx, cancellationToken: ct));

        await tx.CommitAsync(ct);
    }

    private static async Task<int> ResolveOrCreateIssuerAsync(SqlConnection conn, SqlTransaction tx, string? name, string? domain, CancellationToken ct)
    {
        var selectSql = """
            SELECT TOP (1) IssuerID
            FROM dbo.Issuers WITH (UPDLOCK, HOLDLOCK)
            WHERE (@Domain IS NOT NULL AND Domain = @Domain)
               OR (@Name IS NOT NULL AND Name = @Name)
            ORDER BY IssuerID;
            """;

        var existing = await conn.ExecuteScalarAsync<int?>(new CommandDefinition(
            selectSql, new { Domain = domain, Name = name }, tx, cancellationToken: ct));

        if (existing.HasValue)
            return existing.Value;

        var insertSql = """
            INSERT INTO dbo.Issuers (Name, Domain, CreatedDate, UpdatedDate)
            OUTPUT INSERTED.IssuerID
            VALUES (@Name, @Domain, SYSUTCDATETIME(), SYSUTCDATETIME());
            """;

        var issuerId = await conn.ExecuteScalarAsync<int>(new CommandDefinition(
            insertSql, new { Name = name ?? "(unknown)", Domain = domain }, tx, cancellationToken: ct));

        return issuerId;
    }
}