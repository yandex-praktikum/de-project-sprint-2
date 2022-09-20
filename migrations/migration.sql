CREATE TABLE public.shipping_country_rates(
id serial,  
shipping_country text,
shipping_country_base_rate numeric(14, 3),
PRIMARY KEY  (id)); 

INSERT INTO public.shipping_country_rates
(shipping_country, shipping_country_base_rate)  
SELECT
shipping_country,
shipping_country_base_rate
FROM public.shipping
GROUP BY shipping_country,
shipping_country_base_rate;

CREATE TABLE public.shipping_agreement(
agreementid int8,  
agreement_number text,
agreement_rate numeric(14, 2),
agreement_commission numeric(14, 2), 
PRIMARY KEY  (agreementid));  

  
INSERT INTO public.shipping_agreement
(agreementid, agreement_number, agreement_rate, agreement_commission)  
SELECT
d[1]::int8 as agreementid,
d[2]::text as agreement_number,
d[3]::numeric(14, 2) as agreement_rate,
d[4]::numeric(14, 2) as agreement_commission
FROM
(SELECT
distinct regexp_split_to_array(vendor_agreement_description , E'\\:+') as d
FROM public.shipping) as q
Order by agreementid;


CREATE TABLE public.shipping_transfer(
id serial,
transfer_type text,  
transfer_model text,
shipping_transfer_rate numeric(14, 3), 
PRIMARY KEY  (id));  

  
INSERT INTO public.shipping_transfer
(transfer_type, transfer_model, shipping_transfer_rate)  
SELECT
d[1]::text as transfer_type,
d[2]::text as transfer_model,
shipping_transfer_rate
FROM
(SELECT
shipping_transfer_rate,
regexp_split_to_array(shipping_transfer_description , E'\\:+') as d
FROM public.shipping
GROUP BY shipping_transfer_rate,d) as q;


CREATE TABLE public.shipping_info(
shippingid int8,
shipping_country_id int8,  
agreementid int8,
transfer_type_id int8,
shipping_plan_datetime timestamp,
payment_amount numeric(14, 2),
vendorid int8,
PRIMARY KEY  (shippingid),
FOREIGN KEY (shipping_country_id) REFERENCES shipping_country_rates(id),
FOREIGN KEY (agreementid) REFERENCES shipping_agreement(agreementid),
FOREIGN KEY (transfer_type_id) REFERENCES shipping_transfer(id)  
);  

  
INSERT INTO public.shipping_info
(shippingid, shipping_country_id, agreementid, transfer_type_id, shipping_plan_datetime,
payment_amount, vendorid)  
SELECT
shippingid,
cr.id as shipping_country_id,
sa.agreementid as agreementid,
st.id as transfer_type_id,
shipping_plan_datetime,
payment_amount,
vendorid
FROM public.shipping s
LEFT JOIN public.shipping_country_rates cr on cr.shipping_country = s.shipping_country
LEFT JOIN public.shipping_agreement sa
on sa.agreementid::text||':'||agreement_number::text
||':'||ROUND(agreement_rate,2)::text||':'
||ROUND(agreement_commission,2)::text = s.vendor_agreement_description
LEFT JOIN public.shipping_transfer st on st.transfer_type::text||':'
||transfer_model::text = s.shipping_transfer_description
GROUP BY shippingid,
st.id ,
sa.agreementid ,
cr.id ,
shipping_plan_datetime,
payment_amount,
vendorid;


CREATE TABLE public.shipping_status(
shippingid int8,
status text,  
state text,
shipping_start_fact_datetime timestamp,
shipping_end_fact_datetime timestamp,
PRIMARY KEY  (shippingid) 
);  

  
INSERT INTO public.shipping_status
(shippingid, status, state, shipping_start_fact_datetime, shipping_end_fact_datetime)  
with Q1 as (
  select shippingid,
  status,
  state,
  state_datetime as shipping_start_fact_datetime
  from public.shipping s
  where state = 'booked'),
  Q2 as (select shippingid,
  status,
  state,
  state_datetime as shipping_end_fact_datetime
  from public.shipping s
  where state = 'recieved'),
  Q3 as (select 
distinct shippingid as shippingid,
LAST_VALUE(status) OVER (PARTITION BY shippingid ORDER BY state_datetime ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) AS status,
LAST_VALUE(state) OVER (PARTITION BY shippingid ORDER BY state_datetime ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) AS state
FROM public.shipping)
SELECT 
Q3.shippingid,
Q3.status,
Q3.state,
Q1.shipping_start_fact_datetime,
Q2.shipping_end_fact_datetime
FROM Q3
LEFT JOIN Q2 on Q2.shippingid = Q3.shippingid
LEFT JOIN Q1 on Q1.shippingid = Q3.shippingid;

CREATE OR REPLACE VIEW public.shipping_datamart AS
SELECT
si.shippingid,
vendorid,
transfer_type,
date_part('day' , shipping_end_fact_datetime - shipping_start_fact_datetime) as full_day_at_shipping,
CASE WHEN shipping_end_fact_datetime > shipping_plan_datetime THEN 1 ELSE 0 END as is_delay,
CASE WHEN status = 'finished' THEN 1 ELSE 0 END as is_shipping_finish,
CASE WHEN shipping_end_fact_datetime > shipping_plan_datetime THEN
date_part('day' , shipping_end_fact_datetime - shipping_plan_datetime) ELSE 0 END as delay_day_at_shipping,
payment_amount,
payment_amount *(shipping_country_base_rate + agreement_rate + shipping_transfer_rate) as vat,
payment_amount * agreement_commission as profit
FROM 
public.shipping_info si
LEFT JOIN public.shipping_status ss on ss.shippingid = si.shippingid
LEFT JOIN public.shipping_transfer st on si.transfer_type_id = st.id
LEFT JOIN public.shipping_country_rates scr on scr.id = si.shipping_country_id
LEFT JOIN public.shipping_agreement sa on sa.agreementid = si.agreementid;
