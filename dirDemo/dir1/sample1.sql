CREATE PROCEDURE SalesByCustomer
  @CustomerName nvarchar(50)
AS
SELECT c.customer_name, sum(ctr.amount) AS TotalAmount
  FROM customers c, contracts ctr
WHERE c.customer_id = ctr.customer_id
     AND c.customer_name = @CustomerName
GROUP BY c.customer_name
ORDER BY c.customer_name
GO