--- Clean Customer Reviews Table: Trim white spaces and format ReviewDate
SELECT 
	ReviewID,
	CustomerID,
	ProductID,
	FORMAT(CONVERT(DATE, ReviewDate), 'dd.MM.yyyy') AS FormattedReviewDate,
	Rating,
	 REPLACE(		---Use nested REPLACE to handle multiple spaces
        REPLACE(
            REPLACE(LTRIM(RTRIM(ReviewText)), '  ', ' '),
        '  ', ' '),
    '  ', ' ') AS CleanedReviewText
FROM customer_reviews;