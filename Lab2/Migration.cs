using System.Diagnostics;
using MongoDB.Bson;
using MongoDB.Driver;
using Npgsql;

namespace Lab2;

/// <summary>
/// Переносить замовлення з PostgreSQL у MongoDB.
///
/// Одне замовлення в SQL займає рядки у 8 таблицях:
///   Order + OrderItem + Product + Category + Customer + Employee + Department + Store.
/// У Mongo це один документ: позиції вкладені масивом, а клієнт, касир, відділ і назви
/// товарів зберігаються як "знімок" на момент покупки (як надруковано в чеку).
/// </summary>
public static class Migration
{
    // Один рядок = одна позиція замовлення разом з усіма даними, потрібними документу.
    private const string Sql = """
        SELECT o."Id", o."OrderDate", o."TotalAmount",
               c."Id", c."FirstName", c."LastName", c."Phone",
               e."Id", e."FirstName", e."LastName",
               d."Id", d."Name", s."Name",
               p."Id", p."Name", p."SKU", cat."Name", parent."Name",
               oi."Quantity", oi."UnitPrice"
        FROM "Order" o
        LEFT JOIN "Customer" c   ON c."Id" = o."CustomerId"
        JOIN "Employee" e        ON e."Id" = o."EmployeeId"
        JOIN "Department" d      ON d."Id" = e."DepartmentId"
        JOIN "Store" s           ON s."Id" = d."StoreId"
        JOIN "OrderItem" oi      ON oi."OrderId" = o."Id"
        JOIN "Product" p         ON p."Id" = oi."ProductId"
        JOIN "Category" cat      ON cat."Id" = p."CategoryId"
        LEFT JOIN "Category" parent ON parent."Id" = cat."ParentCategoryId"
        ORDER BY o."Id", oi."Id"
        """;

    public static async Task RunAsync(NpgsqlDataSource pg, IMongoDatabase mongo)
    {
        Console.WriteLine("=== Міграція PostgreSQL -> MongoDB ===");
        var sw = Stopwatch.StartNew();

        await mongo.DropCollectionAsync("orders");
        var orders = mongo.GetCollection<BsonDocument>("orders");

        await using var cmd = pg.CreateCommand(Sql);
        await using var reader = await cmd.ExecuteReaderAsync();

        var batch = new List<BsonDocument>(5000);
        BsonDocument? current = null;
        BsonArray? items = null;
        var total = 0;

        while (await reader.ReadAsync())
        {
            var orderId = reader.GetInt32(0);

            // Рядки відсортовані за Id замовлення: новий Id = новий документ
            if (current == null || current["_id"].AsInt32 != orderId)
            {
                if (current != null) batch.Add(current);
                if (batch.Count == 5000)
                {
                    await orders.InsertManyAsync(batch, new InsertManyOptions { IsOrdered = false });
                    total += batch.Count;
                    batch.Clear();
                    Console.Write($"\r  перенесено {total:N0} замовлень...");
                }

                items = new BsonArray();
                current = new BsonDocument
                {
                    { "_id", orderId },
                    { "date", DateTime.SpecifyKind(reader.GetDateTime(1), DateTimeKind.Utc) },
                    { "total", new Decimal128(reader.GetDecimal(2)) },
                    { "customer", reader.IsDBNull(3)
                        ? BsonNull.Value
                        : new BsonDocument
                        {
                            { "id", reader.GetInt32(3) },
                            { "name", $"{reader.GetString(4)} {(reader.IsDBNull(5) ? "" : reader.GetString(5))}".Trim() },
                            { "phone", reader.GetString(6) },
                        } },
                    { "employee", new BsonDocument
                        {
                            { "id", reader.GetInt32(7) },
                            { "name", $"{reader.GetString(8)} {reader.GetString(9)}" },
                        } },
                    { "department", new BsonDocument
                        {
                            { "id", reader.GetInt32(10) },
                            { "name", reader.GetString(11) },
                            { "store", reader.GetString(12) },
                        } },
                    { "items", items },
                };
            }

            items!.Add(new BsonDocument
            {
                { "productId", reader.GetInt32(13) },
                { "name", reader.GetString(14) },
                { "sku", reader.GetString(15) },
                { "category", reader.GetString(16) },
                { "mainCategory", reader.IsDBNull(17) ? BsonNull.Value : reader.GetString(17) },
                { "qty", reader.GetInt32(18) },
                { "price", new Decimal128(reader.GetDecimal(19)) },
            });
        }

        if (current != null) batch.Add(current);
        if (batch.Count > 0)
        {
            await orders.InsertManyAsync(batch, new InsertManyOptions { IsOrdered = false });
            total += batch.Count;
        }

        Console.WriteLine($"\r  перенесено {total:N0} замовлень за {sw.Elapsed.TotalSeconds:F1} с");

        // Індекси - аналоги тих, що є в PostgreSQL з Lab1:
        //   idx_order_customerid  -> customer.id
        //   idx_order_date_brin   -> date
        await orders.Indexes.CreateManyAsync(
        [
            new CreateIndexModel<BsonDocument>(Builders<BsonDocument>.IndexKeys.Ascending("customer.id"),
                new CreateIndexOptions { Name = "idx_customer_id" }),
            new CreateIndexModel<BsonDocument>(Builders<BsonDocument>.IndexKeys.Ascending("date"),
                new CreateIndexOptions { Name = "idx_date" }),
        ]);
        Console.WriteLine("  індекси створено: customer.id, date");
    }
}
