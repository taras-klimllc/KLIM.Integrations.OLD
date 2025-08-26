SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'integration')
    EXEC ('CREATE SCHEMA integration');
GO

IF OBJECT_ID('integration.AffinityOrganizations', 'U') IS NULL
BEGIN
    CREATE TABLE integration.AffinityOrganizations
    (
        AffinityOrganizationId           NVARCHAR(100)  NOT NULL CONSTRAINT PK_integration_AffinityOrganizations PRIMARY KEY,
        IssuerID                         INT            NULL,
        Name                             NVARCHAR(256)  NULL,
        Domain                           NVARCHAR(256)  NULL,
        CreatedDate                      DATETIME2(7)   NOT NULL CONSTRAINT DF_integration_AffinityOrganizations_Created DEFAULT (SYSUTCDATETIME()),
        UpdatedDate                      DATETIME2(7)   NOT NULL CONSTRAINT DF_integration_AffinityOrganizations_Updated DEFAULT (SYSUTCDATETIME()),
        MergedIntoAffinityOrganizationId NVARCHAR(100)  NULL,
        SyncStatus                       NVARCHAR(50)   NOT NULL CONSTRAINT DF_integration_AffinityOrganizations_SyncStatus DEFAULT ('Active'),
        CONSTRAINT FK_integration_AffinityOrganizations_Issuers 
            FOREIGN KEY (IssuerID) REFERENCES dbo.Issuers (IssuerID)
    );

    CREATE NONCLUSTERED INDEX IX_integration_AffinityOrganizations_IssuerID
        ON integration.AffinityOrganizations (IssuerID);

    CREATE NONCLUSTERED INDEX IX_integration_AffinityOrganizations_MergedInto
        ON integration.AffinityOrganizations (MergedIntoAffinityOrganizationId);

    CREATE NONCLUSTERED INDEX IX_integration_AffinityOrganizations_SyncStatus
        ON integration.AffinityOrganizations (SyncStatus);
END
GO