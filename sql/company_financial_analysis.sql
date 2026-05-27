

-- Table 1: budget
-- Stores yearly budgeted financial data per business unit and month
CREATE TABLE budget (
    year                INT             NOT NULL,   -- Fiscal year (e.g. 2022, 2023)
    month               VARCHAR(15)     NOT NULL,   -- Month number (1-12)
    business_unit       VARCHAR(50)     NOT NULL,   -- Business unit name
    budgeted_revenue    DECIMAL(12,2)   NOT NULL,   -- Planned revenue
    budgeted_expense    DECIMAL(12,2)   NOT NULL,   -- Planned expense
    budgeted_profit     DECIMAL(12,2)   NOT NULL    -- Planned profit
);


-- Table 2: customers
-- Stores customer profile and status information
CREATE TABLE customers (
    customer_id     VARCHAR(20)     PRIMARY KEY,    -- Unique customer ID (e.g. CUST10000)
    customer_name   VARCHAR(100),                   -- Full name of customer
    segment         VARCHAR(50),                    -- Segment: Online, Retail, Enterprise
    join_date       VARCHAR(20),                    -- Date customer joined
    region          VARCHAR(50),                    -- Region: North, South, East, West
    status          VARCHAR(20)                     -- Account status: Active, Inactive
);


-- Table 3: financial_transaction
-- Stores all financial transactions — links to customers and vendors
CREATE TABLE financial_transaction (
    transaction_id      VARCHAR(20)     PRIMARY KEY,    -- Unique transaction ID (e.g. TRX100000)
    transaction_date    DATE,                           -- Date of transaction
    amount              DECIMAL(12,2),                  -- Amount (+ve Revenue, -ve Expense)
    account_type        VARCHAR(20),                    -- Expense, Revenue, Equity, Asset, Liability
    category            VARCHAR(50),                    -- Category: Supplies, Utilities, etc.
    business_unit       VARCHAR(20),                    -- Online, Retail, Enterprise
    region              VARCHAR(10),                    -- North, South, East, West
    customer_id         VARCHAR(20),                    -- FK → customers table
    vendor_id           VARCHAR(20),                    -- FK → vendor table
    valid_status        VARCHAR(20),                    -- Valid or Review
    transaction_type    VARCHAR(20),                    -- Customer Transaction / Vendor Transaction
    description         VARCHAR(100)                    -- Short description
);


-- Table 4: headcount
-- Stores employee/HR data including cost details
CREATE TABLE headcount (
    employee_id     VARCHAR(20)     PRIMARY KEY,    -- Unique employee ID (e.g. EMP1000)
    employee_name   VARCHAR(100),                   -- Full name of employee
    business_unit   VARCHAR(20),                    -- Business unit employee belongs to
    join_date       DATE,                           -- Date employee joined
    status          VARCHAR(20),                    -- Active or Inactive
    region          VARCHAR(10),                    -- Region of employee
    cost_to_company DECIMAL(12,2)                   -- Total CTC (salary + benefits)
);


-- Table 5: vendor
-- Stores vendor/supplier information
CREATE TABLE vendor (
    vendor_id       VARCHAR(20)     PRIMARY KEY,    -- Unique vendor ID (e.g. VEND1000)
    vendor_name     VARCHAR(100),                   -- Full name of vendor
    category        VARCHAR(50),                    -- Supplies, Consulting, Services, Utilities, Rent
    region          VARCHAR(10),                    -- Region where vendor operates
    active          VARCHAR(20)                     -- Yes or No
);


-- ============================================================
--  SECTION 2 : VIEWS
-- ============================================================

-- ------------------------------------------------------------
-- VIEW 1: financial_summary
-- Aggregates actual revenue, expense and profit
-- from financial_transaction per year, month, business_unit
-- NOTE: Create this FIRST — budget_vs_actual depends on it
-- ------------------------------------------------------------

CREATE OR REPLACE VIEW financial_summary AS

SELECT
    EXTRACT(YEAR  FROM transaction_date)::INT           AS year,
    EXTRACT(MONTH FROM transaction_date)::INT           AS month,
    business_unit,

    -- Total Revenue
    SUM(CASE WHEN account_type = 'Revenue'
             THEN amount ELSE 0 END)                    AS total_revenue,

    -- Total Expense (ABS to convert negative → positive)
    ABS(SUM(CASE WHEN account_type = 'Expense'
                 THEN amount ELSE 0 END))               AS total_expense,

    -- Net Profit = Revenue + Expense (expense is negative in DB)
    SUM(CASE WHEN account_type = 'Revenue'
             THEN amount ELSE 0 END)
    + SUM(CASE WHEN account_type = 'Expense'
               THEN amount ELSE 0 END)                  AS net_profit

FROM financial_transaction
WHERE valid_status = 'Valid'                            -- Only valid transactions

GROUP BY
    EXTRACT(YEAR  FROM transaction_date)::INT,
    EXTRACT(MONTH FROM transaction_date)::INT,
    business_unit

ORDER BY year, month, business_unit;


-- ------------------------------------------------------------
-- VIEW 2: budget_vs_actual
-- Compares actual figures (from financial_summary view)
-- vs budgeted figures (from budget table)
-- Calculates variance = Actual - Budgeted
-- ------------------------------------------------------------

CREATE OR REPLACE VIEW budget_vs_actual AS

SELECT
    a.year,
    a.month,
    a.business_unit,

    -- Revenue
    a.total_revenue,
    b.budgeted_revenue,
    (a.total_revenue - b.budgeted_revenue)      AS revenue_variance,

    -- Expense
    a.total_expense,
    b.budgeted_expense,
    (a.total_expense - b.budgeted_expense)      AS expense_variance,

    -- Profit
    a.net_profit,
    b.budgeted_profit,
    (a.net_profit - b.budgeted_profit)          AS profit_variance

FROM financial_summary a                        -- Reusing financial_summary view
JOIN budget b
    ON  a.year          = b.year
    AND a.month         = b.month
    AND a.business_unit = b.business_unit;


-- ------------------------------------------------------------
-- VIEW 3: clean_transactions
-- Filters only Valid transactions from financial_transaction
-- ------------------------------------------------------------

CREATE OR REPLACE VIEW clean_transactions AS

SELECT
    transaction_id,
    transaction_date,
    amount,
    account_type,
    category,
    business_unit,
    region,
    customer_id,
    vendor_id,
    valid_status,
    transaction_type,
    description

FROM financial_transaction
WHERE valid_status = 'Valid'                    -- Exclude 'Review' transactions

ORDER BY transaction_date, transaction_id;


-- ============================================================
--  SECTION 3 : INSIGHT QUERIES
-- ============================================================

-- Query 1: Total Revenue, Expense and Profit by Business Unit
SELECT
    business_unit,
    SUM(total_revenue)                          AS total_revenue,
    SUM(total_expense)                          AS total_expense,
    SUM(net_profit)                             AS total_profit,
    ROUND(SUM(net_profit) / NULLIF(SUM(total_revenue), 0) * 100, 2) AS profit_margin_pct
FROM financial_summary
GROUP BY business_unit
ORDER BY total_profit DESC;


-- Query 2: Budget vs Actual — Which month had highest profit variance?
SELECT
    year,
    month,
    business_unit,
    profit_variance
FROM budget_vs_actual
ORDER BY profit_variance DESC
LIMIT 10;


-- Query 3: Monthly Revenue Trend (all business units combined)
SELECT
    year,
    month,
    SUM(total_revenue)  AS monthly_revenue,
    SUM(total_expense)  AS monthly_expense,
    SUM(net_profit)     AS monthly_profit
FROM financial_summary
GROUP BY year, month
ORDER BY year, month;


-- Query 4: Top 10 Customers by Revenue
SELECT
    c.customer_id,
    c.customer_name,
    c.segment,
    c.region,
    SUM(ft.amount)      AS total_revenue
FROM clean_transactions ft
JOIN customers c ON ft.customer_id = c.customer_id
WHERE ft.transaction_type = 'Customer Transaction'
GROUP BY c.customer_id, c.customer_name, c.segment, c.region
ORDER BY total_revenue DESC
LIMIT 10;


-- Query 5: Top 10 Vendors by Spend
SELECT
    v.vendor_id,
    v.vendor_name,
    v.category,
    v.region,
    ABS(SUM(ft.amount)) AS total_spend
FROM clean_transactions ft
JOIN vendor v ON ft.vendor_id = v.vendor_id
WHERE ft.transaction_type = 'Vendor Transaction'
GROUP BY v.vendor_id, v.vendor_name, v.category, v.region
ORDER BY total_spend DESC
LIMIT 10;


-- Query 6: Employee Cost by Business Unit and Region
SELECT
    business_unit,
    region,
    COUNT(employee_id)      AS total_employees,
    SUM(cost_to_company)    AS total_salary_cost,
    ROUND(AVG(cost_to_company), 2) AS avg_salary
FROM headcount
WHERE status = 'Active'
GROUP BY business_unit, region
ORDER BY total_salary_cost DESC;


-- Query 7: Revenue per Employee by Business Unit
SELECT
    fs.business_unit,
    SUM(fs.total_revenue)                               AS total_revenue,
    COUNT(h.employee_id)                                AS total_employees,
    ROUND(SUM(fs.total_revenue) / NULLIF(COUNT(h.employee_id), 0), 2) AS revenue_per_employee
FROM financial_summary fs
JOIN headcount h ON fs.business_unit = h.business_unit
WHERE h.status = 'Active'
GROUP BY fs.business_unit
ORDER BY revenue_per_employee DESC;


-- Query 8: Invalid / Review Transactions Count
SELECT
    valid_status,
    COUNT(transaction_id)   AS total_transactions,
    ABS(SUM(amount))        AS total_amount
FROM financial_transaction
GROUP BY valid_status;
