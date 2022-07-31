insert into mart.d_customer (customer_id, first_name, last_name, city_id)
select customer_id, first_name, last_name, max(city_id) from staging.user_order_log
where customer_id not in (select customer_id from mart.d_customer)
group by customer_id, first_name, last_name