# Build
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY . .
RUN dotnet restore KLIM.Integrations.sln
RUN dotnet publish src/KLIM.Integrations.Affinity.SqlWriter/KLIM.Integrations.Affinity.SqlWriter.csproj -c Release -o /app/publish /p:UseAppHost=false

# Run
FROM mcr.microsoft.com/dotnet/runtime:8.0
WORKDIR /app
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "KLIM.Integrations.Affinity.SqlWriter.dll"]