using System.Data;
using System.Security.Cryptography;
using System.Text;
using Dapper;

namespace KLIM.Integrations.Affinity.Infrastructure;

public static class SqlHelpers
{
    public static byte[] Sha256(string text)
    {
        var bytes = Encoding.UTF8.GetBytes(text);
        return SHA256.HashData(bytes);
    }

    /// <summary>
    /// Inserts if the hash doesn't exist; returns (inserted, webhookEventId).
    /// Uses UPDLOCK/HOLDLOCK to prevent duplicates racing in.
    /// </summary>
    public static async Task<(bool Inserted, long? Id)> InsertWebhookEventIfNewAsync(
        IDbConnection conn, IDbTransaction tx, string eventType, string payload, CancellationToken ct)
    {
        var hash = Sha256(payload);

        var existsSql = """
            SELECT TOP (1) WebhookEventId
            FROM aff.WebhookEvents WITH (UPDLOCK, HOLDLOCK)
            WHERE [Hash] = @Hash;
            """;

        var existing = await conn.ExecuteScalarAsync<long?>(new CommandDefinition(
            existsSql, new { Hash = hash }, tx, cancellationToken: ct));

        if (existing.HasValue)
            return (false, existing.Value);

        var insertSql = """
            INSERT INTO aff.WebhookEvents (EventType, Payload, [Hash], ReceivedAtUtc)
            VALUES (@EventType, @Payload, @Hash, SYSUTCDATETIME());
            SELECT CAST(SCOPE_IDENTITY() as bigint);
            """;

        var id = await conn.ExecuteScalarAsync<long>(new CommandDefinition(
            insertSql, new { EventType = eventType, Payload = payload, Hash = hash }, tx, cancellationToken: ct));

        return (true, id);
    }
}