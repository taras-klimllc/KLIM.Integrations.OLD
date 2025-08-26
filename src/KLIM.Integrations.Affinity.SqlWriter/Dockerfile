# =============================================================================
# KLIM Affinity SQL Writer - Multi-stage Docker build
# Optimized for development workflow and production deployment
# =============================================================================

# Build stage
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Copy solution file first for better layer caching
COPY KLIM.Integrations.sln ./

# Copy project files for dependency restoration
COPY src/KLIM.Integrations.Contracts/KLIM.Integrations.Contracts.csproj src/KLIM.Integrations.Contracts/
COPY src/KLIM.Integrations.Affinity.SqlWriter/KLIM.Integrations.Affinity.SqlWriter.csproj src/KLIM.Integrations.Affinity.SqlWriter/

# Restore dependencies (cached layer if project files haven't changed)
RUN dotnet restore src/KLIM.Integrations.Affinity.SqlWriter/KLIM.Integrations.Affinity.SqlWriter.csproj

# Copy source code
COPY src/ src/

# Build and publish in release mode
RUN dotnet publish src/KLIM.Integrations.Affinity.SqlWriter/KLIM.Integrations.Affinity.SqlWriter.csproj \
    -c Release \
    -o /app/publish \
    --no-restore \
    /p:UseAppHost=false \
    /p:PublishTrimmed=false

# Runtime stage
FROM mcr.microsoft.com/dotnet/runtime:8.0 AS runtime

# Install curl for potential health checks and debugging
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Create non-root user for security
RUN groupadd --gid 1001 appgroup && \
    useradd --uid 1001 --gid appgroup --shell /bin/false --create-home appuser

# Set working directory and copy published app
WORKDIR /app
COPY --from=build --chown=appuser:appgroup /app/publish .

# Configure environment for worker service
ENV DOTNET_ENVIRONMENT=Production
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
ENV DOTNET_EnableDiagnostics=0
ENV DOTNET_USE_POLLING_FILE_WATCHER=true

# Switch to non-root user
USER appuser

# Start the worker service
ENTRYPOINT ["dotnet", "KLIM.Integrations.Affinity.SqlWriter.dll"]