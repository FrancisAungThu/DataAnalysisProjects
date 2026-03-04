
------------------------------------------------
-----------------SALES ANALYSIS ----------------
------------------------------------------------

--- *** Monthly Sales Analysis: MoM, YoY, Growth *** ---

WITH MonthlySales AS (
SELECT 
    Year,
    Month,
    SUM(Quantity) AS UnitsSold,
    CAST(SUM(TotalPrice) AS INT) AS TotalSales,
    --MoM: Previous Month revenue
    LAG(CAST(SUM(TotalPrice) AS INT), 1) OVER (ORDER BY Year, Month) AS LastMonthSales,
    -- YoY: Same month Last Year
    LAG(CAST(SUM(TotalPrice) AS INT), 12) OVER ( ORDER BY Year, Month) AS LastYearSales,
    -- Rolling 3 months avg: backward looking
    CAST (
   AVG( SUM(TotalPrice))OVER (ORDER BY Year, Month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS INT) AS Rolling3MAvg
FROM fact_sales
GROUP BY Year, Month
)
    SELECT 
    Year,
    Month,
    TotalSales,
    LastMonthSales,
    LastYearSales,
    Rolling3MAvg,
    -- UnitsShare: Each month's contribution to the annual quantity sold
    CAST(UnitsSold * 100.0 / SUM(UnitsSold) OVER( PARTITION BY Year) AS Decimal(10,2)) AS UnitsShare,
    -- MoM Growth %
    (TotalSales - LastMonthSales) * 100 / LastMonthSales AS MoMGrowth,
    -- YoY Growth %
    (TotalSales - LastYearSales) * 100 / LastYearSales AS YoYGrowth,
    
    -- Growth Category
    CASE
        WHEN LastMonthSales IS NULL THEN 'No Data'
        WHEN (TotalSales - LastMonthSales) * 100 / LastMonthSales > 15 THEN 'Strong Growth'
        WHEN (TotalSales - LastMonthSales) * 100 / LastMonthSales > 5 THEN 'Moderate Growth'
        WHEN (TotalSales - LastMonthSales) * 100 / LastMonthSales <= 5 THEN 'Flat'
        WHEN (TotalSales - LastMonthSales) * 100 / LastMonthSales > -15 THEN 'Slight Decline'
        ELSE 'Sharp Decline'
    END AS GrowthCategory
    FROM MonthlySales
    ORDER BY Year, Month;

--- *** DayOfWeek Sales *** ---
SELECT
    DayName,
    ROUND(SUM(TotalPrice),2) AS TotalSales,
    ROUND( SUM(TotalPrice) * 100 / SUM(SUM(TotalPrice))OVER (), 2) AS SalesContri
FROM fact_sales
GROUP BY DayName
ORDER BY TotalSales DESC


--- *** What time of the day do customers buy the most? *** ---

SELECT 
    TimeOfDay,
    COUNT(*) AS Transactions,
    CAST(SUM(TotalPrice) AS INT) AS TotalRevenue,
    CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER() AS INT) AS TransactionShare
FROM fact_sales
GROUP BY TimeOfDay
ORDER BY TransactionShare DESC;


--- *** What day of the week do customers buy the most? *** ---
SELECT 
    DayName,
    COUNT(*) AS Transactions,
    ROUND(SUM(TotalPrice), 2) AS TotalRevenue,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER() , 2) AS TransactionShare
FROM fact_sales
GROUP BY DayName
ORDER BY TransactionShare DESC;








--- *** Customer Purchase Behaviour *** ---

--- *** Segement customer based on their RFM *** ---

CREATE OR ALTER VIEW View_RFM_ChurnCustomerSegmentation AS

WITH CustomerSegmentation AS (
SELECT 
    c.CustomerID,
    c.FullName,
    c.CityID,
    --- Recency: Dayy since last purchase
    DATEDIFF(day, MAX(fs.SalesDate), '2024.12.31') AS Recency,
    --- Frequency: Total numbers of transcation
    COUNT(fs.SalesID) AS Frequency,
    --- Monetary: Total Spend
    ROUND(SUM(fs.TotalPrice), 2) AS Monetary
FROM dim_customers AS c
LEFT JOIN fact_sales AS fs ON  c.CustomerID = fs.CustomerID
GROUP BY c.CustomerID, c.FullName, c.CityID
HAVING COUNT(fs.SalesID) > 0
),
Scores AS (
SELECT 
    *,
    -- DIVIDE customer into 5 groups for each metric (NTITLE)
    NTILE(5) OVER (ORDER BY Recency DESC) AS R_score,
    NTILE(5) OVER (ORDER BY Frequency ASC) AS F_score,
    NTILE(5) OVER (ORDER BY Monetary ASC) AS M_score
FROM CustomerSegmentation
),
RFM_Churn AS (
SELECT
    CustomerID,
    FullName,
    c.State,
    c.CityName,
    s.Recency,
    s.Frequency,
    s.Monetary,
    -- RFM Segmentation: Loytalty + Activity 
    CASE 
        -- High in all three: The best customers
        WHEN R_Score >= 4 AND F_Score >= 4 AND M_Score >= 4 THEN 'Champions / VIP'
        -- High Spend, but haven't been back in a while
        WHEN R_Score <= 2 AND M_Score >= 4 THEN 'High Value at Risk'
        -- Low Spend, but buy very often
        WHEN F_Score >= 4 AND M_Score <= 2 THEN 'Loyal Value Seekers'
        -- New and spending well
        WHEN R_Score >= 4 AND M_Score >= 4 THEN 'Promising New Spenders'
        -- Low in everything
        WHEN R_Score <= 1 AND F_Score <= 1 THEN 'Lost / Churned'
        ELSE 'General Population'
    END AS RFMSegment,
    -- Churn Status
    CASE
        WHEN Recency <= 30 THEN 'Active'
        WHEN Recency BETWEEN 31 AND 60 THEN 'At Risk'
        WHEN Recency BETWEEN 61 AND 90 THEN 'Win-Back Target'
        ELSE 'Churn'
    END AS ChurnStatus
FROM Scores AS s
LEFT JOIN dim_cities AS c ON s.CityID = c.CityID
)
    SELECT 
    *,
    CONCAT(RFMSegment, '-', ChurnStatus) AS RFM_Churn_Group
FROM RFM_Churn;


SELECT *
FROM View_RFM_ChurnCustomerSegmentation





-- *** Identify repeat customers VS one-time buyers *** ---


ALTER TABLE dim_customers
ADD RepeatBuyerFlag VARCHAR(50);

WITH CustomerPurchaseBehaviour AS (
    SELECT
        fs.CustomerID,
        COUNT(DISTINCT fs.SalesDate) AS PurchaseCount
    FROM fact_sales AS fs
    GROUP BY fs.CustomerID
)
UPDATE d
SET d.RepeatBuyerFlag =
    CASE 
        WHEN cpb.PurchaseCount = 1 THEN 'One-Time Buyer'
        WHEN cpb.PurchaseCount BETWEEN 2 AND 4 THEN 'Repeat Buyer'
        ELSE 'Loyal Customer'
    END
FROM dim_customers d
JOIN CustomerPurchaseBehaviour cpb
    ON d.CustomerID = cpb.CustomerID;


SELECT
    RepeatBuyerFlag,
    COUNT(DISTINCT CustomerID) AS CustomerCount,
    ROUND(COUNT(DISTINCT CustomerID) * 100.0 / (SELECT COUNT(DISTINCT CustomerID) FROM dim_customers), 2) AS PercentageOfCustomers
FROM dim_customers
GROUP BY RepeatBuyerFlag
ORDER BY CustomerCount DESC;


--- *** Classify customers by discount behaviour *** ---

ALTER TABLE dim_customers
ADD PriceSensitivity VARCHAR(50);


WITH CustomerDiscountBehaviour AS (
    SELECT
        fs.CustomerID,
        ROUND(AVG(fs.Discount * 100), 2) AS AvgDiscountPercentage,
        SUM(CASE WHEN fs.Discount > 0 THEN 1 ELSE 0 END) AS DiscountedTransactions,
        COUNT(*) AS TotalTransactions
    FROM fact_sales AS fs
    GROUP BY fs.CustomerID
),
Classified AS (
    SELECT
        cdb.CustomerID,
        cdb.AvgDiscountPercentage,
        cdb.DiscountedTransactions,
        cdb.TotalTransactions,
        cdb.DiscountedTransactions * 100.0 / NULLIF(cdb.TotalTransactions, 0) AS DiscountUsageRate,
        -- Price Sensitivity segmentation: Discount-driven behaviour
        CASE 
            WHEN cdb.AvgDiscountPercentage >= 4.5
                 AND (cdb.DiscountedTransactions * 100.0 / NULLIF(cdb.TotalTransactions, 0)) >= 30 
                THEN 'Highly Price Sensitive'
            WHEN cdb.AvgDiscountPercentage >= 2 
                 AND (cdb.DiscountedTransactions * 100.0 / NULLIF(cdb.TotalTransactions, 0)) >= 10 
                THEN 'Moderately Price Sensitive'
            ELSE 'Low Price Sensitivity'
        END AS PriceSensitivity
    FROM CustomerDiscountBehaviour AS cdb
)

UPDATE dim_customers
SET PriceSensitivity = c.PriceSensitivity
FROM dim_customers d
JOIN Classified c ON d.CustomerID = c.CustomerID;



SELECT 
    PriceSensitivity,
    COUNT(*) AS CustomerCount
FROM dim_customers
GROUP BY PriceSensitivity


--- *** Classify customers by Customer Profitibality*** ---

ALTER TABLE dim_customers
ADD RFMSegment  NVARCHAR (100),
    CityName NVARCHAR(50),
    State NVARCHAR(50),
    TotalSpending DECIMAL(18,2),
    TotalProfit DECIMAL(18,2),
    TotalTransactions INT,
    AOV DECIMAL(18,2),
    ProfitabilityCategory NVARCHAR(20),
    SpendingRank INT,
    ProfitMargin DECIMAL(18,2),
    SpendingContribution DECIMAL(18,2),
    RunningTotal DECIMAL(18,2),
    CumulativeContribution DECIMAL(18,2),
    Recency INT,
    Frequency INT,
    Monetary DECIMAL(18,2);

/* Step 1: Materialize CustomerSpending into a temp table */
IF OBJECT_ID('tempdb..#CustomerSpending') IS NOT NULL
    DROP TABLE #CustomerSpending;

SELECT 
    c.CustomerID,
    c.FullName,
    cs.RFMSegment,
    cs.CityName,
    cs.State,
    cs.Recency,
    cs.Frequency,
    cs.Monetary,
    SUM(fs.TotalPrice) AS TotalSpending,
    ROUND(SUM(fs.Quantity * p.ProfitPerUnit), 2) AS TotalProfit,
    COUNT(*) AS TotalTransactions,
    AVG(fs.TotalPrice) AS AOV
INTO #CustomerSpending
FROM fact_sales fs
JOIN dim_customers c ON fs.CustomerID = c.CustomerID
JOIN View_RFM_ChurnCustomerSegmentation cs ON c.CustomerID = cs.CustomerID
LEFT JOIN dim_products p ON fs.ProductID = p.ProductID
GROUP BY 
    c.CustomerID, c.FullName, cs.RFMSegment,cs.CityName,cs.State,
    cs.Recency, cs.Frequency, cs.Monetary

/* Step 2: Compute percentiles safely */
DECLARE @P33 DECIMAL(18,2), @P66 DECIMAL(18,2);

SELECT 
    @P33 = PERCENTILE_CONT(0.33) WITHIN GROUP (ORDER BY TotalProfit) OVER (),
    @P66 = PERCENTILE_CONT(0.66) WITHIN GROUP (ORDER BY TotalProfit) OVER ()
FROM #CustomerSpending;

;WITH Ranked AS (
SELECT
    *,
    -- Profit Margin
        CASE 
            WHEN TotalSpending = 0 THEN 0
            ELSE ROUND((TotalProfit / NULLIF(TotalSpending, 0)) * 100, 2)
        END AS ProfitMargin,

    -- Spending Contribution
        CAST(TotalSpending AS FLOAT) * 100.0 
            / SUM(CAST(TotalSpending AS FLOAT)) OVER() AS SpendingContribution,

    -- Running Total  
        SUM(TotalSpending) OVER (ORDER BY TotalSpending DESC) AS RunningTotal,

    -- Cumulative Contribution   
        SUM(TotalSpending) OVER (ORDER BY TotalSpending DESC) * 100.0 
            / SUM(TotalSpending) OVER() AS CumulativeContribution,

    -- Spending Rank
        RANK() OVER (ORDER BY TotalSpending DESC) AS SpendingRank,

    -- ProfitabilityCategory: Contribution to margin
        CASE
            WHEN TotalProfit >= @P66 THEN 'High'
            WHEN TotalProfit >= @P33 THEN 'Medium'
            ELSE 'Low'
        END AS  ProfitabilityCategory 
    FROM #CustomerSpending
)
SELECT *
INTO #CustomerSpending_Final FROM Ranked



--- Updating from temp table into dim_customers
UPDATE c
SET 
    c.RFMSegment = f.RFMSegment,
    c.CityName = f.CityName,
    c.State = f.State,
    c.TotalSpending = ROUND(f.TotalSpending, 2),
    c.TotalProfit = f.TotalProfit,
    c.TotalTransactions = f.TotalTransactions,
    c.AOV = f.AOV,
    c.ProfitabilityCategory = f.ProfitabilityCategory,
    c.SpendingRank = f.SpendingRank,
    c.ProfitMargin = f.ProfitMargin,
    c.SpendingContribution = f.SpendingContribution,
    c.RunningTotal = f.RunningTotal,
    c.CumulativeContribution = f.CumulativeContribution,
    c.Recency = f.Recency,
    c.Frequency = f.Frequency,
    c.Monetary = f.Monetary
FROM dim_customers AS c
JOIN #CustomerSpending_Final AS f
    ON c.CustomerID = f.CustomerID;



--- *** Final Customer Segementation: 3-Dimensional Persona Model "RFM x Profitability x PriceSensitivity" *** ---
ALTER TABLE dim_customers
ADD FinalSegment NVARCHAR(100);



UPDATE c
SET c.FinalSegment =
    CASE
        --------------------------------------------------------------------
        -- 1. HIGH PROFITABILITY + LOW PRICE SENSITIVITY (Premium Shoppers)
        --------------------------------------------------------------------
        WHEN c.ProfitabilityCategory = 'High' 
             AND c.PriceSensitivity = 'Low Price Sensitivity'
             AND c.RFMSegment = 'Champions / VIP'
            THEN 'Premium Loyalist'

        WHEN c.ProfitabilityCategory = 'High' 
             AND c.PriceSensitivity = 'Low Price Sensitivity'
             AND c.RFMSegment = 'Promising New Spenders'
            THEN 'Emerging Premium'

        WHEN c.ProfitabilityCategory = 'High' 
             AND c.PriceSensitivity = 'Low Price Sensitivity'
             AND c.RFMSegment = 'High Value at Risk'
            THEN 'Premium At-Risk'


        --------------------------------------------------------------------
        -- 2. HIGH PROFITABILITY + MODERATE PRICE SENSITIVITY
        --------------------------------------------------------------------
        WHEN c.ProfitabilityCategory = 'High'
             AND c.PriceSensitivity = 'Moderately Price Sensitive'
             AND c.RFMSegment = 'Champions / VIP'
            THEN 'Value-Conscious VIP'

        WHEN c.ProfitabilityCategory = 'High'
             AND c.PriceSensitivity = 'Moderately Price Sensitive'
             AND c.RFMSegment = 'Loyal Value Seekers'
            THEN 'High-Value Routine Shopper'

        WHEN c.ProfitabilityCategory = 'High'
             AND c.PriceSensitivity = 'Moderately Price Sensitive'
             AND c.RFMSegment = 'High Value at Risk'
            THEN 'High-Value Drifting'


        --------------------------------------------------------------------
        -- 3. HIGH PROFITABILITY + HIGH PRICE SENSITIVITY
        --------------------------------------------------------------------
        WHEN c.ProfitabilityCategory = 'High'
             AND c.PriceSensitivity = 'Highly Price Sensitive'
             AND c.RFMSegment = 'Champions / VIP'
            THEN 'Premium Bargain Hunter'

        WHEN c.ProfitabilityCategory = 'High'
             AND c.PriceSensitivity = 'Highly Price Sensitive'
             AND c.RFMSegment = 'Loyal Value Seekers'
            THEN 'Deal-Driven Loyalist'

        WHEN c.ProfitabilityCategory = 'High'
             AND c.PriceSensitivity = 'Highly Price Sensitive'
             AND c.RFMSegment = 'High Value at Risk'
            THEN 'High-Value Promo Churn Risk'


        --------------------------------------------------------------------
        -- 4. MEDIUM PROFITABILITY + LOW PRICE SENSITIVITY (Convenience)
        --------------------------------------------------------------------
        WHEN c.ProfitabilityCategory = 'Medium'
             AND c.PriceSensitivity = 'Low Price Sensitivity'
             AND c.RFMSegment = 'Champions / VIP'
            THEN 'Convenience Loyalist'

        WHEN c.ProfitabilityCategory = 'Medium'
             AND c.PriceSensitivity = 'Low Price Sensitivity'
             AND c.RFMSegment = 'Promising New Spenders'
            THEN 'Emerging Convenience Shopper'

        WHEN c.ProfitabilityCategory = 'Medium'
             AND c.PriceSensitivity = 'Low Price Sensitivity'
             AND c.RFMSegment = 'General Population'
            THEN 'Standard Convenience Buyer'


        --------------------------------------------------------------------
        -- 5. MEDIUM PROFITABILITY + HIGH PRICE SENSITIVITY (Budget Regulars)
        --------------------------------------------------------------------
        WHEN c.ProfitabilityCategory = 'Medium'
             AND c.PriceSensitivity = 'Highly Price Sensitive'
             AND c.RFMSegment = 'Loyal Value Seekers'
            THEN 'Budget Loyalist'

        WHEN c.ProfitabilityCategory = 'Medium'
             AND c.PriceSensitivity = 'Highly Price Sensitive'
             AND c.RFMSegment = 'General Population'
            THEN 'Budget Routine Shopper'

        WHEN c.ProfitabilityCategory = 'Medium'
             AND c.PriceSensitivity = 'Highly Price Sensitive'
             AND c.RFMSegment = 'High Value at Risk'
            THEN 'Budget Churn Risk'


        --------------------------------------------------------------------
        -- 6. LOW PROFITABILITY + HIGH PRICE SENSITIVITY (Low-Value Promo)
        --------------------------------------------------------------------
        WHEN c.ProfitabilityCategory = 'Low'
             AND c.PriceSensitivity = 'Highly Price Sensitive'
             AND c.RFMSegment = 'Lost / Churned'
            THEN 'Churned Bargain Hunter'

        WHEN c.ProfitabilityCategory = 'Low'
             AND c.PriceSensitivity = 'Highly Price Sensitive'
             AND c.RFMSegment = 'General Population'
            THEN 'Low-Value Promo Shopper'

        WHEN c.ProfitabilityCategory = 'Low'
             AND c.PriceSensitivity = 'Highly Price Sensitive'
             AND c.RFMSegment = 'Promising New Spenders'
            THEN 'New Promo Shopper'


        --------------------------------------------------------------------
        -- 7. LOW PROFITABILITY + LOW PRICE SENSITIVITY (Low-Value Full Price)
        --------------------------------------------------------------------
        WHEN c.ProfitabilityCategory = 'Low'
             AND c.PriceSensitivity = 'Low Price Sensitivity'
             AND c.RFMSegment = 'General Population'
            THEN 'Low-Value Convenience Buyer'

        WHEN c.ProfitabilityCategory = 'Low'
             AND c.PriceSensitivity = 'Low Price Sensitivity'
             AND c.RFMSegment = 'Lost / Churned'
            THEN 'Dormant Full-Price Buyer'

        WHEN c.ProfitabilityCategory = 'Low'
             AND c.PriceSensitivity = 'Low Price Sensitivity'
             AND c.RFMSegment = 'Promising New Spenders'
            THEN 'New Low-Value Buyer'


        --------------------------------------------------------------------
        -- DEFAULT
        --------------------------------------------------------------------
        ELSE 'Unclassified'
    END
FROM dim_customers AS c;


--- *** ADD CHURN STATUS & FINAL CHURN-SEGMENT FOR TARGETED RETENTION MARKETING *** ---

ALTER TABLE dim_customers
ALTER COLUMN ChurnStatus VARCHAR(20);



ALTER TABLE dim_customers
ALTER COLUMN SegmentChurnStatus VARCHAR(100);

WITH ChurnClassification AS (
    SELECT 
        CustomerID,
        CASE
            WHEN Recency <= 30 THEN 'Active'
            WHEN Recency BETWEEN 31 AND 60 THEN 'At Risk'
            WHEN Recency BETWEEN 61 AND 90 THEN 'Win-Back Target'
            ELSE 'Churn'
        END AS ChurnStatus
    FROM dim_customers
),
Updated AS (
    SELECT 
        d.CustomerID,
        d.FinalSegment,
        c.ChurnStatus,
        CONCAT(d.FinalSegment, '-', c.ChurnStatus) AS FinalChurnSegment
    FROM dim_customers d
    JOIN ChurnClassification c ON d.CustomerID = c.CustomerID
)
UPDATE dim_customers
SET ChurnStatus = u.ChurnStatus,
    SegmentChurnStatus = u.FinalChurnSegment
FROM dim_customers AS d
JOIN Updated AS u ON d.CustomerID = u.CustomerID;




--- *** ARPU, AOV, AVG frequency, CLV, Customer Contri, Revenue Contribution by Final Customer Segment *** ---

SELECT 
    FinalSegment,
    COUNT(*) AS CustomerCount,
    CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER() AS DECIMAL(10,2)) AS PercentageOfCustomers,
    -- Customer Lifetime Value
    SUM(TotalSpending) AS CLV,
    -- ARPU: Average Revenue Per Customer
    CAST(SUM(Monetary) / COUNT(DISTINCT CustomerID) AS DECIMAL(10,2)) AS ARPU,
    -- AOV: Averrage Order Value 
    CAST(AVG(AOV) AS DECIMAL(10,2)) AS AvgOrderValue,
    -- Average Profit Margin
    ROUND(AVG(ProfitMargin), 2) AS AvgProfitMargin,

    CAST(SUM(TotalSpending) * 100.0 / SUM(SUM(TotalSpending)) OVER() AS DECIMAL (10,2)) AS RevenueContribution,
    ROUND(SUM(TotalProfit) * 100.0 / SUM(SUM(TotalProfit)) OVER(), 2) AS ProfitContribution
    
FROM dim_customers
GROUP BY FinalSegment
HAVING FinalSegment != 'Unclassified'
ORDER BY ProfitContribution DESC


--- ***Churn Win-Back Target List: high valued customer, Last purchase between =< 30 ***---

CREATE OR ALTER VIEW View_WinBackCustomerList AS
SELECT *
FROM dim_customers
WHERE (FinalSegment = 'Premium Bargain Hunters'  OR FinalSegment ='Value-Conscious VIP' OR FinalSegment = 'High-Value Promo Churn Risk')
     AND ChurnStatus = 'Win-Back Target';
     
SELECT 
    FinalSegment,
    COUNT(*) AS TotalCustomers
FROM View_WinBackCustomerList
GROUP BY FinalSegment



--- ***Churn At Risk Target List: high valued customer, Last purchase between > 31 and 60 ***---

CREATE OR ALTER VIEW View_ChurnAtRiskCustomerList AS
SELECT *
FROM dim_customers
WHERE (FinalSegment = 'Premium Bargain Hunters'  OR FinalSegment ='Value-Conscious VIP' OR FinalSegment = 'High-Value Promo Churn Risk')
     AND ChurnStatus = 'At Risk'

SELECT 
    FinalSegment,
    COUNT(*) AS TotalCustomers
FROM View_ChurnAtRiskCustomerList
GROUP BY FinalSegment



--- *** Monthly Retention Rate *** ---

WITH MonthlyActivity AS (
    SELECT 
    CustomerID,
    FORMAT(SalesDate, 'yyyy-MM') AS YearMonth
    FROM fact_sales
    GROUP BY CustomerID, FORMAT(SalesDate, 'yyyy-MM')
),
Retention AS (
    SELECT
        a.YearMonth AS MonthN,
        COUNT(DISTINCT a.CustomerID) AS CustomersInMonthN,
        COUNT(DISTINCT b.CustomerID) AS CustomersRetained
    FROM MonthlyActivity a
    LEFT JOIN MonthlyActivity b
        ON a.CustomerID = b.CustomerID
        AND EOMONTH(CAST(a.YearMonth + '-01' AS DATE), 1)
         = EOMONTH( CAST(b.YearMonth + '-01' AS DATE), 0)
    GROUP BY a.YearMonth
)
SELECT
    MonthN,
    CustomersInMonthN,
    CustomersRetained,
    ROUND( (CustomersRetained * 100 /  CustomersInMonthN) , 2) AS RetentionRate
FROM Retention
ORDER BY MonthN;


--------------------------------------------------------------------
--------------- PRODUCT ANALYSIS -----------------------------------
--------------------------------------------------------------------


-- *** CATEGORY SALES *** ----

-- Calculate Sales for each category
CREATE OR ALTER VIEW View_CategoryParetoAnalysis AS

    WITH CategoryBase AS (
        SELECT
            c.CategoryName,
            ROUND( SUM(s.TotalPrice),2) AS TotalSales,
            SUM(s.Quantity) AS TotalVolume
        FROM fact_sales AS s
        JOIN dim_products AS p ON s.ProductID = p.ProductID
        JOIN dim_categories AS c ON p.CategoryID = c.CategoryID
        GROUP BY c.CategoryName
    ),
    GrandTotals AS (
        SELECT 
            SUM(TotalSales) AS GrandTotalSales,
            SUM(TotalVolume) AS GrandTotalVolume
        FROM CategoryBase
    ),
    Calculation AS (
        SELECT 
            cb.CategoryName,
            cb.TotalSales,
            cb.TotalVolume,
            -- Calculate Running Total for Pareto
            SUM(cb.TotalSales) OVER (ORDER BY cb.TotalSales DESC) AS RunningTotal,
            gt.GrandTotalSales,
            gt.GrandTotalVolume
        FROM CategoryBase cb
        CROSS JOIN GrandTotals gt
    )
    SELECT
        CategoryName,
        TotalSales,
        -- Average Selling Price (ASP)
        ROUND(TotalSales / NULLIF(TotalVolume, 0), 2) AS AvgSellingPrice,
        -- Contribution %
        ROUND((TotalSales / NULLIF(GrandTotalSales, 0)) * 100, 2) AS SalesContribution,
        -- Volume Share %
        CAST ((TotalVolume * 100.0 / NULLIF(GrandTotalVolume, 0)) AS INT) AS VolumeShare,
        -- Pareto Cumulative %
        ROUND((RunningTotal / NULLIF(GrandTotalSales, 0)) * 100, 2) AS CumulativePercentage,
        -- Pareto Classification
        CASE 
            WHEN (RunningTotal / NULLIF(GrandTotalSales, 0)) <= 0.8 THEN 'Top 80% (Core)'
            ELSE 'Bottom 20%'
        END AS ParetoClass
    FROM Calculation;

GO

SELECT *
FROM View_CategoryParetoAnalysis
ORDER BY TotalSales DESC


--- *** Product ranks on total sales revenue *** ---

CREATE OR ALTER VIEW View_ProductSalesPerformance AS

WITH ProductSales AS (
    SELECT 
        p.ProductID,
        p.ProductName,
        c.CategoryName,
        ROUND(SUM(s.TotalPrice), 2) AS TotalSales,
        SUM(s.Quantity) AS TotalQuantity,
        p.Margin,
        ROUND(AVG(s.Discount * 100), 2) AS AvgDiscountPercentage,
        CAST(
            SUM(CASE WHEN s.Discount > 0 THEN s.Quantity ELSE 0 END) * 100.0 
            / NULLIF(SUM(s.Quantity), 0) AS DECIMAL(10,2)
        ) AS DiscountQuantityRate
    FROM fact_sales AS s 
    LEFT JOIN dim_products AS p ON s.ProductID = p.ProductID
    LEFT JOIN dim_categories AS c ON p.CategoryID = c.CategoryID
    GROUP BY p.ProductID, p.ProductName, c.CategoryName, p.Margin
),
Averages AS (
    SELECT
        AVG(TotalQuantity) AS AvgQty,
        AVG(Margin) AS AvgMargin
    FROM ProductSales
),
ProductWithContribution AS (
    SELECT
        ps.*,
        ROUND(ps.TotalSales * 100 / SUM(ps.TotalSales) OVER (), 2) AS SalesContribution,
        CAST(ps.TotalQuantity * 100.0 / SUM(ps.TotalQuantity) OVER () AS DECIMAL(10,2)) AS QuantityContribution,
        a.AvgQty,
        a.AvgMargin
    FROM ProductSales ps
    CROSS JOIN Averages a
)
SELECT
    DENSE_RANK() OVER (ORDER BY TotalSales DESC) AS ProductRank,
    ProductName,
    CategoryName,
    TotalSales,
    TotalQuantity,
    AvgDiscountPercentage,
    DiscountQuantityRate,
    SalesContribution,
    QuantityContribution,
    ROUND(SUM(SalesContribution) OVER (ORDER BY SalesContribution DESC), 2) AS CumulativeSalesContribution,
    -- ABC Classification based on Sales Contribution
    CASE 
        WHEN SUM(SalesContribution) OVER (ORDER BY SalesContribution DESC) <= 80 THEN 'A'
        WHEN SUM(SalesContribution) OVER (ORDER BY SalesContribution DESC) <= 95 THEN 'B'
        ELSE 'C'
    END AS ABC_Classification, 
    -- Strategic Product Role based on Quantity and Margin compared to average 
    CASE 
        WHEN TotalQuantity > AvgQty AND Margin < AvgMargin THEN 'Traffic Driver'
        WHEN TotalQuantity > AvgQty AND Margin >= AvgMargin THEN 'Profit Magnet'
        WHEN TotalQuantity <= AvgQty AND Margin < AvgMargin THEN 'Basket Filler'
        WHEN TotalQuantity <= AvgQty AND Margin >= AvgMargin THEN 'Long-Tail Variety'
    END AS StrategicRole
FROM ProductWithContribution;

--- Sales Contribution
SELECT 
    ProductName,
    SalesContribution,
    QuantityContribution,
    ABC_Classification,
    StrategicRole
FROM View_ProductSalesPerformance
ORDER BY SalesContribution DESC

--- Quantity Contribution
SELECT *
FROM View_ProductSalesPerformance
ORDER BY QuantityContribution DESC


--- *** Segment specific product affnity *** --- 

WITH ProductAffinity AS (
    SELECT 
        c.FinalSegment,
        s.ProductID,
        SUM(s.Quantity) AS TotalQuantity,
        SUM(s.TotalPrice) AS ProductRevenue, 
        RANK() OVER (
            PARTITION BY c.FinalSegment 
            ORDER BY SUM(s.Quantity) DESC
        ) AS ProductRank
    FROM fact_sales s
    JOIN dim_customers AS c ON s.CustomerID = c.CustomerID
    GROUP BY 
        c.FinalSegment, 
        s.ProductID

)
SELECT 
    pa.FinalSegment,
    pa.ProductID,
    p.ProductName,
    p.Margin,
    pa.TotalQuantity,
    ROUND(pa.ProductRevenue, 2) AS ProductRevenue,
    pa.ProductRank
FROM ProductAffinity AS pa
LEFT JOIN dim_products AS p ON pa.ProductID = p.ProductID
WHERE ProductRank <= 10 -- Top 10 PER segment
ORDER BY FinalSegment, ProductRank;


--- *** Product Penetration Rate by Customer Segment *** ---
WITH SegmentTotals AS (
    -- Pre-calculate total customers in each segment for the denominator
    SELECT 
        FinalSegment, 
        COUNT(DISTINCT CustomerID) AS TotalSegmentCustomers
    FROM dim_customers
    GROUP BY FinalSegment
),
ProductSales AS (
    -- Calculate how many unique customers bought each product per segment
    SELECT
        cs.FinalSegment,
        s.ProductID,
        p.ProductName,
        COUNT(DISTINCT s.CustomerID) AS CustomersWhoBought
    FROM fact_sales s
    JOIN dim_customers cs ON s.CustomerID = cs.CustomerID
    LEFT JOIN dim_products AS p ON s.ProductID = p.ProductID
    GROUP BY cs.FinalSegment, s.ProductID, p.ProductName
)
SELECT 
    ps.FinalSegment,
    ps.ProductID,
    ps.ProductName,
    st.TotalSegmentCustomers,
    ps.CustomersWhoBought,
    -- Apply Formula: (Customers who bought product / Total customers in segment) * 100
    CAST(
        (ps.CustomersWhoBought * 100.0 / st.TotalSegmentCustomers) AS DECIMAL(10,2)) AS PenetrationRate
FROM ProductSales ps
JOIN SegmentTotals st ON ps.FinalSegment = st.FinalSegment
ORDER BY ps.FinalSegment, PenetrationRate DESC;


--- *** Product-level Price Sensitivity *** ---

SELECT
    ProductName,
    AVGDiscountPercentage,
    DiscountQuantityRate
FROM View_ProductSalesPerformance
ORDER BY DiscountQuantityRate DESC


--- *** Market Basket Analysis *** ---

--- Support: How often the pair appears across all baskets
--- Confidence: Probability of buying B when A is bought
--- Lift: Strength of association beyond chance

WITH paircounts AS (
SELECT 
    a.ProductID AS ProductA,
    pa.ProductName AS ProductAName,
    b.ProductID AS ProductB,
    pb.ProductName AS ProductBName,
    COUNT(*) AS TransactionCount
FROM fact_sales AS a
JOIN fact_sales AS b 
    ON a.TransactionNumber = b.TransactionNumber 
    AND a.ProductID < b.ProductID
LEFT JOIN dim_products AS pa ON a.ProductID = pa.ProductID
LEFT JOIN dim_products AS pb ON b.ProductID = pb.ProductID
GROUP BY a.ProductID, b.ProductID, pa.ProductName, pb.ProductName
),
productcounts AS (
    SELECT 
        ProductID,
        COUNT(DISTINCT TransactionNumber) AS ProductCount
    FROM fact_sales
    GROUP BY ProductID
),
totaltransactions AS (
    SELECT COUNT(DISTINCT TransactionNumber) AS TotalTransactions
    FROM fact_sales
)
SELECT 
    pc.ProductA,
    pc.ProductAName,
    pc.ProductB,
    pc.ProductBName,
    pc.TransactionCount,
    pc.TransactionCount * 1.0 / tt.TotalTransactions AS Support,
    pc.TransactionCount * 1.0 / pa.ProductCount AS ConfidenceAtoB,
    (pc.TransactionCount * 1.0 / tt.TotalTransactions) /
    ((pa.ProductCount * 1.0 / tt.TotalTransactions) * 
     (pb.ProductCount * 1.0 / tt.TotalTransactions)) AS Lift
FROM paircounts AS pc
JOIN productcounts AS pa ON pc.ProductA = pa.ProductID
JOIN productcounts AS pb ON pc.ProductB = pb.ProductID
CROSS JOIN totaltransactions AS tt







--------------------------------------------------------------------
--------------- PRICE ANALYSIS -----------------------------------
--------------------------------------------------------------------


--- *** Profit Curve:  Unit Price x AvgQtyTransaction x TotalProfit *** ---

CREATE OR ALTER VIEW View_ProfitCurve AS 

WITH ProductPricePoints As (
    -- Step 1: Calculate the actual price paid for every line item
    SELECT
        ProductID,
        Quantity,
        ROUND(TotalPrice/ NULLIF(Quantity, 0), 1) AS ActualUnitPrice,
        TransactionNumber
    FROM fact_sales
),
DemandAnalysis AS (
    -- Step 2: Aggregate to find avg quantity per 'basket' at that price
    SELECT
        ProductID,
        ActualUnitPrice,
        COUNT(DISTINCT TransactionNumber) AS TotalTransactions,
        SUM(Quantity) AS TotalQtySold,
        ROUND(AVG(CAST(Quantity AS FLOAT)), 0) AS AvgQtyTransaction
    FROM ProductPricePoints
    GROUP BY ProductID, ActualUnitPrice
)
-- Step 3: Final output sorted to see the 'Demand Curve' per product
SELECT 
    ProductID,
    ActualUnitPrice,
    AvgQtyTransaction,
    TotalTransactions,
    TotalQtySold
FROM DemandAnalysis

GO 

SELECT *
FROM View_ProfitCurve
WHERE ProductID = 200


--- *** Price Elasticity *** ---

CREATE OR ALTER VIEW View_ProductPriceElasticity AS 

WITH LogData AS (
    -- Step 1: Log-transform the Price and Quantity
    -- Note: LOG() in most SQL dialects is the Natural Log (ln)
    SELECT 
        ProductID,
        LOG(ActualUnitPrice) AS lnP,
        LOG(AvgQtyTransaction) AS lnQ
    FROM View_ProfitCurve
    WHERE AvgQtyTransaction > 0 AND ActualUnitPrice > 0
),
RegressionComponents AS (
    -- Step 2: Calculate the components needed for the OLS formula
    SELECT 
        ProductID,
        COUNT(*) AS n,
        SUM(lnP) AS sumX,
        SUM(lnQ) AS sumY,
        SUM(lnP * lnQ) AS sumXY,
        SUM(lnP * lnP) AS sumX2
    FROM LogData
    GROUP BY ProductID
    HAVING COUNT(*) > 1 -- Need at least 2 price points to draw a line
)
-- Step 3: Apply the Slope formula to get Elasticity
SELECT 
    rc.ProductID,
    P.ProductName,
    ROUND(( (n * sumXY) - (sumX * sumY) ) / ( (n * sumX2) - (sumX * sumX) ), 2) AS Elasticity,
    CASE 
        WHEN ( (n * sumXY) - (sumX * sumY) ) / ( (n * sumX2) - (sumX * sumX) ) BETWEEN  -2 AND -1 
            THEN 'Stable Earners'
                WHEN ( (n * sumXY) - (sumX * sumY) ) / ( (n * sumX2) - (sumX * sumX) ) BETWEEN  -6 AND -2 
            THEN 'Volume Builders'
        WHEN ( (n * sumXY) - (sumX * sumY) ) / ( (n * sumX2) - (sumX * sumX) ) BETWEEN -1 AND 0 
            THEN 'Margin Protectors'
        WHEN ( (n * sumXY) - (sumX * sumY) ) / ( (n * sumX2) - (sumX * sumX) ) < -6
            THEN 'Traffic Drivers'  
        ELSE 'Check Data (Positive Elasticity)'
    END AS MarketCategory
FROM RegressionComponents AS rc
LEFT JOIN dim_Products AS p ON rc.ProductID = p.ProductID;

SELECT *
FROM View_ProductPriceElasticity
WHERE ProductID = 200


--- *** Price Sensitivy Simulation / Price Optimization Analysis *** ---

CREATE OR ALTER VIEW View_PriceOptimizationAnalysis AS

WITH PricingCalc AS (
    SELECT 
        fs.ProductID,
        p.ProductName,
        fs.UnitPrice AS CurrentPrice,
        SUM(fs.TotalPrice) AS CurrentTotalSales,
        p.UnitCost,
        SUM(Quantity) AS BaselineQuantity,
        e.Elasticity,
        e.MarketCategory,
        -- 1. Optimal Price
        ROUND(p.UnitCost / NULLIF((1 + (1.0 / NULLIF(e.Elasticity, 0))), 0), 2) AS OptimalPrice
    FROM fact_sales AS fs
    LEFT JOIN dim_products AS p ON fs.ProductID = p.ProductID
    LEFT JOIN View_ProductPriceElasticity AS e ON fs.ProductID = e.ProductID
    WHERE fs.Discount = 0 
    GROUP BY fs.ProductID, p.ProductName, fs.UnitPrice, p.UnitCost, e.Elasticity, e.MarketCategory
),
QuantityCalc AS (
    SELECT
        *,
        -- Sales Contribtion %
        ROUND(CurrentTotalSales * 100.0 / SUM(CurrentTotalSales) OVER (), 2) AS SalesContribution,
        -- Quantity Contribution %
        CAST(BaselineQuantity * 100.0 / SUM(BaselineQuantity) OVER () AS DECIMAL(10,2)) AS QuantityContribution,
        -- 2. Predicted Quantity at Optimal Price
        CAST(BaselineQuantity * (1 + Elasticity * ((OptimalPrice - CurrentPrice) / CurrentPrice)) AS INT) AS PredictedQuantity,
        -- Calculate current margin % for the break-even formula
        (CurrentPrice - UnitCost) / NULLIF(CurrentPrice, 0) AS CurrentMarginPct
    FROM PricingCalc
),
BreakEvenCalc AS (
    SELECT 
        *,
        -- 3. Required Volume Lift % to stay Profit Neutral after a price change
        -- Formula: -PriceChange / (Margin + PriceChange)
        CASE 
            WHEN OptimalPrice < CurrentPrice THEN 
                ((CurrentPrice - OptimalPrice) / CurrentPrice) / 
                NULLIF(CurrentMarginPct - ((CurrentPrice - OptimalPrice) / CurrentPrice), 0)
            ELSE 0 
        END AS RequiredProfitLiftPct
    FROM QuantityCalc
),
ProfitCalc AS (
    SELECT
        *,
        ROUND(((CurrentPrice - UnitCost) * BaselineQuantity), 2) AS CurrentProfit,
        ROUND(((OptimalPrice - UnitCost) * PredictedQuantity), 2) AS OptimalProfit
    FROM BreakEvenCalc
)
SELECT
    p.ProductID,
    psp.ProductRank,
    p.ProductName,
    p.SalesContribution,
    p.QuantityContribution,
    CurrentPrice,
    OptimalPrice,
    ROUND((OptimalPrice - CurrentPrice) / CurrentPrice * 100, 2) AS PriceChangePercent,
    BaselineQuantity,
    PredictedQuantity,
    -- Actual Lift vs Required Lift
    CAST(((PredictedQuantity - BaselineQuantity) * 1.0 / NULLIF(BaselineQuantity, 0)) * 100 AS DECIMAL(10,2)) AS PredictedLiftPct,
    ROUND(RequiredProfitLiftPct * 100, 2) AS RequiredLiftForBreakEven,
    CurrentProfit,
    OptimalProfit,
    ROUND((OptimalProfit - CurrentProfit), 2) AS ProfitUplift,
    MarketCategory,
    -- 6. Strategic Verdict
    CASE
        WHEN OptimalPrice < CurrentPrice AND (PredictedQuantity - BaselineQuantity) * 1.0 / BaselineQuantity >= RequiredProfitLiftPct THEN 'Efficient Discount'
        WHEN OptimalPrice < CurrentPrice AND (PredictedQuantity - BaselineQuantity) * 1.0 / BaselineQuantity < RequiredProfitLiftPct THEN 'Loss Leader Strategy'
        WHEN OptimalPrice > CurrentPrice THEN 'Margin Expansion'
        ELSE 'Neutral'
    END AS StrategicVerdict
FROM ProfitCalc AS p
LEFT JOIN View_ProductSalesPerformance AS psp ON p.ProductName = psp.ProductName
WHERE psp.ProductRank < 165

SELECT
    ProductName,
    SalesContribution,
    QuantityContribution,
    CurrentPrice,
    OptimalPrice,
    BaselineQuantity,
    PredictedQuantity,
    PredictedLiftPct,
    RequiredLiftForBreakEven,
    ProfitUplift,
    StrategicVerdict
FROM View_PriceOptimizationAnalysis


  

--- *** Salesperson Effectiveness *** ---

--- *** Total sales attributed to each salesperson *** ---
--- *** Identify top-performing and underperforming staff *** ---
WITH SalesSummary AS (
    SELECT 
        e.FullName,
        ROUND(SUM(s.TotalPrice), 2) AS TotalSales
    FROM dim_employees AS e
    LEFT JOIN fact_sales AS s 
        ON e.EmployeeID = s.SalespersonID
    GROUP BY e.FullName
)
SELECT
    FullName,
    TotalSales,
    ROUND(TotalSales * 100.0 / SUM(TotalSales) OVER(), 2) AS ContributionPercentage,
    RANK() OVER (ORDER BY TotalSales DESC) AS TopSalesRank
FROM SalesSummary
ORDER BY TopSalesRank;


--- *** Salestrend based on individual salesperson contribution overtime *** ---
WITH MonthlySales AS (
    SELECT 
        e.FullName,
        s.Year,
        s.Month,
        ROUND(SUM(s.TotalPrice), 2) AS TotalSales
    FROM fact_sales AS s
    LEFT JOIN dim_employees AS e 
        ON e.EmployeeID = s.SalespersonID
    GROUP BY e.FullName, s.Year, s.Month
)
SELECT
    FullName,
    Year,
    Month,
    TotalSales,
    -- Previous Month Sales
    LAG(TotalSales, 1) OVER (
        PARTITION BY FullName 
        ORDER BY Year, Month
    ) AS LastMonthSales,
    -- Month over Month Growth
    ROUND(((TotalSales - LAG(TotalSales, 1) OVER (PARTITION BY FullName ORDER BY Year, Month)) / TotalSales) * 100, 2) AS MoMGrowth
FROM MonthlySales
ORDER BY FullName, Year, Month;


--- *** Monthly Most Contributing Salesperson *** ---

WITH MonthlySales AS (
    SELECT
        FORMAT(s.SalesDate, 'yyyy-MM') AS SalesMonth,
        p.FullName,
    ROUND(SUM(TotalPrice), 2) AS MonthlyRevenue,
    -- Total Store Revenue
    SUM(SUM(s.TotalPrice)) OVER (PARTITION BY FORMAT(s.SalesDate, 'yyyy-MM')) AS TotalStoreRevenue
    FROM fact_sales s
    JOIN dim_employees p ON s.SalespersonID = p.EmployeeID
    GROUP BY FORMAT(s.SalesDate, 'yyyy-MM'), p.FullName
),
RankedSales AS (
    SELECT 
        SalesMonth,
        FullName,
        MonthlyRevenue,
        -- Previous Month Revenue
        LAG(MonthlyRevenue) OVER (PARTITION BY FullName ORDER BY SalesMonth) AS PreviousMonthRevenue,
        -- Contributing Percent
        (MonthlyRevenue / TotalStoreRevenue) * 100 AS ContributionPercentage,
        -- Performance Rank
        RANK() OVER(PARTITION BY SalesMonth ORDER BY MonthlyRevenue DESC) AS PerformanceRank
    FROM MonthlySales
)

SELECT 
    *,
    ROUND(
        ((MonthlyRevenue - PreviousMonthRevenue) / NULLIF(PreviousMonthRevenue, 0)) * 100, 2) AS  MoM_Growth_Percent
FROM RankedSales 
WHERE PerformanceRank < 4
ORDER BY SalesMonth 