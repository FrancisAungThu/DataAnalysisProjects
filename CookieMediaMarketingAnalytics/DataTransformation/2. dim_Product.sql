
SELECT *
FROM products


---Category products based on their price range
SELECT
	ProductID,
	ProductName,
	Price,

	CASE 
		WHEN Price < 50 THEN 'Low'
		WHEN Price >= 50 AND Price <= 200 THEN  'Medium'
		WHEN Price > 200 THEN 'High'
		ELSE 'Uncategorized' -- Handles NULLs if they exist
	END AS PriceCategory

FROM products;


---Summarize the number of products in each price category 

WITH CategorizedProducts AS (    --- CTE to categorize products
	SELECT 
	ProductID,
	ProductName,
	Price,

	CASE 
		WHEN Price < 50 THEN 'Low'
		WHEN Price >= 50 AND Price <= 200 THEN  'Medium'
		WHEN Price > 200 THEN 'High'
		ELSE 'Uncategorized' -- Handles NULLs if they exist
	END AS PriceCategory

FROM products
)
SELECT 
	PriceCategory,
	COUNT(ProductID) AS ProductCount
FROM CategorizedProducts
GROUP BY PriceCategory