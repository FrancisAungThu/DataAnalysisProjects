--- Calculate Average Time Between Purchases per Customer ---
CREATE VIEW vw_PurchaseIntervals AS
WITH Purchases AS (
    SELECT
        CustomerID,
        VisitDate,
        LAG(VisitDate) OVER (
            PARTITION BY CustomerID
            ORDER BY VisitDate
        ) AS Previous_VisitDate
    FROM customer_journey
    WHERE Action = 'Purchase'
),
PurchaseIntervalsCTE AS (
    SELECT
        CustomerID,
        DATEDIFF(day, Previous_VisitDate, VisitDate) AS Days_Between_Purchases
    FROM Purchases
    WHERE Previous_VisitDate IS NOT NULL
)
SELECT
    CustomerID,
    AVG(Days_Between_Purchases) AS Avg_Days_Between_Purchases,
    MIN(Days_Between_Purchases) AS Min_Days_Between_Purchases,
    MAX(Days_Between_Purchases) AS Max_Days_Between_Purchases
FROM PurchaseIntervalsCTE
GROUP BY CustomerID;

SELECT *
FROM vw_PurchaseIntervals;



--- Customer Metrics View ---
CREATE VIEW vw_CustomerMetrics AS 
    SELECT 
        CustomerID,
        -- 1. Total Conversions per customer
        COUNT(CASE WHEN Action = 'Purchase' THEN 1 END) AS Total_Conversions,
        
        -- 2. Drop-off Frequency (Frustration Signal)
        COUNT(CASE WHEN Action = 'Drop-off' THEN 1 END) AS Total_Drop_offs,
        
        -- 3. Calculate Time-to-Action (Days from first visit to first purchase)
        MIN(VisitDate) AS First_Interaction,
        MIN(CASE WHEN Action = 'Purchase' THEN VisitDate END) AS First_Purchase_Date,
        MAX(CASE WHEN Action = 'Purchase' THEN VisitDate END) AS Last_Purchase_Date,
        
        -- 4. Days since last activity (Recency/Churn risk)
        DATEDIFF(day, MAX(VisitDate), '2025-12-31') AS Days_Since_Last_Activity
    FROM customer_journey
    GROUP BY CustomerID

--- Customer Segmentation View ---
CREATE OR ALTER VIEW vw_CustomerSegmentation AS
SELECT 
    CM.CustomerID,
    CM.Total_Conversions,
    CM.Total_Drop_offs,
    CM.First_Purchase_Date,
    CM.First_Interaction,
    CM.Last_Purchase_Date,
    CM.Days_Since_Last_Activity,
    PI.Avg_Days_Between_Purchases,

    
    -- Calculated Column: Days to first conversion
    DATEDIFF(day, CM.First_Interaction, CM.First_Purchase_Date) AS Days_to_First_Purchase,

    -- 1. Automated Churn Risk Logic
    -- Uses personal purchase intervals when available, else defaults to 1/2 year markers
    CASE 
        WHEN CM.Days_Since_Last_Activity > ISNULL(PI.Avg_Days_Between_Purchases, 365 * 2) THEN 'Very High Churn Risk'
        WHEN CM.Days_Since_Last_Activity > ISNULL(PI.Avg_Days_Between_Purchases, 365)     THEN 'High Churn Risk'
        WHEN CM.Days_Since_Last_Activity > ISNULL(PI.Avg_Days_Between_Purchases * 0.5, 180) THEN 'Moderate Churn Risk'
        ELSE 'Healthy'
    END AS Churn_Risk,

    -- 2. Advanced Marketing Segmentation
    -- Categorizes customers by loyalty, speed of conversion, and frustration signals
    CASE 
        WHEN CM.Total_Conversions >= 2 
             AND DATEDIFF(day, CM.First_Interaction, CM.First_Purchase_Date) <= 7 THEN 'Loyal & Quick Customer'
        WHEN CM.Total_Conversions >= 2                                           THEN 'Loyal Customer'
        WHEN CM.Total_Drop_offs > 5 AND CM.Total_Conversions = 0                 THEN 'Frustrated High-Intent'
        ELSE 'Casual Browser'
    END AS Customer_Segment

FROM vw_CustomerMetrics AS CM
LEFT JOIN vw_PurchaseIntervals AS PI
    ON CM.CustomerID = PI.CustomerID;

SELECT *
FROM vw_CustomerSegmentation;


--- Create or Alter View combining customers and geography with Age Grouping ---

CREATE OR ALTER VIEW vw_CustomerGeography AS 
SELECT 
	c.CustomerID,
	c.CustomerName,
	c.Email,
	c.Gender,
	c.Age,
    --- New Age Grouping
    CASE 
    WHEN c.Age BETWEEN 18 AND 24 THEN 'Young Adult'
    WHEN c.Age BETWEEN 25 AND 34 THEN 'Emerging Professional'
    WHEN c.Age BETWEEN 35 AND 44 THEN 'Mature Adult'
    WHEN c.Age BETWEEN 45 AND 54 THEN 'Established Adult'
    WHEN c.Age BETWEEN 55 AND 64 THEN 'Pre-Retirement'
    WHEN c.Age BETWEEN 65 AND 69 THEN 'Senior'
END AS Age_Group, 
	g.Country,
    --- Market Region
    CASE 
    WHEN Country IN ('Germany', 'Austria', 'Switzerland') THEN 'DACH'
    WHEN Country IN ('Belgium', 'Netherlands') THEN 'Benelux'
    WHEN Country IN ('Italy', 'Spain') THEN 'Southern Europe'
    WHEN Country IN ('UK', 'France') THEN 'Western Europe'
    ELSE 'Other Europe'
END AS Market_Region,
	g.City
FROM customers AS c
LEFT JOIN geography AS g
ON c.GeographyID = g.GeographyID;


--- *** Customer Demographics & Geography (Marketing Analyst) *** ---
---Q1: Customer Gender Distribution
SELECT
    Gender,
    COUNT(*) AS PersonCount
FROM CustomerGeography
GROUP BY Gender


---Q2: Which countries and regions have the most customers?
SELECT 
    Market_Region,
    Country,
    COUNT(*) AS PersonCount,
    CAST(
    ROUND(
        COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 
        0)
    AS INT) AS PercentageTotal,
    DENSE_RANK() OVER ( ORDER BY COUNT(*) DESC) AS Country_Rank  ---Ranks countries by PersonCount
FROM CustomerGeography
WHERE Age_Group IS NOT NULL
GROUP BY Market_Region, Country
ORDER BY Country_Rank

---Q3: Top 3 countries by purhcase count
SELECT TOP 3
    CG.Market_Region,
    CG.Country,
    COUNT(*) AS PurchaseCount
FROM CustomerGeography AS CG
LEFT JOIN customer_journey AS CJ
ON CG.CustomerID = CJ.CustomerID
WHERE CJ.Action = 'Purchase'
GROUP BY CG.Market_Region, CG.Country
ORDER BY COUNT(*) DESC


--- *** Acquisition & Conversion (Marketing Manager)
---Q4:  Top 10 campaign IDs driving the highest quality traffic (conversion efficiency)?
---(i.e., traffic that doesn't just 'Click' but actually moves from 'Checkout' to 'Purchase' in the Journey table?)"


WITH CampaignConversions AS (
SELECT
    ED.CampaignID,
    ED.ContentType,
    COUNT(DISTINCT CJ.CustomerID) AS PurchaseCount,
    ED.Views,
    ED.Clicks,
    ED.LIKES,
    -- Purchase per view
    COUNT(DISTINCT CJ.CustomerID) * 100 / NULLIF(ED.Views, 0) AS Purchase_per_100_views
FROM vw_EngagementData AS ED
LEFT JOIN customer_journey AS CJ
    ON ED.ProductID = CJ.ProductID
    AND CJ.ACTION = 'Purchase'
WHERE  ED.CampaignID IS NOT NULL
GROUP BY ED.CampaignID, ED.ContentType, ED.LIKES, ED.Views, ED.Clicks
)

SELECT TOP 10   
    CampaignID,
    ContentType,
    PurchaseCount,
    Views,
    Clicks,
    LIKES,
    Purchase_per_100_views
FROM CampaignConversions
ORDER BY Purchase_per_100_views DESC;

--- Purchase per 100 views by content type
    WITH CampaignConversions AS (
        SELECT
            ED.CampaignID,
            ED.ContentType,
            COUNT(DISTINCT CJ.CustomerID) AS PurchaseCount,
            ED.Views
        FROM vw_EngagementData AS ED
        LEFT JOIN customer_journey AS CJ
            ON ED.ProductID = CJ.ProductID
            AND CJ.ACTION = 'Purchase'
        WHERE ED.CampaignID IS NOT NULL
        GROUP BY ED.CampaignID, ED.ContentType, ED.Views
    )

    SELECT
        ContentType,
        SUM(PurchaseCount) * 100.0 / NULLIF(SUM(Views), 0) AS Purchase_per_100_views
    FROM CampaignConversions
    GROUP BY ContentType
    ORDER BY Purchase_per_100_views DESC;


---Q5:  what is the average Days_to_First_Purchase?
SELECT 
     AVG(Days_to_First_Purchase) AS Average_Days_to_First_Purchase
FROM vw_CustomerSegmentation
WHERE Days_to_First_Purchase IS NOT NULL


--- *** Retention & Loytalty (Prodcut Manager)
--- Q6: What is the most purhcase product?
SELECT 
    P.ProductName,
    COUNT(*) AS PurchaseCount
FROM customer_journey AS CJ
LEFT JOIN dbo.products AS P
    ON CJ.ProductID = P.ProductID
WHERE CJ.Action = 'Purchase'
GROUP BY P.ProductName
ORDER BY PurchaseCount DESC

--- Q7: Loyal & Quick Customer.  What was their most common First_Purchase_Date product? Can we use that product as a 'Hero Product' to acquire more loyal users?
CREATE OR ALTER VIEW vw_HeroProducts AS
WITH ProductPurchases AS (
    SELECT 
        P.ProductID,
        P.ProductName,
        COALESCE(CJ.PurchaseCount, 0) AS PurchaseCount,
        -- Use 100.0 (decimal) to avoid integer division issues
        COALESCE(CJ.PurchaseCount, 0) * 100.0 / NULLIF(SUM(COALESCE(CJ.PurchaseCount, 0)) OVER (), 0) AS
RawContributionPct
    FROM products AS P
    LEFT JOIN ( 
        SELECT 
            CJ.ProductID,
            COUNT(*) AS PurchaseCount
        FROM vw_CustomerSegmentation AS CS
        LEFT JOIN customer_journey AS CJ
            ON CS.CustomerID = CJ.CustomerID
        WHERE CS.Customer_Segment = 'Loyal & Quick Customer'
            AND CJ.Action = 'Purchase'
        GROUP BY CJ.ProductID 
    ) AS CJ
        ON P.ProductID = CJ.ProductID
),
-- Second CTE to calculate the Cumulative total safely
CalculatedProgress AS (
    SELECT
        ProductID,
        ProductName,
        PurchaseCount,
        -- Rounding the individual contribution for the final view
        CAST(ROUND(RawContributionPct, 0) AS INT) AS ContributionPct,
        --- Rounding cumulative percentage for clarity
        CAST(SUM(RawContributionPct) OVER (ORDER BY PurchaseCount DESC ROWS UNBOUNDED PRECEDING) AS INT) AS CumulativePct       
    FROM ProductPurchases
)
-- Final SELECT to apply the Pareto logic
SELECT 
    *,
    --- Pareto Category
    CASE 
        WHEN CumulativePct <= 80 THEN 'Top 80%' -- Use 80, not 0.8, since you multiplied by 100
        ELSE 'Bottom 20%'
    END AS ParetoCategory,
    --- ABC Analysis Category
        CASE
        WHEN CumulativePct <= 70 THEN 'A'
        WHEN CumulativePct <= 90 THEN 'B'
        ELSE 'C'
    END AS ABC_Class
FROM CalculatedProgress

SELECT *
FROM vw_HeroProducts
ORDER BY PurchaseCount DESC;


---Q8: UK Top 5 selling products in cumulative sales percentage
WITH CountryProductSales AS (
    SELECT 
        CG.Country,
        P.ProductName,
        COUNT(*) AS SalesCount,
        SUM(COUNT(*)) OVER (PARTITION BY CG.Country) AS TotalCountrySales
    FROM customer_journey AS CJ
    LEFT JOIN vw_CustomerGeography AS CG
        ON CJ.CustomerID = CG.CustomerID
    LEFT JOIN products AS P
        ON CJ.ProductID = P.ProductID
    WHERE CJ.Action = 'Purchase'
    GROUP BY CG.Country, P.ProductName
),
CountryProductRanked AS (
    SELECT 
        Country,
        ProductName,
        SalesCount,
        TotalCountrySales,
        ROW_NUMBER() OVER (PARTITION BY Country ORDER BY SalesCount DESC) AS SalesRank,
        CAST((SUM(SalesCount) OVER (PARTITION BY Country ORDER BY SalesCount DESC ROWS UNBOUNDED PRECEDING) * 100.0) / NULLIF(TotalCountrySales, 0) AS INT) AS CumulativeSalesPct
    FROM CountryProductSales
)

-- Final select: top 5 products per country with cumulative percent
SELECT
    Country,
    ProductName,
    SalesCount,
    TotalCountrySales,
    SalesRank,
    CumulativeSalesPct
FROM CountryProductRanked
WHERE SalesRank <= 5 AND Country = 'UK'
ORDER BY Country, SalesRank;


--- ***Content & Engagement Strategy (Social Media/Content Manager)
---Q9: Which ContentType (e.g., Blog vs. Video) leads to the most ViewsClicksCombined for our highest-priced items (Price > £350)?"
WITH HighestPriceItems AS (
    SELECT 
        P.ProductID,
        P.ProductName,
        P.Price,
        ED.ContentType,
        ED.Views,
        ED.Clicks,
        (ED.Views + ED.Clicks) AS ViewsClicksCombined
    FROM products AS P
    LEFT JOIN vw_EngagementData AS ED
        ON P.ProductID = ED.ProductID
    WHERE P.Price > 350
)
SELECT 
    ContentType,
    SUM(Views) AS TotalViews,
    SUM(Clicks) AS TotalClicks,
    SUM(ViewsClicksCombined) AS TotalViewsClicksCombined
FROM HighestPriceItems
GROUP BY ContentType



---Q10: any correlation between customer sentiment in reviews and their average days between purchases?

SELECT 
    CR.Sentiment_Label,
    AVG(CS.Avg_Days_Between_Purchases) AS Avg_Days_Between_Purchases,
    COUNT(*) AS ReviewCount
FROM vw_CustomerSegmentation AS CS
LEFT JOIN customer_reviews_analysis3 AS CR
    ON CS.CustomerID = CR.CustomerID
WHERE CS.Avg_Days_Between_Purchases IS NOT NULL
GROUP BY CR.Sentiment_Label






--- *** Analyze total and average Duration by Action and Stage *** ---

SELECT 
	Action,
	Stage,
	SUM(Duration) AS TotalDuration,
	AVG(Duration) AS AverageDuration,
	COUNT(*) AS ActionCount
FROM customer_journey
GROUP BY Action, Stage
ORDER BY Action

SELECT 
	Stage,
	SUM(Duration) AS TotalDuration,
	AVG(Duration) AS AverageDuration,
	COUNT(*) AS ActionCount
FROM customer_journey
GROUP BY Stage

--- Analyze customer journey transitions using LEAD function
SELECT 
    CustomerID,
    VisitDate,
    Stage,
    Action,
    -- This looks at the next row for the same customer to see where they went
    LEAD(VisitDate) OVER (PARTITION BY CustomerID ORDER BY VisitDate) AS Next_VisitDate,
    LEAD(Stage) OVER (PARTITION BY CustomerID ORDER BY VisitDate) AS Next_Stage,  
    LEAD(Action) OVER (PARTITION BY CustomerID ORDER BY VisitDate) AS Next_Action
FROM customer_journey
ORDER BY CustomerID, VisitDate;




--- Drop-offs to Purchases ratio per Customer
SELECT 
    CustomerID,
    COUNT(CASE WHEN Action = 'Drop-off' THEN 1 END) AS Total_Dropoffs,
    COUNT(CASE WHEN Action = 'Purchase' THEN 1 END) AS Total_Purchases,
    CAST(COUNT(CASE WHEN Action = 'Drop-off' THEN 1 END) AS FLOAT) / 
    NULLIF(COUNT(CASE WHEN Action = 'Purchase' THEN 1 END), 0) AS Dropoffs_Per_Purchase
FROM customer_journey
GROUP BY CustomerID
ORDER BY CustomerID;

--- Calculate Success Conversion Efficiency per Customer
SELECT 
    CustomerID,
    Total_Dropoffs,
    Total_Purchases,
    -- Calculate the "SuccessConversion Efficiency"
    ROUND(
        CAST(Total_Purchases AS FLOAT) / 
        NULLIF((Total_Purchases + Total_Dropoffs), 0) * 100, 
    2) AS Success_Percentage
FROM (
    -- Subquery to get totals first for cleaner code
    SELECT 
        CustomerID,
        COUNT(CASE WHEN Action = 'Drop-off' THEN 1 END) AS Total_Dropoffs,
        COUNT(CASE WHEN Action = 'Purchase' THEN 1 END) AS Total_Purchases
    FROM customer_journey
    GROUP BY CustomerID
) AS Sub;

*****
---- Ratio Range	Segment Tag	Business Strategy
---- < 1.0	Power Shopper	Loyalty Rewards / Early Access
---- 1.0 - 3.0	Healthy Shopper	Standard Marketing Newsletters
---- > 3.0	High-Friction	Technical Audit / Retargeting Discounts
---- NULL	Inactive Lead	"Welcome Back" Incentives
******


