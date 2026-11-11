// =====================================================================
// Завантаження графа магазину в Neo4j з CSV (файли з 00_export.sql).
//
// Модель графа:
//   (:Customer)-[:PLACED]->(:Order)-[:CONTAINS {qty, price}]->(:Product)
//   (:Product)-[:IN_CATEGORY]->(:Category)-[:SUBCATEGORY_OF]->(:Category)
//
// Запуск: C:\neo4j\server\bin\cypher-shell.bat -u neo4j -p 1234567890 -f neo4j/01_load.cypher
// =====================================================================

// Очистити базу (на випадок повторного запуску)
MATCH (n) CALL (n) { DETACH DELETE n } IN TRANSACTIONS OF 10000 ROWS;

// Обмеження унікальності - заодно створюють індекси для швидкого MATCH по id
CREATE CONSTRAINT customer_id IF NOT EXISTS FOR (c:Customer) REQUIRE c.id IS UNIQUE;
CREATE CONSTRAINT product_id  IF NOT EXISTS FOR (p:Product)  REQUIRE p.id IS UNIQUE;
CREATE CONSTRAINT category_id IF NOT EXISTS FOR (c:Category) REQUIRE c.id IS UNIQUE;
CREATE CONSTRAINT order_id    IF NOT EXISTS FOR (o:Order)    REQUIRE o.id IS UNIQUE;

// Категорії та ієрархія категорій
LOAD CSV WITH HEADERS FROM 'file:///categories.csv' AS row
CREATE (:Category {id: toInteger(row.id), name: row.name});

LOAD CSV WITH HEADERS FROM 'file:///categories.csv' AS row
WITH row WHERE row.parent_id IS NOT NULL
MATCH (child:Category {id: toInteger(row.id)}), (parent:Category {id: toInteger(row.parent_id)})
CREATE (child)-[:SUBCATEGORY_OF]->(parent);

// Товари
LOAD CSV WITH HEADERS FROM 'file:///products.csv' AS row
MATCH (c:Category {id: toInteger(row.category_id)})
CREATE (p:Product {id: toInteger(row.id), name: row.name, price: toFloat(row.price)})
CREATE (p)-[:IN_CATEGORY]->(c);

// Клієнти
LOAD CSV WITH HEADERS FROM 'file:///customers.csv' AS row
CALL (row) {
  CREATE (:Customer {id: toInteger(row.id), name: row.name, phone: row.phone})
} IN TRANSACTIONS OF 10000 ROWS;

// Замовлення
LOAD CSV WITH HEADERS FROM 'file:///orders.csv' AS row
CALL (row) {
  MATCH (c:Customer {id: toInteger(row.customer_id)})
  CREATE (o:Order {id: toInteger(row.id), date: localdatetime(row.date), total: toFloat(row.total)})
  CREATE (c)-[:PLACED]->(o)
} IN TRANSACTIONS OF 10000 ROWS;

// Позиції замовлень = зв'язки CONTAINS з властивостями
LOAD CSV WITH HEADERS FROM 'file:///order_items.csv' AS row
CALL (row) {
  MATCH (o:Order {id: toInteger(row.order_id)}), (p:Product {id: toInteger(row.product_id)})
  CREATE (o)-[:CONTAINS {qty: toInteger(row.qty), price: toFloat(row.price)}]->(p)
} IN TRANSACTIONS OF 10000 ROWS;

// Перевірка
MATCH (n) RETURN labels(n)[0] AS label, count(*) AS count ORDER BY label;
