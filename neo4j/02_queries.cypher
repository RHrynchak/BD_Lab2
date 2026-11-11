// =====================================================================
// Neo4j: базові запити (пункт 6 лабораторної).
// Виконувати по одному в Neo4j Browser: http://localhost:7474
// =====================================================================


// ---------- 1. CRUD ----------

// CREATE: новий клієнт
CREATE (c:Customer {id: 999999, name: 'Тестовий Клієнт', phone: '+380999999999'})
RETURN c;

// READ: знайти клієнта
MATCH (c:Customer {id: 999999}) RETURN c;

// UPDATE: змінити телефон
MATCH (c:Customer {id: 999999})
SET c.phone = '+380111111111'
RETURN c;

// CREATE зв'язку: клієнт робить замовлення з двома товарами
MATCH (c:Customer {id: 999999}), (p1:Product {id: 1}), (p2:Product {id: 2})
CREATE (c)-[:PLACED]->(o:Order {id: 999999, date: localdatetime(), total: p1.price + p2.price})
CREATE (o)-[:CONTAINS {qty: 1, price: p1.price}]->(p1)
CREATE (o)-[:CONTAINS {qty: 1, price: p2.price}]->(p2)
RETURN c, o, p1, p2;

// DELETE: видалити клієнта разом з його замовленнями (DETACH прибирає зв'язки)
MATCH (c:Customer {id: 999999})
OPTIONAL MATCH (c)-[:PLACED]->(o:Order)
DETACH DELETE c, o;


// ---------- 2. Покупки клієнта (картинка графа в Browser) ----------
MATCH (c:Customer {id: 2861})-[:PLACED]->(o:Order)-[:CONTAINS]->(p:Product)-[:IN_CATEGORY]->(cat:Category)
RETURN c, o, p, cat;


// ---------- 3. Топ-10 товарів за кількістю проданих одиниць ----------
MATCH (:Order)-[r:CONTAINS]->(p:Product)
RETURN p.name AS product, sum(r.qty) AS sold
ORDER BY sold DESC
LIMIT 10;


// ---------- 4. "Разом з цим товаром купують" ----------
// Товари, які найчастіше бувають в одному замовленні з товаром 100.
// У SQL це self-join таблиці OrderItem; тут - просто шлях у графі.
MATCH (p:Product {id: 100})<-[:CONTAINS]-(o:Order)-[:CONTAINS]->(other:Product)
WHERE other <> p
RETURN other.name AS product, count(o) AS together
ORDER BY together DESC
LIMIT 5;


// ---------- 5. Персональні рекомендації для клієнта ----------
// Клієнти, які купували те саме, що й клієнт 2861, ще купували... (і він цього не купував)
MATCH (me:Customer {id: 2861})-[:PLACED]->(:Order)-[:CONTAINS]->(p:Product)
WITH me, collect(DISTINCT p) AS myProducts
UNWIND myProducts AS p
MATCH (p)<-[:CONTAINS]-(:Order)<-[:PLACED]-(other:Customer)-[:PLACED]->(:Order)-[:CONTAINS]->(rec:Product)
WHERE other <> me AND NOT rec IN myProducts
RETURN rec.name AS recommendation, count(DISTINCT other) AS customers
ORDER BY customers DESC
LIMIT 5;


// ---------- 6. Виручка по основних категоріях (ієрархія категорій) ----------
MATCH (o:Order)-[r:CONTAINS]->(:Product)-[:IN_CATEGORY]->(:Category)-[:SUBCATEGORY_OF]->(main:Category)
WHERE o.date >= localdatetime('2026-01-01T00:00') AND o.date < localdatetime('2026-02-01T00:00')
RETURN main.name AS category, round(sum(r.qty * r.price), 2) AS revenue
ORDER BY revenue DESC;


// ---------- 7. Як пов'язані два клієнти (найкоротший шлях) ----------
MATCH path = shortestPath(
  (a:Customer {id: 2861})-[:PLACED|CONTAINS*..6]-(b:Customer {id: 500})
)
RETURN path;


// ---------- 8. Найактивніші клієнти ----------
// Групуємо за вузлом c (а не за c.name) - імена в різних клієнтів можуть збігатися
MATCH (c:Customer)-[:PLACED]->(o:Order)
WITH c, count(o) AS orders, round(sum(o.total), 2) AS spent
RETURN c.id AS id, c.name AS customer, orders, spent
ORDER BY spent DESC
LIMIT 10;
