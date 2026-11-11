-- =====================================================================
-- Генерація тестових даних для бази bd_lab2 (схема як у Lab1)
-- Запуск: psql -U postgres -d bd_lab2 -f sql/01_seed.sql
--
-- Обсяги:
--   3 магазини, 18 відділів, 300 працівників
--   36 категорій (6 основних + 30 підкатегорій), 5 000 товарів
--   100 000 клієнтів
--   300 000 замовлень, ~1 200 000 позицій замовлень (1..7 на замовлення)
--   період: 01.01.2025 - 31.10.2026
--
-- setseed() робить генерацію детермінованою: кожен запуск дає ті самі дані.
-- =====================================================================

\timing on
SELECT setseed(0.42);

-- Тригери складу з Lab1 (перевірка і списання залишків) для лаби вимикаємо:
-- порівнюємо саме зберігання/читання замовлень, а логіки складу в Mongo немає.
ALTER TABLE "OrderItem" DISABLE TRIGGER trg_orderitem_validate;
ALTER TABLE "OrderItem" DISABLE TRIGGER trg_orderitem_sale;

TRUNCATE "OrderItem", "Order", "Inventory", "Discount", "DeliveryItem", "Delivery",
         "Supplier", "Product", "Category", "EmployeeShift", "Shift", "Employee",
         "Position", "Department", "Store", "Customer"
RESTART IDENTITY CASCADE;

-- ---------- Магазини та відділи ----------
INSERT INTO "Store" ("Name", "Address") VALUES
  ('Мегамаркет Центр',   'м. Київ, вул. Хрещатик, 1'),
  ('Мегамаркет Лівобережний', 'м. Київ, просп. Броварський, 15'),
  ('Мегамаркет Львів',   'м. Львів, вул. Городоцька, 120');

-- 6 відділів у кожному магазині. Id відділу = (StoreId-1)*6 + номер відділу
INSERT INTO "Department" ("StoreId", "Name", "Floor")
SELECT s.id, d.name, d.floor
FROM generate_series(1, 3) AS s(id)
CROSS JOIN (VALUES
  (1, 'Продукти', 1), (2, 'Електроніка', 2), (3, 'Одяг', 2),
  (4, 'Побутова хімія', 1), (5, 'Дім і сад', 3), (6, 'Спорт', 3)
) AS d(n, name, floor)
ORDER BY s.id, d.n;

INSERT INTO "Position" ("Title", "BaseSalary") VALUES
  ('Касир', 18000), ('Продавець-консультант', 20000), ('Старший касир', 23000),
  ('Завідувач відділу', 32000), ('Адміністратор', 40000);

-- ---------- Працівники ----------
INSERT INTO "Employee" ("DepartmentId", "PositionId", "FirstName", "LastName")
SELECT 1 + floor(random() * 18)::int,
       1 + floor(random() * 5)::int,
       (ARRAY['Олена','Іван','Марія','Андрій','Наталія','Олег','Ірина','Петро','Тетяна','Сергій',
              'Юлія','Дмитро','Оксана','Василь','Анна','Максим','Катерина','Богдан','Світлана','Роман'])[1 + floor(random() * 20)::int],
       (ARRAY['Коваль','Шевченко','Бондаренко','Ткаченко','Кравченко','Олійник','Мельник','Поліщук',
              'Лисенко','Мороз','Савченко','Руденко','Гончаренко','Марченко','Петренко'])[1 + floor(random() * 15)::int]
FROM generate_series(1, 300);

-- ---------- Категорії ----------
-- 6 основних категорій (Id 1..6 відповідають відділам)
INSERT INTO "Category" ("Name", "ParentCategoryId") VALUES
  ('Продукти', NULL), ('Електроніка', NULL), ('Одяг', NULL),
  ('Побутова хімія', NULL), ('Дім і сад', NULL), ('Спорт', NULL);

-- по 5 підкатегорій (Id 7..36)
INSERT INTO "Category" ("Name", "ParentCategoryId")
SELECT sub.name, sub.parent
FROM (VALUES
  ('Молочні продукти',1,1),('Хліб і випічка',1,2),('М''ясо',1,3),('Овочі та фрукти',1,4),('Напої',1,5),
  ('Смартфони',2,1),('Ноутбуки',2,2),('Телевізори',2,3),('Аксесуари',2,4),('Аудіо',2,5),
  ('Чоловічий одяг',3,1),('Жіночий одяг',3,2),('Дитячий одяг',3,3),('Взуття',3,4),('Сумки',3,5),
  ('Пральні засоби',4,1),('Засоби для посуду',4,2),('Гігієна',4,3),('Чистячі засоби',4,4),('Паперова продукція',4,5),
  ('Меблі',5,1),('Посуд',5,2),('Текстиль',5,3),('Інструменти',5,4),('Садовий інвентар',5,5),
  ('Велосипеди',6,1),('Тренажери',6,2),('Туризм',6,3),('Спортивний одяг',6,4),('М''ячі',6,5)
) AS sub(name, parent, n)
ORDER BY sub.parent, sub.n;

-- ---------- Товари ----------
-- Ціна залежить від основної категорії (продукти дешеві, електроніка дорога)
INSERT INTO "Product" ("CategoryId", "Name", "Barcode", "SKU", "Price")
SELECT cat_id,
       c."Name" || ' ' ||
       (ARRAY['Premium','Classic','Eco','Smart','Pro','Basic','Comfort','Max','Lite','Plus'])[1 + floor(random() * 10)::int]
       || ' ' || g.i,
       '482' || lpad(g.i::text, 10, '0'),
       'SKU-' || lpad(g.i::text, 6, '0'),
       round((CASE c."ParentCategoryId"
                WHEN 1 THEN 15 + random() * 300
                WHEN 2 THEN 300 + random() * 40000
                WHEN 3 THEN 200 + random() * 4000
                WHEN 4 THEN 30 + random() * 500
                WHEN 5 THEN 100 + random() * 8000
                ELSE        150 + random() * 15000
              END)::numeric, 2)
FROM (SELECT i, 7 + floor(random() * 30)::int AS cat_id FROM generate_series(1, 5000) AS i) AS g
JOIN "Category" c ON c."Id" = g.cat_id;

-- ---------- Залишки: кожен товар у відповідному відділі кожного магазину ----------
INSERT INTO "Inventory" ("ProductId", "DepartmentId", "QuantityAvailable")
SELECT p."Id", (s.id - 1) * 6 + c."ParentCategoryId", floor(random() * 500)::int
FROM "Product" p
JOIN "Category" c ON c."Id" = p."CategoryId"
CROSS JOIN generate_series(1, 3) AS s(id);

-- ---------- Клієнти ----------
INSERT INTO "Customer" ("FirstName", "LastName", "Phone", "LoyaltyPoints")
SELECT (ARRAY['Олена','Іван','Марія','Андрій','Наталія','Олег','Ірина','Петро','Тетяна','Сергій',
              'Юлія','Дмитро','Оксана','Василь','Анна','Максим','Катерина','Богдан','Світлана','Роман'])[1 + floor(random() * 20)::int],
       (ARRAY['Коваль','Шевченко','Бондаренко','Ткаченко','Кравченко','Олійник','Мельник','Поліщук',
              'Лисенко','Мороз','Савченко','Руденко','Гончаренко','Марченко','Петренко'])[1 + floor(random() * 15)::int],
       '+38067' || lpad(i::text, 7, '0'),
       floor(random() * 5000)::int
FROM generate_series(1, 100000) AS i;

-- ---------- Замовлення ----------
-- Дати зростають разом з Id (як у реальному житті) - це важливо для BRIN-індексу з Lab1.
-- ~20% замовлень без клієнта (покупець без картки лояльності).
INSERT INTO "Order" ("CustomerId", "EmployeeId", "OrderDate", "TotalAmount")
SELECT CASE WHEN random() < 0.8 THEN 1 + floor(random() * 100000)::int END,
       1 + floor(random() * 300)::int,
       timestamp '2025-01-01 08:00' + (i / 300000.0) * interval '668 days'
                                    + floor(random() * 600) * interval '1 second',
       0
FROM generate_series(1, 300000) AS i;

-- ---------- Позиції замовлень ----------
-- 1..7 позицій на замовлення. Популярність товарів нерівномірна (random()^2):
-- товари з меншим Id купують частіше - так буває і в реальному магазині.
INSERT INTO "OrderItem" ("OrderId", "ProductId", "Quantity", "UnitPrice")
SELECT x.order_id, p."Id", x.qty, p."Price"
FROM (
  SELECT o."Id" AS order_id,
         1 + floor(5000 * power(random(), 2))::int AS product_id,
         1 + floor(random() * 3)::int AS qty
  FROM "Order" o
  CROSS JOIN LATERAL generate_series(1, 1 + floor(random() * 7)::int + 0 * o."Id")
) AS x
JOIN "Product" p ON p."Id" = x.product_id
ORDER BY x.order_id;

-- Сума замовлення = сума позицій
UPDATE "Order" o
SET "TotalAmount" = t.total
FROM (SELECT "OrderId", sum("Quantity" * "UnitPrice") AS total
      FROM "OrderItem" GROUP BY "OrderId") AS t
WHERE t."OrderId" = o."Id";

VACUUM ANALYZE;

-- ---------- Перевірка ----------
SELECT 'Customer' AS "table", count(*) FROM "Customer"
UNION ALL SELECT 'Product', count(*) FROM "Product"
UNION ALL SELECT 'Order', count(*) FROM "Order"
UNION ALL SELECT 'OrderItem', count(*) FROM "OrderItem";
