insert into mart.d_city (city_id, city_name)
select city_id, city_name from staging.user_order_log
where city_id not in (select city_id from mart.d_city)
group by city_id, city_name;