-- =====================================================================
-- Запити з тестів швидкодії.
-- EXPLAIN (ANALYZE, BUFFERS) показує план виконання і реальний час у базі.
-- запити виконує Benchmarks.cs.
-- =====================================================================

-- ---------- T1. Замовлення за Id з усіма деталями (JOIN 8 таблиць) ----------
EXPLAIN (ANALYZE, BUFFERS)
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
WHERE o."Id" = 1042;


-- ---------- T2. Історія клієнта: 10 останніх замовлень з позиціями ----------
EXPLAIN (ANALYZE, BUFFERS)
WITH last_orders AS (
    SELECT * FROM "Order"
    WHERE "CustomerId" = 2861
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
ORDER BY o."OrderDate" DESC;


-- ---------- T3. Створення замовлення (транзакція в 2 таблиці) ----------
BEGIN;
WITH new_order AS (
    INSERT INTO "Order" ("CustomerId", "EmployeeId", "OrderDate", "TotalAmount")
    VALUES (2861, 1, now(), 2 * 289.19 + 458.02)
    RETURNING "Id"
)
INSERT INTO "OrderItem" ("OrderId", "ProductId", "Quantity", "UnitPrice")
SELECT "Id", v.product_id, v.qty, v.price
FROM new_order, (VALUES (4417, 2, 289.19), (868, 1, 458.02)) AS v(product_id, qty, price);
ROLLBACK;  -- щоб не змінювати тестові дані


-- ---------- T4. Виручка по категоріях за місяць ----------
EXPLAIN (ANALYZE, BUFFERS)
SELECT cat."Name", sum(oi."Quantity" * oi."UnitPrice") AS revenue
FROM "Order" o
JOIN "OrderItem" oi ON oi."OrderId" = o."Id"
JOIN "Product" p    ON p."Id" = oi."ProductId"
JOIN "Category" cat ON cat."Id" = p."CategoryId"
WHERE o."OrderDate" >= '2026-01-01' AND o."OrderDate" < '2026-02-01'
GROUP BY cat."Name"
ORDER BY revenue DESC;


-- ---------- Розмір таблиць ----------
SELECT relname AS "table",
       pg_size_pretty(pg_total_relation_size(relid)) AS total_size,
       n_live_tup AS rows
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC;
