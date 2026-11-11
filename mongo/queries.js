// =====================================================================
// MongoDB: запити з тестів швидкодії (для демонстрації).
// Запуск усього файлу:   mongosh lab2 mongo/queries.js
// Або по одному - у mongosh чи вкладці "Mongosh" у Compass (use lab2).
// explain("executionStats") - аналог EXPLAIN ANALYZE у PostgreSQL.
// =====================================================================

db = db.getSiblingDB("lab2");

// ---------- Структура документа ----------
print("=== Приклад документа ===");
printjson(db.orders.findOne({ _id: 1042 }));

// ---------- T1. Замовлення за Id ----------
// Один документ уже містить клієнта, касира, відділ і всі позиції - JOIN не потрібен.
print("=== T1. Замовлення за Id ===");
const t1 = db.orders.find({ _id: 1042 }).explain("executionStats");
print(`план: ${t1.queryPlanner.winningPlan.stage ?? JSON.stringify(t1.queryPlanner.winningPlan)}, ` +
      `час: ${t1.executionStats.executionTimeMillis} мс, ` +
      `переглянуто документів: ${t1.executionStats.totalDocsExamined}`);

// ---------- T2. Історія клієнта: 10 останніх замовлень ----------
print("=== T2. Історія клієнта ===");
db.orders.find({ "customer.id": 2861 }).sort({ date: -1 }).limit(10)
  .forEach(o => print(`${o._id}  ${o.date.toISOString()}  ${o.total}  позицій: ${o.items.length}`));

const t2 = db.orders.find({ "customer.id": 2861 }).sort({ date: -1 }).limit(10).explain("executionStats");
print(`час: ${t2.executionStats.executionTimeMillis} мс, ` +
      `ключів індексу: ${t2.executionStats.totalKeysExamined}, документів: ${t2.executionStats.totalDocsExamined}`);

// ---------- T3. Створення замовлення: один insertOne ----------
print("=== T3. Створення замовлення ===");
db.orders.insertOne({
  _id: 9999999,
  date: new Date(),
  total: NumberDecimal("1036.40"),
  customer: { id: 2861, name: "Олена Лисенко", phone: "+380670002861" },
  employee: { id: 1, name: "Тест Касир" },
  department: { id: 1, name: "Продукти", store: "Мегамаркет Центр" },
  items: [
    { productId: 4417, name: "Засоби для посуду Max 4417", sku: "SKU-004417", category: "Засоби для посуду", mainCategory: "Побутова хімія", qty: 2, price: NumberDecimal("289.19") },
    { productId: 868,  name: "Пральні засоби Max 868",     sku: "SKU-000868", category: "Пральні засоби",    mainCategory: "Побутова хімія", qty: 1, price: NumberDecimal("458.02") },
  ],
});
printjson(db.orders.findOne({ _id: 9999999 }, { items: 0 }));
db.orders.deleteOne({ _id: 9999999 }); // прибрати тестовий документ

// ---------- T4. Виручка по категоріях за місяць ----------
print("=== T4. Виручка по категоріях за січень 2026 ===");
db.orders.aggregate([
  { $match: { date: { $gte: ISODate("2026-01-01"), $lt: ISODate("2026-02-01") } } },
  { $unwind: "$items" },
  { $group: { _id: "$items.category", revenue: { $sum: { $multiply: ["$items.qty", "$items.price"] } } } },
  { $sort: { revenue: -1 } },
]).forEach(r => print(`${r._id}: ${r.revenue}`));

// ---------- Розмір колекції ----------
print("=== Розмір колекції orders ===");
const s = db.orders.aggregate([{ $collStats: { storageStats: {} } }]).next().storageStats;
print(`документів: ${s.count}, дані: ${(s.size / 1048576).toFixed(1)} МБ, ` +
      `на диску (стиснено): ${(s.storageSize / 1048576).toFixed(1)} МБ, індекси: ${(s.totalIndexSize / 1048576).toFixed(1)} МБ`);
