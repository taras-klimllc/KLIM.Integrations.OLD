SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'aff')
    EXEC ('CREATE SCHEMA aff');
GO

IF OBJECT_ID('aff.WebhookEvents', 'U') IS NULL
BEGIN
    CREATE TABLE aff.WebhookEvents
    (
        WebhookEventId      BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_aff_WebhookEvents PRIMARY KEY,
        EventType           NVARCHAR(100) NOT NULL,
        ReceivedAtUtc       DATETIME2(7)  NOT NULL CONSTRAINT DF_aff_WebhookEvents_ReceivedAtUtc DEFAULT (SYSUTCDATETIME()),
        Payload             NVARCHAR(MAX) NOT NULL,
        [Hash]              BINARY(32)    NOT NULL
    );
END
GO