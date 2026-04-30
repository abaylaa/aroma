-- ============================================================
-- AROMA LAB - SQLite Database (English version)
-- Run: sqlite3 aroma_lab.db < aroma_lab_sqlite.sql
-- ============================================================

PRAGMA foreign_keys = ON;

DROP TABLE IF EXISTS invoice;
DROP TABLE IF EXISTS sale_item;
DROP TABLE IF EXISTS sale;
DROP TABLE IF EXISTS purchase_item;
DROP TABLE IF EXISTS purchase_order;
DROP TABLE IF EXISTS supplier;
DROP TABLE IF EXISTS stock;
DROP TABLE IF EXISTS recipe;
DROP TABLE IF EXISTS ingredient;
DROP TABLE IF EXISTS product;
DROP TABLE IF EXISTS shift;
DROP TABLE IF EXISTS employee;
DROP TABLE IF EXISTS position;
DROP TABLE IF EXISTS branch;

-- ============================================================
-- SCHEMA
-- ============================================================

CREATE TABLE branch (
    branch_id   INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL,
    address     TEXT NOT NULL,
    phone       TEXT,
    opened_date TEXT NOT NULL DEFAULT (date('now'))
);

CREATE TABLE position (
    position_id  INTEGER PRIMARY KEY AUTOINCREMENT,
    title        TEXT NOT NULL,
    base_salary  REAL NOT NULL CHECK (base_salary > 0)
);

CREATE TABLE employee (
    employee_id  INTEGER PRIMARY KEY AUTOINCREMENT,
    full_name    TEXT NOT NULL,
    branch_id    INTEGER NOT NULL,
    position_id  INTEGER NOT NULL,
    hire_date    TEXT NOT NULL,
    hourly_rate  REAL NOT NULL,
    is_active    INTEGER NOT NULL DEFAULT 1,
    FOREIGN KEY (branch_id)   REFERENCES branch(branch_id),
    FOREIGN KEY (position_id) REFERENCES position(position_id)
);

CREATE TABLE shift (
    shift_id    INTEGER PRIMARY KEY AUTOINCREMENT,
    employee_id INTEGER NOT NULL,
    start_time  TEXT NOT NULL,
    end_time    TEXT,
    FOREIGN KEY (employee_id) REFERENCES employee(employee_id)
);

CREATE TABLE product (
    product_id INTEGER PRIMARY KEY AUTOINCREMENT,
    name       TEXT NOT NULL,
    category   TEXT NOT NULL,
    price      REAL NOT NULL CHECK (price > 0),
    is_active  INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE ingredient (
    ingredient_id INTEGER PRIMARY KEY AUTOINCREMENT,
    name          TEXT NOT NULL,
    unit          TEXT NOT NULL,
    cost_per_unit REAL NOT NULL CHECK (cost_per_unit > 0),
    min_stock     REAL NOT NULL DEFAULT 0
);

CREATE TABLE recipe (
    recipe_id     INTEGER PRIMARY KEY AUTOINCREMENT,
    product_id    INTEGER NOT NULL,
    ingredient_id INTEGER NOT NULL,
    quantity      REAL NOT NULL CHECK (quantity > 0),
    UNIQUE (product_id, ingredient_id),
    FOREIGN KEY (product_id)    REFERENCES product(product_id),
    FOREIGN KEY (ingredient_id) REFERENCES ingredient(ingredient_id)
);

CREATE TABLE stock (
    stock_id      INTEGER PRIMARY KEY AUTOINCREMENT,
    branch_id     INTEGER NOT NULL,
    ingredient_id INTEGER NOT NULL,
    quantity      REAL NOT NULL DEFAULT 0,
    last_updated  TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE (branch_id, ingredient_id),
    FOREIGN KEY (branch_id)     REFERENCES branch(branch_id),
    FOREIGN KEY (ingredient_id) REFERENCES ingredient(ingredient_id)
);

CREATE TABLE supplier (
    supplier_id INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL,
    contact     TEXT,
    bin         TEXT UNIQUE,
    is_active   INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE purchase_order (
    po_id        INTEGER PRIMARY KEY AUTOINCREMENT,
    supplier_id  INTEGER NOT NULL,
    branch_id    INTEGER NOT NULL,
    order_date   TEXT NOT NULL DEFAULT (date('now')),
    status       TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','sent','received','cancelled')),
    total_amount REAL NOT NULL DEFAULT 0,
    FOREIGN KEY (supplier_id) REFERENCES supplier(supplier_id),
    FOREIGN KEY (branch_id)   REFERENCES branch(branch_id)
);

CREATE TABLE purchase_item (
    item_id       INTEGER PRIMARY KEY AUTOINCREMENT,
    po_id         INTEGER NOT NULL,
    ingredient_id INTEGER NOT NULL,
    quantity      REAL NOT NULL CHECK (quantity > 0),
    unit_price    REAL NOT NULL CHECK (unit_price > 0),
    FOREIGN KEY (po_id)         REFERENCES purchase_order(po_id) ON DELETE CASCADE,
    FOREIGN KEY (ingredient_id) REFERENCES ingredient(ingredient_id)
);

CREATE TABLE sale (
    sale_id        INTEGER PRIMARY KEY AUTOINCREMENT,
    branch_id      INTEGER NOT NULL,
    employee_id    INTEGER NOT NULL,
    sale_time      TEXT NOT NULL DEFAULT (datetime('now')),
    total_amount   REAL NOT NULL DEFAULT 0,
    payment_method TEXT NOT NULL CHECK (payment_method IN ('cash','card','kaspi','transfer')),
    FOREIGN KEY (branch_id)   REFERENCES branch(branch_id),
    FOREIGN KEY (employee_id) REFERENCES employee(employee_id)
);

CREATE TABLE sale_item (
    sale_item_id INTEGER PRIMARY KEY AUTOINCREMENT,
    sale_id      INTEGER NOT NULL,
    product_id   INTEGER NOT NULL,
    quantity     INTEGER NOT NULL CHECK (quantity > 0),
    unit_price   REAL NOT NULL CHECK (unit_price > 0),
    FOREIGN KEY (sale_id)    REFERENCES sale(sale_id) ON DELETE CASCADE,
    FOREIGN KEY (product_id) REFERENCES product(product_id)
);

CREATE TABLE invoice (
    invoice_id    INTEGER PRIMARY KEY AUTOINCREMENT,
    sale_id       INTEGER NOT NULL UNIQUE,
    fiscal_number TEXT NOT NULL UNIQUE,
    vat_amount    REAL NOT NULL,
    issued_at     TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (sale_id) REFERENCES sale(sale_id) ON DELETE CASCADE
);

-- INDEXES
CREATE INDEX idx_employee_branch ON employee(branch_id);
CREATE INDEX idx_sale_branch_time ON sale(branch_id, sale_time);
CREATE INDEX idx_sale_item_sale ON sale_item(sale_id);
CREATE INDEX idx_stock_branch ON stock(branch_id);
CREATE INDEX idx_recipe_product ON recipe(product_id);

-- ============================================================
-- TRIGGERS - Process automation demonstration
-- ============================================================

-- 1. On sale, automatically deduct ingredients per recipe
CREATE TRIGGER trg_deduct_stock
AFTER INSERT ON sale_item
BEGIN
    UPDATE stock
    SET quantity = quantity - (
        SELECT r.quantity * NEW.quantity
        FROM recipe r
        WHERE r.product_id = NEW.product_id
          AND r.ingredient_id = stock.ingredient_id
    ),
    last_updated = datetime('now')
    WHERE branch_id = (SELECT branch_id FROM sale WHERE sale_id = NEW.sale_id)
      AND ingredient_id IN (SELECT ingredient_id FROM recipe WHERE product_id = NEW.product_id);
END;

-- 2. Auto-update sale total
CREATE TRIGGER trg_update_sale_total
AFTER INSERT ON sale_item
BEGIN
    UPDATE sale
    SET total_amount = (
        SELECT COALESCE(SUM(quantity * unit_price), 0)
        FROM sale_item WHERE sale_id = NEW.sale_id
    )
    WHERE sale_id = NEW.sale_id;
END;

-- 3. Auto-create fiscal invoice
CREATE TRIGGER trg_create_invoice
AFTER UPDATE OF total_amount ON sale
WHEN NEW.total_amount > 0 AND NOT EXISTS (
    SELECT 1 FROM invoice WHERE sale_id = NEW.sale_id
)
BEGIN
    INSERT INTO invoice (sale_id, fiscal_number, vat_amount)
    VALUES (
        NEW.sale_id,
        'FN-' || strftime('%Y%m%d', 'now') || '-' || printf('%06d', NEW.sale_id),
        ROUND(NEW.total_amount * 12.0 / 112.0, 2)
    );
END;

-- 4. On PO received, auto-replenish stock
CREATE TRIGGER trg_receive_po
AFTER UPDATE OF status ON purchase_order
WHEN NEW.status = 'received' AND OLD.status <> 'received'
BEGIN
    UPDATE stock
    SET quantity = quantity + (
        SELECT pi.quantity FROM purchase_item pi
        WHERE pi.po_id = NEW.po_id AND pi.ingredient_id = stock.ingredient_id
    ),
    last_updated = datetime('now')
    WHERE branch_id = NEW.branch_id
      AND ingredient_id IN (SELECT ingredient_id FROM purchase_item WHERE po_id = NEW.po_id);
END;

-- ============================================================
-- VIEWS - Analytics (KPIs)
-- ============================================================

CREATE VIEW v_food_cost AS
SELECT
    s.branch_id,
    b.name AS branch_name,
    DATE(s.sale_time) AS sale_date,
    SUM(si.quantity * si.unit_price) AS revenue,
    SUM(si.quantity * (
        SELECT COALESCE(SUM(r.quantity * i.cost_per_unit), 0)
        FROM recipe r JOIN ingredient i ON i.ingredient_id = r.ingredient_id
        WHERE r.product_id = si.product_id
    )) AS cogs,
    ROUND(
        100.0 * SUM(si.quantity * (
            SELECT COALESCE(SUM(r.quantity * i.cost_per_unit), 0)
            FROM recipe r JOIN ingredient i ON i.ingredient_id = r.ingredient_id
            WHERE r.product_id = si.product_id
        )) / SUM(si.quantity * si.unit_price), 2
    ) AS food_cost_pct
FROM sale s
JOIN sale_item si ON si.sale_id = s.sale_id
JOIN branch b ON b.branch_id = s.branch_id
GROUP BY s.branch_id, b.name, DATE(s.sale_time);

CREATE VIEW v_avg_transaction AS
SELECT
    b.branch_id, b.name AS branch_name,
    DATE(s.sale_time) AS sale_date,
    COUNT(s.sale_id) AS transactions,
    ROUND(AVG(s.total_amount), 0) AS avg_transaction_value,
    SUM(s.total_amount) AS total_revenue
FROM sale s
JOIN branch b ON b.branch_id = s.branch_id
GROUP BY b.branch_id, b.name, DATE(s.sale_time);

CREATE VIEW v_stock_alerts AS
SELECT
    b.name AS branch_name,
    i.name AS ingredient,
    i.unit, s.quantity AS current_stock, i.min_stock,
    CASE
        WHEN s.quantity < i.min_stock THEN 'CRITICAL'
        WHEN s.quantity < i.min_stock * 1.3 THEN 'WARNING'
        ELSE 'OK'
    END AS alert_level
FROM stock s
JOIN branch b ON b.branch_id = s.branch_id
JOIN ingredient i ON i.ingredient_id = s.ingredient_id;

CREATE VIEW v_top_products AS
SELECT
    p.product_id, p.name, p.category,
    SUM(si.quantity) AS total_sold,
    SUM(si.quantity * si.unit_price) AS total_revenue,
    ROUND(AVG(si.unit_price), 0) AS avg_price
FROM sale_item si
JOIN product p ON p.product_id = si.product_id
GROUP BY p.product_id, p.name, p.category
ORDER BY total_sold DESC;

-- ============================================================
-- SEED DATA (English)
-- ============================================================

INSERT INTO branch (name, address, phone, opened_date) VALUES
('Aroma Lab Dostyk',     '89 Dostyk Ave, Almaty',          '+7 727 222 11 01', '2021-03-15'),
('Aroma Lab Abay',       '150/1 Abay Ave, Almaty',         '+7 727 222 11 02', '2021-09-20'),
('Aroma Lab Satpayev',   '30B Satpayev St, Almaty',        '+7 727 222 11 03', '2022-04-10'),
('Aroma Lab Rozybakiev', '247 Rozybakiev St, Almaty',      '+7 727 222 11 04', '2022-11-05'),
('Aroma Lab Al-Farabi',  '19 Al-Farabi Ave, Almaty',       '+7 727 222 11 05', '2023-06-12'),
('Aroma Lab Markov',     '61 Markov St, Almaty',           '+7 727 222 11 06', '2024-02-28');

INSERT INTO position (title, base_salary) VALUES
('Barista', 200000), ('Senior Barista', 280000), ('Store Manager', 400000),
('Accountant', 450000), ('Supply Manager', 380000), ('HR Manager', 400000),
('Director', 900000), ('Marketing Manager', 380000);

INSERT INTO employee (full_name, branch_id, position_id, hire_date, hourly_rate) VALUES
('Aliya Zhumabayeva',    1, 1, '2023-04-01', 1500),
('Daniyar Kassenov',     1, 2, '2022-08-15', 2000),
('Aigerim Satova',       1, 3, '2021-09-01', 2500),
('Nurlan Alimov',        2, 1, '2024-01-10', 1500),
('Kamila Bekturova',     2, 2, '2023-02-20', 2000),
('Timur Ospanov',        3, 1, '2024-03-05', 1500),
('Aidana Yergaliyeva',   3, 3, '2022-04-10', 2500),
('Baurzhan Saifullin',   4, 1, '2024-05-15', 1500),
('Zhanel Kenzhebekova',  5, 1, '2024-08-01', 1500),
('Yerlan Tulegenov',     6, 1, '2024-10-12', 1500),
('Gulnara Kassymova',    1, 4, '2021-03-15', 2800),
('Arman Kaliev',         1, 5, '2021-04-01', 2400),
('Dilnaz Kuanysheva',    1, 6, '2022-06-01', 2500),
('Serik Bolatov',        1, 7, '2021-03-15', 5500);

INSERT INTO product (name, category, price) VALUES
('Espresso',                'Coffee',   800),
('Americano',               'Coffee',  1100),
('Cappuccino',              'Coffee',  1500),
('Latte',                   'Coffee',  1700),
('Raf Classic',             'Coffee',  1900),
('Raf Lavender',            'Coffee',  2100),
('Flat White',              'Coffee',  1700),
('Cocoa',                   'Drinks',  1300),
('Earl Grey Tea',           'Drinks',   900),
('Almond Croissant',        'Pastry',  1200),
('Chicken Sandwich',        'Food',    2200),
('NY Cheesecake',           'Dessert', 1800);

INSERT INTO ingredient (name, unit, cost_per_unit, min_stock) VALUES
('Coffee beans (arabica)',  'g',   3.5,    2000),
('Milk 3.2%',               'ml',  0.4,    5000),
('Lactose-free milk',       'ml',  0.7,    2000),
('Sugar',                   'g',   0.18,   1500),
('Lavender syrup',          'ml',  2.5,     500),
('Vanilla syrup',           'ml',  2.2,     500),
('Cocoa powder',            'g',   2.8,     300),
('Earl Grey tea bag',       'pcs', 120,      50),
('Heavy cream 33%',         'ml',  1.6,    1000),
('Cup 250ml',               'pcs',  35,     500),
('Cup 350ml',               'pcs',  40,     500),
('Lid for cup',             'pcs',  15,    1000),
('Straw',                   'pcs',   8,    1500),
('Napkin',                  'pcs',   3,    2000),
('Frozen croissant',        'pcs', 280,     100),
('Almond paste',            'g',   3.2,     500),
('Sandwich bread',          'pcs', 150,     100),
('Boiled chicken fillet',   'g',   2.4,    2000),
('Iceberg lettuce',         'g',   1.2,     800),
('Tomato',                  'g',   0.8,     800),
('Cheddar cheese',          'g',   3.8,    1000),
('Mayonnaise',              'g',   0.9,     500),
('Cheesecake (ready)',      'pcs', 600,      30),
('Ground cinnamon',         'g',   1.5,     100),
('Drinking water',          'ml',  0.05,  10000);

-- RECIPES
INSERT INTO recipe (product_id, ingredient_id, quantity) VALUES
(1, 1, 9), (1, 25, 30),
(2, 1, 9), (2, 25, 200), (2, 11, 1), (2, 12, 1),
(3, 1, 18), (3, 2, 150), (3, 11, 1), (3, 12, 1),
(4, 1, 18), (4, 2, 250), (4, 11, 1), (4, 12, 1),
(5, 1, 18), (5, 9, 100), (5, 2, 100), (5, 4, 12), (5, 6, 10), (5, 11, 1), (5, 12, 1),
(6, 1, 18), (6, 9, 100), (6, 2, 100), (6, 4, 8), (6, 5, 15), (6, 11, 1), (6, 12, 1),
(7, 1, 22), (7, 2, 150), (7, 10, 1), (7, 12, 1),
(8, 7, 25), (8, 2, 250), (8, 4, 20), (8, 11, 1), (8, 12, 1),
(9, 8, 1), (9, 25, 300), (9, 11, 1), (9, 12, 1),
(10, 15, 1), (10, 16, 30), (10, 14, 1),
(11, 17, 1), (11, 18, 80), (11, 19, 30), (11, 20, 40), (11, 21, 25), (11, 22, 15),
(12, 23, 1), (12, 24, 1);

-- STOCK
INSERT INTO stock (branch_id, ingredient_id, quantity) VALUES
(1, 1, 4500), (1, 2, 12000), (1, 3, 1800), (1, 4, 3000), (1, 5, 350),
(1, 6, 800),  (1, 7, 600),   (1, 8, 80),   (1, 9, 1500), (1, 10, 800),
(1, 11, 1200),(1, 12, 2200), (1, 13, 2800),(1, 14, 3500),(1, 15, 90),
(1, 16, 700), (1, 17, 150),  (1, 18, 3500),(1, 19, 1200),(1, 20, 1500),
(1, 21, 1600),(1, 22, 800),  (1, 23, 25),  (1, 24, 250), (1, 25, 25000);

INSERT INTO stock (branch_id, ingredient_id, quantity)
SELECT b.branch_id, i.ingredient_id, i.min_stock * 2
FROM branch b CROSS JOIN ingredient i
WHERE b.branch_id BETWEEN 2 AND 6;

-- SUPPLIERS
INSERT INTO supplier (name, contact, bin) VALUES
('Coffee Region LLP',     '+7 727 333 22 11', '180440012345'),
('Dairy Union LLP',       '+7 727 444 33 22', '190550023456'),
('Sweet Life Sole Trader','+7 705 555 44 33', '780123456789'),
('Packaging KZ LLP',      '+7 727 666 55 44', '170330034567'),
('Fresh Foods LLP',       '+7 727 777 66 55', '210660045678');

-- Disable triggers for historical inserts
DROP TRIGGER trg_deduct_stock;
DROP TRIGGER trg_create_invoice;

-- SHIFTS
INSERT INTO shift (employee_id, start_time, end_time) VALUES
(1, '2026-04-25 07:00', '2026-04-25 15:00'),
(2, '2026-04-25 08:00', '2026-04-25 16:00'),
(4, '2026-04-25 07:30', '2026-04-25 15:30'),
(5, '2026-04-25 09:00', '2026-04-25 17:00'),
(1, '2026-04-26 07:00', '2026-04-26 15:00'),
(2, '2026-04-26 08:00', '2026-04-26 16:00'),
(4, '2026-04-26 07:30', '2026-04-26 15:30');

-- HISTORICAL SALES
INSERT INTO sale (branch_id, employee_id, sale_time, payment_method) VALUES
(1, 1, '2026-04-25 08:15', 'card'),  (1, 1, '2026-04-25 08:23', 'cash'),
(1, 2, '2026-04-25 09:01', 'kaspi'), (1, 1, '2026-04-25 09:45', 'card'),
(1, 2, '2026-04-25 10:30', 'card'),  (1, 1, '2026-04-25 11:20', 'kaspi'),
(1, 2, '2026-04-25 12:50', 'card'),
(2, 4, '2026-04-25 08:30', 'card'),  (2, 5, '2026-04-25 09:15', 'kaspi'),
(2, 4, '2026-04-25 10:50', 'cash'),
(3, 6, '2026-04-25 09:20', 'card'),
(1, 1, '2026-04-26 08:10', 'card'),  (1, 2, '2026-04-26 09:05', 'kaspi'),
(1, 1, '2026-04-26 10:15', 'card'),
(2, 4, '2026-04-26 08:45', 'card'),  (2, 5, '2026-04-26 09:30', 'kaspi'),
(4, 8, '2026-04-26 09:00', 'card'),  (5, 9, '2026-04-26 09:15', 'cash'),
(1, 1, '2026-04-27 08:20', 'kaspi'), (1, 5, '2026-04-27 09:00', 'card'),
(2, 4, '2026-04-27 08:45', 'card'),  (6, 10, '2026-04-27 09:10', 'cash'),
(3, 7, '2026-04-27 10:00', 'kaspi'), (1, 2, '2026-04-27 11:15', 'card');

INSERT INTO sale_item (sale_id, product_id, quantity, unit_price) VALUES
(1, 3, 1, 1500), (1, 10, 1, 1200),
(2, 3, 1, 1500),
(3, 4, 1, 1700), (3, 11, 1, 2200),
(4, 5, 1, 1900),
(5, 11, 1, 2200),
(6, 3, 1, 1500), (6, 4, 1, 1700), (6, 10, 1, 1200),
(7, 4, 1, 1700),
(8, 3, 1, 1500),
(9, 5, 1, 1900), (9, 8, 1, 1300),
(10, 4, 1, 1700),
(11, 11, 1, 2200),
(12, 3, 1, 1500),
(13, 6, 1, 2100), (13, 9, 1, 900),
(14, 3, 1, 1500), (14, 10, 1, 1200),
(15, 4, 1, 1700),
(16, 4, 1, 1700), (16, 1, 1, 800),
(17, 5, 1, 1900),
(18, 3, 1, 1500),
(19, 11, 1, 2200),
(20, 3, 2, 1500), (20, 4, 1, 1700),
(21, 4, 1, 1700),
(22, 3, 1, 1500),
(23, 4, 1, 1700), (23, 10, 1, 1200),
(24, 3, 2, 1500), (24, 6, 1, 2100), (24, 8, 1, 1300);

INSERT INTO invoice (sale_id, fiscal_number, vat_amount)
SELECT
    sale_id,
    'FN-2026-' || printf('%06d', sale_id),
    ROUND(total_amount * 12.0 / 112.0, 2)
FROM sale;

-- Re-create triggers for future demo
CREATE TRIGGER trg_deduct_stock
AFTER INSERT ON sale_item
BEGIN
    UPDATE stock
    SET quantity = quantity - (
        SELECT r.quantity * NEW.quantity
        FROM recipe r
        WHERE r.product_id = NEW.product_id AND r.ingredient_id = stock.ingredient_id
    ),
    last_updated = datetime('now')
    WHERE branch_id = (SELECT branch_id FROM sale WHERE sale_id = NEW.sale_id)
      AND ingredient_id IN (SELECT ingredient_id FROM recipe WHERE product_id = NEW.product_id);
END;

CREATE TRIGGER trg_create_invoice
AFTER UPDATE OF total_amount ON sale
WHEN NEW.total_amount > 0 AND NOT EXISTS (SELECT 1 FROM invoice WHERE sale_id = NEW.sale_id)
BEGIN
    INSERT INTO invoice (sale_id, fiscal_number, vat_amount)
    VALUES (NEW.sale_id,
            'FN-' || strftime('%Y%m%d', 'now') || '-' || printf('%06d', NEW.sale_id),
            ROUND(NEW.total_amount * 12.0 / 112.0, 2));
END;

-- PURCHASE ORDERS
INSERT INTO purchase_order (supplier_id, branch_id, order_date, status) VALUES
(1, 1, '2026-04-20', 'received'),
(2, 1, '2026-04-22', 'received'),
(3, 1, '2026-04-26', 'sent');

INSERT INTO purchase_item (po_id, ingredient_id, quantity, unit_price) VALUES
(1, 1, 50000, 3.5), (2, 2, 200000, 0.4), (3, 15, 200, 280);

-- Final check
SELECT 'Branches'    AS table_name, COUNT(*) AS rows FROM branch
UNION ALL SELECT 'Employees',   COUNT(*) FROM employee
UNION ALL SELECT 'Products',    COUNT(*) FROM product
UNION ALL SELECT 'Ingredients', COUNT(*) FROM ingredient
UNION ALL SELECT 'Recipes',     COUNT(*) FROM recipe
UNION ALL SELECT 'Stock rows',  COUNT(*) FROM stock
UNION ALL SELECT 'Sales',       COUNT(*) FROM sale
UNION ALL SELECT 'Sale items',  COUNT(*) FROM sale_item
UNION ALL SELECT 'Invoices',    COUNT(*) FROM invoice;
