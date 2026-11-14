using Lab2;
using Microsoft.Extensions.Configuration;
using MongoDB.Driver;
using Npgsql;

Console.OutputEncoding = System.Text.Encoding.UTF8;

var config = new ConfigurationBuilder()
    .AddUserSecrets<Program>()
    .Build();

var pgConnectionString = config.GetConnectionString("Postgres")
    ?? throw new InvalidOperationException(
        "Немає рядка підключення. Виконайте: dotnet user-secrets set \"ConnectionStrings:Postgres\" \"Host=localhost;Database=bd_lab2;Username=postgres;Password=...\"");
var mongoConnectionString = config.GetConnectionString("Mongo") ?? "mongodb://localhost:27017";

await using var pg = NpgsqlDataSource.Create(pgConnectionString);
var mongo = new MongoClient(mongoConnectionString).GetDatabase("lab2");

var command = args.FirstOrDefault() ?? "all";

if (command is "migrate" or "all")
    await Migration.RunAsync(pg, mongo);

if (command is "bench" or "all")
    await Benchmarks.RunAsync(pg, mongo);

public partial class Program;
