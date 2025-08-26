-- Unique hash-based dedupe
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_aff_WebhookEvents_Hash' AND object_id = OBJECT_ID('aff.WebhookEvents'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_aff_WebhookEvents_Hash
        ON aff.WebhookEvents ([Hash])
        WITH (FILLFACTOR = 100, IGNORE_DUP_KEY = ON);
END
GO

-- Lookup indexes
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_aff_WebhookEvents_EventType' AND object_id = OBJECT_ID('aff.WebhookEvents'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_aff_WebhookEvents_EventType
        ON aff.WebhookEvents (EventType);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_aff_WebhookEvents_ReceivedAtUtc' AND object_id = OBJECT_ID('aff.WebhookEvents'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_aff_WebhookEvents_ReceivedAtUtc
        ON aff.WebhookEvents (ReceivedAtUtc);
END
GO