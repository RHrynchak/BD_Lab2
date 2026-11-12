using System.Diagnostics;
using System.Globalization;
using System.Text;
using MongoDB.Bson;
using MongoDB.Driver;
using Npgsql;

namespace Lab2;

/// <summary>
/// Тести швидкодії: однакові сценарії для PostgreSQL та MongoDB.
///
/// Методика (однакова для обох баз):
///  * Обидві бази локальні, запит іде з цієї ж програми через офіційний драйвер
///    (Npgsql / MongoDB.Driver), з пулом з'єднань - так само, як працював би вебзастосунок.
///  * Вимірюється повний час "запит -> відповідь прочитана": мережа (localhost),
///    виконання запиту в базі і читання результату в програму.
///  * Перед вимірюванням - прогрів (warmup): кеш бази, пул з'єднань, JIT .NET.
///  * Параметри (id замовлень, клієнтів, місяці) генеруються випадково з фіксованим seed,
///    і обидві бази отримують ТІ САМІ параметри в тому ж порядку.
///  * Рахуємо середнє, медіану, 95-й перцентиль (p95), мінімум і максимум.
///    Медіана і p95 важливіші за середнє: середнє "псують" поодинокі затримки (GC, диск).
/// </summary>
public static class Benchmarks
{
    private const int Seed = 42;

    private sealed record Result(string Test, string Db, int N, double Mean, double Median, double P95, double Min, double Max);

    private sealed record ProductInfo(int Id, string Name, string Sku, string Category, string MainCategory, decimal Price);

    private static readonly List<Result> Results = [];

    public static async Task RunAsync(NpgsqlDataSource pg, IMongoDatabase mongo)
    {
        Console.WriteLine();
        Console.WriteLine("=== Тести швидкодії ===");
        var orders = mongo.GetCollection<BsonDocument>("orders");

        var maxOrderId = (int)(await pg.CreateCommand("""SELECT max("Id") FROM "Order" WHERE "Id" <= 300000""").ExecuteScalarAsync())!;
        var maxCustomerId = (int)(await pg.CreateCommand("""SELECT max("Id") FROM "Customer" """).ExecuteScalarAsync())!;
        await CleanupInsertedAsync(pg, orders, maxOrderId);

        await TestOrderByIdAsync(pg, orders, maxOrderId);
        await TestCustomerHistoryAsync(pg, orders, maxCustomerId, "T2. Історія клієнта (10 останніх)", warmup: 100, n: 1000);
        await TestInsertOrderAsync(pg, orders, maxOrderId, maxCustomerId);
        await TestSalesByCategoryAsync(pg, orders);
        await TestHistoryWithoutIndexAsync(pg, orders, maxCustomerId);

        await WriteReportAsync(pg, mongo, orders);
    }

    // ------------------------------------------------------------------
    // T1. Отримати одне замовлення з усіма деталями за Id.
    // Типова операція: відкрити чек / сторінку замовлення.
    // SQL: JOIN 8 таблиць. Mongo: пошук одного документа за _id.
    // ------------------------------------------------------------------
    private static async Task TestOrderByIdAsync(NpgsqlDataSource pg, IMongoCollection<BsonDocument> orders, int maxOrderId)
    {
        const string test = "T1. Замовлення за Id з деталями";
        const int warmup = 200, n = 2000;
        var rnd = new Random(Seed);
        var ids = Enumerable.Range(0, warmup + n).Select(_ => rnd.Next(1, maxOrderId + 1)).ToArray();

        const string sql = """
            SELECT o."Id", o."OrderDate", o."TotalAmount",
                   c."Id", c."FirstName", c."LastName", c."Phone",
                   e."Id", e."FirstName", e."LastName",
                   d."Id", d."Name", s."Name",
                   p."Id", p."Name", p."SKU", cat."Name",
                   oi."Quantity", oi."UnitPrice"
            FROM "Order" o
            LEFT JOIN "Customer" c ON c."Id" = o."CustomerId"
            JOIN "Employee" e      ON e."Id" = o."EmployeeId"
            JOIN "Department" d    ON d."Id" = e."DepartmentId"
            JOIN "Store" s         ON s."Id" = d."StoreId"
            JOIN "OrderItem" oi    ON oi."OrderId" = o."Id"
            JOIN "Product" p       ON p."Id" = oi."ProductId"
            JOIN "Category" cat    ON cat."Id" = p."CategoryId"
            WHERE o."Id" = @id
            """;

        await MeasureAsync(test, "PostgreSQL", warmup, n, async i =>
        {
            await using var cmd = pg.CreateCommand(sql);
            cmd.Parameters.AddWithValue("id", ids[i]);
            await ReadAllAsync(cmd);
        });

        await MeasureAsync(test, "MongoDB", warmup, n, async i =>
        {
            var doc = await orders.Find(Builders<BsonDocument>.Filter.Eq("_id", ids[i])).FirstOrDefaultAsync();
            if (doc == null) throw new Exception($"Замовлення {ids[i]} не знайдено в Mongo");
        });
    }

    // ------------------------------------------------------------------
    // T2. Історія покупок клієнта: 10 останніх замовлень з позиціями.
    // Типова операція: особистий кабінет / картка лояльності.
    // ------------------------------------------------------------------
    private const string HistorySql = """
        WITH last_orders AS (
            SELECT * FROM "Order"
            WHERE "CustomerId" = @id
            ORDER BY "OrderDate" DESC
            LIMIT 10
        )
        SELECT o."Id", o."OrderDate", o."TotalAmount",
               e."FirstName", e."LastName", d."Name", s."Name",
               p."Id", p."Name", p."SKU", cat."Name",
               oi."Quantity", oi."UnitPrice"
        FROM last_orders o
        JOIN "Employee" e   ON e."Id" = o."EmployeeId"
        JOIN "Department" d ON d."Id" = e."DepartmentId"
        JOIN "Store" s      ON s."Id" = d."StoreId"
        JOIN "OrderItem" oi ON oi."OrderId" = o."Id"
        JOIN "Product" p    ON p."Id" = oi."ProductId"
        JOIN "Category" cat ON cat."Id" = p."CategoryId"
        ORDER BY o."OrderDate" DESC
        """;

    private static async Task TestCustomerHistoryAsync(NpgsqlDataSource pg, IMongoCollection<BsonDocument> orders,
        int maxCustomerId, string test, int warmup, int n)
    {
        var rnd = new Random(Seed + 1);
        var ids = Enumerable.Range(0, warmup + n).Select(_ => rnd.Next(1, maxCustomerId + 1)).ToArray();

        await MeasureAsync(test, "PostgreSQL", warmup, n, async i =>
        {
            await using var cmd = pg.CreateCommand(HistorySql);
            cmd.Parameters.AddWithValue("id", ids[i]);
            await ReadAllAsync(cmd);
        });

        await MeasureAsync(test, "MongoDB", warmup, n, async i =>
        {
            await orders.Find(Builders<BsonDocument>.Filter.Eq("customer.id", ids[i]))
                .Sort(Builders<BsonDocument>.Sort.Descending("date"))
                .Limit(10)
                .ToListAsync();
        });
    }

    // ------------------------------------------------------------------
    // T3. Створення нового замовлення (каса пробиває чек).
    // SQL: транзакція - INSERT в Order + INSERT кількох рядків в OrderItem.
    // Mongo: один insertOne (документ вже містить усе).
    // Тестуємо Mongo двічі:
    //   w:1          - налаштування за замовчуванням (підтвердження після запису в пам'ять)
    //   w:1, j:true  - чекати запису в журнал на диску; це чесний аналог COMMIT у PostgreSQL
    //                  (synchronous_commit = on чекає запису WAL на диск).
    // Після тесту вставлені замовлення видаляються, щоб дані залишались однаковими.
    // ------------------------------------------------------------------
    private static async Task TestInsertOrderAsync(NpgsqlDataSource pg, IMongoCollection<BsonDocument> orders,
        int maxOrderId, int maxCustomerId)
    {
        const string test = "T3. Створення замовлення";
        const int warmup = 50, n = 1000;

        var products = new List<ProductInfo>();
        await using (var cmd = pg.CreateCommand("""
            SELECT p."Id", p."Name", p."SKU", c."Name", parent."Name", p."Price"
            FROM "Product" p
            JOIN "Category" c ON c."Id" = p."CategoryId"
            JOIN "Category" parent ON parent."Id" = c."ParentCategoryId"
            """))
        await using (var r = await cmd.ExecuteReaderAsync())
            while (await r.ReadAsync())
                products.Add(new ProductInfo(r.GetInt32(0), r.GetString(1), r.GetString(2), r.GetString(3), r.GetString(4), r.GetDecimal(5)));

        // Однаковий набір нових замовлень для обох баз
        var rnd = new Random(Seed + 2);
        var newOrders = Enumerable.Range(0, warmup + n).Select(_ => new
        {
            CustomerId = rnd.Next(1, maxCustomerId + 1),
            EmployeeId = rnd.Next(1, 301),
            Items = Enumerable.Range(0, rnd.Next(1, 8))
                .Select(_ => (Product: products[rnd.Next(products.Count)], Qty: rnd.Next(1, 4)))
                .ToArray(),
        }).ToArray();

        await MeasureAsync(test, "PostgreSQL", warmup, n, async i =>
        {
            var o = newOrders[i];
            var total = o.Items.Sum(x => x.Product.Price * x.Qty);

            await using var conn = await pg.OpenConnectionAsync();
            await using var tx = await conn.BeginTransactionAsync();

            await using var insertOrder = new NpgsqlCommand("""
                INSERT INTO "Order" ("CustomerId", "EmployeeId", "OrderDate", "TotalAmount")
                VALUES (@c, @e, now(), @t) RETURNING "Id"
                """, conn, tx);
            insertOrder.Parameters.AddWithValue("c", o.CustomerId);
            insertOrder.Parameters.AddWithValue("e", o.EmployeeId);
            insertOrder.Parameters.AddWithValue("t", total);
            var orderId = (int)(await insertOrder.ExecuteScalarAsync())!;

            // Усі позиції - одним INSERT з кількома VALUES
            var sb = new StringBuilder("""INSERT INTO "OrderItem" ("OrderId", "ProductId", "Quantity", "UnitPrice") VALUES """);
            await using var insertItems = new NpgsqlCommand { Connection = conn, Transaction = tx };
            for (var k = 0; k < o.Items.Length; k++)
            {
                if (k > 0) sb.Append(',');
                sb.Append($"(@o, @p{k}, @q{k}, @u{k})");
                insertItems.Parameters.AddWithValue($"p{k}", o.Items[k].Product.Id);
                insertItems.Parameters.AddWithValue($"q{k}", o.Items[k].Qty);
                insertItems.Parameters.AddWithValue($"u{k}", o.Items[k].Product.Price);
            }
            insertItems.Parameters.AddWithValue("o", orderId);
            insertItems.CommandText = sb.ToString();
            await insertItems.ExecuteNonQueryAsync();

            await tx.CommitAsync();
        });

        BsonDocument BuildDocument(int id, int i)
        {
            var o = newOrders[i];
            return new BsonDocument
            {
                { "_id", id },
                { "date", DateTime.UtcNow },
                { "total", new Decimal128(o.Items.Sum(x => x.Product.Price * x.Qty)) },
                { "customer", new BsonDocument { { "id", o.CustomerId }, { "name", "Тест Клієнт" }, { "phone", "+380670000000" } } },
                { "employee", new BsonDocument { { "id", o.EmployeeId }, { "name", "Тест Касир" } } },
                { "department", new BsonDocument { { "id", 1 }, { "name", "Продукти" }, { "store", "Мегамаркет Центр" } } },
                { "items", new BsonArray(o.Items.Select(x => new BsonDocument
                    {
                        { "productId", x.Product.Id },
                        { "name", x.Product.Name },
                        { "sku", x.Product.Sku },
                        { "category", x.Product.Category },
                        { "mainCategory", x.Product.MainCategory },
                        { "qty", x.Qty },
                        { "price", new Decimal128(x.Product.Price) },
                    })) },
            };
        }

        await MeasureAsync(test, "MongoDB (w:1)", warmup, n, async i =>
            await orders.InsertOneAsync(BuildDocument(1_000_000 + i, i)));

        var journaled = orders.WithWriteConcern(new WriteConcern(w: 1, journal: true));
        await MeasureAsync(test, "MongoDB (w:1, j:true)", warmup, n, async i =>
            await journaled.InsertOneAsync(BuildDocument(2_000_000 + i, i)));

        await CleanupInsertedAsync(pg, orders, maxOrderId);
    }

    // ------------------------------------------------------------------
    // T4. Аналітика: виручка по категоріях товарів за місяць.
    // SQL: JOIN 4 таблиць + GROUP BY. Mongo: aggregation pipeline ($match -> $unwind -> $group).
    // Цей тест "незручний" для Mongo: треба розгорнути масиви позицій.
    // ------------------------------------------------------------------
    private static async Task TestSalesByCategoryAsync(NpgsqlDataSource pg, IMongoCollection<BsonDocument> orders)
    {
        const string test = "T4. Виручка по категоріях за місяць";
        const int warmup = 3, n = 30;
        var rnd = new Random(Seed + 3);
        // Випадковий місяць з періоду даних (01.2025 - 10.2026)
        var months = Enumerable.Range(0, warmup + n)
            .Select(_ => new DateTime(2025, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddMonths(rnd.Next(0, 22)))
            .ToArray();

        const string sql = """
            SELECT cat."Name", sum(oi."Quantity" * oi."UnitPrice") AS revenue
            FROM "Order" o
            JOIN "OrderItem" oi ON oi."OrderId" = o."Id"
            JOIN "Product" p    ON p."Id" = oi."ProductId"
            JOIN "Category" cat ON cat."Id" = p."CategoryId"
            WHERE o."OrderDate" >= @from AND o."OrderDate" < @to
            GROUP BY cat."Name"
            """;

        await MeasureAsync(test, "PostgreSQL", warmup, n, async i =>
        {
            await using var cmd = pg.CreateCommand(sql);
            cmd.Parameters.AddWithValue("from", DateTime.SpecifyKind(months[i], DateTimeKind.Unspecified));
            cmd.Parameters.AddWithValue("to", DateTime.SpecifyKind(months[i].AddMonths(1), DateTimeKind.Unspecified));
            await ReadAllAsync(cmd);
        });

        await MeasureAsync(test, "MongoDB", warmup, n, async i =>
        {
            BsonDocument[] pipeline =
            [
                new("$match", new BsonDocument("date", new BsonDocument { { "$gte", months[i] }, { "$lt", months[i].AddMonths(1) } })),
                new("$unwind", "$items"),
                new("$group", new BsonDocument
                {
                    { "_id", "$items.category" },
                    { "revenue", new BsonDocument("$sum", new BsonDocument("$multiply", new BsonArray { "$items.qty", "$items.price" })) },
                }),
            ];
            await orders.Aggregate<BsonDocument>(pipeline).ToListAsync();
        });
    }

    // ------------------------------------------------------------------
    // T5. Той самий запит, що T2, але БЕЗ індексу по клієнту в обох базах.
    // Показує, наскільки обидві бази залежать від індексів:
    // без індексу обидві читають усі 300 000 замовлень (Seq Scan / COLLSCAN).
    // ------------------------------------------------------------------
    private static async Task TestHistoryWithoutIndexAsync(NpgsqlDataSource pg, IMongoCollection<BsonDocument> orders, int maxCustomerId)
    {
        Console.WriteLine("  (видаляю індекси по клієнту на час тесту T5)");
        await pg.CreateCommand("""DROP INDEX IF EXISTS idx_order_customerid""").ExecuteNonQueryAsync();
        await orders.Indexes.DropOneAsync("idx_customer_id");
        try
        {
            await TestCustomerHistoryAsync(pg, orders, maxCustomerId, "T5. Історія клієнта БЕЗ індексу", warmup: 2, n: 30);
        }
        finally
        {
            await pg.CreateCommand("""CREATE INDEX idx_order_customerid ON "Order" USING btree ("CustomerId")""").ExecuteNonQueryAsync();
            await orders.Indexes.CreateOneAsync(new CreateIndexModel<BsonDocument>(
                Builders<BsonDocument>.IndexKeys.Ascending("customer.id"), new CreateIndexOptions { Name = "idx_customer_id" }));
            Console.WriteLine("  (індекси відновлено)");
        }
    }

    // ------------------------------------------------------------------
    // Допоміжне
    // ------------------------------------------------------------------
    private static async Task MeasureAsync(string test, string db, int warmup, int n, Func<int, Task> action)
    {
        Console.Write($"  {test} | {db} ... ");

        for (var i = 0; i < warmup; i++)
            await action(i);

        var times = new double[n];
        var sw = new Stopwatch();
        for (var i = 0; i < n; i++)
        {
            sw.Restart();
            await action(warmup + i);
            times[i] = sw.Elapsed.TotalMilliseconds;
        }

        Array.Sort(times);
        var result = new Result(test, db, n,
            Mean: times.Average(),
            Median: times[n / 2],
            P95: times[(int)Math.Ceiling(n * 0.95) - 1],
            Min: times[0],
            Max: times[^1]);
        Results.Add(result);
        Console.WriteLine($"медіана {result.Median:F3} мс, p95 {result.P95:F3} мс");
    }

    // Читаємо всі рядки й усі колонки - щоб PostgreSQL, як і Mongo, повністю передав і віддав дані.
    private static async Task ReadAllAsync(NpgsqlCommand cmd)
    {
        await using var reader = await cmd.ExecuteReaderAsync();
        var values = new object[reader.FieldCount];
        while (await reader.ReadAsync())
            reader.GetValues(values);
    }

    private static async Task CleanupInsertedAsync(NpgsqlDataSource pg, IMongoCollection<BsonDocument> orders, int maxOrderId)
    {
        await using var cmd = pg.CreateCommand("""
            DELETE FROM "OrderItem" WHERE "OrderId" > @max;
            DELETE FROM "Order" WHERE "Id" > @max;
            """);
        cmd.Parameters.AddWithValue("max", maxOrderId);
        await cmd.ExecuteNonQueryAsync();
        await orders.DeleteManyAsync(Builders<BsonDocument>.Filter.Gte("_id", 1_000_000));
    }

    private static async Task WriteReportAsync(NpgsqlDataSource pg, IMongoDatabase mongo, IMongoCollection<BsonDocument> orders)
    {
        var ci = CultureInfo.InvariantCulture;
        var pgVersion = (string)(await pg.CreateCommand("SHOW server_version").ExecuteScalarAsync())!;
        var mongoVersion = (await mongo.RunCommandAsync<BsonDocument>(new BsonDocument("buildInfo", 1)))["version"].AsString;

        // Розмір даних на диску
        var pgSize = (long)(await pg.CreateCommand("""
            SELECT sum(pg_total_relation_size(t))::bigint
            FROM unnest(ARRAY['"Order"','"OrderItem"','"Product"','"Category"',
                              '"Customer"','"Employee"','"Department"','"Store"']::regclass[]) AS t
            """).ExecuteScalarAsync())!;
        BsonDocument[] collStats = [new("$collStats", new BsonDocument("storageStats", new BsonDocument()))];
        var stats = await orders.Aggregate<BsonDocument>(collStats).FirstAsync();
        var storage = stats["storageStats"].AsBsonDocument;
        var mongoData = storage["size"].ToInt64();
        var mongoDisk = storage["storageSize"].ToInt64() + storage["totalIndexSize"].ToInt64();

        var sb = new StringBuilder();
        sb.AppendLine("# Результати тестів швидкодії");
        sb.AppendLine();
        sb.AppendLine($"- Дата: {DateTime.Now:yyyy-MM-dd HH:mm}");
        sb.AppendLine($"- PostgreSQL {pgVersion}, MongoDB {mongoVersion}, .NET {Environment.Version}");
        sb.AppendLine($"- {Environment.OSVersion}, логічних ядер: {Environment.ProcessorCount}");
        sb.AppendLine("- Час у мілісекундах, повний цикл \"запит -> результат прочитано програмою\"");
        sb.AppendLine();
        sb.AppendLine("| Тест | База | N | Середнє | Медіана | p95 | Мін | Макс |");
        sb.AppendLine("|---|---|---:|---:|---:|---:|---:|---:|");
        foreach (var r in Results)
            sb.AppendLine(string.Format(ci, "| {0} | {1} | {2} | {3:F3} | {4:F3} | {5:F3} | {6:F3} | {7:F3} |",
                r.Test, r.Db, r.N, r.Mean, r.Median, r.P95, r.Min, r.Max));
        sb.AppendLine();
        sb.AppendLine("## Розмір даних");
        sb.AppendLine();
        sb.AppendLine("| | Розмір |");
        sb.AppendLine("|---|---:|");
        sb.AppendLine($"| PostgreSQL: 8 таблиць замовлень разом з індексами | {(pgSize / 1024.0 / 1024).ToString("F1", ci)} МБ |");
        sb.AppendLine($"| MongoDB: колекція orders, дані без стиснення | {(mongoData / 1024.0 / 1024).ToString("F1", ci)} МБ |");
        sb.AppendLine($"| MongoDB: колекція orders на диску (стиснення + індекси) | {(mongoDisk / 1024.0 / 1024).ToString("F1", ci)} МБ |");

        var dir = FindRepoRoot();
        Directory.CreateDirectory(Path.Combine(dir, "results"));
        var path = Path.Combine(dir, "results", "results.md");
        await File.WriteAllTextAsync(path, sb.ToString());

        // У консоль - таблиця з вирівняними колонками (Markdown у консолі читається погано)
        Console.WriteLine();
        Console.WriteLine("=== Результати (мс) ===");
        string[] header = ["Тест", "База", "N", "Середнє", "Медіана", "p95", "Мін", "Макс"];
        var rows = Results.Select(r => new[]
        {
            r.Test, r.Db, r.N.ToString(ci),
            r.Mean.ToString("F3", ci), r.Median.ToString("F3", ci), r.P95.ToString("F3", ci),
            r.Min.ToString("F3", ci), r.Max.ToString("F3", ci),
        }).ToList();
        var widths = header.Select((h, c) => Math.Max(h.Length, rows.Max(row => row[c].Length))).ToArray();

        string FormatRow(string[] cells) => string.Join("  ", cells.Select((cell, c) =>
            c < 2 ? cell.PadRight(widths[c]) : cell.PadLeft(widths[c])));

        Console.WriteLine(FormatRow(header));
        Console.WriteLine(new string('-', widths.Sum() + 2 * (widths.Length - 1)));
        string? previousTest = null;
        foreach (var row in rows)
        {
            if (previousTest != null && row[0] != previousTest) Console.WriteLine();
            Console.WriteLine(FormatRow(row));
            previousTest = row[0];
        }

        Console.WriteLine();
        Console.WriteLine("=== Розмір даних ===");
        Console.WriteLine($"PostgreSQL (8 таблиць з індексами):        {(pgSize / 1024.0 / 1024).ToString("F1", ci),8} МБ");
        Console.WriteLine($"MongoDB orders, дані без стиснення:        {(mongoData / 1024.0 / 1024).ToString("F1", ci),8} МБ");
        Console.WriteLine($"MongoDB orders на диску (стиснення+індекси): {(mongoDisk / 1024.0 / 1024).ToString("F1", ci),6} МБ");
        Console.WriteLine();
        Console.WriteLine($"Звіт збережено: {path}");
    }

    private static string FindRepoRoot()
    {
        var dir = new DirectoryInfo(Directory.GetCurrentDirectory());
        while (dir != null && !Directory.Exists(Path.Combine(dir.FullName, ".git")))
            dir = dir.Parent;
        return dir?.FullName ?? Directory.GetCurrentDirectory();
    }
}
