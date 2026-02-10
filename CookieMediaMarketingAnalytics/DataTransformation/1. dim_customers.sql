

--- Create a view combining customers and geography

SELECT 
	c.CustomerID,
	c.CustomerName,
	c.Email,
	c.Gender,
	c.Age,
	g.Country,
	g.City
FROM customers AS c
LEFT JOIN geography AS g
ON c.GeographyID = g.GeographyID;

--- Count of customers by Region, Country
SELECT 
	Country,
	Gender,
	COUNT(*) AS PersonCount
FROM CustomerGeography
WHERE Gender IS NOT NULL
GROUP BY Country, Gender
ORDER BY Country, Gender
