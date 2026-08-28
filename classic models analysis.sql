-- ============================================================
-- Customer segmentation by credit limit
-- Buckets customers into credit-limit tiers with CASE logic,
-- then aggregates sales value by order and tier.
-- ============================================================

with sales as (
    select t1.ordernumber, t1.customernumber, productcode, quantityOrdered, priceEach,
           priceEach * quantityOrdered as sales_value, creditLimit
    from orders t1
    inner join orderdetails t2
        on t1.ordernumber = t2.ordernumber
    inner join customers t3
        on t1.customernumber = t3.customernumber
)

select ordernumber, customernumber,
    case
        when creditlimit < 75000 then 'a:Less than $75k'
        when creditlimit between 75000 and 100000 then 'b:$75k - $100k'
        when creditlimit between 100000 and 150000 then 'c:$100k - $150k'
        when creditlimit > 150000 then 'd : Over $150k'
        else 'other'
    end as creditlimit_group,
    sum(sales_value) as sales_value
from sales
group by ordernumber, customernumber, creditlimit_group;

-- ============================================================
-- Cross-sell analysis: which product lines are bought together
-- Self-joins orders to itself to find pairs of different product
-- lines purchased within the same order.
-- ============================================================

with prod_sales as (
    select ordernumber, t1.productcode, productline
    from orderdetails t1
    inner join products t2
        on t1.productcode = t2.productcode
)

select distinct t1.ordernumber, t1.productline as product_one, t2.productline as product_two
from prod_sales t1
left join prod_sales t2
    on t1.ordernumber = t2.ordernumber
    and t1.productline <> t2.productline;

-- ============================================================
-- View: sales_data_for_power_bi
-- Purpose: Core analysis-ready view that feeds the Power BI dashboard.
-- Joins orders, order details, customers, products, employees and
-- offices into a single table with computed sales_value and
-- cost_of_sales columns.
-- ============================================================

create or replace view sales_data_for_power_bi as

select orderdate, ord.ordernumber, p.productName, p.productline, cu.customername,
       cu.country as customer_country, o.country as office_country,
       buyPrice, priceEach, quantityOrdered,
       quantityOrdered * priceEach as sales_value,
       quantityOrdered * buyPrice as cost_of_sales
from orders ord
inner join orderdetails orddet
    on ord.ordernumber = orddet.ordernumber
inner join customers cu
    on ord.customernumber = cu.customernumber
inner join products p
    on orddet.productCode = p.productCode
inner join employees emp
    on cu.salesRepEmployeeNumber = emp.employeeNumber
inner join offices o
    on emp.officeCode = o.officeCode;

select t1.orderdate,t1.ordernumber,quantityordered,priceeach,productname,productline,buyprice,city,country
from orders t1
inner join orderdetails t2
on t1.ordernumber=t2.ordernumber
inner join products t3
on t2.productcode=t3.productcode
inner join customers t4
on t1.customernumber=t4.customernumber
where year(orderdate)=2004
-- ============================================================
-- Sales by geography and product line
-- Aggregates sales value by customer location, product line and
-- office location, joining across 6 tables.
-- ============================================================

with main_cte as (
    select t1.ordernumber, t2.productcode, t2.quantityOrdered, t2.priceEach,
           quantityOrdered * priceEach as sales_value,
           t3.city as customer_city, t3.country as customer_country,
           t4.productLine,
           t6.city as office_city, t6.country as office_country
    from orders t1
    inner join orderdetails t2
        on t1.ordernumber = t2.ordernumber
    inner join customers t3
        on t1.customernumber = t3.customernumber
    inner join products t4
        on t2.productcode = t4.productcode
    inner join employees t5
        on t3.salesRepEmployeeNumber = t5.employeeNumber
    inner join offices t6
        on t5.officecode = t6.officecode
)

select ordernumber, customer_city, customer_country, productline, office_city, office_country,
       sum(sales_value) as sales_value
from main_cte
group by ordernumber, customer_city, customer_country, productline, office_city, office_country;

-- ============================================================
-- Customer purchase trend analysis
-- Uses window functions (ROW_NUMBER, LAG) to sequence each
-- customer's orders over time and measure the change in order
-- value between consecutive purchases.
-- ============================================================

with main_cte as (
    select ordernumber, orderdate, customernumber, sum(sales_value) as sales_value
    from (
        select t1.ordernumber, orderdate, customernumber, productcode,
               quantityOrdered * priceEach as sales_value
        from orders t1
        inner join orderdetails t2
            on t1.ordernumber = t2.ordernumber
    ) main
    group by ordernumber, orderdate, customernumber
),

sales_query as (
    select t1.*, customername,
           row_number() over (partition by customername order by orderdate) as purchase_number,
           lag(sales_value) over (partition by customername order by orderdate) as prev_sales_value
    from main_cte t1
    inner join customers t2
        on t1.customernumber = t2.customernumber
)

select *, sales_value - prev_sales_value as purchase_value_change
from sales_query
where prev_sales_value is not null;
