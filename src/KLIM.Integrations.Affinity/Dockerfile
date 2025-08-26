# =============================================================================
# KLIM Affinity Integration API - Multi-stage Docker build
# Optimized for development workflow and production deployment
# =============================================================================

# Build stage
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Copy solution file first for better layer caching
COPY KLIM.Integrations.sln ./

# Copy project files for dependency restoration
COPY src/KLIM.Integrations.Contracts/KLIM.Integrations.Contracts.csproj src/KLIM.Integrations.Contracts/
COPY src/KLIM.Integrations.Affinity/KLIM.Integrations.Affinity.csproj src/KLIM.Integrations.Affinity/

# Restore dependencies (cached layer if project files haven't changed)
RUN dotnet restore src/KLIM.Integrations.Affinity/KLIM.Integrations.Affinity.csproj

# Copy source code
COPY src/ src/

# Build and publish in release mode
RUN dotnet publish src/KLIM.Integrations.Affinity/KLIM.Integrations.Affinity.csproj \
    -c Release \
    -o /app/publish \
    --no-restore \
    /p:UseAppHost=false \
    /p:PublishTrimmed=false

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime

# Create non-root user for security
RUN groupadd --gid 1001 appgroup && \
    useradd --uid 1001 --gid appgroup --shell /bin/false --create-home appuser

# Set working directory and copy published app
WORKDIR /app
COPY --from=build --chown=appuser:appgroup /app/publish .

# Configure environment
ENV ASPNETCORE_URLS=http://0.0.0.0:8088
ENV ASPNETCORE_ENVIRONMENT=Production
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
ENV DOTNET_EnableDiagnostics=0

# Expose port
EXPOSE 8088

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8088/health || exit 1

# Switch to non-root user
USER appuser

# Start the application
ENTRYPOINT ["dotnet", "KLIM.Integrations.Affinity.dll"]