# Проект 2
Опишите здесь поэтапно ход решения задачи. Вы можете ориентироваться на тот план выполнения проекта, который мы предлагаем в инструкции на платформе.

## 1. Создание public.shipping_country_rates:
```
CREATE TABLE public.shipping_country(
                                shipping_country_id serial primary key ,
                                shipping_country text,
                                shipping_country_base_rate numeric(14,3)
);
insert into public.shipping_country(shipping_country, 
                                    shipping_country_base_rate)
select distinct shipping_country, 
       shipping_country_base_rate 
from public.shipping;
```


## 2. Создание public.shipping_agreement:
```
CREATE TABLE public.shipping_agreement(
                            agreementid int primary key ,
                            agreement_number text,
                            agreement_rate numeric(14,3),
                            agreement_commission numeric(14,3)
);
insert into public.shipping_agreement(agreementid, 
                                      agreement_number, 
                                      agreement_rate, 
                                      agreement_commission)
select  distinct agreement[1]::bigint, 
        agreement[2]::text, 
        agreement[3]::numeric, 
        agreement[4]::numeric
from (
        select regexp_split_to_array(vendor_agreement_description , E'\\:+') as agreement
        from public.shipping
     ) p
order by 1;
```

## 3. Создание public.shipping_transfer:
```
CREATE TABLE public.shipping_transfer (
                                        transfer_type_id serial  primary key ,
                                        transfer_type text,
                                        transfer_model text,
                                        shipping_transfer_rate  numeric(14,3)
);
insert into public.shipping_transfer(transfer_type, 
                                     transfer_model, 
                                     shipping_transfer_rate)
select transfer[1]::text, 
       transfer[2]::text, 
       shipping_transfer_rate
from (
    select distinct regexp_split_to_array(shipping_transfer_description , E'\\:+') as transfer, 
           shipping_transfer_rate
    from public.shipping
     ) p
order by 1;
```

## 4. Создание public.shipping_info:
```
CREATE TABLE public.shipping_info (
                            shippingid bigint,
                            vendorid int,
                            payment_amount numeric(14,3),
                            shipping_plan_datetime  timestamp,
                            shipping_country_id int references public.shipping_country(shipping_country_id),
                            transfer_type_id int references public.shipping_transfer(transfer_type_id),
                            agreementid int references public.shipping_agreement(agreementid)
);

insert into public.shipping_info(
                                 shippingid, 
                                 vendorid, 
                                 payment_amount, 
                                 shipping_plan_datetime, 
                                 shipping_country_id, 
                                 transfer_type_id, 
                                 agreementid)
select sh.shippingid, 
       sh.vendorid, 
       sh.payment_amount, 
       sh.shipping_plan_datetime, 
       sc.shipping_country_id, 
       st.transfer_type_id, 
       sa.agreementid
from public.shipping sh
     join public.shipping_country sc on sc.shipping_country = sh.shipping_country
     join public.shipping_transfer st on concat(st.transfer_type,':',st.transfer_model) = sh.shipping_transfer_description
     join public.shipping_agreement sa on sa.agreementid::text = (regexp_split_to_array(sh.vendor_agreement_description , E'\\:+'))[1]::text;
```

## 5. Создание public.shipping_status:
```
CREATE TABLE public.shipping_status (
                            shippingid bigint,
                            status text,
                            state text,
                            shipping_start_fact_datetime timestamp,
                            shipping_end_fact_datetime timestamp
);


insert into public.shipping_status(
                                   shippingid, 
                                   status, 
                                   state, 
                                   shipping_start_fact_datetime, 
                                   shipping_end_fact_datetime)
with max_st as (
                select st.shippingid as shippingid, 
                       sh.state      as state, 
                       sh.status     as status
                from shipping sh
                    right join (select shippingid          as shippingid, 
                                       max(state_datetime) as max_state_datetime
                                from shipping
                                group by shippingid) st on sh.shippingid = st.shippingid and sh.state_datetime = st.max_state_datetime),
     recbook as (
                select sh.shippingid                   as shippingid, 
                       sh.state_datetime               as shipping_start_fact_datetime,
                       rc.shipping_end_fact_datetime   as shipping_end_fact_datetime
                from shipping sh
                    left join (select shippingid     as shippingid, 
                                      state_datetime as shipping_end_fact_datetime
                               from shipping
                               where state = 'recieved') rc on sh.shippingid = rc.shippingid
                where sh.state = 'booked')
select ms.shippingid,
       ms.status, 
       ms.state, 
       re.shipping_start_fact_datetime, 
       re.shipping_end_fact_datetime
from max_st as ms
join recbook as re on ms.shippingid = re.shippingid;
```


## 6. Создание public.shipping_datamart:
```
CREATE TABLE public.shipping_datamart (
                                shippingid bigint,
                                vendorid bigint,
                                transfer_type text,
                                full_day_at_shipping int,
                                is_delay int,
                                is_shipping_finish int,
                                delay_day_at_shipping int,
                                payment_amount numeric(14,3),
                                vat numeric(14,3),
                                profit numeric(14,3)
);
insert into public.shipping_datamart(
                                     shippingid, 
                                     vendorid, 
                                     transfer_type, 
                                     full_day_at_shipping, 
                                     is_delay, 
                                     is_shipping_finish, 
                                     delay_day_at_shipping, 
                                     payment_amount, 
                                     vat, 
                                     profit)
select si.shippingid                                                                                        as shippingid, 
       si.vendorid                                                                                          as vendorid, 
       st.transfer_type                                                                                     as transfer_type,
       date_part('day', age(ss.shipping_end_fact_datetime,ss.shipping_start_fact_datetime))                 as full_day_at_shipping,
        CASE
         WHEN ss.shipping_end_fact_datetime > si.shipping_plan_datetime 
         THEN 1
         ELSE 0
        END                                                                                                 as is_delay,
        CASE
         WHEN status = 'finished' 
         THEN 1
         ELSE 0
        END                                                                                                 as is_shipping_finish,
        CASE
         WHEN ss.shipping_end_fact_datetime > si.shipping_plan_datetime  
         THEN date_part('day', age(ss.shipping_end_fact_datetime,si.shipping_plan_datetime))
         ELSE 0
        END                                                                                                 as delay_day_at_shipping,
        si.payment_amount,
        si.payment_amount * (sc.shipping_country_base_rate + sa.agreement_rate + st.shipping_transfer_rate) as vat,
        si.payment_amount * sa.agreement_commission                                                         as profit
from public.shipping_info si
    join public.shipping_transfer st on st.transfer_type_id = si.transfer_type_id
    join public.shipping_status ss on ss.shippingid = si.shippingid
    join public.shipping_country sc on sc.shipping_country_id = si.shipping_country_id
    join public.shipping_agreement sa on sa.agreementid = si.agreementid;
```
