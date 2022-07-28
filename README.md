# Проект 2
Здравствуйте, у меня некоторые сложности с github, поэтому вынужден описывать решение здесь
--1.Создание справочника стоимости доставки в страны ----
create table shipping_country_rates(
id serial primary key,
shipping_country text,
shipping_country_base_rate numeric(14, 3)
);

insert into shipping_country_rates(shipping_country, shipping_country_base_rate)
select distinct shipping_country, shipping_country_base_rate
from shipping;

-- select * from shipping_transfer_rate;

--2. Создание справочника тарифов доставки вендора по договору shipping_agreement---
-- drop table shipping_agreement;
create table shipping_agreement(
agreementid int primary key,
agreement_number text,
agreement_rate numeric(14, 2),
agreement_commission numeric(14, 2));

insert into shipping_agreement
select cast (agreement[1] as int),
	   cast (agreement[2] as text),
	   cast (agreement[3] as numeric(14, 2)),
	   cast (agreement[4] as numeric(14, 2))
from
    (select distinct regexp_split_to_array(vendor_agreement_description, ':+') as agreement
    from shipping) as shipping;

--select count (*) , count (distinct agreementid) from shipping_agreement

--3. Создание справочника о типах доставки shipping_transfer------
-- drop table shipping_transfer cascade;
create table shipping_transfer(
id serial primary key,
transfer_type text,
transfer_model text,
shipping_transfer_rate numeric(14, 3));

insert into shipping_transfer(transfer_type, transfer_model, shipping_transfer_rate)
select cast (transfer[1] as text),
	   cast (transfer[2] as text),
	   shipping_transfer_rate
from
    (select distinct shipping_transfer_rate,
    	    regexp_split_to_array(shipping_transfer_description, ':+') as transfer
    from shipping) as shipping;

-- select transfer_type, transfer_model from shipping_transfer;

--4. Создание таблицы shipping_info----
-- drop table shipping_info;
create table shipping_info(
shippingid int8,
shipping_country_id int,
agreementid int,
transfer_type_id int,
shipping_plan_datetime timestamp,
payment_amount numeric(14, 2),
vendorid int8,
constraint first_table_fkey foreign key (shipping_country_id) references shipping_country_rates(id) ON UPDATE cascade,
constraint second_table_fkey foreign key (agreementid) references shipping_agreement(agreementid) ON UPDATE cascade,
constraint third_table_fkey foreign key (transfer_type_id) references shipping_transfer(id) ON UPDATE cascade);

insert into shipping_info
select
	s.shippingid,
	c.id shipping_country_id,
	a.agreementid,
	t.id transfer_type_id,
	s.shipping_plan_datetime,
	sum(s.payment_amount),
	s.vendorid
from shipping s
	 join shipping_country_rates c  on s.shipping_country = c.shipping_country
	 join shipping_agreement a
	 	on cast(split_part(s.vendor_agreement_description, ':', 1) as int) = a.agreementid
	 join shipping_transfer t
	 	on split_part(s.shipping_transfer_description, ':', 1) = t.transfer_type
	 		and split_part(s.shipping_transfer_description, ':', 2) = t.transfer_model
group by
	s.shippingid,
	c.id,
	a.agreementid,
	t.id,
	s.shipping_plan_datetime,
	s.vendorid

-- select * from shipping_info;

-- 5. Создание таблицы статусов о доставке shipping_status
-- drop table shipping_status;
create table shipping_status(
shippingid int8,
status text,
state text,
shipping_start_fact_datetime timestamp,
shipping_end_fact_datetime timestamp
);

insert into shipping_status
with star as
	(
	select  shippingid, state_datetime
	from shipping
	where state = 'booked'
	),
 end_ as
	(
 	select shippingid, status, state, state_datetime
	from
		(
		select shippingid, status, state, state_datetime,
			   row_number() over (partition by shippingid
			   					  order by case when state='recieved' then 1 else 2 end,
			   					  		   state_datetime desc) rn
		from shipping
		) l
	where rn=1
	)
select
	s.shippingid,
	e.status,
	e.state,
	s.state_datetime shipping_start_fact_datetime,
	case when state='recieved' then e.state_datetime else null end shipping_end_fact_datetime
from star s
	 join end_ e on s.shippingid=e.shippingid;

-- select * from shipping_status where shipping_end_fact_datetime is null
-- Создание представления shipping_datamart----
create or replace view shipping_datamart as
select
	s.shippingid,
	i.vendorid,
	t.transfer_type,
	date_part('day', age(s.shipping_end_fact_datetime, s.shipping_start_fact_datetime)) full_day_at_shipping,
	case
		when s.shipping_end_fact_datetime > i.shipping_plan_datetime then 1
		else 0
	end is_delay,
	case
		when s.status = 'finished' then 1
		else 0
	end is_shipping_finish,
	case
		when s.shipping_end_fact_datetime > i.shipping_plan_datetime
			 then date_part('day', age(s.shipping_end_fact_datetime, i.shipping_plan_datetime))
		else 0
	end delay_day_at_shipping,
	i.payment_amount,
	i.payment_amount * (cr.shipping_country_base_rate + a.agreement_rate + t.shipping_transfer_rate) vat,
	i.payment_amount * a.agreement_commission profit
from shipping_status s
	 join shipping_info i on s.shippingid=i.shippingid
	 join shipping_transfer t on i.transfer_type_id=t.id
	 join shipping_country_rates cr on i.shipping_country_id=cr.id
	 join shipping_agreement a on i.agreementid=a.agreementid

