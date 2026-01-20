
--- Update ContentType to be all lowercase for consistency
UPDATE engagement_data
SET ContentType = LOWER(ContentType); 
 
--- Create a cleaned version of engagement_data table with formatted date and split ViewsClicksCombined

SELECT
    EngagementID,
    ContentID,
    CampaignID,
    ProductID,
    ContentType,
    CAST (EngagementDate AS DATE) AS FormattedEngagementDate,
    CAST (Likes AS INT) AS Likes,   
    CAST (Views AS INT) AS Views,
    CAST (Clicks AS INT) AS Clicks
FROM (
SELECT 
    EngagementID,
    ContentID,
    CampaignID,
    ProductID,
    ContentType,
    EngagementDate,
    Likes,
    LEFT(ViewsClicksCombined, CHARINDEX('-', ViewsClicksCombined) - 1) AS Views,   --- Extract everything before the hyphen
    SUBSTRING(ViewsClicksCombined, CHARINDEX('-', ViewsClicksCombined) + 1, LEN(ViewsClicksCombined)) AS Clicks  --- Extract everything after the hyphen
FROM engagement_data
) AS FormattedEngagementData;



 --- ****** Checked quality issues in engagement_data table ******

--- Examine the structure of engagement_data table
sp_help engagement_data;


--- Examine the ContentType values in engagement_data table
SELECT 
    ContentType COLLATE SQL_Latin1_General_CP1_CS_AS AS ContentType,
    SUM(Likes) AS TotalLikes
FROM engagement_data
GROUP BY ContentType COLLATE SQL_Latin1_General_CP1_CS_AS;

--- Update ContentType to be all lowercase for consistency
UPDATE engagement_data
SET ContentType = LOWER(ContentType);

--- Verify the update
SELECT DISTINCT ContentType
FROM engagement_data;

--- Re-examine the ContentType values in engagement_data table after update
SELECT 
    ContentType COLLATE SQL_Latin1_General_CP1_CS_AS AS ContentType,
    SUM(Likes) AS TotalLikes
FROM engagement_data
GROUP BY ContentType COLLATE SQL_Latin1_General_CP1_CS_AS;

******