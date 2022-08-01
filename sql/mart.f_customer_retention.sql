  
 create table if not exists  mart.f_customer_retention (
   new_customers_count int,
   returning_customers_count int,
   refunded_customer_count int,
   period_name varchar(20),
   period_id int,
   item_id int, 
   new_customers_revenue int,
   returning_customers_revenue int,
   customers_refunded int 
   );
  

with order_cnt as (select 
	customer_id
	,c.week_of_year as period_id
	,count(id) as orders_cnt 
from mart.f_sales
left join mart.d_calendar c using(date_id)
group by c.week_of_year, customer_id
order by 1),
main as (
select 
	count(distinct case when oc.orders_cnt = 1 then fs.customer_id end) as new_customers_count	
	, count(distinct case when oc.orders_cnt > 1 then fs.customer_id end) as returning_customers_count
	, count(distinct case when fs.status='refunded' then fs.customer_id end) as refunded_customer_count 
	,'week' as period_name
	, cd.week_of_year as period_id
	, fs.item_id as item_id
	, sum(case when oc.orders_cnt = 1 then fs.payment_amount  end) as new_customers_revenue
	, sum(case when oc.orders_cnt > 1 then fs.payment_amount  end) as returning_customers_revenue
	, count(case when fs.status='refunded' then fs.id end) as customers_refunded 
from mart.f_sales fs
left join mart.d_calendar cd using(date_id)
left join order_cnt oc on fs.customer_id = oc.customer_id and cd.week_of_year = oc.period_id
group by cd.week_of_year, item_id)
insert into mart.f_customer_retention as f
(new_customers_count, returning_customers_count, refunded_customer_count, period_name, period_id, item_id, new_customers_revenue,returning_customers_revenue,customers_refunded)
select * from main;