# Build
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY . .
RUN dotnet restore KLIM.Integrations.sln
RUN dotnet publish src/KLIM.Integrations.Affinity/KLIM.Integrations.Affinity.csproj -c Release -o /app/publish /p:UseAppHost=false

# Run
FROM mcr.microsoft.com/dotnet/aspnet:8.0
WORKDIR /app
ENV ASPNETCORE_URLS=http://0.0.0.0:8088
COPY --from=build /app/publish .
EXPOSE 8088
ENTRYPOINT ["dotnet", "KLIM.Integrations.Affinity.dll"]