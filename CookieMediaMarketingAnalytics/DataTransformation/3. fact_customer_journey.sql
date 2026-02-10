--- CTE to identify and tag duplicate records in cusotmer_journeys table
	WITH TaggedDuplicates AS (
		SELECT 
			JourneyID, 
            CustomerID, 
            ProductID, 
            VisitDate, 
            Stage, 
            Action,
            ISNULL(Duration, 0) AS Duration,
			ROW_NUMBER() OVER 
			--- PARTITIION BY the columns that define a duplicate
			(PARTITION BY JourneyID, CustomerID, ProductID
			ORDER BY JourneyID) AS rn
		FROM customer_journey
	)

---  Select only the unique records (rn = 1)
	SELECT *
	FROM TaggedDuplicates
	WHERE rn = 1
	ORDER BY JourneyID





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
