-- =====================================================================
-- Експорт даних з PostgreSQL у CSV для завантаження в Neo4j.
-- Файли пишуться в папку import сервера Neo4j (звідти їх читає LOAD CSV).
-- Запуск: psql -U postgres -d bd_lab2 -f neo4j/00_export.sql
-- =====================================================================

\copy (SELECT "Id" AS id, "Name" AS name, "ParentCategoryId" AS parent_id FROM "Category") TO 'C:/neo4j/server/import/categories.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

\copy (SELECT "Id" AS id, "CategoryId" AS category_id, "Name" AS name, "Price" AS price FROM "Product") TO 'C:/neo4j/server/import/products.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

\copy (SELECT "Id" AS id, "FirstName" || ' ' || coalesce("LastName", '') AS name, "Phone" AS phone FROM "Customer") TO 'C:/neo4j/server/import/customers.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

-- Лише замовлення з клієнтом: для графа "клієнт -> покупки" анонімні чеки не потрібні
\copy (SELECT "Id" AS id, "CustomerId" AS customer_id, to_char("OrderDate", 'YYYY-MM-DD"T"HH24:MI:SS') AS date, "TotalAmount" AS total FROM "Order" WHERE "CustomerId" IS NOT NULL) TO 'C:/neo4j/server/import/orders.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

\copy (SELECT oi."OrderId" AS order_id, oi."ProductId" AS product_id, oi."Quantity" AS qty, oi."UnitPrice" AS price FROM "OrderItem" oi JOIN "Order" o ON o."Id" = oi."OrderId" WHERE o."CustomerId" IS NOT NULL) TO 'C:/neo4j/server/import/order_items.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
